-- Approved revision-7 metadata boundary; this does not execute lifecycle code.
package.path='tools/?.lua;frontend/?.lua;'..package.path
local assembler,util,int=require('assembler'),require('tool_util'),require('int64')
local ffi=require('let.abi')
local optimizer=require('let.optimize')
local runtime=ffi.load('build/libabc.so')
local tool=ffi.load('build/libabc-opt.so')
local directory=arg[1] or 'build/c-entry-tests'
assert(os.execute('mkdir -p '..util.quote(directory))==0)
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local function u32(s,p) local a,b,c,d=s:byte(p,p+3);return a+b*256+c*65536+d*16777216 end
local function put(s,p,n,width) width=width or 4;return s:sub(1,p-1)..int.pack(n,width)..s:sub(p+width) end
local function sections(bytes)
 local result,order={},{};local p=17
 for _=1,u32(bytes,9) do
  local tag,n=u32(bytes,p),u32(bytes,p+4);p=p+8
  result[tag]=bytes:sub(p,p+n-1);order[#order+1]=tag;p=p+n
 end
 assert(p==#bytes+1);return result,order
end
local function rebuild(bytes,replacements,order)
 local parts,original=sections(bytes);order=order or original
 for tag,payload in pairs(replacements or {}) do parts[tag]=payload end
 local result={put(bytes:sub(1,16),9,#order)}
 for _,tag in ipairs(order) do local p=assert(parts[tag]);result[#result+1]=int.pack(tag,4)..int.pack(#p,4)..p end
 return table.concat(result)
end
local function load(bytes,why)
 for _,lib in ipairs{runtime,tool} do
  local out,e=ffi.new('abc_module *[1]',ffi.cast('abc_module *',1)),ffi.new('abc_error[1]')
  local status=lib.abc_module_load(bytes,#bytes,out,e)
  local message=ffi.string(e[0].message)
  if status==0 then lib.abc_module_free(out[0]) end
  if why then
   check(status==1 and out[0]==nil and message:find(why,1,true),why..': '..message)
  else check(status==0,'valid module rejected: '..message) end
 end
 if why then
  local out,n,e=ffi.new('void *[1]',ffi.cast('void *',1)),ffi.new('size_t[1]',123),ffi.new('abc_error[1]')
  check(tool.abc_optimize(bytes,#bytes,out,n,e)==1 and out[0]==nil and n[0]==0,'invalid optimizer input published output')
 end
end
local source=[[
.profile foreign
.datazero 32
.rodata 0000000000000000
.codeaddr 0 ordinary
; Deliberately unordered declarations; the encoded table is ordered.
.centry 24 drop
.centry 8 drop
.centry 16 drop_other
.signature invoke_sig 2 0 aa -
.function unused_first 0 1 - i
 PUSH.A 13
 RET.A 0 1
.function main 0 1 - i
 PUSH.A 20
 PUSH.B 22
 ADD.A
 RET.A 0 1
.function drop 2 0 aa -
 CGET.A 1
 .loadkind addr
 LD64.A 0
 DROP.A
 RET.A 2 0
.function unused_middle 0 1 - i
 PUSH.A 14
 RET.A 0 1
.function ordinary 2 0 aa -
 RET.B 2 0
.function invoke 3 0 aaa -
 CGET.A 0
 CGET.A 1
 CGET.B 2
 CALLI.A 2 invoke_sig
 RET.A 3 0
.function drop_other 2 0 aa -
 CALL.B helper 0
 RET.B 2 0
.function data_identity 0 1 - a
 .loadkind addr
 GLD64.A 8
 RET.A 0 1
.function helper 0 0 - -
 RET.A 0 0
.export main
.export invoke
.export data_identity
]]
util.write(directory..'/entries.abcasm',source)
local bytes=assembler.assemble(source)
local parts=sections(bytes)
check(bytes:byte(5)==7 and bytes:byte(6)==0 and bytes:byte(8)==4 and u32(bytes,9)==10,'revision/profile/section count')
check(u32(parts[10],1)==3 and #parts[10]==28,'C-entry record count/extent')
check(u32(parts[10],5)==8 and u32(parts[10],9)==2 and u32(parts[10],13)==16 and u32(parts[10],17)==6 and u32(parts[10],21)==24 and u32(parts[10],25)==2,'ordered C-entry destinations and alias target')
load(bytes)
util.write(directory..'/entries.abc',bytes)
local ordinary_source=source:gsub('%.centry [^\n]+\n','')
util.write(directory..'/ordinary.abcasm',ordinary_source)
local ordinary=assembler.assemble(ordinary_source)
check(ordinary:byte(5)==6 and u32(ordinary,9)==9,'ordinary assembly changed revision')
check(sections(ordinary)[2]==parts[2],'C-entry metadata changed instruction bytes')
load(ordinary)
util.write(directory..'/ordinary.abc',ordinary)
local reversed={10,9,8,7,6,5,4,3,2,1}
load(rebuild(bytes,nil,reversed))
-- Section 10 may be empty; it creates no C-entry roles.
local empty=rebuild(bytes,{[10]=int.pack(0,4)})
load(empty);util.write(directory..'/empty.abc',empty)
for _,revision in ipairs{0,5,8,65535} do load(put(bytes,5,revision,2),'expected ABC2 revision') end
for profile=1,3 do load(put(bytes,8,profile,1),'requires profile 4') end
load(put(bytes,5,6,2),'invalid profile section count')
load(rebuild(bytes,nil,{1,2,3,4,5,6,7,8,9}),'invalid profile section count')
load(rebuild(bytes,nil,{1,2,3,4,5,6,7,8,10,10}),'duplicate or unsupported section')
load(put(bytes,13,1),'invalid typed capability profile header')
load(bytes..'x','trailing bytes')
load(bytes:sub(1,15),'invalid module size')
load(bytes:sub(1,-2),'invalid, duplicate or unsupported section')
load(rebuild(bytes,{[10]=''}),'missing sections')
load(rebuild(bytes,{[10]='abc'}),'missing sections')
for _,payload in ipairs{parts[10]:sub(1,-2),parts[10]..'x',put(parts[10],1,65537),put(parts[10],1,4294967295)} do
 load(rebuild(bytes,{[10]=payload}),'invalid table or image size')
end
for _,offset in ipairs{25,32,4294967295} do
 load(rebuild(bytes,{[10]=put(parts[10],21,offset)}),'invalid or overlapping C-entry')
end
for _,offset in ipairs{8,12,7} do
 load(rebuild(bytes,{[10]=put(parts[10],13,offset)}),'invalid or overlapping C-entry')
end
for _,index in ipairs{9,4294967295} do
 load(rebuild(bytes,{[10]=put(parts[10],9,index)}),'invalid or overlapping C-entry')
end
for _,offset in ipairs{0,4} do
 load(rebuild(bytes,{[10]=put(parts[10],5,offset)}),'C-entry and code-address relocations overlap')
end
load(rebuild(bytes,{[8]=put(parts[8],5,12)}),'C-entry and code-address relocations overlap')
load(rebuild(bytes,{[8]=put(parts[8],9,2)}),'code relocation cannot name a lifecycle C entry')
local function bad_source(text,why) load(assembler.assemble(text),why) end
for _,signature in ipairs{'1 0 a -','2 0 ia -','2 0 ai -','2 1 aa i','2 0 aa - 8'} do
 bad_source((source:gsub('%.function drop 2 0 aa %-','.function drop '..signature)),'C entry requires two address arguments')
end
bad_source(source..'\n.export cleanup drop\n','lifecycle C entry cannot be exported')
bad_source((source:gsub('%.function unused_middle','HALT.A\n.function unused_middle')),'lifecycle C entry cannot contain HALT')
for _,bank in ipairs{'A','B'} do
 for _,tail in ipairs{false,true} do
  local operation=tail and ('TCALL.%s drop 2 2'):format(bank) or ('CALL.%s drop 2\nRET.%s 2 0'):format(bank,bank)
  for _,unreachable in ipairs{'','RET.A 2 0\n'} do
   bad_source(source..('\n.function bad 2 0 aa -\n%sCGET.%s 0\nCGET.%s 1\n%s\n'):format(unreachable,bank,bank,operation),'ABC call cannot target a lifecycle C entry')
  end
 end
end
for _,text in ipairs{
 '.profile callables\n.centry 0 drop',
 '.profile foreign\n.centry 0',
 '.profile foreign\n.centry -1 drop',
 '.profile foreign\n.centry 0 drop extra',
 '.profile foreign\n.centry 0 missing\n.function f 2 0 aa -\nRET.A 2 0',
} do check(not pcall(assembler.assemble,text),'malformed C-entry directive assembled') end
local optimized,map=optimizer.optimizeMapped(bytes)
load(optimized)
local after=sections(optimized)
check(optimized:sub(1,16)==bytes:sub(1,16),'optimizer changed format header')
check(u32(after[1],1)==7,'optimizer did not prune exactly the two dead functions')
check(u32(after[8],9)==2,'optimizer failed to remap ordinary code address')
check(u32(after[10],9)==1 and u32(after[10],17)==4 and u32(after[10],25)==1,'optimizer lost/remapped C-entry roots incorrectly')
check(u32(after[10],5)==8 and u32(after[10],13)==16 and u32(after[10],21)==24,'optimizer changed C-entry destinations')
check(after[4]==parts[4] and after[5]==parts[5],'optimizer changed persistent bytes')
check(next(map)~=nil,'mapped optimizer omitted provenance')
check(u32(after[6],1)==2,'optimizer lost load annotations in lifecycle/ordinary bodies')
util.write(directory..'/optimized.abc',optimized)
local listed,text,message=util.capture({'build/abc-runtime','dis',directory..'/optimized.abc'})
check(listed and text:find('C-entry image[8] = function 1',1,true) and text:find('lifecycle C entry (not ABC-callable)',1,true),'disassembler lost entry role: '..message)
local twice=optimizer.optimize(optimized);load(twice)
check(sections(twice)[10]==after[10],'second optimization changed C-entry identity')
-- No exports or ABC relocations: C entries alone must root their functions and callees.
local only_source=source:gsub('%.export [^\n]+\n',''):gsub('%.codeaddr [^\n]+\n',''):gsub('%.function main ','.function not_main ')
local only=assembler.assemble(only_source);local only_optimized=optimizer.optimize(only);load(only_optimized)
local only_parts=sections(only_optimized)
check(u32(only_parts[1],1)==3 and u32(only_parts[3],1)==0 and u32(only_parts[8],1)==0,'C-entry-only roots/callee preservation')
check(u32(only_parts[10],9)==0 and u32(only_parts[10],17)==1 and u32(only_parts[10],25)==0,'C-entry-only root index rewrite')
local reordered=optimizer.optimize(rebuild(bytes,nil,reversed));load(reordered)
check(sections(reordered)[10]==after[10],'section-order-dependent optimizer rewrite')
print(('C-entry format: %d assembler/loader/optimizer checks; no lifecycle execution'):format(checks))
