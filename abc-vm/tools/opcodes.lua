-- Spec-owned opcode manifest for the public ABC runtime/toolchain.
-- Do not import vm/gen.lua here: vm/ is an experimental/optimized implementation track.
local M={}
M.kind={NORMAL=0,BRANCH=1,CALL=2,RET=3,HALT=4,ABORT=5,OPI=6,OPC=7,BRI=8,TCALL=9,INTERNAL=10,MEMORY=11,ICALL=12,ITCALL=13,EXT=14,FCALL=15,JMP32=16,SWITCH=17}
M.memory_action={NONE=0,ALLOC=1,FREE=2,FLOAD=3,FSTORE=4,FADDR=5,GLOAD=6,GSTORE=7,GADDR=8,PLOAD=9,PSTORE=10,XLOAD=11,INDEX=12,COPY=13}
local ops={}
local function op(name,len,kind,mem)
  ops[#ops+1]={name=name,len=len,kind=kind or M.kind.NORMAL,mem=mem}
end
op('HALT',1,M.kind.HALT)
for _,X in ipairs{'A','B'} do op('PUSH8_'..X,2); op('PUSH32_'..X,5); op('PUSH64_'..X,9) end
for _,X in ipairs{'A','B'} do op('DUP_'..X,1); op('DROP_'..X,1) end
for _,n in ipairs{'COPY_AB','COPY_BA','MOVE_AB','MOVE_BA'} do op(n,1) end
op('CPUSH_A',1); op('CPUSH_B',1); op('CPUSHN',2); op('CPOP',1)
for _,X in ipairs{'A','B'} do
  op('CGET0_'..X,1); op('CGET1_'..X,1); op('CGETN_'..X,2); op('CGETR_'..X,3)
  op('CSET0_'..X,1); op('CSETN_'..X,2)
end
for _,n in ipairs{'ADD','SUB','MUL','DIVU','DIVS','REMU','REMS','AND','OR','XOR','SHL','SHR','SAR','EQ','NE','LT','LE','LTU','LEU'} do op(n..'_A',1); op(n..'_B',1) end
for _,n in ipairs{'NEG','NOT','LNOT','ZX32','SX32'} do op(n..'_A',1); op(n..'_B',1) end
for _,n in ipairs{'ZX8','ZX16','POW','POWS','CHKU8','CHKU16','CHKU32','CHKI32','CHKNN'} do op(n,1) end
op('JMP',3,M.kind.BRANCH); op('JMP32',5,M.kind.JMP32); op('SWITCH',3,M.kind.SWITCH); for _,X in ipairs{'A','B'} do op('JZ_'..X,3,M.kind.BRANCH); op('JNZ_'..X,3,M.kind.BRANCH) end
for _,n in ipairs{'BEQ','BNE','BLT','BLE','BLTU','BLEU'} do op(n,3,M.kind.BRANCH) end
for _,n in ipairs{'ADD','SUB','MUL','AND','OR','XOR','SHL','SHR','SAR'} do op(n..'I_A',2,M.kind.OPI); op(n..'I_B',2,M.kind.OPI) end
for _,n in ipairs{'ADD','SUB','MUL','XOR'} do op(n..'C_A',2,M.kind.OPC); op(n..'C_B',2,M.kind.OPC) end
for _,n in ipairs{'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'} do op(n,4,M.kind.BRI) end
op('CALL_A',6,M.kind.CALL); op('CALL_B',6,M.kind.CALL); op('TCALL',7,M.kind.TCALL); op('RET',3,M.kind.RET); op('ABORT',2,M.kind.ABORT)
-- EXT reserves a core byte for the extended selector table. No extended selectors
-- are assigned yet, so verification rejects every selector deterministically.
op('EXT',2,M.kind.EXT)
for _,X in ipairs{'A','B'} do for n=0,2 do op(('CALL_%s_%d'):format(X,n),6,M.kind.INTERNAL) end end
for k=0,2 do for n=0,2 do op(('TCALL_%d_%d'):format(k,n),7,M.kind.INTERNAL) end end
for k=0,2 do for r=0,2 do op(('RET_%d_%d'):format(k,r),3,M.kind.INTERNAL) end end
M.legacy_count=#ops
local function mem(action,width,to_b,sign) return {action=action,width=width or 0,to_b=to_b or 0,sign=sign or 0} end
op('CALLOC',3,M.kind.MEMORY,mem(M.memory_action.ALLOC)); op('CFREE',3,M.kind.MEMORY,mem(M.memory_action.FREE))
local loads={{'8',1,0},{'16',2,0},{'32',4,0},{'32S',4,1},{'64',8,0}}
local stores={{'8',1},{'16',2},{'32',4},{'64',8}}
for _,v in ipairs(loads) do for _,X in ipairs{'A','B'} do op('FLD'..v[1]..'_'..X,3,M.kind.MEMORY,mem(M.memory_action.FLOAD,v[2],X=='B' and 1 or 0,v[3])) end end
for _,v in ipairs(stores) do for _,X in ipairs{'A','B'} do op('FST'..v[1]..'_'..X,3,M.kind.MEMORY,mem(M.memory_action.FSTORE,v[2],X=='B' and 1 or 0)) end end
for _,X in ipairs{'A','B'} do op('FADDR_'..X,3,M.kind.MEMORY,mem(M.memory_action.FADDR,0,X=='B' and 1 or 0)) end
for _,v in ipairs(loads) do op('GLD'..v[1],5,M.kind.MEMORY,mem(M.memory_action.GLOAD,v[2],0,v[3])) end
for _,v in ipairs(stores) do op('GST'..v[1],5,M.kind.MEMORY,mem(M.memory_action.GSTORE,v[2])) end
for _,X in ipairs{'A','B'} do op('GADDR_'..X,5,M.kind.MEMORY,mem(M.memory_action.GADDR,0,X=='B' and 1 or 0)) end
for _,v in ipairs(loads) do for _,X in ipairs{'A','B'} do op('LD'..v[1]..'_'..X,3,M.kind.MEMORY,mem(M.memory_action.PLOAD,v[2],X=='B' and 1 or 0,v[3])) end end
for _,v in ipairs(stores) do op('ST'..v[1],3,M.kind.MEMORY,mem(M.memory_action.PSTORE,v[2])) end
for _,v in ipairs(loads) do op('LDX'..v[1],1,M.kind.MEMORY,mem(M.memory_action.XLOAD,v[2],0,v[3])) end
op('IDX',3,M.kind.MEMORY,mem(M.memory_action.INDEX)); op('MEMCPY',5,M.kind.MEMORY,mem(M.memory_action.COPY))
op('CALLI_A',6,M.kind.ICALL); op('CALLI_B',6,M.kind.ICALL); op('TCALLI',7,M.kind.ITCALL)
op('CALLI_MONO_A',6,M.kind.INTERNAL); op('CALLI_MONO_B',6,M.kind.INTERNAL); op('TCALLI_MONO',7,M.kind.INTERNAL)
op('CALLI_FINAL_A',6,M.kind.INTERNAL); op('CALLI_FINAL_B',6,M.kind.INTERNAL); op('TCALLI_FINAL',7,M.kind.INTERNAL)
op('FCALL',3,M.kind.FCALL)
for _,n in ipairs{'FADD','FSUB','FMUL','FDIV','FLT','FLE','FEQ'} do op(n..'_A',1); op(n..'_B',1) end
for _,n in ipairs{'FNEG','I2FS','I2FU','F2IS','F2IU'} do op(n,1) end
for _,n in ipairs{'FBLT','FBLE','FBEQ'} do op(n,3,M.kind.BRANCH) end
-- Profile-5 public EXT selectors. Length includes EXT and selector bytes.
-- Stack effects and descriptor-dependent layout checks are consumed by the verifier.
local ext_ops={}
local function ext(name,len,family) ext_ops[#ext_ops+1]={name=name,len=len,family=family} end
for _,n in ipairs{'ANY_BOX','ANY_CAST','ANY_IS'} do ext(n,6,'descriptor') end
for _,n in ipairs{'DNEG','DNOT','DLNOT'} do ext(n,2,'unary') end
for _,n in ipairs{'DADD','DSUB','DMUL','DDIV','DREM','DPOW','DSHL','DSHR','DSAR','DAND','DOR','DXOR'} do ext(n,2,'binary') end
for _,n in ipairs{'DADDL','DSUBL','DMULL','DDIVL','DREML','DPOWL','DSHLL','DSHRL','DSARL','DANDL','DORL','DXORL'} do ext(n,7,'literal') end
for _,n in ipairs{'DEQ','DNE','DLT','DLE'} do ext(n,2,'compare') end
ext('DREQUIRE_BOOL',2,'condition')
ext('DCALL',9,'call'); ext('DTCALL',9,'tailcall')
ext('WORD_NEW',6,'word-new')
for _,n in ipairs{'WORD_GET','WORD_SET','WORD_HAS','WORD_REMOVE','WORD_COUNT','WORD_KEY','WORD_SUPPLY','WORD_METHOD','WORD_FREEZE'} do ext(n,2,'word') end
ext('STRING_CAT',2,'string'); ext('STRING_TEXT',2,'string')
ext('WORD_DIRECT',10,'callable'); ext('CLOSURE_NEW',10,'closure')
ext('MANAGED_NEW',6,'descriptor'); ext('MANAGED_COPY',6,'descriptor')
M.ext_ops=ext_ops
M.ops=ops
return M
