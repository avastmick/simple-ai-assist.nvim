local M = {}

M.defaults = {
    api_key = vim.env.OPENROUTER_API_KEY,
    endpoint = "https://openrouter.ai/api/v1",
    model = "anthropic/claude-sonnet-4",
    keymaps = {
        trigger = "<leader>ac",
        accept = "a",
        retry = "r",
        cancel = "<Esc>",
    },
    window = {
        width = 0.7,
        height = 0.7,
        border = "rounded",
    },
    actions = {
        { key = "e", label = "Explain",  prompt = "Explain this code in detail:" },
        { key = "r", label = "Refactor", prompt = "Suggest improvements for this code:" },
        { key = "f", label = "Fix",      prompt = "Find and fix issues in this code:" },
        { key = "c", label = "Comment",  prompt = "Add appropriate comments to this code:" },
    }
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})

    if not M.options.api_key then
        if vim.env.OPENAI_API_KEY then
            M.options.api_key = vim.env.OPENAI_API_KEY
            M.options.endpoint = "https://api.openai.com/v1"
            M.options.model = "gpt-4o"
        elseif vim.env.ANTHROPIC_API_KEY then
            M.options.api_key = vim.env.ANTHROPIC_API_KEY
            M.options.endpoint = "https://api.anthropic.com/v1"
            M.options.model = "claude-sonnet-4"
        else
            vim.notify("No API key found. Please set OPENROUTER_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY",
                vim.log.levels.ERROR)
        end
    end
end

return M

