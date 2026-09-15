-- C printing only. Binding-time analysis and effect ordering belong to evaluate.lua.
local V, ffi = require('let.vocab'), require('ffi')
local C = V.Residual
local U, limb = ffi.typeof('uint64_t'), ffi.new('uint64_t', 4294967296)
function C.I64:c() return 'int64_t' end
function C.Bool:c() return 'bool' end
function C.U8:c() return 'uint8_t' end
function C.Pointer:c() return self.pointee:c() .. ' *' end
function C.Expr:known() return nil end
function C.Integer:known() return ffi.cast('int64_t', U(self.hi) * limb + U(self.lo)) end
function C.Boolean:known() return self.value end
function C.Unit:known() return 0 end
function C.Integer:c()
    if self.hi == 2147483648 and self.lo == 0 then return '(-INT64_C(9223372036854775807)-1)' end
    return 'INT64_C(' .. tostring(self:known()):gsub('LL$', '') .. ')'
end
function C.Boolean:c() return self.value and 'true' or 'false' end
function C.Unit:c() return '0' end
function C.Local:c(ctx) return ctx:local_(self.id, self.type) end
function C.Argument:c() return 'p' .. self.index end
function C.Deref:c(ctx) return '(*' .. self.pointer:c(ctx) .. ')' end
function C.Address:c(ctx) return '(&' .. self.place:c(ctx) .. ')' end
function C.Expr:unsigned(ctx) return '((uint64_t)' .. self:c(ctx) .. ')' end
local wrapping = { ['+']=true, ['-']=true, ['*']=true }
function C.Binary:unsigned(ctx)
    if not wrapping[self.operator] then return C.Expr.unsigned(self, ctx) end
    return '(' .. self.left:unsigned(ctx) .. ' ' .. self.operator .. ' ' .. self.right:unsigned(ctx) .. ')'
end
function C.Binary:c(ctx)
    if wrapping[self.operator] then ctx.bits = true; return 'let_signed_bits(' .. self:unsigned(ctx) .. ')' end
    return '(' .. self.left:c(ctx) .. ' ' .. self.operator .. ' ' .. self.right:c(ctx) .. ')'
