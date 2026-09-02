# Nix Configuration Repository

This repository manages macOS system and user configurations using Nix flakes, nix-darwin, and home-manager.

## Repository Structure

```
.
├── flake.nix                    # Main flake definition with inputs and outputs
├── flake.lock                   # Flake lock file
├── darwinConfigurations/        # System-level configurations (per machine)
│   ├── Andrews-MacBook-Pro-M3.nix
│   ├── MacBookPro.nix           # Work machine (lean profile; OS user adbell)
│   └── Testers-Virtual-Machine.nix
├── homeConfigurations/          # User-level configurations (per user/machine)
│   ├── adbell.nix
│   ├── MacBookPro.nix           # Lean home config for the work machine
│   └── tester.nix
└── darwinModules/               # Reusable Darwin modules
    └── nix-homebrew.nix
```

## Key Patterns and Conventions

### Configuration File Structure

All configuration files follow a functional pattern:

**Darwin configurations:**
```nix
{ inputs, username, ... }@flakeContext:
let
  darwinModule = { config, lib, pkgs, ... }: {
    # Configuration here
  };
in
inputs.nix-darwin.lib.darwinSystem {
  modules = [ darwinModule ];
  system = "aarch64-darwin";
}
```

**Home configurations:**
```nix
{ inputs, username, homeDirectory, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    # Configuration here
  };
  nixosModule = { ... }: {
    home-manager.users.${username} = homeModule;
  };
in
(
  (inputs.home-manager.lib.homeManagerConfiguration {
    modules = [ homeModule ];
    pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
  }) // { inherit nixosModule; }
)
```

**Darwin modules:**
```nix
{ inputs, username, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  # Module configuration
}
```

### Integration Pattern

- Darwin configurations import home-manager configurations via `inputs.self.homeConfigurations.${username}.nixosModule`
- This creates a tight coupling where each Darwin configuration has a corresponding home configuration for its user
- The `flakeContext` pattern passes `inputs` and user-specific parameters throughout the configuration

### System Configuration

- **Architecture:** `aarch64-darwin` (Apple Silicon)
- **Darwin state version:** `6`
- **Home-manager state version:** `"26.05"`
- **Experimental features:** Flakes and nix-command are always enabled
- **Nixpkgs config:** Unfree packages are allowed (`allowUnfree = true`)

### Package Management

- **Nix packages:** Use `pkgs.*` for packages available in nixpkgs (preferred). Always check nixpkgs before reaching for a Homebrew brew.
- **Homebrew brews:** Last resort — only for CLI tools genuinely absent from nixpkgs or requiring special compilation
- **Homebrew casks:** For GUI applications, particularly those with auto-update mechanisms
- **Homebrew settings:**
  - Auto-update enabled
  - Auto-upgrade enabled
  - Cleanup differs per machine. The **test VM** uses `"uninstall"` — on each activation `brew bundle --cleanup` uninstalls **any** formula or cask not in the declared config (and not a dependency of one), keeping only the declared Brewfile and its dependency closure. **Production** uses `"none"`: `brew bundle cleanup` (used by both `"uninstall"` and `"zap"`) miscomputes the `omlx` custom-tap dependency closure, tries to remove `omlx`'s deps, and aborts every activation — so undeclared formulae are pruned manually there with `brew autoremove` (which respects `omlx`). The VM avoids this by excluding `omlx`.

### Philosophy

- Minimal tools installed natively to macOS; prefer Docker containers for development environments
- Exceptions made for small Python or TypeScript projects (tools like `uv` are configured natively)

### VS Code

