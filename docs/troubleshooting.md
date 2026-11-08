# Troubleshooting

Recipes for recurring failure modes in this Nix configuration. Each entry
follows the same shape: **Symptom → What's actually happening → Fix →
Prevention**, so you can jump straight to whichever section you need.

---

## `darwin-rebuild switch` halts at Homebrew with "invalid cask definition"

### Symptom

You run:

```bash
sudo --set-home darwin-rebuild switch --flake .#<host>
```

The Nix build phase completes fine. Then, after the `Homebrew bundle...`
banner, the output ends with lines like:

```
Error: Cask 'vlc' definition is invalid: undefined method 'command_wrapper' for Cask 'vlc'
`brew bundle` failed! Failed to fetch omlx, claude, docker-desktop, figma, idrive, vlc
```

You go to check whether the change you edited in the repo is live — say, a
plugin config under `nvim/` — and it isn't:

```bash
$ readlink ~/.config/nvim/lua
/nix/store/<OLD-HASH>-home-manager-files/.config/nvim/lua
```

The symlink still points at the *previous* generation. Your edit appears
to have had no effect, even though the build succeeded.

### What's actually happening

nix-darwin's activation runs a fixed sequence of steps. Home-manager
swaps the `~/.config/*` and other user-owned symlinks *after* the
Homebrew bundle step. When `brew bundle` exits non-zero, the whole
activation script aborts before home-manager runs. The result is:

- A new system generation *is* built in `/nix/store/`.
- The home-manager symlinks are **not** updated.
- Your repo edit is present in the store but not visible from your
  home directory.

The trigger — `undefined method '<name>' for Cask` — means the upstream
`homebrew/cask` tap has a cask that uses a Cask DSL method the installed
Homebrew doesn't recognise. The tap tracks HEAD and can pull ahead of
tagged Homebrew releases, so there's a window where a newly-updated cask
references DSL that hasn't shipped in a Homebrew version yet. During
that window, `brew bundle` fails for any Brewfile that includes the
offending cask.

### Fix

1. **Confirm the diagnosis.** Read the error and note the cask name and
   the missing method. If the message isn't `undefined method … for
   Cask`, you're looking at a different failure — most other `brew
   bundle` errors are network or 403 issues that resolve on retry.

2. **Try updating Homebrew first.**

   ```bash
   brew update
   brew --version
   ```

   If the version bumped, retry the switch — upstream may have shipped
   the missing method. If the version didn't change or the error
   persists, you're stuck until upstream ships a fix.

3. **Temporarily drop the offending cask.** Edit the affected
   `darwinConfigurations/<host>.nix` and comment out the cask, with a
   note explaining why and when you disabled it:

   ```nix
   # "vlc"  # temporarily dropped 2026-08-08: upstream cask uses
   #          `command_wrapper` DSL method, not supported by
   #          Homebrew 6.0.1. cleanup = "none" here, so the
   #          installed app is untouched. Re-enable once Homebrew
   #          ships the missing method.
   ```

   **Safety by cleanup mode:**

   | Config                             | `cleanup`     | Safe to drop? |
   |------------------------------------|---------------|---------------|
   | `Andrews-MacBook-Pro-M3.nix`       | `"none"`      | Yes — app stays installed |
   | `MacBookPro.nix`                   | `"none"`      | Yes — app stays installed |
   | `Testers-Virtual-Machine.nix`      | `"uninstall"` | **No** — app would be uninstalled on next activation |

4. **Re-run activation.**

   ```bash
   sudo --set-home darwin-rebuild switch --flake .#<host>
   ```

5. **Verify a home-manager symlink flipped.** Pick anything you know is
   managed:

   ```bash
   readlink ~/.config/nvim/lua
   ```

   The `/nix/store/<hash>-home-manager-files/...` prefix should now be
   different from before.

6. **Re-enable the cask** once Homebrew catches up. Periodically check:

   ```bash
   brew --version
   brew info --cask <name>   # should no longer error
   ```

   Then uncomment the cask and run `switch` again.

### Prevention / early warning

You can't stop upstream from shipping a broken cask, but you can catch
it before your next activation:

- Run `brew bundle check --file=<generated-Brewfile>` occasionally, or
  just `brew info --cask <cask>` for casks you especially rely on.
- Homebrew's own release notes usually explain when a new Cask DSL
  method lands; if you follow them you'll know when it's safe to
  re-enable.

---

## `darwin-rebuild switch` halts at Homebrew with "circular dependency"

### Symptom

Same activation shape as the cask DSL case above — Nix build succeeds,
then `brew bundle` fails and home-manager symlinks don't flip. The
error looks like:

```
Error: Formulae dependency graph sorting failed (likely due to a circular dependency):
libtiff: ["jpeg-turbo", "giflib", "libpng", "webp", "xz", "lz4", "zstd"]
webp: ["giflib", "jpeg-turbo", "libpng", "libtiff"]
Please run the following commands and try again:
  brew update
  brew uninstall --ignore-dependencies --force libtiff webp
  brew install libtiff webp
