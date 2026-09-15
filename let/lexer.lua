local V = require('let.vocab')
local S, List = V.Source, V.List
local Lexer = {}
Lexer.__index = Lexer
local keywords = {}
for word in ('let with do end own mut move return if else while and or not true false'):gmatch('%S+') do
    keywords[word] = true
end
function Lexer.new(text, file)
    return setmetatable({ text = text, file = file or '<input>', pos = 1, line = 1, column = 1 }, Lexer)
end
function Lexer:span() return S.Span(self.file, self.line, self.column) end
function Lexer.fail(span, message)
    error(('%s:%d:%d: %s'):format(span.file, span.line, span.column, message), 0)
end
function Lexer:take(n)
    local text = self.text:sub(self.pos, self.pos + n - 1)
    for c in text:gmatch('.') do
        if c == '\n' then self.line, self.column = self.line + 1, 1
        else self.column = self.column + 1 end
    end
    self.pos = self.pos + n
    return text
end
function Lexer:next()
    while true do
        local c = self.text:sub(self.pos, self.pos)
        if c == ' ' or c == '\t' or c == '\r' then self:take(1)
        elseif self.text:sub(self.pos, self.pos + 1) == '//' then
            while self.pos <= #self.text and self.text:sub(self.pos, self.pos) ~= '\n' do self:take(1) end
        else break end
    end
    local span, rest = self:span(), self.text:sub(self.pos)
    if rest == '' then return S.Token('eof', '', span) end
    local c = rest:sub(1, 1)
    if c == '\n' then return S.Token('newline', self:take(1), span) end
    local name = rest:match('^[A-Za-z_][A-Za-z_0-9]*')
    if name then return S.Token(keywords[name] and name or 'name', self:take(#name), span) end
    if c:match('[0-9]') then
        local digits = rest:match('^[A-Za-z_0-9]+')
        local body, pattern = digits, '^[0-9]+$'
        if digits:sub(1, 2) == '0x' then body, pattern = digits:sub(3), '^[0-9a-fA-F]+$' end
        if body:sub(1, 1) == '_' or body:sub(-1) == '_' or body:find('__', 1, true) or not body:gsub('_', ''):match(pattern) then
            Lexer.fail(span, 'invalid integer literal')
        end
        return S.Token('integer', self:take(#digits), span)
    end
    local two = rest:sub(1, 2)
    if two == '<=' or two == '>=' or two == '==' or two == '!=' then return S.Token(two, self:take(2), span) end
    if c:match('[=;(),{}:+*/%%<>%-]') then return S.Token(c, self:take(1), span) end
    if c == '"' then Lexer.fail(span, 'Text is not supported by the scalar bootstrap yet') end
    Lexer.fail(span, 'unexpected character ' .. string.format('%q', c))
end
function Lexer:scan()
    local tokens = List()
    repeat tokens:insert(self:next()) until tokens[#tokens].tag == 'eof'
    return tokens
end
return Lexer

