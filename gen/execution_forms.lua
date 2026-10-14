-- Register-addressed execution forms, independent of native instruction bytes.
-- IDs describe bound physical operations, not another value IR or public ISA.
-- IDs retain eight-slot coordinates for both bindings. Threaded availability
-- excludes any form using slot 7; it does not renumber the remaining forms.
local semantics=require('semantics')
local M={native_registers=8,threaded_registers=7,forms={},by_name={}}
local R=M.native_registers
local header={'#ifndef ABC_EXECUTION_FORMS_H','#define ABC_EXECUTION_FORMS_H',
  '#define ABC_NATIVE_VALUE_REGISTERS 8','#define ABC_THREADED_VALUE_REGISTERS 7'}
local function define(name,value) header[#header+1]='#define '..name..' '..value end
local function base(name) define('ABC_FORM_'..name..'_BASE',#M.forms) end
local function add(name,kind,regs,operands,op,stack,native_only)
  assert(not M.by_name[name],'duplicate execution form '..name)
  local form={id=#M.forms,name=name,kind=kind,registers=regs or {},
    operands=operands or {},operation=op,stack=stack,native_only=native_only or false}
  -- One handler word, then exactly one 64-bit word per bound operand.
  form.words=1+#form.operands
  M.forms[#M.forms+1]=form;M.by_name[name]=form
end
local function enums(prefix,ops)
  for i,op in ipairs(ops) do define(prefix..op,i-1) end
end
local function matrix(group,kind,ops,naming,operands)
  base(group)
  define('ABC_FORM_'..group..'(OP,D,S)','(ABC_FORM_'..group..'_BASE+(OP)*64+(D)*8+(S))')
  for _,op in ipairs(ops) do for d=0,R-1 do for s=0,R-1 do
    add(naming(op,d,s),kind,{d,s},operands(op),op)
  end end end
end
local function vector(group,kind,ops,naming,operands)
  base(group)
  define('ABC_FORM_'..group..'(OP,D)','(ABC_FORM_'..group..'_BASE+(OP)*8+(D))')
  for _,op in ipairs(ops) do for d=0,R-1 do
    add(naming(op,d),kind,{d},operands(op),op)
  end end
end
local function none() return {} end
local function immediate() return {'immediate:u64'} end
local function offset() return {'byte_offset:i64'} end
local function target() return {'target:tape'} end
local function error_word() return {'error:u64'} end
local function binary_name(op,d,s) return ('%s_%d_%d'):format(op:lower(),d,s) end

define('ABC_FORM_CONST(D)','((D)*8)')
define('ABC_FORM_MOV(D,S)','((D)*8+1+((S)<(D)?(S):(S)-1))')
for d=0,R-1 do
  add(('const_%d'):format(d),'const',{d},immediate())
  for s=0,R-1 do if d~=s then add(('mov_%d_%d'):format(d,s),'move',{d,s}) end end
end
enums('ABC_JOP_',semantics.binary_order)
matrix('BINARY','binary',semantics.binary_order,binary_name,function(op)
  return semantics.transfers[op].check_zero and error_word() or none()
end)
M.binary32={'ADD','SUB','MUL','AND','OR','XOR'}
enums('ABC_J32_',M.binary32)
matrix('BINARY32','binary32',M.binary32,function(op,d,s) return 'u32_'..binary_name(op,d,s) end,none)
enums('ABC_JUN_',semantics.unary_order)
vector('UNARY','unary',semantics.unary_order,function(op,d) return ('%s_%d'):format(op:lower(),d) end,none)
enums('ABC_JIMM_',semantics.immediate_order)
vector('IMMEDIATE','immediate',semantics.immediate_order,function(op,d) return ('%si_%d'):format(op:lower(),d) end,immediate)
vector('IMMEDIATE32','immediate32',semantics.immediate_order,function(op,d) return ('u32_%si_%d'):format(op:lower(),d) end,immediate)
base('ACCESS')
define('ABC_FORM_JZ(D)','(ABC_FORM_ACCESS_BASE+(D)*8)')
define('ABC_FORM_JNZ(D)','(ABC_FORM_ACCESS_BASE+(D)*8+1)')
define('ABC_FORM_LOAD(STACK,D)','(ABC_FORM_ACCESS_BASE+(D)*8+2+(STACK)*2)')
define('ABC_FORM_STORE(STACK,D)','(ABC_FORM_ACCESS_BASE+(D)*8+3+(STACK)*2)')
for d=0,R-1 do
  add(('jz_%d'):format(d),'zero_branch',{d},target(),'EQ')
  add(('jnz_%d'):format(d),'zero_branch',{d},target(),'NE')
  for _,stack in ipairs({'a','b','c'}) do
    add(('load_%s_%d'):format(stack,d),'home_load',{d},offset(),nil,stack)
    add(('store_%s_%d'):format(stack,d),'home_store',{d},offset(),nil,stack)
  end
end
M.branches={}
for _,op in ipairs(semantics.branch_order) do M.branches[#M.branches+1]=op:sub(2) end
enums('ABC_JBR_',M.branches)
matrix('BRANCH','branch',M.branches,function(op,d,s) return 'b'..binary_name(op,d,s) end,target)
enums('ABC_JFLOAT_',semantics.float_binary_order)
matrix('FLOAT_BINARY','float_binary',semantics.float_binary_order,function(op,d,s) return 'float_'..binary_name(op,d,s) end,none)
enums('ABC_JFUN_',semantics.float_unary_order)
vector('FLOAT_UNARY','float_unary',semantics.float_unary_order,function(op,d) return ('float_%s_%d'):format(op:lower(),d) end,function(op)
  return (op=='F2IS' or op=='F2IU') and error_word() or none()
end)
matrix('FLOAT_BRANCH','float_branch',semantics.float_branch_order,function(op,d,s)
  return ('float_b%s_%d_%d'):format(op:sub(3):lower(),d,s)
end,target)
M.loads={{'u8','uint8_t'},{'u16','uint16_t'},{'u32','uint32_t'},{'s32','int32_t'},{'u64','uint64_t'}}
M.stores={{'u8','uint8_t'},{'u16','uint16_t'},{'u32','uint32_t'},{'u64','uint64_t'}}
local loads,stores={},{}
for i,k in ipairs(M.loads) do loads[i]=k[1];define('ABC_JLOAD_'..k[1]:upper(),i-1) end
for i,k in ipairs(M.stores) do stores[i]=k[1] end
vector('MEM_LOAD','memory_load',loads,function(k,d) return ('mem_load_%s_%d'):format(k,d) end,offset)
matrix('MEM_STORE','memory_store',stores,function(k,d,s) return ('mem_store_%s_%d_%d'):format(k,d,s) end,offset)
base('INDEX');define('ABC_FORM_INDEX(A,I)','(ABC_FORM_INDEX_BASE+(A)*8+(I))')
for a=0,R-1 do for i=0,R-1 do add(('index_%d_%d'):format(a,i),'index',{a,i},{'scale:i64'}) end end
base('MEMCPY');define('ABC_FORM_MEMCPY(A,B)','(ABC_FORM_MEMCPY_BASE+(A)*8+(B))')
for a=0,R-1 do for b=0,R-1 do add(('memcpy_%d_%d'):format(a,b),'memory_copy',{a,b},{'bytes:u64','copy:fnptr'}) end end
define('ABC_FORM_CALLOC',#M.forms)
add('calloc','frame_zero',{}, {'cells:u64','c_byte_offset:i64'})
vector('FRAME_LOAD','frame_load',loads,function(k,d) return ('frame_load_%s_%d'):format(k,d) end,offset)
vector('FRAME_STORE','frame_store',stores,function(k,d) return ('frame_store_%s_%d'):format(k,d) end,offset)
base('FRAME_ADDR');define('ABC_FORM_FRAME_ADDR(D)','(ABC_FORM_FRAME_ADDR_BASE+(D))')
for d=0,R-1 do add(('frame_addr_%d'):format(d),'frame_address',{d},offset()) end
vector('GLOBAL_LOAD','global_load',loads,function(k,d) return ('global_load_%s_%d'):format(k,d) end,function()return {'address:ptr'}end)
vector('GLOBAL_STORE','global_store',stores,function(k,d) return ('global_store_%s_%d'):format(k,d) end,function()return {'address:ptr'}end)
base('GLOBAL_ADDR');define('ABC_FORM_GLOBAL_ADDR(D)','(ABC_FORM_GLOBAL_ADDR_BASE+(D))')
for d=0,R-1 do add(('global_addr_%d'):format(d),'global_address',{d},{'address:ptr'}) end
base('POW');define('ABC_FORM_POW(A,B)','(ABC_FORM_POW_BASE+(A)*8+(B))')
define('ABC_FORM_POWS(A,B)','(ABC_FORM_POW_BASE+64+(A)*8+(B))')
for a=0,R-1 do for b=0,R-1 do add(('pow_%d_%d'):format(a,b),'pow',{a,b},{},'POW') end end
for a=0,R-1 do for b=0,R-1 do add(('pows_%d_%d'):format(a,b),'pow',{a,b},error_word(),'POWS') end end
M.check_suffix={CHKU8='u8',CHKU16='u16',CHKU32='u32',CHKI32='i32',CHKNN='nn'}
vector('CHECK','check',semantics.check_order,function(op,d) return ('check_%s_%d'):format(M.check_suffix[op],d) end,error_word)
base('FCALL');define('ABC_FORM_FCALL(STACK,RESULTS)','(ABC_FORM_FCALL_BASE+(STACK)*2+(RESULTS))')
for _,stack in ipairs({'a','b'}) do for results=0,1 do
  add(('fcall_%s_%d'):format(stack,results),'foreign',{},
    {'argument_byte_offset:i64','bridge:fnptr','external:ptr','callee:fnptr','error:u64'},results,stack)
end end
define('ABC_FORM_ABORT',#M.forms);add('abort','abort',{},error_word())
base('GUARD');define('ABC_FORM_GUARD(S)','(ABC_FORM_GUARD_BASE+(S))')
for _,stack in ipairs({'a','b','c'}) do add('guard_'..stack,'guard',{},
  {'required_bytes:u64','bounds:fnptr','error:u64'},nil,stack) end
define('ABC_FORM_RESOLVE_INDIRECT',#M.forms)
add('resolve_indirect','resolve_indirect',{0},
  {'resolver:fnptr','pc:u64','a_byte_offset:i64','b_byte_offset:i64','c_byte_offset:i64'})
define('ABC_FORM_STORE_LABEL',#M.forms)
add('store_label','store_continuation',{}, {'c_byte_offset:i64','resume:tape'})
base('REBASE');define('ABC_FORM_REBASE(S)','(ABC_FORM_REBASE_BASE+(S))')
for _,stack in ipairs({'a','b','c'}) do add('rebase_'..stack,'rebase',{},offset(),nil,stack) end
base('CONTINUE');define('ABC_FORM_CONTINUE(R)','(ABC_FORM_CONTINUE_BASE+(R))')
for r=0,R-1 do add(('continue_%d'):format(r),'continue',{r}) end
define('ABC_FORM_JUMP',#M.forms);add('jump','jump',{},target())
define('ABC_FORM_FINISH',#M.forms);add('finish','finish',{0},{'output:ptr'})
define('ABC_FORM_RETURN_OK',#M.forms);add('return_ok','return_ok')
define('ABC_FORM_LAZY_ENTRY',#M.forms)
add('lazy_entry','native_lazy_entry',{}, {'state:ptr','prepare:fnptr'},nil,nil,true)
base('RELEASE_FIELD');define('ABC_FORM_RELEASE_FIELD(R)','(ABC_FORM_RELEASE_FIELD_BASE+(R))')
for r=0,R-1 do add(('release_field_%d'):format(r),'release_field',{r},
  {'callee:fnptr','offset:u64','ordinal:u64'},nil,nil,true) end
for _,kind in ipairs{'DATA','PROGRESS','ENQUEUE'} do
 base('RELEASE_'..kind);define('ABC_FORM_RELEASE_'..kind..'(R)','(ABC_FORM_RELEASE_'..kind..'_BASE+(R))')
 for r=0,R-1 do add(('release_%s_%d'):format(kind:lower(),r),'release_'..kind:lower(),{r},{'callee:fnptr'},nil,nil,true) end
end
define('ABC_FORM_RELEASE_ENTRY',#M.forms)
add('release_entry','release_entry',{}, {'frame_bytes:u64','b_offset:u64','c_offset:u64','body:code'},nil,nil,true)
define('ABC_FORM_COUNT',#M.forms)
header[#header+1]='#endif'
function M.header() return table.concat(header,'\n')..'\n' end
function M.available(form,binding)
  assert(binding=='native' or binding=='threaded','invalid execution binding')
  if binding=='threaded' and form.native_only then return false end
  local count=binding=='native' and M.native_registers or M.threaded_registers
  for _,r in ipairs(form.registers) do if r>=count then return false end end
  return true
end
return M
