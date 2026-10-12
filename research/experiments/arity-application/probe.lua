-- Isolated syntax experiment. Uses the production lexer, NOT production parsing.
-- Signature lookup is injected; no inference, module loading or source execution.
local Lex = require('let.lex')
local M = {}
local Parser = {}; Parser.__index = Parser
local precedence = {['or']=1,['and']=2,['==']=3,['!=']=3,['<']=3,['<=']=3,['>']=3,['>=']=3,
    ['|']=4,['~']=5,['&']=6,['<<']=7,['>>']=7,['..']=8,['+']=9,['-']=9,
    ['*']=10,['/']=10,['%']=10,['^']=12}
local comparisons = {['==']=true,['!=']=true,['<']=true,['<=']=true,['>']=true,['>=']=true}
local function node(kind, fields) fields.kind=kind; return fields end
function Parser:peek() return self.tokens[self.pos] end
function Parser:at(text) return self:peek().text==text end
function Parser:take(text)
    if self:at(text) then local t=self:peek();self.pos=self.pos+1;return t end
end
function Parser:fail(code, message)
    error(code..': '..message..' near '..self:peek().text,0)
end
function Parser:expect(text)
    if not self:take(text) then self:fail('parse','expected '..text) end
end
function Parser:starts()
    local t=self:peek()
    return t.kind=='name' or t.kind=='number' or t.kind=='float' or t.kind=='string'
        or t.kind=='byte' or t.text=='true' or t.text=='false' or t.text=='('
