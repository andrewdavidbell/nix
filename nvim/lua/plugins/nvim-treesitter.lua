return {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
        local parsers = {
            "c", "lua", "vim", "vimdoc", "query", "markdown", "markdown_inline",
            "elixir", "heex", "javascript", "html",
        }

        require("nvim-treesitter").install(parsers)

        vim.treesitter.language.register("markdown", "mdx")

        vim.api.nvim_create_autocmd("FileType", {
            callback = function(args)
                local ft = vim.bo[args.buf].filetype
                local lang = vim.treesitter.language.get_lang(ft) or ft
                -- Skip empty filetypes and plugin-owned floating buffers
                -- (e.g. "Showkeys") that will never have a parser.
                if not lang or lang == "" then return end
                -- language.add returns true on success, nil+err otherwise
                -- (see :h vim.treesitter.language.add). Do NOT wrap in pcall
                -- — pcall's own success bit is always true here, so the check
                -- below is what actually gates start().
                if not vim.treesitter.language.add(lang) then return end
                vim.treesitter.start(args.buf, lang)
                vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end,
        })
    end,
}