```

The two named formulae (`libtiff` and `webp` in this example) list each
other as runtime dependencies, so Homebrew can't compute an install
order and refuses to proceed. Note: your declared `brews = [...]` may
not mention either — they're transitive deps of *something* that is
(or was) installed.

### What's actually happening

Two things compound to produce this failure:

1. **The cycle itself.** Each formula's on-disk install receipt
   (`/opt/homebrew/Cellar/<f>/<version>/INSTALL_RECEIPT.json`) lists the
   other as a `runtime_dependencies` entry. That's a genuine cycle. It
   typically appears after a `brew update` (auto or manual) pulls a new
   version of one formula whose dep list crosses over the
   already-installed version of the other. Homebrew has no
   in-place-repair path for this — the receipts have to be regenerated
   by uninstalling and reinstalling both, which normal `brew uninstall`
   won't do (each blocks the other), hence Homebrew's
   `--ignore-dependencies --force` recipe.

2. **A stale explicit install keeping the cycle alive.** On machines
   with `cleanup = "none"` (M3 and the work machine, both needed for the
   `omlx` closure bug — see `AGENTS.md`), formulae dropped from `brews =
   [...]` are **not** uninstalled on activation. Worse, `brew
   autoremove` only reaps formulae that were installed *as a
   dependency* (`installed_on_request: false`) — it deliberately leaves
   alone anything marked `installed_on_request: true`. So a formula you
   once declared and later removed lingers forever, dragging its dep
   subtree along with it. If that subtree contains the cycled pair, the
   cycle keeps being pulled back in even after you fix it.

### Diagnosis

Homebrew's API is currently 404ing on macOS 26 Tahoe
(`packages.dunno_tahoe.jws.json` doesn't exist yet), which breaks `brew
uses`, `brew leaves`, and sometimes `brew autoremove` — the standard
"who pulls this in?" commands. Fall back to reading install receipts
directly.

**Find which installed formulae pull in the cycled pair:**

```bash
for r in /opt/homebrew/Cellar/*/*/INSTALL_RECEIPT.json; do
  formula=$(echo "$r" | awk -F/ '{print $(NF-2)}')
  deps=$(python3 -c "import json; d=json.load(open('$r')); print(' '.join(x['full_name'] for x in d.get('runtime_dependencies',[])))" 2>/dev/null)
  if echo " $deps " | grep -qE " (libtiff|webp) "; then
    echo "$formula -> $deps"
  fi