end
function Parser:block()
    self:expect('do')
    local params={}
    if self:take('|') then
        if not self:at('|') then
            repeat
                local t=self:peek();if t.kind~='name' then self:fail('probe-scope','block parameter name required') end
                params[#params+1]=t.text;self.pos=self.pos+1
            until not self:take(',')
        end
        self:expect('|')
    end
    -- Parameters shadow signature entries. Qualified receiver entries supplied by
    -- the fixture are a deliberate external assumption, not inferred schema facts.
    local old=self.signatures;local scoped={}
    for k,v in pairs(old) do scoped[k]=v end
    for _,p in ipairs(params) do scoped[p]={kind='value'} end
    self.signatures=scoped
    local body=self:statements('end')
    self:expect('end');self.signatures=old
    return node('block',{params=params,body=body})
end
function Parser:primary()
    local t=self:peek()
    if self:take('(') then
        local e=self:expression(1);self:expect(')');return node('group',{value=e})
    elseif t.kind=='name' then
        self.pos=self.pos+1;local name=t.text
        while self:take('.') do
            local part=self:peek();if part.kind~='name' then self:fail('parse','member name required') end
            name=name..'.'..part.text;self.pos=self.pos+1
        end
        return node('name',{name=name})
    elseif t.kind=='number' or t.kind=='float' or t.kind=='string' or t.kind=='byte'
        or t.text=='true' or t.text=='false' then
        if t.kind=='string' or t.kind=='byte' then self:fail('probe-scope','text literals omitted from this probe') end
        self.pos=self.pos+1;return node('literal',{text=t.text})
    end
    self:fail('parse','expression required')
end
function Parser:prefix()
    if self:at('-') or self:at('~') or self:at('not') then
        local op=self:peek().text;self.pos=self.pos+1
        return node('unary',{op=op,value=self:expression(11)})
    end
    local e=self:primary()
    -- Parenthesized application always wins, independent of whitespace.
    while self:take('(') do
        local args={}
        if not self:at(')') then
            repeat
                args[#args+1]=self:expression(1)
                if not self:take(',') then break end
            until self:at(')')
        end
        self:expect(')');e=node('call',{callee=e,args=args,bare=false})
    end
    if e.kind=='call' and self:at('do') then
        e.args[#e.args+1]=self:block();return e
    end
    local sig=e.kind=='name' and self.signatures[e.name] or nil
    if e.kind=='name' and self:at('do') and (not sig or sig.kind~='fixed' or sig.arity==0) then
        self:fail('bare-signature','a fixed nonzero ordered signature is required before do')
    end
    if e.kind=='name' and sig and sig.kind=='fixed' and sig.arity>0 and (self:starts() or self:at('do')) then
        local args={}
        for i=1,sig.arity do
            if self:at('do') then
                if i~=sig.arity then self:fail('bare-block','block must fill final requirement') end
                args[i]=self:block()
            else
                if not self:starts() and not self:at('-') and not self:at('~') and not self:at('not') then
                    self:fail('bare-arity','missing argument '..i..' of '..e.name)
                end
                args[i]=self:prefix()
            end
        end
        return node('call',{callee=e,args=args,bare=true})
    end
    if e.kind=='name' and sig and sig.kind=='fixed' and sig.arity>0
        and (self:at('-') or self:at('~') or self:at('not')) then
        self:fail('bare-unary','first unary argument needs an explicit call; avoid subtraction/xor ambiguity')
    end
    return e
end
function Parser:expression(min)
    local e=self:prefix();local compared=false
    while true do
        local op=self:peek().text;local p=precedence[op]
        if not p or p<min then break end
        if comparisons[op] and compared then self:fail('parse','comparison chaining requires grouping') end
        self.pos=self.pos+1
        local rhs=self:expression((op=='^' or op=='..') and p or p+1)
        e=node('binary',{op=op,left=e,right=rhs})
        if comparisons[op] then compared=true end
    end
    return e
end
function Parser:statements(stop)
    local out={}
    while self:peek().kind~='eof' and not (stop and self:at(stop)) do
        if not self:take(';') then
            local s
            if self:take('let') then
                local t=self:peek();if t.kind~='name' then self:fail('probe-scope','single local binder required') end
                self.pos=self.pos+1;self:expect('=');local value=self:expression(1)
                s=node('let',{name=t.text,value=value})
                -- No callable-interface inference from initializers in this experiment.
                self.signatures[t.text]={kind='value'}
            elseif self:take('return') then
                local values={}
                if self:starts() or self:at('-') or self:at('~') or self:at('not') then
                    repeat values[#values+1]=self:expression(1) until not self:take(',')
                end
                s=node('return',{values=values})
            else
                local value=self:expression(1)
                if value.kind~='call' then self:fail('call-statement','only calls are expression statements') end
                s=node('statement',{value=value})
            end
            out[#out+1]=s
        end
    end
    return out
end
local render
local function list(xs)
    local r={};for i,x in ipairs(xs) do r[i]=render(x) end;return table.concat(r,', ')
end
local function statements(xs)
    local r={};for i,x in ipairs(xs) do r[i]=render(x) end;return table.concat(r,'; ')
end
render=function(e)
    if e.kind=='name' then return e.name
    elseif e.kind=='literal' then return e.text
    elseif e.kind=='group' then return '('..render(e.value)..')'
    elseif e.kind=='unary' then return '('..e.op..' '..render(e.value)..')'
    elseif e.kind=='binary' then return '('..render(e.left)..' '..e.op..' '..render(e.right)..')'
    elseif e.kind=='call' then
        local args={};for i,a in ipairs(e.args) do
            local value=render(a)
            -- Every bare operand is scalar, including its final operand. Explicit
            -- calls retain the production language's final-result forwarding.
            args[i]=e.bare and a.kind~='block' and '('..value..')' or value
        end
        return render(e.callee)..'('..table.concat(args,', ')..')'
    elseif e.kind=='block' then return '|'..table.concat(e.params,', ')..'| -> do '..statements(e.body)..' end'
    elseif e.kind=='statement' then return render(e.value)
    elseif e.kind=='let' then return 'let '..e.name..' = '..render(e.value)
    elseif e.kind=='return' then return #e.values==0 and 'return' or 'return '..list(e.values) end
    error('unknown node '..tostring(e.kind))
end
function M.parse(source, signatures, mode)
    local copy={};for k,v in pairs(signatures) do copy[k]=v end
    local p=setmetatable({tokens=Lex.tokens(source,'<arity-probe>'),pos=1,signatures=copy},Parser)
    local result=mode=='statements' and p:statements() or p:expression(1)
    if p:peek().kind~='eof' then p:fail('bare-boundary','unexpected tokens after complete expression') end
    return mode=='statements' and statements(result) or render(result)
end
return M
