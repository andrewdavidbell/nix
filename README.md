# nix

Declarative macOS system and user configuration using Nix flakes, nix-darwin, and home-manager.

## Overview

This repository captures the full configuration of an Apple Silicon Mac, including:

- System-level settings via **nix-darwin**
- User dotfiles, packages, and programs via **home-manager**
- Homebrew casks and formulae via **nix-homebrew**
- VSCode settings and extensions

A separate test configuration (`Testers-Virtual-Machine` / `tester`) mirrors the production setup and is used to verify changes before applying them to the main machine.

## Prerequisites

- [Nix](https://nixos.org/download/) with flakes enabled
- [nix-darwin](https://github.com/nix-darwin/nix-darwin)
- [Homebrew](https://brew.sh/) (managed by nix-homebrew after initial install)

## Repository Structure

```
.
├── flake.nix                          # Flake inputs and outputs
├── flake.lock                         # Pinned dependency versions
├── darwinConfigurations/              # System-level config (per machine)
│   ├── Andrews-MacBook-Pro-M3.nix
│   └── Testers-Virtual-Machine.nix
├── homeConfigurations/                # User-level config (per user)
│   ├── adbell.nix
│   └── tester.nix
└── darwinModules/                     # Reusable Darwin modules
    └── nix-homebrew.nix
```

## Usage

### Apply system configuration

```bash
darwin-rebuild switch --flake .#Andrews-MacBook-Pro-M3
```

### Apply user configuration

```bash
home-manager switch --flake .#adbell
```

### Apply test VM configuration

```bash
darwin-rebuild switch --flake .#Testers-Virtual-Machine
home-manager switch --flake .#tester
```

### Update all flake inputs

```bash
nix flake update
```

## Adding a New Machine

1. Create `darwinConfigurations/<Machine-Name>.nix`, using an existing config as a template
2. Create `homeConfigurations/<username>.nix` for the machine's user
3. Register both in `flake.nix`:

```nix
darwinConfigurations = {
  <Machine-Name> = import ./darwinConfigurations/<Machine-Name>.nix
    (flakeContext // { username = "<username>"; });
};

homeConfigurations = {
  <username> = import ./homeConfigurations/<username>.nix
    (flakeContext // { username = "<username>"; homeDirectory = "/Users/<username>"; });
};
```

## Notes

- All configurations target `aarch64-darwin` (Apple Silicon)
- Nix packages are preferred over Homebrew brews; brews are used only when a package is unavailable in nixpkgs
- Homebrew cleanup is set to `"uninstall"` — brews not declared in the config are removed on activation
- Git commits are signed via SSH using 1Password — ensure 1Password is unlocked when committing
- VSCode extensions are managed by Nix; marketplace extensions are pinned by version and SHA256 hash
