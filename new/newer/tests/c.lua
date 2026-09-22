-- Differential tests: the reference interpreter and the generated C must agree.
-- Requires a C11 compiler (CC) and GNU timeout.
local source = debug.getinfo(1, "S").source:sub(2)
package.path = (source:match("^(.*[/\\])") or "./") .. "../?.lua;"
    .. (source:match("^(.*[/\\])") or "./") .. "../?/init.lua;" .. package.path

local wordlet = require("wordlet")
local C = require("wordlet.cabi")
local S = require("wordlet.schema")
local D = require("wordlet.diag")
local checks = 0
local function check(ok, message) assert(ok, message) checks = checks + 1 end

local CC = os.getenv("CC") or "cc"
local timeout = os.getenv("WORDLET_TIMEOUT") or "20s"
local directory = os.tmpname()
os.remove(directory)
assert(os.execute("mkdir -p -- '" .. directory .. "'") ~= nil)

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    assert(file:write(text))
    assert(file:close())
end
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = assert(file:read("*a"))
    assert(file:close())
    return text
end
-- LuaJIT follows Lua 5.1: os.execute returns the raw status, so success is 0 rather than true.
local function shell(command)
    local first, how = os.execute(command)
    if first == true or first == 0 then return 0 end
    if first == nil then return how end
    return first
end

