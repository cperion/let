-- Constant execution binds the same scalar expressions as concrete/native code.
local root=arg[0]:match('^(.*)/[^/]+$') or '.'
package.path=root..'/?.lua;'..package.path
local semantics=require('semantics')
local output=assert(io.open(assert(arg[1],'output file required'),'wb'))
local function emit(text)assert(output:write(text,'\n'))end
emit('#include "symbolic.h"')
emit('uint64_t abc_symbolic_fold_binary(unsigned operation,uint64_t x,uint64_t y,int *ok){*ok=1;switch(operation){')
for _,name in ipairs(semantics.binary_order) do
 local guard=semantics.transfers[name].check_zero and 'if(!y){*ok=0;return 0;}' or ''
 emit(('case ABC_OPERATION_%s:%s return %s;'):format(name,guard,semantics.binary[name]))
end
emit('default:*ok=0;return 0;}}')
emit('uint64_t abc_symbolic_fold_unary(unsigned operation,uint64_t x){switch(operation){')
for _,name in ipairs(semantics.unary_order) do emit(('case ABC_OPERATION_%s:return %s;'):format(name,semantics.unary[name])) end
emit('default:__builtin_unreachable();}}')
emit('uint64_t abc_symbolic_fold_float(unsigned operation,uint64_t x,uint64_t y){switch(operation){')
for _,name in ipairs(semantics.float_binary_order) do emit(('case ABC_OPERATION_%s:return %s;'):format(name,semantics.float_binary[name])) end
emit('default:__builtin_unreachable();}}')
assert(output:close())
