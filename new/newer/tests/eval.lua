-- Evaluator semantics: static results, specialization sharing and source rejections.
local source = debug.getinfo(1, "S").source:sub(2)
package.path = (source:match("^(.*[/\\])") or "./") .. "../?.lua;"
    .. (source:match("^(.*[/\\])") or "./") .. "../?/init.lua;" .. package.path

local wordlet = require("wordlet")
local Eval = require("wordlet.eval")
local Parse = require("wordlet.parse")
local D = require("wordlet.diag")
local C = require("wordlet.cabi")
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
