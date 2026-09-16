-- Lexer-driven highlighting for Neovim.
--
-- The tokenizer is the compiler's own: ide/tokens.lua drives let/lex.lua, and this module
-- only paints what the scanner reports, using buffer-local extmarks. There is no Vim
-- regex grammar to drift from the language, and a keyword can never be highlighted inside
-- a Text literal or a comment because the scanner never produces a keyword token there.
--
-- Attached from ftplugin/let.vim. Requires this directory on 'runtimepath'.

local M = {}

local namespace = vim.api.nvim_create_namespace('letide-highlight')

-- Display category (ide/tokens.lua) to highlight group.
local groups = {
    keyword = 'LetKeyword',
    conditional = 'LetConditional',
    ['repeat'] = 'LetRepeat',
    boolean = 'LetBoolean',
    operator = 'LetOperator',
    number = 'LetNumber',
    string = 'LetString',
    comment = 'LetComment',
    delimiter = 'LetDelimiter',
    variable = 'LetVariable',
    type = 'LetType',
}

local links = {
    LetKeyword = 'Keyword', LetConditional = 'Conditional', LetRepeat = 'Repeat',
    LetBoolean = 'Boolean', LetOperator = 'Operator', LetNumber = 'Number',
    LetString = 'String', LetComment = 'Comment', LetDelimiter = 'Delimiter',
    LetVariable = 'Identifier', LetType = 'Type',
}

local attached, pending = {}, {}
local loaded

-- This file lives at <repository>/ide/nvim/lua/letide.lua. The compiler modules are found
-- by putting the repository root on package.path, exactly as letc.lua and letls.lua do.
local function modules()
    if loaded ~= nil then return loaded end
    local source = debug.getinfo(1, 'S').source:sub(2)
    local repository = source:match('^(.*)/ide/nvim/lua/letide%.lua$')
    if not repository then
        loaded = false
        return loaded
    end
    package.path = repository .. '/?.lua;' .. repository .. '/?/init.lua;' .. package.path
    local ok, tokens = pcall(require, 'ide.tokens')
    if not ok then
        loaded = false
        vim.notify('let: cannot load the compiler lexer: ' .. tostring(tokens), vim.log.levels.WARN)
        return loaded
    end
    loaded = {tokens = tokens, text = require('ide.text')}
    return loaded
end

local function paint(buf)
    local module = modules()
    if not module then return end
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
    local document = module.text.new(text)
    local scan = module.tokens.scan(text, vim.api.nvim_buf_get_name(buf))
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    for _, comment in ipairs(scan.comments) do
        vim.api.nvim_buf_set_extmark(buf, namespace, comment.span.line - 1,
            document:byte_column(comment.span), {
                end_line = comment.stop.line - 1,
                end_col = document:byte_column(comment.stop),
                hl_group = groups.comment,
                priority = 101,
            })
    end
    for _, token in ipairs(scan.tokens) do
        local group = groups[module.tokens.category(token) or '']
        if group then
            local start = document:byte_column(token.span)
            vim.api.nvim_buf_set_extmark(buf, namespace, token.span.line - 1, start, {
                end_col = start + #token.spelling,
                hl_group = group,
                priority = 100,
            })
        end
    end
end

-- Coalesce a burst of edits into one repaint. `on_lines` runs on every keystroke; a
-- 30 ms delay keeps typing responsive on large files.
local function schedule(buf)
    if pending[buf] then return end
    pending[buf] = true
    vim.defer_fn(function()
        pending[buf] = nil
        if vim.api.nvim_buf_is_valid(buf) then paint(buf) end
    end, 30)
end

function M.attach(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    if attached[buf] then return end
    attached[buf] = true
    for name, target in pairs(links) do
        vim.api.nvim_set_hl(0, name, {link = target, default = true})
    end
    vim.api.nvim_buf_attach(buf, false, {
        on_lines = function() schedule(buf) return false end,
        on_reload = function() schedule(buf) end,
    })
    paint(buf)
end

function M.detach(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    attached[buf] = nil
    vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
end

return M
