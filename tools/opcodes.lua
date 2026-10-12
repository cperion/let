-- Revision-6 public ISA. Semantic identity is independent of serialized opcode.
local M = {revision=6, ops={}, ext_ops={}, operations={}, layouts={}}
M.kind_order={'NORMAL','BRANCH','CALL','RET','HALT','ABORT','OPI','OPC','BRI','TCALL','MEMORY','ICALL','ITCALL','EXT','FCALL','JMP32','SWITCH'}
M.kind={}
for index,name in ipairs(M.kind_order) do M.kind[name]=index-1 end
M.layout_order={'NONE','I8','I32','U64','U8','U8_U8','I16','SWITCH','I32_U8','I32_U8_U8','U16','U32','I8_I16','EXT'}
local operand_bytes={NONE=0,I8=1,I32=4,U64=8,U8=1,U8_U8=2,I16=2,SWITCH=2,I32_U8=5,I32_U8_U8=6,U16=2,U32=4,I8_I16=3,EXT=1}
for index,name in ipairs(M.layout_order) do M.layouts[name]=index-1 end
M.memory_action_order={'NONE','ALLOC','FREE','FLOAD','FSTORE','FADDR','GLOAD','GSTORE','GADDR','PLOAD','PSTORE','XLOAD','INDEX','COPY'}
M.memory_action={}
for index,name in ipairs(M.memory_action_order) do M.memory_action[name]=index-1 end
M.stack={A=0,B=1,NONE=2}
M.stack_role_order={'NONE','RESULT','UNARY','BINARY','SOURCE','ADDRESS','CONDITION','ARGUMENT_RESULT','ARGUMENT','RETURN_SOURCE','PREFIX'}
M.stack_role={}
for index,name in ipairs(M.stack_role_order) do M.stack_role[name]=index-1 end
local operation_indices={}
local function operation_index(name)
    if operation_indices[name]==nil then
        operation_indices[name]=#M.operations
        M.operations[#M.operations+1]=name
    end
    return operation_indices[name]
end
local function descriptor(name,layout,kind,profile,role,stack,memory,prefix_bytes)
    return {name=name,operation=operation_index(name),layout=M.layouts[layout],
        layout_name=layout,kind=M.kind[kind or 'NORMAL'],profile=profile or 1,
        role=M.stack_role[role or 'NONE'],stack=stack,len=prefix_bytes+operand_bytes[layout],mem=memory}
end
local function pair(name,layout,kind,profile,role,memory)
    assert(#M.ops%2==0,'selected pairs must begin on an even byte')
    for _,stack in ipairs{'A','B'} do
        local instruction=descriptor(name,layout or 'NONE',kind,profile,role,M.stack[stack],memory,1)
        instruction.name=name..'_'..stack
        instruction.opcode=#M.ops
        M.ops[#M.ops+1]=instruction
    end
end
local function neutral(name,layout,kind,profile,memory)
    local instruction=descriptor(name,layout,kind,profile,'NONE',M.stack.NONE,memory,1)
    instruction.opcode=#M.ops
    M.ops[#M.ops+1]=instruction
end
local function extended(name,layout,kind,role)
    -- The prefix supplies the selected stack; no duplicate selector per bank.
    local instruction=descriptor(name,layout,kind,1,role,M.stack.NONE,nil,2)
    instruction.selector=#M.ext_ops
    M.ext_ops[#M.ext_ops+1]=instruction
end
local function memory(action,width,sign)
    return {action=M.memory_action[action],width=width or 0,sign=sign or 0}
end
pair('HALT','NONE','HALT',1,'RETURN_SOURCE')
for _,width in ipairs{8,32,64} do pair('PUSH'..width,({[8]='I8',[32]='I32',[64]='U64'})[width],nil,1,'RESULT') end
pair('DUP','NONE',nil,1,'UNARY')
pair('DROP','NONE',nil,1,'SOURCE')
pair('COPY','NONE',nil,1,'SOURCE')
pair('MOVE','NONE',nil,1,'SOURCE')
pair('CPUSH','NONE',nil,1,'SOURCE')
pair('CPUSHN','U8',nil,1,'SOURCE')
pair('CGET0','NONE',nil,1,'RESULT')
pair('CGET1','NONE',nil,1,'RESULT')
pair('CGETN','U8',nil,1,'RESULT')
pair('CGETR','U8_U8',nil,1,'RESULT')
pair('CSET0','NONE',nil,1,'SOURCE')
pair('CSETN','U8',nil,1,'SOURCE')
for _,name in ipairs{'ADD','SUB','MUL','DIVU','DIVS','REMU','REMS','AND','OR','XOR','SHL','SHR','SAR','EQ','NE','LT','LE','LTU','LEU'} do pair(name,'NONE',nil,1,'BINARY') end
for _,name in ipairs{'NEG','NOT','LNOT','ZX32','SX32','ZX8','ZX16'} do pair(name,'NONE',nil,1,'UNARY') end
for _,name in ipairs{'POW','POWS'} do pair(name,'NONE',nil,1,'BINARY') end
for _,name in ipairs{'CHKU8','CHKU16','CHKU32','CHKI32','CHKNN'} do pair(name,'NONE',nil,1,'UNARY') end
pair('SWITCH','SWITCH','SWITCH',1,'CONDITION')
for _,name in ipairs{'JZ','JNZ','BEQ','BNE','BLT','BLE','BLTU','BLEU'} do pair(name,'I16','BRANCH',1,'CONDITION') end
for _,name in ipairs{'ADD','SUB','MUL','AND','OR','XOR','SHL','SHR','SAR'} do pair(name..'I','I8','OPI',1,'UNARY') end
pair('CALL','I32_U8','CALL',1,'ARGUMENT_RESULT')
pair('TCALL','I32_U8_U8','TCALL',1,'ARGUMENT')
pair('RET','U8_U8','RET',1,'RETURN_SOURCE')
local loads={{'8',1,0},{'16',2,0},{'32',4,0},{'32S',4,1},{'64',8,0}}
local stores={{'8',1},{'16',2},{'32',4},{'64',8}}
for _,base in ipairs{{'F','U16','FLOAD','FSTORE','FADDR'},{'G','U32','GLOAD','GSTORE','GADDR'}} do
    for _,width in ipairs(loads) do pair(base[1]..'LD'..width[1],base[2],'MEMORY',2,'RESULT',memory(base[3],width[2],width[3])) end
    for _,width in ipairs(stores) do pair(base[1]..'ST'..width[1],base[2],'MEMORY',2,'SOURCE',memory(base[4],width[2])) end
    pair(base[1]..'ADDR',base[2],'MEMORY',2,'RESULT',memory(base[5]))
end
for _,width in ipairs(loads) do pair('LD'..width[1],'U16','MEMORY',2,'ADDRESS',memory('PLOAD',width[2],width[3])) end
for _,width in ipairs(stores) do pair('ST'..width[1],'U16','MEMORY',2,'ADDRESS',memory('PSTORE',width[2])) end
for _,width in ipairs(loads) do pair('LDX'..width[1],'NONE','MEMORY',2,'ADDRESS',memory('XLOAD',width[2],width[3])) end
pair('IDX','U16','MEMORY',2,'ADDRESS',memory('INDEX'))
pair('MEMCPY','U32','MEMORY',2,'ADDRESS',memory('COPY'))
pair('CALLI','U8','ICALL',3,'ARGUMENT_RESULT')
pair('TCALLI','U8_U8','ITCALL',3,'ARGUMENT')
pair('FCALL','U16','FCALL',4,'ARGUMENT_RESULT')
for _,name in ipairs{'FADD','FSUB','FMUL','FDIV','FLT','FLE','FEQ'} do pair(name,'NONE',nil,2,'BINARY') end
for _,name in ipairs{'FNEG','I2FS','I2FU','F2IS','F2IU'} do pair(name,'NONE',nil,2,'UNARY') end
for _,name in ipairs{'FBLT','FBLE','FBEQ'} do pair(name,'I16','BRANCH',2,'CONDITION') end
assert(#M.ops==0xf8,'ordinary core allocation disagrees with revision 6')
pair('EXT','EXT','EXT',1,'PREFIX')
neutral('CPOP','NONE')
neutral('CALLOC','U16','MEMORY',2,memory('ALLOC'))
neutral('CFREE','U16','MEMORY',2,memory('FREE'))
neutral('JMP','I16','BRANCH')
neutral('JMP32','I32','JMP32')
neutral('ABORT','U8','ABORT')
for _,name in ipairs{'ADDC','SUBC','MULC','XORC'} do extended(name,'U8','OPC','UNARY') end
for _,name in ipairs{'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'} do extended(name,'I8_I16','BRI','CONDITION') end
assert(#M.ops==256 and #M.ext_ops==14 and #M.operations==145,'incomplete revision-6 manifest')
return M
