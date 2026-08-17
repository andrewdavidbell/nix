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
  provider = {
    lmstudio = {
      npm = "@ai-sdk/openai-compatible";
      name = "LM Studio (local)";
      options = {
        baseURL = "http://127.0.0.1:1234/v1";
      };
      models = {
        "glm-4.5-air-mlx" = { name = "GLM 4.5 Air"; };
        "qwen/qwen3-coder-30b" = { name = "Qwen 3 Coder 30b"; };
      };
    };
    # Ollama provider previously kept commented in opencode.jsonc; restore
    # here as a Nix comment when needed:
    #   ollama = {
    #     npm = "@ai-sdk/openai-compatible";
    #     name = "Ollama (local)";
    #     options.baseURL = "http://localhost:11434/v1";
    #     models = {
    #       "qwen3-coder:30b-a3b-q4_K_M" = {
    #         id = "qwen3-coder:30b-a3b-q4_K_M";
    #         name = "Qwen 3 Coder Q4";
    #         reasoning = true;
    #         tool_call = true;
    #       };
    #     };
    #   };
  };
}