-- Source programs exercised end to end. Each case lists concrete input vectors; expected results
-- are produced by the interpreter, then asserted by the compiled C.
local CASES = {
    {
        name = "affine",
        source = "let affine(a, b, x: U32) : U32 = a * x + b\nreturn { functions = { affine } }",
        entry = "affine", arity = 3,
        inputs = { { 3, 7, 4 }, { 1, 0, 0 }, { 4294967295, 1, 1 }, { 65536, 65536, 65537 } },
    },
    {
        name = "branch",
        source = "let pick(x: U32) : U32 = if x == 0 then 7 else x * 2\nreturn { functions = { pick } }",
        entry = "pick", arity = 1,
        inputs = { { 0 }, { 1 }, { 2147483648 }, { 4294967295 } },
    },
    {
        name = "comparison",
        source = "let classify(x: U32) : U32 = if x < 10 then 1 else if x == 10 then 2 else 3\n"
            .. "return { functions = { classify } }",
        entry = "classify", arity = 1,
        inputs = { { 0 }, { 9 }, { 10 }, { 11 }, { 4294967295 } },
    },
    {
        name = "results",
        source = "let divmod(a, b: U32) : (U32, U32) = do return a / b, a % b end\n"
            .. "let recompose(a, b: U32) : U32 = do let q, r = divmod(a, b) return q * b + r end\n"
            .. "return { functions = { divmod, recompose } }",
        entries = { { entry = "divmod", arity = 2 }, { entry = "recompose", arity = 2 } },
        inputs = { { 17, 5 }, { 1, 1 }, { 4294967295, 3 }, { 100, 7 } },
    },
    {
        name = "calls",
        source = "let inc(x: U32) : U32 = x + 1\n"
            .. "let twice(x: U32) : U32 = inc(inc(x))\n"
            .. "let offset(x: U32) : U32 = twice(x) + inc(x)\n"
            .. "return { functions = { twice, offset } }",
        entries = { { entry = "twice", arity = 1 }, { entry = "offset", arity = 1 } },
        inputs = { { 0 }, { 1 }, { 4294967294 } },
    },
    {
        name = "recursion",
        source = "let sum_to(n: U32) : U32 = if n == 0 then 0 else n + sum_to(n - 1)\n"
            .. "let factorial(n: U32) : U32 = if n == 0 then 1 else n * factorial(n - 1)\n"
            .. "return { functions = { sum_to, factorial } }",
        entries = { { entry = "sum_to", arity = 1 }, { entry = "factorial", arity = 1 } },
        inputs = { { 0 }, { 1 }, { 5 }, { 10 } },
    },
    {
        name = "staticspecialization",
        source = "let scale(k, x: U32) : U32 = k * x\n"
            .. "let by3 = scale(3)\n"
            .. "let scaled(x: U32) : U32 = by3(x) + scale(5)(x)\n"
            .. "return { functions = { scaled } }",
        entry = "scaled", arity = 1,
        inputs = { { 0 }, { 1 }, { 7 }, { 1000000 } },
    },
    {
        name = "shifts",
        source = "let xorshift(a, b, c, s: U32) : U32 = do\n"
            .. "  let s1 = s ~ (s << a)\n  let s2 = s1 ~ (s1 >> b)\n  return s2 ~ (s2 << c)\nend\n"
            .. "let next32 = xorshift(13, 17, 5)\n"
            .. "let third(s: U32) : U32 = next32(next32(next32(s)))\n"
            .. "return { functions = { next32, third } }",
        entries = { { entry = "next32", arity = 1 }, { entry = "third", arity = 1 } },
        inputs = { { 0 }, { 1 }, { 42 }, { 4294967295 } },
    },
    {
        name = "guard",
        source = "let safe_div(a, b: U32) : U32 = a / b\nreturn { functions = { safe_div } }",
        entry = "safe_div", arity = 2,
        inputs = { { 100, 3 }, { 7, 1 }, { 4294967295, 65536 } },
    },
    {
        name = "records",
        source = "let P = { x: U32, y: U32 }\n"
            .. "let build(a, b: U32) : U32 = do\n"
            .. "  let p = P { x = a, y = b }\n  return p.x * 1000 + p.y\nend\n"
            .. "let bump(p: P) : U32 = do p.x += 1 return p.x end\n"
            .. "let caller(n: U32) : U32 = do\n"
            .. "  let p = P { x = n, y = 5 }\n  let raised = bump(p)\n"
            .. "  return raised * 1000 + p.x * 10 + p.y\nend\n"
            .. "let pair(a: U32) : P = P { x = a, y = a + 1 }\n"
            .. "let use(a: U32) : U32 = do let q = pair(a) return q.x * 10 + q.y end\n"
            .. "let alias(n: U32) : U32 = do\n"
            .. "  let p = P { x = n, y = 0 }\n  let q = p\n  q.y = 9\n  return p.x * 10 + p.y\nend\n"
            .. "let compound(n: U32) : U32 = do\n"
            .. "  let p = P { x = n, y = 3 }\n  p.x += 4\n  p.y *= 2\n  p.x -= 1\n"
            .. "  return p.x * 100 + p.y\nend\n"
            .. "return { types = { P }, functions = { build, caller, use, alias, compound } }",
        entries = {
            { entry = "build", arity = 2 }, { entry = "caller", arity = 1 },
            { entry = "use", arity = 1 }, { entry = "alias", arity = 1 },
            { entry = "compound", arity = 1 },
        },
        inputs = { { 0, 0 }, { 3, 4 }, { 7, 5 }, { 10, 1 }, { 4294967295, 1 }, { 2 }, { 9 }, { 5 } },
    },
    {
        name = "methods",
        source = "let Counter = {\n  value: U32,\n  inc() : U32 = do value += 1 return value end,\n"
            .. "  add(n: U32) : U32 = do value += n return value end,\n}\n"
            .. "let observe(n: U32, change: Bool) : (U32, U32) = do\n"
            .. "  let c = Counter { value = n }\n  let old = c.value\n"
            .. "  if change then c.inc() end\n  return old, c.value\nend\n"
            .. "let twice(n: U32) : U32 = do\n"
            .. "  let c = Counter { value = n }\n  c.inc()\n  c.add(5)\n  return c.value\nend\n"
            .. "return { types = { Counter }, functions = { observe, twice } }",
        entries = { { entry = "observe", arity = 2 }, { entry = "twice", arity = 1 } },
        inputs = { { 7, true }, { 7, false }, { 0, true }, { 4294967295, true }, { 1 }, { 100 } },
    },
    {
        name = "tails",
        source = "let sum_to(n, acc: U32) : U32 = if n == 0 then acc else sum_to(n - 1, acc + n)\n"
            .. "let count_down(n: U32) : U32 = if n == 0 then 7 else count_down(n - 1)\n"
            .. "let swapdown(a, b: U32) : U32 = if a == 0 then b else swapdown(b, a - 1)\n"
            .. "return { functions = { sum_to, count_down, swapdown } }",
        entries = { { entry = "sum_to", arity = 2 }, { entry = "count_down", arity = 1 },
            { entry = "swapdown", arity = 2 } },
        inputs = { { 0, 5 }, { 1, 0 }, { 10, 3 }, { 5, 0 }, { 3, 4 }, { 0, 0 }, { 2, 5 }, { 7, 1 } },
    },
    {
        name = "closures",
        source = "let apply(f: (U32): U32, x: U32) : U32 = f(x)\n"
            .. "let twice(f: (U32): U32, x: U32) : U32 = f(f(x))\n"
            .. "let make_adder(n: U32) = |x: U32| -> n + x\n"
            .. "let run(n, x: U32) : U32 = do let add = make_adder(n) return apply(add, x) end\n"
            .. "let inline(x: U32) : U32 = twice(|y: U32| -> y + 1, x)\n"
            .. "let compose(a, b, x: U32) : U32 = do\n"
            .. "  let f = make_adder(a)\n  let g = make_adder(b)\n  return apply(f, apply(g, x))\nend\n"
            .. "let C = { v: U32, mk() = |x: U32| -> v + x }\n"
            .. "let snap(n: U32) : U32 = do\n"
            .. "  let c = C { v = n }\n  let f = c.mk()\n  c.v += 5\n  return f(100)\nend\n"
            .. "return { types = { C }, functions = { run, inline, compose, snap } }",
        entries = { { entry = "run", arity = 2 }, { entry = "inline", arity = 1 },
            { entry = "compose", arity = 3 }, { entry = "snap", arity = 1 } },
        inputs = { { 5, 7 }, { 0, 0 }, { 3 }, { 7 }, { 3, 4, 10 }, { 0, 0, 0 }, { 1 }, { 4294967295 } },
    },
    {
        name = "contextual",
        source = "let twice(f: (U32): U32, x: U32): U32 = f(f(x))\n"
            .. "let adder(n: U32): (U32): U32 = |x| -> x + n\n"
            .. "let inc: (U32): U32 = |x| -> x + 1\n"
            .. "let use(n, x: U32): U32 = do\n"
            .. "  let f = adder(n)\n  return twice(f, x) + inc(x)\nend\n"
            .. "let inline(x: U32): U32 = twice(|y| -> y * 2, x)\n"
            .. "let capture(x: U32): U32 = twice(|y| -> y + x, 1)\n"
            .. "return { functions = { use, inline, capture } }",
        entries = { { entry = "use", arity = 2 }, { entry = "inline", arity = 1 },
            { entry = "capture", arity = 1 } },
        inputs = { { 3, 4 }, { 0, 0 }, { 7, 5 }, { 5 }, { 0 }, { 10 } },
    },
    {
        name = "alias",
        source = "let inc(x: U32) : U32 = x + 1\nreturn { functions = { a = inc, b = inc } }",
        entries = { { entry = "a", arity = 1 }, { entry = "b", arity = 1 } },
        inputs = { { 0 }, { 5 } },
    },
    {
        name = "unitandbool",
        source = "let flag(x: U32) : Bool = x != 0\n"
            .. "let both(a, b: U32) : Bool = (a < b) and (b != 0)\n"
            .. "return { functions = { flag, both } }",
        entries = { { entry = "flag", arity = 1 }, { entry = "both", arity = 2 } },
        inputs = { { 0 }, { 1 }, { 5, 0 }, { 3, 9 }, { 9, 3 } },
    },
}

