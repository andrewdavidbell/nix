# Nix Configuration Repository

This repository manages macOS system and user configurations using Nix flakes, nix-darwin, and home-manager.

## Repository Structure

```
.
├── flake.nix                    # Main flake definition with inputs and outputs
├── flake.lock                   # Flake lock file
├── darwinConfigurations/        # System-level configurations (per machine)
│   ├── Andrews-MacBook-Pro-M3.nix
│   └── Tests-Virtual-Machine.nix
├── homeConfigurations/          # User-level configurations (per user)
│   ├── adbell.nix
│   └── testaccount.nix
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
- **Home-manager state version:** `"25.05"`
- **Experimental features:** Flakes and nix-command are always enabled
- **Nixpkgs config:** Unfree packages are allowed (`allowUnfree = true`)

### Package Management

- **Nix packages:** Use `pkgs.*` for packages available in nixpkgs (preferred)
- **Homebrew brews:** For CLI tools not in nixpkgs or requiring special compilation
- **Homebrew casks:** For GUI applications, particularly those with auto-update mechanisms
- **Homebrew settings:**
  - Auto-update enabled
  - Auto-upgrade enabled
  - Cleanup set to `"none"` to preserve manually installed packages

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
# Build darwin configuration
darwin-rebuild build --flake .#Andrews-MacBook-Pro-M3

# Activate darwin configuration (system-wide changes)
darwin-rebuild switch --flake .#Andrews-MacBook-Pro-M3

# Build home-manager configuration
home-manager build --flake .#adbell

# Activate home-manager configuration (user changes)
home-manager switch --flake .#adbell
```

### Updating Dependencies

```bash
# Update all flake inputs
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs
```

### Testing Changes

Use the test configurations (`Tests-Virtual-Machine` and `testaccount`) for experimental changes before applying to production configurations.

## Important Constraints

- **Architecture:** All configurations target `aarch64-darwin` (Apple Silicon Macs)
- **Git signing:** Configured to use 1Password SSH signing for git commits
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

## Technologies Used

- **Nix flakes:** Reproducible configuration management
- **nix-darwin:** macOS system-level configuration
- **home-manager:** User-level dotfiles and configuration
- **nix-homebrew:** Declarative Homebrew package management
- **nixpkgs-unstable:** Latest package versions from Nix package collection
