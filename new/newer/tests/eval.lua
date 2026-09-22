-- Evaluator semantics: static results, specialization sharing and source rejections.
local source = debug.getinfo(1, "S").source:sub(2)
package.path = (source:match("^(.*[/\\])") or "./") .. "../?.lua;"
    .. (source:match("^(.*[/\\])") or "./") .. "../?/init.lua;" .. package.path

local wordlet = require("wordlet")
local Eval = require("wordlet.eval")
local Parse = require("wordlet.parse")
local D = require("wordlet.diag")
local C = require("wordlet.cabi")
local A = require("wordlet.ast")
local S = require("wordlet.schema")
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end

local function interpret(entry, args, program)
    return wordlet.interpret{ source = program, name = "t.let", entry = entry, args = args }
end

local function compile(program)
    return wordlet.compile{ source = program, name = "t.let" }
end

local function rejects(code, program, entry, args)
    local ok, err = pcall(function()
        if entry then interpret(entry, args or {}, program) else compile(program) end
    end)
    check(not ok, "expected a rejection (" .. code .. ")")
    check(D.is(err), "expected a diagnostic, got " .. tostring(err))
    check(err.code == code, ("expected %s but got %s"):format(code, err.code))
    check(err.span ~= nil, "rejection should carry a span")
    return err
end

-- Static evaluation ----------------------------------------------------------------------------
check(interpret("affine", { 3, 7, 4 },
    "let affine(a, b, x: U32) :: U32 = a * x + b\nreturn { functions = { affine } }")[1] == 19,
    "affine is 19")
check(interpret("pick", { 0 },
    "let pick(x: U32) :: U32 = if x == 0 then 7 else x * 2\nreturn { functions = { pick } }")[1] == 7,
    "known condition selects one arm")

local divmod = interpret("divmod", { 17, 5 },
    "let divmod(a, b: U32) :: (U32, U32) = do return a / b, a % b end\nreturn { functions = { divmod } }")
