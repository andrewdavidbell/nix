# Agent Harness Onboarding

How to add or remove **MCP servers** and **skills** across the AI
harnesses on these machines, and what to do when you add a new harness.

The recurring question this file answers is *where does this change
belong* — the wrong layer either won't survive a rebuild or won't reach
the other machines.

Related: `docs/skills.md` (skill sources and per-harness paths),
`docs/mcp-manual.md` (one-off servers that can't be nix-managed),
`docs/patterns.md` (the two override patterns), `docs/troubleshooting.md`
(when a change lands on disk but the agent ignores it).

---

## Who owns what

| Layer | Owns | Change it by |
| --- | --- | --- |
| `agentic-config` flake | Agent *configuration*: MCP server list, skills, subagents, slash commands, baseline config files | Edit that repo, then bump the input here |
| This repo | Agent *packages* and which agents each machine runs | `home.packages` / Homebrew casks + `programs.agenticConfig.agents.*.enable` |
| The machine | Secrets, per-host endpoints, runtime state | Writable overlay files, off-repo |
| A project repo | Deviations scoped to one codebase | Project-local config, committed there |

Enabling an agent in this repo:

```nix
programs.agenticConfig = {
  skills.enable          = true;   # publish ~/.agents/skills/
  agents.claude.enable   = true;
  agents.opencode.enable = true;
  agents.kiro.enable     = true;   # MacBookPro only
};
```

The opencode module **asserts** `pkgs.opencode` is in `home.packages`
and fails the build with an explicit message if not. Kiro has no such
guard — it's a Homebrew cask, invisible to home-manager at evaluation
time, so enabling it without the cask lays down config nothing reads.

---

## MCP servers

### Adding one

Decision tree (the same one at the foot of `docs/mcp-manual.md`):

1. **Direct process (`command` + `args`), no secrets, useful
   everywhere** → add to `agentic-config/data/mcp-servers.nix`, bump
   the input here, rebuild. Reaches every harness on every machine.
2. **HTTP transport, secrets, or one client only** → it can't go in
   that list. Add a section to `docs/mcp-manual.md` with a per-machine
   recipe, and land it in the harness's writable slot
   (`~/.claude.json` via `claude mcp add`;
   `~/.config/opencode/local.jsonc` for opencode).
3. **Only relevant to one codebase** → project-scoped file, committed
   to that repo. See "Turning one off, per project" below.

The shared list currently holds `nixos`, `context7`,
`aws-documentation` and `headroom`. All run as direct processes, so the
list is portable across machines. `headroom` additionally needs its CLI
on `$PATH` — see `docs/headroom-setup.md`.

### Turning one off, everywhere on one machine

Override the server set in that machine's home config:

```nix
programs.agenticConfig.mcp.servers =
  builtins.removeAttrs (import "${inputs.agentic-config}/data/mcp-servers.nix")
    [ "context7" ];
```

This removes it from **every** harness on that machine. If you only
want it gone from one harness, use the per-project route instead, or
add a harness-specific option upstream.

### Turning one off, per project

Full table, gotchas and precedence rules live in `docs/patterns.md`
under "Per-project override (agent harnesses)". The short version:

**Kiro** — `.kiro/settings/mcp.json` in the project. No field merging,
so restate `command`/`args`:

```json
{ "mcpServers": { "context7": {
    "command": "npx", "args": ["-y", "@upstash/context7-mcp"],
    "disabled": true } } }
```

**opencode** — `opencode.json` in the project root. Deep-merges, so the
flag alone is enough:

```json
{ "mcp": { "context7": { "enabled": false } } }
```

**Claude Code** — `.mcp.json` can only *override*, not disable. Use the
settings list instead, in the project's `.claude/settings.json`:

```json
{ "disabledMcpServers": ["context7"] }
```

Note `disabledMcpjsonServers` is a *different* list that gates only
`.mcp.json` entries. The nix-provided servers arrive as **plugin**
servers, so `disabledMcpServers` is the one that applies.

### Runtime toggles

Only Claude Code has one that works: `/mcp` writes to `~/.claude.json`,
which is deliberately left writable. Kiro's MCP panel writes to
`~/.kiro/settings/mcp.json`, a read-only store symlink, so its toggles
fail silently. opencode has no runtime toggle at all.

---

## Skills

### Adding one

- **Bespoke (you own it)** → write it under `agentic-config/skills/<name>/`
  and register it there. Write portable: no harness-specific language or
  frontmatter extensions, so the same directory serves every harness.
- **Third-party** → clone upstream into `~/Documents/Local Source/<repo>/`,
  land the canonical link at `~/.agents/skills/<name>`, then symlink per
  harness. Never copy — `git pull` in the clone then propagates fixes
  everywhere at once. Full recipe in `docs/skills.md`.

Discovery paths differ per harness, which is why the canonical-path +
symlink shape exists:

| Harness | Global | Project |
| --- | --- | --- |
| opencode | `~/.agents/skills/`, `~/.claude/skills/`, `~/.config/opencode/skills/` | `.agents/skills/`, `.claude/skills/`, `.opencode/skills/` |
| Claude Code | `~/.claude/skills/` only | `.claude/skills/` |
| Kiro | `~/.kiro/skills/` only | `.kiro/skills/` |

opencode reads the canonical path natively; Claude Code and Kiro each
need a link. Kiro reads neither `~/.agents/skills/` nor
`~/.claude/skills/`, so third-party skills need one extra link there.

### Turning one off

**Claude Code** — `skillOverrides`, no file edit needed:

```json
{ "skillOverrides": { "extract-wisdom": "off" } }
```

Values: `"on"` (default), `"name-only"` (Claude sees the name only),
`"user-invocable-only"` (hidden from Claude, still in the `/` menu),
`"off"`. Put it in the project's `.claude/settings.json`, or
`~/.claude/settings.local.json` for machine-wide — **not**
`~/.claude/settings.json`, which is a managed store symlink. Editing
the skill's own frontmatter (`disable-model-invocation: true`) is not
an option for skills served from the store.

**opencode** — deny the permission in `opencode.json`:

```json
{ "permission": { "skill": { "extract-wisdom": "deny" } } }
```

**Kiro** — no documented disable mechanism; deletion is the only
supported route. Since workspace skills shadow global ones by name, a
same-named stub at `.kiro/skills/<name>/` should neutralise a global
skill per project — **untested here**, verify before relying on it.

---

## Onboarding a new harness

1. **Install the package.** nixpkgs → `home.packages` in the relevant
   home config. GUI app or absent from nixpkgs → Homebrew cask in the
   machine's `darwinConfigurations/<host>.nix`. Package choice is a
   machine concern and stays in this repo.
2. **Read its config docs before writing any nix.** You need three
   facts: the config file path(s), the precedence order between them,
   and whether merging is per-key or whole-entry. Everything else
   follows from those.
3. **Decide the pattern.** Does it have a global writable slot (env var
   or a `.local` sibling)? Then the managed-base/writable-overlay shape
   applies. Only a project-scoped file? Then the per-project override
   shape applies and the global file is purely declarative. Both are in
   `docs/patterns.md`.
4. **Check whether one file holds both declared config and runtime
   state.** If so, managing it declaratively will break the harness's
   own UI toggles — decide that trade-off deliberately and write it
   down. This is exactly the Kiro MCP situation.
5. **Write the module in `agentic-config`**, not here. Render
   `mcp.claudeShape` if the harness accepts the `{ mcpServers = … }`
   shape (Claude Code, LM Studio, omlx and Kiro all do); otherwise add
   a shape mapping in `modules/mcp.nix`.
6. **Add a build-time guard** asserting the binary is in
   `home.packages`, as the opencode module does — unless it's a cask,
   in which case say so in the module comment.
7. **Enable it** in the machine's home config, bump the flake input,
   `darwin-rebuild switch`.
8. **Verify on disk, then in the app.** `nix build` cannot catch a
   config the harness silently ignores. Restart the harness fully — a
   file appearing under a running instance is not the same as an edit
   to a file it already tracks.

### Sync obligations

- `homeConfigurations/tester.nix` mirrors `adbell.nix`, including the
  agent enables. The VM once silently failed to exercise the MCP wiring
  it existed to test, because the agent config had drifted. Keep them
  in step.
- `MacBookPro.nix` is a deliberately lean work profile and is **not** a
  sync target — apply shared changes there only where they fit.

---

## When it doesn't work

Diagnose cheapest-first — see `docs/troubleshooting.md`, "A newly-wired
agent appears to ignore its MCP servers and skills":

1. Fully restart the harness.
2. Check you're looking in the right UI (Kiro lists skills under
   **Agent Steering & Skills**).
3. Confirm activation ran at all — `readlink ~/.claude/settings.json`.
   A `brew bundle` failure aborts activation *before* home-manager
   links anything, so repo edits appear unapplied even though the build
   succeeded.
4. Only then suspect the config itself.
