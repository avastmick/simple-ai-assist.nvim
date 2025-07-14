# Current Issues - simple-ai-assist.nvim

## Date: 2025-01-14

### Summary
The plugin successfully displays a floating window with AI assistance options, but there are critical issues with applying changes back to the source buffer.

## Working Features
- ✅ Visual selection capture (using `vim.fn.getregion` or yank fallback)
- ✅ Floating window display (85% width/height)
- ✅ Syntax highlighting for selected code
- ✅ AI API integration (OpenRouter/OpenAI/Anthropic)
- ✅ Diff-style view showing original vs proposed code
- ✅ Action selection (Explain/Refactor/Fix/Comment)

## Critical Issues

### 1. E21: Cannot make changes, 'modifiable' is off
- **Problem**: When pressing 'a' to accept changes, getting `E21` error
- **Root Cause**: The key 'a' in normal mode tries to enter insert mode (append) in the non-modifiable floating buffer
- **Attempted Fixes**:
  - Added `noremap = true, silent = true` to keymaps
  - Tried various buffer modification approaches
  - Attempted to switch to source buffer before applying changes
  - Used `pcall` to catch errors
  - Made buffer temporarily modifiable
- **Current Status**: Unresolved

### 2. Floating panel doesn't close after accepting
- **Problem**: The floating window remains open after pressing 'a'
- **Expected**: Window should close and changes should be applied to source buffer
- **Likely Cause**: The error preventing the changes from being applied also prevents the close operation

### 3. Key binding conflicts
- **Problem**: Single letter keys (a, r, etc.) conflict with normal Vim commands
- **Impact**: When buffer is non-modifiable, these keys try their default action first
- **Proposed Solution**: Use Ctrl-based keybindings

## Proposed Solutions

### 1. Change to Ctrl-based keybindings
```lua
keymaps = {
  trigger = "<leader>ac",  -- Keep this as is
  accept = "<C-a>",        -- Ctrl+A to accept (was 'a')
  retry = "<C-r>",         -- Ctrl+R to retry (was 'r')  
  cancel = "<Esc>",        -- Keep Escape as is
}

-- For actions:
actions = {
  { key = "<C-e>", label = "Explain" },
  { key = "<C-r>", label = "Refactor" }, 
  { key = "<C-f>", label = "Fix" },
  { key = "<C-c>", label = "Comment" },
}
```

### 2. Alternative approach for buffer modification
Instead of trying to modify from within the floating window context:
1. Store the changes in a temporary variable
2. Close the floating window completely
3. Focus on the source buffer window
4. Apply the changes
5. Show success notification

### 3. Debug approach
Add comprehensive logging to understand the exact state when the error occurs:
- Which buffer is current
- What is the modifiable state of each buffer
- Which window has focus
- Full stack trace of where E21 originates

## Code Locations to Review

1. **Keymap setup**: `lua/simple-ai-assist/ui.lua:140-248`
2. **Accept handler**: `lua/simple-ai-assist/ui.lua:161-229`
3. **Buffer modification**: `lua/simple-ai-assist/ui.lua:206-208`
4. **Visual selection**: `lua/simple-ai-assist/init.lua:20-51`

## Next Steps

1. **Immediate**: Change to Ctrl-based keybindings to avoid conflicts
2. **Debug**: Add detailed logging to trace the exact source of E21
3. **Refactor**: Simplify the accept flow - close window first, then apply changes
4. **Test**: Create minimal test case to isolate the issue
5. **Consider**: Using `vim.ui.input()` or `vim.ui.select()` for action selection instead of custom keymaps

## Technical Notes

- The error occurs even with `silent!` and `pcall` wrapping
- The floating buffer is correctly set to `modifiable = false`
- The source buffer should be modifiable (unless it's a readonly file)
- The issue might be related to which buffer/window has focus when the keymap is triggered

## Environment
- Neovim version: 0.11.x
- Plugin dependencies: plenary.nvim
- OS: macOS (Darwin 24.5.0)