done
```

Substitute the pair Homebrew named. Any formula listed that isn't
itself part of the cycle is a candidate root. Cross-reference against
the declared `brews = [...]` in `darwinConfigurations/<host>.nix`.

**Check whether the root is a stale explicit install:**

```bash
python3 -c "
import json, os
name = '<root>'
ver = os.listdir(f'/opt/homebrew/Cellar/{name}')[0]
d = json.load(open(f'/opt/homebrew/Cellar/{name}/{ver}/INSTALL_RECEIPT.json'))
print('installed_on_request:', d.get('installed_on_request'))
print('installed_as_dependency:', d.get('installed_as_dependency'))
"
```

If the root is absent from `brews = [...]` and shows
`installed_on_request: True`, it's a stale explicit install — a
formula you declared once, removed from the config, and `cleanup =
"none"` left behind.

### Fix

1. **Break the cycle**, exactly as Homebrew suggests:

   ```bash
   brew update
   brew uninstall --ignore-dependencies --force <pair-A> <pair-B>
   brew install <pair-A> <pair-B>
   ```

2. **If diagnosis found a stale explicit install, remove it and reap
   the subtree.** `brew autoremove` won't do this on its own because of
   the `installed_on_request: true` guard:

   ```bash
   brew uninstall <stale-root>
   brew autoremove
   ```

   After `brew uninstall <stale-root>`, its former deps are now marked
   as unused and `brew autoremove` will collect them.

3. **Retry activation:**

   ```bash
   sudo --set-home darwin-rebuild switch --flake .#<host>
   ```

4. **Verify a home-manager symlink flipped** (same check as the cask
   DSL section).

### Prevention

- On `cleanup = "none"` machines, periodically audit for stale explicit
  installs. `brew list --formula` shows what's actually installed;
  cross-reference against the declared `brews` in the host config.
  Anything present locally but absent from the config, with
  `installed_on_request: True`, is a stale root that `brew autoremove`
  cannot clean up on its own.
- When removing a brew from `brews = [...]`, also `brew uninstall
  <name>` on the affected machine in the same commit — otherwise the
  formula and its dep closure survive indefinitely.
- The test VM is not exposed to this failure (`cleanup = "uninstall"`
  prunes any undeclared formula on every activation), so it can look
  green while the production machines accumulate stale roots. Don't
  rely on VM activations as a signal here.

---

## `brew bundle` fails with "process has already locked" → activation halts

### Symptom

`darwin-rebuild switch` reaches the Homebrew step and dies with a lock error
naming **its own command line**:

```
Error: jundot/omlx/omlx: A `brew install --adopt jundot/omlx/omlx homebrew/cask/idrive` process
has already locked /opt/homebrew/Cellar/openssl@3.
Please wait for it to finish or terminate it to continue.
`brew bundle` failed! 1 Brewfile dependency failed to install
```

Same downstream consequence as the other two `brew bundle` entries above:
home-manager runs *after* Homebrew in nix-darwin's activation, so repo edits
appear "not applied" even though the build succeeded. Hit on
`Andrews-MacBook-Pro-M3`, 18 Oct 2026.

The message invites you to go hunting for a competing process. **There isn't
one.** Read the command line in the error: it is the process you are running.
Homebrew is deadlocking against itself.

### What's actually happening

One `brew upgrade` run locked the same formula twice. A dependency lands in
both the *"upgrade these outdated dependencies"* set and the *"install
dependencies"* set of a single invocation, and the second acquisition blocks
on the first.

What put `openssl@3` in both sets was an upstream formula reshuffle that the
run's own `Auto-updating Homebrew...` step pulled in: Homebrew split
`openssl@3.6` out into its own formula, so `openssl@3` **rolled backwards**
to 3.5.9 while 3.6.5 was installed. That reads as `outdated` even though the
installed version is numerically newer:

```console
$ brew outdated --formula --verbose
openssl@3 (3.6.5) < 3.5.9          # the giveaway: installed > "available"
```

Two things follow, and both matter for diagnosis:

- **The named formula is rarely the culprit.** `omlx` was simply the first
  thing `brew bundle` reached; anything with `openssl@3` in its closure would
  have deadlocked identically. `omlx`'s only *direct* dependency is
  `python@3.11` — `openssl@3` arrives transitively.
- **Failures compound.** Each aborted attempt died mid-pour, leaving debris
  that causes *different* errors on retry: a nested
  `Cellar/openssl@4/4.0.3/4.0.3` directory (`Error: openssl@4: File exists`)
  and an orphaned `4.0.3.tmp` keg. Don't read those as new problems; they are
  wreckage from the first one.

### Fix

Settle the closure one formula at a time, so no single `brew` process ever has
to lock anything twice. Only then retry the package that was named:

```bash
brew outdated --formula --verbose        # find the installed > available rows
brew upgrade openssl@3                   # each in its OWN process
for f in openssl@4 libssh2 libgit2 pkgconf sqlite rust; do brew upgrade "$f"; done
brew upgrade jundot/omlx/omlx            # now has nothing left to lock
brew outdated --formula                  # must be empty before re-activating
```

Expect most of the loop to print `already installed` — earlier failed runs got
through the dependency phase before dying, so the work is already done.

Then re-run `sudo --set-home darwin-rebuild switch --flake .#<host>` and
confirm a home-manager symlink actually flipped — the `/nix/store/…-home-manager-files/…`
prefix should differ from before:

```bash
readlink ~/.zshrc
```

**Clearing the debris.** An orphaned `*.tmp` keg carries a valid
`INSTALL_RECEIPT.json`, so Homebrew counts it as installed and `brew cleanup`
will *not* remove it (the dry run prints nothing). Verify nothing links to it,
then delete it directly:

```bash
K=/opt/homebrew/Cellar/openssl@4/4.0.3.tmp
find /opt/homebrew/{opt,lib,bin,include} -maxdepth 1 -type l \
  | xargs -I{} sh -c 'readlink "{}" | grep -q "4\.0\.3\.tmp" && echo "LINK: {}"'
rm -rf "$K"        # only if the find printed nothing
brew missing       # should be silent
```

### Prevention

There is nothing to declare in this repo — the trigger is upstream formula
churn, and `onActivation.autoUpdate`/`upgrade` means activation picks it up
whenever Homebrew decides to reshuffle. What helps is **separating the two
jobs**: when `brew update` reports a large batch of new formulae (especially
a versioned split like `openssl@3.6`), run `brew upgrade` by hand *before*
`darwin-rebuild switch`, so a lock failure costs you a brew run rather than a
halted activation.

The cheap pre-flight, and the one check worth making a habit:

```bash
brew update && brew outdated --formula --verbose
```

