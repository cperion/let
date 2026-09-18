-- LSP semantic tokens.
--
-- The lexical answer comes from the compiler's scanner (ide/tokens.lua); names are then refined
-- by the symbol index, so a stage paints as a parameter and a word as a function. Without an
-- index the lexical answer stands, which is what a file with no resolution gets.
--
-- Delimiters are deliberately not reported: punctuation is an editor concern, and reporting it
-- would override a client's own styling for no semantic gain. Comments come from the scanner's
-- trivia, so the same `//` rule produces them.
--
-- The protocol encodes tokens as a flat delta array: for each token, line delta, character
-- delta, UTF-16 length, token type index, and modifier bits.

local tokens = require('ide.tokens')

local M = {}

-- Standard LSP semantic token names, in legend order.
M.types = {'variable', 'type', 'number', 'string', 'comment', 'operator', 'keyword',
    'parameter', 'function', 'namespace'}
M.modifiers = {'declaration', 'readonly'}

local type_index, modifier_bit = {}, {}
for position, name in ipairs(M.types) do type_index[name] = position - 1 end
for position, name in ipairs(M.modifiers) do modifier_bit[name] = 2 ^ (position - 1) end

-- Display category (ide/tokens.lua) to semantic token type. A category with no entry is not
-- reported.
local semantic = {
    variable = 'variable', type = 'type', number = 'number', string = 'string',
    comment = 'comment', operator = 'operator', keyword = 'keyword',
    conditional = 'keyword', ['repeat'] = 'keyword', boolean = 'keyword',
}

function M.encode(document, file, scan, symbols)
    local items = {}
    for _, comment in ipairs(scan.comments) do
        items[#items + 1] = {span = comment.span, stop = comment.stop, type = type_index.comment, modifiers = 0}
    end
    for _, token in ipairs(scan.tokens) do
        local type_, modifiers
        if token.kind == 'name' and symbols then
            local record = symbols:at(file, document:offset(token.span))
            local classified = record and symbols:classify(record)
            if classified and type_index[classified.type] then
                type_ = type_index[classified.type]
                modifiers = 0
                for _, modifier in ipairs(classified.modifiers) do
                    modifiers = modifiers + (modifier_bit[modifier] or 0)
                end
            end
        end
        if not type_ then
            local name = semantic[tokens.category(token) or '']
            if name then type_ = type_index[name] end
            modifiers = 0
        end
        if type_ then
            items[#items + 1] = {span = token.span, length = #token.spelling, type = type_, modifiers = modifiers}
        end
    end
    table.sort(items, function(a, b)
        if a.span.line ~= b.span.line then return a.span.line < b.span.line end
        return a.span.column < b.span.column
    end)

    local data = {}
    local last_line, last_character = 0, 0
    for _, item in ipairs(items) do
        local start = document:position(item.span)
        local stop = item.stop and document:position(item.stop)
            or document:token_range(item.span, item.length)['end']
        local length = stop.character - start.character
        if length < 1 then length = 1 end
        data[#data + 1] = start.line - last_line
        data[#data + 1] = (start.line == last_line) and (start.character - last_character) or start.character
        data[#data + 1] = length
        data[#data + 1] = item.type
        data[#data + 1] = item.modifiers or 0
        last_line, last_character = start.line, start.character
    end
    return {data = data}
end

return M
