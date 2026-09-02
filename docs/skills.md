## Agent Skills: sources and per-harness locations

Skills follow a spec that most modern agent harnesses can consume,
but each harness reads from its own directory. To avoid drift, the
pattern used here is: **one canonical source per skill at
`~/.agents/skills/<name>/`, with per-harness symlinks pointing at
it where needed**.

`~/.agents/skills/` is the agent-agnostic path (matches the
AGENTS.md convention: no vendor prefix). OpenCode reads it natively;
Claude Code needs a symlink from `~/.claude/skills/<name>` to it;
Hermes has its own hub layout and stays out-of-band (see below).

### Two sources

- **Bespoke / shared:** `agentic-config/skills/*`. Written portable
  (no `Claude Code`-only language, no Claude-Code-only frontmatter
  extensions), so the same directory can be surfaced to any harness.
- **Third-party:** cloned into `~/Documents/Local Source/<repo>/`.
  Each skill lives in a subdirectory of that clone. Symlink out of
  the clone; never copy — `git pull` in the clone then propagates
  upstream fixes to every harness at once.

### Per-harness locations

| Harness | Reads from | How it gets populated |
| --- | --- | --- |
| OpenCode (≥ 1.15) | `~/.agents/skills/<name>/` (also `~/.config/opencode/skills/`, `~/.claude/skills/`) | Canonical path — no wiring needed |
| Claude Code | `~/.claude/skills/<name>/` only | `programs.claude-code.skills.*` in `agentic-config` for bespoke; symlink `~/.claude/skills/<name>` → `~/.agents/skills/<name>` for third-party |
| Hermes | `~/.hermes/skills/<category>/<name>/` (hub-managed) | Out-of-band — install via `hermes skills install <identifier>`, not by symlinking. See "Hermes" below |
| Open WebUI | Not file-based | Import each skill via the Open WebUI admin panel per install |

### Third-party skills: recipe

```bash
# Clone once into your source directory.
git clone <upstream> ~/Documents/Local\ Source/<repo>

# Land the canonical link.
ln -s "$HOME/Documents/Local Source/<repo>/Skills/<skill>" ~/.agents/skills/<skill>

# Point Claude Code at it (OpenCode already sees ~/.agents/skills/).
ln -s ~/.agents/skills/<skill> ~/.claude/skills/<skill>
```

Currently linked on this machine (Andrews-MacBook-Pro-M3):

- `~/.agents/skills/extract-wisdom` →
  `~/Documents/Local Source/sams-agentic-coding/Skills/extract-wisdom`
- `~/.agents/skills/skill-creator-primer` →
  `~/Documents/Local Source/sams-agentic-coding/Skills/skill-creator-primer`
- `~/.claude/skills/extract-wisdom` → `~/.agents/skills/extract-wisdom`
- `~/.claude/skills/skill-creator-primer` → `~/.agents/skills/skill-creator-primer`

Other machines: none.

### Bespoke skills (`agentic-config`)

`agentic-config` currently registers bespoke skills into
`~/.claude/skills/` via `programs.claude-code.skills.*`, and also
publishes the source subtree to `~/.local/share/agentic-skills/` via
`modules/skills.nix`. That XDG path is **not** on any harness's
discovery list — it's currently unused.

Cleaner future shape (a change in `agentic-config`, not this repo):
retarget `modules/skills.nix` at `~/.agents/skills/`. Bespoke skills
then land on the canonical path directly, OpenCode picks them up
without symlink, and Claude Code's per-skill registration can be
kept as-is or reduced to a symlink loop from `~/.claude/skills/`
into the canonical dir.

### Hermes

Hermes is deliberately out-of-band:

- Its global path is hard-coded to `~/.hermes/skills/` and the layout
  is **categorised** (`~/.hermes/skills/<category>/<name>/SKILL.md`)
  rather than the flat `<name>/SKILL.md` used by the spec.
- It ships its own package-manager (`hermes skills install/browse/
  search/tap`) with a hub lockfile at `~/.hermes/skills/.hub/`. Third
  parties are meant to be installed with `hermes skills install
  <identifier>` (GitHub-style or URL), which copies into the
  categorised layout — bypassing the hub with hand-placed symlinks
  is likely to be silently ignored.
- `~/.agents/skills/` is recognised only per-project after `hermes
  skills trust <repo>` — no global read.
- Many popular skills ship as builtins already (`humanizer` in
  `creative`, `test-driven-development` in `software-development`,
  `claude-code`/`opencode`/`codex` in `autonomous-ai-agents`). Check
  `hermes skills list` before installing anything.

`docs/hermes-setup.md` §4 currently suggests flat symlinks from
`agentic-config/skills/` into `~/.hermes/skills/`. That recipe was
written before this discovery model was verified; it likely doesn't
work as written and should be revisited (either delete it, or
replace with `hermes skills install` for equivalents).

### Open WebUI

Open WebUI has no on-disk skills path — skills are imported through
the admin UI and stored in its database. Every install imports
separately; no sync with the file-based locations above.

### When to write vs symlink

- **New bespoke skill** → add under `agentic-config/skills/<name>/`
  and register in `modules/claude-code.nix`. Write portable — see
  `Write Skills to Run Across Agents` in Sam's `skill-creator-primer`.
  For Hermes, publish through a tap or use `hermes skills install`;
  don't try to symlink.
- **Adopting a third-party skill** → clone the upstream into
  `~/Documents/Local Source/`, land the canonical link at
  `~/.agents/skills/`, and symlink from `~/.claude/skills/` per the
  recipe above. Do not duplicate into `agentic-config` — that repo
  is for skills you own.

### Related

- `docs/hermes-setup.md` — Hermes setup (§4 pending revisit per above).
- `docs/patterns.md` — the managed-base/writable-overlay pattern
  used elsewhere for tools that don't allow read-only config.
- `agentic-config/modules/skills.nix` — the XDG publishing module
  (candidate for retarget at `~/.agents/skills/`).
