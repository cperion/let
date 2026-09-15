-- Let grammar (§3), independent of the current compiler. Parsing preserves words,
-- preludes, aggregates and places even where belt construction is still pending.
return function(V)
local A,L,Lexer=V.AST,V.List,V.Lexer
local fail=Lexer.fail; local literal=require('let.literal')
local Parser={}; Parser.__index=Parser
function Parser:token() return self.tokens[self.pos] end
function Parser:is(kind) return self:token().kind==kind end
function Parser:take() local t=self:token(); self.pos=self.pos+1; return t end
function Parser:accept(kind) if self:is(kind) then return self:take() end end
function Parser:expect(kind)
    if not self:is(kind) then fail(self:token().span,'expected ' .. kind .. ', found ' .. self:token().kind) end
    return self:take()
end
function Parser:separators() while self:accept(';') do end end
-- Bounded lexical lookahead for place '='. It never builds or evaluates an index.
function Parser:assignment_ahead()
    local at=self.pos
    if self.tokens[at].kind~='name' then return false end; at=at+1
    while true do
        if self.tokens[at].kind=='.' then
            at=at+1; if self.tokens[at].kind~='name' then return false end; at=at+1
        elseif self.tokens[at].kind=='[' then
            local depth=1; at=at+1
            while depth>0 do
                local token=self.tokens[at]; if not token or token.kind=='eof' then return false end
                if token.kind=='[' then depth=depth+1 elseif token.kind==']' then depth=depth-1 end
                at=at+1
            end
        else return self.tokens[at].kind=='=' end
    end
end
function Parser:constraint()
    local name=self:expect('name'); local arguments=L()
    while true do
        if self:is('name') then local token=self:take(); arguments:insert(A.Name(token.spelling,token.span))
        elseif self:is('integer') or self:is('text') or self:is('true') or self:is('false') then arguments:insert(self:atom())
        elseif self:accept('(') then
            local span=self:token().span; local nested=self:constraint(); self:expect(')')
            local value=A.Name(nested.name,span)
            for _,argument in ipairs(nested.arguments) do value=A.Specialize(value,argument,span) end
            arguments:insert(value)
        else break end
    end
    return A.Constraint(name.spelling,arguments)
end
function Parser:header()
    local span=self:expect('let').span; local name=self:expect('name').spelling
    local own=self:accept('own')~=nil; local mutable=self:accept('mut')~=nil
    if self:is('own') or self:is('mut') then fail(self:token().span,'qualifiers must occur once in own mut order') end
    local constraint=self:accept(':') and self:constraint() or nil
    return name,own,mutable,constraint,span
end
function Parser:binding()
    local name,own,mutable,constraint,span=self:header()
    if own then fail(span,'own is only valid on an unsatisfied stage') end
    self:expect('='); self:separators()
    return A.Binding(name,mutable,constraint,self:chain(),span)
end
-- The chain items: consecutive `let` forms, an unsatisfied one being a stage.
function Parser:items()
    local items=L()
    while self:is('let') do
        local name,own,mutable,constraint,at=self:header()
        if self:accept('=') then
            if own then fail(at,'own is only valid on an unsatisfied stage') end
            self:separators(); items:insert(A.Prelude(A.Binding(name,mutable,constraint,self:chain(),at)))
        else
            local cap=own and (mutable and A.OwnMut or A.Own) or (mutable and A.Mut or A.Read)
            items:insert(A.Stage(name,cap,constraint,at))
        end
        self:separators()
    end
    return items
end

-- A chain in an expression position always has a written terminal. A source file may omit
-- it, in which case the terminal is the namespace of the file's own prelude bindings.
function Parser:chain(optional_terminal)
    local span=self:token().span
    local items=self:items()
    local terminal
    if self:is('do') then terminal=A.Body(self:body())
    elseif optional_terminal and self:is('eof') then terminal=nil
    else terminal=A.Data(self:transfer()) end
    return A.Chain(items,terminal,span)
end
function Parser:value()
    local chain=self:chain()
    if #chain.items==0 and A.Data:isclassof(chain.terminal) then return chain.terminal.value end
    return A.Word(chain,chain.span)
end
function Parser:region(stops)
    local statements=L(); self:separators()
    while not stops[self:token().kind] do
        if self:is('eof') then fail(self:token().span,'unterminated control/body region') end
        statements:insert(self:statement()); self:separators()
    end
    return statements
end
function Parser:body()
    self:expect('do'); local body=self:region({['end']=true}); self:expect('end'); return body
end
function Parser:conditional(span)
    local condition=self:expression(); self:expect('do')
    local yes=self:region({['else']=true,['end']=true}); local no=L()
    if self:accept('else') then
        local next_=self:accept('if')
        if next_ then no:insert(self:conditional(next_.span)); return A.If(condition,yes,no,span) end
        no=self:region({['end']=true})
    end
    self:expect('end'); return A.If(condition,yes,no,span)
