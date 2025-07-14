local M = {}

local config = require("simple-ai-assist.config")
local ui = require("simple-ai-assist.ui")

function M.setup(opts)
  config.setup(opts)

  vim.api.nvim_create_user_command("SimpleAIAssist", function()
    M.trigger_assistant()
  end, {})

  if config.options.keymaps.trigger then
    vim.keymap.set("v", config.options.keymaps.trigger, function()
      M.trigger_assistant()
    end, { desc = "Trigger Simple AI Assistant" })
  end
end

function M.trigger_assistant()
  -- Store the current buffer
  local current_buf = vim.api.nvim_get_current_buf()
  
  -- Save the current z register to restore it later
  local saved_reg = vim.fn.getreg('z')
  local saved_regtype = vim.fn.getregtype('z')
  
  -- Get the actual selected text using the yank register
  -- First, yank the current selection to a temporary register
  vim.cmd('normal! "zy')
  
  -- Get the yanked text from register z
  local selected_text = vim.fn.getreg('z')
  
  -- Restore the original z register
  vim.fn.setreg('z', saved_reg, saved_regtype)
  
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