check(#divmod == 2 and divmod[1] == 3 and divmod[2] == 2, "two results")

check(interpret("b", { 7 },
    "let a(x: U32) :: U32 = x + 1\nlet b(x: U32) :: U32 = a(x) * 2\nreturn { functions = { b } }")[1] == 16,
    "a call is evaluated statically when every argument is known")
check(interpret("wrap", { 1 },
    "let inc(x: U32) :: U32 = x + 1\nlet wrap(x: U32) :: U32 = inc(41)\nreturn { functions = { wrap } }")[1] == 42,
    "a constant call ignores an unused parameter")
check(interpret("g", { 3, 4 },
    "let g(a, b: U32) :: U32 = if a < b then b - a else a - b\nreturn { functions = { g } }")[1] == 1,
    "comparison and subtraction")
check(interpret("s", { 0 },
    "let s(n: U32) :: U32 = if n == 0 then 0 else n + s(n - 1)\nreturn { functions = { s } }")[1] == 0,
    "static recursion terminates")
check(interpret("x", { 1, 4 }, "let x(a, b: U32) :: U32 = a | b\nreturn { functions = { x } }")[1] == 5,
    "bitwise or")

-- Partial application and specialization --------------------------------------------------------
local session = Eval.session()
session:compile(Parse.source("let scale(k, x: U32) :: U32 = k * x\n"
    .. "let use(x: U32) :: U32 = scale(3)(x) + scale(3)(x) + scale(5)(x)\n"
    .. "return { functions = { use } }", "s.let"))
check(#session.order == 3, "two static specializations of scale plus the entry, not three")
local bodies = {}
for _, instance in ipairs(session.order) do bodies[#bodies + 1] = instance.fn.body end
check(#bodies == 3, "one body per distinct static key")

local shared = Eval.session()
shared:compile(Parse.source("let inc(x: U32) :: U32 = x + 1\n"
    .. "let use(x: U32) :: U32 = inc(x) + inc(x)\nreturn { functions = { use } }", "s.let"))
check(#shared.order == 2, "a helper called twice in one caller has one body")

-- Records, methods and stores ------------------------------------------------------------------
local RECORDS = [==[
let P = { x: U32, y: U32 }
let build(a, b: U32) :: U32 = do
  let p = P { x = a, y = b }
  return p.x * 1000 + p.y
end
let bump(p: P) :: U32 = do p.x += 1 return p.x end
let caller(n: U32) :: U32 = do
  let p = P { x = n, y = 5 }
  let raised = bump(p)
  return raised * 1000 + p.x * 10 + p.y
end
let pair(a: U32) :: P = P { x = a, y = a + 1 }
let use(a: U32) :: U32 = do let q = pair(a) return q.x * 10 + q.y end
let alias(n: U32) :: U32 = do
  let p = P { x = n, y = 0 }
  let q = p
  q.y = 9
  return p.x * 10 + p.y
end
let compound(n: U32) :: U32 = do
  let p = P { x = n, y = 3 }
  p.x += 4
  p.y *= 2
  p.x -= 1
  return p.x * 100 + p.y
end
return { types = { P }, functions = { build, bump, caller, pair, use, alias, compound } }
]==]
check(interpret("build", { 3, 4 }, RECORDS)[1] == 3004, "record construction and field reads")
check(interpret("caller", { 7 }, RECORDS)[1] == 8075, "a record argument is a copy, not an alias")
check(interpret("use", { 9 }, RECORDS)[1] == 100, "a returned record's fields are readable")
check(interpret("alias", { 5 }, RECORDS)[1] == 59, "a local alias keeps its instance, so writes are visible")
check(interpret("compound", { 10 }, RECORDS)[1] == 1306, "compound stores read once and write once")
local U32 = require("wordletkit.u32")
check(interpret("build", { 0, 0 }, RECORDS)[1] == 0, "zero fields")
check(interpret("build", { 4294967295, 1 }, RECORDS)[1] == U32.add(U32.mul(4294967295, 1000), 1),
    "record field arithmetic wraps like any other U32")

local METHODS = [==[
let Counter = {
  value: U32,
  inc() :: U32 = do value += 1 return value end,
  add(n: U32) :: U32 = do value += n return value end,
}
let observe(n: U32, change: Bool) :: (U32, U32) = do
  let c = Counter { value = n }
  let old = c.value
  if change then c.inc() end
  return old, c.value
end
let twice(n: U32) :: U32 = do
  let c = Counter { value = n }
  c.inc()
  c.add(5)
  return c.value
end
let snapshot(n: U32) :: U32 = do
  let c = Counter { value = n }
  let a = c.value
  c.inc()
  let b = c.value
  return a * 100 + b
end
return { types = { Counter }, functions = { observe, twice, snapshot } }
]==]
local observed = interpret("observe", { 7, true }, METHODS)
check(observed[1] == 7 and observed[2] == 8, "a method mutates its receiver and an earlier read is a snapshot")
check(interpret("observe", { 7, false }, METHODS)[2] == 7, "the untaken arm performs no mutation")
check(interpret("twice", { 1 }, METHODS)[1] == 7, "several method calls on one instance")
check(interpret("snapshot", { 4 }, METHODS)[1] == 405, "reads before and after a call are distinct")
check(interpret("observe", { 4294967295, true }, METHODS)[2] == 0, "receiver arithmetic wraps")

-- Reading a receiver field is not a compile-time constant when the receiver is runtime storage.
local STATIC_FIELD = "let C = { v: U32, get() :: U32 = v }\n"
    .. "let f(x: U32) :: U32 = do let c = C { v = x } return c.get() end\n"
    .. "return { types = { C }, functions = { f } }"
check(interpret("f", { 12 }, STATIC_FIELD)[1] == 12, "a runtime receiver field is loaded, not folded")

-- Closures and higher-order words ---------------------------------------------------------------
local CLOSURES = [==[
let apply(f: U32 :: U32, x: U32) :: U32 = f(x)
let twice(f: U32 :: U32, x: U32) :: U32 = f(f(x))
let make_adder(n: U32) = |x: U32| -> n + x
let run(n, x: U32) :: U32 = do
  let add = make_adder(n)
  return apply(add, x)
end
let inline(x: U32) :: U32 = twice(|y: U32| -> y + 1, x)
let compose(a, b, x: U32) :: U32 = do
  let f = make_adder(a)
  let g = make_adder(b)
  return apply(f, apply(g, x))
end
let C = { v: U32, mk() = |x: U32| -> v + x }
let snap(n: U32) :: U32 = do
  let c = C { v = n }
  let f = c.mk()
  c.v += 5
  return f(100)
end
return { types = { C }, functions = { run, inline, compose, snap } }
]==]
check(interpret("run", { 5, 7 }, CLOSURES)[1] == 12, "a returned closure is called through its environment")
check(interpret("run", { 0, 0 }, CLOSURES)[1] == 0, "a zero capture still works")
check(interpret("inline", { 3 }, CLOSURES)[1] == 5, "an inline lambda specialises at its call site")
check(interpret("compose", { 3, 4, 10 }, CLOSURES)[1] == 17, "two closures with different captures")
check(interpret("snap", { 1 }, CLOSURES)[1] == 101,
    "a captured field is a snapshot, so a later store does not change it")

-- Code identity is per syntactic lambda, and the environment is a runtime input.
local shareSession = Eval.session()
shareSession:compile(Parse.source("let twice(f: U32 :: U32, x: U32) :: U32 = f(f(x))\n"
    .. "let a(x: U32) :: U32 = twice(|y: U32| -> y + 1, x)\n"
    .. "let b(x: U32) :: U32 = twice(|y: U32| -> y + 1, x)\n"
    .. "return { functions = { a, b } }", "s.let"))
-- a, b, twice specialised for each distinct lambda, and each lambda once
check(#shareSession.order == 6, "identical-looking lambdas are still distinct code identities")
local closureBodies = 0
for _, instance in ipairs(shareSession.order) do
    if instance.plan then closureBodies = closureBodies + 1 end
end
check(closureBodies == 2, "each syntactic lambda compiles once regardless of call sites")

local retSession = Eval.session()
retSession:compile(Parse.source("let apply(f: U32 :: U32, x: U32) :: U32 = f(x)\n"
    .. "let make_adder(n: U32) = |x: U32| -> n + x\n"
    .. "let run(n, x: U32) :: U32 = do let add = make_adder(n) return apply(add, x) end\n"
    .. "return { functions = { run } }", "r.let"))
check(#retSession.order == 4, "a returned closure has one body and one caller specialisation")
local sawOwnedInput = false
for _, instance in ipairs(retSession.order) do
    for _, input in ipairs(instance.fn.inputs) do
        if S.isOwned(input.type) then sawOwnedInput = true end
    end
end
check(sawOwnedInput, "the callable travels as a by-value environment input")

-- Rejections ---; non-tail recursion stays a call -------------------------------
local loopSession = Eval.session()
loopSession:compile(Parse.source("let sum_to(n, acc: U32) :: U32 = if n == 0 then acc else sum_to(n - 1, acc + n)\n"
    .. "return { functions = { sum_to } }", "l.let"))
check(#loopSession.order == 1, "a tail self-call reuses the instance it is defined in")
local loopIR = A.dump(loopSession.order[1].fn)
check(loopIR:find("Loop", 1, true) ~= nil and loopIR:find("Next", 1, true) ~= nil,
    "the body carries a Loop with a back edge")
check(loopIR:find("Call", 1, true) == nil, "the tail call emits no call at all")

local recSession = Eval.session()
recSession:compile(Parse.source("let f(a: U32) :: U32 = if a == 0 then 1 else a * f(a - 1)\n"
    .. "return { functions = { f } }", "r.let"))
check(A.dump(recSession.order[1].fn):find("Loop", 1, true) == nil,
    "recursion outside tail position stays an ordinary call")

-- A conditional in tail position loops from either arm.
local bothSession = Eval.session()
bothSession:compile(Parse.source("let count(n: U32) :: U32 =\n"
    .. "  if n == 0 then 0 else if n == 1 then count(0) else count(n - 2)\n"
    .. "return { functions = { count } }", "b.let"))
check(A.dump(bothSession.order[1].fn):find("Loop", 1, true) ~= nil, "either tail arm may loop")

-- A tail call with different static arguments is a different instance, so it is a real call.
local staticSession = Eval.session()
staticSession:compile(Parse.source("let scale(k, x: U32) :: U32 = if k == 0 then x else scale(0, x + 1)\n"
    .. "let five(x: U32) :: U32 = scale(5, x)\nreturn { functions = { five } }", "s.let"))
check(#staticSession.order >= 2, "changing a static argument creates a new instance")

-- Rejections ------------------------------------------------------------------------------------
rejects("unknown-name", "let f(x: U32) = y\nreturn { functions = { f } }")
rejects("arity", "let f(a, b: U32) :: U32 = a + b\nlet g(x: U32) :: U32 = f(1, 2, 3)\nreturn { functions = { g } }")
rejects("callable-required", "let f(x: U32) :: U32 = x\nlet g(x: U32) :: U32 = f(1)(2)\nreturn { functions = { g } }")
rejects("type-mismatch", "let f(x: U32) :: U32 = x + true\nreturn { functions = { f } }")
rejects("division-zero", "let f(x: U32) :: U32 = x / 0\nreturn { functions = { f } }")
rejects("recursive-result", "let f(x: U32) = if x == 0 then 0 else f(x - 1)\nreturn { functions = { f } }")
-- A block must end in `return`, so an unterminated block is a parse error rather than a silent
-- fall-through; the evaluator keeps the defensive check anyway.
rejects("parse", "let f(x: U32) :: U32 = do let y = x + 1 end\nreturn { functions = { f } }")
rejects("duplicate", "let f(x: U32) :: U32 = do let y = x let y = x return y end\nreturn { functions = { f } }")
rejects("unknown-name", "return { functions = { missing } }")
rejects("function-required", "let x = 3\nreturn { functions = { x } }")
rejects("parse", "let f(x: U32) = x\nreturn { functions = { f }")
rejects("initializer-cycle", "let a = b\nlet b = a\nlet f(x: U32) :: U32 = a + x\nreturn { functions = { f } }")
rejects("static-required", "let scale(k, x: U32) :: U32 = k * x\n"
    .. "let use(x: U32) :: U32 = do let g = scale(x) return g(1) end\nreturn { functions = { use } }")
rejects("branch-result", "let f(x: U32) :: U32 = if x == 0 then 1 else true\nreturn { functions = { f } }")
rejects("static-required", "let P = { x: U32, y: U32 }\nlet f(a: U32) :: U32 = do"
    .. " let q = P { x = a } let z = q.y return z end\nreturn { functions = { f } }")
rejects("not-a-place", "let P = { x: U32 }\nlet f(a: U32) :: U32 = do"
    .. " let p = P { x = a }\n let n = 3\n n = 4\n return p.x end\nreturn { functions = { f } }")
rejects("type-mismatch", RECORDS, "bump", { 7 })
-- A captured record instance or method retains a place, which needs a non-retaining environment.
rejects("borrowed-capture", "let C = { v: U32, inc() :: U32 = v }\n"
    .. "let f(x: U32) :: U32 = do let c = C { v = x } let g = |y: U32| -> c.inc() return g(1) end\n"
    .. "return { types = { C }, functions = { f } }")
-- A callable with no known code needs a function-pointer ABI.
rejects("opaque-callable", "let apply(f: U32 :: U32, x: U32) :: U32 = f(x)\n"
    .. "return { functions = { apply } }")
rejects("lambda-annotation", "let twice(f: U32 :: U32, x: U32) :: U32 = f(f(x))\n"
    .. "let a(x: U32) :: U32 = twice(|y| -> y + 1, x)\nreturn { functions = { a } }")
rejects("callable-shape", "let apply(f: U32 :: U32, x: U32) :: U32 = f(x)\n"
    .. "let bad(x: U32) :: U32 = apply(|y: U32| -> true, x)\nreturn { functions = { bad } }")
rejects("unknown-member", "let P = { x: U32 }\nlet f(a: U32) :: U32 = do"
    .. " let p = P { x = a } return p.z end\nreturn { functions = { f } }")
rejects("duplicate", "let P = { x: U32 }\nlet f(a: U32) :: U32 = do"
    .. " let p = P { x = a, x = 1 } return p.x end\nreturn { functions = { f } }")
rejects("module-mutable-capture", "let P = { x: U32 }\nlet m = P { x = 1 }\n"
    .. "let f(a: U32) :: U32 = do m.x += a return m.x end\nreturn { functions = { f } }")

-- The interpreter refuses an unsaturated entry rather than inventing a value.
local ok, err = pcall(wordlet.interpret, { source = "let f(a, b: U32) :: U32 = a + b\n"
    .. "return { functions = { f } }", entry = "f", args = { 1 } })
check(not ok and D.is(err) and err.code == "arity", "undersaturated entry rejects instead of returning a word")

-- C naming is injective, so two distinct source names cannot collide.
check(C.escape("sum_to") == "sum_5Fto" and C.functionName("sum_to") == "wordlet_sum_5Fto",
    "underscore is escaped")
check(C.escape("a_b") ~= C.escape("aXbX") or C.escape("a-") ~= C.escape("a_"),
    "escaping distinguishes distinct spellings")
check(C.escape("a") ~= C.escape("A"), "case is preserved")

-- Exported aliases share one body and forward.
local aliasArtifact = compile("let inc(x: U32) :: U32 = x + 1\nreturn { functions = { a = inc, b = inc } }")
check(#aliasArtifact:exports() == 2, "both aliases are exported")
local aliasUnit = aliasArtifact:unit()
check(aliasUnit:find("wordlet_a", 1, true) and aliasUnit:find("wordlet_b", 1, true),
    "aliases appear in the generated C")

-- Determinism: identical input gives byte-identical output.
local one = compile("let f(x: U32) :: U32 = x * 3 + 1\nreturn { functions = { f } }"):unit()
local two = compile("let f(x: U32) :: U32 = x * 3 + 1\nreturn { functions = { f } }"):unit()
check(one == two, "emission is deterministic")

print(("PASS: evaluator semantics (%d checks)"):format(checks))
