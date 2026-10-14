-- Validate the shared form catalog and compile-time C addressing formulas.
-- Optional argument writes a C translation unit of exhaustive static assertions.
package.path='gen/?.lua;'..package.path
local forms=require('execution_forms')
local semantics=require('semantics')
local indices={}
local function index(ops)
  local out={} for i,op in ipairs(ops) do out[op]=i-1 end return out
end
indices.binary=index(semantics.binary_order)
indices.binary32=index(forms.binary32)
indices.unary=index(semantics.unary_order)
indices.immediate=index(semantics.immediate_order)
indices.immediate32=indices.immediate
indices.branch=index(forms.branches)
indices.float_binary=index(semantics.float_binary_order)
indices.float_unary=index(semantics.float_unary_order)
indices.float_branch=index(semantics.float_branch_order)
indices.check=index(semantics.check_order)
local loads,stores={},{}
for i,k in ipairs(forms.loads) do loads[i]=k[1] end
for i,k in ipairs(forms.stores) do stores[i]=k[1] end
for _,kind in ipairs({'memory_load','frame_load','global_load'}) do indices[kind]=index(loads) end
for _,kind in ipairs({'memory_store','frame_store','global_store'}) do indices[kind]=index(stores) end
local macro={binary='BINARY',binary32='BINARY32',unary='UNARY',immediate='IMMEDIATE',
  immediate32='IMMEDIATE32',branch='BRANCH',float_binary='FLOAT_BINARY',float_unary='FLOAT_UNARY',
  float_branch='FLOAT_BRANCH',check='CHECK',memory_load='MEM_LOAD',memory_store='MEM_STORE',
  frame_load='FRAME_LOAD',frame_store='FRAME_STORE',global_load='GLOBAL_LOAD',global_store='GLOBAL_STORE'}
local stack={a=0,b=1,c=2}
local function expression(f)
  local args={} for _,r in ipairs(f.registers) do args[#args+1]=r end
  local name=macro[f.kind]
  if name then table.insert(args,1,assert(indices[f.kind][f.operation]))
  elseif f.kind=='const' then name='CONST'
  elseif f.kind=='move' then name='MOV'
  elseif f.kind=='zero_branch' then name=f.operation=='EQ' and 'JZ' or 'JNZ'
  elseif f.kind=='home_load' or f.kind=='home_store' then
    name=f.kind=='home_load' and 'LOAD' or 'STORE';table.insert(args,1,stack[f.stack])
  elseif f.kind=='index' then name='INDEX'
  elseif f.kind=='memory_copy' then name='MEMCPY'
  elseif f.kind=='frame_address' then name='FRAME_ADDR'
  elseif f.kind=='global_address' then name='GLOBAL_ADDR'
  elseif f.kind=='pow' then name=f.operation
  elseif f.kind=='foreign' then name='FCALL';args={stack[f.stack],f.operation}
  elseif f.kind=='guard' or f.kind=='rebase' then name=f.kind:upper();args={stack[f.stack]}
  elseif f.kind=='continue' then name='CONTINUE'
  elseif f.kind:match('^release_') and f.kind~='release_entry' then name=f.kind:upper()
  else
    local constants={frame_zero='CALLOC',release_entry='RELEASE_ENTRY',abort='ABORT',resolve_indirect='RESOLVE_INDIRECT',
      store_continuation='STORE_LABEL',jump='JUMP',finish='FINISH',return_ok='RETURN_OK',native_lazy_entry='LAZY_ENTRY'}
    return 'ABC_FORM_'..assert(constants[f.kind],f.kind)
  end
  return 'ABC_FORM_'..name..'('..table.concat(args,',')..')'
end
local out=arg[1] and assert(io.open(arg[1],'wb'))
if out then out:write('#include "execution_forms.h"\n') end
local threaded=0
for i,f in ipairs(forms.forms) do
  assert(f.id==i-1 and forms.by_name[f.name]==f)
  assert(f.words==1+#f.operands)
  local available=not f.native_only
  for _,r in ipairs(f.registers) do
    assert(r>=0 and r<8 and r==math.floor(r))
    if r==7 then available=false end
  end
  local fields={}
  for _,operand in ipairs(f.operands) do
    local name,kind=operand:match('^([a-z_]+):([a-z0-9]+)$')
    assert(name and not fields[name],f.name..': malformed or repeated operand')
    assert(({u64=true,i64=true,ptr=true,fnptr=true,tape=true,code=true})[kind],operand)
    fields[name]=true
  end
  assert(forms.available(f,'native'))
  assert(forms.available(f,'threaded')==available)
  if available then threaded=threaded+1 end
  local expr=expression(f)
  if out then out:write(('_Static_assert(%s == %d, "%s");\n'):format(expr,f.id,f.name)) end
end
assert(#forms.forms==3803,'form coverage changed: review all bindings')
assert(forms.native_registers==8 and forms.threaded_registers==7)
local examples={const_2=2,mov_2_5=1,add_2_5=1,addi_2=2,divu_2_5=2,
  load_c_2=2,store_a_2=2,bne_2_5=2,store_label=3,continue_1=1,guard_a=4}
for name,words in pairs(examples) do assert(forms.by_name[name].words==words,name) end
assert(not forms.available(forms.by_name.add_2_7,'threaded'))
assert(not forms.available(forms.by_name.const_7,'threaded'))
assert(not forms.available(forms.by_name.continue_7,'threaded'))
assert(not forms.available(forms.by_name.lazy_entry,'threaded'))
assert(not forms.available(forms.by_name.release_entry,'threaded'))
assert(not forms.available(forms.by_name.release_field_0,'threaded'))
assert(forms.available(forms.by_name.add_2_6,'threaded'))
if out then
  out:write(('_Static_assert(ABC_FORM_COUNT == %d, "form count");\nint main(void) { return 0; }\n'):format(#forms.forms))
  assert(out:close())
end
print(('execution forms: %d native, %d threaded-eligible; layouts and register exclusions pass'):format(#forms.forms,threaded))