end
function Parser:label()
    local at=self:token().span
    if self:is('true') or self:is('false') then local value=self:atom(); return value,'Bool:' .. tostring(value.value),'Bool' end
    local negative=self:accept('-')~=nil; local token=self:expect('integer')
    local _,key=literal.integer(token.spelling,negative,function(m) fail(token.span,m) end)
    local value=A.Integer(token.spelling,token.span)
    return negative and A.Unary(A.Negate,value,at) or value,'Int:' .. key,'Int'
end
function Parser:selection(span)
    local subject=self:expression(); self:expect('do'); self:separators()
    local cases,otherwise,seen=L(),L(),{}; local kind
    while self:accept('case') do
        local at=self:token().span; local labels=L()
        repeat
            local value,key,type_=self:label()
            if kind and kind~=type_ then fail(value.span,'case labels must have the same type') end; kind=type_
            if seen[key] then fail(value.span,'duplicate case label') end; seen[key]=true; labels:insert(value)
        until not self:accept(',')
        cases:insert(A.Case(labels,self:region({case=true,['else']=true,['end']=true}),at))
    end
    if #cases==0 then fail(span,'switch requires at least one case') end
    if self:accept('else') then otherwise=self:region({['end']=true}) end
    self:expect('end'); return A.Switch(subject,cases,otherwise,span)
end
function Parser:place()
    local token=self:expect('name'); local value=A.Name(token.spelling,token.span)
    while true do
        if self:accept('.') then value=A.Project(value,self:expect('name').spelling,value.span)
        elseif self:accept('[') then local index=self:expression(); self:expect(']'); value=A.Index(value,index,value.span)
        else return value end
    end
end
function Parser:statement()
    local token=self:token()
    if self:is('let') then return A.Local(self:binding(),token.span) end
    if self:accept('return') then
        local value
        if not self:is(';') and not self:is('end') and not self:is('else') and not self:is('case') then value=self:value() end
        return A.Return(value,token.span)
    end
    if self:accept('if') then return self:conditional(token.span) end
    if self:accept('switch') then return self:selection(token.span) end
    if self:accept('while') then local condition=self:expression(); return A.While(condition,self:body(),token.span) end
    -- §7.3 makes any expression a statement, and §9.2 admits `move place` as an
    -- expression. A leading `move` is otherwise recognized only where a transfer
    -- value is expected, so `move a.x` as a statement would be read as a
    -- continuation of the previous value instead of a move.
    if self:is('move') then
        local moved=self:take()
        return A.Discard(A.Move(self:place(),moved.span),token.span)
    end
    if self:assignment_ahead() then
        local place=self:place(); self:expect('='); self:separators(); return A.Assign(place,self:value(),token.span)
    end
    return A.Discard(self:expression(),token.span)
end
function Parser:named_members()
    local members=L()
    repeat members:insert(self:binding()); self:separators() until not self:is('let')
    self:expect('}'); return members
end
function Parser:aggregate()
    local start=self.pos; local cached=self.aggregates[start]
    if cached then if cached.error then error(cached.error,0) end; self.pos=cached.next; return cached.value end
    local span=self:expect('{').span; local body=self.pos; self:separators(); local value
    if self:accept('}') then value=A.Unit(span)
    else
        local named_error
        if self:is('let') then
            -- A positional element can itself be a chain beginning with a prelude.
            -- Prefer a complete named aggregate; otherwise parse a binding-value list.
            -- Memoized nested aggregates prevent exponential re-parsing.
            local trial=setmetatable({tokens=self.tokens,pos=self.pos,aggregates=self.aggregates},Parser)
            local ok,members=pcall(function() return trial:named_members() end)
            if ok then self.pos=trial.pos; value=A.NamedAggregate(members,span) else named_error=members end
        end
        if not value then
            self.pos=body
            local ok,result=pcall(function()
                local elements=L{self:chain()}
                while self:accept(',') do if self:is('}') then break end; elements:insert(self:chain()) end
                self:expect('}'); return A.PositionalAggregate(elements,span)
            end)
            if not ok then
                local message=named_error or result; self.aggregates[start]={error=message}; error(message,0)
            end
            value=result
        end
    end
    self.aggregates[start]={value=value,next=self.pos}; return value
end
function Parser:atom()
    local token=self:token()
    if self:accept('name') then return A.Name(token.spelling,token.span) end
    if self:accept('integer') then return A.Integer(token.spelling,token.span) end
    if self:accept('float') then return A.Float(token.spelling,token.span) end
    if self:accept('text') then return A.Text(token.value,token.span) end
    if self:accept('true') then return A.Boolean(true,token.span) end
    if self:accept('false') then return A.Boolean(false,token.span) end
    if self:accept('(') then local value=self:expression(); self:expect(')'); return value end
    if self:is('{') then return self:aggregate() end
    fail(token.span,'expected expression, found ' .. token.kind)