Any row where the installed version is **greater** than the available one is a
formula rollback, and is the shape that causes this. Settle those individually
first.

Note the test VM will not catch this class of failure — it excludes `omlx`
entirely (see the cleanup-mode note in `AGENTS.md`), and the trigger is
whatever Homebrew happened to publish that day rather than anything in the
flake. A green VM activation is not evidence here.

**`brew pin` does hold against activation** — verified 20 Oct 2026, because
"will nix-darwin just re-upgrade it?" is the obvious doubt. nix-darwin runs a
plain `brew bundle --file=<store Brewfile>` with no upgrade flag, and
Homebrew's bundle layer subtracts pins before deciding what to touch:

```ruby
# Library/Homebrew/bundle/brew.rb
def upgradable_formulae = outdated_formulae - pinned_formulae
```

Casks are handled equivalently in `bundle/cask.rb` (`casks.reject(&:pinned?)`).
So `brew pin <formula>` is a legitimate way to hold a package across
activations — useful to park something that keeps failing, without editing the
darwin config and rebuilding.

Two caveats. A pin is **machine-local and invisible to this repo**, so the
declared config and what is installed silently diverge — if a brew looks
frozen at the wrong version, check `brew list --pinned` before suspecting the
flake. And a pin suppresses security updates for as long as it is set, so
treat it as a dated workaround and record why.

## A newly-wired agent appears to ignore its MCP servers and skills

**Symptom:** a new agent is wired up, `darwin-rebuild switch` succeeds, the
config files are present and readable on disk — and the agent behaves as though
none of it exists. First hit with Kiro on `MacBookPro` (9 Sep 2026), where both
the MCP servers and the skills looked broken and neither actually was.

**Diagnose in this order — cheapest and most likely first:**

1. **Restart the agent completely.** Config appearing *underneath* a running
   instance is not the same as an edit to a file it already tracks. Kiro
   documents reload-at-idle for the latter only. Quit fully, don't just reload
   the window.
2. **Check you are looking in the right place.** Agents surface skills in
   product-specific UI that is not always obvious. In Kiro it is the **Agent
   Steering & Skills** panel; MCP servers are under the MCP panel, reachable via
   `Cmd+Shift+P` → "Kiro: Open user MCP config (JSON)". "I can't see them"
   usually means "I haven't found the panel yet".
3. **Confirm activation actually ran.** A `brew bundle` failure aborts
   activation *before* home-manager links anything, so the build succeeds and
   nothing flips. `readlink ~/.claude/settings.json` — if it isn't a store path,
   home-manager never ran. See the two Homebrew entries above.
4. **Only then** suspect the config itself.

**Do not assume a symlink-traversal problem.** Kiro reads bespoke skills through
bare `/nix/store` symlinks without trouble, exactly as Claude Code reads the
third-party symlinks in `~/.claude/skills/`. A plausible mechanism — Node's
`readdir({ withFileTypes: true })` reporting `isDirectory() === false` for
symlinks — was diagnosed here and turned out **not** to apply. Bare symlinks are
the norm across `~/.agents/skills/`, `~/.claude/skills/` and `~/.kiro/skills/`;
`recursive = true` is not needed.

**Prevention:** when adding an agent, confirm where it *displays* skills and MCP
servers before concluding anything is broken, and restart it once after the
first activation. `nix build` proves evaluation, never activation or discovery.

## Kiro's agent reports exit code -1 and captures the prompt as command output

Applies to `MacBookPro` only — Kiro is a work-machine cask.

### Symptom

Kiro's agent runs a command in its integrated terminal and comes back with one
or more of:

- the captured "output" contains the oh-my-posh prompt box and the echoed input
  line, not just the command's own output
- **`exit code -1`** instead of the real status, so the agent cannot tell
  success from failure
- the agent hangs in **`Working...`** and never sees the command finish

Everything else about the shell is fine — `$PATH` is right, aliases work,
commands you type by hand behave normally. It is only the *agent's* view that is
broken.

### What's actually happening

Kiro drives its terminal through VS Code-style shell integration: the shell
emits escape-sequence markers around each command so the editor knows where
output starts, where it ends, and what the exit status was.

