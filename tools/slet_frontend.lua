-- Scalar SLet -> language-independent ABC assembly, implemented in LuaJIT.
local int,util=require('int64'),require('tool_util')
local bit=int.bit
local M={}
local scalar={bool=true,unit=true}
for name in pairs(int.types) do scalar[name]=true end
local keywords={}
for word in ('let do end if then else return and or not true false extern defer'):gmatch('%S+') do keywords[word]=true end
local predefined=util.copy(scalar)
for word in ('f64 type string array slice ref ptr null oneof'):gmatch('%S+') do predefined[word]=true end
local function fail(at,message)
    at=at.at or at
    error(('line %d, column %d: %s'):format(at.line,at.column,message),0)
end
local function checked(at,fn,...)
    local ok,value=pcall(fn,...)
    if not ok then fail(at,tostring(value)) end
    return value
end
local function node(kind,at,...) return {kind=kind,at=at,args={...}} end
local function bool(value) return int.constant(value and 1 or 0,'bool') end
local function truth(c) return c.value~=int.zero end
local function same(a,b)
    if #a~=#b then return false end
    for i=1,#a do if a[i]~=b[i] then return false end end
    return true
end
local function count(types) local n=0 for _,t in ipairs(types) do if t~='unit' then n=n+1 end end return n end
local function convert(c,t,at,explicit) return checked(at,int.convert,c,t,explicit) end
local function common(a,b,at) return checked(at,int.common,a,b) end

