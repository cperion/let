-- The standalone binary and LuaJIT binding share the C residual-DAG optimizer.
local source = debug.getinfo(1, "S").source:sub(2)
local here = source:match("^(.*[/\\])") or "./"
local root = here .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. root .. "../build/?.lua;" .. package.path

local Compiler = require("let.compiler")
local Optimizer = require("let.optimize")
local Assembler = require("assembler")
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end

local input = Assembler.assemble([[
.function sq 1 1
  CGET.A 0
  CGET.B 0
  MUL.A
  RET 1 1
.function f 2 1
  CGET.A 0
  CALL.A sq 1
  CGET.A 1
  CALL.A sq 1
  MOVE.AB
  ADD.A
  RET 2 1
.function addk 1 1
  CGET.A 0
  PUSH.B 7
  ADD.A
  RET 1 1
.function folded 0 1
  PUSH.A 6
  PUSH.B 7
  MUL.A
  RET 0 1
.function choose 0 1
  PUSH.A 0
  JZ.A yes
  PUSH.A 1
  RET 0 1
yes:
  PUSH.A 42
  RET 0 1
.function shared 1 1
  CGET.A 0
  PUSH.B 1
  ADD.A
  DUP.A
  MOVE.AB
  MUL.A
  RET 1 1
.function traps 1 1
  CGET.A 0
  CGET.B 0
  DIVU.A
  DROP.A
  CGET.A 0
  PUSH.B 0
  DIVU.A
  DROP.A
  PUSH.A 42
  RET 1 1
.function doomed 0 1
  PUSH.A 6
  PUSH.B 7
  MUL.A
  ABORT 9
.function checked 1 1
  CGET.A 0
  CHKU8
  DROP.A
  PUSH.A 42
  RET 1 1
.function cse 1 1
  CGET.A 0
  PUSH.B 1
  ADD.A
  MOVE.AB
  CGET.A 0
  PUSH.B 1
  ADD.A
  ADD.A
  RET 1 1
.function branch 1 1
  CGET.A 0
  JZ.A zero
  PUSH.A 1
  RET 1 1
zero:
  PUSH.A 2
  RET 1 1
.function choices 1 1
  CGET.A 0
  SWITCH choice0 choice1
  PUSH.A 9
  JMP choiceDone
choice0:
  PUSH.A 10
  JMP choiceDone
choice1:
  PUSH.A 11
choiceDone:
  PUSH.B 1
  ADD.A
  RET 1 1
.function diamond 1 1
  CGET.A 0
  JZ.A otherwise
  PUSH.A 10
  JMP join
otherwise:
  PUSH.A 20
join:
  PUSH.B 1
  ADD.A
  RET 1 1
.function shri3 1 1
  CGET.A 0
  SHRI.A 3
  RET 1 1
.function sari3 1 1
  CGET.A 0
  SARI.A 3
  RET 1 1
.export f
.export addk
.export folded
.export choose
.export shared
.export traps
.export doomed
.export checked
.export cse
.export branch
.export choices
.export diamond
.export shri3
.export sari3
]])
local optimized = Compiler.optimize(input)
check(#optimized > 0, "symbolic optimization emits a verified canonical module without a no-growth gate")
check(Compiler.optimize(optimized) == optimized, "optimization reaches a byte-identical fixpoint")
local recursive = Assembler.assemble([[
.function loop 1 1
  CGET.A 0
  TCALL loop 1 1
.export loop
]])
local recursiveOptimized = Compiler.optimize(recursive)
local pathPlacementInput=Assembler.assemble([=[
.function collatz_paths 2 1
head:
  CGET.A 0
  JZ.A done
  CGET.A 0
  PUSH.B 1
  AND.A
  JZ.A even
  CGET.A 0
  PUSH.B 1
  SUB.A
  CGET.A 1
  PUSH.B 1
  ADD.A
  ZX32.A
  CALL.A collatz_paths 2
  RET 2 1
even:
  CGET.A 0
  PUSH.B 2
  SUB.A
  CGET.A 1
  PUSH.B 1
  ADD.A
  ZX32.A
  CALL.A collatz_paths 2
  RET 2 1
done:
  CGET.A 1
  RET 2 1
.export collatz_paths
]=])
local pathPlacementOptimized=Compiler.optimize(pathPlacementInput)
check(Compiler.optimize(pathPlacementOptimized)==pathPlacementOptimized,
  "path-sensitive loop placement reaches a byte-identical fixpoint")
local pathTrapInput=Assembler.assemble([=[
.function guarded_div 3 1
  CGET.A 0
  JZ.A other
  CGET.A 1
  CGET.B 2
  DIVU.A
  RET 3 1
other:
  CGET.A 1
  CGET.B 2
  DIVU.A
  RET 3 1
.export guarded_div
]=])
check(Compiler.optimize(pathTrapInput)==pathTrapInput,
  "path placement does not rematerialize or hoist potentially trapping operations")
local descriptorDceInput=Assembler.assemble([=[
.profile dynamic
.datazero 8
.descriptor primitive Dead u64
.descriptor primitive Live u32
.function descriptor_test 1 1 d i
  CGET.A 0
  ANY_IS Live
  RET 1 1
.codeaddr 0 descriptor_test
]=])
local descriptorDceOptimized=Compiler.optimize(descriptorDceInput)
check(Compiler.optimize(descriptorDceOptimized)==descriptorDceOptimized,
  "descriptor optimization remains at a fixpoint")
local descriptorRootInput=Assembler.assemble([=[
.profile dynamic
.datazero 8
.descriptor primitive Dead u64
.descriptor primitive A any
.descriptor record Root 8 1 0 0 0 A
.gcroot 0 Root
.function descriptor_root 0 1 - i
  PUSH.A 1
  RET 0 1
.export descriptor_root
]=])
local descriptorRootOptimized=Compiler.optimize(descriptorRootInput)
check(Compiler.optimize(descriptorRootOptimized)==descriptorRootOptimized,
  "GC-root descriptor graphs remain valid at a fixpoint")
check(recursiveOptimized ~= recursive and Compiler.optimize(recursiveOptimized) == recursiveOptimized, "stable self-tail frames become deterministic residual backedges")
local directReturnInput = Assembler.assemble([=[
.function wrapper 1 1
  CGET.A 0
  CALL.A countdown 1
  RET 1 1
.function countdown 1 1
  CGET.A 0
  JZ.A done
  CGET.A 0
  PUSH.B 1
  SUB.A
  CALL.A countdown 1
  RET 1 1
done:
  PUSH.A 0
  RET 1 1
.export wrapper
.export countdown
]=])
local directReturnOptimized=Compiler.optimize(directReturnInput)
check(Compiler.optimize(directReturnOptimized)==directReturnOptimized,
  "direct-return tail conversion and self-backedge emission reach one-pass fixpoints")
local counterInput = Assembler.assemble([[
.function main 0 2
  PUSH.A 50
  CALL.A count_to 1
  RET 0 2
.function count_to 1 2
  PUSH.A 0
  CPUSH.A
  PUSH.A 0
  CPUSH.A
  CGET.A 0
  CGET.A 1
  CPOP
  CPOP
  CPUSH.A
  CPUSH.A
  PUSH.A 7
  CPUSH.A
  CGET.A 1
  CGET.A 2
  CGET.A 3
  CGET.A 0
  CALL.A loop 4
  RET 4 2
.function loop 4 2
  CGET.A 1
  CGET.B 2
  BLTU body
  CGET.A 1
  CGET.A 0
  RET 4 2
body:
  CGET.A 0
  CGET.A 1
  CGET.A 3
  CALL.A bump 3
  CSET.A 1
  CSET.A 0
  DROP.A
  CGET.A 0
  CGET.A 1
  CGET.A 2
  CGET.A 3
  TCALL loop 4 4
.function bump 3 3
  CGET.A 1
  CGET.B 2
  ADD.A
  ZX32.A
  CSET.A 1
  CGET.A 0
  PUSH.B 1
  ADD.A
  ZX32.A
  CSET.A 0
  CGET.A 1
  CGET.A 0
  CGET.A 1
  RET 3 3
.export main
]])
local counterOptimized = Compiler.optimize(counterInput)
check(Compiler.optimize(counterOptimized) == counterOptimized,
  "recursive SCC specialization spends its bounded budget at a stable fixpoint")
local callableFile = assert(io.open(root .. "../examples/callables.abcasm", "rb"))
local callable = Assembler.assemble(callableFile:read("*a")); callableFile:close()
check(Compiler.optimize(callable) == callable, "unsupported callable regions remain byte-identical")
local callableRootsInput = Assembler.assemble([[
.profile callables
.datazero 8
.codeaddr 0 target
.signature op 1 1 a i
.function dead 0 1
  PUSH.A 99
  RET 0 1
.function target 1 1 a i
  PUSH.A 42
  RET 1 1
.function main 0 1
  GADDR.A 0
  .loadkind addr
  GLD64 0
  MOVE.AB
  CALLI.A 1 op
  RET 0 1
.export main
]])
local callableRootsOptimized = Compiler.optimize(callableRootsInput)
local memoryInput = Assembler.assemble([[
.profile memory
.datazero 8
.function pure 1 1
  CGET.A 0
  PUSH.B 7
  ADD.A
  RET 1 1
.function read 0 1
  .loadkind int
  GLD64 0
  RET 0 1
.function frame 0 1
  CALLOC 8
  CFREE 8
  PUSH.A 42
  RET 0 1
.export pure
.export read
.export frame
]])
local memoryOptimized = Compiler.optimize(memoryInput)
check(#memoryOptimized > #memoryInput, "full-profile optimization retains a canonical larger rewrite")
check(Compiler.optimize(memoryOptimized) == memoryOptimized, "full-profile output reaches a byte-identical fixpoint")
local memPairInput = Assembler.assemble([[
.profile memory
.datazero 32
.function main 0 1
  CALLOC 16
  FADDR.A 16
  CALL.A pair 1
  FLD64.A 16
  FLD64.B 8
  ADD.A
  CFREE 16
  RET 0 1
.function pair 1 0 a - 16
  CGET.A 0
  PUSH.B 42
  ST64 0
  CGET.A 0
  PUSH.B 57
  ST64 8
  RET 1 0
.export main
.export pair
]])
local memPairOptimized = Compiler.optimize(memPairInput)
check(memPairOptimized == memPairInput and Compiler.optimize(memPairOptimized) == memPairOptimized,
  "live caller frames and hidden-result callees form a conservative inlining barrier")
local dynamicInput = Assembler.assemble([[
.profile dynamic
.descriptor primitive U u32
.descriptor primitive W u64
.function pure 1 1
  CGET.A 0
  PUSH.B 7
  ADD.A
  RET 1 1
.function dyn 0 1 - i
  PUSH.A 7
  ANY_BOX U
  PUSH.A 35
  ANY_BOX U
  DADD
  ANY_CAST U
  RET 0 1
.function dyn_arg 1 1 i i
  CGET.A 0
  ZX32.A
  ANY_BOX U
  PUSH.A 1
  ANY_BOX U
  DADD
  ANY_CAST U
  RET 1 1
.function d2_u64 0 1 - i
  PUSH.A 2
  ANY_BOX W
  ANY_CAST W
  RET 0 1
.function f_w_add_w 0 1 - i
  PUSH.A 19
  ANY_BOX W
  PUSH.A 23
  ANY_BOX W
  DADD
  ANY_CAST W
  RET 0 1
.export pure
.export dyn
.export dyn_arg
.export d2_u64
.export f_w_add_w
]])
local dynamicOptimized = Compiler.optimize(dynamicInput)
check(Compiler.optimize(dynamicOptimized) == dynamicOptimized,
  "dynamic-effect optimization reaches a deterministic fixpoint")
local wideOverflowInput=Assembler.assemble([[
.profile dynamic
.descriptor primitive W u64
.function main 0 1 - i
  PUSH64.A 549755813888
  ANY_BOX W
  PUSH64.A 549755813888
  ANY_BOX W
  DADD
  ANY_CAST W
  RET 0 1
.export main
]])
check(Compiler.optimize(wideOverflowInput)==wideOverflowInput,
  "u64 constants widen conservatively when the result requires generic boxing")
local foreignInput = Assembler.assemble([[
.profile foreign
.extern host_note i -
.function note 1 1 i i
  CGET.A 0
  PUSH.B 1
  ADD.A
  FCALL host_note
  PUSH.A 42
  RET 1 1
.export note
]])
local foreignOptimized = Compiler.optimize(foreignInput)
check(Compiler.optimize(foreignOptimized) == foreignOptimized,
  "ordered foreign-effect optimization reaches a deterministic fixpoint")
local mixedCallableInput = Assembler.assemble([[
.profile callables
.datazero 8
.codeaddr 0 target
.signature op 1 1 a i
.function pure 1 1
  CGET.A 0
  PUSH.B 7
  ADD.A
  RET 1 1
.function target 1 1 a i
  PUSH.A 42
  RET 1 1
.function invoke 0 1
  GADDR.A 0
  .loadkind addr
  GLD64 0
  MOVE.AB
  CALLI.A 1 op
  RET 0 1
.export pure
.export invoke
]])
local mixedCallableOptimized = Compiler.optimize(mixedCallableInput)
check(Compiler.optimize(mixedCallableOptimized) == mixedCallableOptimized,
  "callable-profile optimization reaches a deterministic fixpoint")
local finiteCallableInput = Assembler.assemble([[
.profile callables
.datazero 16
.codeaddr 0 left
.codeaddr 8 right
.signature op 1 1 a i
.function left 1 1 a i
  PUSH.A 10
  RET 1 1
.function right 1 1 a i
  PUSH.A 20
  RET 1 1
.function choose 1 1 i i
  CGET.A 0
  JZ.A use_right
  GADDR.A 0
  .loadkind addr
  GLD64 0
  MOVE.AB
  JMP invoke
use_right:
  GADDR.A 8
  .loadkind addr
  GLD64 8
  MOVE.AB
invoke:
  CALLI.A 1 op
  RET 1 1
.export choose
]])
local finiteCallableOptimized = Compiler.optimize(finiteCallableInput)
check(Compiler.optimize(finiteCallableOptimized) == finiteCallableOptimized,
  "finite callable-set optimization reaches a deterministic fixpoint")
local escapingCallable = Assembler.assemble([[
.profile callables
.datazero 8
.codeaddr 0 target
.function target 0 0
  RET 0 0
.function expose 0 1 - a
  .loadkind addr
  GLD64 0
  RET 0 1
.export expose
]])
check(Compiler.optimize(escapingCallable) == escapingCallable, "ABI-escaping callable identity blocks private callable elimination")
local phiInput = Assembler.assemble([[
.function choose 1 2
  CGET.A 0
  JZ.A other
  PUSH.A 10
  PUSH.A 20
  JMP done
other:
  PUSH.A 30
  PUSH.A 40
done:
  RET 1 2
.export choose
]])
local phiOptimized = Compiler.optimize(phiInput)
check(Compiler.optimize(phiOptimized) == phiOptimized, "fixed phi-home output reaches a byte-identical fixpoint")

local function write(path, bytes)
  local f = assert(io.open(path, "wb")); assert(f:write(bytes)); assert(f:close())
end
local prefix = os.tmpname()
local original, residual, standalone = prefix .. ".abc", prefix .. ".opt.abc", prefix .. ".standalone.abc"
write(original, input); write(residual, optimized)
local memoryOriginal, memoryResidual = prefix .. ".memory.abc", prefix .. ".memory.opt.abc"
local memPairOriginal, memPairResidual = prefix .. ".mem-pair.abc", prefix .. ".mem-pair.opt.abc"
local counterOriginal, counterResidual = prefix .. ".counter.abc", prefix .. ".counter.opt.abc"
local dynamicResidual = prefix .. ".dynamic.opt.abc"
local mixedCallableResidual = prefix .. ".callable.opt.abc"
local directReturnOriginal = prefix .. ".direct-return.abc"
local finiteCallableResidual = prefix .. ".finite.opt.abc"
local phiResidual = prefix .. ".phi.opt.abc"
local callableRootsResidual = prefix .. ".callable-roots.opt.abc"
local directReturnResidual = prefix .. ".direct-return.opt.abc"
local pathPlacementResidual = prefix .. ".path-placement.opt.abc"
local descriptorRootResidual = prefix .. ".descriptor-root.opt.abc"
write(memoryOriginal, memoryInput); write(memoryResidual, memoryOptimized); write(memPairOriginal, memPairInput); write(memPairResidual, memPairOptimized); write(counterOriginal, counterInput); write(counterResidual, counterOptimized); write(dynamicResidual, dynamicOptimized); write(mixedCallableResidual, mixedCallableOptimized); write(finiteCallableResidual, finiteCallableOptimized); write(phiResidual, phiOptimized); write(callableRootsResidual, callableRootsOptimized); write(directReturnOriginal,directReturnInput); write(directReturnResidual,directReturnOptimized); write(pathPlacementResidual,pathPlacementOptimized); write(descriptorRootResidual,descriptorRootOptimized)
check(os.execute(string.format("%q %q -o %q", root .. "../build/abc-opt", original, standalone)) == 0,
  "standalone optimizer succeeds")
local f = assert(io.open(standalone, "rb")); local standaloneBytes = f:read("*a"); f:close()
check(standaloneBytes == optimized, "standalone and LuaJIT FFI use identical C optimization")
local rootsDis=assert(io.popen(string.format("%q dis %q",root.."../build/abc",callableRootsResidual),"r"));local rootsListing=rootsDis:read("*a");local _,rootFunctions=rootsListing:gsub("function %d+:","")
check(rootsDis:close() and rootFunctions==2 and not rootsListing:match("PUSH8_A%s+99"),"residual reachability drops dead callable-profile functions but retains code-address roots")
check(Compiler.optimize(callableRootsOptimized)==callableRootsOptimized,"remapped callable relocation output is a byte-identical fixpoint")
local rootsRun=assert(io.popen(string.format("%q run %q main --interpreted",root.."../build/abc",callableRootsResidual),"r"));check(rootsRun:read("*a"):match("42") and rootsRun:close(),"remapped code-address relocation invokes the retained function")
local directRun=assert(io.popen(string.format("%q run %q wrapper --interpreted 20 2>&1",root.."../build/abc",directReturnResidual),"r"));local directRunText=directRun:read("*a");local directRunOk=directRun:close()
check(directRunOk and directRunText:match("^0%s*$"),
  "direct recursive returns preserve execution through shared residual CFG lowering")
local directDis=assert(io.popen(string.format("%q dis %q",root.."../build/abc",directReturnResidual),"r"));local directListing=directDis:read("*a");check(directDis:close() and directListing:match("CALL_A") and directListing:match("RET"),
  "direct recursive returns retain explicit call and return boundaries")
local pathDis=assert(io.popen(string.format("%q dis %q",root.."../build/abc",pathPlacementResidual),"r"));local pathListing=pathDis:read("*a");check(pathDis:close() and pathListing:match("ANDI_A%s+1") and pathListing:match("ADDI_A%s+1") and pathListing:match("SUBI_A%s+1") and pathListing:match("SUBI_A%s+2") and pathListing:match("JMP") and pathListing:match("RET"),
  "exclusive loop paths retain their arithmetic and explicit residual control flow")
for _,mode in ipairs({"interpreted","compiled","lazy"}) do local run=assert(io.popen(string.format("%q run %q descriptor_root --%s",root.."../build/abc",descriptorRootResidual,mode),"r"));check(run:read("*a"):match("1") and run:close(),"compacted GC-root descriptors execute in "..mode.." mode") end
for _,mode in ipairs({"interpreted","compiled","lazy"}) do local run=assert(io.popen(string.format("%q run %q collatz_paths 5 0 --%s",root.."../build/abc",pathPlacementResidual,mode),"r"));check(run:read("*a"):match("3") and run:close(),"path-sensitive residual loop executes in "..mode.." mode") end
for _,mode in ipairs({"interpreted","compiled","lazy"}) do local run=assert(io.popen(string.format("%q run %q wrapper 20 --%s",root.."../build/abc",directReturnResidual,mode),"r"));check(run:read("*a"):match("0") and run:close(),"direct-return tails execute in "..mode.." mode") end
local counterDis = assert(io.popen(string.format("%q dis %q", root .. "../build/abc", counterResidual), "r")); local counterListing = counterDis:read("*a"); check(counterDis:close(), "residual recursive Counter disassembles")
check(counterListing:match("BLTUI%s+50") and counterListing:match("ADDI_A%s+7"), "recursive counter retains invariant limit and step specialization")
local _, counterFunctions = counterListing:gsub("function %d+:", "")
check(counterFunctions <= 4, "symbolic reachability preserves the bounded recursive counter family")
check(counterListing:match("BLTUI%s+50.-ADDI_A%s+7.-ZX32_A") and counterListing:match("JMP"), "loop invariants become immediates in explicit residual control flow")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local a = assert(io.popen(string.format("%q run %q main --%s", root .. "../build/abc", counterOriginal, mode), "r"))
  local b = assert(io.popen(string.format("%q run %q main --%s", root .. "../build/abc", counterResidual, mode), "r"))
  local av, bv = a:read("*a"), b:read("*a")
  check(a:close() and b:close() and av:match("56 8") and bv == av, "residual recursive Counter agrees in " .. mode .. " mode")
end
for _, name in ipairs({"pure", "read", "frame"}) do
  local argument = name == "pure" and " 7" or ""
  local a = assert(io.popen(string.format("%q run %q %s%s --interpreted", root .. "../build/abc", memoryOriginal, name, argument), "r"))
  local b = assert(io.popen(string.format("%q run %q %s%s --interpreted", root .. "../build/abc", memoryResidual, name, argument), "r"))
  local av, bv = a:read("*a"), b:read("*a")
  check(a:close() and b:close() and av == bv, "relocated full-profile " .. name .. " agrees")
end
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local a = assert(io.popen(string.format("%q run %q main --%s", root .. "../build/abc", memPairOriginal, mode), "r"))
  local b = assert(io.popen(string.format("%q run %q main --%s", root .. "../build/abc", memPairResidual, mode), "r"))
  local av, bv = a:read("*a"), b:read("*a")
  check(a:close() and b:close() and av:match("99") and bv == av, "hidden-result frame barrier agrees in " .. mode .. " mode")
end
local dynamicDis=assert(io.popen(string.format("%q dis %q",root.."../build/abc",dynamicResidual),"r"));local dynamicListing=dynamicDis:read("*a");check(dynamicDis:close(),"specialized dynamic residue disassembles")
check(dynamicListing:match("RET"),
  "dynamic residue retains valid typed return boundaries")
local dynamicRun = assert(io.popen(string.format("%q run %q pure 35 --interpreted", root .. "../build/abc", dynamicResidual), "r"))
check(dynamicRun:read("*a"):match("42") and dynamicRun:close(), "optimized dynamic-profile function executes")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  dynamicRun = assert(io.popen(string.format("%q run %q dyn --%s", root .. "../build/abc", dynamicResidual, mode), "r"))
  check(dynamicRun:read("*a"):match("42") and dynamicRun:close(), "ordered dynamic-effect DAG executes in " .. mode .. " mode")
  dynamicRun = assert(io.popen(string.format("%q run %q dyn_arg 41 --%s",root.."../build/abc",dynamicResidual,mode),"r"))
  check(dynamicRun:read("*a"):match("42") and dynamicRun:close(),"typed dynamic specialization executes in "..mode.." mode")
  for _,wide in ipairs({{"d2_u64","2"},{"f_w_add_w","42"}}) do
    dynamicRun=assert(io.popen(string.format("%q run %q %s --%s",root.."../build/abc",dynamicResidual,wide[1],mode),"r"))
    check(dynamicRun:read("*a"):match(wide[2]) and dynamicRun:close(),wide[1].." wide dynamic constant executes in "..mode.." mode")
  end
end
local callableDis = assert(io.popen(string.format("%q dis %q", root .. "../build/abc", mixedCallableResidual), "r")); local callableListing = callableDis:read("*a"); check(callableDis:close(), "exact callable residual disassembles")
check(callableListing:match("CALLI") and callableListing:match("GLD64"), "conservative callable fallback retains verified indirect call machinery")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local callableRun = assert(io.popen(string.format("%q run %q invoke --%s", root .. "../build/abc", mixedCallableResidual, mode), "r"))
  check(callableRun:read("*a"):match("42") and callableRun:close(), "exact callable elimination executes in " .. mode .. " mode")
end
local finiteDis = assert(io.popen(string.format("%q dis %q", root .. "../build/abc", finiteCallableResidual), "r")); local finiteListing = finiteDis:read("*a"); check(finiteDis:close(), "finite callable residual disassembles")
check(finiteListing:match("CALLI") and finiteListing:match("RET"), "finite callable fallback retains verified callable control flow")
for _, case in ipairs({{0, 20}, {1, 10}}) do for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local callableRun = assert(io.popen(string.format("%q run %q choose %d --%s", root .. "../build/abc", finiteCallableResidual, case[1], mode), "r"))
  check(callableRun:read("*a"):match(tostring(case[2])) and callableRun:close(), "finite callable arm executes in " .. mode .. " mode")
end end
local phiDis = assert(io.popen(string.format("%q dis %q", root .. "../build/abc", phiResidual), "r")); local phiListing = phiDis:read("*a"); check(phiDis:close(), "phi-home module disassembles")
check(phiListing:match("RET%s+%d+%s+2"),
  "unknown multi-result joins retain their verified result contract")
for _, pair in ipairs({{0, "30 40"}, {1, "10 20"}}) do
  local p = assert(io.popen(string.format("%q run %q choose %d --interpreted", root .. "../build/abc", phiResidual, pair[1]), "r"))
  check(p:read("*a"):match(pair[2]) and p:close(), "fixed phi-home path executes")
end
local dis = assert(io.popen(string.format("%q dis %q", root .. "../build/abc", residual), "r"))
local listing = dis:read("*a"); check(dis:close(), "optimized module disassembles")
local mappedBytes, provenance = Optimizer.optimizeMapped(input)
check(mappedBytes == optimized, "mapped and ordinary optimizer entry points emit identical bytes")
local originalDis = assert(io.popen(string.format("%q dis %q", root .. "../build/abc", original), "r")); local originalListing = originalDis:read("*a"); check(originalDis:close(), "original module disassembles for provenance validation")
local optimizedTrap = tonumber(assert(listing:match("(%x+)%s+DIVU_A")), 16)
local originalTrap = tonumber(assert(originalListing:match("(%x+)%s+DIVU_A")), 16)
check(provenance[optimizedTrap] == originalTrap, "optimizer provenance maps a residual trap to its original bytecode offset")
check(listing:match("MUL") and listing:match("ADD"),
  "canonical output retains the verified arithmetic schedule")
check(listing:match("ADDI_A%s+7") or listing:match("PUSH8_[AB]%s+7"),
  "residual arithmetic retains its literal seven")
local scalar = assert(io.popen(string.format("%q run %q addk 35 --interpreted", root .. "../build/abc", residual), "r"))
check(scalar:read("*a"):match("42") and scalar:close(), "optimized immediate function executes")
check(listing:match("SHRI_A%s+3") and listing:match("SARI_A%s+3"),
  "shift immediates retain their logical and arithmetic base operations")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  for _, name in ipairs({"shri3", "sari3"}) do
    local a = assert(io.popen(string.format("%q run %q %s 255 --%s", root .. "../build/abc", original, name, mode), "r"))
    local b = assert(io.popen(string.format("%q run %q %s 255 --%s", root .. "../build/abc", residual, name, mode), "r"))
    local av, bv = a:read("*a"), b:read("*a")
    check(a:close() and b:close() and av:match("31") and bv == av, name .. " immediate agrees in " .. mode .. " mode")
  end
end
scalar = assert(io.popen(string.format("%q run %q folded --interpreted", root .. "../build/abc", residual), "r"))
check(scalar:read("*a"):match("42") and scalar:close(), "shared semantics fold constant expression")
scalar = assert(io.popen(string.format("%q run %q choose --interpreted", root .. "../build/abc", residual), "r"))
check(scalar:read("*a"):match("42") and scalar:close(), "known control follows one residual path")
check(listing:match("MUL_A") and listing:match("RET"),
  "pure multiplication retains its verified result boundary")
scalar = assert(io.popen(string.format("%q run %q shared 4 --interpreted", root .. "../build/abc", residual), "r"))
check(scalar:read("*a"):match("25") and scalar:close(), "materialized multi-use DAG executes")
check(listing:match("ADD_A"),
  "shared arithmetic retains a valid addition schedule")
scalar = assert(io.popen(string.format("%q run %q cse 20 --interpreted", root .. "../build/abc", residual), "r"))
check(scalar:read("*a"):match("42") and scalar:close(), "hash-consed residual DAG executes")
check(select(2, listing:gsub("DIVU_A", "")) >= 2 and listing:match("PUSH8_A%s+42"),
  "ordered traps remain present before the final constant")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local function trap(path)
    local p = assert(io.popen(string.format("%q run %q traps 7 --%s 2>&1", root .. "../build/abc", path, mode), "r"))
    local output = p:read("*a"):gsub("%s+$", ""); local ok = p:close(); return ok, output
  end
  local aok, a = trap(original); local bok, b = trap(residual)
  a = a:gsub("byte 0x%x+", "byte <pc>"); b = b:gsub("byte 0x%x+", "byte <pc>")
  check(aok and bok and a == b and a:match("language abort 1"), "trapping effect order agrees in " .. mode .. " mode")
end
check(listing:match("ABORT%s+9"), "terminal abort remains an ordered effect without a synthetic result")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local function doomed(path)
    local p = assert(io.popen(string.format("%q run %q doomed --%s 2>&1", root .. "../build/abc", path, mode), "r"))
    local output = p:read("*a"):gsub("byte 0x%x+", "byte <pc>"):gsub("%s+$", ""); local ok = p:close(); return ok, output
  end
  local aok, a = doomed(original); local bok, b = doomed(residual)
  check(aok and bok and a == b and a:match("language abort 9"), "terminal abort agrees in " .. mode .. " mode")
end
check(listing:match("CHKU8") and listing:match("PUSH8_A%s+42"), "range checks remain ordered before the checked result")
scalar = assert(io.popen(string.format("%q run %q checked 7 --interpreted", root .. "../build/abc", residual), "r"))
check(scalar:read("*a"):match("42") and scalar:close(), "residual checked path executes")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local function checked(path)
    local p = assert(io.popen(string.format("%q run %q checked 300 --%s 2>&1", root .. "../build/abc", path, mode), "r"))
    local output = p:read("*a"):gsub("byte 0x%x+", "byte <pc>"):gsub("%s+$", ""); local ok = p:close(); return ok, output
  end
  local aok, a = checked(original); local bok, b = checked(residual)
  check(aok and bok and a == b and a:match("language abort"), "range-check effect agrees in " .. mode .. " mode")
end
local _, residualBranches = listing:gsub("JZ_A", "")
check(residualBranches >= 2, "unknown controls remain represented in conservative output")
scalar = assert(io.popen(string.format("%q run %q branch 0 --interpreted", root .. "../build/abc", residual), "r"))
check(scalar:read("*a"):match("2") and scalar:close(), "residual unknown-control function executes")
check(listing:match("JZ_A") and listing:match("RET"),
  "unknown diamond paths retain explicit verified control flow")
for _, pair in ipairs({{0, 21}, {1, 11}}) do
  scalar = assert(io.popen(string.format("%q run %q diamond %d --interpreted", root .. "../build/abc", residual, pair[1]), "r"))
  check(scalar:read("*a"):match(tostring(pair[2])) and scalar:close(), "residual diamond path executes")
end
check(listing:match("SWITCH") and listing:match("RET"),
  "unknown SWITCH paths retain explicit verified control flow")
for _, pair in ipairs({{0, 11}, {1, 12}, {4, 10}}) do
  scalar = assert(io.popen(string.format("%q run %q choices %d --interpreted", root .. "../build/abc", residual, pair[1]), "r"))
  check(scalar:read("*a"):match(tostring(pair[2])) and scalar:close(), "residual SWITCH path executes")
end
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
  local function run(path)
    local p = assert(io.popen(string.format("%q run %q f 3 4 --%s 2>&1", root .. "../build/abc", path, mode), "r"))
    local output = p:read("*a"):gsub("%s+$", ""); local ok = p:close(); return ok, output
  end
  local aok, a = run(original); local bok, b = run(residual)
  check(aok and bok and a == "25" and b == a, "optimized result agrees in " .. mode .. " mode")
end
os.remove(original); os.remove(residual); os.remove(standalone); os.remove(memoryOriginal); os.remove(memoryResidual); os.remove(memPairOriginal); os.remove(memPairResidual); os.remove(counterOriginal); os.remove(counterResidual); os.remove(dynamicResidual); os.remove(mixedCallableResidual); os.remove(finiteCallableResidual); os.remove(phiResidual); os.remove(callableRootsResidual); os.remove(directReturnOriginal); os.remove(directReturnResidual); os.remove(pathPlacementResidual); os.remove(descriptorRootResidual)
print(string.format("PASS: shared C residual-DAG optimizer and LuaJIT FFI (%d checks)", checks))
