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
  original_lines = nil, -- Store original buffer content
  filetype = nil, -- Store the source buffer filetype
  progress_timer = nil, -- Timer for progress animation
  progress_frame = 1, -- Current frame of animation
  ask_mode = false, -- Track if we're in ask mode
  ask_text = "", -- Store the user's question/action text
  ask_buf = nil, -- Buffer for text input
  ask_win = nil, -- Window for text input
}

local function debug_log(msg, level)
  if config.options.debug then
    vim.notify("[SimpleAI Debug] " .. msg, level or vim.log.levels.DEBUG)
  end
end

-- Using braille patterns that fill progressively
local braille_patterns = {
  "⡀",
  "⡄",
  "⡆",
  "⡇",
  "⣇",
  "⣧",
  "⣷",
  "⣿",
  "⣿",
  "⣷",
  "⣧",
  "⣇",
  "⡇",
  "⡆",
  "⡄",
  "⡀",
}

-- Forward declaration
local render_content

local function start_progress_animation()
  if state.progress_timer then
    state.progress_timer:stop()
  end

  state.progress_frame = 1
  state.progress_timer = vim.loop.new_timer()

  state.progress_timer:start(
    0,
    100, -- Update every 100ms
    vim.schedule_wrap(function()
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) and not state.response then
        state.progress_frame = state.progress_frame + 1
        if state.progress_frame > #braille_patterns then
          state.progress_frame = 1
        end
        render_content()
      end
    end)
  )
end

local function stop_progress_animation()
  if state.progress_timer then
    state.progress_timer:stop()
    state.progress_timer = nil
  end
  state.progress_frame = 1
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
    title_pos = "center",
  })

  vim.wo[state.win].wrap = true
  vim.wo[state.win].linebreak = true
  vim.wo[state.win].cursorline = true
end

local function create_ask_input_window()
  local parent_width = vim.api.nvim_win_get_width(state.win)
  local parent_height = vim.api.nvim_win_get_height(state.win)
  local parent_row = vim.api.nvim_win_get_position(state.win)[1]
  local parent_col = vim.api.nvim_win_get_position(state.win)[2]

  -- Create input window centered in the parent window
  local input_width = math.floor(parent_width * 0.8)
  local input_height = 5
  local input_row = parent_row + math.floor((parent_height - input_height) / 2)
  local input_col = parent_col + math.floor((parent_width - input_width) / 2)

  state.ask_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.ask_buf].buftype = "nofile"
  vim.bo[state.ask_buf].modifiable = true

  state.ask_win = vim.api.nvim_open_win(state.ask_buf, true, {
    relative = "editor",
    width = input_width,
    height = input_height,
    row = input_row,
    col = input_col,
    border = "rounded",
    style = "minimal",
    title = " Enter your question or action ",
    title_pos = "center",
  })

  vim.wo[state.ask_win].wrap = true
  vim.wo[state.ask_win].linebreak = true

  -- Set initial text if any
  if state.ask_text ~= "" then
    local lines = vim.split(state.ask_text, "\n", { plain = true })
    vim.api.nvim_buf_set_lines(state.ask_buf, 0, -1, false, lines)
  end

  -- Setup keymaps for the input window
  vim.keymap.set("n", "<Return>", function()
    M.submit_ask_prompt()
  end, { buffer = state.ask_buf, nowait = true, noremap = true, silent = true })

  vim.keymap.set("i", "<Return>", function()
    M.submit_ask_prompt()
  end, { buffer = state.ask_buf, nowait = true, noremap = true, silent = true })

  vim.keymap.set("i", "<S-Return>", function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
  end, { buffer = state.ask_buf, nowait = true, noremap = true, silent = true })

  vim.keymap.set({ "n", "i" }, "<Esc>", function()
    M.close_ask_input()
  end, { buffer = state.ask_buf, nowait = true, noremap = true, silent = true })

  -- Enter insert mode
  vim.cmd("startinsert")
end

