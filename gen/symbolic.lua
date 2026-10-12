-- Bind the shared revision-6 transfers to the symbolic machine.
local root=arg[0]:match('^(.*)/[^/]+$') or '.'
package.path=root..'/?.lua;'..root..'/../tools/?.lua;'..package.path
local manifest,semantics=require('opcodes'),require('semantics')
local directory=assert(arg[1],'output directory required')
local output=assert(io.open(directory..'/symbolic_dispatch.c.tmp','wb'))
local function emit(text)assert(output:write(text,'\n'))end
emit('#include "symbolic.h"')
emit('typedef abc_symbolic_exit (*abc_symbolic_handler)(abc_symbolic_machine *);')
emit('static const abc_symbolic_handler handlers[OP_COUNT],extended_a[256],extended_b[256];')
emit('#define SYM_NEXT(N) do {m->pc+=(N)+m->extra_advance;m->extra_advance=0;if(m->pc>=m->end||(m->blocks&&m->blocks[m->pc]))return ABC_SYM_EXIT_BLOCK;ABC_MUSTTAIL return handlers[m->code[m->pc]](m);}while(0)')
local relations={BEQ='ABC_SYM_EQ',BNE='ABC_SYM_NE',BLT='ABC_SYM_LT',BLE='ABC_SYM_LE',
 BLTU='ABC_SYM_LTU',BLEU='ABC_SYM_LEU',BGT='ABC_SYM_LT',BGE='ABC_SYM_LE',
 BGTU='ABC_SYM_LTU',BGEU='ABC_SYM_LEU',FBLT='ABC_SYM_LT',FBLE='ABC_SYM_LE',FBEQ='ABC_SYM_EQ'}
