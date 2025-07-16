-- Luacheck configuration for simple-ai-assist.nvim

globals = {
  "vim",
}

read_globals = {
  -- Test framework globals
  "describe",
  "it",
  "before_each",
  "after_each",
  "spy",
  "stub",
  "mock",
  "match",
  "assert",
}

-- Exclude test files from certain checks
files["tests/*.lua"] = {
  globals = {
    "vim", -- Allow redefining vim in tests
  },
}

max_line_length = 120

exclude_files = {
  ".luacheckrc",
}