VS Code is installed as the `visual-studio-code` Homebrew cask on every machine — not
via `pkgs.vscode` and not via `programs.vscode`. Extensions, `settings.json`,
keybindings, and snippets are **not** managed by home-manager; VS Code's built-in
Settings Sync (backed by the user's GitHub account) owns that state and syncs it
across machines. Editing settings via the UI therefore persists, and nothing in this
repo touches `~/Library/Application Support/Code/User/settings.json` or
`~/.vscode/extensions/`.

Why not nix: home-manager renders `settings.json` as a read-only symlink, which
conflicts with both the UI's write path and Settings Sync — both silently fight the
symlink. Settings Sync is the better fit for user preferences edited interactively;
nix is best for state you want frozen and diffed in git.

On a fresh machine, install the cask via `darwin-rebuild switch`, then sign in to
Settings Sync to pull down extensions and settings.

### Shell Environment

The following shell configuration is captured in `homeConfigurations/adbell.nix`:

- **`home.sessionPath`:** `~/.local/bin` (uv)
- **`shellAliases`:** `ic` (iCloud Drive), `ob` (Obsidian vault)
- **`initExtra`:** NVM initialisation, `vm()` neovim config selector, 1Password plugins source

### AWS CLI

`pkgs.awscli2` is installed via nix in both `adbell.nix` and `MacBookPro.nix`, but
`~/.aws/config` is deliberately **not** managed by home-manager — it is a machine-local
file, created by hand on each machine (same handling as `~/.gitconfig.local`).

The reason is that this repo is public and the SSO fields in `~/.aws/config` (AWS
account IDs, SSO start URL / instance ID) are classified by AWS as *sensitive but not
secret*. They do not grant access on their own, but publishing them lowers the recon
cost for anyone targeting the account (enumeration, phishing that name-drops the
account, cross-account policy abuse where trust is by account ID alone). Runtime SSO
state under `~/.aws/sso/cache/` and `~/.aws/cli/cache/` is also off-repo — it contains
bearer tokens and is populated by `aws sso login`.

Do not add `xdg.configFile."aws/config"` (or a rendered-template equivalent) to this
repo without first moving the account IDs and SSO start URL into an off-repo file
read at activation time. The AWS config format has no native `include` directive, so
the "managed base + writable local overlay" pattern below does not apply directly.

### Claude Code (`agentic-config`)

Claude Code is configured by the external [`agentic-config`](https://github.com/andrewdavidbell/agentic-config)
flake, imported in `homeConfigurations/adbell.nix` via
`inputs.agentic-config.homeManagerModules.default`. That module owns everything
under `~/.claude` (CLAUDE.md, skills, agents, hooks, MCP servers) plus the CLI
itself — do **not** add `programs.claude-code` settings here; change them in the
`agentic-config` repo and bump the flake input.

- **`~/.claude/settings.json` is managed** (a read-only symlink into the store).
  In-app `/model` changes therefore don't persist across sessions — the model is
  pinned in `agentic-config`. Runtime state that *does* need to be writable is
  unaffected: permission approvals live in `~/.claude/settings.local.json`
  (git-ignored — see `programs.git.ignores` in `adbell.nix`) and app state in
  `~/.claude.json`. On first activation an existing writable `settings.json` is
  moved to `settings.json.backup` via `home-manager.backupFileExtension`.
- **Commands on `$PATH`:** `claude` (Anthropic). Additional providers are
  added in `agentic-config`, not here.
- **Shared MCP servers** ship in `agentic-config`'s `data/mcp-servers.nix` —
  currently `nixos`, `context7`, `aws-documentation`, `headroom`. All run as
  direct processes (npx/uvx/local CLI), so the list is portable across
  machines. Per-machine disable via `builtins.removeAttrs` when overriding
  `programs.agenticConfig.mcp.servers`. `headroom` additionally requires the
  CLI on `$PATH` — see `docs/headroom-setup.md` for the per-machine install.
- **Machine-local MCP servers** (HTTP transport, secrets, or client-
  specific like Claude Desktop) live in `docs/mcp-manual.md` with one-time
  recipes per host. Currently: Obsidian (for Claude Code + OpenCode) and
  eBay (for Claude Desktop).
- **Skills** (bespoke and third-party) — per-harness locations and the
  clone-and-symlink pattern for third-party skills live in
  `docs/skills.md`.

### Hermes (Nous Research desktop agent)

Hermes is installed as the `hermes-desktop` Homebrew cask on
`Andrews-MacBook-Pro-M3` only — exploratory tool on the personal
machine; any paid model backend (Nous Portal, direct provider API, or
local endpoint) is billed to a personal account, so it stays off the
work profile. The cask installs `Hermes.app` to `/Applications/`; the
`hermes` CLI appears on first-app-launch or via Hermes's own installer.

Everything under `~/.hermes/` (`config.yaml`, `.env`, `auth.json`,
`SOUL.md`, `skills/`, `memories/`, `sessions/`) is **not** nix-managed.
`hermes config set` and `hermes mcp add` both write to
`~/.hermes/config.yaml`, and Hermes's config has no `include` directive,
so the "managed base + writable overlay" pattern doesn't apply. Post-
install steps (Portal OAuth, MCP-server adds mirroring
`agentic-config/data/mcp-servers.nix`, symlinking shared skills) live
in `docs/hermes-setup.md`.

No `forHermes` module in `agentic-config` yet — revisit if Hermes
earns daily-driver status. See the "Deferred" section of that doc for
what a nix module would need to solve.

### Tester Configuration

`homeConfigurations/tester.nix` is identical to `adbell.nix`. Both configurations share the same git signing setup; git identity (name and email) is externalised to `~/.gitconfig.local` on each machine.

This allows the test VM to verify the full production configuration.

### Work Machine Configuration (`MacBookPro`)

`darwinConfigurations/MacBookPro` is the work machine (hostname `MacBookPro`). Its OS
user is `adbell` — the same login as the personal M3 — but it needs its own leaner home
config rather than reusing `adbell.nix`. Because the darwin ↔ home coupling normally
resolves the home config by `${username}` (which would collide on `adbell`), this darwin
config instead imports `inputs.self.homeConfigurations.MacBookPro.nixosModule` by explicit
flake attribute. `homeConfigurations.MacBookPro` still sets `home-manager.users.adbell`, so
the OS user is unchanged; only the flake attribute name differs. This is a deliberate
deviation from the by-`${username}` pattern — keep the comment in the file explaining it.

It shares the antidote/oh-my-posh Zsh setup and the neovim config with `adbell.nix`,
but runs a **lean work profile**:
- **Plain git:** no 1Password SSH commit signing and no `allowed_signers` (identity still
  comes from `~/.gitconfig.local`).
- **No 1Password:** the SSH agent socket, `op` CLI, biometric env, and the `1password`
  antidote plugin/cask are all dropped.
- **Dropped personal bits:** FluxCD credential refs, the personal `ob` (Obsidian vault)
  alias, and the M3-only system packages (xld/utm/container). The `ic` (iCloud Drive)
  and `src` aliases, the `nvm` init, and the neovim `vm()` switcher are kept.
- **Homebrew** mirrors the M3's handling: the `jundot/omlx` tap plus `nvm`/`omlx` brews (neither
  is in nixpkgs) and `cleanup = "none"` for the same omlx dependency-closure reason.

### Standard Configurations

All configurations include:
- nix-homebrew integration for Homebrew management
- home-manager integration for user configuration
- Touch ID for sudo authentication
- 24-hour clock format
- Trackpad tap-to-click and three-finger drag enabled

## Adding New Configurations

### Adding a New Machine

1. Create a new file in `darwinConfigurations/` named after the machine (e.g., `New-Machine-Name.nix`)
2. Copy the structure from an existing darwin configuration
3. Customise the packages, Homebrew formulae/casks, and system settings
4. Add the configuration to `flake.nix`:
```nix
darwinConfigurations = {
  # ... existing configs
  New-Machine-Name = import ./darwinConfigurations/New-Machine-Name.nix
    (flakeContext // { username = "yourusername"; });
};
```

### Adding a New User

1. Create a new file in `homeConfigurations/` named after the user (e.g., `newuser.nix`)
2. Copy the structure from an existing home configuration
3. Customise the packages, programs, and user settings
4. Update user-specific values (email, username, etc.)
5. Add the configuration to `flake.nix`:
```nix
homeConfigurations = {
  # ... existing configs
  newuser = import ./homeConfigurations/newuser.nix
    (flakeContext // { username = "newuser"; homeDirectory = "/Users/newuser"; });
};
```

### Adding a New Darwin Module

1. Create a new file in `darwinModules/` with a descriptive name
2. Follow the module pattern shown in `nix-homebrew.nix`
3. Import the module in relevant darwin configurations:
```nix
imports = [
  # ... other imports
  (import ../darwinModules/your-module.nix flakeContext)
];
```

## Common Workflows

### Building and Activating Configurations

```bash
# Build darwin configuration (no root needed)
darwin-rebuild build --flake .#Andrews-MacBook-Pro-M3

# Activate darwin configuration (system-wide changes) — must run as root
sudo --set-home darwin-rebuild switch --flake .#Andrews-MacBook-Pro-M3
```

`darwin-rebuild switch` must be run as root. The `--set-home` flag sets `$HOME` to
root's home (`/var/root`) so the root-run activation doesn't leave root-owned files
(nix caches, state) in the invoking user's home directory; home-manager itself
resolves each user's home from `home.homeDirectory` in the config, not from `$HOME`,
so it targets the correct user with or without the flag. Home-manager is applied as
part of `darwin-rebuild` — the standalone `home-manager` CLI is not installed, so
there is no separate `home-manager switch`.

### Updating Dependencies

```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
```

### Testing Changes

Use the test configurations (`Testers-Virtual-Machine` and `tester`) to verify changes before applying to production. The tester configuration is identical to production (see Tester Configuration above).

```bash
# Build and activate on the test VM (home-manager is included via darwin-rebuild)
sudo --set-home darwin-rebuild switch --flake .#Testers-Virtual-Machine
```

## Patterns

Structural recipes for how config is arranged in this repo (as
opposed to how to debug it). See `docs/patterns.md`.

- **Managed base + writable local overlay** — pattern for tools where
  home-manager owns the shared baseline but you also need a writable
  local override slot (`~/.config/*` symlinks are read-only). Applied
  to opencode via `OPENCODE_CONFIG` pointing at
  `~/.config/opencode/local.jsonc`, activation-script-initialised to
  `{}`. Also natively used by Claude Code (`settings.json` managed,
  `settings.local.json` writable) and git identity (`~/.gitconfig.local`
  via `programs.git.includes`). Use this shape before adding a new
  tool's config to `xdg.configFile`.

## Troubleshooting

See `docs/troubleshooting.md` for the human-facing walkthroughs; the section below is the quick reference for Claude.

### `brew bundle` fails during `darwin-rebuild switch` → activation halts, symlinks don't flip

**Symptom:** The `darwin-rebuild switch` output finishes with something like:

```
Error: Cask '<name>' definition is invalid: undefined method '<x>' for Cask '<name>'
`brew bundle` failed! Failed to fetch <casks…>
```

Home-manager runs *after* the Homebrew bundle step in nix-darwin's activation, so a `brew bundle` failure aborts the whole activation before home-manager symlinks are updated. Repo edits in `homeConfigurations/`, `nvim/`, etc. therefore appear "not applied" even though the build succeeded.

**Diagnosis:** `undefined method '<x>' for Cask` means the upstream tap ships a cask that uses a Cask DSL feature newer than the installed Homebrew. The tap tracks HEAD and can pull ahead of shipped Homebrew releases.

**Fix (in order):**

1. `brew update && brew --version`. If a newer Homebrew has landed since the last attempt, retry `switch`.
2. Otherwise, comment out the offending cask in the affected `darwinConfigurations/<host>.nix`. Add a comment naming the failed method and the date, so future-you knows why it's disabled and when to try re-enabling.
3. Re-run `sudo --set-home darwin-rebuild switch --flake .#<host>`.
4. Verify a home-manager symlink flipped, e.g. `readlink ~/.config/nvim/lua` — the `/nix/store/<hash>-home-manager-files/...` prefix should differ from before.
5. Re-enable the cask once Homebrew ships a version that recognises the method (`brew info --cask <name>` should stop erroring).

**Cleanup-mode safety:** Dropping a cask from the declared list is safe on `Andrews-MacBook-Pro-M3.nix` and `MacBookPro.nix` (both `cleanup = "none"` — the installed app stays put). Do **not** use this workaround on `Testers-Virtual-Machine.nix` (`cleanup = "uninstall"` would remove the app on next activation).

### `brew bundle` fails with "circular dependency" → activation halts, symlinks don't flip

**Symptom:** `darwin-rebuild switch` finishes with:

```
Error: Formulae dependency graph sorting failed (likely due to a circular dependency):
<pair-A>: [... <pair-B> ...]
<pair-B>: [... <pair-A> ...]
```

Same downstream consequence as the cask DSL failure above — home-manager symlinks don't flip.

**Diagnosis:** Two installed formulae list each other in their local `INSTALL_RECEIPT.json` `runtime_dependencies`, usually after a `brew update` pulled one to a version whose dep list crosses over the other. On `cleanup = "none"` machines the cycle often persists because a **stale explicit install** — a formula removed from `brews = [...]` but never `brew uninstall`ed — keeps the cycled pair in the closure. `brew autoremove` will not clean stale roots whose receipts show `installed_on_request: true`.

Homebrew's own diagnostic commands (`brew uses`, `brew leaves`) currently 404 on macOS 26 Tahoe (`packages.dunno_tahoe.jws.json` doesn't exist yet), so fall back to parsing `/opt/homebrew/Cellar/*/*/INSTALL_RECEIPT.json` locally — full recipe in `docs/troubleshooting.md`.

