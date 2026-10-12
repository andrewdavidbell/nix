# Exam-matched bash shell for CKA/CKAD/CKS drills. Launch it with `kdrill`,
# defined in the home configs' programs.zsh.initContent.
#
# Rendered to ~/.config/bash/k8s-drill.bashrc as a read-only store symlink, so
# edit it here and re-activate rather than in place.
#
# Deliberately minimal. The exam terminal has only what you set up yourself in
# the first minute, so anything extra in here trains a reflex you won't have on
# the day. Resist adding the oh-my-zsh kubectl aliases.

# --- safety rail ------------------------------------------------------------
# Lab-only kubeconfig. This shell cannot see a production context even if asked,
# which is the point: `$now` lives here, and force deletion against a real
# cluster skips graceful shutdown (on a StatefulSet it can break the
# at-most-one-pod-per-identity guarantee and corrupt a volume).
#
# ~/.kube/drill.config is machine-local and NOT in this repo — it holds cluster
# credentials and this repo is public. Create it per machine with:
#   kubectl config view --minify --flatten --context=<lab-context> \
#     > ~/.kube/drill.config && chmod 600 ~/.kube/drill.config
# It is a point-in-time snapshot: recreate the lab cluster and it goes stale.
export KUBECONFIG="$HOME/.kube/drill.config"

# --- the exam shortcuts -----------------------------------------------------
# Strings, not arrays: bash word-splits unquoted expansions, so `k get po $do`
# correctly becomes three arguments. zsh does not, which is why ~/.config/zsh/
# local.zsh defines `do` as an array instead. `now` is defined *only* here --
# the zsh ops shell can reach production.
export do='--dry-run=client -o yaml'
export now='--force --grace-period 0'

alias k=kubectl

# --- completion, including for the `k` alias --------------------------------
# Generated synchronously here, unlike the zsh side (where the oh-my-zsh kubectl
# plugin caches it in the background). A drill shell is launched deliberately
# and rarely, so paying ~200ms once beats a cache that is one shell stale.
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  complete -o default -F __start_kubectl k
fi

# `kubectl edit` defers to this
export KUBE_EDITOR=vim
export EDITOR=vim

# Not enabling `shopt -s globstar` on purpose: the exam's bash has it off, so
# getting used to ** here would train a habit that silently fails there.

# --- prompt -----------------------------------------------------------------
# Plain and static, with a clear [drill] marker so this is never mistaken for
# the ops shell. No command substitution, so no per-prompt kubectl call --
# the pinned KUBECONFIG means there is only one context it could be showing.
PS1='\[\e[1;33m\][drill]\[\e[0m\] \w\$ '

# --- scratch space ----------------------------------------------------------
# Somewhere for generated YAML to land instead of whatever repo you were in.
export DRILL_DIR="$HOME/Documents/Local Source/k8s-drills"
mkdir -p "$DRILL_DIR"
cd "$DRILL_DIR" || true

# Separate history, so drill commands don't pollute the zsh history (and vice
# versa -- searching for a real command shouldn't surface practice runs).
export HISTFILE="$HOME/.bash_history_k8s_drill"
export HISTSIZE=5000
export HISTFILESIZE=5000
shopt -s histappend
