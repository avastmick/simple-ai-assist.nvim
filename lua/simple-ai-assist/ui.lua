local M = {}

local config = require("simple-ai-assist.config")
local api = require("simple-ai-assist.api")

local state = {
  win = nil,
  buf = nil,
  code = "",
  context = nil,
  current_action = nil,
  response = nil,
  original_lines = nil,  -- Store original buffer content
  filetype = nil  -- Store the source buffer filetype
}

local function debug_log(msg, level)
  if config.options.debug then
    vim.notify("[SimpleAI Debug] " .. msg, level or vim.log.levels.DEBUG)
  end
end

local function create_window()
  local opts = config.options.window
  local width = math.floor(vim.o.columns * opts.width)
  local height = math.floor(vim.o.lines * opts.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].filetype = "markdown"
  -- Don't set modifiable to false here - let render_content handle it
  vim.bo[state.buf].modifiable = true

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

  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].cursorline = true
end

local function extract_code_from_response(response_text)
  -- Extract code from markdown code blocks if present
  local code_block = response_text:match("```%w*\n(.-)```") or
                    response_text:match("```\n(.-)```") or
                    response_text:match("```(.-)```")
  if code_block then
    return code_block:gsub("^%s+", ""):gsub("%s+$", "")
  end
  return response_text
end

local function render_content()
  -- Only modify the floating window buffer, never the source buffer
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.bo[state.buf].modifiable = true
  local lines = {}

  table.insert(lines, "## Selected Code:")
  -- Add language to code fence for syntax highlighting
  local lang = state.filetype or ""
  table.insert(lines, "```" .. lang)
  for line in state.code:gmatch("[^\n]+") do
    table.insert(lines, line)
  end
  table.insert(lines, "```")
  table.insert(lines, "")

  if not state.current_action then
    table.insert(lines, "## Choose an action:")
    for _, action in ipairs(config.options.actions) do
      table.insert(lines, string.format("  %s - %s", action.key, action.label))
    end
    table.insert(lines, "")
    table.insert(lines, "Press the key combination to select an action, or " ..
                 config.options.keymaps.cancel .. " to cancel")
  elseif state.response then
    -- Check if this is an explanation action
    if state.current_action and state.current_action.label == "Explain" then
      -- For explanations, show the response directly without diff view
      table.insert(lines, "## Explanation:")
      table.insert(lines, "")

      -- Split response into lines and add them
      for line in state.response:gmatch("[^\n]+") do
        table.insert(lines, line)
      end

      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, string.format("%s Retry  %s Close",
        config.options.keymaps.retry,
        config.options.keymaps.cancel))
    else
      -- For other actions (Refactor, Fix, Comment), show diff view
      local response_text = extract_code_from_response(state.response)

      table.insert(lines, "## Proposed Changes:")
      table.insert(lines, "")
      table.insert(lines, "### Original Code:")
      table.insert(lines, "```" .. (state.filetype or ""))
      for line in state.code:gmatch("[^\n]+") do
        table.insert(lines, "- " .. line)
      end
      table.insert(lines, "```")
      table.insert(lines, "")
      table.insert(lines, "### Updated Code:")
      table.insert(lines, "```" .. (state.filetype or ""))
      for line in response_text:gmatch("[^\n]+") do
        table.insert(lines, "+ " .. line)
      end
      -- Handle empty lines at the end
      if response_text:match("\n$") then
        table.insert(lines, "+")
      end
      table.insert(lines, "```")
      table.insert(lines, "")
      table.insert(lines, "---")
      table.insert(lines, string.format("%s Accept  %s Retry  %s Cancel",
        config.options.keymaps.accept,
        config.options.keymaps.retry,
        config.options.keymaps.cancel))
    end
  else
    table.insert(lines, "## Processing...")
    table.insert(lines, "Waiting for AI response...")
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false

  -- Also set the buffer to be non-modifiable at the buffer-local level
  vim.bo[state.buf].modifiable = false
end

local function clear_keymaps()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_call(state.buf, function()
      vim.cmd("mapclear <buffer>")
    end)
  end
end

local function set_buffer_keymap(mode, lhs, rhs, desc)
  -- Use pcall to handle any errors during keymap setup
  local ok, err = pcall(vim.keymap.set, mode, lhs, rhs, {
    buffer = state.buf,
    nowait = true,
    noremap = true,
    silent = true,
    desc = desc
  })
  if not ok then
    debug_log("Failed to set keymap " .. lhs .. ": " .. tostring(err), vim.log.levels.WARN)
  end
end

local function handle_api_error(error)
  vim.notify("AI request failed: " .. error, vim.log.levels.ERROR)
  M.close(false)
end

