local spy = require("luassert.spy")

describe("simple-ai-assist.api", function()
  local api
  local curl_mock

  before_each(function()
    -- Mock curl responses
    curl_mock = {
      post = spy.new(function(_, opts)
        -- Simulate successful API response
        opts.callback({
          status = 200,
          body = vim.json.encode({
            choices = {
              {
                message = {
                  content = "Refactored code here",
                },
              },
            },
          }),
        })
      end),
    }

    package.loaded["plenary.curl"] = curl_mock
    package.loaded["simple-ai-assist.api"] = nil
    package.loaded["simple-ai-assist.config"] = nil

    _G.vim = {
      env = {
        OPENROUTER_API_KEY = "test-key",
      },
      notify = function() end,
      schedule = function(fn)
        fn()
      end,
      schedule_wrap = function(fn)
        return fn
      end,
      json = {
        encode = function(t)
          -- Mock JSON encoding that preserves data for testing
          return t -- Return the table itself so we can inspect it
        end,
        decode = function(_)
          -- Return mock decoded response
          return {
            choices = {
              {
                message = {
                  content = "Refactored code here",
                },
              },
            },
          }
        end,
      },
      log = {
        levels = {
          ERROR = 2,
        },
      },
    }

    -- Mock config
    package.loaded["simple-ai-assist.config"] = {
      options = {
        api_key = "test-key",
        endpoint = "https://openrouter.ai/api/v1",
        model = "gpt-3.5-turbo",
      },
    }

    api = require("simple-ai-assist.api")
  end)

  describe("request_completion", function()
    it("should include language context in the prompt", function()
      local callback = spy.new(function() end)

      api.request_completion("Refactor this", "local x = 1", "lua", callback)

      assert.spy(curl_mock.post).was_called()
      local call = curl_mock.post.calls[1]
      local body = call.vals[2].body

      -- Check that the body includes Lua language context
      assert.is_not_nil(body.messages)
      assert.is_truthy(body.messages[1].content:match("Lua"))
      assert.is_truthy(body.messages[2].content:match("Lua"))
    end)

    it("should handle different language filetypes", function()
      local callback = spy.new(function() end)

      -- Test Python
      api.request_completion("Fix this", "def foo():\n  pass", "python", callback)
      assert.spy(curl_mock.post).was_called()
      local body = curl_mock.post.calls[1].vals[2].body
      assert.is_truthy(body.messages[1].content:match("Python"))

      -- Test JavaScript
      api.request_completion("Fix this", "function foo() {}", "javascript", callback)
      assert.spy(curl_mock.post).was_called()
      body = curl_mock.post.calls[2].vals[2].body
      assert.is_truthy(body.messages[1].content:match("JavaScript"))
    end)

    it("should handle missing API key", function()
      local config = require("simple-ai-assist.config")
      config.options.api_key = nil

      local callback = spy.new(function() end)

      api.request_completion("Refactor", "code", "lua", callback)

      assert.spy(callback).was_called_with(nil, "No API key configured")
    end)

    it("should handle API errors", function()
      -- Mock error response
      curl_mock.post = spy.new(function(_, opts)
        opts.callback({
          status = 500,
          body = "Server error",
        })
      end)

      local callback = spy.new(function() end)

      api.request_completion("Refactor", "code", "lua", callback)

      assert.spy(callback).was_called()
      local args = callback.calls[1].vals
      assert.is_nil(args[1]) -- response should be nil
      assert.is_not_nil(args[2]) -- error should be present
    end)

    it("should set correct headers for OpenRouter", function()
      api.request_completion("Refactor", "code", "lua", function() end)

      assert.spy(curl_mock.post).was_called()
      local headers = curl_mock.post.calls[1].vals[2].headers

      assert.equals("https://github.com/avastmick/simple-ai-assist.nvim", headers["HTTP-Referer"])
      assert.equals("simple-ai-assist.nvim", headers["X-Title"])
    end)
  end)
end)
