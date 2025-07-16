-- Integration test to run inside Neovim
-- This test verifies the plugin loads and functions correctly in a real Neovim environment

local function test_plugin_loads()
  -- Test that the plugin can be required
  local ok, plugin = pcall(require, "simple-ai-assist")
  assert(ok, "Failed to load simple-ai-assist: " .. tostring(plugin))

  -- Test that setup function exists
  assert(type(plugin.setup) == "function", "setup function not found")

  -- Test that trigger_assistant function exists
  assert(type(plugin.trigger_assistant) == "function", "trigger_assistant function not found")

  print("✓ Plugin loads successfully")
end

local function test_plugin_without_api_key()
  -- Test that plugin loads without errors when no API key is present
  local plugin = require("simple-ai-assist")

  -- This should not error, even without API key
  local ok, err = pcall(plugin.setup)
  assert(ok, "Failed to setup plugin without API key: " .. tostring(err))

  -- Command should still be created
  local commands = vim.api.nvim_get_commands({})
  assert(commands.SimpleAIAssist ~= nil, "SimpleAIAssist command not created")

  print("✓ Plugin handles missing API key gracefully")
end

local function test_plugin_setup()
  local plugin = require("simple-ai-assist")

  -- Test setup with default options, providing API key directly
  local ok, err = pcall(plugin.setup, {
    api_key = "test-key-for-ci",
  })
  assert(ok, "Failed to setup plugin: " .. tostring(err))

  -- Check that user command was created
  local commands = vim.api.nvim_get_commands({})
  assert(commands.SimpleAIAssist ~= nil, "SimpleAIAssist command not created")

  -- Check that keymaps were set
  local keymaps = vim.api.nvim_get_keymap("v")
  local found_keymap = false
  for _, keymap in ipairs(keymaps) do
    if keymap.lhs == "<leader>ac" then
      found_keymap = true
      break
    end
  end
  assert(found_keymap, "Default keymap not set")

  print("✓ Plugin setup works correctly")
end

local function test_visual_selection()
  local plugin = require("simple-ai-assist")
  plugin.setup({
    api_key = "test-key", -- Provide test key to avoid error
  })

  -- Create a test buffer with some content
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "local function test()",
    "  print('hello')",
    "end",
  })
  vim.api.nvim_set_current_buf(buf)

  -- Test that trigger_assistant can be called
  -- Note: We can't fully test visual selection in headless mode,
  -- but we can verify the function doesn't error
  local ok, err = pcall(plugin.trigger_assistant)
  -- It should warn about no selection, which is expected
  assert(ok, "trigger_assistant failed: " .. tostring(err))

  print("✓ Visual selection handler works")
end

local function test_config_validation()
  local plugin = require("simple-ai-assist")

  -- Test with custom configuration, including API key
  local ok, err = pcall(plugin.setup, {
    api_key = "test-key-for-ci",
    model = "custom-model",
    keymaps = {
      trigger = "<leader>ai",
      accept = "<C-y>",
    },
    window = {
      width = 0.9,
      height = 0.9,
    },
  })
  assert(ok, "Failed to setup with custom config: " .. tostring(err))

  -- Verify custom keymaps were set
  local keymaps = vim.api.nvim_get_keymap("v")
  local found_custom_keymap = false
  for _, keymap in ipairs(keymaps) do
    if keymap.lhs == "<leader>ai" then
      found_custom_keymap = true
      break
    end
  end
  assert(found_custom_keymap, "Custom keymap not set")

  print("✓ Configuration validation works")
end

-- Helper to reset plugin state between tests
local function reset_plugin_state()
  -- Clear the package cache to force reload
  package.loaded["simple-ai-assist"] = nil
  package.loaded["simple-ai-assist.config"] = nil
  package.loaded["simple-ai-assist.ui"] = nil
  package.loaded["simple-ai-assist.api"] = nil

  -- Clear any existing keymaps
  pcall(vim.keymap.del, "v", "<leader>ac")
  pcall(vim.keymap.del, "v", "<leader>ai")

  -- Clear environment variables
  vim.env.OPENROUTER_API_KEY = nil
  vim.env.OPENAI_API_KEY = nil
  vim.env.ANTHROPIC_API_KEY = nil
end

-- Run all tests
local function run_tests()
  print("Running simple-ai-assist.nvim integration tests...")
  print("")

  local tests = {
    test_plugin_loads,
    test_plugin_without_api_key,
    test_plugin_setup,
    test_visual_selection,
    test_config_validation,
  }

  local passed = 0
  local failed = 0

  for _, test in ipairs(tests) do
    -- Reset state before each test
    reset_plugin_state()

    local ok, err = pcall(test)
    if ok then
      passed = passed + 1
    else
      failed = failed + 1
      print("✗ Test failed: " .. tostring(err))
    end
  end

  print("")
  print(string.format("Tests: %d passed, %d failed", passed, failed))

  -- Exit with appropriate code
  if failed > 0 then
    vim.cmd("cquit 1")
  else
    vim.cmd("quit")
  end
end

-- Run tests after a short delay to ensure Neovim is fully initialized
vim.defer_fn(run_tests, 100)
