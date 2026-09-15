local V = require('let.vocab')
local Lexer = require('let.lexer')
local A, List = V.Syntax, V.List
local Parser = {}
Parser.__index = Parser
function Parser.new(text, file)
    return setmetatable({ tokens = Lexer.new(text, file):scan(), pos = 1 }, Parser)
end
function Parser:token() return self.tokens[self.pos] end
function Parser:is(tag) return self:token().tag == tag end
function Parser:take() local t = self:token(); self.pos = self.pos + 1; return t end
function Parser:accept(tag) if self:is(tag) then return self:take() end end
function Parser:expect(tag)
    if not self:is(tag) then Lexer.fail(self:token().span, 'expected ' .. tag .. ', found ' .. self:token().tag) end
    return self:take()
end
function Parser:separators()
    local any = false
    while self:is(';') do self:take(); any = true end
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
        self:separators()
    end
    local terminal
    if self:is('do') then terminal = A.Body(self:body())
    else terminal = A.Data(self:transfer()) end
    return A.Chain(items, terminal, span)
end
function Parser:region(stops)
    local statements=List(); self:separators()
    while not stops[self:token().tag] do
        statements:insert(self:statement()); self:separators()
    end
    return statements
end
function Parser:body()
    self:expect('do'); local statements=self:region({['end']=true})
    self:expect('end'); return statements
end
function Parser:conditional(span)
    local condition=self:expression(); self:expect('do')
    local yes=self:region({['else']=true,['end']=true}); local no=List()
    if self:accept('else') then
        local next_=self:accept('if')
        if next_ then no:insert(self:conditional(next_.span)); return A.If(condition,yes,no,span) end
        no=self:region({['end']=true})
    end
    self:expect('end'); return A.If(condition,yes,no,span)
end
function Parser:case_label()
    local span=self:token().span
    if self:is('true') or self:is('false') then
        local label=self:atom(); return label,'Bool:' .. tostring(label.value),'Bool'
    end
    local negative=self:accept('-')~=nil
    local token=self:expect('integer'); local literal=A.Integer(token.text,token.span)
    require('let.integer')
    local hi,lo=literal:parts(negative)
    local key=((negative and (hi~=0 or lo~=0)) and '-' or '') .. hi .. ':' .. lo
    return negative and A.Unary('-',literal,span) or literal,key,'Int'
end
function Parser:selection(span)
    local subject=self:expression(); self:expect('do'); self:separators()
    local arms,seen={},{}; local shape
    self.switch_id=(self.switch_id or 0)+1
    local name='$switch' .. self.switch_id -- cannot collide with any source identifier
    while self:accept('case') do
        local condition
        repeat
            local label,key,kind=self:case_label()
            if shape and shape~=kind then Lexer.fail(label.span,'case labels must have the same type') end
            shape=kind
            if seen[key] then Lexer.fail(label.span,'duplicate case label') end; seen[key]=true
            local test=A.Binary('==',A.Name(name,span),label,label.span)
            condition=condition and A.Binary('or',condition,test,label.span) or test
        until not self:accept(',')
        arms[#arms+1]={condition=condition,body=self:region({case=true,['else']=true,['end']=true})}
    end
    if #arms==0 then Lexer.fail(span,'switch requires at least one case') end
    local tail=List(); local last=#arms
    if self:accept('else') then tail=self:region({['end']=true})
    elseif seen['Bool:true'] and seen['Bool:false'] then
        tail=arms[last].body; last=last-1 -- both Boolean values make selection exhaustive
    end
    self:expect('end')
    for i=last,1,-1 do tail=List{A.If(arms[i].condition,arms[i].body,tail,span)} end
    local binding=A.Binding(name,false,shape,A.Chain(List(),A.Data(subject),span),span)
    local body=List{A.Local(binding,span)}; body:insertall(tail)
    return A.Switch(body,span)
end
function Parser:statement()
    local t = self:token()
    if t.tag == 'let' then return A.Local(self:binding(), t.span) end
    if self:accept('return') then
        local value
        if not self:is(';') and not self:is('end') and not self:is('else') and not self:is('case') then value = self:transfer() end
        return A.Return(value, t.span)
    end
    if self:accept('if') then return self:conditional(t.span) end
    if self:accept('switch') then return self:selection(t.span) end
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
        local value = self:expression(); self:expect(')'); return value
    end
    Lexer.fail(t.span, 'expected expression, found ' .. t.tag)
end
function Parser:postfix()
    local value = self:atom()
    while self:accept('(') do
        local args = List()
        if not self:is(')') then
            repeat
                local token = self:accept('mut')
                args:insert(token and A.Borrow(self:expect('name').text, token.span) or self:transfer())
            until not self:accept(',')
        end
        self:expect(')')
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
    while self:is('name') or self:is('integer') or self:is('true') or self:is('false') or self:is('{') or self:is('move') do
        -- Assignment has an explicit boundary even without a leading keyword.
        if self:is('name') and self.tokens[self.pos + 1].tag == '=' then break end
        value = A.Specialize(value, self:specialization_atom(), value.span)
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
        self:separators()
    end
    return A.Program(bindings)
end
function Parser:transfer()
    local token = self:accept('move')
    if token then return A.Move(self:expect('name').text, token.span) end
    return self:expression()
end
return Parser

