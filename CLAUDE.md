# Nix Configuration Repository

This repository manages macOS system and user configurations using Nix flakes, nix-darwin, and home-manager.

## Repository Structure

```
.
├── flake.nix                    # Main flake definition with inputs and outputs
├── flake.lock                   # Flake lock file
├── darwinConfigurations/        # System-level configurations (per machine)
│   ├── Andrews-MacBook-Pro-M3.nix
│   └── Testers-Virtual-Machine.nix
├── homeConfigurations/          # User-level configurations (per user)
│   ├── adbell.nix
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
  - Cleanup set to `"uninstall"` — removes brews not declared in config on each activation (casks are left untouched)

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

- **`home.sessionPath`:** `~/.local/bin` (uv) and `~/.cache/lm-studio/bin`
- **`shellAliases`:** `ic` (iCloud Drive), `ob` (Obsidian vault)
- **`initExtra`:** NVM initialisation, `vm()` neovim config selector, 1Password plugins source

### Tester Configuration

`homeConfigurations/tester.nix` is identical to `adbell.nix`. Both configurations share the same git signing setup; git identity (name and email) is externalised to `~/.gitconfig.local` on each machine.

This allows the test VM to verify the full production configuration.

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

`darwin-rebuild switch` must be run as root. `sudo --set-home` preserves the user's
home directory environment so the integrated home-manager activation resolves the
correct paths. Home-manager is applied as part of `darwin-rebuild` — the standalone
`home-manager` CLI is not installed, so there is no separate `home-manager switch`.

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

## Important Constraints

- **Architecture:** All configurations target `aarch64-darwin` (Apple Silicon Macs)
- **Git signing:** Configured to use 1Password SSH signing for git commits. The signer binary is the nix-store `op-ssh-sign` from `pkgs._1password-gui`; `programs.git.signing.key` is `null`, so the signing key is supplied via `~/.gitconfig.local` (below).
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
7. **Sync darwin configurations:** All changes to darwin configurations should be applied to both `Andrews-MacBook-Pro-M3.nix` and `Testers-Virtual-Machine.nix` unless there is a specific reason to differ (document any intentional differences with comments)

## Technologies Used

- **Nix flakes:** Reproducible configuration management
- **nix-darwin:** macOS system-level configuration
- **home-manager:** User-level dotfiles and configuration
- **nix-homebrew:** Declarative Homebrew package management
- **nixpkgs 26.05:** Stable package versions from Nix package collection (darwin channel)
