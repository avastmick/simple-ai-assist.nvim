local M = {}

local config = require("simple-ai-assist.config")
local api = require("simple-ai-assist.api")

local state = {
  win = nil,
  buf = nil,
  code = "",
  context = nil,
  current_action = nil,
  response = nil
}

local function create_window()
  local opts = config.options.window
  local width = math.floor(vim.o.columns * opts.width)
  local height = math.floor(vim.o.lines * opts.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(state.buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(state.buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
  
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    border = opts.border,
    style = "minimal",
    title = " Simple AI Assistant ",
    title_pos = "center"
  })
  
  vim.api.nvim_win_set_option(state.win, "wrap", true)
  vim.api.nvim_win_set_option(state.win, "linebreak", true)
  vim.api.nvim_win_set_option(state.win, "cursorline", true)
end

local function render_content()
  vim.api.nvim_buf_set_option(state.buf, "modifiable", true)
  local lines = {}
  
  table.insert(lines, "## Selected Code:")
  table.insert(lines, "```")
  for line in state.code:gmatch("[^\n]+") do
    table.insert(lines, line)
  end
  table.insert(lines, "```")
  table.insert(lines, "")
  
  if not state.current_action then
    table.insert(lines, "## Choose an action:")
    for _, action in ipairs(config.options.actions) do
      table.insert(lines, string.format("  [%s] %s", action.key, action.label))
    end
    table.insert(lines, "")
    table.insert(lines, "Press a key to select an action, or [Esc] to cancel")
  elseif state.response then
    table.insert(lines, "## AI Response:")
    table.insert(lines, "")
    for line in state.response:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "[a] Accept  [r] Retry  [Esc] Cancel")
  else
    table.insert(lines, "## Processing...")
    table.insert(lines, "Waiting for AI response...")
  end
  
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(state.buf, "modifiable", false)
end

local function clear_keymaps()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_call(state.buf, function()
      vim.cmd("mapclear <buffer>")
    end)
  end
end

local function setup_keymaps()
  local buf = state.buf
  
  if not state.current_action then
    for _, action in ipairs(config.options.actions) do
      vim.keymap.set("n", action.key, function()
        state.current_action = action
        state.response = nil
        render_content()
        
        api.request_completion(action.prompt, state.code, function(response, error)
          if error then
            vim.notify("AI request failed: " .. error, vim.log.levels.ERROR)
            M.close()
            return
          end
          
          state.response = response
          render_content()
        end)
      end, { buffer = buf, nowait = true })
    end
  else
    vim.keymap.set("n", config.options.keymaps.accept, function()
      if state.response and state.context then
        local lines = {}
        for line in state.response:gmatch("[^\n]+") do
          table.insert(lines, line)
        end
        
        vim.api.nvim_buf_set_lines(
          state.context.buffer,
          state.context.start_line,
          state.context.end_line,
          false,
          lines
        )
        
        vim.notify("Changes applied!", vim.log.levels.INFO)
        M.close()
      end
    end, { buffer = buf })
    
    vim.keymap.set("n", config.options.keymaps.retry, function()
      if state.current_action then
        state.response = nil
        render_content()
        
        api.request_completion(state.current_action.prompt, state.code, function(response, error)
          if error then
            vim.notify("AI request failed: " .. error, vim.log.levels.ERROR)
            M.close()
            return
          end
          
          state.response = response
          render_content()
        end)
      end
    end, { buffer = buf })
  end
  
  vim.keymap.set("n", config.options.keymaps.cancel, function()
    M.close()
  end, { buffer = buf })
end

function M.show_assistant(code, context)
  -- Close any existing window first
  M.close()
  
  -- Reset state
  state.code = code
  state.context = context
  state.current_action = nil
  state.response = nil
  
  create_window()
  render_content()
  setup_keymaps()
end

function M.close()
  clear_keymaps()
  
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  
  state.win = nil
  state.buf = nil
  state.code = ""
  state.context = nil
  state.current_action = nil
  state.response = nil
end

return M