**Fix (in order):**

1. Break the cycle exactly as Homebrew suggests: `brew update && brew uninstall --ignore-dependencies --force <pair-A> <pair-B> && brew install <pair-A> <pair-B>`.
2. If diagnosis found a stale root (declared nowhere in `brews`, `installed_on_request: true`): `brew uninstall <stale-root>` then `brew autoremove` to reap the subtree.
3. Retry `sudo --set-home darwin-rebuild switch --flake .#<host>` and verify a home-manager symlink flipped.

**Prevention:** on `cleanup = "none"` machines, when removing a brew from `brews = [...]`, `brew uninstall <name>` on that machine in the same commit — otherwise the formula and its dep closure survive indefinitely. The test VM's `cleanup = "uninstall"` masks this class of failure, so don't treat a green VM activation as a signal.

## Important Constraints

- **Architecture:** All configurations target `aarch64-darwin` (Apple Silicon Macs)
- **Git signing:** Configured to use 1Password SSH signing for git commits. The signer binary is `op-ssh-sign` from the **1Password Homebrew cask** at `/Applications/1Password.app` — 1Password is the one GUI app kept as a cask rather than nixpkgs, because its integrity check requires running from `/Applications` proper (the `op` CLI stays in Nix via `pkgs._1password-cli`). `programs.git.signing.key` is `null`, so the signing key is supplied via `~/.gitconfig.local` (below).
- **Git identity:** Name, email, and signing key are intentionally absent from the repo. They live in `~/.gitconfig.local` on the machine, included via `programs.git.includes`. Create this file on any new machine:
  ```ini
  [user]
      name = Your Name
      email = you@example.com
      signingkey = ssh-ed25519 AAAA...
  ```
