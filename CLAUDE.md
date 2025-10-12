# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a nix-darwin system flake for managing macOS system configuration using Nix. The flake defines a declarative system configuration including packages, fonts, and Homebrew integration for a MacBook Pro M3.

## Key Commands

### Build and Apply Configuration
```bash
# Build the darwin configuration
sudo darwin-rebuild build --flake .

# Build and switch to the new configuration
sudo darwin-rebuild switch --flake .

# Check for configuration changes without applying
sudo darwin-rebuild check --flake .
```

### Flake Management
```bash
# Update flake inputs to latest versions
nix flake update

# Show flake information
nix flake show

# Check flake for issues
nix flake check
```

## Architecture

The system is configured through a single `flake.nix` file that:

- Uses nixpkgs-unstable as the package source
- Integrates nix-darwin for macOS system management
- Includes nix-homebrew for Homebrew package management
- Defines system packages, fonts, and configuration for hostname "Andrews-MacBook-Pro-M3"

Key configuration sections:
- `environment.systemPackages`: System-wide packages including development tools (go, neovim, uv, git) and utilities
- `fonts.packages`: Nerd fonts for terminal usage
- `nix-homebrew`: Homebrew integration with Rosetta 2 support for Apple Silicon

## Important Notes

- The flake is configured for `aarch64-darwin` (Apple Silicon)
- Unfree packages are allowed system-wide via `nixpkgs.config.allowUnfree`
- System state version is 6 (check changelog before changing)
- Experimental features "nix-command flakes" are enabled