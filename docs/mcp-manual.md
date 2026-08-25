# Manual MCP Server Recipes

MCP servers wired into every machine via `agentic-config` live in that
flake's `data/mcp-servers.nix` and reach both Claude Code and OpenCode
automatically. Some MCP servers don't fit that path — because they use
HTTP transport (not yet modelled by the module), because they need
per-machine secrets, or because they're only useful in one client (e.g.
Claude Desktop). Those live here as one-time manual adds, documented so
future-you knows what's plumbed on each machine and how to re-plumb it.

---

## Obsidian (Claude Code + OpenCode)

### Prerequisites

Install the **Local REST API with MCP** community plugin in Obsidian
(Adam Coddington's `coddingtonbear/obsidian-local-rest-api`). The plugin
ships its own built-in MCP server; no external stdio process is needed.

In Obsidian: Settings → Community plugins → Local REST API with MCP.
Copy the API key it generates. Also enable **HTTP server** in that
settings pane — the HTTPS endpoint uses a self-signed cert which most
MCP clients reject by default; the HTTP endpoint on `127.0.0.1` is
loopback-only so the security cost is negligible.

### Endpoint

- HTTP (recommended):  `http://127.0.0.1:27123/mcp/`
- HTTPS (self-signed): `https://127.0.0.1:27124/mcp/`

Auth: `Authorization: Bearer <API-KEY>`.

### Claude Code

Run once per machine:

```bash
claude mcp add \
  --transport http \
  --header "Authorization: Bearer YOUR-API-KEY" \
  obsidian http://127.0.0.1:27123/mcp/
```

This lands in `~/.claude.json` under `mcpServers.obsidian`. Verify with
`/mcp` inside Claude Code — the entry should show as connected while
Obsidian is running.

### OpenCode

Add to `~/.config/opencode/local.jsonc` (the writable overlay — see
`docs/patterns.md` "Managed base + writable local overlay"):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "obsidian": {
      "type": "remote",
      "url": "http://127.0.0.1:27123/mcp/",
      "enabled": true,
      "headers": {
        "Authorization": "Bearer YOUR-API-KEY"
      }
    }
  }
}
```

If the file already has a `mcp` key, merge into it rather than replacing.

### Notes

- The API key is per-install: a fresh Obsidian install generates a new
  key. Every machine needs its own add.
- The endpoint is only reachable while Obsidian is running. Both Claude
  Code and OpenCode will retry on next tool call.
- Requires Obsidian ≥ the plugin's minimum version (check the plugin's
  README if the connection fails on an older Obsidian).

---

## eBay listings (Claude Desktop only)

### Prerequisites

Sign up at [developer.ebay.com](https://developer.ebay.com/) and create
an application. Copy three credentials from the developer dashboard:

- **App ID** (Client ID)
- **Cert ID** (Client Secret)
- **Dev ID**

App-level credentials are fine for search; no per-user OAuth needed.

### Install `hanku4u/ebay-mcp-server`

Python-based. Install into an isolated uv-managed venv so the server's
dependencies don't collide with anything else:

```bash
mkdir -p ~/Source/mcp
cd ~/Source/mcp
git clone https://github.com/hanku4u/ebay-mcp-server.git
cd ebay-mcp-server
uv sync                            # if the repo ships pyproject.toml + uv.lock
# — or —
uv venv && uv pip install -e .     # fallback for repos with only pyproject.toml
```

Confirm the console entry point (`uv run ebay-mcp` or
`uv run python -m ebay_mcp` — the repo's README is authoritative).

### Wire into Claude Desktop

Claude Desktop → Settings → Developer → **Edit Config**. This opens
`~/Library/Application Support/Claude/claude_desktop_config.json` in
the default editor. Add under `mcpServers`:

```json
{
  "mcpServers": {
    "ebay": {
      "command": "uv",
      "args": [
        "run",
        "--directory",
        "/Users/adbell/Source/mcp/ebay-mcp-server",
        "python",
        "-m",
        "ebay_mcp"
      ],
      "env": {
        "EBAY_APP_ID": "your-app-id",
        "EBAY_CERT_ID": "your-cert-id",
        "EBAY_DEV_ID": "your-dev-id"
      }
    }
  }
}
```

Preserve everything else in the file (`preferences`,
`coworkUserFilesPath`, etc.) — Claude Desktop stores UI state there
too. Merge into `mcpServers`, don't replace the whole file.

Restart Claude Desktop. The server should appear under Settings →
Developer with a green status dot.

### Scope

This server exposes eBay's **Buy Browse APIs** — search listings, item
details, watchlists, price tracking. It does **not** place bids.
Bidding requires the eBay Buy Offer API's `placeProxyBid`, which is a
Limited Release available only to eBay-approved developers and needs
per-user OAuth. No off-the-shelf MCP server implements bidding as of
this doc's writing. Place bids manually in the browser.

---

## Why not nix-manage these?

- **Secrets.** Both the Obsidian API key and the eBay credentials are
  machine-local. Getting them into nix would mean plumbing 1Password
  references through activation scripts. Fine as a pattern for values
  used by many tools, overkill for one-off entries.
- **HTTP transport (Obsidian).** `agentic-config`'s current
  `modules/mcp.nix` only models stdio servers (`{ command, args, env }`).
  Extending it to support `type = "http" | "sse"` with `url` and
  `headers` is a reasonable follow-on if HTTP MCP entries multiply, but
  not worth the machinery for one.
- **Client-specific (eBay).** Claude Desktop's config file also holds
  UI state, so a home-manager symlink would clobber it. A merge-on-
  activation script is possible but fiddly, and eBay is only useful in
  the desktop app anyway.

When adding a new MCP server, the decision:

1. Direct-process (`command` + `args`), no secrets, useful everywhere →
   add to `agentic-config/data/mcp-servers.nix`.
2. Anything else → add here, one section per server.