local function setup_keymaps()
  local buf = state.buf

  -- Ensure we're setting keymaps for the floating buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    vim.notify("Invalid buffer for keymaps", vim.log.levels.ERROR)
    return
  end

  -- The buffer should already be non-modifiable to prevent accidental edits
  -- Don't change modifiable state during keymap setup

  if not state.current_action then
    for _, action in ipairs(config.options.actions) do
      set_buffer_keymap("n", action.key, function()
        state.current_action = action
        state.response = nil
        render_content()

        api.request_completion(action.prompt, state.code, function(response, error)
          if error then
            handle_api_error(error)
            return
          end

          state.response = response
          render_content()
          -- Clear and re-setup keymaps for the new state
          clear_keymaps()
          setup_keymaps()
        end)
      end, "Select " .. action.label .. " action")
    end
  else
    -- Only set up accept keymap if this is not an explanation
    if state.current_action and state.current_action.label ~= "Explain" then
      set_buffer_keymap("n", config.options.keymaps.accept, function()
      debug_log("Accept key pressed")
      -- First check we're in the floating window
      local current_buf = vim.api.nvim_get_current_buf()
      if current_buf ~= state.buf then
        vim.notify("Accept can only be called from the assistant window", vim.log.levels.WARN)
        return
      end

      debug_log("In correct buffer, processing response")
      if state.response and state.context then
        local response_text = extract_code_from_response(state.response)

        -- Split response into lines (preserving empty lines)
        local lines = vim.split(response_text, "\n", { plain = true })

        -- Remove trailing empty line if present
        if #lines > 0 and lines[#lines] == "" then
          table.remove(lines)
        end

        -- Store the context before closing
        local target_buf = state.context.buffer
        local start_line = state.context.start_line
        local end_line = state.context.end_line

        debug_log(string.format("Applying changes to buffer %d, lines %d-%d",
          target_buf, start_line, end_line))

        -- Close the floating window first
        M.close(false)

        -- Now apply changes after window is closed
        vim.schedule(function()
          debug_log("Applying changes after window closed")
          -- Ensure the source buffer is valid
          if vim.api.nvim_buf_is_valid(target_buf) then
            local success, err = pcall(function()
              -- Ensure buffer is loaded
              if not vim.api.nvim_buf_is_loaded(target_buf) then
                vim.fn.bufload(target_buf)
              end

              -- Get buffer options
              local buf_modifiable = vim.bo[target_buf].modifiable
              local buf_readonly = vim.bo[target_buf].readonly

              -- Check if buffer is modifiable
              if not buf_modifiable or buf_readonly then
                error("Buffer is not modifiable or is readonly")
              end

              -- Apply the changes to the target buffer
              vim.api.nvim_buf_set_lines(target_buf, start_line, end_line, false, lines)
            end)

            if success then
              vim.notify("Changes applied!", vim.log.levels.INFO)
            else
              vim.notify("Failed to apply changes: " .. tostring(err), vim.log.levels.ERROR)
            end
          else
            vim.notify("Source buffer is no longer valid", vim.log.levels.ERROR)
          end
        end)
      end
    end, "Accept AI suggestion")
    end

    set_buffer_keymap("n", config.options.keymaps.retry, function()
      if state.current_action then
        state.response = nil
        render_content()

        api.request_completion(state.current_action.prompt, state.code, function(response, error)
          if error then
            handle_api_error(error)
            return
          end

          state.response = response
          render_content()
          -- Clear and re-setup keymaps for the new state
          clear_keymaps()
          setup_keymaps()
        end)
      end
    end, "Retry AI request")
  end

  set_buffer_keymap("n", config.options.keymaps.cancel, function()
    M.close(false)
  end, "Cancel and close")
end

function M.show_assistant(code, context)
  -- Close any existing window first
  M.close(false)

  -- Reset state
  state.code = code
  state.context = context
  state.current_action = nil
  state.response = nil

  -- Store original buffer content to ensure we don't accidentally modify it
  if context and context.buffer and vim.api.nvim_buf_is_valid(context.buffer) then
    state.original_lines = vim.api.nvim_buf_get_lines(
      context.buffer,
      context.start_line,
      context.end_line,
      false
    )
    -- Get the filetype of the source buffer for syntax highlighting
    state.filetype = vim.bo[context.buffer].filetype
  end

  create_window()
  render_content()
  setup_keymaps()

  -- Ensure we're focused on the floating window
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.close(accepted)
  clear_keymaps()

  -- If not accepted and we have original lines, restore them to ensure no changes
  if not accepted and state.original_lines and state.context and
     vim.api.nvim_buf_is_valid(state.context.buffer) then
    -- Check if buffer was modified
    local current_lines = vim.api.nvim_buf_get_lines(
      state.context.buffer,
      state.context.start_line,
      state.context.end_line,
      false
    )

    -- Only restore if content actually changed
    local changed = false
    if #current_lines ~= #state.original_lines then
      changed = true
    else
      for i, line in ipairs(current_lines) do
        if line ~= state.original_lines[i] then
          changed = true
          break
        end
      end
    end

    if changed then
      vim.api.nvim_buf_set_lines(
        state.context.buffer,
        state.context.start_line,
        state.context.end_line,
        false,
        state.original_lines
      )
      vim.notify("Original content restored", vim.log.levels.INFO)
    end
  end

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
  state.original_lines = nil
  state.filetype = nil
end

return M