end
function Parser:postfix()
    local value=self:atom()
    while true do
        if self:accept('.') then value=A.Project(value,self:expect('name').spelling,value.span)
        elseif self:accept('[') then local index=self:expression(); self:expect(']'); value=A.Index(value,index,value.span)
        elseif self:accept('(') then
            local arguments=L()
            if not self:is(')') then
                repeat
                    local borrow=self:accept('mut')
                    arguments:insert(borrow and A.Borrow(self:place(),borrow.span) or self:value())
                until not self:accept(',')
            end
            self:expect(')'); value=A.Invoke(value,arguments,value.span)
        else return value end
    end
end
function Parser:specialization_argument()
    local moved=self:accept('move'); if moved then return A.Move(self:place(),moved.span) end
    if self:is('name') then return self:postfix() end
    return self:atom()
end
function Parser:prefix()
    local minus=self:accept('-'); if minus then return A.Unary(A.Negate,self:prefix(),minus.span) end
    local not_=self:accept('not'); if not_ then return A.Unary(A.Not,self:prefix(),not_.span) end
    local value=self:postfix()
    while self:is('name') or self:is('integer') or self:is('text') or self:is('true') or self:is('false') or self:is('{') or self:is('move') do
        if self:assignment_ahead() then break end
        value=A.Specialize(value,self:specialization_argument(),value.span)
    end
    return value
end
local operators={
    ['or']={1,A.Or},['and']={2,A.And},
    ['==']={3,A.Equal},['!=']={3,A.NotEqual},
    ['<']={4,A.Less},['<=']={4,A.LessEqual},['>']={4,A.Greater},['>=']={4,A.GreaterEqual},
    ['+']={5,A.Add},['-']={5,A.Subtract},
    ['*']={6,A.Multiply},['/']={6,A.Divide},['%']={6,A.Remainder}
}
function Parser:expression(minimum)
    minimum=minimum or 1; local left=self:prefix(); local used={}
    while true do
        local token=self:token(); local op=operators[token.kind]
        if not op or op[1]<minimum then return left end
        if (op[1]==3 or op[1]==4) and used[op[1]] then fail(token.span,'chained comparison is invalid') end
        used[op[1]]=true; self:take(); left=A.Binary(op[2],left,self:expression(op[1]+1),token.span)
    end
end
function Parser:transfer()
    local moved=self:accept('move'); if moved then return A.Move(self:place(),moved.span) end
    return self:expression()
end
-- Sign-sensitive literal checks are constructor-owned and run over the final AST.
local function visit(values) for _,value in ipairs(values) do value:check_literals() end end
function A.Expr:check_literals() end
function A.Integer:check_literals() literal.integer(self.spelling,false,function(m) fail(self.span,m) end) end
function A.Unary:check_literals()
    if self.operator==A.Negate and A.Integer:isclassof(self.operand) then literal.integer(self.operand.spelling,true,function(m) fail(self.operand.span,m) end)
    else self.operand:check_literals() end
end
function A.Binary:check_literals() self.left:check_literals(); self.right:check_literals() end
function A.Specialize:check_literals() self.word:check_literals(); self.argument:check_literals() end
function A.Invoke:check_literals() self.word:check_literals(); visit(self.arguments) end
function A.Word:check_literals() self.chain:check_literals() end
function A.NamedAggregate:check_literals() visit(self.members) end
function A.PositionalAggregate:check_literals() visit(self.elements) end
function A.Project:check_literals() self.base:check_literals() end
function A.Index:check_literals() self.base:check_literals(); self.index:check_literals() end
function A.Move:check_literals() self.place:check_literals() end
function A.Borrow:check_literals() self.place:check_literals() end
function A.Constraint:check_literals() visit(self.arguments) end
function A.Binding:check_literals() if self.constraint then self.constraint:check_literals() end; self.value:check_literals() end
function A.Stage:check_literals() if self.constraint then self.constraint:check_literals() end end
function A.Prelude:check_literals() self.binding:check_literals() end
function A.Chain:check_literals() visit(self.items); if self.terminal then self.terminal:check_literals() end end
function A.Data:check_literals() self.value:check_literals() end
function A.Body:check_literals() visit(self.statements) end
function A.Local:check_literals() self.binding:check_literals() end
function A.Assign:check_literals() self.place:check_literals(); self.value:check_literals() end
function A.Return:check_literals() if self.value then self.value:check_literals() end end
function A.Discard:check_literals() self.value:check_literals() end
function A.If:check_literals() self.condition:check_literals(); visit(self.yes); visit(self.no) end
function A.While:check_literals() self.condition:check_literals(); visit(self.body) end
function A.Switch:check_literals() self.subject:check_literals(); visit(self.cases); visit(self.otherwise) end
function A.Case:check_literals() visit(self.labels); visit(self.body) end
return function(text,file)
    local parser=setmetatable({tokens=Lexer.new(text,file):scan(),pos=1,aggregates={}},Parser)
    parser:separators()
    local file=parser:chain(true)
    visit(file.items); if file.terminal then file.terminal:check_literals() end
    return A.Program(file)
end
end

