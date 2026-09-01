# Headroom Setup (per machine)

[Headroom](https://github.com/headroomlabs-ai/headroom) is a token-
compression tool for LLM traffic — it can run as a proxy in front of a
model, wrap a subprocess, or expose itself as an MCP server so agents call
compression on tool outputs explicitly. This repo wires it in **MCP-first**
via `agentic-config/data/mcp-servers.nix`; proxy mode is a follow-on once
we know whether it earns its place.

The `headroom` CLI is not in nixpkgs and there's no Homebrew formula/cask
upstream. It ships as a Python package on PyPI (the npm package is SDK-only
— no binary). Install via `uv tool install` per machine — same shape used
for [Hermes](./hermes-setup.md), `nvm`, and `omlx`.

**Why not nix-manage the install:** headroom-ai isn't packaged for nix, and
its `[all]` extras pull in heavy ML deps that would be painful to track by
hash in this flake. `uv tool` gives an isolated, easily-updated venv on
`$PATH` without any of that; the CLAUDE.md "install via nix/OS, configure
by hand" pattern applies.

---

## Prerequisites

- `programs.uv.enable = true` on the target machine — already true for both
  `homeConfigurations/adbell.nix` and `homeConfigurations/MacBookPro.nix`.
- `~/.local/bin` on `home.sessionPath` — already true on both.

---

## Install

```bash
uv tool install --python 3.13 "headroom-ai[all]"
headroom doctor
```

`headroom doctor` should report all checks green. If it flags a missing
Python 3.13, install via `uv python install 3.13` and re-run the install
command.

## Verify the MCP wiring

The MCP entry lives in the shared list, so after
`sudo --set-home darwin-rebuild switch --flake .#<host>` picks up the
current `agentic-config` revision:

```bash
claude mcp list          # `headroom` should appear
```

End-to-end: in Claude Code, ask the agent to compress a large tool output
using the `headroom` MCP tool. It should return compressed text with a
token-savings figure. If it says the server is unavailable, the CLI likely
isn't on `$PATH` in the shell that spawned Claude — restart the shell so
the `home.sessionPath` update takes effect and try again.

## Not applied to the tester VM

The shared MCP list will reference `headroom` on `Testers-Virtual-Machine`
too, but the CLI isn't installed there by default (matches how
`~/.gitconfig.local` and `~/.config/git/allowed_signers` are seeded by
hand on each machine — see CLAUDE.md "Important Constraints"). Run the
install recipe above on the VM if you need to exercise the MCP path
there; otherwise the entry will show as unavailable, which is expected.

Alternatively, disable the entry per-machine by overriding the shared
attrset in the home config:

```nix
programs.agenticConfig.mcp.servers =
  builtins.removeAttrs config.programs.agenticConfig.mcp.servers [ "headroom" ];
```

---

## Update / uninstall

Update:

```bash
uv tool upgrade headroom-ai
```

Uninstall:

```bash
uv tool uninstall headroom-ai
```

To drop it entirely, also remove the `headroom` entry from
`~/Source/agentic-config/data/mcp-servers.nix`, commit + push, and bump the
flake input here with `nix flake lock --update-input agentic-config`.

---

## Follow-ons (deferred)

- **Proxy mode** — `headroom proxy` intercepts model requests transparently.
  Worth a look if MCP-driven compression proves reliably useful and the
  agent-driven overhead of "please call the compression tool first" becomes
  annoying. Would need per-agent env-var wiring (`ANTHROPIC_BASE_URL` and
  friends) and careful thought about what to do when the proxy misbehaves —
  hence not the starting shape.
- **A `forHeadroom` module in `agentic-config`** — only worth it if the
  install grows configuration state beyond "run once". Right now there's
  nothing to manage.
