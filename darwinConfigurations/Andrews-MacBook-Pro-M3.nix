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
        taps = [
          {
            name = "jundot/omlx";
            clone_target = "https://github.com/jundot/omlx";
            force_auto_update = true;
          }
        ];
        brews = [
          "nvm"
          "omlx"
        ];
        casks = [
          "anaconda"
          "claude"
          "claude-code"
          "comfyui"
          "docker-desktop"
          "figma"
          "ghostty"
          "idrive"
          "little-snitch"
          "lm-studio"
          "logi-options+"
          "makemkv"
          "micro-snitch"
          "stellarium"
          "synology-drive"
          "vlc"
        ];
        enable = true;
        # masApps requires Mac App Store sign-in — uncomment after signing in
        # masApps = {
        #   "1Password for Safari" = 1569813296;
        #   "AdGuard for Safari" = 1440147259;
        # };
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
