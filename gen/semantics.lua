-- Shared scalar expressions and bank-independent instruction transfers.
-- x always means the selected-stack operand; y means the other operand.
local M={}
M.binary={
 ADD='x+y',SUB='x-y',MUL='x*y',AND='x&y',OR='x|y',XOR='x^y',
 SHL='(y>=64 ? 0 : x<<y)',SHR='(y>=64 ? 0 : x>>y)',SAR='vm_sar(x,y)',
 EQ='x==y',NE='x!=y',LT='abc_signed(x)<abc_signed(y)',LE='abc_signed(x)<=abc_signed(y)',
 LTU='x<y',LEU='x<=y',DIVU='x/y',REMU='x%y',
 DIVS='(y==UINT64_MAX ? 0-x : (uint64_t)(abc_signed(x)/abc_signed(y)))',
 REMS='(y==UINT64_MAX ? 0 : (uint64_t)(abc_signed(x)%abc_signed(y)))',
}
M.binary_order={'ADD','SUB','MUL','DIVU','DIVS','REMU','REMS','AND','OR','XOR','SHL','SHR','SAR','EQ','NE','LT','LE','LTU','LEU'}
M.unary_order={'NEG','NOT','LNOT','ZX32','SX32','ZX8','ZX16'}
M.immediate_order={'ADD','SUB','MUL','AND','OR','XOR','SHL','SHR','SAR'}
M.c_operand_order={'ADD','SUB','MUL','XOR'}
M.check_order={'CHKU8','CHKU16','CHKU32','CHKI32','CHKNN'}
M.branch_order={'BEQ','BNE','BLT','BLE','BLTU','BLEU'}
M.immediate_branch_order={'BEQI','BNEI','BLTI','BLEI','BGTI','BGEI','BLTUI','BLEUI','BGTUI','BGEUI'}
M.float_binary_order={'FADD','FSUB','FMUL','FDIV','FLT','FLE','FEQ'}
M.float_unary_order={'FNEG','I2FS','I2FU','F2IS','F2IU'}
-- Cell kind + 1 (zero is unspecified): integer=1, float=3. Raw identity,
-- not a numeric conversion or a memory/placement effect.
M.bitcast_order={'F2BITS','BITS2F'}
M.bitcasts={F2BITS={input_kind=3,result_kind=1},BITS2F={input_kind=1,result_kind=3}}
M.float_branch_order={'FBLT','FBLE','FBEQ'}
M.float_binary={FADD='vm_fadd(x,y)',FSUB='vm_fsub(x,y)',FMUL='vm_fmul(x,y)',FDIV='vm_fdiv(x,y)',FLT='vm_flt(x,y)',FLE='vm_fle(x,y)',FEQ='vm_feq(x,y)'}
M.float_branches={FBLT='vm_flt(x,y)',FBLE='vm_fle(x,y)',FBEQ='vm_feq(x,y)'}
M.unary={NEG='0-x',NOT='~x',LNOT='x^1',ZX8='x&255',ZX16='x&65535',ZX32='x&UINT32_MAX',SX32='(uint64_t)(int64_t)abc_i32_from_u64(x)',F2BITS='x',BITS2F='x'}
M.checks={CHKU8='x>255',CHKU16='x>65535',CHKU32='x>UINT32_MAX',CHKI32='abc_signed(x)<INT32_MIN || abc_signed(x)>INT32_MAX',CHKNN='x>>63'}
M.comparisons={BEQ='x==y',BNE='x!=y',BLT='abc_signed(x)<abc_signed(y)',BLE='abc_signed(x)<=abc_signed(y)',BLTU='x<y',BLEU='x<=y',BGT='abc_signed(x)>abc_signed(y)',BGE='abc_signed(x)>=abc_signed(y)',BGTU='x>y',BGEU='x>=y'}

-- One transfer definition per semantic family; bindings supply me/other.
M.transfers={}
local function transfer(name,kind,fields)
 assert(not M.transfers[name],name)
 local definition=fields or {};definition.kind=kind;M.transfers[name]=definition
end
for _,width in ipairs{8,32,64} do transfer('PUSH'..width,'push',{width=width}) end
for _,name in ipairs{'DUP','DROP','COPY','MOVE','CPUSH','CPUSHN','CPOP','CGETR','CALL','TCALL','RET','CALLI','TCALLI','FCALL','HALT','ABORT','SWITCH','EXT'} do transfer(name,name:lower()) end
transfer('CGET0','cget',{depth=0});transfer('CGET1','cget',{depth=1});transfer('CGETN','cget')
transfer('CSET0','cset',{depth=0});transfer('CSETN','cset')
for _,name in ipairs(M.binary_order) do transfer(name,'binary',{operation=name,check_zero=name:match('^DIV')~=nil or name:match('^REM')~=nil}) end
for _,name in ipairs(M.float_binary_order) do transfer(name,'float_binary',{operation=name}) end
for _,name in ipairs(M.unary_order) do transfer(name,'unary',{operation=name}) end
for _,name in ipairs(M.bitcast_order) do
 local cast=M.bitcasts[name]
 transfer(name,'unary',{operation=name,input_kind=cast.input_kind,result_kind=cast.result_kind})
end
for _,name in ipairs(M.float_unary_order) do transfer(name,'float_unary',{operation=name}) end
for _,name in ipairs(M.immediate_order) do transfer(name..'I','immediate',{operation=name}) end
for _,name in ipairs(M.c_operand_order) do transfer(name..'C','c_operand',{operation=name}) end
for _,name in ipairs(M.check_order) do transfer(name,'check',{operation=name}) end
transfer('POW','power',{signed_exponent=false});transfer('POWS','power',{signed_exponent=true})
transfer('JMP','jump',{width=16});transfer('JMP32','jump',{width=32})
transfer('JZ','zero_branch',{zero=true});transfer('JNZ','zero_branch',{zero=false})
for _,name in ipairs(M.branch_order) do transfer(name,'branch',{operation=name}) end
for _,name in ipairs(M.float_branch_order) do transfer(name,'float_branch',{operation=name}) end
for _,name in ipairs(M.immediate_branch_order) do transfer(name,'immediate_branch',{operation=name:sub(1,-2)}) end
transfer('CALLOC','allocate');transfer('CFREE','free')
for _,base in ipairs{'F','G',''} do
 for _,width in ipairs{'8','16','32','32S','64'} do transfer(base..'LD'..width,'memory') end
 for _,width in ipairs{'8','16','32','64'} do transfer(base..'ST'..width,'memory') end
end
transfer('FADDR','memory');transfer('GADDR','memory')
for _,width in ipairs{'8','16','32','32S','64'} do transfer('LDX'..width,'memory') end
transfer('IDX','memory');transfer('MEMCPY','memory')

function M.expr(expression,x,y)
 assert(expression,'missing instruction expression')
 local result=expression:gsub('%f[%a]x%f[%A]',function() return x end)
 if y then result=result:gsub('%f[%a]y%f[%A]',function() return y end) end
 return result
end
return M
