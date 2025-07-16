local M = {}

local config = require("simple-ai-assist.config")
local curl = require("plenary.curl")

function M.request_completion(prompt, code, filetype, callback)
  local opts = config.options

  if not opts.api_key then
    callback(nil, "No API key configured")
    return
  end

  -- Determine the language from filetype
  local language = filetype or "plaintext"
  -- Map common filetypes to language names
  local filetype_map = {
    lua = "Lua",
    python = "Python",
    javascript = "JavaScript",
    typescript = "TypeScript",
    java = "Java",
    cpp = "C++",
    c = "C",
    rust = "Rust",
    go = "Go",
    ruby = "Ruby",
    php = "PHP",
    sh = "Bash",
    bash = "Bash",
    zsh = "Zsh",
    vim = "Vimscript",
    html = "HTML",
    css = "CSS",
    scss = "SCSS",
    json = "JSON",
    yaml = "YAML",
    toml = "TOML",
    markdown = "Markdown",
    md = "Markdown",
  }
  local language_name = filetype_map[language] or language

  local messages = {
    {
      role = "system",
      content = "You are a helpful coding assistant specializing in "
        .. language_name
        .. ". "
        .. "Provide clear, concise responses focused on the specific request. "
        .. "For code suggestions, provide only the improved code without explanations "
        .. "unless explicitly asked. "
        .. "IMPORTANT: Always respond with valid "
        .. language_name
        .. " code. "
        .. "Maintain the same programming language and syntax throughout your response.",
    },
    {
      role = "user",
      content = prompt .. "\n\nLanguage: " .. language_name .. "\n\n```" .. language .. "\n" .. code .. "\n```",
    },
  }

  local body = vim.json.encode({
    model = opts.model,
    messages = messages,
    max_tokens = 2000,
    temperature = 0.7,
  })

  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. opts.api_key,
  }

  if opts.endpoint:match("openrouter") then
    headers["HTTP-Referer"] = "https://github.com/avastmick/simple-ai-assist.nvim"
    headers["X-Title"] = "simple-ai-assist.nvim"
  end

  vim.schedule(function()
    curl.post(opts.endpoint .. "/chat/completions", {
      headers = headers,
      body = body,
      callback = vim.schedule_wrap(function(response)
        if response.status ~= 200 then
          callback(nil, "API request failed: " .. (response.body or "Unknown error"))
          return
        end

        local ok, data = pcall(vim.json.decode, response.body)
        if not ok then
          callback(nil, "Failed to parse API response")
          return
        end

        if data.choices and data.choices[1] and data.choices[1].message then
          callback(data.choices[1].message.content, nil)
        else
          callback(nil, "Unexpected API response format")
        end
      end),
    })
  end)
end

return M
