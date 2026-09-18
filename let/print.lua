-- Render the C output vocabulary. This prints C; it decides no Let semantics.
return function(V)
local C=V.C
local function uint64_text(hi,lo) return ('0x%08x%08xULL'):format(hi,lo) end
-- Small magnitudes print in decimal so the emitted C stays readable; anything else keeps
-- the exact hexadecimal form, which also avoids ever writing INT64_MIN as a negated literal.
local function integer(hi,lo)
    if hi==0 and lo<2147483648 then return ('INT64_C(%d)'):format(lo) end
    if hi==4294967295 and lo>=2147483648 then return ('(-INT64_C(%d))'):format(4294967296-lo) end
    return '((int64_t)' .. uint64_text(hi,lo) .. ')'
end
local function quoted(text)
    local parts={'"'}
    for i=1,#text do
        local byte=text:byte(i)
        parts[#parts+1]=('\\%03o'):format(byte)
    end
    parts[#parts+1]='"'
    return table.concat(parts)
end
local function indent(level) return string.rep('    ',level) end

function C.Type:print() error('missing C type printer',0) end
function C.Void:print() return 'void' end
function C.Bool:print() return 'bool' end
function C.I64:print() return 'int64_t' end
function C.U64:print() return 'uint64_t' end
function C.F64:print() return 'double' end
function C.U8:print() return 'uint8_t' end
function C.U32:print() return 'uint32_t' end
function C.F32:print() return 'float' end
function C.Size:print() return 'size_t' end
function C.Pointer:print() return self.pointee:print() .. '*' end
function C.Named:print() return self.name end

function C.Expr:print() error('missing C expression printer',0) end
function C.Integer:print() return integer(self.hi,self.lo) end
function C.Float:print()
    if self.value~=self.value then return 'NAN' end
    if self.value==math.huge then return 'INFINITY' end
    if self.value==-math.huge then return '(-INFINITY)' end
    return string.format('%a',self.value)
end
function C.CString:print() return 'const char *' end
function C.Boolean:print() return self.value and 'true' or 'false' end
function C.String:print() return quoted(self.value) end
function C.Name:print() return self.name end
function C.Unary:print() return '(' .. self.operator .. self.operand:print() .. ')' end
function C.Binary:print() return '(' .. self.left:print() .. ' ' .. self.operator .. ' ' .. self.right:print() .. ')' end
function C.Cast:print() return '((' .. self.type:print() .. ')' .. self.value:print() .. ')' end
function C.Comma:print()
    local parts = {} for _, value in ipairs(self.values) do parts[#parts + 1] = value:print() end
    return '(' .. table.concat(parts, ', ') .. ')'
end
function C.Conditional:print()
    return '(' .. self.condition:print() .. ' ? ' .. self.yes:print() .. ' : ' .. self.no:print() .. ')'
end
function C.Call:print()
    local parts={} for _,argument in ipairs(self.arguments) do parts[#parts+1]=argument:print() end
    return self.callee:print() .. '(' .. table.concat(parts,', ') .. ')'
end
function C.Field:print() return '(' .. self.base:print() .. ').' .. self.name end
function C.Index:print() return '(' .. self.base:print() .. ')[' .. self.index:print() .. ']' end
function C.Compound:print()
    local parts={} for _,field in ipairs(self.fields) do parts[#parts+1]=field:print() end
    return '((' .. self.type:print() .. '){' .. table.concat(parts,', ') .. '})'
end
-- A designated initializer names each member it sets. The compiler uses it for a sum, so only
-- the tag and the active alternative are written and the rest is left to C's zero-fill.
function C.Init:print()
    local parts={} for _,field in ipairs(self.fields) do parts[#parts+1]='.' .. field.name .. ' = ' .. field.value:print() end
    return '((' .. self.type:print() .. '){' .. table.concat(parts,', ') .. '})'
end

-- Renders one statement. `lines` accumulates output; `level` is the indent depth.
local function statement(node,level,lines)
    local pad=indent(level)
    if C.Declare:isclassof(node) then
        local text=node.type:print() .. ' ' .. node.name
        if node.initial then text=text .. ' = ' .. node.initial:print() end
        lines[#lines+1]=pad .. text .. ';'
    elseif C.Assign:isclassof(node) then
        lines[#lines+1]=pad .. node.place:print() .. ' = ' .. node.value:print() .. ';'
    elseif C.Evaluate:isclassof(node) then
        lines[#lines+1]=pad .. node.value:print() .. ';'
    elseif C.Block:isclassof(node) then
        lines[#lines+1]=pad .. '{'
        for _,child in ipairs(node.statements) do statement(child,level+1,lines) end
        lines[#lines+1]=pad .. '}'
    elseif C.If:isclassof(node) then
        lines[#lines+1]=pad .. 'if (' .. node.condition:print() .. ')'
        statement(node.yes,level,lines)
        if node.no then lines[#lines+1]=pad .. 'else'; statement(node.no,level,lines) end
    elseif C.While:isclassof(node) then
        lines[#lines+1]=pad .. 'while (' .. node.condition:print() .. ')'
        statement(node.body,level,lines)
    elseif C.Break:isclassof(node) then
        lines[#lines+1]=pad .. 'break;'
    elseif C.Switch:isclassof(node) then
        -- C's own construct for a select on an integer, so a lowering that needs one writes one
        -- rather than a function. A case with no value is the default arm.
        lines[#lines+1]=pad .. 'switch (' .. node.value:print() .. ') {'
        for _,case in ipairs(node.cases) do
            lines[#lines+1]=indent(level+1) .. (case.value and ('case ' .. case.value:print() .. ':') or 'default:')
            for _,child in ipairs(case.body) do statement(child,level+2,lines) end
        end
        lines[#lines+1]=pad .. '}'
    elseif C.Label:isclassof(node) then
        lines[#lines+1]=node.name .. ':;'
    elseif C.Goto:isclassof(node) then
        lines[#lines+1]=pad .. 'goto ' .. node.name .. ';'
    elseif C.Return:isclassof(node) then
        lines[#lines+1]=node.value and (pad .. 'return ' .. node.value:print() .. ';') or (pad .. 'return;')
    else error('missing C statement printer',0) end
end

-- An empty list must print as (void): a bare () is an unprototyped declaration in C,
-- which conflicts with a later definition that passes promoted arguments.
local function parameters(list)
    if #list==0 then return 'void' end
    local parts={} for _,parameter in ipairs(list) do parts[#parts+1]=parameter.type:print() .. ' ' .. parameter.name end
    return table.concat(parts,', ')
end

local function declaration(node,lines)
    -- A union is a declaration like a struct, and §3.5's sum needs one: the payload is a union of
    -- the alternatives because only one of them has ever been written.
    if C.Struct:isclassof(node) or C.Union:isclassof(node) then
        lines[#lines+1]=(C.Union:isclassof(node) and 'union ' or 'struct ') .. node.name .. ' {'
        for _,field in ipairs(node.fields) do lines[#lines+1]='    ' .. field.type:print() .. ' ' .. field.name .. ';' end
        lines[#lines+1]='};'
    elseif C.Function:isclassof(node) then
        -- `extern` is a host-provided symbol, `exported` is ours but reachable from outside, and
        -- anything else is `static` -- **including a prototype**. A forward declaration and its
        -- definition must agree on linkage, and demand order is not dependency order, so the
        -- emitter needs prototypes for its own static functions.
        local prefix
        if node.external then prefix='extern '
        elseif node.exported then prefix=''
        else prefix='static ' end
        local head=prefix .. node.result:print() .. ' ' .. node.name .. '(' .. parameters(node.parameters) .. ')'
        if not node.body then lines[#lines+1]=head .. ';'; return end
        lines[#lines+1]=head .. ' {'
        statement(node.body,1,lines)
        lines[#lines+1]='}'
    elseif C.Global:isclassof(node) then
        lines[#lines+1]='static ' .. node.type:print() .. ' ' .. node.name .. ';'
    elseif C.Raw:isclassof(node) then
        lines[#lines+1]=node.code
    else error('missing C declaration printer',0) end
end

-- A null body is a forward declaration; `external` marks a host-provided symbol.
function C.Unit:print()
    local lines={}
    -- An include is a name: `<x>` for a system header, and a QUOTED one when the spelling starts
    -- with a quote, which is what a local header is. The distinction is C's, not ours, so the
    -- spelling carries it rather than a second field.
    for _,include in ipairs(self.includes) do
        if include:sub(1, 1) == '"' then
            lines[#lines+1]='#include ' .. include
        else
            lines[#lines+1]='#include <' .. include .. '>'
        end
    end
    if #lines>0 then lines[#lines+1]='' end
    for _,node in ipairs(self.declarations) do declaration(node,lines); lines[#lines+1]='' end
    return table.concat(lines,'\n')
end
V.print=function(unit) return unit:print() end
end
