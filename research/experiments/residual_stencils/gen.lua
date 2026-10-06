-- Register-addressed residual stencils, translated from the refreshed seed.
-- Run from this directory: luajit gen.lua
local R = 8
local args,pass={},{}
for i=0,R-1 do args[#args+1]='V r'..i; pass[#pass+1]='r'..i end
local output={'#include <stdint.h>','typedef uint64_t V;','#define PN __attribute__((preserve_none))',
    '#define ARGS V *asp, V *bsp, V *csp, '..table.concat(args,', '),
    '#define PASS asp, bsp, csp, '..table.concat(pass,', '),
    'extern PN V HOLE_NEXT(ARGS); extern PN V HOLE_TAKEN(ARGS); extern char HOLE_IMM[], HOLE_IMM2[], HOLE_FINAL[];',
    '#define NEXT [[clang::musttail]] return HOLE_NEXT(PASS);'}
local names={}
local function stencil(name,body)
    names[#names+1]=name
    output[#output+1]='PN V '..name..'(ARGS) { '..body..' }'
end
for i=0,R-1 do
    for j=0,R-1 do
        if i~=j then
            stencil(('mov_%d_%d'):format(i,j),('r%d = r%d; NEXT'):format(i,j))
            stencil(('xor32_%d_%d'):format(i,j),('r%d = (uint32_t)r%d ^ (uint32_t)r%d; NEXT'):format(i,i,j))
        end
    end
    for _,k in ipairs({5,13}) do
        stencil(('shl32_%d_%d'):format(i,k),('r%d = (uint32_t)((uint32_t)r%d << %d); NEXT'):format(i,i,k))
    end
    stencil('shr32_'..i..'_17',('r%d = (uint32_t)r%d >> 17; NEXT'):format(i,i))
    stencil('sub32_'..i..'_imm',('r%d = (uint32_t)((uint32_t)r%d - (uint32_t)(uintptr_t)HOLE_IMM); NEXT'):format(i,i))
    stencil('bz_'..i,('if (r%d == 0) { [[clang::musttail]] return HOLE_TAKEN(PASS); } NEXT'):format(i))
    stencil('exit_'..i,('*(V *)HOLE_FINAL = r%d; return 0;'):format(i))
end
stencil('jmp','[[clang::musttail]] return HOLE_TAKEN(PASS);')
local function write(path,lines)
    local file=assert(io.open(path,'w')); assert(file:write(table.concat(lines,'\n'),'\n')); assert(file:close())
end
write('rs.c',output); write('rs_order.txt',names)
local defines={}
for i,name in ipairs(names) do defines[#defines+1]='#define S_'..name..' '..(i-1) end
write('rs_names.h',defines)
print(#names..' stencils')

