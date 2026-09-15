local V = require('let.vocab')
local Lexer = require('let.lexer')
local A, List = V.Syntax, V.List
local Parser = {}
Parser.__index = Parser
function Parser.new(text, file)
    return setmetatable({ tokens = Lexer.new(text, file):scan(), pos = 1, nesting = 0 }, Parser)
end
function Parser:token()
    while self.nesting > 0 and self.tokens[self.pos].tag == 'newline' do self.pos = self.pos + 1 end
    return self.tokens[self.pos]
end
function Parser:is(tag) return self:token().tag == tag end
function Parser:take() local t = self:token(); self.pos = self.pos + 1; return t end
function Parser:accept(tag) if self:is(tag) then return self:take() end end
function Parser:expect(tag)
    if not self:is(tag) then Lexer.fail(self:token().span, 'expected ' .. tag .. ', found ' .. self:token().tag) end
    return self:take()
end
function Parser:separators()
    local any = false
    while self:is('newline') or self:is(';') do self:take(); any = true end
    return any
end
function Parser:annotation()
    if self:accept(':') then return self:expect('name').text end
end
function Parser:binding_header()
    local start = self:expect('let').span
    local name = self:expect('name').text
    local own = self:accept('own') ~= nil
    local mutable = self:accept('mut') ~= nil
    if self:is('own') then Lexer.fail(self:token().span, 'qualifier order must be own mut') end
    local cap = own and (mutable and V.Semantic.OwnMut or V.Semantic.Own) or (mutable and V.Semantic.Mut or V.Semantic.Read)
    return start, name, mutable, self:annotation(), cap
end
function Parser:binding()
    local span, name, mutable, annotation, cap = self:binding_header()
    if cap == V.Semantic.Own or cap == V.Semantic.OwnMut then Lexer.fail(span, 'own is only valid on an unsatisfied stage') end
    self:expect('='); self:separators()
    return A.Binding(name, mutable, annotation, self:chain(), span)
end
function Parser:chain()
    local span, items = self:token().span, List()
    while self:is('let') do
        local at, name, mutable, annotation, cap = self:binding_header()
        if self:accept('=') then
            if cap == V.Semantic.Own or cap == V.Semantic.OwnMut then Lexer.fail(at, 'own is only valid on an unsatisfied stage') end
            self:separators()
            items:insert(A.Prelude(A.Binding(name, mutable, annotation, self:chain(), at)))
        else
            items:insert(A.Stage(name, annotation, cap, at))
        end
        if not self:separators() then Lexer.fail(self:token().span, 'expected separator after chain item') end
    end
    local terminal
    if self:is('do') then terminal = A.Body(self:body())
    else terminal = A.Data(self:transfer()) end
    return A.Chain(items, terminal, span)
end
function Parser:body()
    self:expect('do')
    local old = self.nesting; self.nesting = 0
    self:separators()
    local statements = List()
    while not self:is('end') do
        statements:insert(self:statement())
        if not self:separators() and not self:is('end') then Lexer.fail(self:token().span, 'expected statement separator') end
    end
    self:expect('end'); self.nesting = old
    return statements
end
function Parser:statement()
    local t = self:token()
    if t.tag == 'let' then return A.Local(self:binding(), t.span) end
    if self:accept('return') then
        local value
        if not self:is('newline') and not self:is(';') and not self:is('end') then value = self:transfer() end
        return A.Return(value, t.span)
    end
    if self:accept('if') then
        local condition, yes = self:expression(), nil
        yes = self:body()
        local save = self.pos
        self:separators()
        local no = List()
        if self:accept('else') then no = self:body() else self.pos = save end
        return A.If(condition, yes, no, t.span)
    end
    if self:accept('while') then
        local condition = self:expression()
        return A.While(condition, self:body(), t.span)
    end
    if t.tag == 'name' and self.tokens[self.pos + 1].tag == '=' then
        self:take(); self:take(); self:separators()
        return A.Assign(t.text, self:transfer(), t.span)
    end
    return A.Discard(self:expression(), t.span)
end
local precedence = { ['or'] = 1, ['and'] = 2, ['=='] = 3, ['!='] = 3,
    ['<'] = 4, ['<='] = 4, ['>'] = 4, ['>='] = 4, ['+'] = 5, ['-'] = 5, ['*'] = 6, ['/'] = 6, ['%'] = 6 }
function Parser:atom()
    local t = self:take()
    if t.tag == 'name' then return A.Name(t.text, t.span) end
    if t.tag == 'integer' then return A.Integer(t.text, t.span) end
    if t.tag == 'true' or t.tag == 'false' then return A.Boolean(t.tag == 'true', t.span) end
    if t.tag == '{' then self:separators(); self:expect('}'); return A.Unit(t.span) end
    if t.tag == '(' then
        self.nesting = self.nesting + 1
        local value = self:expression(); self:expect(')'); self.nesting = self.nesting - 1
        return value
    end
    Lexer.fail(t.span, 'expected expression, found ' .. t.tag)
end
function Parser:postfix()
    local value = self:atom()
    while self:accept('(') do
        self.nesting = self.nesting + 1
        local args = List()
        if not self:is(')') then
            repeat
                local token = self:accept('mut')
                args:insert(token and A.Borrow(self:expect('name').text, token.span) or self:transfer())
            until not self:accept(',')
        end
        self:expect(')'); self.nesting = self.nesting - 1
        value = A.Invoke(value, args, value.span)
    end
    return value
end
function Parser:specialization_atom()
    if self:is('move') then return self:transfer() end
    if self:is('name') then return self:postfix() end
    if self:is('integer') or self:is('true') or self:is('false') or self:is('{') then return self:atom() end
    Lexer.fail(self:token().span, 'expected specialization atom')
end
function Parser:prefix()
    local t = self:token()
    if self:accept('-') or self:accept('not') then return A.Unary(t.text, self:prefix(), t.span) end
    local value = self:postfix()
    if self:accept('with') then
        repeat value = A.Specialize(value, self:specialization_atom(), value.span) until not self:accept('with')
        if self:is('name') or self:is('integer') or self:is('true') or self:is('false') or self:is('{') or self:is('move') then
            Lexer.fail(self:token().span, 'mixed specialization spelling')
        end
    else
        while self:is('name') or self:is('integer') or self:is('true') or self:is('false') or self:is('{') or self:is('move') do
            value = A.Specialize(value, self:specialization_atom(), value.span)
        end
        if self:is('with') then Lexer.fail(self:token().span, 'mixed specialization spelling') end
    end
    return value
end
function Parser:expression(minimum)
    minimum = minimum or 1
    local left, used = self:prefix(), {}
    while true do
        local t = self:token(); local p = precedence[t.tag]
        if not p or p < minimum then break end
        if (p == 3 or p == 4) and used[p] then Lexer.fail(t.span, 'chained comparison is invalid') end
        used[p] = true; self:take()
        left = A.Binary(t.tag, left, self:expression(p + 1), t.span)
    end
    return left
end
function Parser:parse()
    local bindings = List(); self:separators()
    while not self:is('eof') do
        bindings:insert(self:binding())
        if not self:separators() and not self:is('eof') then Lexer.fail(self:token().span, 'expected declaration separator') end
    end
    return A.Program(bindings)
end
function Parser:transfer()
    local token = self:accept('move')
    if token then return A.Move(self:expect('name').text, token.span) end
    return self:expression()
end
return Parser

