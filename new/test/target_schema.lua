-- Standalone validation of the proposed schema, not a test of a ported compiler.
-- Run: luajit new/test/target_schema.lua
local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
local root = directory .. "../../"
package.path = root .. "?.lua;" .. package.path
local ASDL = require("asdl")
local List = ASDL.List
local file = assert(io.open(root .. "new/target.asdl", "rb"))
local text = assert(file:read("*a")); assert(file:close())
local function context()
    local c = ASDL.NewContext(); c:Define(text); return c
end
local c = context()
local T, I, K = c.Ty, c.IR, c.Identity
local checks = 0
local function check(condition, message)
    assert(condition, message); checks = checks + 1
end

local field = T.Field("x", T.U32)
local record = T.Record("example", List{field})
check(record == T.Record("example", List{field}), "record interning")
check(record ~= T.Record("another-meaning", List{field}), "source meaning survives layout equality")
check(T.Tuple(List{T.U32, T.Bool}) ~= T.Tuple(List{T.Bool, T.U32}), "tuple order")
check(T.Sig(List{T.InValue(T.U32)}, List{T.Unit, T.U32}) ~=
    T.Sig(List{T.InValue(T.U32)}, List{T.U32}), "logical Unit result slots survive")
check(not pcall(T.Tuple, {T.U32}), "ASDL requires List fields")
check(T.Field.kind == nil and I.Call.kind == "Call", "products and variants differ")

local definition = K.Token("definition", 1)
local binding = K.Pos(1, K.UInt(3))
local key = K.Source(definition, List{binding}, List{})
check(key == K.Source(definition, List{K.Pos(1, K.UInt(3))}, List{}), "static key interning")
check(key ~= K.Source(definition, List{K.Pos(1, K.UInt(4))}, List{}), "static values distinguish keys")
local owner = K.Token("meaning", 1)
local left = K.Owner(owner, List{K.Name("left")}, nil)
local right = K.Owner(owner, List{K.Name("right")}, nil)
check(K.Source(definition, List{}, List{left}) ~= K.Source(definition, List{}, List{right}), "owner routes distinguish keys")

local sig = T.Sig(List{T.InValue(T.U32)}, List{T.U32})
local v = I.Value(1)
local decl = I.Decl(v, T.U32)
local fn = I.Function("identity", sig, 0, List{I.ValueInput(decl)}, 1,
    List{I.Block(1, List{}, List{}, I.Return(List{v}))})
local program = I.Program(List{fn}, List{I.FunctionExport("identity", "identity")}, List{})
check(program.functions[1].blocks[1].exit.values[1] == v, "sample program construction")
check(I.Call(List{decl}, "identity", List{I.ValueArg(v)}) ~=
    I.Call(List{decl}, "identity", List{I.ValueArg(v)}), "calls are occurrences, not interned effects")

local S = c.Source
local source_definition = S.Definition(definition, S.Ordered(List{}, S.Lua(function() return 3 end)),
    S.Location("schema-fixture", 1))
local ref = S.Ref(key, List{}, nil)
local plan = S.Inline(ref, List{S.Known(K.UInt(3), nil)})
check(source_definition.shape.terminal.kind == "Lua" and plan.kind == "Inline", "frontend-only definitions and call plans")
check(not pcall(I.Return, List{S.Known(K.UInt(3), nil)}), "frontend values cannot enter IR returns")
check(not pcall(I.Constant, decl, S.RawValue(S.Number(3))), "frontend raw values cannot enter IR constants")
check(not pcall(S.Symbol, "attempt", v, c.Analysis.Unknown), "unknown result type cannot become a symbolic proxy")

local env = T.Env(List{T.Reference(record), T.Saved(T.U32)})
local bundle = I.Bundle(2)
check(I.MakeBundle(bundle, env, List{I.PlaceArg(I.Borrowed(1)), I.ValueArg(v)}).type == env,
    "borrowed and owned bundle slots")
check(not pcall(I.Return, List{I.Borrowed(1)}), "Place is not a return Value")
check(not pcall(I.Construct, decl, List{bundle}), "Bundle is not an aggregate Value")
check(not pcall(T.Record, "bad", List{env}), "bundle environment is not a value field")

local expected = {}
for name in ("Constant UnaryOp BinaryOp Construct Extract Alloc Load Store Call Indirect " ..
    "MakeOwned OwnedEnvironment MakeBundle BundleValue MakeView Check"):gmatch("%S+") do
    expected[name] = true
end
local variants = 0
for class in pairs(I.Instruction.members) do
    if class.kind then
        check(expected[class.kind], "unexpected instruction variant: " .. class.kind)
        expected[class.kind] = nil; variants = variants + 1
    end
end
check(next(expected) == nil and variants == 16, "complete instruction vocabulary")

-- Check actual vendor behavior in an isolated context. Production wrappers must
-- prevent list mutation and install parents before child overrides.
local isolated = context()
check(isolated.Ty.U32 ~= T.U32, "contexts do not share session identities")
local mutable = isolated.Ty.Record("mutable-fixture", List{isolated.Ty.Field("x", isolated.Ty.U32)})
mutable.fields:insert(isolated.Ty.Field("y", isolated.Ty.Bool))
check(#mutable.fields == 2, "vendor interning does not imply immutability")
isolated.IR.Jump.probe = function() return "child" end
isolated.IR.Terminator.probe = function() return "parent" end
local jump = isolated.IR.Jump(isolated.IR.Edge(1, List{}))
check(jump:probe() == "parent", "late parent installation overwrites child override")

print(string.format("target schema: %d checks passed; %d instruction variants; no compiler migration exercised", checks, variants))