local function generate(instruction,bank,extended)
 local name=manifest.operations[instruction.operation+1]
 local transfer=assert(semantics.transfers[name],name)
 local kind=transfer.kind
 local selected=bank or instruction.stack
 local other=selected==0 and 1 or 0
 local identity='ABC_OPERATION_'..name
 local handler=(extended and 'extended_'..name..'_'..selected or instruction.name):lower()
 if kind=='ext' then
  emit(('static abc_symbolic_exit h_%s(abc_symbolic_machine*m){ABC_MUSTTAIL return extended_%s[m->code[m->pc+1]](m);}'):format(handler,selected==0 and 'a' or 'b'))
  return handler
 end
 local action,mask,length=nil,'ABC_SYM_TRANSFER_STACK',tostring(instruction.len)
 local function call(helper,arguments) return 'abc_symbolic_machine_'..helper..'(m'..(arguments and ','..arguments or '')..')' end
 if kind=='push' then action=call('push',selected..','..({[8]='abc_imm8(p[0])',[32]='(uint64_t)(int64_t)abc_i32(p)',[64]='abc_u64(p)'})[transfer.width])
 elseif kind=='dup' or kind=='drop' or kind=='cpush' then action=call(kind,selected)
 elseif kind=='copy' or kind=='move' then action=call('transfer',selected..','..other..','..(kind=='move' and 1 or 0))
 elseif kind=='cpushn' then action=call(kind,selected..',p[0]')
 elseif kind=='cpop' then action=call(kind)
 elseif kind=='cget' or kind=='cset' then action=call(kind,selected..','..(transfer.depth~=nil and transfer.depth or 'p[0]'))
 elseif kind=='cgetr' then action=call('cget_range',selected..',p[0],p[1]')
 elseif kind=='binary' or kind=='float_binary' or kind=='unary' or kind=='float_unary' or kind=='check' or kind=='power' then
  action=call(kind=='power' and 'pow' or kind,identity..','..selected);mask='ABC_SYM_TRANSFER_VALUE'
 elseif kind=='immediate' or kind=='c_operand' then
  action=call(kind,identity..','..selected..','..(kind=='immediate' and 'abc_imm8(p[0])' or 'p[0]'));mask='ABC_SYM_TRANSFER_VALUE'
 elseif kind=='jump' or kind=='zero_branch' or kind=='branch' or kind=='float_branch' or kind=='immediate_branch' then
  local control=({jump='JUMP',zero_branch='ZERO',branch='INTEGER',float_branch='FLOAT',immediate_branch='IMMEDIATE'})[kind]
  local relation=kind=='zero_branch' and (transfer.zero and 'ABC_SYM_EQ' or 'ABC_SYM_NE') or relations[transfer.operation] or 'ABC_SYM_EQ'
  local reverse=kind=='immediate_branch' and transfer.operation:match('^BG') and 1 or 0
  local displacement=kind=='jump' and transfer.width==32 and 'abc_i32(p)' or 'abc_i16(p'..(kind=='immediate_branch' and '+1' or '')..')'
  action=call('control',('ABC_SYM_CONTROL_%s,%s,%s,%d,%d,(uint32_t)((int64_t)(m->pc+%s)+%s),m->pc+%s,%s'):format(control,identity,relation,reverse,selected,length,displacement,length,kind=='immediate_branch' and 'abc_imm8(p[0])' or '0'))
  mask='ABC_SYM_TRANSFER_CONTROL'
 elseif kind=='switch' then
  length='3+4*abc_u16(p)';action=call('switch',selected..',abc_u16(p),m->pc+'..length);mask='ABC_SYM_TRANSFER_CONTROL'
 elseif kind=='abort' then action=call('abort','p[0]');mask='ABC_SYM_TRANSFER_CONTROL'
 elseif kind=='halt' then action=call('halt',selected);mask='ABC_SYM_TRANSFER_CONTROL'
 elseif kind=='memory' or kind=='allocate' or kind=='free' then action=call('memory');mask='ABC_SYM_TRANSFER_EFFECT'
 elseif kind=='call' then action=call('call','(uint32_t)((int64_t)(m->pc+'..length..')+abc_i32(p)),p[4],'..selected..',m->pc+'..length);mask='ABC_SYM_TRANSFER_EFFECT'
 elseif kind=='tcall' then action=call('tail','(uint32_t)((int64_t)(m->pc+'..length..')+abc_i32(p)),p[4],p[5],'..selected);mask='ABC_SYM_TRANSFER_EFFECT'
 elseif kind=='ret' then action=call('return','p[0],p[1],'..selected);mask='ABC_SYM_TRANSFER_EFFECT'
 elseif kind=='calli' then action=call('indirect','0,p[0],'..selected..',0');mask='ABC_SYM_TRANSFER_EFFECT'
 elseif kind=='tcalli' then action=call('indirect','p[0],p[1],'..selected..',1');mask='ABC_SYM_TRANSFER_EFFECT'
 elseif kind=='fcall' then action=call('foreign',selected);mask='ABC_SYM_TRANSFER_EFFECT'
 else error('missing symbolic binding: '..name..' ('..kind..')') end
 emit(('static abc_symbolic_exit h_%s(abc_symbolic_machine*m){const uint8_t*p=m->code+m->pc+%d;(void)p;if(m->transfer_mask&&!(m->transfer_mask&%s))return abc_symbolic_machine_boundary(m);if(!(%s))return m->exit;SYM_NEXT(%s);}'):format(handler,extended and 2 or 1,mask,action,length))
 return handler
end
local core,extended_a,extended_b={},{},{}
for _,instruction in ipairs(manifest.ops) do core[instruction.opcode]=generate(instruction) end
for _,instruction in ipairs(manifest.ext_ops) do
 extended_a[instruction.selector]=generate(instruction,0,true)
 extended_b[instruction.selector]=generate(instruction,1,true)
end
local function table_definition(name,entries,size)
 emit(('static const abc_symbolic_handler %s[%d]={'):format(name,size))
 for index=0,size-1 do if entries[index] then emit((' [%d]=h_%s,'):format(index,entries[index])) end end
 emit('};')
end
table_definition('handlers',core,256);table_definition('extended_a',extended_a,256);table_definition('extended_b',extended_b,256)
emit('abc_symbolic_exit abc_symbolic_dispatch(abc_symbolic_machine*m){if(!m||!m->context||!m->code||m->pc>=m->end)return ABC_SYM_EXIT_FAILURE;abc_clear(m->error);m->exit=ABC_SYM_EXIT_BLOCK;ABC_MUSTTAIL return handlers[m->code[m->pc]](m);}')
emit('#undef SYM_NEXT')
assert(output:close());assert(os.rename(directory..'/symbolic_dispatch.c.tmp',directory..'/symbolic_dispatch.c'))
