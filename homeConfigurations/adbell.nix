{ inputs, username, homeDirectory, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    imports = [
      # Claude Code module transitively imports the agent-agnostic mcp
      # and skills modules from the same flake — no need to re-import
      # them here (the module system rejects duplicate option declarations
      # when the same file is imported via two different attribute paths).
      inputs.agentic-config.homeManagerModules.default
    ];
    config = {
      programs.agenticConfig.skills.enable = true;
      # Opencode is installed on this machine (pkgs.opencode below), so wire
      # in the TDD sub-agents, /tdd slash command, and phase-guard plugin.
      programs.agenticConfig.opencode.tdd.enable = true;
      home = {
        username = lib.mkForce username;
        homeDirectory = lib.mkForce homeDirectory;
        packages = [
          pkgs.ansible
          pkgs.awscli2
          pkgs.discord
          pkgs.ffmpeg
          pkgs.fluxcd
          pkgs.gh
          pkgs.google-cloud-sdk
          pkgs.jq
          pkgs.k3d
          pkgs.mas
          pkgs.opencode
          pkgs.pwgen
          # Required by nvim-treesitter's `main` branch, which compiles parsers
          # at install time via the tree-sitter CLI (unlike `master`, which
          # shipped precompiled .so files).
          pkgs.tree-sitter
          pkgs._1password-cli
        ];
        stateVersion = "26.05";
        sessionPath = [
          "${homeDirectory}/.local/bin"
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
        # Opencode baseline is rendered from Nix so the MCP fragment
        # (shared across every agent) is merged in. Static provider/theme
        # config lives in ../opencode/opencode-base.nix; per-machine or
        # personal overrides go in ~/.config/opencode/local.jsonc (see
        # OPENCODE_CONFIG above).
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
          # Emit these as a `Host *` block (settings."*"), which home-manager
          # renders *after* the includes. SSH uses the first value seen for each
          # option, so host-specific settings in `config.d/*` must come first and
          # win. `extraOptionOverrides` would emit them at the top of the file,
          # ahead of the Include, pre-empting config.d (e.g. GitHub auth).
          # settings uses freeform upstream directive names (capitalised).
          settings."*" = {
            IdentityAgent = "\"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock\"";
            # ServerAliveCountMax defaults to 3 so disconnect will occur after 3 minutes
            ServerAliveInterval = 60;
          };
        };
        git = {
          enable = true;
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
            # No-op here (~/.gitconfig.local always sets `[user]` on this
            # machine) but load-bearing on the work box, where identity is
            # routed by remote URL and a repo with no remote yet has none.
            user.useConfigOnly = true;
            # Verify SSH-signed commits against this file (committer email ->
            # allowed public key). The path is shared; the file content is
            # machine-local identity, created per machine like ~/.gitconfig.local
            # (see CLAUDE.md).
            gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
          };
          ignores = [
            ".DS_Store"
            ".vscode"
            "**/.claude/settings.local.json"
          ];
          includes = [
            { path = "~/.gitconfig.local"; }
          ];
          signing = {
            format = "ssh";
            key = null;
            signByDefault = true;
            # 1Password is a Homebrew cask (it must live in /Applications
            # proper for its integrity check), so op-ssh-sign is at the stable
            # /Applications path, not a nix-store path.
            signer = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
          };
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
        zsh = {
          enable = true;
          shellAliases = {
            ic = "cd ~/Library/Mobile\\ Documents/com~apple~CloudDocs";
            ob = "cd ~/Library/Mobile\\ Documents/iCloud~md~obsidian/Documents";
            src = "cd ~/Documents/Local\\ Source";
          };
          initContent = lib.mkMerge [
            (lib.mkBefore ''
              # Set up ZSH cache directory for oh-my-zsh plugins
              export ZSH_CACHE_DIR="$HOME/.cache/zsh"
              [[ -d "$ZSH_CACHE_DIR/completions" ]] || mkdir -p "$ZSH_CACHE_DIR/completions"
            '')
            ''
              # 1Password SSH agent
              export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
              export OP_BIOMETRIC_UNLOCK_ENABLED=true

              # FluxCD credentials (1Password references)
              export FLUXCD_TOKEN="op://Private/fgl2ajasfbzxslend4sqnowuui/token"
              export FLUXCD_USERNAME="op://Private/fgl2ajasfbzxslend4sqnowuui/username"

              export NVM_DIR="$HOME/.nvm"
              [[ -e "''${HOMEBREW_PREFIX}/opt/nvm/nvm.sh" ]] && source "''${HOMEBREW_PREFIX}/opt/nvm/nvm.sh"

              vm() {
                select config in kickstart lazyvim nvchad
                do NVIM_APPNAME=nvim-$config nvim $@; break; done
              }

              genpass() {
                if [[ -z "$1" || ! "$1" =~ ^[0-9]+$ ]]; then
                  echo "Usage: genpass <length>"
                  return 1
                fi
                pwgen -Bsy "$1" 1 | pbcopy
                echo "Password copied to clipboard"
              }

              [[ -e ~/.config/op/plugins.sh ]] && source ~/.config/op/plugins.sh
            ''
          ];
          antidote = {
            enable = true;
            plugins = [
              # Oh My Zsh
              "getantidote/use-omz"
              "ohmyzsh/ohmyzsh path:lib"
              # Plugins
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