- **Git signature verification:** `gpg.ssh.allowedSignersFile` points at `~/.config/git/allowed_signers` (path declared in the repo; content is machine-local identity, like `~/.gitconfig.local`). Create this file on any new machine so `git log --show-signature` can verify commits:
  ```text
  you@example.com namespaces="git" ssh-ed25519 AAAA...
  ```
- **Editor:** Neovim is set as the default editor
- **Shell:** Zsh with oh-my-posh (powerlevel10k_rainbow theme) and antidote plugin manager

## Modification Guidelines

When modifying this repository:

1. **Maintain consistency:** Keep the functional pattern and structure across all configuration files
2. **Test first:** Use test configurations for experimental changes
3. **Update both:** When changing system packages, consider if user packages also need updating
4. **Document changes:** Update this file if you add new patterns or conventions
5. **Preserve integration:** Maintain the darwin ↔ home-manager integration pattern
6. **Keep organised:** Put shared configuration in modules, machine-specific config in darwinConfigurations, user-specific config in homeConfigurations
7. **Sync darwin configurations:** Changes to the production darwin configuration should be applied to both `Andrews-MacBook-Pro-M3.nix` and `Testers-Virtual-Machine.nix` (the test VM verifies production) unless there is a specific reason to differ — document any intentional differences with comments. `MacBookPro.nix` is a deliberately leaner work-machine profile and is **not** a sync target; only apply shared changes to it where they fit the lean profile.

## Technologies Used

- **Nix flakes:** Reproducible configuration management
- **nix-darwin:** macOS system-level configuration
- **home-manager:** User-level dotfiles and configuration
- **nix-homebrew:** Declarative Homebrew package management
- **nixpkgs 26.05:** Stable package versions from Nix package collection (darwin channel)
