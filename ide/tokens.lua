-- One classification of Let source, produced by the compiler's own scanner.
--
-- The editor highlighter (ide/nvim/lua/let/highlight.lua) and the language server both
-- require this module, so there is exactly one tokenizer and one mapping from syntax to a
-- display category. Nothing here restates a lexical rule: `Source.Token.kind` is already
-- the scanner's spelling for a keyword and its class for everything else (let/lex.lua),
-- and the scalar type names come from the compiler's vocabulary (let/vocabulary.lua).
--
-- `scan` is tolerant on purpose. An editor asks about text that is mid-keystroke and
-- therefore often unlexable; the compiler's scanner fails fast, so this recovers one byte
-- at a time and reports what it could read.

local V = require('let')

local M = {}

-- Category names are display-level, not language-level: they say how to paint a token,
-- not what it means. A consumer maps them to its own vocabulary (highlight groups, LSP
-- semantic token types).
local categories = {
    name = 'variable',
    integer = 'number', float = 'number',
    text = 'string',
    ['true'] = 'boolean', ['false'] = 'boolean',
    ['if'] = 'conditional', ['else'] = 'conditional', ['switch'] = 'conditional', ['case'] = 'conditional',
    ['while'] = 'repeat', ['break'] = 'repeat', ['continue'] = 'repeat',
    ['and'] = 'operator', ['or'] = 'operator', ['not'] = 'operator',
    ['let'] = 'keyword', ['do'] = 'keyword', ['end'] = 'keyword', ['own'] = 'keyword',
    ['mut'] = 'keyword', ['move'] = 'keyword', ['return'] = 'keyword',
    ['extern'] = 'keyword', ['pure'] = 'keyword',
    ['=='] = 'operator', ['!='] = 'operator', ['<='] = 'operator', ['>='] = 'operator',
    ['<'] = 'operator', ['>'] = 'operator', ['='] = 'operator',
    ['+'] = 'operator', ['-'] = 'operator', ['*'] = 'operator', ['/'] = 'operator',
    ['%'] = 'operator', ['&'] = 'operator', ['|'] = 'operator', ['^'] = 'operator',
    ['~'] = 'operator', ['<<'] = 'operator', ['>>'] = 'operator', ['->'] = 'operator',
    ['('] = 'delimiter', [')'] = 'delimiter', ['{'] = 'delimiter', ['}'] = 'delimiter',
    ['['] = 'delimiter', [']'] = 'delimiter', [';'] = 'delimiter', [','] = 'delimiter',
    [':'] = 'delimiter', ['.'] = 'delimiter',
}

-- The base type names the compiler itself knows, so a program's `Int` paints as a type
-- without the editor keeping a second list.
local scalars = {}
for _, name in ipairs(V.Vocabulary.scalars) do scalars[name] = true end

-- A scanner failure is reported as `file:line:column: message` by Lexer.fail. The file
-- may itself contain colons, so the numbers are taken from the right.
local function failure(message)
    local line, column, text = tostring(message):match(':(%d+):(%d+): (.*)$')
    if not line then return nil end
    return {line = tonumber(line), column = tonumber(column), message = text}
end

-- Advance the scanner one byte without validating UTF-8, so a buffer that is momentarily
-- invalid still makes progress. This is the scanner's own line/column bookkeeping.
local function recover(lexer)
    if lexer.pos > #lexer.text then return false end
    local byte = lexer.text:byte(lexer.pos)
    lexer.pos = lexer.pos + 1
    if byte == 13 then
        lexer.line, lexer.column, lexer.cr = lexer.line + 1, 1, true
    elseif byte == 10 then
        if not lexer.cr then lexer.line = lexer.line + 1 end
        lexer.column, lexer.cr = 1, false
    else
        lexer.column, lexer.cr = lexer.column + 1, false
    end
    return true
end

-- Scan `text` into tokens, comments, and lexical errors. Tokens carry the compiler's
-- Source.Span; `spelling` is the exact source bytes, so a consumer needs no re-decoding.
function M.scan(text, file)
    local lexer = V.Lexer.new(text, file or '<source>', {trivia = true})
    local tokens, errors = {}, {}
    while true do
        local ok, token = pcall(lexer.next, lexer)
        if ok then
            if token.kind == 'eof' then break end
            tokens[#tokens + 1] = token
        else
            local at = failure(token)
            if at then
                errors[#errors + 1] = {
                    message = at.message,
                    start = {line = at.line, column = at.column},
                    stop = {line = lexer.line, column = lexer.column},
                }
            end
            if not recover(lexer) then break end
        end
    end
    return {tokens = tokens, comments = lexer.trivia or {}, errors = errors}
end

-- The display category of a token, or nil for a token with no category (none currently,
-- but a new scanner kind should not be mislabeled by default).
function M.category(token)
    if token.kind == 'name' and scalars[token.spelling] then return 'type' end
    return categories[token.kind]
end

return M
