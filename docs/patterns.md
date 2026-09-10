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

- **Baseline:** `~/.config/opencode/opencode.jsonc` — a store symlink
  written by `agentic-config`'s `modules/agents/opencode.nix` via
  `home.file.".config/opencode/opencode.jsonc".text`. Owned by that
  flake, **not** by this repo; change it there and bump the input.
- **Overlay:** `~/.config/opencode/local.jsonc` — writable file
  outside `/nix/store/`. Pointed at by `OPENCODE_CONFIG`, set by the
  same module's `home.sessionVariables`. Seeded to `{}` by its
  `home.activation.opencodeLocalOverlay` script if missing, so
  opencode always finds valid JSON.

Result: to add e.g. a work-machine-only provider, edit
`~/.config/opencode/local.jsonc` directly. No repo edit, no rebuild.
If a setting settles and belongs everywhere, promote it into
`agents.opencode.settings` in `agentic-config`.

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

## Per-project override (agent harnesses)

Applies to: **Kiro**, **opencode**, **Claude Code**.

### When to use

The overlay pattern above needs a *global* writable slot. Some tools
don't have one — Kiro's only MCP config paths are the global
`~/.kiro/settings/mcp.json` (which we manage, so it's read-only) and a
workspace file. When there's no global overlay, the project-scoped
config is the escape hatch: it outranks the managed global everywhere
it exists, costs no rebuild, and is scoped to the repo you're in.

Reach for this when you want a server or skill off *here* but on
elsewhere. For "off on this machine, always", stay declarative and
change `agentic-config` instead.

### Shape

Managed global baseline (store symlink) + a small project-local file
committed to whichever repo needs the deviation. The harness merges
them, project-first.

### Example: disabling one MCP server per harness

| Harness | Project file | Merge granularity | Disable one server | Runtime toggle |
| --- | --- | --- | --- | --- |
| Kiro | `.kiro/settings/mcp.json` | whole server entry replaced | `"disabled": true` — restate `command`/`args` | **no** |
| opencode | `opencode.json(c)` in project root | deep, per-key | `{"mcp":{"<name>":{"enabled":false}}}` | no |
| Claude Code | `.mcp.json` + `.claude/settings.json` | whole server entry replaced | `disabledMcpServers` in `.claude/settings.json` | **yes** — `/mcp` |

Three gotchas behind that table:

- **Only opencode deep-merges.** It combines configs per-key, so a
  project file naming just `enabled` inherits `command`/`args` from the
  baseline. Kiro and Claude Code take the winning source's server entry
  wholesale, with no field merging — restate the full entry there.
- **Claude Code's `.mcp.json` can only override, not disable.**
  Switching a server off goes through settings lists, and which list
  depends on provenance: `disabledMcpjsonServers` gates only `.mcp.json`
  entries, while `disabledMcpServers` covers user-scope, plugin and
  connector servers. The servers `agentic-config` provides arrive as
  **plugin** servers (they surface as
  `mcp__plugin_claude-code-home-manager_<name>__<tool>`), so
  `disabledMcpServers` is the one that applies.
- **opencode's project config outranks `OPENCODE_CONFIG`.** Precedence
  is global < `local.jsonc` < project, so a project file beats the
  machine-local overlay, not the other way round.

### Why Claude Code has a working UI toggle and Kiro doesn't

Not luck, and it's the generalisable rule here. Claude Code separates
*declared config* (`~/.claude/settings.json`, which `agentic-config`
manages as a store symlink) from *runtime state* (`~/.claude.json`,
deliberately left writable) — and `/mcp` writes to the latter. Kiro
collapses both roles into `~/.kiro/settings/mcp.json`, so managing that
file declaratively necessarily costs the toggle.

**The overlay pattern works wherever a tool separates declared config
from runtime state, and fails wherever one file does both.** Check
which of the two you're dealing with before promising yourself a UI
toggle will still work post-activation.

### Applying to other tools

1. Find the tool's config precedence order and confirm project scope
   outranks the global path we manage.
2. Check merge granularity — per-key or whole-entry. If whole-entry,
   the project file must restate every field, and it will silently
   drift from the baseline when upstream changes.
3. Check whether "disable" is expressible in the same file at all, or
   whether it lives in a separate settings key (the Claude Code case).
4. Commit the project file. Unlike the writable overlay, this one is
   meant to be in version control and shared.

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
