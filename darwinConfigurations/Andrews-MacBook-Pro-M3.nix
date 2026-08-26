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
        taps = [
          {
            name = "jundot/omlx";
            clone_target = "https://github.com/jundot/omlx";
            force_auto_update = true;
            trusted = true;
          }
        ];
        brews = [
          "nvm"
          "omlx"
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
          "hermes-desktop"
          "idrive"
          "little-snitch"
          "logi-options+"
          "makemkv"
          "micro-snitch"
          "qlmarkdown"
          "stellarium"
          "synology-drive"
          "visual-studio-code"
          # "vlc" — temporarily dropped: upstream cask uses `command_wrapper`
          # DSL method not supported by Homebrew 6.0.1, breaking `brew bundle`.
          # cleanup = "none" here so the installed app is untouched. Re-enable
          # once Homebrew ships a version that recognises the method.
        ];
        enable = true;
        # masApps disabled: Homebrew Bundle force-installs its own `mas`, and
        # mas 7.0.0 (a breaking release) is incompatible with bundle's handling
        # of already-installed apps, aborting activation. These apps are all
        # already installed and the App Store keeps them updated. Re-enable if
        # the mas/brew-bundle incompatibility is resolved; ids kept below.
        # masApps = {
        #   "1Password for Safari" = 1569813296;
        #   "AdGuard for Safari" = 1440147259;
        #   "GarageBand" = 682658836;
        #   "Hacktivate" = 6754342195;
        #   "iMovie" = 408981434;
        #   "Keynote" = 361285480;
        #   "Numbers" = 361304891;
        #   "Obsidian Web Clipper" = 6720708363;
        #   "Pages" = 361309726;
        # };
        onActivation = {
          autoUpdate = true;
          # cleanup is "none" here (the test VM uses "uninstall"): `brew bundle
          # cleanup` — used by both "uninstall" and "zap" — miscomputes the omlx
          # (custom tap) dependency closure, tries to uninstall omlx's deps
          # (python@3.11, openssl@3, ...), and brew refuses, aborting the batch
          # atomically on every activation. Prune undeclared formulae manually
          # with `brew autoremove` (which respects omlx). The VM excludes omlx,
          # so cleanup = "uninstall" works there.
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
        configurationRevision = if inputs.self ? rev then inputs.self.rev else if inputs.self ? dirtyRev then inputs.self.dirtyRev else "";
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
