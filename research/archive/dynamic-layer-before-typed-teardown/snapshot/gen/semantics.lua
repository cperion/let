-- Authoritative pure expressions plus sink-independent symbolic transfer classes.
-- Cache placement and target-specific emission remain separate from these semantics.
local M = {}
M.binary = {
  ADD='x+y', SUB='x-y', MUL='x*y', AND='x&y', OR='x|y', XOR='x^y',
  SHL='(y>=64 ? 0 : x<<y)', SHR='(y>=64 ? 0 : x>>y)', SAR='vm_sar(x,y)',
  EQ='x==y', NE='x!=y', LT='abc_signed(x)<abc_signed(y)', LE='abc_signed(x)<=abc_signed(y)',
  LTU='x<y', LEU='x<=y', DIVU='x/y', REMU='x%y',
  DIVS='(y==UINT64_MAX ? 0-x : (uint64_t)(abc_signed(x)/abc_signed(y)))',
  REMS='(y==UINT64_MAX ? 0 : (uint64_t)(abc_signed(x)%abc_signed(y)))',
}
M.binary_order={'ADD','SUB','MUL','DIVU','DIVS','REMU','REMS','AND','OR','XOR','SHL','SHR','SAR','EQ','NE','LT','LE','LTU','LEU'}
M.unary_order={'NEG','NOT','LNOT','ZX32','SX32'}
M.immediate_order={'ADD','SUB','MUL','AND','OR','XOR','SHL','SHR','SAR'}
M.c_operand_order={'ADD','SUB','MUL','XOR'}
M.check_order={'CHKU8','CHKU16','CHKU32','CHKI32','CHKNN'}
M.branch_order={'BEQ','BNE','BLT','BLE','BLTU','BLEU'}
M.float_binary_order={'FADD','FSUB','FMUL','FDIV','FLT','FLE','FEQ'}
M.float_unary_order={'FNEG','I2FS','I2FU','F2IS','F2IU'}
M.float_branch_order={'FBLT','FBLE','FBEQ'}
M.float_binary={FADD='vm_fadd(x,y)',FSUB='vm_fsub(x,y)',FMUL='vm_fmul(x,y)',FDIV='vm_fdiv(x,y)',
                FLT='vm_flt(x,y)',FLE='vm_fle(x,y)',FEQ='vm_feq(x,y)'}
M.float_branches={FBLT='vm_flt(x,y)',FBLE='vm_fle(x,y)',FBEQ='vm_feq(x,y)'}
M.unary = { NEG='0-x', NOT='~x', LNOT='x^1', ZX32='x&UINT32_MAX',
            SX32='(uint64_t)(int64_t)abc_i32_from_u64(x)' }
M.checks = { CHKU8='x>255', CHKU16='x>65535', CHKU32='x>UINT32_MAX',
             CHKI32='abc_signed(x)<INT32_MIN || abc_signed(x)>INT32_MAX', CHKNN='x>>63' }
M.comparisons = { BEQ='x==y', BNE='x!=y', BLT='abc_signed(x)<abc_signed(y)',
  BLE='abc_signed(x)<=abc_signed(y)', BLTU='x<y', BLEU='x<=y',
  BGT='abc_signed(x)>abc_signed(y)', BGE='abc_signed(x)>=abc_signed(y)',
  BGTU='x>y', BGEU='x>=y' }
-- Scalar EXT semantics are checked compositions of the ordinary operations.
-- Both the banked interpreter and symbolic execution consume these recipes;
-- neither execution sink owns a second arithmetic/conversion switch.
M.scalar_binary_order={'DADD','DSUB','DMUL','DDIV','DREM','DPOW','DSHL','DSHR','DSAR','DAND','DOR','DXOR','DLT','DLE'}
M.scalar_binary={
  DADD={'ADD','ADD','FADD'}, DSUB={'SUB','SUB','FSUB'}, DMUL={'MUL','MUL','FMUL'},
  DDIV={'DIVU','DIVS','FDIV'}, DREM={'REMU','REMS'}, DPOW={'POW','POW'},
  DSHL={'SHL','SHL'}, DSHR={'SHR','SHR'}, DSAR={'SAR','SAR'},
  DAND={'AND','AND'}, DOR={'OR','OR'}, DXOR={'XOR','XOR'},
  DLT={'LTU','LT','FLT'}, DLE={'LEU','LE','FLE'},
}
M.scalar_unary_order={'DNEG','DNOT','DLNOT','DREQUIRE_BOOL'}
M.scalar_unary={DNEG={'NEG','FNEG'},DNOT={'NOT'},DLNOT={'EQ_ZERO'},DREQUIRE_BOOL={'IDENTITY'}}
M.scalar_tags={'UNIT','BOOL','U8','U16','U32','U64','I32','I64','F64'}
M.scalar_widths={0,1,8,16,32,64,32,64,64}
function M.scalar_normalization(tag)
  if tag=='U8' then return {{'mask',255}} elseif tag=='U16' then return {{'mask',65535}}
  elseif tag=='U32' then return {{'unary','ZX32'}} elseif tag=='I32' then return {{'unary','SX32'}} end
  return {}
