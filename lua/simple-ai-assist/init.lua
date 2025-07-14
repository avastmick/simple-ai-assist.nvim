local M = {}

local config = require("simple-ai-assist.config")
local ui = require("simple-ai-assist.ui")

function M.setup(opts)
    config.setup(opts)

    vim.api.nvim_create_user_command("SimpleAIAssist", M.trigger_assistant, {
        desc = "Trigger Simple AI Assistant"
    })

    local trigger_key = config.options.keymaps and config.options.keymaps.trigger
    if trigger_key then
        vim.keymap.set("v", trigger_key, M.trigger_assistant, {
            desc = "Trigger Simple AI Assistant"
        })
    end
end

function M.trigger_assistant()
    -- Store the current buffer
    local current_buf = vim.api.nvim_get_current_buf()

    -- Get the visual selection using getregion (available in newer Neovim)
    local ok, region = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
    local selected_text

    if ok and region then
        -- getregion returns a table of lines
        selected_text = table.concat(region, "\n")
    else
        -- Fallback: Get the unnamed register which should contain the selection
        -- First ensure we're in visual mode and yank
        vim.cmd('silent! normal! gvy')
        selected_text = vim.fn.getreg('"')
    end

    -- Get selection bounds for context
    local start_line = vim.fn.line("v")
    local end_line = vim.fn.line(".")

    -- Ensure start comes before end
    if start_line > end_line then
        start_line, end_line = end_line, start_line
    end

    -- Validate we have selected text
    if not selected_text or selected_text == "" then
        vim.notify("No code selected", vim.log.levels.WARN)
        return
    end

    -- Exit visual mode before showing the assistant
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

    -- Show the assistant with the selected text
    vim.schedule(function()
        ui.show_assistant(selected_text, {
            start_line = start_line - 1,
            end_line = end_line,
            buffer = current_buf
        })
    end)
end

return M
