local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("simple-ai-assist", function()
  local simple_ai_assist
  
  before_each(function()
    package.loaded["simple-ai-assist"] = nil
    package.loaded["simple-ai-assist.config"] = nil
    package.loaded["simple-ai-assist.ui"] = nil
    package.loaded["simple-ai-assist.api"] = nil
    
    _G.vim = {
      api = {
        nvim_create_user_command = function() end,
        nvim_buf_get_lines = function() return {"test code"} end,
        nvim_get_current_buf = function() return 1 end,
      },
      fn = {
        mode = function() return "v" end,
        getpos = function() return {0, 1, 1, 0} end,
      },
      keymap = {
        set = function() end,
      },
      notify = function() end,
      cmd = function() end,
      env = {
        OPENROUTER_API_KEY = "test-key"
      },
      log = {
        levels = {
          WARN = 1,
          ERROR = 2,
          INFO = 3,
        }
      }
    }
    
    simple_ai_assist = require("simple-ai-assist")
  end)
  
  describe("setup", function()
    it("should create user command", function()
      local cmd_spy = spy.on(vim.api, "nvim_create_user_command")
      
      simple_ai_assist.setup()
      
      assert.spy(cmd_spy).was_called()
      assert.spy(cmd_spy).was_called_with("SimpleAIAssist", match.is_function(), match.is_table())
    end)
    
    it("should set default keymap", function()
      local keymap_spy = spy.on(vim.keymap, "set")
      
      simple_ai_assist.setup()
      
      assert.spy(keymap_spy).was_called()
      assert.spy(keymap_spy).was_called_with("v", "<leader>ac", match.is_function(), match.is_table())
    end)
    
    it("should respect custom keymaps", function()
      local keymap_spy = spy.on(vim.keymap, "set")
      
      simple_ai_assist.setup({
        keymaps = {
          trigger = "<leader>ai"
        }
      })
      
      assert.spy(keymap_spy).was_called_with("v", "<leader>ai", match.is_function(), match.is_table())
    end)
  end)
  
  describe("trigger_assistant", function()
    it("should warn if not in visual mode", function()
      local notify_spy = spy.on(vim, "notify")
      vim.fn.mode = function() return "n" end
      
      simple_ai_assist.trigger_assistant()
      
      assert.spy(notify_spy).was_called_with("Please select code in visual mode first", vim.log.levels.WARN)
    end)
    
    it("should get selected text in visual mode", function()
      local ui_mock = mock(require("simple-ai-assist.ui"), true)
      
      simple_ai_assist.trigger_assistant()
      
      assert.stub(ui_mock.show_assistant).was_called()
      assert.stub(ui_mock.show_assistant).was_called_with("test code", match.is_table())
    end)
  end)
end)