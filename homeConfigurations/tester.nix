{ inputs, username, homeDirectory, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    imports = [
      # Neutral entrypoint: pulls in the shared MCP + skills modules and every
      # agent module. Nothing is wired until an agent is enabled below.
      inputs.agentic-config.homeManagerModules.default
    ];
    config = {
      # The VM mirrors production, so it runs the same agent set as
      # adbell.nix. Kiro is deliberately absent (work machine only).
      programs.agenticConfig.skills.enable = true;
      programs.agenticConfig.agents.claude.enable = true;
      programs.agenticConfig.agents.opencode.enable = true;
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
          # gcloud, plus the GKE auth plugin. Extra components must come from
          # this wrapper, never `gcloud components install`: the SDK is a
          # read-only store path, so gcloud's own component manager cannot
          # write to it. Same reason `gcloud components update` fails — the
          # version is whatever nixpkgs pins, bumped via `nix flake update`.
          # The plugin is the credential helper kubectl execs for GKE clusters;
          # it must exist as its own binary on $PATH, which is exactly what the
          # wrapper puts in the profile's bin.
          (pkgs.google-cloud-sdk.withExtraComponents [
            pkgs.google-cloud-sdk.components.gke-gcloud-auth-plugin
          ])
          pkgs.jq
          pkgs.k3d
          pkgs.k9s
          # Ships both `kubectx` (switch cluster context) and `kubens`
          # (switch default namespace). Interactive fuzzy selection needs
          # fzf on $PATH, which programs.fzf below provides.
          pkgs.kubectx
          # Helm. The attribute is kubernetes-helm; `pkgs.helm` is an
          # unrelated Haskell package, and the binary this installs is
          # plain `helm`.
          pkgs.kubernetes-helm
          pkgs.llmfit
          pkgs.mas
          pkgs.opencode
          pkgs.pwgen
          # Terraform version manager. Deliberately *not* alongside
          # pkgs.terraform: tfenv ships its own bin/terraform shim, so the two
          # collide on the same path and buildEnv refuses to build the profile
          # ("two given paths contain a conflicting subpath"). tfenv owns the
          # terraform name here, and versions come from `tfenv install` /
          # per-repo .terraform-version files. Consequence: the terraform
          # binaries themselves are HashiCorp downloads under ~/.tfenv, outside
          # nix and not reproducible from the flake lock.
          pkgs.tfenv
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
          # tfenv derives TFENV_ROOT from where its shim lives, which under nix
          # is a read-only store path, and TFENV_CONFIG_DIR defaults to
          # TFENV_ROOT. Left unset, `tfenv install` tries to write versions into
          # /nix/store and fails. Name a writable dir explicitly.
          TFENV_CONFIG_DIR = "${homeDirectory}/.tfenv";
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
          # Mirrors adbell.nix — see the rationale there. Go's default GOPATH
          # is ~/go; this redirects it onto XDG paths, puts `go install` output
          # on PATH via GOBIN, and pins GOCACHE (which Go would otherwise
          # resolve to ~/Library/Caches on darwin). GOROOT stays unset so the
          # toolchain derives it from its own store path.
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
        obsidian = {
          enable = true;
        };
        oh-my-posh = {
          enable = true;
          enableZshIntegration = true;
          # Vendored theme rather than `useTheme`. Upstream
          # powerlevel10k_rainbow ships no kubectl segment, and a theme from
          # the package is a read-only store path, so it cannot be extended in
          # place. `settings`, `useTheme` and `configFile` are mutually
          # exclusive (home-manager asserts on more than one), so gaining one
          # segment means owning the whole file. Copied verbatim from
          # oh-my-posh 29.14.0 with a single kubectl segment inserted after
          # `aws` — diff it against
          # ${pkgs.oh-my-posh}/share/oh-my-posh/themes/ after a version bump
          # and only that insertion should show.
          configFile = ../oh-my-posh/powerlevel10k_rainbow.omp.json;
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
            # Machine-local overlay — the writable half of the "managed base +
            # writable local overlay" pattern (docs/patterns.md), applied to the
            # shell. Sourced last so it can override anything nix or antidote
            # set up. Both files are optional, so this is a no-op on a machine
            # that has neither.
            #
            #   local.zsh    on-the-fly tweaks: aliases, functions, PATH bits.
            #                Either get promoted into this file later, or stay
            #                machine-specific forever.
            #   secrets.zsh  tokens and API keys (chmod 600). Never in this
            #                repo — it's public — and never in
            #                home.sessionVariables, which renders into a
            #                world-readable /nix/store path. Prefer an
            #                `op://` reference (as FluxCD above) where the
            #                consumer can resolve one; secrets.zsh is for the
            #                tokens that must be a literal value in the
            #                environment.
            #
            # `if` rather than `[[ … ]] && source`, so a missing file doesn't
            # leave $? nonzero for the first prompt to render as an error.
            (lib.mkAfter ''
              if [[ -f "$HOME/.config/zsh/local.zsh" ]]; then
                source "$HOME/.config/zsh/local.zsh"
              fi
              if [[ -f "$HOME/.config/zsh/secrets.zsh" ]]; then
                source "$HOME/.config/zsh/secrets.zsh"
              fi
            '')
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
