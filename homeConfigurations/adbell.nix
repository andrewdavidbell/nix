{ inputs, username, homeDirectory, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    config = {
      home = {
        username = lib.mkForce username;
        homeDirectory = lib.mkForce homeDirectory;
        packages = [
          pkgs.ansible
          pkgs.fluxcd
          pkgs.jq
          pkgs.k3d
          pkgs.pwgen
          pkgs.discord
          pkgs.google-cloud-sdk
          pkgs._1password-gui
          pkgs._1password-cli
          pkgs.awscli2
        ];
        stateVersion = "25.05";
      };
      programs = {
        fzf = {
          enable = true;
        };
        git = {
          enable = true;
          extraConfig = {
            core = {
              pager = "less -r";
            };
            pull = {
              rebase = true;
            };
            fetch = {
              prune = true;
            };
            diff = {
              colorMoved = "zebra";
            };
            rebase = {
              autoStash = true;
              autoSquash = true;
            };
          };
          ignores = [
            ".DS_Store"
            ".vscode"
            "**/.claude/settings.local.json"
          ];
          signing = {
            format = "ssh";
            key = null;
            signByDefault = true;
            signer = "/Applications/Nix apps/1Password.app/Contents/MacOS/op-ssh-sign";
          };
          userEmail = "8567862+andrewdavidbell@users.noreply.github.com";
          userName = "Andrew Bell";
        };
        go = {
          enable = true;
        };
        neovim = {
          defaultEditor = true;
          enable = true;
          viAlias = true;
          vimAlias = true;
        };
        obsidian = {
          enable = true;
        };
        oh-my-posh = {
          enable = true;
          enableZshIntegration = true;
          useTheme = "powerlevel10k_rainbow";
        };
        ripgrep = {
          enable = true;
        };
        uv = {
          enable = true;
        };
        vscode = {
          enable = true;
        };
        zsh = {
          enable = true;
          antidote = {
            enable = true;
            plugins = [
              "ohmyzsh/ohmyzsh path:plugins/1password"
              "ohmyzsh/ohmyzsh path:plugins/git"
              "ohmyzsh/ohmyzsh path:plugins/docker"
              "ohmyzsh/ohmyzsh path:plugins/docker-compose"
              "ohmyzsh/ohmyzsh path:plugins/kubectl"
              "ohmyzsh/ohmyzsh path:plugins/aws"
              "ohmyzsh/ohmyzsh path:plugins/gcloud"
              "ohmyzsh/ohmyzsh path:plugins/npm"
              "ohmyzsh/ohmyzsh path:plugins/python"
              "ohmyzsh/ohmyzsh path:plugins/uv"
              "zsh-users/zsh-completions kind:fpath path:src"
              "zdharma-continuum/fast-syntax-highlighting kind:defer"
              "zsh-users/zsh-autosuggestions"
              "zsh-users/zsh-history-substring-search"
            ];
            useFriendlyNames = true;
          };
        };
      };
    };
  };
  nixosModule = { ... }: {
    home-manager.users.${username} = homeModule;
  };
in
(
  (
    inputs.home-manager.lib.homeManagerConfiguration {
      modules = [
        homeModule
      ];
      pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
    }
  ) // { inherit nixosModule; }
)
