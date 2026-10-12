-- The interpreter opcodes with cache-state-specific handlers.
local set = {}
local function add(name) assert(not set[name], 'duplicate banked opcode ' .. name); set[name] = true end
for _,X in ipairs({'A','B'}) do
  for _,width in ipairs({8,32,64}) do add('PUSH'..width..'_'..X) end
  for _,name in ipairs({'DUP','DROP','CPUSH','CGET0','CGET1','CGETN','CGETR','CSET0','CSETN','JZ','JNZ'}) do add(name..'_'..X) end
  for _,name in ipairs({'NEG','NOT','LNOT','ZX32','SX32'}) do add(name..'_'..X) end
  for _,name in ipairs({'FADD','FSUB','FMUL','FDIV','FLT','FLE','FEQ'}) do add(name..'_'..X) end
  for _,name in ipairs({'ADD','SUB','MUL','DIVU','DIVS','REMU','REMS','AND','OR','XOR',
                         'SHL','SHR','SAR','EQ','NE','LT','LE','LTU','LEU'}) do add(name..'_'..X) end
  for _,name in ipairs({'ADD','SUB','MUL','AND','OR','XOR','SHL','SHR','SAR'}) do add(name..'I_'..X) end
  for _,name in ipairs({'ADD','SUB','MUL','XOR'}) do add(name..'C_'..X) end
end
for _,name in ipairs({'COPY_AB','COPY_BA','MOVE_AB','MOVE_BA','CPUSHN','CPOP','ZX8','ZX16',
                     'POW','POWS','CHKU8','CHKU16','CHKU32','CHKI32','CHKNN',
                     'JMP','JMP32','SWITCH','BEQ','BNE','BLT','BLE','BLTU','BLEU','FBLT','FBLE','FBEQ',
                     'FNEG','I2FS','I2FU','F2IS','F2IU',
                     'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'}) do add(name) end
for _,X in ipairs({'A','B'}) do
  add('CALL_'..X)
  for n=0,2 do add('CALL_'..X..'_'..n) end
end
add('TCALL'); add('RET'); add('HALT'); add('ABORT')
for k=0,2 do
  for n=0,2 do add('TCALL_'..k..'_'..n) end
  for r=0,2 do add('RET_'..k..'_'..r) end
end
return set

