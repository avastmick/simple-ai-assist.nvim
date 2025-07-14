describe("simple-ai-assist.config", function()
  local config
  
  before_each(function()
    -- Mock plenary.curl before loading any modules
    package.loaded["plenary.curl"] = {
      post = function() end
    }
    
    package.loaded["simple-ai-assist.config"] = nil
    package.loaded["simple-ai-assist.api"] = nil
    
    _G.vim = {
      env = {},
      notify = function() end,
      tbl_deep_extend = function(behavior, a, b)
        local result = {}
        for k, v in pairs(a) do result[k] = v end
        for k, v in pairs(b or {}) do result[k] = v end
        return result
      end,
      log = {
        levels = {
          ERROR = 2,
        }
      }
    }
  end)
  
  describe("setup", function()
    it("should use default values", function()
      vim.env.OPENROUTER_API_KEY = "test-key"
      
      -- Load config module after setting env var
      local config = require("simple-ai-assist.config")
      config.setup()
      
      assert.equals("test-key", config.options.api_key)
      assert.equals("https://openrouter.ai/api/v1", config.options.endpoint)
      assert.equals("<leader>ac", config.options.keymaps.trigger)
      assert.equals("<C-u>", config.options.keymaps.accept)
      assert.equals("<C-r>", config.options.keymaps.retry)
      assert.equals(false, config.options.debug)
    end)
    
    it("should merge custom options", function()
      vim.env.OPENROUTER_API_KEY = "test-key"
      
      local config = require("simple-ai-assist.config")
      config.setup({
        model = "custom-model",
        keymaps = {
          trigger = "<leader>ai"
        }
      })
      
      assert.equals("custom-model", config.options.model)
      assert.equals("<leader>ai", config.options.keymaps.trigger)
    end)
    
    it("should fallback to OpenAI if no OpenRouter key", function()
      vim.env.OPENAI_API_KEY = "openai-key"
      
      local config = require("simple-ai-assist.config")
      config.setup()
      
      assert.equals("openai-key", config.options.api_key)
      assert.equals("https://api.openai.com/v1", config.options.endpoint)
    end)
    
    it("should fallback to Anthropic if no other keys", function()
      vim.env.ANTHROPIC_API_KEY = "anthropic-key"
      
      local config = require("simple-ai-assist.config")
      config.setup()
      
      assert.equals("anthropic-key", config.options.api_key)
      assert.equals("https://api.anthropic.com/v1", config.options.endpoint)
    end)
    
    it("should notify error if no API key found", function()
      local notify_spy = spy.on(vim, "notify")
      
      local config = require("simple-ai-assist.config")
      config.setup()
      
      assert.spy(notify_spy).was_called_with(
        "No API key found. Please set OPENROUTER_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY",
        vim.log.levels.ERROR
      )
    end)
  end)
end)