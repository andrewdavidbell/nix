{ inputs, username, ... }@flakeContext:
let
  darwinModule = { config, lib, pkgs, ... }: {
    imports = [
      inputs.nix-homebrew.darwinModules.nix-homebrew
      (import ../darwinModules/nix-homebrew.nix flakeContext)
      inputs.home-manager.darwinModules.home-manager
      inputs.self.homeConfigurations.${username}.nixosModule
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        # Back up pre-existing files that home-manager wants to manage (e.g.
        # ~/.zshrc, ~/.config/nvim*) instead of failing activation on conflict.
        home-manager.backupFileExtension = "backup";
      }
    ];
    config = {
      environment = {
        systemPackages = [
          pkgs.xld
          pkgs.utm
          pkgs.container
        ];
      };
      fonts = {
        packages = [ pkgs.meslo-lgs-nf pkgs.nerd-fonts.jetbrains-mono ];
      };
      homebrew = {
        # omlx excluded: python@3.11 bottle incompatible with macOS Tahoe's libexpat
        # (missing _XML_SetAllocTrackerActivationThreshold symbol)
        brews = [
          "nvm"
        ];
        # Note: Some casks require manual permission grants in System Settings:
        # - ghostty: Privacy & Security > App Management
        casks = [
          # 1Password is a cask (not pkgs._1password-gui): it enforces an
          # integrity check that requires running from /Applications proper,
          # which the home-manager app dir can't satisfy. The op CLI stays in
          # Nix (pkgs._1password-cli). This is the one GUI app kept as a cask.
          "1password"
          "anaconda"
          "claude"
          "comfy"
          "docker-desktop"
          "figma"
          "ghostty"
          "idrive"
          "little-snitch"
          "lm-studio"
          "logi-options+"
          "makemkv"
          "micro-snitch"
          "qlmarkdown"
          "stellarium"
          "synology-drive"
          "vlc"
        ];
        enable = true;
        # masApps omitted: the test VM has no signed-in Mac App Store account.
        # (masApps is disabled on production too — mas 7.0.0 breaks Homebrew
        # Bundle; see Andrews-MacBook-Pro-M3.nix.)
        onActivation = {
          autoUpdate = true;
          cleanup = "uninstall";
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
