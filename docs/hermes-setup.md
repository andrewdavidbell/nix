# Hermes Setup (Andrews-MacBook-Pro-M3)

Hermes is a Nous Research desktop AI agent (self-improving via
runtime skill generation) that sits alongside Claude Code and OpenCode
as another agent runtime. It calls out to a model backend of your
choice — [Nous Portal](https://portal.nousresearch.com/) for one-OAuth
access to 300+ models, a direct provider API (Anthropic, OpenAI,
OpenRouter, etc.), or a local endpoint (Ollama, LM Studio). Installed
on the personal M3 only — exploratory tool, and any paid backend is
billed to a personal account.

The desktop app itself is nix-installed via the `hermes-desktop`
Homebrew cask in `darwinConfigurations/Andrews-MacBook-Pro-M3.nix`.
Everything else — auth, MCP wiring, skills seeding — is machine-local
post-install, documented here. This mirrors the "install via nix,
configure by hand" split used for eBay and Obsidian in
`docs/mcp-manual.md`.

**Why not nix-manage the config**: Hermes stores everything under
`~/.hermes/`, and both `hermes config set` and `hermes mcp add` write
directly to `~/.hermes/config.yaml`. A read-only symlink into the nix
store would break the CLI. Hermes's config format also has no
`include`/`import` directive, so the "managed base + writable local
overlay" pattern in `docs/patterns.md` doesn't apply. If Hermes proves
useful enough to warrant a `forHermes` module in `agentic-config`,
that's a follow-on decision — the module would need an activation
script that re-runs the MCP-add commands idempotently rather than
symlinking config files.

---

## Prerequisites

- **`Hermes.app`** installed via `darwin-rebuild switch`. Confirm with
  `ls /Applications/Hermes.app`.
- **A model backend of your choice.** See step 2 — Nous Portal is the
  easiest onboarding, but not required.

---

## Steps

### 1. Locate the CLI

After first launching `Hermes.app` (which may install the `hermes`
CLI shim during onboarding):

```bash
which hermes
```

If nothing is on `$PATH`, run the upstream installer:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

Note the install location — most likely `~/.hermes/bin/hermes` per
Hermes's default `HERMES_HOME` layout. If it lands somewhere not
already on `$PATH`, add the directory to `home.sessionPath` in
`homeConfigurations/adbell.nix` (currently: `~/.local/bin`,
`~/.rd/bin`) and rebuild — the install itself stays off-repo.

### 2. Configure a model backend

`hermes model` opens an interactive wizard covering all four paths
below — OAuth, API keys, custom endpoints. `hermes config set …`
handles individual field edits. Both persist to `~/.hermes/config.yaml`
(non-secret settings) and `~/.hermes/.env` (secrets). Editing those
files by hand is also fine — `config.yaml` is the source of truth.

Pick the option that matches your existing accounts:

#### Option A — Nous Portal (easiest, aggregates 300+ models)

```bash
hermes setup --portal
```

One OAuth flow. Portal subscribers also get 10% off token-billed
providers. Writes `~/.hermes/auth.json` (Portal session state) and
Portal credentials into `~/.hermes/.env`.

#### Option B — Anthropic direct (if you already have API access)

`~/.hermes/config.yaml`:
```yaml
model:
  provider: "anthropic"
  default: "claude-sonnet-4-6"
```

`~/.hermes/.env`:
```
ANTHROPIC_API_KEY=sk-ant-...
```

Or use `hermes model` for the OAuth path if you have a Claude Max plan
with extra usage credits.

#### Option C — OpenRouter (single key, many models)

`~/.hermes/config.yaml`:
```yaml
model:
  provider: "openrouter"
  default: "anthropic/claude-sonnet-4"
```

`~/.hermes/.env`:
```
OPENROUTER_API_KEY=sk-or-...
```

OpenRouter is Hermes's default provider when no other config is
present.

#### Option D — Local endpoint (Ollama / LM Studio, offline-capable)

Ollama:
```yaml
model:
  default: qwen2.5-coder:32b
  provider: custom
  base_url: http://localhost:11434/v1
  context_length: 64000
```

LM Studio:
```yaml
model:
  default: your-model-name
  provider: custom
  base_url: http://localhost:1234/v1
```

No API key needed for keyless local servers. Hermes needs **≥ 64k
context** for tool use; small local models likely won't cut it for
serious agent work.

None of `.env` / `auth.json` / `config.yaml` should be committed or
symlinked from the repo — machine-local.

### 3. Wire MCP servers (pick what matches how you'll use Hermes)

The shared MCPs in `agentic-config/data/mcp-servers.nix` (`nixos`,
`context7`, `aws-documentation`) are all software-development
flavoured. Don't wire them into Hermes unless you actually plan to do
coding work there — every registered MCP costs tokens (tool
descriptions loaded on every prompt) whether you use it or not.

Verify what's currently wired at any time with `hermes mcp list`.

#### Recommended for a note-taking / knowledge-worker Hermes: Obsidian

Same Local REST API endpoint you already have wired for Claude Code
and OpenCode (see `docs/mcp-manual.md`), reused for Hermes. Hand-edit
`~/.hermes/config.yaml` and add:

```yaml
mcp_servers:
  obsidian:
    url: http://127.0.0.1:27123/mcp/
    headers:
      Authorization: Bearer YOUR-API-KEY
```

(`hermes mcp add` documented flags cover stdio servers only. For
HTTP-transport servers, edit `config.yaml` directly.)

The API key is the same one you configured in Obsidian's Local REST
API with MCP plugin. Endpoint is loopback-only, so HTTP-not-HTTPS is
fine.

#### If you're using Hermes for coding: the shared list

```bash
hermes mcp add nixos --command uvx --args mcp-nixos
hermes mcp add context7 --command npx --args '-y @upstash/context7-mcp'
hermes mcp add aws-documentation --command uvx --args awslabs.aws-documentation-mcp-server
```

No automatic sync with `agentic-config` — if the shared list grows,
re-run the corresponding `hermes mcp add` here.

### 4. Seed the shared skills (optional, coding-flavoured)

`agentic-config`'s current skills (`tdd`, `design-patterns`) are also
coding-shaped, so the same "pick what matches your use" applies. Skip
this step if Hermes isn't for coding — Hermes generates its own skills
at runtime anyway (that's its self-improvement pitch).

If you do want them, symlink each skill directory from the checkout
into `~/.hermes/skills/`, subdir-per-skill so Hermes-generated skills
alongside don't collide:

```bash
mkdir -p ~/.hermes/skills
for d in ~/Source/agentic-config/skills/*/; do
  name=$(basename "$d")
  [ -e ~/.hermes/skills/"$name" ] || ln -s "$d" ~/.hermes/skills/"$name"
done
```

Symlinks point into the git checkout (not the nix store), so bumps to
`agentic-config` are picked up on next Hermes launch without a
rebuild.

### 5. SOUL.md (optional)

Hermes's equivalent of Claude Code's `CLAUDE.md` — global "identity /
voice" file at `~/.hermes/SOUL.md`. Start without one; Hermes has a
sensible default. Only introduce a `SOUL.md` if / when there's a
Hermes-specific voice worth pinning. Do not symlink Claude Code's
`CLAUDE.md` — different tool, different voice, and the file is Nous-
opinion-shaped rather than Anthropic-opinion-shaped.

---

## Uninstall

```bash
brew uninstall --cask hermes-desktop --zap
```

`--zap` also removes `~/.hermes/`, `~/Library/Application Support/Hermes/`,
`~/Library/Caches/com.nousresearch.hermes.setup`, and the plist. Also
remove the `"hermes-desktop"` line from
`darwinConfigurations/Andrews-MacBook-Pro-M3.nix` so it doesn't come
back on next activation.

---

## References

- Landing / download: https://hermes-agent.nousresearch.com/
- Config layout: https://hermes-agent.nousresearch.com/docs/user-guide/configuration
- MCP wiring: https://hermes-agent.nousresearch.com/docs/guides/use-mcp-with-hermes
- Skills format: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills
