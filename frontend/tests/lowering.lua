-- Checked ASDL Ir -> ABC lowering and cross-policy execution.
local source = debug.getinfo(1, "S").source:sub(2)
local here = source:match("^(.*[/\\])") or "./"
local root = here .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path

local Compiler = require("let.compiler")
local D = require("let.diag")
local S = require("let.schema")
require("let.ir")
local I, L = S.Ir, S.ASDL.List
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local function ref(value, ty) return I.Ref(value, ty) end
local function uint(n, ty) return I.Const(ty or S.U32, I.UInt(n)) end
local function input(ty) return S.inValue(ty) end

local av, bv = I.Value(1), I.Value(2)
local add = I.Fn("add", I.Body, 0, L{input(S.U32), input(S.U32)}, L{S.U32},
    L{I.ValueParam(0, av, S.U32), I.ValueParam(1, bv, S.U32)},
    L{I.Return(L{I.Bin(I.Add, ref(av, S.U32), ref(bv, S.U32), S.U32)})})

-- A loop with mutable local storage exercises fixed C-frame slots and branch joins.
local nv = I.Value(1)
local accumulator, counter = I.Storage(1), I.Storage(2)
local counterValue, resultValue, accumulatorValue = I.Value(2), I.Value(3), I.Value(4)
local loop = I.Loop(L{
    I.Read(counterValue, S.U32, I.Local(counter)),
    I.If(I.Bin(I.Eq, ref(counterValue, S.U32), uint(0), S.Bool),
        L{I.Read(resultValue, S.U32, I.Local(accumulator)), I.Return(L{ref(resultValue, S.U32)})},
        L{I.Read(accumulatorValue, S.U32, I.Local(accumulator)),
            I.Store(I.Local(accumulator), I.Bin(I.Add, ref(accumulatorValue, S.U32),
                ref(counterValue, S.U32), S.U32)),
            I.Store(I.Local(counter), I.Bin(I.Sub, ref(counterValue, S.U32), uint(1), S.U32)),
            I.Next})
})
local sum = I.Fn("sum", I.Body, 0, L{input(S.U32)}, L{S.U32},
    L{I.ValueParam(0, nv, S.U32)},
    L{I.Var(accumulator, S.U32, uint(0)), I.Var(counter, S.U32, ref(nv, S.U32)), loop})

local addResult, sumResult = I.Value(1), I.Value(2)
local main = I.Fn("main", I.Entry, 0, L{}, L{S.U32}, L{}, L{
    I.Call(L{addResult}, "add", L{I.ValueArg(uint(40)), I.ValueArg(uint(2))}),
    I.Call(L{sumResult}, "sum", L{I.ValueArg(uint(10))}),
    I.Return(L{I.Bin(I.Add, ref(addResult, S.U32), ref(sumResult, S.U32), S.U32)})
})

local tailResult = I.Value(1)
local tail = I.Fn("tail", I.Entry, 0, L{}, L{S.U32}, L{}, L{
    I.Call(L{tailResult}, "add", L{I.ValueArg(uint(20)), I.ValueArg(uint(22))}),
    I.Return(L{ref(tailResult, S.U32)})
})

local narrowed = I.Value(1)
local narrow = I.Fn("narrow", I.Entry, 0, L{input(S.U32)}, L{S.U8},
    L{I.ValueParam(0, narrowed, S.U32)},
    L{I.Return(L{I.Convert(ref(narrowed, S.U32), S.U8)})})

local ox, oy = I.Value(1), I.Value(2)
local function oref(value) return ref(value, S.U32) end
local function obin(op, result) return I.Bin(op, oref(ox), oref(oy), result or S.U32) end
local opsResults = {S.U32, S.U32, S.U32, S.U32, S.U32, S.U32, S.U32, S.U32, S.U32,
    S.U32, S.U32, S.Bool, S.Bool, S.Bool, S.Bool, S.Bool, S.Bool}
local ops = I.Fn("ops", I.Entry, 0, L{input(S.U32), input(S.U32)}, L(opsResults),
    L{I.ValueParam(0, ox, S.U32), I.ValueParam(1, oy, S.U32)}, L{I.Return(L{
        obin(I.Add), obin(I.Sub), obin(I.Mul), obin(I.Div), obin(I.Rem), obin(I.Pow),
        obin(I.BitAnd), obin(I.BitOr), obin(I.BitXor), obin(I.Shl), obin(I.Shr),
        obin(I.Eq, S.Bool), obin(I.Ne, S.Bool), obin(I.Lt, S.Bool), obin(I.Le, S.Bool),
        obin(I.Gt, S.Bool), obin(I.Ge, S.Bool)})})

local wrap = I.Fn("wrap", I.Entry, 0, L{}, L{S.U8}, L{},
    L{I.Return(L{I.Bin(I.Add, uint(250, S.U8), uint(10, S.U8), S.U8)})})
local trapped = I.Value(1)
local trap = I.Fn("trap", I.Entry, 0, L{input(S.Bool)}, L{S.U32},
    L{I.ValueParam(0, trapped, S.Bool)},
    L{I.Trap(ref(trapped, S.Bool), "index-range"), I.Return(L{uint(7)})})

local f1, f2, nan = I.Const(S.F64, I.Float(1.5)), I.Const(S.F64, I.Float(2.5)),
    I.Const(S.F64, I.Float(0 / 0))
local function fbin(op, left, right, result)
    return I.Bin(op, left or f1, right or f2, result or S.F64)
end
local function ftoi(expr) return I.Convert(expr, S.I32) end
local floatResults = {S.I32, S.I32, S.I32, S.I32, S.I32, S.Bool, S.Bool, S.Bool, S.Bool,
    S.Bool, S.Bool, S.Bool, S.Bool, S.Bool, S.Bool}
local floatMain = I.Fn("float_main", I.Entry, 0, L{}, L(floatResults), L{}, L{I.Return(L{
    ftoi(fbin(I.Add)), ftoi(fbin(I.Sub)), ftoi(fbin(I.Mul)), ftoi(fbin(I.Div)),
    ftoi(I.Un(I.Neg, f1, S.F64)),
    fbin(I.Lt, nil, nil, S.Bool), fbin(I.Le, nil, nil, S.Bool),
    fbin(I.Gt, nil, nil, S.Bool), fbin(I.Ge, nil, nil, S.Bool),
    fbin(I.Eq, nil, nil, S.Bool), fbin(I.Ne, nil, nil, S.Bool),
    fbin(I.Eq, nan, nan, S.Bool), fbin(I.Ne, nan, nan, S.Bool),
    fbin(I.Lt, nan, f2, S.Bool), fbin(I.Gt, nan, f2, S.Bool)})})

local addSignature = S.Sig({input(S.U32), input(S.U32)}, {S.U32})
local addView = S.View(addSignature)
local callableValue, callableResult = I.Value(1), I.Value(2)
local virtualMain = I.Fn("virtual_main", I.Entry, 0, L{}, L{S.U32}, L{}, L{
    I.View(callableValue, addView, "add", L{}, nil),
    I.Indirect(L{callableResult}, ref(callableValue, addView),
        L{I.ValueArg(uint(40)), I.ValueArg(uint(2))}),
    I.Return(L{ref(callableResult, S.U32)})
})

local pairRecord = S.Record{x=S.U32,y=S.U32}
local pairValue, pairField = I.Value(1), I.Value(2)
local madePair = I.Make(pairRecord,L{uint(40),uint(2)})
local virtualRecord = I.Fn("virtual_record",I.Entry,0,L{},L{S.U32},L{},L{
    I.Let(pairValue,pairRecord,madePair),
    I.Let(pairField,S.U32,I.Get(ref(pairValue,pairRecord),I.Field("y"),S.U32)),
    I.Return(L{I.Bin(I.Add,I.Get(ref(pairValue,pairRecord),I.Field("x"),S.U32),ref(pairField,S.U32),S.U32)})
})

local functions = {add, sum, main, tail, narrow, ops, wrap, trap, virtualMain, virtualRecord}
local artifact = Compiler.lower(functions, {profile = "slet",
    exports = {"main", "tail", "narrow", "ops", "wrap", "trap", "virtual_main", "virtual_record"}})
check(artifact.phase == "lowered" and artifact.profile == "integer", "scalar SLet lowers to profile 1")
check(artifact.assembly:match("TCALL%.A add"), "identity call-return lowers to TCALL")
check(not artifact.assembly:match("CALLI"), "exact nonescaping empty callable views re-project to direct calls")
check(not artifact.assembly:match("CALLOC"), "exact nonescaping immutable records scalarize without storage")
check(not artifact.assembly:match("instruction%-budget"), "lowering emits no fuel mechanism")
local lineCount = select(2, artifact.assembly:gsub("\n", "\n"))
check(#artifact.lineMap == lineCount, "every assembly line retains an IR source-map hook")

local base = os.tmpname()
os.remove(base)
local asm, module = base .. ".abcasm", base .. ".abc"
local file = assert(io.open(asm, "wb")); assert(file:write(artifact.assembly)); assert(file:close())
local abc = root .. "../build/abc"
local function capture(command)
    local pipe = assert(io.popen(command .. " 2>&1", "r"))
    local output = pipe:read("*a"):gsub("%s+$", "")
    pipe:close()
    return output
end
check(capture(("%q asm %q -o %q"):format(abc, asm, module)) == "", "lowered assembly verifies")
for _, mode in ipairs{"interpreted", "compiled", "lazy", "jit=threaded"} do
    check(capture(("%q run %q main --%s"):format(abc, module, mode)) == "97",
        "main agrees in " .. mode .. " mode")
    check(capture(("%q run %q tail --%s"):format(abc, module, mode)) == "42",
        "tail call agrees in " .. mode .. " mode")
    check(capture(("%q run %q virtual_main --%s"):format(abc, module, mode)) == "42",
        "exact callable view agrees in " .. mode .. " mode")
    check(capture(("%q run %q virtual_record --%s"):format(abc, module, mode)) == "42",
        "exact immutable record agrees in " .. mode .. " mode")
    check(capture(("%q run %q narrow 300 --%s"):format(abc, module, mode)):match("language abort 3"),
        "checked narrowing aborts in " .. mode .. " mode")
    check(capture(("%q run %q ops 20 6 --%s"):format(abc, module, mode)) ==
        "26 14 120 3 2 64000000 4 22 18 1280 0 0 1 0 0 1 1",
        "integer operators agree in " .. mode .. " mode")
    check(capture(("%q run %q wrap --%s"):format(abc, module, mode)) == "4",
        "narrow arithmetic normalizes in " .. mode .. " mode")
    check(capture(("%q run %q trap 0 --%s"):format(abc, module, mode)) == "7",
        "false trap continues in " .. mode .. " mode")
    check(capture(("%q run %q trap 1 --%s"):format(abc, module, mode)):match("language abort 2"),
        "true trap aborts in " .. mode .. " mode")
end
os.remove(asm); os.remove(module)

-- Addressable aggregates use target-C field offsets in live frame blocks. Borrowed scalar
-- storage is likewise frame-backed, and a borrow cannot become a tail call that releases it.
local addressRecord=S.Record{x=S.U32,y=S.U16}
local addressStorage=I.Storage(20)
local addressX,addressY=I.Value(20),I.Value(21)
local addressable=I.Fn("addressable",I.Entry,0,L{},L{S.U32},L{},L{
    I.Var(addressStorage,addressRecord,I.Make(addressRecord,L{uint(40),uint(1,S.U16)})),
    I.Store(I.Project(I.Local(addressStorage),I.Field("y")),uint(2,S.U16)),
    I.Read(addressX,S.U32,I.Project(I.Local(addressStorage),I.Field("x"))),
    I.Read(addressY,S.U16,I.Project(I.Local(addressStorage),I.Field("y"))),
    I.Return(L{I.Bin(I.Add,ref(addressX,S.U32),I.Convert(ref(addressY,S.U16),S.U32,I.Checked),S.U32)})
})
local borrowedParameter=I.Storage(21)
local borrowedValue=I.Value(22)
local takeBorrow=I.Fn("take_borrow",I.Body,0,L{S.inPlace(S.U32)},L{S.U32},
    L{I.PlaceParam(0,borrowedParameter,S.U32)},
    L{I.Read(borrowedValue,S.U32,I.Local(borrowedParameter)),I.Return(L{ref(borrowedValue,S.U32)})})
local borrowedLocal=I.Storage(22)
local borrowedResult=I.Value(23)
local borrowMain=I.Fn("borrow_main",I.Entry,0,L{},L{S.U32},L{},L{
    I.Var(borrowedLocal,S.U32,uint(42)),
    I.Call(L{borrowedResult},"take_borrow",L{I.BorrowArg(I.Local(borrowedLocal))}),
    I.Return(L{ref(borrowedResult,S.U32)})
})
local arrayType=S.Array(S.U16,3)
local arrayIndex,arrayResult=I.Value(24),I.Value(25)
local arrayStorage=I.Storage(23)
local arrayRead=I.Fn("array_read",I.Entry,0,L{input(S.U32)},L{S.U16},L{I.ValueParam(0,arrayIndex,S.U32)},L{
    I.Var(arrayStorage,arrayType,I.Make(arrayType,L{uint(1,S.U16),uint(2,S.U16),uint(42,S.U16)})),
    I.Read(arrayResult,S.U16,I.Index(I.Local(arrayStorage),ref(arrayIndex,S.U32),S.U16)),
    I.Return(L{ref(arrayResult,S.U16)})
})
local optionType=S.Sum{none=S.Unit,some=S.U32}
local optionValue,optionPayload=I.Value(26),I.Value(27)
local sumMain=I.Fn("sum_main",I.Entry,0,L{},L{S.U32},L{},L{
    I.ConstructVariant(optionValue,optionType,"some",uint(42)),
    I.Switch(optionValue,optionType,L{
        I.Case("none",false,L{I.Return(L{uint(0)})}),
        I.Case("some",true,L{I.VariantPayload(optionPayload,optionValue,optionType,"some"),I.Return(L{ref(optionPayload,S.U32)})})
    })
})
local sliceType=S.Slice(S.U16)
local sliceParam,sliceParamIndex=I.Value(30),I.Value(31)
local sliceParamResult=I.Value(32)
local sliceGet=I.Fn("slice_get",I.Body,0,L{input(sliceType),input(S.U32)},L{S.U16},
    L{I.ValueParam(0,sliceParam,sliceType),I.ValueParam(1,sliceParamIndex,S.U32)},L{
        I.Read(sliceParamResult,S.U16,I.SliceIndex(ref(sliceParam,sliceType),ref(sliceParamIndex,S.U32),S.U16)),
        I.Return(L{ref(sliceParamResult,S.U16)})})
local sliceArrayStorage,sliceStorage=I.Storage(30),I.Storage(31)
local sliceMainIndex=I.Value(38)
local sliceValue,sliceResult=I.Value(33),I.Value(34)
local sliceMain=I.Fn("slice_main",I.Entry,0,L{input(S.U32)},L{S.U16},L{I.ValueParam(0,sliceMainIndex,S.U32)},L{
    I.Var(sliceArrayStorage,S.Array(S.U16,3),I.Make(S.Array(S.U16,3),L{uint(1,S.U16),uint(2,S.U16),uint(42,S.U16)})),
    I.Var(sliceStorage,sliceType,I.Make(sliceType,L{
        I.Addr(I.Index(I.Local(sliceArrayStorage),uint(0),S.U16),S.Ref(S.U16)),uint(3)})),
    I.Read(sliceValue,sliceType,I.Local(sliceStorage)),
    I.Call(L{sliceResult},"slice_get",L{I.ValueArg(ref(sliceValue,sliceType)),I.ValueArg(ref(sliceMainIndex,S.U32))}),
    I.Return(L{ref(sliceResult,S.U16)})})
local stringType=S.String
local stringValue=I.Value(35)
local stringByte,stringLength=I.Value(36),I.Value(37)
local stringMain=I.Fn("string_main",I.Entry,0,L{},L{S.U8,S.U32},L{},L{
    I.Let(stringValue,stringType,I.Const(stringType,I.Str("A*"))),
    I.Read(stringByte,S.U8,I.SliceIndex(ref(stringValue,stringType),uint(1),S.U8)),
    I.Let(stringLength,S.U32,I.SliceLength(ref(stringValue,stringType),S.U32)),
    I.Return(L{ref(stringByte,S.U8),ref(stringLength,S.U32)})})

local captureRecord=S.Record{base=S.Any}
local capturePlace=I.Storage(40)
local captureArgument=I.Value(40)
local capturedBase=I.Value(41)
local captureTarget=I.Fn("captured_add",I.Body,1,L{S.inPlace(captureRecord),input(S.U32)},L{S.U32},
    L{I.PlaceParam(0,capturePlace,captureRecord),I.ValueParam(1,captureArgument,S.U32)},L{
        I.Read(capturedBase,S.Any,I.Project(I.Local(capturePlace),I.Field("base"))),
        I.Return(L{I.Bin(I.Add,I.Convert(ref(capturedBase,S.Any),S.U32),ref(captureArgument,S.U32),S.U32)})})
local captureSignature=S.Sig({input(S.U32)},{S.U32})
local captureView=S.View(captureSignature)
local ownedRecord,adapterStorage=I.Storage(41),I.Storage(42)
local madeView=I.Value(42)
local makeAdder=I.Fn("make_adder",I.Body,0,L{},L{captureView},L{},L{
    I.Var(ownedRecord,captureRecord,I.Make(captureRecord,L{I.Convert(uint(40),S.Any)})),
    I.View(madeView,captureView,"captured_add",L{I.BorrowArg(I.Local(ownedRecord))},adapterStorage),
    I.Return(L{ref(madeView,captureView)})})
local escapedView,capturedResult=I.Value(43),I.Value(44)
local captureMain=I.Fn("capture_main",I.Entry,0,L{},L{S.U32},L{},L{
    I.Call(L{escapedView},"make_adder",L{}),
    I.Indirect(L{capturedResult},ref(escapedView,captureView),L{I.ValueArg(uint(2))}),
    I.Return(L{ref(capturedResult,S.U32)})})
local dynamicWord,dynamicLeft,dynamicRight,dynamicResult,dynamicTyped,dynamicIs=I.Value(50),I.Value(51),I.Value(52),I.Value(53),I.Value(54),I.Value(55)
local anyMain=I.Fn("any_main",I.Entry,0,L{},L{S.U32,S.Bool},L{},L{
    I.View(dynamicWord,S.Any,"add",L{},nil),
    I.Let(dynamicLeft,S.Any,I.Convert(uint(40),S.Any)),
    I.Let(dynamicRight,S.Any,I.Convert(uint(2),S.Any)),
    I.Indirect(L{dynamicResult},ref(dynamicWord,S.Any),L{I.ValueArg(ref(dynamicLeft,S.Any)),I.ValueArg(ref(dynamicRight,S.Any))}),
    I.Let(dynamicTyped,S.U32,I.Convert(ref(dynamicResult,S.Any),S.U32)),
    I.Let(dynamicIs,S.Bool,I.Is(ref(dynamicResult,S.Any),S.U32,S.Bool)),
    I.Return(L{ref(dynamicTyped,S.U32),ref(dynamicIs,S.Bool)})})
local boxedString,castString,stringAnyLength=I.Value(56),I.Value(57),I.Value(58)
local anyStringMain=I.Fn("any_string_main",I.Entry,0,L{},L{S.U32},L{},L{
    I.Let(boxedString,S.Any,I.Convert(I.Const(S.String,I.Str("abc")),S.Any)),
    I.Let(castString,S.String,I.Convert(ref(boxedString,S.Any),S.String)),
    I.Let(stringAnyLength,S.U32,I.SliceLength(ref(castString,S.String),S.U32)),
    I.Return(L{ref(stringAnyLength,S.U32)})})
local escapeOK,escapeError=pcall(Compiler.lower,{add,captureTarget,makeAdder,captureMain},{profile='slet'})
check(not escapeOK and D.is(escapeError) and escapeError.code=='borrow-return',
    'frame-backed adapters cannot escape without an implemented environment owner')
local managedFunctions={add,anyMain,anyStringMain}
require('let.program').analyze(managedFunctions)
local managedOK,managedError=pcall(Compiler.lower,managedFunctions,{profile="let",exports={"any_main","any_string_main"}})
check(not managedOK and D.is(managedError) and managedError.code=='dynamic-lowering',
    'verified managed IR does not produce obsolete dynamic ABC')
local memoryArtifact=Compiler.lower({addressable,takeBorrow,borrowMain,arrayRead,sumMain,sliceGet,sliceMain,stringMain},{profile="slet",exports={"addressable","borrow_main","array_read","sum_main","slice_main","string_main"}})
check(memoryArtifact.profile=="memory" and memoryArtifact.assembly:match("CALLOC 8"),
    "addressable records select frame-backed memory lowering")
check(memoryArtifact.assembly:match("ST16%.B 4") and memoryArtifact.assembly:match("LD16%.A 4"),
    "record fields use C-aligned offsets and typed accesses")
check(memoryArtifact.assembly:match("CALL%.A take_borrow 1") and not memoryArtifact.assembly:match("TCALL%.A take_borrow"),
    "a local borrow preserves its backing frame across the call")
check(memoryArtifact.assembly:match("IDX%.[AB] 2") and memoryArtifact.assembly:match("ABORT 2"),
    "fixed arrays use scaled addresses with an explicit bounds guard")
check(memoryArtifact.assembly:match("ST32%.B 0") and memoryArtifact.assembly:match("LD32%.A 0"),
    "sum construction and dispatch preserve the explicit tag layout")
check(memoryArtifact.assembly:match("%.function slice_get 3 1 aii i") and memoryArtifact.assembly:match("CALL%.A slice_get 3"),
    "slice values flatten to address and length cells across the call ABI")
check(memoryArtifact.assembly:match("ST32%.B 8") and memoryArtifact.assembly:match("ST64%.B 0") and memoryArtifact.assembly:match("LD64%.A 0") and memoryArtifact.assembly:match("LD32%.A 8"),
    "slice storage uses the target address-plus-length layout")
check(memoryArtifact.assembly:match("%.rodata 412a") and memoryArtifact.assembly:match("GADDR%.A 8"),
    "byte-slice literals use deterministic read-only module storage")
file=assert(io.open(asm,"wb"));assert(file:write(memoryArtifact.assembly));assert(file:close())
check(capture(("%q asm %q -o %q"):format(abc,asm,module))=="","addressable aggregate assembly verifies")
for _,mode in ipairs{"interpreted","compiled","lazy","jit=threaded"} do
    check(capture(("%q run %q addressable --%s"):format(abc,module,mode))=="42",
        "addressable aggregate agrees in "..mode.." mode")
    check(capture(("%q run %q borrow_main --%s"):format(abc,module,mode))=="42",
        "strict borrow agrees in "..mode.." mode")
    check(capture(("%q run %q array_read 2 --%s"):format(abc,module,mode))=="42",
        "fixed array indexing agrees in "..mode.." mode")
    check(capture(("%q run %q array_read 3 --%s"):format(abc,module,mode)):match("language abort 2"),
        "fixed array bounds abort agrees in "..mode.." mode")
    check(capture(("%q run %q sum_main --%s"):format(abc,module,mode))=="42",
        "sum tag dispatch agrees in "..mode.." mode")
    check(capture(("%q run %q slice_main 2 --%s"):format(abc,module,mode))=="42",
        "borrowed slice storage and call ABI agree in "..mode.." mode")
    check(capture(("%q run %q slice_main 3 --%s"):format(abc,module,mode)):match("language abort 2"),
        "borrowed slice bounds abort agrees in "..mode.." mode")
    check(capture(("%q run %q string_main --%s"):format(abc,module,mode))=="42 2",
        "slice literal, index, and length agree in "..mode.." mode")
end
os.remove(asm);os.remove(module)
-- Profile-5 execution/fixpoint checks are preserved in
-- research/archive/dynamic-layer-before-typed-teardown/mixed-frontend-tests/lowering.lua.
-- Managed IR remains verified above; obsolete profile-5 emission is rejected.

-- Typed SLet callable transport must survive removal of managed Let emission.
-- The capture-free view is passed as a real code/environment pair to a callee.
local typedView=S.View(S.Sig({input(S.U32),input(S.U32)},{S.U32}))
local callable,callLeft,callRight,callResult=I.Value(60),I.Value(61),I.Value(62),I.Value(63)
local applyTyped=I.Fn('apply_typed',I.Body,0,L{input(typedView),input(S.U32),input(S.U32)},L{S.U32},
 L{I.ValueParam(0,callable,typedView),I.ValueParam(1,callLeft,S.U32),I.ValueParam(2,callRight,S.U32)},
 L{I.Indirect(L{callResult},ref(callable,typedView),L{I.ValueArg(ref(callLeft,S.U32)),I.ValueArg(ref(callRight,S.U32))}),I.Return(L{ref(callResult,S.U32)})})
local codeValue,typedResult=I.Value(64),I.Value(65)
local typedMain=I.Fn('typed_main',I.Entry,0,L{},L{S.U32},L{},L{
 I.View(codeValue,typedView,'add',L{},nil),
 I.Call(L{typedResult},'apply_typed',L{I.ValueArg(ref(codeValue,typedView)),I.ValueArg(uint(20)),I.ValueArg(uint(22))}),
 I.Return(L{ref(typedResult,S.U32)})})
local typedArtifact=Compiler.lower({add,applyTyped,typedMain},{profile='slet',exports={'typed_main'}})
check(typedArtifact.profile=='callables','SLet retains the typed callable profile')
check(typedArtifact.assembly:match('CALLI%.A 3 _let_sig') and typedArtifact.assembly:match('TCALL%.A add 3 2'),
 'typed adapters retain checked indirect signatures and explicit tail argument transport')
file=assert(io.open(asm,'wb'));assert(file:write(typedArtifact.assembly));assert(file:close())
check(capture(('%q asm %q -o %q'):format(abc,asm,module))=='','typed callable assembly verifies')
for _,mode in ipairs{'interpreted','compiled','lazy','jit=threaded'} do
 check(capture(('%q run %q typed_main --%s'):format(abc,module,mode))=='42','SLet typed indirect call executes in '..mode)
end
os.remove(asm);os.remove(module)

local floatArtifact = Compiler.lower({floatMain}, {profile = "slet", exports = {"float_main"}})
check(floatArtifact.profile == "memory" and floatArtifact.assembly:match("%.profile memory"),
    "typed f64 selects the GC-free memory profile")
asm, module = base .. "-float.abcasm", base .. "-float.abc"
file = assert(io.open(asm, "wb")); assert(file:write(floatArtifact.assembly)); assert(file:close())
check(capture(("%q asm %q -o %q"):format(abc, asm, module)) == "", "f64 lowering verifies")
for _, mode in ipairs{"interpreted", "compiled", "lazy", "jit=threaded"} do
    check(capture(("%q run %q float_main --%s"):format(abc, module, mode)) ==
        "4 -1 3 0 -1 1 1 0 0 0 1 0 1 0 0",
        "f64 lowering agrees in " .. mode .. " mode")
end
os.remove(asm); os.remove(module)

local letOK,letError = pcall(Compiler.lower,{main, add, sum}, {profile = "let", exports = {"main"}})
check(not letOK and D.is(letError) and letError.code=='dynamic-lowering',
    "Let is not silently reinterpreted as SLet, even for scalar functions")

local record = S.Record {x = S.U32}
local badValue = I.Value(1)
local unsupportedFn = I.Fn("unsupported", I.Body, 0, L{input(record)}, L{record},
    L{I.ValueParam(0, badValue, record)}, L{I.Return(L{ref(badValue, record)})})
local aggregateArtifact=Compiler.lower({unsupportedFn},{profile="slet",exports={"unsupported"}})
check(aggregateArtifact.assembly:match("%.function unsupported 1 1") and aggregateArtifact.assembly:match("RET%.A 1 1"),
    "record inputs and results use the checked aggregate call ABI")

print(("PASS: checked ASDL Ir -> ABC lowering (%d checks)"):format(checks))
