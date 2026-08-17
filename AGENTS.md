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

### VSCode Extensions

Extensions are managed in `homeConfigurations/` via `programs.vscode.profiles.default.extensions`. Two sources are used:

- **nixpkgs** (`pkgs.vscode-extensions.*`): preferred — version is managed by the nixpkgs channel
- **Marketplace** (`pkgs.vscode-utils.buildVscodeMarketplaceExtension`): for extensions absent from nixpkgs, pinned to a specific version with a hash inside `mktplcRef`

To update a marketplace extension, bump the `version` field and re-fetch the hash:
```bash
# For platform-independent extensions:
nix-prefetch-url --unpack "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<name>/<version>/vspackage"

# For darwin-arm64 specific extensions:
nix-prefetch-url --unpack "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/<publisher>/vsextensions/<name>/<version>/vspackage?targetPlatform=darwin-arm64"

# Convert to SRI format:
nix hash convert --to sri --type sha256 <hash>
```

### Shell Environment

The following shell configuration is captured in `homeConfigurations/adbell.nix`:

- **`home.sessionPath`:** `~/.local/bin` (uv)
- **`shellAliases`:** `ic` (iCloud Drive), `ob` (Obsidian vault)
- **`initExtra`:** NVM initialisation, `vm()` neovim config selector, 1Password plugins source

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

It shares the antidote/oh-my-posh Zsh setup, the neovim config, and the full VS Code config
with `adbell.nix`, but runs a **lean work profile**:
- **Plain git:** no 1Password SSH commit signing and no `allowed_signers` (identity still
  comes from `~/.gitconfig.local`).
- **No 1Password:** the SSH agent socket, `op` CLI, biometric env, and the `1password`
  antidote plugin/cask are all dropped.
- **Dropped personal bits:** FluxCD credential refs, personal aliases (`ic`/`ob`/`src`), and
  the M3-only system packages (xld/utm/container). The `nvm` init and neovim `vm()` switcher
  are kept.
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
