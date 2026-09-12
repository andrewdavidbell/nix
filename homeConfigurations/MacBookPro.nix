{ inputs, username, homeDirectory, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    imports = [
      # Neutral entrypoint: pulls in the shared MCP + skills modules and every
      # agent module. Nothing is wired until an agent is enabled below.
      inputs.agentic-config.homeManagerModules.default
    ];
    config = {
      programs.agenticConfig.skills.enable = true;
      # Agent config (MCP servers, skills, subagents, baseline files) is owned
      # by the agentic-config flake; this repo only declares which agents the
      # machine runs. Agent *packages* stay in home.packages below.
      programs.agenticConfig.agents.claude.enable = true;
      programs.agenticConfig.agents.opencode.enable = true;
      # Kiro is the `kiro` cask in darwinConfigurations/MacBookPro.nix. It is
      # AWS-account-backed, so it stays off the personal M3 and the test VM.
      # Note agentic-config cannot assert the cask is present -- enabling this
      # without the cask just lays down config nothing reads.
      programs.agenticConfig.agents.kiro.enable = true;
      home = {
        username = lib.mkForce username;
        homeDirectory = lib.mkForce homeDirectory;
        packages = [
          pkgs.awscli2
          pkgs.google-cloud-sdk
          pkgs.jq
          pkgs.llmfit
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
        };
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
          # Matches adbell.nix — see the rationale there. Replaces the former
          # GOROOT/GOPATH entries in home.sessionVariables: GOROOT pointed at
          # ${pkgs.go}/libexec, which nixpkgs does not create (the real root is
          # ${pkgs.go}/share/go), and GOPATH pointed at ~/Source/go, a third
          # location that matched neither machine. Set via programs.go.env so
          # it lands in Go's own env file rather than the shell environment.
          env = {
            GOPATH = "${homeDirectory}/.local/share/go";
            GOBIN = "${homeDirectory}/.local/bin";
            GOMODCACHE = "${homeDirectory}/.cache/go/mod";
            GOCACHE = "${homeDirectory}/.cache/go/build";
          };
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
