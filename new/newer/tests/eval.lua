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
    "let affine(a, b, x: U32) : U32 = a * x + b\nreturn { functions = { affine } }")[1] == 19,
    "affine is 19")
check(interpret("pick", { 0 },
    "let pick(x: U32) : U32 = if x == 0 then 7 else x * 2\nreturn { functions = { pick } }")[1] == 7,
    "known condition selects one arm")

local divmod = interpret("divmod", { 17, 5 },
    "let divmod(a, b: U32) : (U32, U32) = do return a / b, a % b end\nreturn { functions = { divmod } }")
check(#divmod == 2 and divmod[1] == 3 and divmod[2] == 2, "two results")

check(interpret("b", { 7 },
    "let a(x: U32) : U32 = x + 1\nlet b(x: U32) : U32 = a(x) * 2\nreturn { functions = { b } }")[1] == 16,
    "a call is evaluated statically when every argument is known")
check(interpret("wrap", { 1 },
    "let inc(x: U32) : U32 = x + 1\nlet wrap(x: U32) : U32 = inc(41)\nreturn { functions = { wrap } }")[1] == 42,
    "a constant call ignores an unused parameter")
check(interpret("g", { 3, 4 },
    "let g(a, b: U32) : U32 = if a < b then b - a else a - b\nreturn { functions = { g } }")[1] == 1,
    "comparison and subtraction")
check(interpret("s", { 0 },
    "let s(n: U32) : U32 = if n == 0 then 0 else n + s(n - 1)\nreturn { functions = { s } }")[1] == 0,
    "static recursion terminates")
check(interpret("x", { 1, 4 }, "let x(a, b: U32) : U32 = a | b\nreturn { functions = { x } }")[1] == 5,
    "bitwise or")

-- Partial application and specialization --------------------------------------------------------
local session = Eval.session()
session:compile(Parse.source("let scale(k, x: U32) : U32 = k * x\n"
    .. "let use(x: U32) : U32 = scale(3)(x) + scale(3)(x) + scale(5)(x)\n"
    .. "return { functions = { use } }", "s.let"))
check(#session.order == 3, "two static specializations of scale plus the entry, not three")
local bodies = {}
for _, instance in ipairs(session.order) do bodies[#bodies + 1] = instance.fn.body end
check(#bodies == 3, "one body per distinct static key")

local shared = Eval.session()
shared:compile(Parse.source("let inc(x: U32) : U32 = x + 1\n"
    .. "let use(x: U32) : U32 = inc(x) + inc(x)\nreturn { functions = { use } }", "s.let"))
check(#shared.order == 2, "a helper called twice in one caller has one body")

-- Records, methods and stores ------------------------------------------------------------------
local RECORDS = [==[
let P = { x: U32, y: U32 }
let build(a, b: U32) : U32 = do
  let p = P { x = a, y = b }
  return p.x * 1000 + p.y
end
let bump(p: P) : U32 = do p.x += 1 return p.x end
let caller(n: U32) : U32 = do
  let p = P { x = n, y = 5 }
  let raised = bump(p)
  return raised * 1000 + p.x * 10 + p.y
end
let pair(a: U32) : P = P { x = a, y = a + 1 }
let use(a: U32) : U32 = do let q = pair(a) return q.x * 10 + q.y end
let alias(n: U32) : U32 = do
  let p = P { x = n, y = 0 }
  let q = p
  q.y = 9
  return p.x * 10 + p.y
end
let compound(n: U32) : U32 = do
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
  inc() : U32 = do value += 1 return value end,
  add(n: U32) : U32 = do value += n return value end,
}
let observe(n: U32, change: Bool) : (U32, U32) = do
  let c = Counter { value = n }
  let old = c.value
  if change then c.inc() end
  return old, c.value
end
let twice(n: U32) : U32 = do
  let c = Counter { value = n }
  c.inc()
  c.add(5)
  return c.value
end
let snapshot(n: U32) : U32 = do
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
local STATIC_FIELD = "let C = { v: U32, get() : U32 = v }\n"
    .. "let f(x: U32) : U32 = do let c = C { v = x } return c.get() end\n"
    .. "return { types = { C }, functions = { f } }"
check(interpret("f", { 12 }, STATIC_FIELD)[1] == 12, "a runtime receiver field is loaded, not folded")

-- Closures and higher-order words ---------------------------------------------------------------
local CLOSURES = [==[
let apply(f: (U32): U32, x: U32) : U32 = f(x)
let twice(f: (U32): U32, x: U32) : U32 = f(f(x))
let make_adder(n: U32) = |x: U32| -> n + x
let run(n, x: U32) : U32 = do
  let add = make_adder(n)
  return apply(add, x)
end
let inline(x: U32) : U32 = twice(|y: U32| -> y + 1, x)
let compose(a, b, x: U32) : U32 = do
  let f = make_adder(a)
  let g = make_adder(b)
  return apply(f, apply(g, x))
end
let C = { v: U32, mk() = |x: U32| -> v + x }
let snap(n: U32) : U32 = do
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
shareSession:compile(Parse.source("let twice(f: (U32): U32, x: U32) : U32 = f(f(x))\n"
    .. "let a(x: U32) : U32 = twice(|y: U32| -> y + 1, x)\n"
    .. "let b(x: U32) : U32 = twice(|y: U32| -> y + 1, x)\n"
    .. "return { functions = { a, b } }", "s.let"))
-- a, b, twice specialised for each distinct lambda, and each lambda once
check(#shareSession.order == 6, "identical-looking lambdas are still distinct code identities")
local closureBodies = 0
for _, instance in ipairs(shareSession.order) do
    if instance.plan then closureBodies = closureBodies + 1 end
end
check(closureBodies == 2, "each syntactic lambda compiles once regardless of call sites")

local retSession = Eval.session()
retSession:compile(Parse.source("let apply(f: (U32): U32, x: U32) : U32 = f(x)\n"
    .. "let make_adder(n: U32) = |x: U32| -> n + x\n"
    .. "let run(n, x: U32) : U32 = do let add = make_adder(n) return apply(add, x) end\n"
    .. "return { functions = { run } }", "r.let"))
check(#retSession.order == 4, "a returned closure has one body and one caller specialisation")
local sawOwnedInput = false
for _, instance in ipairs(retSession.order) do
    for _, input in ipairs(instance.fn.inputs) do
        if S.isOwned(input.type) then sawOwnedInput = true end
    end
end
check(sawOwnedInput, "the callable travels as a by-value environment input")

-- Contextual typing: a signature requirement supplies a lambda's missing parameter types -------
local CONTEXTUAL = [==[
let twice(f: (U32): U32, x: U32): U32 = f(f(x))
let adder(n: U32): (U32): U32 = |x| -> x + n
let inc: (U32): U32 = |x| -> x + 1
let use(n, x: U32): U32 = do
  let f = adder(n)
  return twice(f, x) + inc(x)
end
let inline(x: U32): U32 = twice(|y| -> y * 2, x)
let capture(x: U32): U32 = twice(|y| -> y + x, 1)
return { functions = { use, inline, capture } }
]==]
check(interpret("use", { 3, 4 }, CONTEXTUAL)[1] == 15,
    "a lambda argument, a signature result and a declared callable binding all infer")
check(interpret("inline", { 5 }, CONTEXTUAL)[1] == 20, "an unannotated lambda argument takes its type")
check(interpret("capture", { 10 }, CONTEXTUAL)[1] == 21, "a contextually typed lambda may capture")

rejects("lambda-annotation", "let g = |x| -> x + 1\nlet f(y: U32): U32 = g(y)\nreturn { functions = { f } }")
rejects("callable-shape", "let twice(f: (U32): U32, x: U32): U32 = f(f(x))\n"
    .. "let a(x: U32): U32 = twice(|y, z: U32| -> y + z + x, 1)\nreturn { functions = { a } }")
rejects("callable-shape", "let apply(f: (U32): U32, x: U32): U32 = f(x)\n"
    .. "let a(x: U32): U32 = apply(|y: U32| -> true, x)\nreturn { functions = { a } }")
-- Two different lambdas in one conditional have different code identities, so no single callable
-- type describes the result; a tagged callable would need a variant representation.
rejects("callable-branch", "let pick(c: Bool): (U32): U32 = if c then |x: U32| -> x + 1 else |x: U32| -> x + 2\n"
    .. "return { functions = { pick } }")

-- Borrowed captures: a captured receiver is a place, not a copy --------------------------------
local BORROWED = [==[
let Counter = {
  value: U32,
  bump(): U32 = do value += 1 return value end,
}
let local_bumps(n: U32): U32 = do
  let c = Counter { value = n }
  let f = |k: U32| -> c.bump() + k
  return f(1) + f(2)
end
let method_view(n: U32): U32 = do
  let c = Counter { value = n }
  let g = c.bump
  let h = |u: U32| -> g() + u
  return h(10)
end
let read_through(n: U32): U32 = do
  let c = Counter { value = n }
  let peek = |u: U32| -> c.value + u
  c.value += 5
  return peek(100)
end
return { types = { Counter }, functions = { local_bumps, method_view, read_through } }
]==]
check(interpret("local_bumps", { 5 }, BORROWED)[1] == 16, "a captured receiver mutates through the closure")
check(interpret("method_view", { 5 }, BORROWED)[1] == 16, "a captured method view keeps its receiver")
check(interpret("read_through", { 1 }, BORROWED)[1] == 106,
    "a borrowed receiver is live, unlike a captured field snapshot")

rejects("borrow-escape", "let C = { v: U32, bump(): U32 = v }\n"
    .. "let bad(n: U32): (U32): U32 = do let c = C { v = n } return |k: U32| -> c.bump() + k end\n"
    .. "return { types = { C }, functions = { bad } }")

-- Opaque runtime callables: the invocation-pointer ABI -----------------------------------------
local EXTERNAL = [==[
let apply(f: (U32): U32, x: U32): U32 = f(x)
let twice_apply(f: (U32): U32, x: U32): U32 = apply(f, apply(f, x))
let compose(f: (U32): U32, g: (U32): U32, x: U32): U32 = f(g(x))
let invoke(f: (U32): (), x: U32): U32 = do f(x) return x end
let internal(x: U32): U32 = apply(|y: U32| -> y + 1, x)
return { functions = { apply, twice_apply, compose, invoke, internal } }
]==]
-- An exported callable parameter has no call site, so it becomes an opaque view.
local externalArtifact = wordlet.compile{ source = EXTERNAL, name = "external.let" }
local externalUnit = externalArtifact:unit()
check(externalUnit:find("typedef struct wordletview_1", 1, true) ~= nil, "a view struct is emitted")
check(externalUnit:find("(*invoke)(const void *, uint32_t)", 1, true) ~= nil, "the view carries an invoke pointer")
check(externalUnit:find(".invoke(", 1, true) ~= nil, "the opaque call goes through the pointer")
check(#externalArtifact:exports() == 5, "the higher-order functions are exportable")

local externalSession = Eval.session()
externalSession:compile(Parse.source(EXTERNAL, "external.let"))
local viewInputs, indirectInstances = 0, 0
for _, instance in ipairs(externalSession.order) do
    for _, input in ipairs(instance.fn.inputs) do
        if S.isView(input.type) then viewInputs = viewInputs + 1 end
    end
    if A.dump(instance.fn):find("Indirect", 1, true) then indirectInstances = indirectInstances + 1 end
end
check(viewInputs == 5, "each opaque callable parameter is a view input")
-- `apply`, `compose` and `invoke` call through the pointer; `twice_apply` instead forwards the
-- view to `apply`, which is known code, so that call stays direct.
check(indirectInstances == 3, "a body calls indirectly exactly when the callee is opaque")
check(interpret("internal", { 4 }, EXTERNAL)[1] == 5,
    "a call with known code still specialises to a direct call")

-- Tail self-calls become loops; non-tail recursion stays a call -------------------------------
local loopSession = Eval.session()
loopSession:compile(Parse.source("let sum_to(n, acc: U32) : U32 = if n == 0 then acc else sum_to(n - 1, acc + n)\n"
    .. "return { functions = { sum_to } }", "l.let"))
check(#loopSession.order == 1, "a tail self-call reuses the instance it is defined in")
local loopIR = A.dump(loopSession.order[1].fn)
check(loopIR:find("Loop", 1, true) ~= nil and loopIR:find("Next", 1, true) ~= nil,
    "the body carries a Loop with a back edge")
check(loopIR:find("Call", 1, true) == nil, "the tail call emits no call at all")

local recSession = Eval.session()
recSession:compile(Parse.source("let f(a: U32) : U32 = if a == 0 then 1 else a * f(a - 1)\n"
    .. "return { functions = { f } }", "r.let"))
check(A.dump(recSession.order[1].fn):find("Loop", 1, true) == nil,
    "recursion outside tail position stays an ordinary call")

-- A conditional in tail position loops from either arm.
local bothSession = Eval.session()
bothSession:compile(Parse.source("let count(n: U32) : U32 =\n"
    .. "  if n == 0 then 0 else if n == 1 then count(0) else count(n - 2)\n"
    .. "return { functions = { count } }", "b.let"))
check(A.dump(bothSession.order[1].fn):find("Loop", 1, true) ~= nil, "either tail arm may loop")

-- A tail call with different static arguments is a different instance, so it is a real call.
local staticSession = Eval.session()
staticSession:compile(Parse.source("let scale(k, x: U32) : U32 = if k == 0 then x else scale(0, x + 1)\n"
    .. "let five(x: U32) : U32 = scale(5, x)\nreturn { functions = { five } }", "s.let"))
check(#staticSession.order >= 2, "changing a static argument creates a new instance")

-- Contextual typing: a signature requirement supplies a lambda's missing parameter types -------
local CONTEXTUAL = [==[
let twice(f: (U32): U32, x: U32): U32 = f(f(x))
let adder(n: U32): (U32): U32 = |x| -> x + n
let inc: (U32): U32 = |x| -> x + 1
let use(n, x: U32): U32 = do
  let f = adder(n)
  return twice(f, x) + inc(x)
end
let inline(x: U32): U32 = twice(|y| -> y * 2, x)
let capture(x: U32): U32 = twice(|y| -> y + x, 1)
return { functions = { use, inline, capture } }
]==]
check(interpret("use", { 3, 4 }, CONTEXTUAL)[1] == 15,
    "a lambda argument, a signature result and a declared callable binding all infer")
check(interpret("inline", { 5 }, CONTEXTUAL)[1] == 20, "an unannotated lambda argument takes its type")
check(interpret("capture", { 10 }, CONTEXTUAL)[1] == 21, "a contextually typed lambda may capture")

rejects("lambda-annotation", "let g = |x| -> x + 1\nlet f(y: U32): U32 = g(y)\nreturn { functions = { f } }")
rejects("callable-shape", "let twice(f: (U32): U32, x: U32): U32 = f(f(x))\n"
    .. "let a(x: U32): U32 = twice(|y, z: U32| -> y + z + x, 1)\nreturn { functions = { a } }")
rejects("callable-shape", "let apply(f: (U32): U32, x: U32): U32 = f(x)\n"
    .. "let a(x: U32): U32 = apply(|y: U32| -> true, x)\nreturn { functions = { a } }")
-- Two different lambdas in one conditional have different code identities, so no single callable
-- type describes the result; a tagged callable would need a variant representation.
rejects("callable-branch", "let pick(c: Bool): (U32): U32 = if c then |x: U32| -> x + 1 else |x: U32| -> x + 2\n"
    .. "return { functions = { pick } }")

-- Partial application of a closure ------------------------------------------------------------
local PARTIAL = [==[
let add = |a, b: U32| -> a + b
let add5 = add(5)
let use(x: U32): U32 = add5(x) + add(2)(3)
return { functions = { use } }
]==]
check(interpret("use", { 10 }, PARTIAL)[1] == 20, "a closure may be supplied with fewer arguments")
local partialUnit = wordlet.compile{ source = PARTIAL, name = "partial.let" }:unit()
check(partialUnit:find("wordlet_use", 1, true) ~= nil, "a partially applied closure compiles")
rejects("static-required", "let add = |a, b: U32| -> a + b\n"
    .. "let f(n: U32): U32 = do let g = add(n) return g(1) end\nreturn { functions = { f } }")

-- Module-level mutable state --------------------------------------------------------------------
local MODULE_STATE = [==[
let Counter = { value: U32, bump(): U32 = do value += 1 return value end }
let shared = Counter { value = 100 }
let bump_twice(x: U32): U32 = do shared.bump() shared.bump() return shared.value + x end
return { types = { Counter }, functions = { bump_twice } }
]==]
check(interpret("bump_twice", { 1 }, MODULE_STATE)[1] == 103,
    "module storage is live and shared across calls in one session")
local moduleArtifact = wordlet.compile{ source = MODULE_STATE, name = "module.let" }
local moduleUnit = moduleArtifact:unit()
check(moduleUnit:find("static wordletrecord_1 wordletmodule_1;", 1, true) ~= nil,
    "module storage is a file-scope object")
check(moduleUnit:find("void wordlet_init(void)", 1, true) ~= nil, "a module initialiser is exported")
check(moduleUnit:find("wordletmodule_1 = (wordletrecord_1)", 1, true) ~= nil,
    "the initialiser assigns the starting value")
local names = moduleArtifact:exports()
local sawInit = false
for _, name in ipairs(names) do if name == "init" then sawInit = true end end
check(sawInit, "the initialiser is part of the artifact surface")

-- Rejections ---
---------------------------------------------------------------------------------
rejects("unknown-name", "let f(x: U32) = y\nreturn { functions = { f } }")
rejects("arity", "let f(a, b: U32) : U32 = a + b\nlet g(x: U32) : U32 = f(1, 2, 3)\nreturn { functions = { g } }")
rejects("callable-required", "let f(x: U32) : U32 = x\nlet g(x: U32) : U32 = f(1)(2)\nreturn { functions = { g } }")
rejects("type-mismatch", "let f(x: U32) : U32 = x + true\nreturn { functions = { f } }")
rejects("division-zero", "let f(x: U32) : U32 = x / 0\nreturn { functions = { f } }")
rejects("recursive-result", "let f(x: U32) = if x == 0 then 0 else f(x - 1)\nreturn { functions = { f } }")
-- A block must end in `return`, so an unterminated block is a parse error rather than a silent
-- fall-through; the evaluator keeps the defensive check anyway.
rejects("parse", "let f(x: U32) : U32 = do let y = x + 1 end\nreturn { functions = { f } }")
rejects("duplicate", "let f(x: U32) : U32 = do let y = x let y = x return y end\nreturn { functions = { f } }")
rejects("unknown-name", "return { functions = { missing } }")
rejects("function-required", "let x = 3\nreturn { functions = { x } }")
rejects("parse", "let f(x: U32) = x\nreturn { functions = { f }")
rejects("initializer-cycle", "let a = b\nlet b = a\nlet f(x: U32) : U32 = a + x\nreturn { functions = { f } }")
rejects("static-required", "let scale(k, x: U32) : U32 = k * x\n"
    .. "let use(x: U32) : U32 = do let g = scale(x) return g(1) end\nreturn { functions = { use } }")
rejects("branch-result", "let f(x: U32) : U32 = if x == 0 then 1 else true\nreturn { functions = { f } }")
rejects("static-required", "let P = { x: U32, y: U32 }\nlet f(a: U32) : U32 = do"
    .. " let q = P { x = a } let z = q.y return z end\nreturn { functions = { f } }")
rejects("not-a-place", "let P = { x: U32 }\nlet f(a: U32) : U32 = do"
    .. " let p = P { x = a }\n let n = 3\n n = 4\n return p.x end\nreturn { functions = { f } }")
rejects("type-mismatch", RECORDS, "bump", { 7 })
-- A callable with no known code needs a function-pointer ABI.
-- Exporting a callable parameter is supported (it becomes a view); an argument that is neither
-- known code nor a view is still rejected.
-- A signature-typed field is represented by the borrowed callable ABI, so a record holding one is
-- usable locally but cannot escape.
local CALLABLE_FIELD = [==[
let Holder = { f: (U32): U32 }
let use(n: U32): U32 = do
  let h = Holder { f = |x: U32| -> x + n }
  return h.f(1)
end
let chase(n: U32): U32 = do
  let h = Holder { f = |x: U32| -> x * 2 }
  return h.f(h.f(n))
end
return { types = { Holder }, functions = { use, chase } }
]==]
check(interpret("use", { 5 }, CALLABLE_FIELD)[1] == 6, "a callable field is invoked through its view")
check(interpret("chase", { 3 }, CALLABLE_FIELD)[1] == 12, "a capture-free callable field still invokes")
local fieldUnit = wordlet.compile{ source = CALLABLE_FIELD, name = "field.let" }:unit()
check(fieldUnit:find("wordletadapterstruct_1", 1, true) ~= nil, "an adapter struct is emitted")
check(fieldUnit:find(".invoke = wordletadapterfn_1", 1, true) ~= nil, "the view is built from the adapter")
rejects("borrow-escape", "let H = { f: (U32): U32 }\n"
    .. "let make(n: U32) = H { f = |x: U32| -> x + n }\nreturn { types = { H }, functions = { make } }")
rejects("borrow-escape", "let H = { f: (U32): U32 }\nlet shared = H { f = |x: U32| -> x }\n"
    .. "let set(n: U32): U32 = do shared.f = |y: U32| -> y + n return 0 end\n"
    .. "return { types = { H }, functions = { set } }")

rejects("callable-shape", "let apply(f: (U32): U32, x: U32) : U32 = f(x)\n"
    .. "let bad(x: U32) : U32 = apply(|y: U32| -> true, x)\nreturn { functions = { bad } }")
rejects("unknown-member", "let P = { x: U32 }\nlet f(a: U32) : U32 = do"
    .. " let p = P { x = a } return p.z end\nreturn { functions = { f } }")
rejects("duplicate", "let P = { x: U32 }\nlet f(a: U32) : U32 = do"
    .. " let p = P { x = a, x = 1 } return p.x end\nreturn { functions = { f } }")
-- Module-level mutable state is supported: the binding becomes a named runtime object.
local moduleBinding = wordlet.compile{ source = "let P = { x: U32 }\nlet m = P { x = 1 }\n"
    .. "let f(a: U32): U32 = do m.x += a return m.x end\nreturn { functions = { f } }" }
check(moduleBinding:unit():find("wordletmodule_1", 1, true) ~= nil, "a module binding gets its own storage")
check(interpret("f", { 4 },
    "let P = { x: U32 }\nlet m = P { x = 1 }\nlet f(a: U32): U32 = do m.x += a return m.x end\n"
    .. "return { functions = { f } }")[1] == 5, "module state mutates through a field store")

-- The interpreter refuses an unsaturated entry rather than inventing a value.
local ok, err = pcall(wordlet.interpret, { source = "let f(a, b: U32) : U32 = a + b\n"
    .. "return { functions = { f } }", entry = "f", args = { 1 } })
check(not ok and D.is(err) and err.code == "arity", "undersaturated entry rejects instead of returning a word")

-- C naming is injective, so two distinct source names cannot collide.
check(C.escape("sum_to") == "sum_5Fto" and C.functionName("sum_to") == "wordlet_sum_5Fto",
    "underscore is escaped")
check(C.escape("a_b") ~= C.escape("aXbX") or C.escape("a-") ~= C.escape("a_"),
    "escaping distinguishes distinct spellings")
check(C.escape("a") ~= C.escape("A"), "case is preserved")

-- Exported aliases share one body and forward.
local aliasArtifact = compile("let inc(x: U32) : U32 = x + 1\nreturn { functions = { a = inc, b = inc } }")
check(#aliasArtifact:exports() == 2, "both aliases are exported")
local aliasUnit = aliasArtifact:unit()
check(aliasUnit:find("wordlet_a", 1, true) and aliasUnit:find("wordlet_b", 1, true),
    "aliases appear in the generated C")

-- Determinism: identical input gives byte-identical output.
local one = compile("let f(x: U32) : U32 = x * 3 + 1\nreturn { functions = { f } }"):unit()
local two = compile("let f(x: U32) : U32 = x * 3 + 1\nreturn { functions = { f } }"):unit()
check(one == two, "emission is deterministic")

print(("PASS: evaluator semantics (%d checks)"):format(checks))