end
function C.Compare:c(ctx) return '(' .. self.left:c(ctx) .. ' ' .. self.operator .. ' ' .. self.right:c(ctx) .. ')' end
function C.Expr:test(ctx) return '(' .. self:c(ctx) .. ')' end
C.Compare.test = C.Compare.c
function C.Select:c(ctx) return '(' .. self.condition:c(ctx) .. ' ? ' .. self.yes:c(ctx) .. ' : ' .. self.no:c(ctx) .. ')' end
local Writer = {}; Writer.__index = Writer
function Writer:line(text) self.lines[#self.lines+1] = string.rep('  ', self.indent) .. text end
function Writer:local_(id, type_)
    local name = 'v' .. id
    if not self.locals[name] then self.locals[name] = true; self.declarations[#self.declarations+1] = '  ' .. type_:c() .. ' ' .. name .. ';' end
    return name
end
function Writer:call(id, arguments)
    self.stats.calls = self.stats.calls + 1
    local args = {}; for _, arg in ipairs(arguments) do args[#args+1] = arg:c(self) end
    return assert(self.symbols[id]) .. '(' .. table.concat(args, ', ') .. ')'
end
function C.Call:c(ctx) return ctx:call(self.function_id, self.arguments) end
function C.Assign:emit(ctx) ctx:line(self.place:c(ctx) .. ' = ' .. self.value:c(ctx) .. ';') end
function C.SeqStmt:emit(ctx, tail)
    for i, statement in ipairs(self.statements) do statement:emit(ctx, i == #self.statements and tail or nil) end
end
function C.IfStmt:emit(ctx, tail)
    ctx:line('if ' .. self.condition:test(ctx) .. ' {'); ctx.indent=ctx.indent+1
    self.yes:emit(ctx, tail); ctx.indent=ctx.indent-1; ctx:line('} else {'); ctx.indent=ctx.indent+1
    self.no:emit(ctx, tail); ctx.indent=ctx.indent-1; ctx:line('}')
end
function C.WhileStmt:emit(ctx)
    ctx:line('while (true) {'); ctx.indent=ctx.indent+1; self.test:emit(ctx)
    ctx:line('if (!' .. self.condition:test(ctx) .. ') break;'); self.body:emit(ctx)
    ctx.indent=ctx.indent-1; ctx:line('}')
end
function C.Label:emit(ctx) ctx:line('L' .. self.id .. ':;'); ctx.stats.labels=ctx.stats.labels+1 end
function C.Jump:emit(ctx)
    local saved = {}
    for i, value in ipairs(self.arguments) do
        ctx.temporary=ctx.temporary+1; local name='transfer' .. ctx.temporary
        ctx.declarations[#ctx.declarations+1]='  ' .. self.places[i].type:c() .. ' ' .. name .. ';'
        ctx:line(name .. ' = ' .. value:c(ctx) .. ';'); saved[i]=name
    end
    for i, name in ipairs(saved) do ctx:line(self.places[i]:c(ctx) .. ' = ' .. name .. ';') end
    ctx:line('goto L' .. self.label .. ';'); ctx.used[self.label]=true
end
function C.Exit:emit(ctx, tail)
    local type_ = ctx.regions[self.label]
    if type_ then ctx:line(ctx:local_(self.label, type_) .. ' = ' .. self.value:c(ctx) .. ';') end
    if tail ~= self.label then ctx:line('goto L' .. self.label .. ';'); ctx.used[self.label]=true end
end
function C.Region:emit(ctx)
    ctx.regions[self.label]=self.result or false; self.body:emit(ctx, self.label)
    if ctx.used[self.label] then C.Label(self.label):emit(ctx) end
end
function C.ReturnStmt:emit(ctx) ctx:line('return ' .. self.value:c(ctx) .. ';') end
function C.VoidCall:emit(ctx) ctx:line(ctx:call(self.function_id, self.arguments) .. ';') end
function C.Trap:emit(ctx) ctx:line('abort();') end
function C.Function:prototype()
    local params={}; for i, type_ in ipairs(self.parameters) do params[i]=type_:c() .. ' p' .. i end
    return (self.external and 'extern ' or self.exported and '' or 'static ') .. (self.result and self.result:c() or 'void') .. ' ' .. self.c_name .. '(' .. (#params>0 and table.concat(params, ', ') or 'void') .. ')'
end
function C.Function:emit(symbols)
    local ctx=setmetatable({symbols=symbols,lines={},declarations={},locals={},regions={},used={},indent=1,temporary=0,stats={calls=0,labels=0}}, Writer)
    self.body:emit(ctx); ctx.stats.locals=#ctx.declarations; ctx.stats.statements=#ctx.lines
    local declarations=#ctx.declarations>0 and table.concat(ctx.declarations,'\n') .. '\n' or ''
    return self:prototype() .. ' {\n' .. declarations .. table.concat(ctx.lines,'\n') .. '\n}', ctx.stats, ctx.bits
end
function C.Module:emit()
    local lines, symbols, stats={'#include <stdint.h>','#include <stdbool.h>','#include <stdlib.h>','#include <string.h>',''}, {}, {}
    for _, fn in ipairs(self.functions) do symbols[fn.id]=fn.c_name; lines[#lines+1]=fn:prototype() .. ';' end
    local bodies, bits={},false
    for _, fn in ipairs(self.functions) do if not fn.external then
        local body, info, uses_bits=fn:emit(symbols); bodies[#bodies+1]=body; stats[fn.c_name]=info; bits=bits or uses_bits
    end end
    if bits then lines[#lines+1]='static inline int64_t let_signed_bits(uint64_t x) { int64_t y; memcpy(&y, &x, sizeof y); return y; }' end
    for _, body in ipairs(bodies) do lines[#lines+1]='\n' .. body end
    return table.concat(lines,'\n') .. '\n', stats
end
return C

