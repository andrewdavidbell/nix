return {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
        require("nvim-treesitter").setup({
            ensure_installed = {
                "c", "lua", "vim", "vimdoc", "query", "markdown", "markdown_inline", "elixir", "heex", "javascript", "html",
            },
            auto_install = true,
            sync_install = false,
        })

        -- Highlighting and indent are now configured via vim.treesitter
        vim.treesitter.language.register("markdown", "mdx")
    end
}
