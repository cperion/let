-- Verified ABC isolates runtime type costs from frontend/build-time optimization.
local bit=require('bit')
local M={}
M.cases={
  {name='u32-known',n=1000000,known=true},
  {name='u32-carried',n=1000000},
  {name='u32-checked',n=1000000,checked=true},
  {name='u32-unproven',n=1000000,unproven=true},
  {name='u32-reload',n=1000000,reload=true},
  {name='width-alternate',n=1000000,alternate=true},
  {name='f64-carried',n=1000000,float=true},
}
function M.expected(b,n)
  if b.float then return n+2 end
  local x=12345
  for i=0,n-1 do x=(bit.bxor(x,math.floor(x/128))*5+i)%65536 end
  return x
end
function M.assembly(b,n,dynamic)
  local lines={dynamic and '.profile dynamic' or '.profile memory'}
  local function emit(s) lines[#lines+1]=s end
  if dynamic then emit([=[.descriptor primitive U u32
.descriptor primitive H u16
.descriptor primitive F f64
.descriptor primitive D any
.gcroot 0 D]=]) end
  emit('.datazero 8\n.function main 0 1 - i')
  emit(b.float and ' PUSH.A 1\n I2FU' or ' PUSH.A 12345')
  if dynamic then emit(' ANY_BOX '..(b.float and 'F' or 'U')) end
  -- Initial load deliberately loses static value/type information. Alternate
  -- keeps x unboxed between iterations and changes the boxed tag at one site.
  if not b.known then
    emit(' GST64 0\n .loadkind '..(dynamic and 'any' or b.float and 'float' or 'int')..'\n GLD64 0')
  end
  if dynamic and b.alternate then emit(' ANY_CAST U') end
  emit(' CPUSH.A')
  emit(' PUSH.A 0\n CPUSH.A\nloop:\n CGET.A 0\n PUSH.B '..n..'\n BLTU body')
  emit(' CGET.A 1')
  if dynamic and not b.alternate then emit(' ANY_CAST '..(b.float and 'F' or 'U')) end
  if b.float then emit(' DUP.A\n MOVE.AB\n FADD.A\n F2IU') end
  emit(' RET 2 1\nbody:')
  if b.checked then
    if dynamic then emit(' CGET.A 1\n ANY_IS U\n JZ.A bad') end
  end
  if b.reload then
    emit(' CGET.A 1\n GST64 0\n .loadkind '..(dynamic and 'any' or 'int')..'\n GLD64 0\n CSET.A 1')
  end
  if b.alternate then
    emit(' CGET.A 0\n PUSH.B 1\n AND.A\n JZ.A narrow\n CGET.A 1')
    if dynamic then emit(' ANY_BOX U') end
    emit(' JMP store\nnarrow:\n CGET.A 1')
    if dynamic then emit(' ANY_BOX H') end
    emit('store:\n GST64 0\n .loadkind '..(dynamic and 'any' or 'int')..'\n GLD64 0')
  else emit(' CGET.A 1') end
  if b.float then
    -- x += 0.5, exactly representable; return 2*x as an integer checksum.
    emit(' PUSH.A 1\n I2FU\n PUSH.A 2\n I2FU\n MOVE.AB\n FDIV.A')
    if dynamic then emit(' ANY_BOX F\n DADD')
    else emit(' MOVE.AB\n FADD.A') end
  elseif dynamic then
    emit(' DUP.A\n PUSH.A 7\n ANY_BOX U\n DSHR\n DXOR\n PUSH.A 5\n ANY_BOX U\n DMUL\n CGET.A 0')
    if not b.unproven then emit(' ZX32.A') end
    emit(' ANY_BOX U\n DADD\n PUSH.A 65535\n ANY_BOX U\n DAND')
    if b.alternate then emit(' ANY_CAST U') end
  else
    emit(' DUP.A\n PUSH.B 7\n SHR.A\n MOVE.AB\n XOR.A\n MULI.A 5\n CGET.A 0')
    if not b.unproven then emit(' ZX32.A') end
    emit(' MOVE.AB\n ADD.A\n PUSH.B 65535\n AND.A')
  end
  emit(' CSET.A 1\n CGET.A 0\n ADDI.A 1\n CSET.A 0\n JMP loop')
  if dynamic and b.checked then emit('bad:\n ABORT 6') end
  emit('.export main')
  return table.concat(lines,'\n')..'\n'
end
return M
