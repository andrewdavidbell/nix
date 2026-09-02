{ inputs, username, homeDirectory, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    imports = [
      # Claude Code module transitively imports mcp + skills from the same
      # flake — no need to re-import (duplicate option declarations error).
      inputs.agentic-config.homeManagerModules.default
    ];
    config = {
      programs.agenticConfig.skills.enable = true;
      home = {
        username = lib.mkForce username;
        homeDirectory = lib.mkForce homeDirectory;
        packages = [
          pkgs.awscli2
          pkgs.google-cloud-sdk
          pkgs.jq
          pkgs.opencode
          pkgs.ruff
          # Required by nvim-treesitter's `main` branch, which compiles parsers
          # at install time via the tree-sitter CLI (unlike `master`, which
          # shipped precompiled .so files).
          pkgs.tree-sitter
          # Provides the `huggingface-cli` and `hf` binaries (Hugging Face CLI).
          pkgs.python313Packages.huggingface-hub
        ];
        stateVersion = "26.05";
        sessionPath = [
          "${homeDirectory}/.local/bin"
          "${homeDirectory}/.rd/bin"
        ];
        sessionVariables = {
          HOMEBREW_NO_ANALYTICS = 1;
          EDITOR = "nvim";
          # Opencode merges this file over ~/.config/opencode/opencode.jsonc
          # (the managed baseline). See `docs/patterns.md` — "Managed base +
          # writable local overlay". The activation script below ensures it
          # exists; it is intentionally not managed by home-manager so it
          # stays writable and off-repo.
          OPENCODE_CONFIG = "${homeDirectory}/.config/opencode/local.jsonc";

          GOROOT = "${pkgs.go}/libexec";
          GOPATH = "${toString config.home.homeDirectory}/Source/go";
        };
        activation.opencodeLocalOverlay = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          overlay="${homeDirectory}/.config/opencode/local.jsonc"
          if [ ! -e "$overlay" ]; then
            mkdir -p "$(dirname "$overlay")"
            echo '{}' > "$overlay"
          fi
        '';
      };
      xdg.configFile = {
        "nvim/init.lua".source = ../nvim/init.lua;
        "nvim/.editorconfig".source = ../nvim/.editorconfig;
        # lazy-lock.json not managed here — lazy.nvim creates it directly
        # (home-manager symlinks are read-only, but lazy needs to write updates)
        "nvim/lua".source = ../nvim/lua;
        "nvim-kickstart/init.lua".source = ../nvim-kickstart/init.lua;
        "nvim-kickstart/lua".source = ../nvim-kickstart/lua;
        "nvim-lazynvim/init.lua".source = ../nvim-lazynvim/init.lua;
        "nvim-lazynvim/lua".source = ../nvim-lazynvim/lua;
        "nvim-nvchad/init.lua".source = ../nvim-nvchad/init.lua;
        "nvim-nvchad/lua".source = ../nvim-nvchad/lua;
        # Opencode baseline rendered from Nix so the MCP fragment merges in.
        # See ../opencode/opencode-base.nix for the static provider/theme
        # config; per-machine overrides go in ~/.config/opencode/local.jsonc.
        "opencode/opencode.jsonc".text = builtins.toJSON (
          (import ../opencode/opencode-base.nix) // {
            mcp = config.programs.agenticConfig.mcp.opencodeConfig;
          }
        );
      };
      programs = {
        fzf = {
          enable = true;
        };
        ssh = {
          enable = true;
          enableDefaultConfig = false;
          includes = [
            "config.d/*"
          ];
          # Emit as a `Host *` block, rendered after the includes so host-specific
          # settings in config.d/* win (SSH uses the first value seen per option).
          settings."*" = {
            # ServerAliveCountMax defaults to 3 so disconnect will occur after 3 minutes
            ServerAliveInterval = 60;
          };
        };
        git = {
          enable = true;
          # Identity is machine-local via ~/.gitconfig.local, which may fan
          # out to further per-directory includes (see git-config(1)
          # `includeIf`).
          settings = {
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
            init = {
              defaultBranch = "main";
            };
            # Refuse to commit when no identity is configured, instead of
            # falling back to git's auto-derived `$USER@$(hostname).local`.
            # Load-bearing here: identity is routed by remote URL via
            # ~/.gitconfig.local, so `git init` with no remote yet resolves
            # no `[user]` block and would otherwise silently misattribute.
            user.useConfigOnly = true;
            # Verify SSH-signed commits; file content is machine-local,
            # like ~/.gitconfig.local. Matches the pattern in adbell.nix.
            gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
          };
          ignores = [
            ".DS_Store"
            ".vscode"
          ];
          includes = [
            { path = "~/.gitconfig.local"; }
          ];
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
        zsh = {
          enable = true;
          shellAliases = {
            ic = "cd ~/Library/Mobile\\ Documents/com~apple~CloudDocs";
            src = "cd ~/Documents/Local\\ Source";
            dps = "docker ps | grep -v \"k8s_\"";
          };
          initContent = lib.mkMerge [
            (lib.mkBefore ''
              # Set up ZSH cache directory for oh-my-zsh plugins
              export ZSH_CACHE_DIR="$HOME/.cache/zsh"
              [[ -d "$ZSH_CACHE_DIR/completions" ]] || mkdir -p "$ZSH_CACHE_DIR/completions"
            '')
            ''
              export NVM_DIR="$HOME/.nvm"
              [[ -e "''${HOMEBREW_PREFIX}/opt/nvm/nvm.sh" ]] && source "''${HOMEBREW_PREFIX}/opt/nvm/nvm.sh"

              vm() {
                select config in kickstart lazyvim nvchad
                do NVIM_APPNAME=nvim-$config nvim $@; break; done
              }
            ''
          ];
          antidote = {
            enable = true;
            plugins = [
              # Oh My Zsh
              "getantidote/use-omz"
              "ohmyzsh/ohmyzsh path:lib"
              # Plugins
              "ohmyzsh/ohmyzsh path:plugins/git"
              "ohmyzsh/ohmyzsh path:plugins/docker"
              "ohmyzsh/ohmyzsh path:plugins/docker-compose"
              "ohmyzsh/ohmyzsh path:plugins/kubectl"
              "ohmyzsh/ohmyzsh path:plugins/aws"
              "ohmyzsh/ohmyzsh path:plugins/gcloud"
              "ohmyzsh/ohmyzsh path:plugins/npm"
              "ohmyzsh/ohmyzsh path:plugins/python"
              "ohmyzsh/ohmyzsh path:plugins/uv"
              # Completions
              "zsh-users/zsh-completions kind:fpath path:src"
              # Fish-like features
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
      pkgs = import inputs.nixpkgs {
        system = "aarch64-darwin";
        config = { allowUnfree = true; };
      };
    }
  ) // { inherit nixosModule; }
)