local function lex(source)
    local tokens,pos,line,column={},1,1,1
    while pos<=#source do
        local rest=source:sub(pos); local text,kind
        if rest:sub(1,2)=='--' then
            local equals=rest:match('^%-%-%[(=*)%[')
            if equals then
                local closing=']'..equals..']'; local opening=4+#equals
                local finish=source:find(closing,pos+opening,true)
                if not finish then fail({line=line,column=column},'unterminated block comment') end
                text=source:sub(pos,finish+#closing-1)
            else text=rest:match('^[^\n]*') end
        elseif rest:match('^%s') then text=rest:match('^%s+')
        elseif rest:match('^%d') then
            text=rest:match('^0[xX][%x_]+') or rest:match('^0[bB][01_]+') or rest:match('^[0-9][0-9_]*'); kind='number'
            checked({line=line,column=column},int.parse,text)
        elseif rest:match('^[A-Za-z_]') then
            text=rest:match('^[A-Za-z_][A-Za-z_0-9]*'); kind=keywords[text] and text or 'name'
        else
            for _,op in ipairs({'<<=','>>=','<<','>>','<=','>=','==','!=','->','+=','-=','*=','/=','%=','^=','~=','&=','|='}) do
                if rest:sub(1,#op)==op then text=op; break end
            end
            if not text and rest:sub(1,1):match('[-+*/%%%^~&|<>()=,:;]') then text=rest:sub(1,1) end
            if not text then fail({line=line,column=column},'unsupported character '..rest:sub(1,1)..' in scalar SLet') end
            kind=text
        end
        if kind then tokens[#tokens+1]={kind=kind,text=text,line=line,column=column} end
        local _,newlines=text:gsub('\n','')
        column=newlines>0 and #(text:match('[^\n]*$'))+1 or column+#text
        line=line+newlines; pos=pos+#text
    end
    tokens[#tokens+1]={kind='eof',text='',line=line,column=column}
    return tokens
end

local Parser={}; Parser.__index=Parser
local BP={['or']=10,['and']=20,['==']=30,['!=']=30,['<']=30,['<=']=30,['>']=30,['>=']=30,
          ['|']=40,['~']=50,['&']=60,['<<']=70,['>>']=70,['+']=80,['-']=80,['*']=90,['/']=90,['%']=90,['^']=110}
function Parser.new(source) return setmetatable({tokens=lex(source),pos=1},Parser) end
function Parser:peek() return self.tokens[self.pos] end
function Parser:take() local t=self:peek(); self.pos=self.pos+1; return t end
function Parser:accept(kind) if self:peek().kind==kind then return self:take() end end
function Parser:expect(kind)
    if self:peek().kind~=kind then fail(self:peek(),'expected '..kind..', found '..(self:peek().text~='' and self:peek().text or 'end of file')) end
    return self:take()
end
function Parser:type()
    local token=self:expect('name')
    if not scalar[token.text] then fail(token,'unsupported scalar type '..token.text) end
    return token.text
end
function Parser:params()
    self:expect('('); local out,seen={},{}
    if self:accept(')') then return out end
    repeat
        local names={self:expect('name')}
        while self:accept(',') do names[#names+1]=self:expect('name') end
        self:expect(':'); local t=self:type()
        for _,token in ipairs(names) do
            if seen[token.text] then fail(token,'duplicate parameter') end
            seen[token.text]=true; out[#out+1]={token.text,t}
        end
        if not self:accept(',') or self:peek().kind==')' then break end
    until false
    self:expect(')'); return out
end
function Parser:results()
    if not self:accept('(') then return {self:type()} end
    local out={}
    if not self:accept(')') then
        repeat
            out[#out+1]=self:type()
            if not self:accept(',') or self:peek().kind==')' then break end
        until false
        self:expect(')')
    end
    return #out==0 and {'unit'} or out
end
function Parser:expressions()
    local out={self:expression()}
    while self:accept(',') do out[#out+1]=self:expression() end
    return out
end
function Parser:expression(minimum)
    minimum=minimum or 0
    local token=self:take(); local kind=token.kind; local value
    if kind=='number' then value=node('constant',token,int.constant(checked(token,int.parse,token.text),'literal'))
    elseif kind=='true' or kind=='false' then value=node('constant',token,bool(kind=='true'))
    elseif kind=='name' then value=node('variable',token,token.text)
    elseif kind=='(' then value=node('group',token,self:expression()); self:expect(')')
    elseif kind=='-' or kind=='~' or kind=='not' then
        local child=self:expression(100)
        if kind=='-' and child.kind=='constant' and child.args[1].type=='literal' then
            local c=child.args[1]
            if c.value>int.sign then fail(token,'signed literal is below i64 minimum') end
            value=node('constant',token,int.constant(-c.value,'literal',true))
        else value=node('unary',token,kind,child) end
    elseif kind=='if' then
        local condition=self:expression(); self:expect('then'); local yes=self:expression()
        self:expect('else'); value=node('conditional',token,condition,yes,self:expression())
    else fail(token,'expected a scalar expression') end
    while true do
        if self:peek().kind=='(' then
            if value.kind~='variable' then fail(self:peek(),'only named calls are supported in scalar SLet') end
            self:take(); local args={}
            if self:peek().kind~=')' then
                repeat
                    args[#args+1]=self:expression()
                    if not self:accept(',') or self:peek().kind==')' then break end
                until false
            end
            self:expect(')'); value=node('call',value.at,value.args[1],args)
        else
            local op=self:peek().kind; local power=BP[op] or 0
            if power<=minimum then break end
            local operator=self:take(); local right=self:expression(op=='^' and power-1 or power)
            value=node('binary',operator,op,value,right)
            if power==30 and BP[self:peek().kind]==30 then fail(self:peek(),'comparisons cannot be chained') end
        end
    end
    return value
end
function Parser:binders()
    local out={}
    repeat
        local token=self:expect('name')
        out[#out+1]={token.text,self:accept(':') and self:type() or false,token}
    until not self:accept(',')
    return out
end
function Parser:statements(stops)
    local out={}
    while not stops[self:peek().kind] do
        if self:peek().kind=='eof' then fail(self:peek(),'expected end before end of file') end
        if not self:accept(';') then
            local token=self:take()
            if token.kind=='let' then
                local binders=self:binders(); self:expect('='); out[#out+1]=node('binding',token,binders,self:expressions())
            elseif token.kind=='return' then
                local next_=self:peek().kind
                out[#out+1]=node('return',token,(stops[next_] or next_==';' or next_=='end' or next_=='else') and {} or self:expressions())
            elseif token.kind=='if' then
                local condition=self:expression(); self:expect('then')
                local yes=self:statements({['else']=true,['end']=true})
                local no=self:accept('else') and self:statements({['end']=true}) or {}
                self:expect('end'); out[#out+1]=node('if_statement',token,condition,yes,no)
            elseif token.kind=='name' then
                self.pos=self.pos-1; local call=self:expression()
                if call.kind~='call' then fail(token,'bindings cannot be reassigned; a statement must be a saturated call') end
                out[#out+1]=node('call_statement',token,call)
            else fail(token,token.text..' is not supported in scalar SLet blocks') end
        end
    end
    return out
end
function Parser:module()
    local items,order={},{}
    while self:peek().kind~='eof' do
        if not self:accept(';') then
            self:expect('let'); local name=self:expect('name')
            if predefined[name.text] then fail(name,'predefined words are reserved at module level') end
            if items[name.text] then fail(name,'duplicate module binding') end
            local item
            if self:peek().kind=='(' then
                local params=self:params()
                if not self:accept(':') then fail(self:peek(),'this frontend requires an explicit result contract on every word') end
                local results=self:results(); self:expect('='); local body
                if self:accept('do') then body=node('block',name,self:statements({['end']=true})); self:expect('end')
                else body=self:expression() end
                item={kind='word',name=name.text,params=params,results=results,body=body,at=name,bound={}}
            else
                local annotation=self:accept(':') and self:type() or false
                self:expect('='); item={kind='initializer',at=name,annotation=annotation,body=self:expression()}
            end
            items[name.text]=item; order[#order+1]=name.text
        end
    end
    return items,order
end

local Compiler={}; Compiler.__index=Compiler
local Function={}; Function.__index=Function
function Compiler.new(source,exports)
    local items,order=Parser.new(source):module()
    local self=setmetatable({items=items,globals={},resolving={},exports={'main'},needed={},output={},adapters={},adapter_count=0},Compiler)
    local seen={main=true}
    for _,name in ipairs(exports or {}) do if not seen[name] then self.exports[#self.exports+1]=name; seen[name]=true end end
    for _,name in ipairs(order) do self:global(name) end
    for _,name in ipairs(order) do if self.globals[name].kind=='word' then self:resolve_names(self.globals[name]) end end
    for _,name in ipairs(self.exports) do
        local word=self.globals[name]
        if not word or word.kind~='word' then error('export '..name..' is not a word',0) end
        if name=='main' and #word.params>0 then fail(word,'main must take no parameters') end
        self.needed[name]=true
    end
    return self
end
function Compiler:global(name)
    if self.globals[name] then return self.globals[name] end
    local item=self.items[name]; if not item then return nil end
    if item.kind=='word' then self.globals[name]=item; return item end
    if self.resolving[name] then fail(item,'cycle in module initializers') end
    self.resolving[name]=true
    local ast,value=item.body
    if ast.kind=='call' and not scalar[ast.args[1]] then
        local base=self:global(ast.args[1])
        if not base or base.kind~='word' then fail(ast,'partial supply needs a known word') end
        local args=ast.args[2]
        if #args>=#base.params then fail(ast,'module initializers support constants or incomplete static supply, not saturated calls yet') end
        if item.annotation then fail(item,'a partial word cannot have a scalar annotation') end
        local bound=util.copy(base.bound)
        for i,arg_ in ipairs(args) do
            local c=self:constant(arg_,{})
            if not c then fail(arg_,'partial supply requires static arguments') end
            bound[base.params[i][1]]=convert(c,base.params[i][2],arg_)
        end
        value={kind='word',name=name,params=util.slice(base.params,#args+1),results=base.results,body=base.body,at=item.at,bound=bound}
    else
        value=self:constant(ast,{})
        if not value then fail(ast,'module binding must be a scalar constant or a static partial supply') end
        value=convert(value,item.annotation or int.natural(value),ast)
    end
    self.resolving[name]=nil; self.globals[name]=value; return value
end
function Compiler:resolve_names(word)
    local expression,block
    expression=function(ast,names)
        local k,d=ast.kind,ast.args
        if k=='variable' or k=='call' then
            if not names[d[1]] and not self.items[d[1]] and not scalar[d[1]] then fail(ast,'unknown '..(k=='call' and 'word ' or 'name ')..d[1]) end
            if k=='call' then for _,arg_ in ipairs(d[2]) do expression(arg_,names) end end
        elseif k=='group' or k=='unary' then expression(d[#d],names)
        elseif k=='binary' then expression(d[2],names); expression(d[3],names)
        elseif k=='conditional' then for _,child in ipairs(d) do expression(child,names) end end
    end
    block=function(statements,outer,same_scope)
        local local_=util.copy(same_scope or {}); local names=util.copy(outer)
        for _,ast in ipairs(statements) do
            local k,d=ast.kind,ast.args
            if k=='binding' then
                for _,arg_ in ipairs(d[2]) do expression(arg_,names) end
                for _,binding in ipairs(d[1]) do
                    if local_[binding[1]] then fail(binding[3],'duplicate binding in one lexical scope') end
                    local_[binding[1]]=true; names[binding[1]]=true
                end
            elseif k=='return' then for _,arg_ in ipairs(d[1]) do expression(arg_,names) end
            elseif k=='call_statement' then expression(d[1],names)
            elseif k=='if_statement' then expression(d[1],names); block(d[2],names); block(d[3],names) end
        end
    end
    local names={}
    for _,p in ipairs(word.params) do names[p[1]]=true end
    for name in pairs(word.bound) do names[name]=true end
    if word.body.kind=='block' then block(word.body.args[1],names,names) else expression(word.body,names) end
end
function Compiler:constant(ast,env)
    local kind,d=ast.kind,ast.args
    if kind=='constant' then return d[1] end
    if kind=='variable' then
        local value=env[d[1]] or self:global(d[1]); return value and value.type and value or nil
    end
    if kind=='group' then return self:constant(d[1],env) end
    if kind=='call' and scalar[d[1]] and not env[d[1]] then
        local name,args=d[1],d[2]
        if name=='unit' then if #args>0 then fail(ast,'unit takes no arguments') end return int.constant(0,'unit') end
        if #args~=1 then fail(ast,'a scalar conversion takes one argument') end
        local c=self:constant(args[1],env); return c and convert(c,name,ast,true) or nil
    end
    if kind=='unary' then
        local op,c=d[1],self:constant(d[2],env); if not c then return nil end
        local type_=int.natural(c)
        if op=='not' then if type_~='bool' then fail(ast,'not requires bool') end return bool(not truth(c)) end
        if not int.types[type_] then fail(ast,'integer unary operation requires an integer') end
        return int.constant(int.normalize(op=='-' and -c.value or bit.bnot(c.value),type_),type_)
    end
    if kind=='conditional' then
        local c=self:constant(d[1],env); if not c then return nil end
        if int.natural(c)~='bool' then fail(d[1],'condition requires bool; there is no truthiness') end
        return self:constant(truth(c) and d[2] or d[3],env)
    end
    if kind~='binary' then return nil end
    local op,left,right=d[1],self:constant(d[2],env)
    if (op=='and' or op=='or') and left then
        if int.natural(left)~='bool' then fail(d[2],op..' requires bool') end
        if (op=='and' and not truth(left)) or (op=='or' and truth(left)) then return left end
    end
    right=self:constant(d[3],env)
    if (op=='/' or op=='%') and right and not truth(right) then fail(d[3],'known zero divisor rejects at compile time') end
    if op=='^' and right then
        if not int.types[int.natural(right)] then fail(d[3],'power exponent requires integer') end
        if int.isnegative(right) then fail(d[3],'known negative exponent rejects at compile time') end
    end
    if not left or not right then return nil end
    if op=='and' or op=='or' then
        if int.natural(left)~='bool' or int.natural(right)~='bool' then fail(ast,op..' requires bool') end
        return bool(op=='and' and (truth(left) and truth(right)) or op=='or' and (truth(left) or truth(right)))
    end
    local function adopt(c,target)
        if c.type=='literal' and int.types[target] and int.fits(c.value,int.isnegative(c),unpack(int.types[target])) then return convert(c,target,ast) end
        return c
    end
    if op~='<<' and op~='>>' and op~='^' then
        if right.type~='literal' then left=adopt(left,right.type) end
        if left.type~='literal' then right=adopt(right,left.type) end
    end
    local type_
    if op=='<<' or op=='>>' or op=='^' then type_=int.natural(left)
    elseif left.type=='literal' and right.type=='literal' and (int.isnegative(left) or int.isnegative(right)) then type_='i64'
    else type_=common(int.natural(left),int.natural(right),ast) end
    if not int.types[type_] and not ((type_=='unit' or type_=='bool') and (op=='==' or op=='!=')) then fail(ast,'operator requires integer operands') end
    if op=='<<' or op=='>>' then right=convert(right,'u32',d[3]) end
    return checked(ast,int.binary,op,left,right,type_)
end
function Compiler:compile()
    while true do
        local next_
        for _,name in ipairs(util.sorted(self.needed)) do if not self.output[name] then next_=name; break end end
        if not next_ then break end
        self.output[next_]=Function.new(self,self.globals[next_]):compile()
    end
    local lines={}
    if self.adapter_count>0 then
        lines[#lines+1]='.profile callables'; lines[#lines+1]='.datazero '..(8+self.adapter_count*8)
        for _,key in ipairs(util.sorted(self.adapters)) do local adapter=self.adapters[key]; lines[#lines+1]='.codeaddr '..adapter.offset..' '..adapter.name end
    end
    for _,name in ipairs(util.sorted(self.output)) do lines[#lines+1]=self.output[name] end
    for _,name in ipairs(self.exports) do lines[#lines+1]='.export '..name end
    return table.concat(lines,'\n')..'\n'
end

function Function.new(compiler,word)
    local self=setmetatable({compiler=compiler,word=word,lines={},frame={},labels=0,env=util.copy(word.bound),probes={}},Function)
    for i=#word.params,1,-1 do
        local p=word.params[i]
        if p[2]=='unit' then self.env[p[1]]={'unit',false}
        else self.frame[#self.frame+1]=p[1]; self.env[p[1]]={p[2],#self.frame} end
    end
    if #self.frame>255 or count(word.results)>255 then fail(word,'function exceeds 255 physical argument/result cells') end
    return self
end
function Function:emit(text) self.lines[#self.lines+1]='  '..text end
function Function:label() self.labels=self.labels+1; return '_let_'..self.labels end
function Function:place(label) self.lines[#self.lines+1]=label..':' end
function Function:const(ast) return self.compiler:constant(ast,self.env) end
function Function:normalize(type_)
    local op=({u8='ZX8',u16='ZX16',u32='ZX32.A',i32='SX32.A'})[type_]
    if op then self:emit(op) end
end
function Function:convert(source,target,at,explicit)
    if source==target then return target end
    local a,b=int.types[source],int.types[target]
    if not a or not b then fail(at,'cannot convert '..source..' to '..target) end
    if explicit and a[1]==b[1] then
        if a[1]==64 then self:emit('CHKNN') else self:normalize(target) end
        return target
    end
    if int.widenable(source,target) then return target end
    if not explicit then fail(at,'numeric-range: runtime '..source..' needs explicit '..target..'(...) conversion') end
    if a[2]~=b[2] then self:emit('CHKNN') end
    local check=({u8='CHKU8',u16='CHKU16',u32='CHKU32',i32='CHKI32'})[target]
    if check then self:emit(check) end
    self:normalize(target); return target
end
function Function:scalar(ast,want)
    local types=self:expression(ast,want and {want} or nil)
    for i=#types,2,-1 do if types[i]~='unit' then self:emit('DROP.A') end end
    return want and self:convert(types[1],want,ast) or types[1]
end
function Function:probe(ast)
    if not self.probes[ast] then
        local length,labels=#self.lines,self.labels
        self.probes[ast]=self:scalar(ast)
        for i=#self.lines,length+1,-1 do self.lines[i]=nil end
        self.labels=labels
    end
    return self.probes[ast]
end
local function comparison_signature(self,ast)
    if ast.kind~='binary' then return nil end
    local op,lhs,rhs=unpack(ast.args)
    if BP[op]~=30 then return nil end
    local lc,rc=self:const(lhs),self:const(rhs)
    local lt,rt=self:probe(lhs),self:probe(rhs)
    if lc and lc.type=='literal' and int.types[rt] and int.fits(lc.value,int.isnegative(lc),unpack(int.types[rt])) then lt=rt end
    if rc and rc.type=='literal' and int.types[lt] and int.fits(rc.value,int.isnegative(rc),unpack(int.types[lt])) then rt=lt end
    local type_=common(lt,rt,ast)
    return op,lhs,rhs,lc,rc,type_
end
function Function:branch(ast,label,on_true)
    local op,lhs,rhs,lc,rc,type_=comparison_signature(self,ast)
    if op then
        local relation,dynamic,constant=op,lhs,rc
        if not constant and lc then
            dynamic,constant=rhs,lc
            relation=({['==']='==',['!=']='!=',['<']='>',['<=']='>=',['>']='<',['>=']='<='})[relation]
        end
        if constant then
            constant=convert(constant,type_,ast)
            if int.fits(constant.value,int.isnegative(constant),8,true) then
                if not on_true then relation=({['==']='!=',['!=']='==',['<']='>=',['<=']='>',['>']='<=',['>=']='<'})[relation] end
                local stem=({['==']='BEQI',['!=']='BNEI',['<']='BLTI',['<=']='BLEI',['>']='BGTI',['>=']='BGEI'})[relation]
                if relation~='==' and relation~='!=' and int.types[type_] and not int.types[type_][2] then stem=stem:gsub('I$','UI') end
                self:scalar(dynamic,type_); self:emit(stem..' '..int.format(constant.value,int.isnegative(constant))..' '..label); return
            end
        end
        if type_~='unit' then
            local reverse=(on_true and (op=='>' or op=='>=')) or (not on_true and (op=='<' or op=='<='))
            self:scalar(lhs,type_)
            if reverse then self:emit('MOVE.AB'); self:scalar(rhs,type_) else self:scalar(rhs,type_); self:emit('MOVE.AB') end
            local stem
            if on_true then stem=({['==']='BEQ',['!=']='BNE',['<']='BLT',['<=']='BLE',['>']='BLT',['>=']='BLE'})[op]
            else stem=({['==']='BNE',['!=']='BEQ',['<']='BLE',['<=']='BLT',['>']='BLE',['>=']='BLT'})[op] end
            if op~='==' and op~='!=' and int.types[type_] and not int.types[type_][2] then stem=stem..'U' end
            self:emit(stem..' '..label); return
        end
    end
    self:scalar(ast,'bool'); self:emit((on_true and 'JNZ.A ' or 'JZ.A ')..label)
end
function Function:expression(ast,wants)
    local c=self:const(ast)
    if c then
        local type_=wants and wants[1] or int.natural(c); c=convert(c,type_,ast)
        if type_~='unit' then self:emit('PUSH.A '..int.format(c.value,int.isnegative(c))) end
        return {type_}
    end
    local kind,d=ast.kind,ast.args
    if kind=='variable' then
        local binding=self.env[d[1]]
        if not binding or not binding[1] then fail(ast,d[1]..' is not a scalar binding') end
        if binding[1]~='unit' then self:emit('CGET.A '..(#self.frame-binding[2])) end
        return {binding[1]}
    elseif kind=='group' then return {self:scalar(d[1],wants and wants[1])}
    elseif kind=='call' then return self:call(ast)
    elseif kind=='conditional' then
        local condition,yes,no=unpack(d); local known=self:const(condition)
        if known then
            if int.natural(known)~='bool' then fail(condition,'condition requires bool') end
            return self:expression(truth(known) and yes or no,wants)
        end
        local otherwise,finish=self:label(),self:label()
        self:branch(condition,otherwise,false); local left=self:expression(yes,wants)
        self:emit('JMP '..finish); self:place(otherwise); local right=self:expression(no,wants); self:place(finish)
        if #left~=#right then fail(ast,'conditional result arities disagree') end
        local out={} for i,a in ipairs(left) do out[i]=common(a,right[i],ast) end return out
    elseif kind=='unary' then
        local op,type_=d[1],self:scalar(d[2])
        if op=='not' then
            if type_~='bool' then fail(ast,'not requires bool') end self:emit('LNOT.A')
        else
            if not int.types[type_] then fail(ast,'unary operation requires integer') end
            self:emit(op=='-' and 'NEG.A' or 'NOT.A'); self:normalize(type_)
        end
        return {type_}
    end
    if kind~='binary' then fail(ast,'unsupported scalar expression') end
    local op,lhs,rhs=unpack(d)
    if op=='and' or op=='or' then
        local alt,finish=self:label(),self:label()
        self:branch(lhs,alt,op=='or'); self:scalar(rhs,'bool')
        self:emit('JMP '..finish); self:place(alt); self:emit('PUSH.A '..(op=='and' and 0 or 1)); self:place(finish)
        return {'bool'}
    end
    local lc,rc=self:const(lhs),self:const(rhs)
    local lt,rt=self:probe(lhs),self:probe(rhs); local type_,right_type
    if op=='<<' or op=='>>' or op=='^' then
        type_=lt; right_type=op=='^' and rt or 'u32'
        if op=='^' and not int.types[rt] then fail(rhs,'power exponent requires integer') end
    else
        if lc and lc.type=='literal' and int.types[rt] and int.fits(lc.value,int.isnegative(lc),unpack(int.types[rt])) then lt=rt end
        if rc and rc.type=='literal' and int.types[lt] and int.fits(rc.value,int.isnegative(rc),unpack(int.types[lt])) then rt=lt end
        type_=common(lt,rt,ast); right_type=type_
    end
    if not int.types[type_] and not ((type_=='unit' or type_=='bool') and (op=='==' or op=='!=')) then fail(ast,'operator requires integers (bool/unit support equality only)') end
    local opi=({['+']='ADD',['-']='SUB',['*']='MUL',['&']='AND',['|']='OR',['~']='XOR',['<<']='SHL',['>>']=int.types[type_] and int.types[type_][2] and 'SAR' or 'SHR'})[op]
    if opi and rc then
        local immediate=convert(rc,right_type,rhs)
        if int.fits(immediate.value,int.isnegative(immediate),8,true) then
            self:scalar(lhs,type_); self:emit(opi..'I.A '..int.format(immediate.value,int.isnegative(immediate))); self:normalize(type_); return {type_}
        end
    end
    local opc=({['+']='ADD',['-']='SUB',['*']='MUL',['~']='XOR'})[op]
    local binding=rhs.kind=='variable' and self.env[rhs.args[1]]
    if opc and binding and binding[1] and (binding[1]==right_type or int.widenable(binding[1],right_type)) then
        self:scalar(lhs,type_); self:emit(opc..'C.A '..(#self.frame-binding[2])); self:normalize(type_); return {type_}
    end
    self:scalar(lhs,type_); self:scalar(rhs,right_type)
    if type_=='unit' then self:emit('PUSH.A '..(op=='==' and 1 or 0)); return {'bool'} end
    self:emit('MOVE.AB'); local signed=int.types[type_] and int.types[type_][2]
    if op=='>' or op=='>=' then
        self:emit((op=='>' and 'LE' or 'LT')..(signed and '' or 'U')..'.A'); self:emit('LNOT.A')
    elseif op=='^' then self:emit(int.types[rt][2] and 'POWS' or 'POW')
    else
        local instruction=({['+']='ADD',['-']='SUB',['*']='MUL',['/']=signed and 'DIVS' or 'DIVU',
                            ['%']=signed and 'REMS' or 'REMU',['&']='AND',['|']='OR',['~']='XOR',['<<']='SHL',
                            ['>>']=signed and 'SAR' or 'SHR',['==']='EQ',['!=']='NE',['<']=signed and 'LT' or 'LTU',
                            ['<=']=signed and 'LE' or 'LEU'})[op]
        self:emit(instruction..'.A')
    end
    local comparison=BP[op]==30
    if not comparison then self:normalize(type_) end
    return {comparison and 'bool' or type_}
end
function Function:values(expressions,wants)
    if #expressions==0 then return {'unit'} end
    local types={}
    for i,ast in ipairs(expressions) do
        local expected=wants and util.slice(wants,#types+1) or nil
        if i==#expressions then
            local produced=self:expression(ast,expected)
            for j,a in ipairs(produced) do
                local b=expected and expected[j]
                if b then self:convert(a,b,ast) end
                types[#types+1]=b or a
            end
        else types[#types+1]=self:scalar(ast,expected and expected[1]) end
    end
    return types
end
function Function:callee(ast)
    local name=ast.args[1]
    if self.env[name] then
        if self.env[name].closure then return self.env[name] end
        fail(ast,name..' is a scalar binding, not callable')
    end
    local word=self.compiler.globals[name]
    if not word or word.kind~='word' then fail(ast,'unknown word '..name) end
    return word
end
function Function:arguments(ast,word)
    local wants={} for _,p in ipairs(word.params) do wants[#wants+1]=p[2] end
    local got=#ast.args[2]>0 and self:values(ast.args[2],wants) or {}
    if #got~=#word.params then fail(ast,'call arity disagrees; runtime partial supply is not supported') end
    if not same(got,wants) then fail(ast,'argument types disagree') end
    return count(wants)
end
function Function:call(ast)
    local name,args=unpack(ast.args)
    if scalar[name] and not self.env[name] then
        if name=='unit' then fail(ast,'unit takes no arguments') end
        if #args~=1 then fail(ast,'conversion needs one argument') end
        return {self:convert(self:scalar(args[1]),name,ast,true)}
    end
    local word=self:callee(ast)
    if word.closure then
        if word.bytes>0 then self:emit('FADDR.A '..((#self.frame-word.frame_end)*8+word.bytes))
        else self:emit('.loadkind addr'); self:emit('GLD64 0') end
        local n=self:arguments(ast,word)
        self:emit('.loadkind addr'); self:emit('GLD64 '..word.offset); self:emit('MOVE.AB')
        self:emit('CALLI.A '..(n+1)..' '..word.adapter)
    else
        local n=self:arguments(ast,word); self.compiler.needed[word.name]=true; self:emit('CALL.A '..word.name..' '..n)
    end
    return util.copy(word.results)
end
function Function:return_values(expressions,at)
    if #expressions==1 then
        local ast=expressions[1]
        if ast.kind=='conditional' then
            local condition,yes,no=unpack(ast.args); local known=self:const(condition)
            if known then
                if int.natural(known)~='bool' then fail(condition,'condition requires bool') end
                self:return_values({truth(known) and yes or no},at); return
            end
            local alt=self:label(); self:branch(condition,alt,false)
            self:return_values({yes},at); self:place(alt); self:return_values({no},at); return
        elseif ast.kind=='call' and not scalar[ast.args[1]] then
            local word=self:callee(ast)
            if not word.closure and same(word.results,self.word.results) then
                local n=self:arguments(ast,word); self.compiler.needed[word.name]=true
                self:emit('TCALL '..word.name..' '..#self.frame..' '..n); return
            end
        end
    end
    local got=self:values(expressions,self.word.results)
    if not same(got,self.word.results) then fail(at,'return contract requires '..table.concat(self.word.results,',')..', got '..table.concat(got,',')) end
    self:emit('RET '..#self.frame..' '..count(got))
end
-- Lexical closures of known words. Captures are copied into an owned C block;
-- no heap allocation and no escaping/function-typed parameters in this subset.
function Function:partial_bind(binders,expressions)
    if #binders~=1 or #expressions~=1 or expressions[1].kind~='call' then return false end
    local ast=expressions[1]; local word=self.compiler.globals[ast.args[1]]
    if self.env[ast.args[1]] or not word or word.kind~='word' then return false end
    local mark,labels=#self.lines,self.labels; local wants={}
    for _,p in ipairs(word.params) do wants[#wants+1]=p[2] end
    local types=#ast.args[2]>0 and self:values(ast.args[2],wants) or {}
    if #types>=#word.params then
        for i=#self.lines,mark+1,-1 do self.lines[i]=nil end; self.labels=labels; return false
    end
    if binders[1][2] then fail(ast,'a partial word cannot have a scalar annotation') end
    local cells=count(types); if #self.frame+cells>255 then fail(ast,'closure frame exceeds 255 cells') end
    local remaining=util.slice(word.params,#types+1); local argc=1
    for _,p in ipairs(remaining) do if p[2]~='unit' then argc=argc+1 end end
    if argc>255 then fail(ast,'callable exceeds 255 argument cells') end
    local key=word.name..':'..#types; local adapter=self.compiler.adapters[key]
    if not adapter then
        self.compiler.adapter_count=self.compiler.adapter_count+1
        local name='_let_closure_'..self.compiler.adapter_count
        while self.compiler.items[name] or self.compiler.output[name] do name=name..'_' end
        adapter={name=name,offset=self.compiler.adapter_count*8}; self.compiler.adapters[key]=adapter
        local body={'.function '..name..' '..argc..' '..count(word.results)..' a'..string.rep('i',argc-1)..' '..(count(word.results)>0 and string.rep('i',count(word.results)) or '-')}
        local offset=0
        for _,t in ipairs(types) do if t~='unit' then body[#body+1]='CGET.A 0'; body[#body+1]='LD64.A '..offset; offset=offset+8 end end
        local depth=1
        for _,p in ipairs(remaining) do if p[2]~='unit' then body[#body+1]='CGET.A '..depth; depth=depth+1 end end
        body[#body+1]='TCALL '..word.name..' '..argc..' '..count(wants)
        self.compiler.output[name]=table.concat(body,'\n'); self.compiler.needed[word.name]=true
    end
    if cells>0 then
        self:emit('CALLOC '..(cells*8))
        for _=1,cells do self.frame[#self.frame+1]={} end
        self.frame[#self.frame].block_bytes=cells*8
        for i=cells,1,-1 do self:emit('FST64.A '..((cells-i+1)*8)) end
    end
    self.env[binders[1][1]]={closure=true,params=remaining,results=word.results,bytes=cells*8,frame_end=#self.frame,offset=adapter.offset,adapter=adapter.name}
    return true
end
function Function:block(statements,child)
    if child==nil then child=true end
    local old_env,mark=util.copy(self.env),#self.frame; local terminated=false
    for _,ast in ipairs(statements) do
        if terminated then fail(ast,'unreachable statement after return') end
        local kind,d=ast.kind,ast.args
        if kind=='binding' then
            local binders,expressions=unpack(d); local known,wants={},{}
            if not self:partial_bind(binders,expressions) then
                for i,arg_ in ipairs(expressions) do known[i]=self:const(arg_) or false end
                for i,b in ipairs(binders) do wants[i]=b[2] end
                local types=self:values(expressions,wants)
                for i=#types,#binders+1,-1 do if types[i]~='unit' then self:emit('DROP.A') end; types[i]=nil end
                while #types<#binders do types[#types+1]='unit' end
                for i,b in ipairs(binders) do if b[2] and b[2]~=types[i] then fail(b[3],'missing binding value is unit, incompatible with annotation') end end
                for i=#binders,1,-1 do
                    local b,type_,c=binders[i],types[i],known[i]
                    if type_=='unit' then self.env[b[1]]=int.constant(0,'unit')
                    elseif c then self:emit('DROP.A'); self.env[b[1]]=convert(c,type_,b[3])
                    else
                        self:emit('CPUSH.A'); self.frame[#self.frame+1]=b[1]; self.env[b[1]]={type_,#self.frame}
                        if #self.frame>255 then fail(b[3],'frame exceeds 255 cells') end
                    end
                end
            end
        elseif kind=='return' then self:return_values(d[1],ast); terminated=true
        elseif kind=='call_statement' then
            local types=self:expression(d[1]); for i=#types,1,-1 do if types[i]~='unit' then self:emit('DROP.A') end end
        elseif kind=='if_statement' then
            local condition,yes,no=unpack(d); local known=self:const(condition)
            if known then
                if int.natural(known)~='bool' then fail(condition,'condition requires bool') end
                terminated=self:block(truth(known) and yes or no)
            else
                local alt,finish=self:label(),self:label(); self:branch(condition,alt,false)
                local left=self:block(yes); if not left then self:emit('JMP '..finish) end
                self:place(alt); local right=self:block(no); if not left or not right then self:place(finish) end
                terminated=left and right
            end
        end
    end
    if not terminated and child then
        local i=#self.frame
        while i>mark do
            if type(self.frame[i])=='table' then local bytes=self.frame[i].block_bytes; self:emit('CFREE '..bytes); i=i-bytes/8
            else self:emit('CPOP'); i=i-1 end
        end
    end
    if child then self.env=old_env; for i=#self.frame,mark+1,-1 do self.frame[i]=nil end end
    return terminated
end
function Function:compile()
    local params={} for _,p in ipairs(self.word.params) do params[#params+1]=p[2] end
    self.lines[#self.lines+1]='.function '..self.word.name..' '..count(params)..' '..count(self.word.results)
    if self.word.body.kind=='block' then
        if not self:block(self.word.body.args[1],false) then fail(self.word,'every function path must return explicitly') end
    else self:return_values({self.word.body},self.word.body) end
    return table.concat(self.lines,'\n')
end
function M.compile(source,exports) return Compiler.new(source,exports):compile() end
return M