local function cLiteral(value)
    if type(value) == "number" then return "UINT32_C(" .. value .. ")" end
    if type(value) == "boolean" then return value and "true" or "false" end
    return nil
end

local function runCase(case)
    local artifact = wordlet.compile{ source = case.source, name = case.name .. ".let" }
    local unit = artifact:unit()
    local cPath, exePath = directory .. "/" .. case.name .. ".c", directory .. "/" .. case.name
    write(cPath, unit)

    local checksList = {}
    for _, target in ipairs(case.entries or { { entry = case.entry, arity = case.arity } }) do
        for _, input in ipairs(case.inputs) do
          if #input >= target.arity then
            local args = {}
            for index = 1, target.arity do args[index] = input[index] end
            local expected = wordlet.interpret{ source = case.source, name = case.name .. ".let",
                entry = target.entry, args = args }
            local literalArgs = {}
            for index, value in ipairs(args) do literalArgs[index] = cLiteral(value) end
            -- Export names are escaped: underscore becomes _5F, so the C symbol is not the source name.
            local call = C.functionName(target.entry) .. "(" .. table.concat(literalArgs, ", ") .. ")"
            local expectedC = {}
            for index, value in ipairs(expected) do
                local literal = cLiteral(value)
                check(literal ~= nil, "unsupported expected result " .. tostring(value))
                expectedC[index] = literal
            end
            if #expected == 1 then
                checksList[#checksList + 1] = "    assert((" .. call .. ") == " .. expectedC[1] .. ");"
            else
                -- Multiple results come back in the generated result struct.
                local struct = unit:match("(wordlettuple_%d+) {")
                checksList[#checksList + 1] = "    { " .. struct .. " r = " .. call .. "; "
                    .. "assert(r.f_1 == " .. expectedC[1] .. " && r.f_2 == " .. expectedC[2] .. "); }"
            end
          end
        end
    end

    local main = { "#include <assert.h>", "#include <stdint.h>", "#include <stdbool.h>", "",
        unit, "", "int main(void) {" }
    for _, line in ipairs(checksList) do main[#main + 1] = line end
    main[#main + 1] = "    return 0;"
    main[#main + 1] = "}"
    write(cPath, table.concat(main, "\n"))

    local flags = "-std=c11 -Wall -Wextra -Werror -O2"
    local compile = ("timeout --kill-after=2s %s %s %s -o '%s' '%s'"):format(timeout, CC, flags, exePath, cPath)
    local status = shell(compile .. " 2> " .. directory .. "/err.txt")
    check(status == 0, "C compilation failed for " .. case.name .. ":\n" .. read(directory .. "/err.txt"))
    local run = shell("timeout --kill-after=2s 10s '" .. exePath .. "'")
    check(run == 0, "generated C failed its assertions for " .. case.name .. " (status " .. tostring(run) .. ")")
end

for _, case in ipairs(CASES) do runCase(case) end

-- A self-tail call must not consume C stack. Without the loop rewrite this overflows; with it,
-- the call is a back edge and the depth is constant. This runs only in C because the reference
-- interpreter would recurse in Lua.
do
    local source = "let count_down(n: U32) : U32 = if n == 0 then 7 else count_down(n - 1)\n"
        .. "let sum_to(n, acc: U32) : U32 = if n == 0 then acc else sum_to(n - 1, acc + n)\n"
        .. "return { functions = { count_down, sum_to } }"
    local generated = wordlet.compile{ source = source, name = "deep.let" }:unit()
    local path = directory .. "/deep.c"
    write(path, generated .. "\n#include <assert.h>\n"
        .. "int main(void) {\n"
        .. "    assert(wordlet_count_5Fdown(UINT32_C(5000000)) == UINT32_C(7));\n"
        .. "    assert(wordlet_sum_5Fto(UINT32_C(65535), UINT32_C(0)) == (uint32_t)((uint64_t)65535*65536/2));\n"
        .. "    return 0;\n}\n")
    local exe = directory .. "/deep"
    check(shell("timeout --kill-after=2s 30s " .. CC .. " -std=c11 -Wall -Wextra -Werror -O2 -o '"
        .. exe .. "' '" .. path .. "' 2> " .. directory .. "/derr.txt") == 0,
        "deep-recursion C failed to compile:\n" .. read(directory .. "/derr.txt"))
    check(shell("timeout --kill-after=2s 30s '" .. exe .. "'") == 0,
        "a self-tail call must run at constant C stack depth")
end

-- Single-file distribution: bundle the compiler, then compile a program through the bundle's CLI.
-- This checks the shipped artifact, not just the checkout modules.
local root = (source:match("^(.*[/\\])") or "./") .. "../"
local bundlePath = directory .. "/wordlet.lua"
check(shell("timeout --kill-after=2s 40s luajit " .. root .. "tools/bundle.lua "
    .. root .. "bundle-manifest.lua '" .. bundlePath .. "' > /dev/null") == 0,
    "bundling the compiler failed")
local generatedPath = directory .. "/bundled.c"
check(shell("timeout --kill-after=2s 20s luajit '" .. bundlePath .. "' -o '" .. generatedPath
    .. "' " .. root .. "examples/arithmetic.let") == 0, "the bundled CLI failed to emit C")
local generated = read(generatedPath)
check(generated:find("wordlet_transform", 1, true) ~= nil
    and generated:find("wordlet_consume", 1, true) ~= nil, "bundle emitted the expected exports")
write(directory .. "/bundled_main.c", generated .. "\n#include <assert.h>\n"
    .. "int main(void) { assert(wordlet_transform(UINT32_C(4)) == UINT32_C(19)); return 0; }\n")
local exe = directory .. "/bundled"
check(shell("timeout --kill-after=2s 20s " .. CC .. " -std=c11 -Wall -Wextra -Werror -O2 -o '"
    .. exe .. "' '" .. directory .. "/bundled_main.c' 2> " .. directory .. "/berr.txt") == 0,
    "bundled C failed to compile:\n" .. read(directory .. "/berr.txt"))
check(shell("timeout --kill-after=2s 10s '" .. exe .. "'") == 0, "bundled C failed its assertions")

os.execute("rm -rf -- '" .. directory .. "'")
print(("PASS: interpreter/C differential and single-file distribution (%d checks, %d programs)")
    :format(checks, #CASES))
