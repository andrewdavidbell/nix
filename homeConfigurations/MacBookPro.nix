{ inputs, username, homeDirectory, ... }@flakeContext:
let
  homeModule = { config, lib, pkgs, ... }: {
    config = {
      home = {
        username = lib.mkForce username;
        homeDirectory = lib.mkForce homeDirectory;
        packages = [
          pkgs.awscli2
          pkgs.jq
          pkgs.llama-cpp
          pkgs.opencode
          pkgs.ruff
          # Provides the `huggingface-cli` and `hf` binaries (Hugging Face CLI).
          pkgs.python313Packages.huggingface-hub
        ];
        stateVersion = "26.05";
        sessionPath = [
          "${homeDirectory}/.local/bin"
        ];
        sessionVariables = {
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
        "opencode/opencode.jsonc".source = ../opencode/opencode.jsonc;
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
          # Plain git for the work machine: no 1Password SSH commit signing.
          # Identity (name/email) is machine-local via ~/.gitconfig.local.
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
        vscode = {
          enable = true;
          profiles.default = {
            extensions = (with pkgs.vscode-extensions; [
              bbenoist.nix
              eamodio.gitlens
              ms-azuretools.vscode-containers
              ms-python.debugpy
              ms-python.python
              ms-python.vscode-pylance
              ms-vscode-remote.remote-containers
              tomoki1207.pdf
            ]) ++ (with pkgs.vscode-utils; [
              (buildVscodeMarketplaceExtension {
                mktplcRef = {
                  publisher = "continue";
                  name = "continue";
                  version = "1.2.16";
                  arch = "darwin-arm64";
                  hash = "sha256-LX7PIUf/8//WJraABTw+1Awt2oj3Q8pFNt4xLQvYgvw=";
                };
              })
              (buildVscodeMarketplaceExtension {
                mktplcRef = {
                  publisher = "ms-python";
                  name = "vscode-python-envs";
                  version = "1.20.1";
                  arch = "darwin-arm64";
                  hash = "sha256-Cy1GBU0U08anuRKCoPcYQYZJWyH2H+Bcn7hMxVzRfLM=";
                };
              })
              (buildVscodeMarketplaceExtension {
                mktplcRef = {
                  publisher = "vsls-contrib";
                  name = "gistfs";
                  version = "0.9.6";
                  hash = "sha256-p1HxLW29CFRnIhknlqoS+koY+pe4zrdqDBcj87dkHuU=";
                };
              })
            ]);
            userSettings = {
            "dev.containers.defaultExtensions" = [
              "eamodio.gitlens"
              "mutantdino.resourcemonitor"
            ];
            "editor.renderWhitespace" = "all";
            "editor.renderFinalNewline" = "on";
            "editor.tabSize" = 2;
            "editor.fontSize" = 14;
            "editor.suggestSelection" = "first";
            "editor.detectIndentation" = false;
            "editor.rulers" = [ 80 120 ];
            "editor.suggest.showMethods" = true;
            "editor.suggest.preview" = true;
            "editor.acceptSuggestionOnEnter" = "on";
            "editor.snippetSuggestions" = "top";
            "editor.multiCursorModifier" = "ctrlCmd";
            "editor.inlineSuggest.enabled" = true;
            "editor.formatOnSave" = true;
            "editor.defaultFormatter" = "charliermarsh.ruff";
            "editor.fontFamily" = "JetBrains Mono, MesloLGS NF, Menlo, Monaco, 'Courier New', monospace";
            "editor.fontLigatures" = true;
            "[json]" = {
              "editor.defaultFormatter" = "vscode.json-language-features";
            };
            "[html]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
            "[javascript]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
            "[jsonc]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
            "[yaml]" = {
              "editor.defaultFormatter" = "esbenp.prettier-vscode";
            };
            "[xml]" = {
              "editor.defaultFormatter" = "redhat.vscode-xml";
            };
            "[python]" = {
              "editor.codeActionsOnSave" = {
                "source.organizeImports" = "explicit";
                "source.fixAll" = "explicit";
              };
            };
            "[prompt]" = {
              "editor.unicodeHighlight.ambiguousCharacters" = false;
              "editor.unicodeHighlight.invisibleCharacters" = false;
              "diffEditor.ignoreTrimWhitespace" = false;
              "editor.wordWrap" = "on";
              "editor.quickSuggestions" = {
                "comments" = "off";
                "strings" = "off";
                "other" = "off";
              };
            };
            "files.trimTrailingWhitespace" = true;
            "files.insertFinalNewline" = true;
            "git.confirmSync" = false;
            "git.suggestSmartCommit" = false;
            "telemetry.telemetryLevel" = "crash";
            "terminal.integrated.defaultProfile.osx" = "zsh";
            "terminal.integrated.defaultProfile.linux" = "zsh";
            "terminal.external.osxExec" = "Ghostty.app";
            "terraform.languageServer.enable" = true;
            "yaml.customTags" = [
              "!And" "!And sequence" "!If" "!If sequence"
              "!Not" "!Not sequence" "!Equals" "!Equals sequence"
              "!Or" "!Or sequence" "!FindInMap" "!FindInMap sequence"
              "!Base64" "!Join" "!Join sequence" "!Cidr"
              "!Ref" "!Sub" "!Sub sequence" "!GetAtt" "!GetAZs"
              "!ImportValue" "!ImportValue sequence"
              "!Select" "!Select sequence" "!Split" "!Split sequence"
            ];
            "aws.telemetry" = false;
            "continue.telemetryEnabled" = false;
            "continue.enableTabAutocomplete" = false;
            "continue.enableNextEdit" = false;
            "gitlens.telemetry.enabled" = false;
            "redhat.telemetry.enabled" = false;
            "explorer.fileNesting.patterns" = {
              "*.ts" = "\${capture}.js";
              "*.js" = "\${capture}.js.map, \${capture}.min.js, \${capture}.d.ts";
              "*.jsx" = "\${capture}.js";
              "*.tsx" = "\${capture}.ts";
              "tsconfig.json" = "tsconfig.*.json";
              "package.json" = "package-lock.json, yarn.lock, pnpm-lock.yaml, bun.lockb";
              "*.sqlite" = "\${capture}.\${extname}-*";
              "*.db" = "\${capture}.\${extname}-*";
              "*.sqlite3" = "\${capture}.\${extname}-*";
              "*.db3" = "\${capture}.\${extname}-*";
              "*.sdb" = "\${capture}.\${extname}-*";
              "*.s3db" = "\${capture}.\${extname}-*";
            };
            "npm.packageManager" = "yarn";
            "chat.agent.enabled" = true;
            "chat.disableAIFeatures" = true;
            "python.analysis.typeCheckingMode" = "basic";
            "python.analysis.ignore" = [ "*" ];
          };
          };
        };
        zsh = {
          enable = true;
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
