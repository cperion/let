-- Compile-time evaluation must cross the public ABC VM boundary, never a Lua evaluator.
local source = debug.getinfo(1, "S").source:sub(2)
local here = source:match("^(.*[/\\])") or "./"
local root = here .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. root .. "../build/?.lua;" .. package.path

local Compiler = require("let.compiler")
local Stage = require("let.stage")
local D = require("let.diag")
local S = require("let.schema")
local Int = require("int64")
require("let.ir")
local I, L = S.Ir, S.ASDL.List
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end
local function input(ty) return S.inValue(ty) end
local function uint(n, ty) return I.Const(ty or S.u32, I.UInt(n)) end
local function ref(value, ty) return I.Ref(value, ty) end

local argument = I.Value(1)
local calc = I.Fn("calc", I.Entry, 0, L{input(S.u32)}, L{S.u32},
    L{I.ValueParam(0, argument, S.u32)},
    L{I.Return(L{I.Bin(I.Mul, ref(argument, S.u32), uint(2), S.u32)})})

local huge = I.Fn("huge", I.Entry, 0, L{}, L{S.u64}, L{},
    L{I.Return(L{I.Const(S.u64, I.UInt64(0xffffffff, 0xffffffff))})})
local multiple = I.Fn("multiple", I.Entry, 0, L{}, L{S.bool, S.u32}, L{},
    L{I.Return(L{I.Const(S.bool, I.Boolean(true)), uint(42)})})

local trapStmt = I.Trap(I.Const(S.bool, I.Boolean(true)), "index-range")
trapStmt.span = {file = "static-test.let", line = 12}
local failing = I.Fn("failing", I.Entry, 0, L{}, L{S.u32}, L{},
    L{trapStmt, I.Return(L{uint(0)})})

-- Deliberately non-tail recursion: the pending addition is the saved continuation.
local n, recursiveResult = I.Value(1), I.Value(2)
local recurse = I.Fn("recurse", I.Entry, 0, L{input(S.u32)}, L{S.u32},
    L{I.ValueParam(0, n, S.u32)}, L{
        I.If(I.Bin(I.Eq, ref(n, S.u32), uint(0), S.bool),
            L{I.Return(L{uint(0)})},
            L{
                I.Call(L{recursiveResult}, "recurse",
                    L{I.ValueArg(I.Bin(I.Sub, ref(n, S.u32), uint(1), S.u32))}),
                I.Return(L{I.Bin(I.Add, ref(recursiveResult, S.u32), uint(1), S.u32)}),
            }),
    })

local modules, events = {}, {}
for _, mode in ipairs{"interpreted", "eager", "lazy"} do
    local result = Compiler.stage({calc}, {
        profile = "slet", entry = "calc", mode = mode, arguments = {21},
        progress = function(event) events[#events + 1] = event.phase .. ":" .. event.binding end,
    })
    check(result.phase == "executed" and Int.format(result.cells[1], false) == "42",
        "known computation runs through the " .. mode .. " VM")
    check(result.values[1].type == S.u32, "static result retains its semantic type")
    modules[#modules + 1] = result.module
end
check(modules[1] == modules[2] and modules[2] == modules[3],
    "VM policy does not change emitted module bytes")
check(#events == 6 and events[1] == "start:calc" and events[2] == "finish:calc",
    "static execution reports binding progress")

local exact = Compiler.stage({huge}, {profile = "slet", entry = "huge", mode = "interpreted"})
check(Int.format(exact.cells[1], false) == "18446744073709551615",
    "static cells cross the VM boundary without Lua-number truncation")
local pair = Compiler.stage({multiple}, {profile = "slet", entry = "multiple", mode = "lazy"})
check(#pair.values == 2 and pair.values[1].type == S.bool and pair.values[2].type == S.u32,
    "multiple VM results retain their semantic types")
check(Int.format(pair.cells[1], false) == "1" and Int.format(pair.cells[2], false) == "42",
    "boolean and integer results are decoded as raw exact cells")
local sx, sy = I.Value(1), I.Value(2)
local sum = I.Fn("sum", I.Entry, 0, L{input(S.u32), input(S.u32)}, L{S.u32},
    L{I.ValueParam(0, sx, S.u32), I.ValueParam(1, sy, S.u32)},
    L{I.Return(L{I.Bin(I.Add, ref(sx, S.u32), ref(sy, S.u32), S.u32)})})
local specialized = Compiler.specialize({sum, multiple}, {
    profile = "slet", entry = "sum", name = "add42", known = {[2] = pair.values[2]},
})
check(specialized.phase == "specialized" and Compiler.optimize(specialized.module) == specialized.module,
    "VM-produced values drive deterministic residual specialization through abc-opt")
local specializedPath = os.tmpname() .. ".abc"
local specializedFile = assert(io.open(specializedPath, "wb")); assert(specializedFile:write(specialized.module)); assert(specializedFile:close())
local dis = assert(io.popen(string.format("%q dis %q", root .. "../build/abc", specializedPath), "r")); local listing = dis:read("*a")
check(dis:close() and listing:match("ADDI_A%s+42"),
    "known VM cells become constants in deterministic shared residual output")
for _, mode in ipairs({"interpreted", "compiled", "lazy"}) do
    local run = assert(io.popen(string.format("%q run %q add42 8 --%s", root .. "../build/abc", specializedPath, mode), "r"))
    local output = run:read("*a")
    check(run:close() and output:match("^50%s*$"), "specialized residual agrees in " .. mode .. " mode")
end
os.remove(specializedPath)

local ok, diagnostic = pcall(Compiler.stage, {failing},
    {profile = "slet", entry = "failing", mode = "lazy"})
check(not ok and D.is(diagnostic) and diagnostic.code == "static-index-range",
    "VM language abort becomes a compiler rejection")
check(diagnostic.ir == trapStmt and diagnostic.bytecodeOffset ~= nil and diagnostic.assemblyLine ~= nil,
    "VM abort maps back to the originating typed IR node")
check(diagnostic.span == trapStmt.span, "VM abort retains the source span hook")

ok, diagnostic = pcall(Compiler.stage, {recurse},
    {profile = "slet", entry = "recurse", mode = "interpreted", arguments = {100}, stackCells = 8})
check(not ok and D.is(diagnostic) and diagnostic.kind == "resource" and diagnostic.code == "static-stack",
    "a genuine VM stack limit is a resource failure: " .. tostring(diagnostic))

ok, diagnostic = pcall(Compiler.stage, {calc},
    {profile = "slet", entry = "calc", arguments = {1}})
check(not ok and D.is(diagnostic) and diagnostic.code == "execution-policy",
    "the host must select the static VM execution policy")

ok, diagnostic = pcall(Compiler.stage, {calc},
    {profile = "slet", entry = "calc", mode = "interpreted", arguments = {1}, fuel = 100})
check(not ok and D.is(diagnostic) and diagnostic.code == "static-option",
    "compile-time execution rejects semantic fuel and instruction-budget options")

ok, diagnostic = pcall(Stage.execute,
    {profile = "foreign", assembly = ".profile foreign\n.extern host - i\nFCALL host", lineMap = {}},
    {calc}, {entry = "calc", mode = "interpreted", arguments = {1}})
check(not ok and D.is(diagnostic) and diagnostic.code == "static-foreign",
    "foreign effects are unavailable to compile-time execution")

print(string.format("PASS: VM-backed compile-time execution (%d checks)", checks))
