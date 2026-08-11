# Patterns

Recipes for structuring configuration in this repo. Where
`docs/troubleshooting.md` covers *things that break*, this file covers
*shapes* — the way we tend to arrange declarative + writable config so
day-to-day tweaks don't require a `darwin-rebuild`.

---

## Managed base + writable local overlay

### When to use

You want a config file that is:

1. **Declarative and shared** — the shape and defaults live in the
   repo, sync across machines, are visible in git history.
2. **Locally editable per machine** — you can add machine-specific
   settings (new providers, credentials, per-host endpoints) without
   editing the repo or running `darwin-rebuild`.

Home-manager symlinks into `/nix/store/` are always read-only, so the
same file cannot be both managed and locally-writable. The pattern
splits it in two.

### Shape

- **Managed baseline:** the "real" config file, owned by home-manager
  via `xdg.configFile.<path>.source`. Read-only symlink into the Nix
  store. Change it in the repo, apply with `darwin-rebuild switch`.
- **Local overlay:** an *unmanaged* sibling file, writable, off-repo.
  Ensured to exist by a home-manager `activation` script that touches
  an empty JSON object if missing. Loaded via whatever mechanism the
  target tool provides — an env var, a fixed lookup path, etc. Merged
  over the baseline; conflicts resolved by the tool's own precedence
  rules.

The baseline holds the reproducible shared defaults. The overlay
holds the local override you'd otherwise be blocked from making.

### Example: opencode

Opencode's config precedence (docs: `https://opencode.ai/docs/config/`)
loads and **merges** in order (lowest → highest):

1. Remote / `.well-known/opencode`
2. Global — `~/.config/opencode/opencode.json(c)`
3. `OPENCODE_CONFIG` env var — custom file path
4. Project — `opencode.json(c)` in cwd
5. `.opencode/` directories
6. `OPENCODE_CONFIG_CONTENT` env — inline
7. Managed system prefs

The pattern maps to positions 2 (baseline) and 3 (overlay):

- **Baseline:** `~/.config/opencode/opencode.jsonc` — home-manager
  symlink to `opencode/opencode.jsonc` in this repo, wired up in
  every home config via `xdg.configFile."opencode/opencode.jsonc"`.
- **Overlay:** `~/.config/opencode/local.jsonc` — writable file
  outside `/nix/store/`. Pointed at by `OPENCODE_CONFIG`, set in each
  home config's `sessionVariables`. Touched to `{}` on activation if
  missing so opencode always finds valid JSON.

Result: to add e.g. a work-machine-only provider, edit
`~/.config/opencode/local.jsonc` directly. No repo edit, no rebuild.
If a setting settles and belongs everywhere, promote it into
`opencode/opencode.jsonc` in the repo (or a machine-specific
`opencode/opencode-<host>.jsonc` if only some hosts should get it).

### Applying to other tools

The same shape works whenever the target tool supports layered configs
or a custom-path override. Checklist:

1. Confirm the tool merges multiple config sources (not
   last-file-wins-and-replaces-everything). Read its docs for
   precedence order.
2. Identify the *low-precedence* slot for the managed baseline (usually
   a fixed user path like `~/.config/<tool>/config.<ext>`).
3. Identify a *higher-precedence* slot for the overlay — env var,
   `.local.<ext>` sibling, project-local file. Confirm it's optional
   / merged, not required.
4. Wire the baseline via `xdg.configFile` in the home config(s).
5. Wire the overlay via `sessionVariables` (env-var case) or the
   tool's own lookup path.
6. If the tool errors on missing overlay, add a home-manager
   `activation.<name>` script that touches a valid-empty version on
   first activation:

       activation.<name>Overlay = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
         overlay="${homeDirectory}/.config/<tool>/local.<ext>"
         if [ ! -e "$overlay" ]; then
           mkdir -p "$(dirname "$overlay")"
           echo '{}' > "$overlay"
         fi
       '';

### Existing precedent in this repo

- **Claude Code** already uses this shape natively:
  `~/.claude/settings.json` is managed (by the `agentic-config` flake
  input); writable local state lives in `~/.claude/settings.local.json`
  (git-ignored) and `~/.claude.json`. See the "Claude Code" section in
  `CLAUDE.md` for details.
- **Git identity** uses a variant: fixed contents live in the repo
  (`programs.git` in the home configs) and machine-local identity
  lives in `~/.gitconfig.local` via `programs.git.includes`. See the
  "Important Constraints" section in `CLAUDE.md`.

---

## Adding new patterns

When you find yourself using the same structural shape for a second
tool, document it here rather than re-deriving it. Each entry:

1. Uses the **When to use → Shape → Example → Applying to other
   tools** headings so entries are comparable.
2. Names the specific tools it applies to at the top so a Ctrl-F for
   the tool lands on the pattern.
3. Cross-links from the relevant `CLAUDE.md` section with a one-line
   pointer, so future Claude sessions notice the pattern exists.
