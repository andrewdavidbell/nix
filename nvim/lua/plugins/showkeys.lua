return {
    "nvzone/showkeys",
    cmd = "ShowkeysToggle",
    opts = {
        maxkey = 5
    },
    -- Guards an upstream crash: `vim.schedule callback: …/showkeys/utils.lua:58:
    -- Invalid 'win': Expected Lua number`.
    --
    -- clear_and_close() calls redraw() -> update_win_w() -> nvim_win_set_config(
    -- state.win, …) *before* checking state.win, and nils state.win itself two
    -- lines later. The timer callback is schedule_wrap'd, so timer:stop() cancels
    -- future firings but not one already queued on the scheduler — whenever
    -- something nils state.win first (a second queued callback, or the
    -- WinClosed/TabEnter autocmds calling close()), the queued one calls the API
    -- with nil. We see it because config/lazy.lua toggles showkeys on at startup,
    -- so it is armed from the first keypress of every session.
    --
    -- The wrapper applies the same guard upstream already uses in parse_key().
    -- Not stale code: byte-identical to nvzone/showkeys main (cb0a502, May 2025),
    -- so there is no version to update to — revisit if upstream fixes it.
    --
    -- `config` means setup() is ours to call; lazy.nvim only does that
    -- implicitly when `opts` is used without a `config` function.
    config = function(_, opts)
        require("showkeys").setup(opts)

        local utils = require("showkeys.utils")
        local state = require("showkeys.state")

        -- Read through the table rather than closing over the original, so the
        -- wrapper composes if upstream later adds its own guard.
        local unguarded = utils.clear_and_close
        utils.clear_and_close = function()
            if state.win then
                unguarded()
            end
        end
    end,
}
