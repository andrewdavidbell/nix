# Baseline (managed) opencode config for every machine. The `mcp` key is not
# set here — it is merged in per-machine from `programs.agenticConfig.mcp.
# opencodeConfig` (see agentic-config/modules/mcp.nix), so all coding agents
# share one MCP server list.
#
# For local overrides that stay off-repo (e.g. private providers, per-machine
# tweaks), edit ~/.config/opencode/local.jsonc — opencode merges it on top
# because $OPENCODE_CONFIG points there.
{
  "$schema" = "https://opencode.ai/config.json";
  theme = "kanagawa";
}