oh-my-posh installs a `precmd` hook that re-renders `PROMPT` on **every** prompt
draw. That happens after the integration has set its markers, so the markers get
clobbered. With no command boundaries the editor falls back to screen-scraping
(hence the prompt in the output) and has nowhere to read the status from (hence
`-1`). Powerlevel10k/9k has the same problem for the same reason, and
[Kiro's own troubleshooting docs](https://kiro.dev/docs/ide/troubleshooting/)
name both by name.

Kiro sets **`TERM_PROGRAM=kiro`** in terminals it launches, which is the hook
the upstream fix hangs off.

### Fix

Gate the prompt engine on `$TERM_PROGRAM` in the nix-managed `~/.zshrc`. In
`homeConfigurations/MacBookPro.nix`:

1. Set `programs.oh-my-posh.enableZshIntegration = false` (keep
   `enable = true` — the package and its themes are still wanted) and drop
   `useTheme`. That stops home-manager emitting an *unconditional*
   `eval "$(oh-my-posh init zsh …)"`.
2. Emit the eval yourself, guarded, in `programs.zsh.initContent`:

   ```nix
   ''
     if [[ "$TERM_PROGRAM" != "kiro" ]]; then
       eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh \
         --config ${pkgs.oh-my-posh}/share/oh-my-posh/themes/powerlevel10k_rainbow.omp.json)"
     fi
   ''
   ```

3. `sudo --set-home darwin-rebuild switch --flake .#MacBookPro`, then **quit
   Kiro fully and relaunch** — a window reload is not enough (see the entry
   above).

Verify with `echo "$TERM_PROGRAM"` (`kiro`) and
`ls /nonexistent; echo $?` (`1`, and Kiro must report `1`, not `-1`) in Kiro's
terminal; then confirm the rainbow prompt still renders in Terminal.app.

Only the prompt is suppressed. Antidote plugins, aliases, `$PATH`, `nvm` and
`vm()` all still load inside Kiro. If Kiro is still flaky after this, the next
thing to try is the zle widgets (`zsh-autosuggestions`,
`fast-syntax-highlighting`, `zsh-history-substring-search`), which redraw the
input line — but upstream does not blame them, and that needs a second antidote
bundle rather than a one-line guard.

### Prevention

**When an agent proposes fixing something by hand-editing a home-manager-managed
dotfile on these machines, that is the signal to go find the declarative
equivalent — not to accept the edit.** Kiro's own agent "fixed" this (Sept 2026)
by replacing the `~/.zshenv` store symlink with a real file setting
`ZDOTDIR="$HOME/.kiro/zdotdir"`, deleting the `~/.zshrc` symlink, hand-rolling a
`~/.kiro/zdotdir/.zshrc`, and adding a `zsh-clean` terminal profile to Kiro's
User settings. It worked, and it was wrong three times over:

- **Imperative** — it edits files this repo declares, so the next
  `darwin-rebuild switch` fights it (`backupFileExtension = "backup"` will move
  the stray `~/.zshenv` aside, and aborts outright if a `.backup` already
  exists).
- **Global, not scoped** — `~/.zshenv` is read by *every* zsh, so it stripped
  the prompt from Terminal.app too, and from the shell that runs
  `darwin-rebuild` itself.
- **Lossy** — the hand-rolled `.zshrc` re-derived `$PATH` from scratch and
  dropped everything else, which is why tools that were "missing" from it looked
  like PATH bugs when they were simply not in the config at all.

`ZDOTDIR` hijacking from `~/.zshenv` is never the right move on these machines.
A `$TERM_PROGRAM` guard inside the managed file is: it is scoped to one program,
survives rebuilds, and leaves nothing outside the store to drift.

To undo that specific hack: `rm ~/.zshenv`, `rm -rf ~/.kiro/zdotdir
~/.kiro/zsh-backup`, move any stale `~/.zsh*.backup` aside, revert
`terminal.integrated.*` in `~/Library/Application Support/Kiro/User/settings.json`
(not nix-managed, same as VS Code's), then switch.

---

## `kubectl` tab-completion does nothing

### Symptom

`kubectl get po<TAB>` just inserts a literal tab, or beeps, in a shell where
everything else completes fine. `kubectl` itself runs normally. Most likely on
`MacBookPro`, where `kubectl` is kuberlr, but the same mechanism can misfire
anywhere.

### What's actually happening

Nothing in this repo declares kubectl completion. It comes from the oh-my-zsh
`kubectl` plugin (loaded via antidote in all three home configs), which on every
shell start backgrounds:

```zsh
zf_mv -f -- =( kubectl completion zsh 2> /dev/null ) "$ZSH_CACHE_DIR/completions/_kubectl"
```

This repo supplies only the directory it writes into — the `lib.mkBefore` block
in each home config exports `ZSH_CACHE_DIR="$HOME/.cache/zsh"`, creates
`completions/`, and that path ends up first on `fpath`.

Two properties of that one line cause nearly every failure:

- **stderr is discarded, and `zf_mv` moves the file regardless of exit status.**
  If `kubectl completion zsh` fails, the result is a zero-byte `_kubectl` in the
  cache and no error anywhere. On `MacBookPro` the generator runs through
  kuberlr, which must reach a cluster's API server (or find a cached client in
  `~/.kuberlr/`) before it can delegate — so an unauthenticated or
  freshly-provisioned machine poisons the cache on the very first shell.
- **It is asynchronous (`&|`), so the cache is always one shell behind.** The
  current shell loads the *previous* snapshot. The first shell opened after a
  kubectl version change completes against the old client's flags; the next one
  is correct. A single new shell is therefore not enough to confirm a fix.

`k` is unaffected by any of this when it works: `complete_aliases` is off (zsh's
default, and oh-my-zsh doesn't change it), so zsh expands `k` → `kubectl` before
completion and the same `_kubectl` applies. No separate `compdef` exists for it.

### Fix

1. Look at the cache before suspecting the plugin or this repo:

   ```bash
   wc -l ~/.cache/zsh/completions/_kubectl   # healthy: ~200 lines
   ```

2. If it's empty or truncated, run the generator by hand to see the error the
   plugin swallowed:

   ```bash
   kubectl completion zsh | head -5
   ```

3. On `MacBookPro`, a kuberlr error here means it has no client to delegate to.
   Authenticate once against any cluster (`kubectl version` is enough to trigger
   the download), then clear the poisoned cache:

   ```bash
   rm ~/.cache/zsh/completions/_kubectl
   ```

4. Open **two** new shells — the first regenerates the cache, the second loads
   it. Then confirm the binding directly rather than by eye:

   ```bash
   zsh -i -c 'echo ${_comps[kubectl]:-NONE}'   # expect: _kubectl
   ```

Do **not** "fix" this by adding `kubectl completion zsh` to `initContent`, or by
adding `pkgs.kubectl` for its completions. The first runs a cluster-dependent
subprocess synchronously on every shell start (and on `MacBookPro` can block on
a kuberlr download); the second installs a binary that is shadowed on both
machines — see the kubectl section of `AGENTS.md`.

### Prevention

`kubectx` and `kubens` have none of this fragility, and are the model to copy:
nixpkgs installs their upstream `#compdef`-tagged completions into
`share/zsh/site-functions`, which is on `fpath` already, so they are declared,
version-locked and generated at build time rather than at shell start. When
these two don't complete, the cause is almost never completion — it's that the
generation adding `pkgs.kubectx` was never activated on that machine:

```bash
ls /etc/profiles/per-user/<user>/bin | grep kubectx
```

A clean `nix build` proves nothing here; only activation puts the completions on
`fpath`.

## A nix-installed Python app can't see a `pip install`ed module

### Symptom

A tool's docs say to `pip install <module>`, you do, and the tool still
behaves as though it isn't there. Hit with `ansible` and `netaddr` on
`Andrews-MacBook-Pro-M3`, 17 Oct 2026, setting up the `k3s-ansible`
playbooks in the `turingpi` repo — whose README says:

> The control node **must** have Ansible 8.0+ (ansible-core 2.15+) and the
> Python `netaddr` library (`pip install netaddr`), required by the
> `ansible.utils.ipwrap` filter.

The natural first move is to work out which Python is "the" Python —
`/usr/bin/python3` is macOS's 3.9.6, and there's a Homebrew `python@3.11`
as well. **That question is a dead end**, and chasing it is the actual
trap. In this instance nothing needed fixing at all: the filter already
worked.

### What's actually happening

`pkgs.ansible` is a `buildPythonApplication`. Its `bin/ansible` is a bash
wrapper that only touches `$PATH`; the real entrypoint is the sibling
`bin/.ansible-wrapped`, whose first lines hard-code the entire import path:

```python
#!/nix/store/fj9h…-python3-3.13.15/bin/python3.13
import sys;import site;import functools;…
functools.reduce(lambda k, p: site.addsitedir(p, k), [
  '/nix/store/…-python3.13-ansible-core-2.21.1/lib/python3.13/site-packages',
  '/nix/store/…-python3.13-ansible-13.7.0/lib/python3.13/site-packages',
  '/nix/store/…-python3.13-netaddr-1.3.0/lib/python3.13/site-packages',
  …], site._init_pathinfo());
```

Three consequences, and the first is the general rule:

- **The interpreter is private and the path is closed.** Ansible runs on its
  own nix Python 3.13.15, which is on nobody's `$PATH`. Whichever `python3`
  you'd have found is irrelevant — so is whichever `pip3` goes with it.
- **The wrapper exports `PYTHONNOUSERSITE`.** Even a `pip install --user`
  against the *correct* interpreter would be ignored by design.
- **netaddr was already there.** nixpkgs propagates it as an `ansible.utils`
  dependency, so the `pip install` the README asks for was never needed.

Collections are likewise already present. `pkgs.ansible` is the full
**ansible 13.7.0** bundle, not bare ansible-core — note that
`readlink -f $(which ansible)` lands in the *ansible-core* store path, which
makes it look core-only. That's expected: the bundle ships collections and no
executables, so the profile's `bin/ansible` is symlinked from the core
derivation it propagates. All three of the `turingpi` repo's
`collections/requirements.yml` entries ship in it:

| Collection | Version |
|---|---|
| `ansible.posix` | 2.2.0 |
| `ansible.utils` | 6.0.2 |
| `community.general` | 12.6.1 |

### Fix

There was nothing to fix here, so the "fix" is the diagnosis that stops you
inventing a problem. Read the real import path before touching anything:

```bash
head -3 "$(dirname "$(readlink -f "$(which ansible)")")/.ansible-wrapped"
```

That single line shows both the interpreter and every directory it will
import from. Then confirm the module end-to-end rather than by proxy — a bare
`python3 -c 'import netaddr'` tests the *wrong* interpreter and will mislead
you:

```bash
cat > /tmp/ipwrap-check.yml <<'YAML'
- hosts: localhost
  connection: local
  gather_facts: false
  become: false
  tasks:
    - debug:
        msg: "{{ '2001:db8::1' | ansible.utils.ipwrap }}"
YAML
ansible-playbook -i localhost, /tmp/ipwrap-check.yml   # => [2001:db8::1]
```

If a module genuinely *is* missing, the declarative fix is
`pkgs.ansible.overridePythonAttrs` to extend the propagated inputs — **not**
adding `pkgs.python3Packages.<module>` to `home.packages`, which would be
inert for exactly the reasons above.

### Prevention

**Don't run `ansible-galaxy collection install -r collections/requirements.yml`.**
It writes to `~/.ansible/collections`, which takes precedence over the bundled
copies — you'd silently run versions outside `flake.lock` while the nix ones
sit unused. Keep that directory absent, and check it first if a collection
version ever looks wrong:

```bash
ls -A ~/.ansible/collections 2>/dev/null || echo "(absent — good)"
ansible-galaxy collection list    # paths should all be /nix/store/…
```

The same reasoning applies to every nix-installed Python application, not
just ansible — `awscli2` and `opencode` have the same closed import path. The
general signal is a tool whose documentation assumes it shares a
system-wide `site-packages`. Under nix it never does.

## Claude Code fails with "SSL certificate verification failed" after a flake update

### Symptom

Every Claude Code session dies immediately on the first request:

```
API Error: Unable to connect to API: SSL certificate verification failed. Check your proxy or corporate SSL certificates
```

Hit on `Andrews-MacBook-Pro-M3`, 8 Nov 2026, after `nix flake update` +
`darwin-rebuild switch`. `git restore flake.lock` and a second switch
appeared to fix it.

**That conclusion was wrong, and it is an expensive one to hold** — it
implies the lockfile can never be updated again. The revert cost a ~20
minute rebuild and changed nothing that could affect TLS. The cause was
never identified; the timing was coincidental. Everything below is the
evidence that rules this repo out, so the next occurrence isn't
misattributed the same way.

### What's actually happening

Not the trust store. **Claude Code's CA roots are compiled into its Bun
binary** and are immune to every certificate variable nix sets:

```bash
CLAUDE=/etc/profiles/per-user/adbell/bin/claude
# all three print PONG — the env vars are simply ignored
NIX_SSL_CERT_FILE=/dev/null $CLAUDE -p 'reply with exactly: PONG'
SSL_CERT_FILE=/dev/null     $CLAUDE -p 'reply with exactly: PONG'
```

`NIX_SSL_CERT_FILE` is set on this machine (by the Nix *installer*'s
`/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`, not by
nix-darwin — which is why it won't show up when grepping a generation's
`/etc`). Claude ignores it anyway. `NODE_EXTRA_CA_CERTS` *is* read, but
it is **additive** — pointed at garbage it warns and still connects:

```
warn: ignoring extra certs from /dev/null, load failed: error:10000009:SSL routines:…
```

So no nixpkgs `cacert`/`nss-cacert` bump can ever produce this error. In
this incident the lockfile did move `nss-cacert` 3.126 → 3.131.1, which
looks damning until you read the diff: it removes three eMudhra roots and
adds nothing. `api.anthropic.com` chains to **Google Trust Services WE1 →
GTS Root R4**, present in both, and both bundles validate it at
`ssl_verify=0`.

Not the package either. The two generations' Claude binaries were
**byte-identical**:

| | gen 93 (updated, broke) | gen 94 (reverted, worked) |
|---|---|---|
| `darwin-system` | `26.05.d31953c` | `26.05.c3e90c8` |
| `.claude-wrapped` SHA-256 | `fcbe0b8d4757…` | `fcbe0b8d4757…` |
| version in transcripts | 2.1.223 | 2.1.223 |
| `settings.json` | identical content | identical content |
| plugin dir | identical content | identical content |

And not store-path churn. A flake update gives every rebuilt package a new
`/nix/store` path, which is a plausible trigger for anything keying on
executable path — a Little Snitch rule, for instance. It wasn't that here:
`op` is also a nix binary, its path *also* changed in gen 93
(`j5bccqgg…` → `n7di7gg6…`), and `op read "op://…"` succeeded during the
failure window. Little Snitch also turned out to hold **no rules
referencing any `/nix/store` path at all**, and being a connection
firewall rather than a TLS-inspecting proxy it cannot make a certificate
fail validation — only make a connection fail.

Also checked and clear: no MITM root CA in the System or login keychain,
no system proxy (`scutil --proxy` empty), no `ANTHROPIC_BASE_URL`
override, and no certificate or proxy variable in either generation's
`/etc`, `.zshenv`, `.zshrc`, `hm-session-vars.sh`, or the machine-local
`~/.config/zsh/{local,secrets}.zsh` overlays.

What remains is a genuine certificate rejection that nothing in the
machine's *configured* state explains — most likely transient and
endpoint-specific, which fits `op` reaching 1Password fine while Claude
could not reach `api.anthropic.com`.

### Fix

There is nothing to fix in this repo, so the fix is the diagnosis that
stops you reverting the lockfile. Run this **while it is failing** — it
names an interceptor directly:

```bash
echo | openssl s_client -connect api.anthropic.com:443 \
  -servername api.anthropic.com 2>/dev/null \
  | grep -E '^ *[0-9] [si]:|Verify return'
```

Healthy output is exactly:

```
 0 s:CN=api.anthropic.com
 1 s:C=US, O=Google Trust Services, CN=WE1
 2 s:C=US, O=Google Trust Services LLC, CN=GTS Root R4
Verify return code: 0 (ok)
```

Any other issuer is something intercepting TLS, and the subject line says
what. Also capture `env | grep -i proxy` and `claude --debug` at the time —
both are gone once the window closes, which is why this incident stayed
unexplained.

### Prevention

**Don't revert `flake.lock` as a first move.** Confirm the update actually
changed the thing you suspect first. The generation forensics below are
reusable for any "the flake update broke X" claim, and both old generations
remain on disk until garbage collection.

Find the generations and what moved between them:

```bash
ls -lt /nix/var/nix/profiles/system-*-link | head        # dates + darwin-system rev
nix store diff-closures /nix/var/nix/profiles/system-94-link \
                        /nix/var/nix/profiles/system-93-link
```

`diff-closures` reports only version *changes*, so a package it omits is
identical. To compare a specific binary, resolve it in each generation and
hash it — same version can still mean a rebuild, and a matching hash ends
the argument:

```bash
for g in 94 93; do
  nix-store -qR /nix/var/nix/profiles/system-$g-link | grep 'claude-code-[0-9]'
done
shasum -a 256 /nix/store/<gen94>-claude-code-*/bin/claude \
              /nix/store/<gen93>-claude-code-*/bin/claude
```

User-facing config lives in `home-manager-files`; diff the whole tree
rather than guessing which file matters:

```bash
diff -rq /nix/store/<a>-home-manager-files /nix/store/<b>-home-manager-files
```

Date the failure window from Claude's own transcripts — **timestamps are
UTC**, so add 11 hours for AEDT. A failed request records model
`<synthetic>`, Claude's marker for a locally generated error that never
reached the API, which distinguishes "could not connect" from "the model
replied badly":

```bash
grep -l 'SSL certificate verification failed' ~/.claude/projects/*/*.jsonl
```

Note `darwin-rebuild switch` also runs `brew bundle` with
`onActivation.upgrade = true`, so an activation changes things *outside*
the nix store that a lockfile revert will **not** undo. Here it upgraded
`ca-certificates`, `openssl@4`, `docker-desktop` and others at 15:21–15:24,
minutes after the switch — worth checking, and worth remembering that a
revert is not a rollback of it:

```bash
for d in /opt/homebrew/Caskroom/* /opt/homebrew/Cellar/*; do
  echo "$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$d")  $(basename "$d")"
done | sort | tail -20
```

## Adding new entries

When you hit a failure mode that took non-obvious diagnosis and you
think you'll (or someone else will) hit it again:

1. Add a section here using the **Symptom → What's actually happening →
   Fix → Prevention** shape. Include the *literal error text* so future
   searches land here.
2. Add a short quick-reference version under `## Troubleshooting` in
   `CLAUDE.md`, cross-linking to the full section here.
3. Where relevant, keep the recipe *machine-specific* by naming the host
   configs it applies to — some workarounds are safe on one machine and
   destructive on another (see the cleanup-mode table above for an
   example).
