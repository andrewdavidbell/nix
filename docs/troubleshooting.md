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