local function close_ask_input()
  if state.ask_win and vim.api.nvim_win_is_valid(state.ask_win) then
    vim.api.nvim_win_close(state.ask_win, true)
  end
  if state.ask_buf and vim.api.nvim_buf_is_valid(state.ask_buf) then
    vim.api.nvim_buf_delete(state.ask_buf, { force = true })
  end
  state.ask_win = nil
  state.ask_buf = nil

  -- Return focus to main window
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

local function extract_code_from_response(response_text)
  -- Extract code from markdown code blocks if present
  local code_block = response_text:match("```%w*\n(.-)```")
    or response_text:match("```\n(.-)```")
    or response_text:match("```(.-)```")
  if code_block then
    return code_block:gsub("^%s+", ""):gsub("%s+$", "")
  end
  return response_text
end

-- Function to format code with line numbers
local function format_code_with_line_numbers(code, start_line)
  local lines = vim.split(code, "\n", { plain = true, trimempty = false })
  local formatted_lines = {}

  -- Remove trailing empty line if present
  if code:match("\n$") and #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end

  local line_num = start_line or 1
  for _, line in ipairs(lines) do
    local formatted = string.format("%4d │ %s", line_num, line)
    table.insert(formatted_lines, formatted)
    line_num = line_num + 1
  end

  return formatted_lines
end

