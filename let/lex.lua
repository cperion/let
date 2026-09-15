-- Let lexical rules (§2). Newlines never become tokens; source spans count
-- Unicode scalars, with CRLF treated as one line break and tabs as one column.
return function(V)
local Source,L=V.Source,V.List
local Lexer={}; Lexer.__index=Lexer
local keywords={}
for word in ('let do end own mut move return if else while switch case and or not true false extern pure break continue'):gmatch('%S+') do keywords[word]=true end
local escapes={['\\']='\\',['"']='"',n='\n',r='\r',t='\t'}
function Lexer.fail(span,message) error(('%s:%d:%d: %s'):format(span.file,span.line,span.column,message),0) end
function Lexer.new(text,file) return setmetatable({text=text,file=file or '<source>',pos=1,line=1,column=1},Lexer) end
function Lexer:span() return Source.Span(self.file,self.line,self.column) end
function Lexer:char() return self.text:sub(self.pos,self.pos) end
function Lexer:advance()
    local start=self.pos; local byte=self.text:byte(start); assert(byte,'advance beyond input')
    local count,value,minimum
    if byte<128 then count,value,minimum=1,byte,0
    elseif byte>=194 and byte<=223 then count,value,minimum=2,byte-192,128
    elseif byte>=224 and byte<=239 then count,value,minimum=3,byte-224,2048
    elseif byte>=240 and byte<=244 then count,value,minimum=4,byte-240,65536
    else Lexer.fail(self:span(),'invalid UTF-8') end
    for offset=1,count-1 do
        local next_=self.text:byte(start+offset)
        if not next_ or next_<128 or next_>191 then Lexer.fail(self:span(),'invalid UTF-8 continuation') end
        value=value*64+next_-128
    end
    if value<minimum or value>1114111 or (value>=55296 and value<=57343) then Lexer.fail(self:span(),'invalid UTF-8 scalar') end
    self.pos=start+count
    if byte==13 then self.line=self.line+1; self.column=1
    elseif byte==10 then if not self.cr then self.line=self.line+1 end; self.column=1
    else self.column=self.column+1 end
    self.cr=byte==13
    return self.text:sub(start,self.pos-1)
end
local function utf8(value)
    if value<128 then return string.char(value) end
    if value<2048 then return string.char(192+math.floor(value/64),128+value%64) end
    if value<65536 then return string.char(224+math.floor(value/4096),128+math.floor(value/64)%64,128+value%64) end
    return string.char(240+math.floor(value/262144),128+math.floor(value/4096)%64,128+math.floor(value/64)%64,128+value%64)
end
function Lexer:text_literal()
    local span,start=self:span(),self.pos; self:advance(); local chunks={}
    while self:char()~='"' do
        local c=self:char(); local at=self:span()
        if c=='' then Lexer.fail(span,'unterminated Text literal') end
        if c=='\n' or c=='\r' then Lexer.fail(at,'unescaped newline in Text literal') end
        if c=='\\' then
            self:advance(); c=self:char()
            if escapes[c] then chunks[#chunks+1]=escapes[c]; self:advance()
            elseif c=='u' then
                self:advance(); if self:char()~='{' then Lexer.fail(at,'expected { in Unicode escape') end
                self:advance(); local digits=''
                while self:char():match('^[0-9a-fA-F]$') do digits=digits .. self:advance() end
                if #digits<1 or #digits>6 or self:char()~='}' then Lexer.fail(at,'invalid Unicode escape') end
                local value=tonumber(digits,16)
                if value>1114111 or (value>=55296 and value<=57343) then Lexer.fail(at,'invalid Unicode scalar') end
                self:advance(); chunks[#chunks+1]=utf8(value)
            else Lexer.fail(at,'invalid Text escape') end
        else chunks[#chunks+1]=self:advance() end
    end
    self:advance(); return Source.Token('text',self.text:sub(start,self.pos-1),table.concat(chunks),span)
end
function Lexer:next()
    while true do
        local c=self:char()
        if c:match('^[ \t\r\n\v\f]$') then self:advance()
        elseif self.text:sub(self.pos,self.pos+1)=='//' then
            while self:char()~='' and self:char()~='\r' and self:char()~='\n' do self:advance() end
        else break end
    end
    local span,start=self:span(),self.pos; local c=self:char()
    if c=='' then return Source.Token('eof','',nil,span) end
    if c=='"' then return self:text_literal() end
    local rest=self.text:sub(start)
    local name=rest:match('^[A-Za-z_][A-Za-z_0-9]*')
    if name then for _=1,#name do self:advance() end; return Source.Token(keywords[name] and name or 'name',name,nil,span) end
    if c:match('^[0-9]$') then
        -- A Float has a digit on each side of its `.`; an exponent may follow either form.
        local mantissa=rest:match('^%d[%d_]*%.%d[%d_]*')
        if mantissa then
            local exponent=rest:sub(#mantissa+1):match('^[eE][%+%-]?%d[%d_]*')
            if not exponent and rest:sub(#mantissa+1):match('^[eE]') then
                Lexer.fail(span,'invalid Float exponent')
            end
            local spelling=mantissa .. (exponent or '')
            require('let.literal').float(spelling,function(m) Lexer.fail(span,m) end)
            for _=1,#spelling do self:advance() end
            return Source.Token('float',spelling,nil,span)
        end
        local exponent=rest:match('^%d[%d_]*[eE][%+%-]?%d[%d_]*')
        if exponent then
            require('let.literal').float(exponent,function(m) Lexer.fail(span,m) end)
            for _=1,#exponent do self:advance() end
            return Source.Token('float',exponent,nil,span)
        end
        local spelling=rest:match('^[A-Za-z_0-9]+')
        -- Permit the magnitude of INT_MIN here; its literal sign is checked on
        -- the AST, after parentheses and unary operators have been parsed.
        require('let.literal').integer(spelling,true,function(m) Lexer.fail(span,m) end)
        for _=1,#spelling do self:advance() end
        return Source.Token('integer',spelling,nil,span)
    end
    local two=rest:sub(1,2)
    if two=='==' or two=='!=' or two=='<=' or two=='>=' then self:advance(); self:advance(); return Source.Token(two,two,nil,span) end
    if c:match('^[=;(),{}%[%].:+*/%%<>%-]$') then self:advance(); return Source.Token(c,c,nil,span) end
    local bad=self:advance(); Lexer.fail(span,'unexpected character ' .. string.format('%q',bad))
end
function Lexer:scan()
    local tokens=L()
    repeat tokens:insert(self:next()) until tokens[#tokens].kind=='eof'
    return tokens
end
return Lexer
end

