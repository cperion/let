-- Binding-time domain. Known values contain semantic atoms, never residual expressions.
local V, ffi = require('let.vocab'), require('ffi')
local E, S, C = V.Evaluation, V.Semantic, V.Residual
local U, limb = ffi.typeof('uint64_t'), ffi.new('uint64_t',4294967296)
local M = {}
function E.Bits:native() return ffi.cast('int64_t', U(self.hi)*limb+U(self.lo)) end
function E.Truth:native() return self.value end
function E.Nothing:native() return 0 end
function E.Bits:code() return C.Integer(self.hi,self.lo) end
function E.Truth:code() return C.Boolean(self.value) end
function E.Nothing:code() return C.Unit end
function E.Value:key() return '?' end
function E.Known:key() return self.shape.kind .. ':' .. tostring(self.atom:native()) end
function E.Value:same(other) return self == other end
function E.Known:same(other) return E.Known:isclassof(other) and self.shape==other.shape and self:known()==other:known() end
function E.Value:known() return nil end
function E.Known:known() return self.atom:native() end
function E.Known:code() return self.atom:code() end
function E.Dynamic:code() return self.expression end
function E.Resource:code() return self.expression end
function E.Value:abi() return self.shape:ctype() end
function E.Place:abi() return C.Pointer(self.shape:ctype()) end
function M.integer(n) local u=U(n); return E.Known(S.Int,E.Bits(tonumber(u/limb),tonumber(u%limb))) end
function M.boolean(b) return E.Known(S.Bool,E.Truth(b)) end
function M.unit() return E.Known(S.Unit,E.Nothing) end
local arithmetic={['+']=function(a,b)return U(a)+U(b)end,['-']=function(a,b)return U(a)-U(b)end,['*']=function(a,b)return U(a)*U(b)end}
local comparisons={['==']=function(a,b)return a==b end,['!=']=function(a,b)return a~=b end,['<']=function(a,b)return a<b end,['<=']=function(a,b)return a<=b end,['>']=function(a,b)return a>b end,['>=']=function(a,b)return a>=b end}
local minimum=ffi.cast('int64_t',U(2147483648)*limb)
function E.Value:binary(ctx, op, right)
    local a,b=self:code(),right:code()
    if comparisons[op] then return E.Dynamic(S.Bool,C.Compare(op,a,b)) end
    if arithmetic[op] then return E.Dynamic(S.Int,C.Binary(op,a,b)) end
    if right:known()==0 then ctx:emit(C.Trap); ctx.terminated=true; return E.Bottom(S.Int) end
    if right:known()==nil then ctx:emit(C.IfStmt(C.Compare('==',b,M.integer(0):code()),C.SeqStmt(V.List{C.Trap}),C.SeqStmt(V.List()))) end
    local ordinary=C.Binary(op,a,b)
    local x=self:binary(ctx,'==',M.integer(minimum)); local y=right:binary(ctx,'==',M.integer(-1))
    if x:known()==false or y:known()==false then return E.Dynamic(S.Int,ordinary) end
    local exceptional=x:known()==true and y:code() or y:known()==true and x:code() or C.Binary('&&',x:code(),y:code())
    return E.Dynamic(S.Int,C.Select(exceptional,M.integer(op=='/' and minimum or 0):code(),ordinary))
end
function E.Known:binary(ctx, op, right)
    if not E.Known:isclassof(right) then return E.Value.binary(self,ctx,op,right) end
    local a,b=self:known(),right:known()
    if comparisons[op] then return M.boolean(comparisons[op](a,b)) end
    if arithmetic[op] then return M.integer(arithmetic[op](a,b)) end
    if b==0 then ctx:emit(C.Trap); ctx.terminated=true; return E.Bottom(S.Int) end
    if a==minimum and b==-1 then return M.integer(op=='/' and minimum or 0) end
    return M.integer(op=='/' and a/b or a%b)
end
function S.Scalar:evaluation() return E.Known(self.shape,self.atom) end
function S.Word:evaluation() return E.Word(self.id,self.bound:map(function(v)return v:evaluation()end)) end
function S.Host:evaluation() return E.Host(self.id) end
return M

