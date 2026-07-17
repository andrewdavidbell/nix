{ inputs, username, ... }@flakeContext:
let
  darwinModule = { config, lib, pkgs, ... }: {
    imports = [
      inputs.nix-homebrew.darwinModules.nix-homebrew
      (import ../darwinModules/nix-homebrew.nix flakeContext)
      inputs.home-manager.darwinModules.home-manager
      # Imported by explicit flake attribute ("MacBookPro") rather than by
      # ${username}: the OS user here is "adbell" (same as the personal M3), but
      # this machine needs its own lean home configuration, not adbell.nix.
      inputs.self.homeConfigurations.MacBookPro.nixosModule
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        # Back up pre-existing files that home-manager wants to manage (e.g.
        # ~/.zshrc, ~/.config/nvim*) instead of failing activation on conflict.
        home-manager.backupFileExtension = "backup";
      }
    ];
    config = {
      fonts = {
        packages = [ pkgs.meslo-lgs-nf pkgs.nerd-fonts.jetbrains-mono ];
      };
      homebrew = {
        taps = [
          {
            name = "jundot/omlx";
            clone_target = "https://github.com/jundot/omlx";
            force_auto_update = true;
            trusted = true;
          }
        ];
        # nvm and omlx are not in nixpkgs, so they stay on Homebrew (matching
        # Andrews-MacBook-Pro-M3).
        brews = [
          "nvm"
          "omlx"
        ];
        # Note: Some casks require manual permission grants in System Settings:
        # - ghostty: Privacy & Security > App Management
        casks = [
          "ghostty"
          "google-chrome"
          "logi-options+"
          "obsidian"
          "slack"
          "zoom"
        ];
        enable = true;
        onActivation = {
          autoUpdate = true;
          # cleanup is "none" (as on Andrews-MacBook-Pro-M3, not the test VM's
          # "uninstall"): `brew bundle cleanup` miscomputes the omlx (custom tap)
          # dependency closure, tries to uninstall omlx's deps, and brew refuses,
          # aborting every activation. Prune undeclared formulae manually with
          # `brew autoremove` (which respects omlx).
          cleanup = "none";
          upgrade = true;
        };
      };
      nix = {
        settings = { experimental-features = "nix-command flakes"; };
      };
      nixpkgs = {
        config = { allowUnfree = true; };
      };
      security = {
        pam = {
          services = {
            sudo_local = {
              touchIdAuth = true;
            };
          };
        };
      };
      system = {
        configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;
        defaults = {
          menuExtraClock = {
            Show24Hour = true;
          };
          trackpad = {
            Clicking = true;
            TrackpadThreeFingerDrag = true;
          };
        };
        primaryUser = username;
        stateVersion = 6;
      };
    };
  };
in
inputs.nix-darwin.lib.darwinSystem {
  modules = [
    darwinModule
  ];
  system = "aarch64-darwin";
}
