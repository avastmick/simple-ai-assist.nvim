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
  -- Store the current buffer before any mode changes
  local current_buf = vim.api.nvim_get_current_buf()

  -- Get visual selection using vim.fn.getregion (more reliable)
  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")

  -- Ensure we have valid positions
  if not start_pos or not end_pos or start_pos[2] == 0 or end_pos[2] == 0 then
    vim.notify("Please select code in visual mode first", vim.log.levels.WARN)
    return
  end

  -- Swap positions if selection was made backwards
  if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
    start_pos, end_pos = end_pos, start_pos
  end

  -- Get the selected lines
  local lines = vim.api.nvim_buf_get_lines(current_buf, start_pos[2] - 1, end_pos[2], false)

  if #lines == 0 then
    vim.notify("No code selected", vim.log.levels.WARN)
    return
  end

  -- Handle column selection for single and multi-line selections
  if #lines == 1 then
    -- Single line selection
    lines[1] = string.sub(lines[1], start_pos[3], end_pos[3])
  else
    -- Multi-line selection
    lines[1] = string.sub(lines[1], start_pos[3])
    if lines[#lines] then
      lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
    end
  end

  -- Filter out any nil or empty lines from the selection
  local filtered_lines = {}
  for _, line in ipairs(lines) do
    if line then
      table.insert(filtered_lines, line)
    end
  end

  if #filtered_lines == 0 then
    vim.notify("No code selected", vim.log.levels.WARN)
    return
  end

  local selected_text = table.concat(filtered_lines, "\n")

  -- Exit visual mode
  vim.cmd("normal! <Esc>")

  ui.show_assistant(selected_text, {
    start_line = start_pos[2] - 1,
    end_line = end_pos[2],
    buffer = current_buf
  })
end

return M