-- Function to create a unified diff view with line numbers
local function create_diff_view(original, modified, start_line)
  local original_lines = vim.split(original, "\n", { plain = true, trimempty = false })
  local modified_lines = vim.split(modified, "\n", { plain = true, trimempty = false })
  local diff_lines = {}
  local line_num = start_line or 1

  -- Handle trailing newlines
  if original:match("\n$") and #original_lines > 0 and original_lines[#original_lines] == "" then
    table.remove(original_lines)
  end
  if modified:match("\n$") and #modified_lines > 0 and modified_lines[#modified_lines] == "" then
    table.remove(modified_lines)
  end

  -- Simple line-by-line diff (can be enhanced with actual diff algorithm later)
  local max_lines = math.max(#original_lines, #modified_lines)

  for i = 1, max_lines do
    local orig_line = original_lines[i]
    local mod_line = modified_lines[i]

    if orig_line ~= nil and mod_line == nil then
      -- Line was removed
      table.insert(diff_lines, { text = string.format("%4d │ - %s", line_num, orig_line), type = "removed" })
      line_num = line_num + 1
    elseif orig_line == nil and mod_line ~= nil then
      -- Line was added
      table.insert(diff_lines, { text = string.format("%4d │ + %s", line_num, mod_line), type = "added" })
      line_num = line_num + 1
    elseif orig_line ~= mod_line then
      -- Line was changed
      table.insert(diff_lines, { text = string.format("%4d │ - %s", line_num, orig_line), type = "removed" })
      table.insert(diff_lines, { text = string.format("%4d │ + %s", line_num, mod_line), type = "added" })
      line_num = line_num + 1
    else
      -- Line unchanged
      table.insert(diff_lines, { text = string.format("%4d │   %s", line_num, orig_line), type = "unchanged" })
      line_num = line_num + 1
    end
  end

  return diff_lines
end

-- Function to apply line number highlighting to code view
local function apply_line_number_highlights(buf, start_line, end_line)
  vim.cmd([[highlight LineNumber guifg=#7c6f64 ctermfg=243]])
  vim.cmd([[highlight LineSeparator guifg=#504945 ctermfg=239]])

  local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

  for i, line in ipairs(lines) do
    local line_num = start_line + i - 1
    local sep_pos = line:find("│")
    if sep_pos then
      -- Highlight line number (everything before separator)
      vim.api.nvim_buf_add_highlight(buf, -1, "LineNumber", line_num - 1, 0, sep_pos - 1)
      -- Highlight separator
      vim.api.nvim_buf_add_highlight(buf, -1, "LineSeparator", line_num - 1, sep_pos - 1, sep_pos + 2)
    end
  end
end

-- Function to apply syntax highlighting to diff lines
local function apply_diff_highlights(buf, start_line, end_line)
  -- Define highlight groups to match standard diff colors
  vim.cmd([[highlight DiffAddedLine guibg=#1c3b1a guifg=#b8bb26 ctermbg=22 ctermfg=142]])
  vim.cmd([[highlight DiffRemovedLine guibg=#3b1a1a guifg=#fb4934 ctermbg=52 ctermfg=167]])
  vim.cmd([[highlight DiffAddedChar guibg=#2d4a2b guifg=#b8bb26 ctermbg=28 ctermfg=142]])
  vim.cmd([[highlight DiffRemovedChar guibg=#4a2b2b guifg=#fb4934 ctermbg=88 ctermfg=167]])
  vim.cmd([[highlight LineNumber guifg=#7c6f64 ctermfg=243]])
  vim.cmd([[highlight LineSeparator guifg=#504945 ctermfg=239]])

  local lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)

  for i, line in ipairs(lines) do
    local line_num = start_line + i - 1

    -- Highlight line numbers and separator for all lines
    local sep_pos = line:find("│")
    if sep_pos then
      -- Highlight line number (everything before separator)
      vim.api.nvim_buf_add_highlight(buf, -1, "LineNumber", line_num - 1, 0, sep_pos - 1)
      -- Highlight separator
      vim.api.nvim_buf_add_highlight(buf, -1, "LineSeparator", line_num - 1, sep_pos - 1, sep_pos + 2)
    end

    -- Match lines with line numbers and +/- indicators
    if line:match("│ %+") then
      -- Highlight entire line with added background
      vim.api.nvim_buf_add_highlight(buf, -1, "DiffAddedLine", line_num - 1, 0, -1)
      -- Find where the + character is after the line number separator
      local plus_pos = line:find("│ %+")
      if plus_pos then
        vim.api.nvim_buf_add_highlight(buf, -1, "DiffAddedChar", line_num - 1, plus_pos + 1, plus_pos + 2)
      end
    elseif line:match("│ %-") then
      -- Highlight entire line with removed background
      vim.api.nvim_buf_add_highlight(buf, -1, "DiffRemovedLine", line_num - 1, 0, -1)
      -- Find where the - character is after the line number separator
      local minus_pos = line:find("│ %-")
      if minus_pos then
        vim.api.nvim_buf_add_highlight(buf, -1, "DiffRemovedChar", line_num - 1, minus_pos + 1, minus_pos + 2)
      end
    end
  end
end

render_content = function()
  -- Only modify the floating window buffer, never the source buffer
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end

  vim.bo[state.buf].modifiable = true
  local lines = {}
  local diff_start_line = nil
  local diff_end_line = nil
  local code_start_line = nil
  local code_end_line = nil
  local header_highlights = {} -- Store header line positions and types

  -- Get filename from context buffer if available
  local filename = ""
  if state.context and state.context.buffer and vim.api.nvim_buf_is_valid(state.context.buffer) then
    filename = vim.api.nvim_buf_get_name(state.context.buffer)
    -- Get relative path if it's in the current working directory
    local cwd = vim.fn.getcwd()
    if vim.startswith(filename, cwd) then
      filename = vim.fn.fnamemodify(filename, ":~:.")
    else
      filename = vim.fn.fnamemodify(filename, ":~")
    end
  end

  if not state.current_action then
    -- Show selected code with line numbers
    if filename ~= "" then
      table.insert(lines, filename)
      table.insert(header_highlights, { line = #lines, type = "filename" })
    else
      table.insert(lines, "Selected Code")
      table.insert(header_highlights, { line = #lines, type = "header" })
    end
    table.insert(lines, "")
    local lang = state.filetype or ""
    table.insert(lines, "```" .. lang)
    code_start_line = #lines + 1
    local formatted_lines =
      format_code_with_line_numbers(state.code, state.context and state.context.display_start_line or 1)
    for _, line in ipairs(formatted_lines) do
      table.insert(lines, line)
    end
    code_end_line = #lines
    table.insert(lines, "```")
    table.insert(lines, "")
    table.insert(lines, "Actions:")
    table.insert(header_highlights, { line = #lines, type = "header" })
    table.insert(lines, "")
    for _, action in ipairs(config.options.actions) do
      table.insert(lines, string.format("  %s - %s", action.key, action.label))
    end
    table.insert(lines, string.format("  %s - %s", "<C-q>", "Ask (custom prompt)"))
    table.insert(lines, "")
    table.insert(
      lines,
      "Press the key combination to select an action, or " .. config.options.keymaps.cancel .. " to cancel"
    )
    table.insert(header_highlights, { line = #lines, type = "hint" })
  elseif state.response then
    -- Check if this is an explanation action
    if state.current_action and state.current_action.label == "Explain" then
      -- For explanations, show original code with line numbers at top and explanation below
      if filename ~= "" then
        table.insert(lines, filename)
        table.insert(header_highlights, { line = #lines, type = "filename" })
      else
        table.insert(lines, "Selected Code")
        table.insert(header_highlights, { line = #lines, type = "header" })
      end
      table.insert(lines, "")
      local lang = state.filetype or ""
      table.insert(lines, "```" .. lang)
      code_start_line = #lines + 1
      local formatted_lines =
        format_code_with_line_numbers(state.code, state.context and state.context.display_start_line or 1)
      for _, line in ipairs(formatted_lines) do
        table.insert(lines, line)
      end
      code_end_line = #lines
      table.insert(lines, "```")
      table.insert(lines, "")
      table.insert(lines, "Explanation:")
      table.insert(header_highlights, { line = #lines, type = "header" })
      table.insert(lines, "")

      -- Split response into lines and add them
      for line in state.response:gmatch("[^\n]+") do
        table.insert(lines, line)
      end

      table.insert(lines, "")
      table.insert(
        lines,
        string.format("%s Retry  %s Close", config.options.keymaps.retry, config.options.keymaps.cancel)
      )
      table.insert(header_highlights, { line = #lines, type = "keyhint" })
    elseif state.current_action and state.current_action.label == "Ask" then
      -- For Ask action, determine if response contains code
      local response_text = extract_code_from_response(state.response)

      -- Check if the response is likely code by looking for common patterns
      local is_code_response = false
      if response_text ~= state.response then
        -- Response had code blocks, so it's definitely code
        is_code_response = true
      else
        -- Check if response looks like code (simple heuristic)
        local code_indicators = {
          "^%s*function",
          "^%s*local",
          "^%s*if%s+",
          "^%s*for%s+",
          "^%s*while%s+",
          "^%s*return",
          "^%s*class%s+",
          "^%s*def%s+",
          "^%s*import",
          "^%s*const%s+",
          "^%s*let%s+",
          "^%s*var%s+",
          "[%;%{%}%(%)]",
        }
        for _, pattern in ipairs(code_indicators) do
          if response_text:match(pattern) then
            is_code_response = true
            break
          end
        end
      end

      if is_code_response then
        -- Show diff view for code responses
        table.insert(lines, "Code Changes:")
        table.insert(header_highlights, { line = #lines, type = "header" })
        table.insert(lines, "")
        table.insert(lines, "```diff")
        diff_start_line = #lines + 1

        -- Create and add diff lines with line numbers
        local diff_data =
          create_diff_view(state.code, response_text, state.context and state.context.display_start_line or 1)
        for _, diff_line in ipairs(diff_data) do
          table.insert(lines, diff_line.text)
        end
        diff_end_line = #lines

        table.insert(lines, "```")
        table.insert(lines, "")

        -- Add AI explanation/notes if present in response
        local explanation = state.response:match("```.-```(.*)$")
        if explanation and explanation:match("%S") then
          table.insert(lines, "Notes:")
          table.insert(header_highlights, { line = #lines, type = "header" })
          table.insert(lines, "")
          for line in explanation:gmatch("[^\n]+") do
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
              table.insert(lines, trimmed)
            end
          end
          table.insert(lines, "")
        end

        table.insert(
          lines,
          string.format(
            "%s Accept  %s Retry  %s Cancel",
            config.options.keymaps.accept,
            config.options.keymaps.retry,
            config.options.keymaps.cancel
          )
        )
        table.insert(header_highlights, { line = #lines, type = "keyhint" })
      else
        -- Show as plain text response (like Explain)
        if filename ~= "" then
          table.insert(lines, filename)
          table.insert(header_highlights, { line = #lines, type = "filename" })
        else
          table.insert(lines, "Selected Code")
          table.insert(header_highlights, { line = #lines, type = "header" })
        end
        table.insert(lines, "")
        local lang = state.filetype or ""
        table.insert(lines, "```" .. lang)
        code_start_line = #lines + 1
        local formatted_lines =
          format_code_with_line_numbers(state.code, state.context and state.context.display_start_line or 1)
        for _, line in ipairs(formatted_lines) do
          table.insert(lines, line)
        end
        code_end_line = #lines
        table.insert(lines, "```")
        table.insert(lines, "")
        table.insert(lines, "Response:")
        table.insert(header_highlights, { line = #lines, type = "header" })
        table.insert(lines, "")

        -- Split response into lines and add them
        for line in state.response:gmatch("[^\n]+") do
          table.insert(lines, line)
        end

        table.insert(lines, "")
        table.insert(
          lines,
          string.format("%s Retry  %s Close", config.options.keymaps.retry, config.options.keymaps.cancel)
        )
        table.insert(header_highlights, { line = #lines, type = "keyhint" })
      end
    else
      -- For other actions (Refactor, Fix, Comment), show unified diff view
      local response_text = extract_code_from_response(state.response)

      table.insert(lines, "Code Changes:")
      table.insert(header_highlights, { line = #lines, type = "header" })
      table.insert(lines, "")
      table.insert(lines, "```diff")
      diff_start_line = #lines + 1

      -- Create and add diff lines with line numbers
      local diff_data =
        create_diff_view(state.code, response_text, state.context and state.context.display_start_line or 1)
      for _, diff_line in ipairs(diff_data) do
        table.insert(lines, diff_line.text)
      end
      diff_end_line = #lines

      table.insert(lines, "```")
      table.insert(lines, "")

      -- Add AI explanation/notes if present in response
      local explanation = state.response:match("```.-```(.*)$")
      if explanation and explanation:match("%S") then
        table.insert(lines, "Notes:")
        table.insert(header_highlights, { line = #lines, type = "header" })
        table.insert(lines, "")
        for line in explanation:gmatch("[^\n]+") do
          local trimmed = line:match("^%s*(.-)%s*$")
          if trimmed ~= "" then
            table.insert(lines, trimmed)
          end
        end
        table.insert(lines, "")
      end

      table.insert(
        lines,
        string.format(
          "%s Accept  %s Retry  %s Cancel",
          config.options.keymaps.accept,
          config.options.keymaps.retry,
          config.options.keymaps.cancel
        )
      )
      table.insert(header_highlights, { line = #lines, type = "keyhint" })
    end
  else
    table.insert(lines, "Processing...")
    table.insert(header_highlights, { line = #lines, type = "processing" })
    table.insert(lines, "")

    -- Show animated progress indicator with block patterns
    local frame = state.progress_frame

    -- Create a nice visual with multiple block indicators
    local blocks = string.format(
      "%s %s %s",
      braille_patterns[((frame - 1) % #braille_patterns) + 1],
      braille_patterns[(frame % #braille_patterns) + 1],
      braille_patterns[((frame + 1) % #braille_patterns) + 1]
    )

    table.insert(lines, string.format("  %s  Waiting for AI response", blocks))
    table.insert(lines, "")
    table.insert(lines, string.format("  Action: %s", state.current_action.label))
    table.insert(lines, "")
    table.insert(lines, "  Press " .. config.options.keymaps.cancel .. " to cancel")
    table.insert(header_highlights, { line = #lines, type = "hint" })
  end

  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

  -- Link to standard highlight groups that exist in all colorschemes
  vim.cmd([[highlight link SimpleAIHeader Title]]) -- Usually bold and prominent
  vim.cmd([[highlight link SimpleAIFilename Directory]]) -- Usually distinctive color
  vim.cmd([[highlight link SimpleAIProcessing WarningMsg]]) -- Usually yellow/orange
  vim.cmd([[highlight link SimpleAIHint Comment]]) -- Usually muted/gray
  vim.cmd([[highlight link SimpleAIKeyHint Special]]) -- Usually distinctive

  -- Apply header highlights
  for _, highlight in ipairs(header_highlights) do
    local hl_group = "SimpleAIHeader"
    if highlight.type == "filename" then
      hl_group = "SimpleAIFilename"
    elseif highlight.type == "processing" then
      hl_group = "SimpleAIProcessing"
    elseif highlight.type == "hint" then
      hl_group = "SimpleAIHint"
    elseif highlight.type == "keyhint" then
      hl_group = "SimpleAIKeyHint"
    end
    vim.api.nvim_buf_add_highlight(state.buf, -1, hl_group, highlight.line - 1, 0, -1)
  end

  -- Apply line number highlighting to regular code views
  if code_start_line and code_end_line then
    apply_line_number_highlights(state.buf, code_start_line, code_end_line)
  end

  -- Apply diff highlighting if we rendered a diff
  if diff_start_line and diff_end_line then
    apply_diff_highlights(state.buf, diff_start_line, diff_end_line)
  end

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
    desc = desc,
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
        start_progress_animation()

        api.request_completion(action.prompt, state.code, state.filetype, function(response, error)
          stop_progress_animation()
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

    -- Add the Ask action keymap
    set_buffer_keymap("n", "<C-q>", function()
      state.ask_mode = true
      create_ask_input_window()
    end, "Ask (custom prompt)")
  else
    -- Only set up accept keymap if this is not an explanation action
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

          debug_log(string.format("Applying changes to buffer %d, lines %d-%d", target_buf, start_line, end_line))

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
        start_progress_animation()

        api.request_completion(state.current_action.prompt, state.code, state.filetype, function(response, error)
          stop_progress_animation()
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
    state.original_lines = vim.api.nvim_buf_get_lines(context.buffer, context.start_line, context.end_line, false)
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

function M.submit_ask_prompt()
  if not state.ask_buf or not vim.api.nvim_buf_is_valid(state.ask_buf) then
    return
  end

  -- Get the text from the input buffer
  local lines = vim.api.nvim_buf_get_lines(state.ask_buf, 0, -1, false)
  state.ask_text = table.concat(lines, "\n")

  -- Close the input window
  close_ask_input()

  -- Create the ask action
  state.current_action = {
    label = "Ask",
    prompt = state.ask_text,
  }

  -- Clear the ask text and reset ask mode
  state.ask_mode = false
  state.response = nil
  render_content()
  start_progress_animation()

  -- Make the API request with the custom prompt
  api.request_completion(state.ask_text, state.code, state.filetype, function(response, error)
    stop_progress_animation()
    if error then
      handle_api_error(error)
      return
    end

    state.response = response
    render_content()
    -- Clear and re-setup keymaps for the new state
    clear_keymaps()
    setup_keymaps()

    -- Ensure we're in normal mode after rendering
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_call(state.win, function()
        vim.cmd("stopinsert")
      end)
    end
  end)
end

function M.close_ask_input()
  close_ask_input()
  state.ask_mode = false
  state.ask_text = ""
end

function M.close(accepted)
  clear_keymaps()
  stop_progress_animation()

  -- If not accepted and we have original lines, restore them to ensure no changes
  if not accepted and state.original_lines and state.context and vim.api.nvim_buf_is_valid(state.context.buffer) then
    -- Check if buffer was modified
    local current_lines =
      vim.api.nvim_buf_get_lines(state.context.buffer, state.context.start_line, state.context.end_line, false)

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
  state.ask_mode = false
  state.ask_text = ""

  -- Clean up ask input window if it exists
  if state.ask_win and vim.api.nvim_win_is_valid(state.ask_win) then
    vim.api.nvim_win_close(state.ask_win, true)
  end
  if state.ask_buf and vim.api.nvim_buf_is_valid(state.ask_buf) then
    vim.api.nvim_buf_delete(state.ask_buf, { force = true })
  end
  state.ask_win = nil
  state.ask_buf = nil
end

return M
