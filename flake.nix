{
  description = "nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, nix-homebrew }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = with pkgs; [
          ansible
          antidote
          #          awscli2
          fluxcd
          fzf
          git
          go
          jq
          k3d
          neovim
          oh-my-posh
          opencode
          pwgen
          ripgrep
          uv

          # Homebrew Casks
          _1password-gui
          _1password-cli
          container
          discord
          ghostty-bin
          google-cloud-sdk
          obsidian
          utm
          vscode
          xld
        ];

      # Make Zsh script and themes available
      environment.etc."antidote".source = "${pkgs.antidote}";
      environment.etc."oh-my-posh".source = "${pkgs.oh-my-posh}";

      # Allow system-wide unfree packages
      nixpkgs.config.allowUnfree = true;

      fonts.packages = [
          pkgs.meslo-lgs-nf
          pkgs.nerd-fonts.jetbrains-mono
        ];

        #      homebrew = {
        #        enable = true;
        #        casks = [
        #          "name"
        #        ];
        #        masApps = {
        #          "name" = 123345
        #        };
        #        onActivation.cleanup = "none";
        #        onActivation.autoUpdate = true;
        #        onActivation.upgrade = true;
        #      };

        #      system.defaults = {
        #};

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .
    darwinConfigurations."Andrews-MacBook-Pro-M3" = nix-darwin.lib.darwinSystem {
      modules = [
        configuration
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            # Install Homebrew under the default prefix
            enable = true;

            # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
            enableRosetta = true;

            # User owning the Homebrew prefix
            user = "adbell";

            # Automatically migrate existing Homebrew installations
            autoMigrate = true;
          };
        }
      ];
    };
  };
}
