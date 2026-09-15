-- Module construction and source checks. No runtime operations execute here.
local V=require('let.vocab')
local A,S,E,L=V.Syntax,V.Semantic,V.Evaluation,V.List
local Host=require('let.host')
local D=require('let.domain')
local fail=require('let.lexer').fail
require('let.integer')
local Program={}; Program.__index=Program
function Program.new(options)
    local p=setmetatable({words={},env={},exports=L(),helpers={},queue=L(),constants={},specialization_limit=8,fuel=512},Program)
    Host.install(p,options); return p
end
function Program:annotation(value,annotation,span)
    if not annotation then return end
    local shape=self.shapes[annotation]; if not shape then fail(span,'unsupported constraint ' .. annotation) end
    if value.shape~=shape then fail(span,'expected ' .. shape.kind .. ', got ' .. (value.shape and value.shape.kind or 'word')) end
end
function A.Expr:construct() fail(self.span,'top-level initialization currently requires a literal, alias, or scalar specialization') end
function A.Integer:construct() local hi,lo=self:parts(false); return S.Scalar(S.Int,E.Bits(hi,lo)) end
function A.Boolean:construct() return S.Scalar(S.Bool,E.Truth(self.value)) end
function A.Unit:construct() return S.Scalar(S.Unit,E.Nothing) end
function A.Name:construct(p) local b=p.env[self.name]; if not b then fail(self.span,'unknown name ' .. self.name) end; return b.value end
function A.Unary:construct(p)
    if self.operator~='-' or not A.Integer:isclassof(self.operand) then return A.Expr.construct(self,p) end
    local hi,lo=self.operand:parts(true)
    local value=D.integer(0):binary(nil,'-',E.Known(S.Int,E.Bits(hi,lo)))
    return S.Scalar(value.shape,value.atom)
end
function S.Scalar:specialize(_,_,span) fail(span,'specialization requires a word') end
function S.Host:specialize(_,_,span) fail(span,'host specialization is not supported; wrap the host word in a source word') end
function S.Word:specialize(p,value,span)
    local def=p.words[self.id]
    if def.has_preludes then fail(span,'persistent specialization with preludes is not supported yet') end
    local stage=def.stages[#self.bound+1]; if not stage then fail(span,'oversaturated specialization') end
    if not value.shape then fail(span,'expected scalar value, got word') end
    p:annotation(value,stage.annotation,span)
    if stage.capability==S.Mut then fail(span,'persistent mutable borrow is forbidden') end
    if not value.shape:is_copy() or stage.capability==S.OwnMut then fail(span,'persistent owned resource or mutable word state is not supported yet') end
    local bound=L(); bound:insertall(self.bound); bound:insert(value); return S.Word(self.id,bound)
end
function A.Specialize:construct(p) return self.word:construct(p):specialize(p,self.argument:construct(p),self.span) end
function A.Stage:register(def) def.stages:insert(self) end
function A.Prelude:register(def)
    if #def.stages==0 then fail(self.binding.span,'initial construction preludes are not supported yet') end
    def.has_preludes=true
end
function A.Body:construct(p,chain)
    local env={}; for name,binding in pairs(p.env) do env[name]=binding end
    local def={chain=chain,env=env,stages=L(),has_preludes=false}
    for _, item in ipairs(chain.items) do item:register(def) end
    p.words[#p.words+1]=def; return S.Word(#p.words,L())
end
function A.Data:construct(p,chain)
    if #chain.items~=0 then fail(chain.span,'data-terminal templates are not supported yet') end
    return self.value:construct(p)
end
function S.Scalar:export() end
function S.Host:export() end
function S.Word:export(p,name,span)
    p.exports:insert({word=self,name=name,span=span})
    local def=p.words[self.id]; def.self_name=def.self_name or name
end
function A.Program:check(options)
    local p=Program.new(options)
    for _, binding in ipairs(self.bindings) do
        if binding.mutable then fail(binding.span,'mutable module state is not supported yet') end
        if p.env[binding.name] then fail(binding.span,'duplicate binding ' .. binding.name) end
        local value=binding.value.terminal:construct(p,binding.value)
        p:annotation(value,binding.annotation,binding.span)
        p.env[binding.name]=S.Binding(value,false); value:export(p,binding.name,binding.span)
    end
    require('let.infer').new(p):run(); require('let.ownership').new(p):run()
    p.external=Host.declarations(p); p.next_function=#p.exports+#p.external
    return p
end
return Program

