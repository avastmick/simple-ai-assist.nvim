# A Simple AI Assistant for Neovim

My workflow is to use CLI-based code generation AI assistants. I don't need anything complicated, just select code: explain, refactor, fix or comment. This plugin does just that.

## Features

- Multiple AI provider support (OpenRouter, OpenAI, Anthropic)
- Visual mode code selection
- AI-powered code actions:
  - **Explain**: Get detailed explanations
  - **Refactor**: Improve code structure
  - **Fix**: Identify and fix issues
  - **Comment**: Generate appropriate comments
- Keyboard-driven workflow
- Non-intrusive floating window UI

## Requirements

- Neovim 0.7.0+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (for HTTP requests)
- API key for one of:
  - OpenRouter (`OPENROUTER_API_KEY`)
  - OpenAI (`OPENAI_API_KEY`)
  - Anthropic (`ANTHROPIC_API_KEY`)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "avastmick/simple-ai-assist.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("simple-ai-assist").setup({
      -- Optional configuration
    })
  end,
  keys = {
    { "<leader>ac", mode = "v", desc = "AI Code Assistant" },
  },
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "avastmick/simple-ai-assist.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("simple-ai-assist").setup()
  end
}
```

## Configuration

### Default Configuration

```lua
require("simple-ai-assist").setup({
  -- API configuration (defaults to OPENROUTER_API_KEY)
  api_key = vim.env.OPENROUTER_API_KEY,
  endpoint = "https://openrouter.ai/api/v1",
  model = "anthropic/claude-3-5-sonnet-20241022",
  
  -- Keymappings
  keymaps = {
    trigger = "<leader>ac", -- Trigger assistant in visual mode
    accept = "C-u",         -- Accept (update) AI suggestion
    retry = "C-r",          -- Retry same action
    cancel = "<Esc>",       -- Cancel and close
  },
  
  -- Window appearance
  window = {
    width = 0.7,      -- 70% of editor width
    height = 0.7,     -- 70% of editor height
    border = "rounded",
  },
  
  -- Available AI actions
    actions = {
        { key = "<C-e>", label = "Explain",  prompt = "Explain this code in detail:" },
        { key = "<C-p>", label = "Refactor", prompt = "Suggest improvements for this code:" },
        { key = "<C-f>", label = "Fix",      prompt = "Find and fix issues in this code:" },
        { key = "<C-c>", label = "Comment",  prompt = "Add appropriate comments to this code:" },
    }
})
```

### API Key Setup

Set your API key as an environment variable:

```bash
# For OpenRouter (default)
export OPENROUTER_API_KEY="your-key-here"

# For OpenAI
export OPENAI_API_KEY="your-key-here"

# For Anthropic
export ANTHROPIC_API_KEY="your-key-here"
```

Add to your shell configuration file (`~/.bashrc`, `~/.zshrc`, etc.) to persist.

## Usage

1. Select code in visual mode (`v`, `V`, or `<C-v>`)
2. Press `<leader>ac` (default) to trigger the assistant
3. Choose an action:
   - `C-e` - Explain the code
   - `C-p` - Refactor suggestions
   - `C-f` - Fix issues
   - `C-c` - Add comments
4. Wait for AI response
5. Then:
   - `C-u` - Accept and apply changes
   - `C-r` - Retry for different response
   - `<Esc>` - Cancel without changes

## Local Development

For local testing in your Neovim configuration:

```lua
-- In your init.lua or plugin configuration
use {
  dir = "~/repos/simple-ai-assist.nvim",  -- Path to local clone
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("simple-ai-assist").setup()
  end
}
```

## Troubleshooting

### No API Key Error
Ensure your API key environment variable is set and exported. Check with:
```bash
echo $OPENROUTER_API_KEY
```

### API Request Failed
- Verify your internet connection
- Check API key validity
- Ensure the selected model is available for your API provider

### Plenary Not Found
Install plenary.nvim first:
```vim
:Lazy install nvim-lua/plenary.nvim
```

## License

MIT License - see [LICENSE](LICENSE) for details

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
