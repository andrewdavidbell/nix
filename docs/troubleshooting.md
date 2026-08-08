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
