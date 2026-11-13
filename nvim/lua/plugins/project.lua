-- Maintained fork of ahmedkhalf/project.nvim, which is abandoned at its
-- Apr 2023 commit. Upstream's find_lsp_root() calls vim.lsp.buf_get_clients()
-- (deprecated since nvim 0.10, scheduled for removal in 0.12 — the version
-- `programs.neovim` ships), so it warns on the first LSP attach of a session.
-- The fork uses vim.lsp.get_clients() and renames the module project_nvim ->
-- project; `main` is set so lazy.nvim calls setup() on the right one.
--
-- Defaults match upstream's behaviour used here: manual_mode = false,
-- scope_chdir = "global", lsp.enabled = true — so cwd still follows the
-- project root automatically.
return {
    "DrKJeff16/project.nvim",
    main = "project",
    opts = {},
}
