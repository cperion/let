-- Small assembly -> module verification -> concrete execution contract set.
local directory=arg[0]:match('^(.*)/[^/]*$') or '.'
package.path=directory..'/?.lua;'..package.path
local assembler,util=require('assembler'),require('tool_util')
local runtime=arg[1] or 'build/abc-runtime'
local fixtures={
 {name='selected subtraction',expected=-7,source=[[.function main 0 1
 PUSH.A 10
 PUSH.B 3
 SUB.B
 RET.B 0 1
 ]]},
 {name='selected memory address and value',expected=7,source=[[.profile memory
 .datazero 8
 .function main 0 1 - i
 PUSH.B 123
 GST64.B 0
 GADDR.B 0
 PUSH.A 7
 ST64.B 0
 GLD64.B 0
 RET.B 0 1
 ]]},
 {name='indirect selected arguments',expected=10,source=[[.profile callables
 .datazero 16
 .codeaddr 0 target
 .signature sig 2 1 ai i
 .function main 0 1 - i
 GADDR.B 8
 PUSH.B 9
 .loadkind addr
 GLD64.A 0
 CALLI.B 2 sig
 RET.B 0 1
 .function target 2 1 ai i
 CGET.A 1
 ADDI.A 1
 RET.A 2 1
 ]]},
 {name='tail continuation destination',expected=10,source=[[.profile callables
 .datazero 16
 .codeaddr 0 target
 .signature sig 2 1 ai i
 .function main 0 1 - i
 GADDR.B 8
 PUSH.B 9
 .loadkind addr
 GLD64.A 0
 TCALLI.B 0 2 sig
 .function target 2 1 ai i
 CGET.A 1
 ADDI.A 1
 RET.A 2 1
 ]]},
 {name='extended immediate branch base',expected=42,source=[[.function main 0 1
 PUSH.B 7
 BEQI.B 7 yes
 ABORT 9
 yes:
 PUSH.B 42
 RET.B 0 1
 ]]},
 {name='overlapping copy with full u32 count',expected=66,source=[[.profile memory
 .datazero 65547
 .function main 0 1 - i
 PUSH.A 66
 GST8.A 65536
 GADDR.B 8
 GADDR.A 0
 MEMCPY.B 65539
 GLD8.B 65544
 RET.B 0 1
 ]]},
 {name='selected float conversion',expected=7,source=[[.profile memory
 .function main 0 1 - i
 PUSH.B 7
 I2FU.B
 FNEG.B
 FNEG.B
 F2IU.B
 RET.B 0 1
 ]]},
 {name='direct tail preserves caller result destination',expected=9,source=[[.function main 0 1
 PUSH.B 9
 CALL.B first 1
 RET.B 0 1
 .function first 1 1
 CGET.A 0
 TCALL.A last 1 1
 .function last 1 1
 CGET.B 0
 RET.B 1 1
 ]]},
}
local cases=0
for _,fixture in ipairs(fixtures) do
 for mirror=0,1 do
    local source=fixture.source
    if mirror==1 then source=source:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end) end
    local path=os.tmpname()
    local success,message=pcall(function()
        local bytes=assembler.assemble(source)
        assert(bytes:byte(5)==6 and bytes:byte(6)==0,'incorrect ISA revision')
        util.write(path,bytes)
        local valid,result,error=util.capture({runtime,'run',path,'--interpreted'})
        assert(valid,fixture.name..': '..error)
        assert(tonumber(result)==fixture.expected,fixture.name..': '..result)
    end)
    os.remove(path)
    assert(success,message);cases=cases+1
 end
end
-- Kind-only casts still require a selected operand of exactly the declared kind.
for _,body in ipairs{' F2BITS.A\n', ' PUSH.A 1\n F2BITS.A\n',
 ' PUSH.A 1\n BITS2F.A\n BITS2F.A\n', ' GADDR.A 0\n BITS2F.A\n'} do
 for mirror=0,1 do
  local text='.profile memory\n.datazero 8\n.function main 0 0 - -\n'..body..' DROP.A\n RET.A 0 0\n.export main\n'
  if mirror==1 then text=text:gsub('%.([AB])',function(bank)return bank=='A' and '.B' or '.A' end) end
  local path=os.tmpname();util.write(path,assembler.assemble(text))
  local valid=util.capture({runtime,'run',path,'--interpreted'});os.remove(path)
  assert(not valid,'unproved bitcast operand kind was accepted');cases=cases+1
 end
end
assert(not pcall(assembler.assemble,'.function main 0 1\n PUSH.A 0\n BITS2F.A\n RET.A 0 1\n.export main\n'),'bitcasts must require profile 2+')
print(('revision-6 assembly/verifier/interpreter: %d original/mirrored contracts passed'):format(cases))