end
function M.scalar_conversion(from,to)
  local steps={}
  local function add(kind,op) steps[#steps+1]={kind,op} end
  local function signed(t) return t=='I32' or t=='I64' end
  local function width(t) for i,v in ipairs(M.scalar_tags) do if v==t then return M.scalar_widths[i] end end end
  if from==to then if to=='F64' then add('canonical','F64') end;return steps end
  if to=='F64' then add('float_unary',signed(from) and 'I2FS' or 'I2FU');return steps end
  if from=='F64' then add('float_unary',signed(to) and 'F2IS' or 'F2IU');from=signed(to) and 'I64' or 'U64' end
  local fw,tw=width(from),width(to)
  if fw~=tw then
    if signed(to) then
      if not signed(from) then add('check','CHKNN') end
      if tw==32 then add('check','CHKI32') end
    else
      if signed(from) then add('check','CHKNN') end
      if tw<64 then add('check','CHKU'..tw) end
    end
  end
  for _,step in ipairs(M.scalar_normalization(to)) do steps[#steps+1]=step end
  return steps
end
-- Sink-independent transfer classes consumed by the generated symbolic VM.
-- The generator assigns every remaining manifest opcode an explicit effect contract
-- and rejects an opcode that has neither a transfer class nor such a contract.
M.symbolic = {}
local function symbolic(name,effect) assert(not M.symbolic[name],name); M.symbolic[name]=effect end
for _,stack in ipairs{'A','B'} do
  for _,width in ipairs{8,32,64} do symbolic(('PUSH%d_%s'):format(width,stack),{kind='push',stack=stack,width=width}) end
  symbolic('DUP_'..stack,{kind='dup',stack=stack})
  symbolic('DROP_'..stack,{kind='drop',stack=stack})
  symbolic('CPUSH_'..stack,{kind='cpush',stack=stack})
  for _,depth in ipairs{0,1} do symbolic(('CGET%d_%s'):format(depth,stack),{kind='cget',stack=stack,depth=depth}) end
  symbolic('CGETN_'..stack,{kind='cget',stack=stack,depth='immediate'})
  symbolic('CGETR_'..stack,{kind='cget_range',stack=stack})
  symbolic('CSET0_'..stack,{kind='cset',stack=stack,depth=0})
  symbolic('CSETN_'..stack,{kind='cset',stack=stack,depth='immediate'})
end
symbolic('CPUSHN',{kind='cpushn'})
symbolic('CPOP',{kind='cpop'})
for _,from in ipairs{'A','B'} do for _,to in ipairs{'A','B'} do if from~=to then
  symbolic('COPY_'..from..to,{kind='transfer',from=from,to=to,consume=false})
  symbolic('MOVE_'..from..to,{kind='transfer',from=from,to=to,consume=true})
end end end
for _,name in ipairs(M.binary_order) do
  symbolic(name..'_A',{kind='binary',operation=name,destination='A'})
  symbolic(name..'_B',{kind='binary',operation=name,destination='B'})
end
for _,name in ipairs(M.unary_order) do
  symbolic(name..'_A',{kind='unary',operation=name,stack='A'})
  symbolic(name..'_B',{kind='unary',operation=name,stack='B'})
end
for _,name in ipairs(M.float_binary_order) do
  symbolic(name..'_A',{kind='float_binary',operation=name,destination='A'})
  symbolic(name..'_B',{kind='float_binary',operation=name,destination='B'})
end
for _,name in ipairs(M.float_unary_order) do symbolic(name,{kind='float_unary',operation=name}) end
for _,name in ipairs(M.immediate_order) do
  symbolic(name..'I_A',{kind='immediate',operation=name,stack='A'})
  symbolic(name..'I_B',{kind='immediate',operation=name,stack='B'})
end
for _,name in ipairs(M.c_operand_order) do
  symbolic(name..'C_A',{kind='c_operand',operation=name,stack='A'})
  symbolic(name..'C_B',{kind='c_operand',operation=name,stack='B'})
end
symbolic('ZX8',{kind='mask',immediate=255})
symbolic('ZX16',{kind='mask',immediate=65535})
symbolic('POW',{kind='pow'})
symbolic('POWS',{kind='pow'})
for _,name in ipairs(M.check_order) do symbolic(name,{kind='check'}) end
symbolic('JMP',{kind='jump',width=16})
symbolic('JMP32',{kind='jump',width=32})
for _,stack in ipairs{'A','B'} do
  symbolic('JZ_'..stack,{kind='zero_branch',stack=stack,relation=0})
  symbolic('JNZ_'..stack,{kind='zero_branch',stack=stack,relation=1})
end
for relation,name in ipairs(M.branch_order) do symbolic(name,{kind='branch',relation=relation-1}) end
local float_branch_relation={FBLT=2,FBLE=3,FBEQ=0}
for _,name in ipairs(M.float_branch_order) do symbolic(name,{kind='float_branch',relation=float_branch_relation[name]}) end
local immediate_branches={
  BEQI={0,false},BNEI={1,false},BLTI={2,false},BLEI={3,false},
  BGTI={2,true},BGEI={3,true},BLTUI={4,false},BLEUI={5,false},BGTUI={4,true},BGEUI={5,true},
}
for name,fact in pairs(immediate_branches) do symbolic(name,{kind='immediate_branch',relation=fact[1],reverse=fact[2]}) end
symbolic('ABORT',{kind='abort'})
symbolic('SWITCH',{kind='switch'})
symbolic('HALT',{kind='halt'})

function M.expr(expression,x,y)
  assert(expression, 'missing instruction expression')
  local out=expression:gsub('%f[%a]x%f[%A]',function() return x end)
  if y then out=out:gsub('%f[%a]y%f[%A]',function() return y end) end
  return out
end
return M

