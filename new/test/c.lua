local H = ...
local Word = require("word")
local table = require("word.host").table
local C = require("word.c")

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function read(path)
    local f = assert(io.open(path, "r")); local text = f:read("a"); f:close(); return text
end
local function duration(name, default)
    local value = tonumber(os.getenv(name) or default)
    assert(value and value > 0 and value < math.huge, name .. " must be positive finite seconds")
    return value
end
local compile_timeout = duration("WORD_TEST_COMPILE_TIMEOUT", "15")
local run_timeout = duration("WORD_TEST_RUN_TIMEOUT", "5")
local function bounded(command, seconds, label)
    -- Bound the whole process group, including compiler children. Escalate if
    -- a broken generated program ignores SIGTERM. These are test-only limits.
    local status = os.execute("timeout --kill-after=1s " .. seconds .. "s sh -c " .. quote(command))
    if status == 124 * 256 or status == 137 * 256 or status == 9 then
        error(label .. " timed out after " .. seconds .. "s", 0)
    end
    return status
end
local function run_c(source, expect_abort, timeout)
    local stem = os.tmpname()
    local paths = { stem, stem .. ".c", stem .. ".exe", stem .. ".log", stem .. ".out" }
    local ok, result = pcall(function()
        local f = assert(io.open(stem .. ".c", "w")); f:write(source); f:close()
        local cc = os.getenv("CC") or "cc"
        local built = bounded(cc .. " -std=c11 -O2 -Wall -Wextra -Werror -pedantic " ..
            quote(stem .. ".c") .. " -o " .. quote(stem .. ".exe") .. " >" .. quote(stem .. ".log") .. " 2>&1",
            compile_timeout, "C test compilation")
        assert(built == 0, read(stem .. ".log"))
        local status = bounded("ulimit -c 0; " .. quote(stem .. ".exe") ..
            " >" .. quote(stem .. ".out") .. " 2>" .. quote(stem .. ".log"),
            timeout or run_timeout, "Generated C test")
        if expect_abort then
            assert(status == 134 * 256 or status == 6, "Expected checked arithmetic abort, got " .. tostring(status))
        else assert(status == 0, read(stem .. ".log")) end
        return read(stem .. ".out")
    end)
    for _, path in ipairs(paths) do os.remove(path) end
    assert(ok, result)
    return result
end

H.test("a nonterminating generated C program fails with a deadline diagnostic", function()
    local ok, err = pcall(function() run_c("int main(void) { for (;;) {} }", false, 0.1) end)
    assert(not ok and tostring(err):find("Generated C test timed out after 0.1s", 1, true), tostring(err))
end)

H.test("compiled C agrees with concrete U32 execution across boundaries", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/affine.lua")
    local max = 0xffffffff
    local cases = { { 0, 0, 0 }, { 3, 7, 4 }, { max, max, max }, { 65536, 0, 65536 }, { 1, 1, max } }
    local seed = 17
    for _ = 1, 100 do
        local row = {}
        for j = 1, 3 do seed = (1664525 * seed + 1013904223) % 4294967296; row[j] = seed end
        cases[#cases + 1] = row
    end
    local source = s:emit_c{ functions = m }
    local main = { "#include <stdio.h>", "#include <inttypes.h>", "int main(void) {" }
    local expected = {}
    for _, row in ipairs(cases) do
        local a, b, x = table.unpack(row)
        expected[#expected + 1] = tostring(s:value(m.affine(a, b, x)))
        main[#main + 1] = string.format('printf("%%" PRIu32 "\\n", word_affine(UINT32_C(%d), UINT32_C(%d), UINT32_C(%d)));', a, b, x)
        expected[#expected + 1] = tostring(s:value(m.transform(x)))
        main[#main + 1] = string.format('printf("%%" PRIu32 "\\n", word_transform(UINT32_C(%d)));', x)
    end
    main[#main + 1] = "return 0; }"
    H.eq(run_c(source .. table.concat(main, "\n")), table.concat(expected, "\n") .. "\n")
end)

H.test("constant, subtraction, Bool, Unit and unused values emit valid C11", function()
    local s = Word.new()
    local U32 = s.U32
    local f = s.word(s.U32, function(x) return x - 1 end)
    local constant = s.word(s.U32, function(x) return x * x end):of(0xffffffff)
    local bool = s.word(s.Bool, function(b) return b end)
    local unit = s.word(s.Unit, function() end)
    local unused = s.word(s.U32, function(x) local ignored = x + 1; return U32(7) end)
    local choose = s.word(s.Bool, s.U32, function(flag, x)
        if flag:eq(true) then return x + 1 else return x - 1 end
    end)
    local code = s:emit_c{ functions = { sub = f, constant = constant, flag = bool, unit = unit,
        unused = unused, yes = choose:of(true), no = choose:of(false) } }
    H.eq(run_c(code .. [[
int main(void) {
    word_unit();
    return !(word_sub(0) == UINT32_MAX && word_constant() == 1 &&
             !word_flag(false) && word_flag(true) && word_unused(5) == 7 &&
             word_yes(0) == 1 && word_no(0) == UINT32_MAX);
}
]]), "")
end)

H.test("type factories disappear from compiled C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/generics.lua")
    m.prefix = s.word(s.Type, s.U32, function(T, x) return T(x + 1) end):of(s.U32)
    local program = s:compile{ functions = m }
    for _, fn in ipairs(program.functions) do
        H.eq(#fn.parameters, 1)
        assert(fn.result == s.U32 or fn.result == s.Bool)
    end
    local source = s:emit_c{ functions = m }
    assert(not source:find("Type", 1, true))
    H.eq(run_c(source .. [[
int main(void) {
    return !(word_identity(UINT32_MAX) == UINT32_MAX &&
             word_increment(UINT32_MAX) == 0 && !word_flag(false) && word_flag(true) &&
             word_prefix(9) == 10);
}
]]), "")
end)

H.test("nested zero-stage factory calls preserve their C result", function()
    local s = Word.new()
    local m = s:load_string([[
        local factory = word(function() return word(function() return U32(7) end) end)
        return { outer = word(function() local f = factory(); return f() end) }
    ]])
    H.eq(run_c(s:emit_c{ functions = m } ..
        "int main(void) { return word_outer() != 7; }\n"), "")
end)

H.test("nested record C agrees with value copies, field places and U32 snapshots", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/records.lua")
    local P, Pair = m.types.Point, m.types.Pair
    local shift = m.functions.shift
    m.functions.composed = s.word(P, function(p)
        local q = shift(p, 1)
        return p.x + q.x
    end)
    local source = {s:emit_c(m), "#include <assert.h>", "int main(void) {"}
    local values = {0, 1, 255, 65535, 2147483648, 4294967295}
    for _, x in ipairs(values) do
        for _, y in ipairs(values) do
            local p = P{x = x, y = y}
            local q = m.functions.shift(p, y)
            local pair = Pair{left = p, right = P{x = y, y = x}}
            source[#source + 1] = string.format(
                "{ wordtype_Point p = word_make(UINT32_C(%d), UINT32_C(%d)); " ..
                "wordtype_Point q = word_shift(p, UINT32_C(%d)); " ..
                "assert(q.f_x == UINT32_C(%d) && q.f_y == UINT32_C(%d)); " ..
                "assert(p.f_x == UINT32_C(%d)); " ..
                "wordtype_Pair pair = { .f_left = p, .f_right = word_make(UINT32_C(%d), UINT32_C(%d)) }; " ..
                "assert(word_exercise(pair) == UINT32_C(%d)); " ..
                "assert(pair.f_left.f_x == UINT32_C(%d) && pair.f_right.f_x == UINT32_C(%d)); " ..
                "assert(word_composed(p) == UINT32_C(%d)); }",
                x, y, y, s:value(q.x), s:value(q.y), x, y, x,
                s:value(m.functions.exercise(pair)), x, y, s:value(m.functions.composed(p)))
        end
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("closed runtime producers, static factory chains and erased Unit fields compile", function()
    local s = Word.new(); local m = s:load_string([=[
        local Point = word{x = U32, y = U32}
        local Empty = word{}
        local HasUnit = word{marker = Unit, value = U32}
        local Weird = word{["x-y"] = U32, ["x_2dy"] = U32}
        local Flags = word{before = Bool, after = Bool}
        local make = word(function() return Point{x = 3, y = 4} end)
        local factory = word(function()
            return word(function() return Point{x = 8, y = 9} end)
        end)
        local generic = word(Type, function(T)
            return word(U32, function(n) return T{x = n, y = n + 1} end)
        end)
        return {
            types = {Point = Point, Empty = Empty, HasUnit = HasUnit, Weird = Weird, Unit = Unit, Flags = Flags},
            functions = {
                make = make, factory = factory, generic = generic:of(Point),
                empty = word(function() return Empty{} end),
                unit = word(HasUnit, function(p) p.marker = Unit(); return p.value end),
                weird = word(Weird, function(p) return p["x-y"] + p["x_2dy"] end),
                flags = word(Bool, function(b)
                    local p = Flags{before = false, after = b}
                    local old = p.before
                    p.before = p.after; p.after = old
                    return p
                end),
            },
        }
    ]=])
    local c = s:emit_c(m)
    H.eq(c, s:emit_c(m))
    H.eq(run_c(c .. [=[

#include <assert.h>
int main(void) {
    wordtype_Point a = word_make(), b = word_make();
    a.f_x = 90;
    assert(b.f_x == 3 && a.f_x == 90);
    assert(word_factory().f_x == 8);
    assert(word_generic(12).f_y == 13);
    wordtype_Empty e = word_empty();
    assert(sizeof(e) > 0);
    wordtype_HasUnit u = { .f_value = 42 };
    assert(word_unit(u) == 42);
    wordtype_Weird w = { .f_x_2dy = 7, .f_x_5f2dy = 5 };
    assert(word_weird(w) == 12);
    wordtype_Flags flags = word_flags(true);
    assert(flags.f_before && !flags.f_after);
    return 0;
}
]=]), "")
end)

H.test("C functions, exported types and internal records have disjoint namespaces", function()
    local s = Word.new(); local types = {["5fFoo"] = s.U32}
    for i = 1, 10 do types["T" .. i] = s.word{["field" .. i] = s.U32} end
    local identity = s.word(s.U32, function(x) return x end)
    local unusual = "record" .. string.char(16)
    local c = s:emit_c{types = types, functions = {type_Foo = identity, [unusual] = identity}}
    local main = string.format("\nint main(void) { %s n = 7; return (%s(n) == 7 && %s(n) == 7) ? 0 : 1; }",
        Word.c_type_name("5fFoo"), Word.c_name("type_Foo"), Word.c_name(unusual))
    H.eq(run_c(c .. main), "")
end)

H.test("keyed static fields disappear from C but survive value boundaries", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/specialized.lua")
    local c = s:emit_c(m)
    assert(not c:find("f_y", 1, true)); assert(not c:find("f_enabled", 1, true))
    assert(not c:find("f_element", 1, true)); assert(not c:find("f_bias", 1, true))
    local source = {c, "#include <assert.h>", "int main(void) {",
        "wordtype_Config config = { .word_empty = 0 };"}
    for _, x in ipairs({0, 1, 255, 65535, 2147483648, 4294967295}) do
        local p = m.functions.make(x)
        local b = m.types.Box{point = p}
        source[#source + 1] = string.format(
            "{ wordtype_XAxis p = word_make(UINT32_C(%d)); " ..
            "assert(word_sum(p) == UINT32_C(%d)); " ..
            "assert(word_configured(config, UINT32_C(%d)) == UINT32_C(%d)); " ..
            "wordtype_Box b = { .f_point = p }; " ..
            "assert(word_nested(b).f_x == UINT32_C(%d)); " ..
            "assert(b.f_point.f_x == UINT32_C(%d)); " ..
            "assert(word_local_5fspecialization(UINT32_C(%d)) == UINT32_C(%d)); }",
            x, s:value(m.functions.sum(p)), x, s:value(m.functions.configured(m.types.Config{}, x)),
            s:value(m.functions.nested(b).x), x, x, s:value(m.functions.local_specialization(x)))
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("higher-order words erase their callable inputs and agree with C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/higher_order.lua")
    local program = s:compile{functions = m}
    for _, export in ipairs(program.exports) do
        local expected = (export.name == "add" or export.name == "multiply") and 2 or 1
        H.eq(#program.functions[export.target].parameters, expected)
    end
    local source = {s:emit_c{functions = m}, "#include <assert.h>", "int main(void) {"}
    local values = {0, 1, 65535, 2147483648, 4294967295}
    for _, x in ipairs(values) do
        for _, y in ipairs(values) do
            source[#source + 1] = string.format(
                "assert(word_add(UINT32_C(%d), UINT32_C(%d)) == UINT32_C(%d)); " ..
                "assert(word_multiply(UINT32_C(%d), UINT32_C(%d)) == UINT32_C(%d));",
                x, y, s:value(m.add(x, y)), x, y, s:value(m.multiply(x, y)))
        end
        source[#source + 1] = string.format(
            "assert(word_add10(UINT32_C(%d)) == UINT32_C(%d)); " ..
            "assert(word_nested(UINT32_C(%d)) == UINT32_C(%d)); " ..
            "assert(word_local_5fcall(UINT32_C(%d)) == UINT32_C(%d)); " ..
            "assert(word_predicate(UINT32_C(%d))); " ..
            "assert(word_composed(UINT32_C(%d)) == UINT32_C(%d));",
            x, s:value(m.add10(x)), x, s:value(m.nested(x)), x, s:value(m.local_call(x)), x,
            x, s:value(m.composed(x)))
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("callable record results keep the by-value C boundary", function()
    local s = Word.new(); local m = s:load_string([[
        local Point = word{x = U32, y = U32}:of{y = 0}
        local apply = word(word(Point), Point, function(f, p) return f(p) end)
        local bump = word(Point, function(p) p.x = p.x + 1; return p end)
        return {types = {Point = Point}, functions = {bump = apply:of(bump)}}
    ]])
    H.eq(run_c(s:emit_c(m) .. [[

#include <assert.h>
int main(void) {
    wordtype_Point p = { .f_x = 7 };
    wordtype_Point q = word_bump(p);
    assert(p.f_x == 7 && q.f_x == 8);
    return 0;
}
]]), "")
end)

H.test("C emission is deterministic and name mangling is injective", function()
    local s = Word.new(); local f = s.word(s.U32, function(x) return x end)
    local roots = { ["a-b"] = f, ["a_2db"] = f, ["int"] = f, ["x\n}"] = f }
    local a = s:emit_c{ functions = roots }
    local b = s:emit_c{ functions = roots }
    H.eq(a, b); assert(C.name("a-b") ~= C.name("a_2db"))
    H.eq(run_c(a .. "int main(void) { return 0; }\n"), "")
end)

H.test("receiver state, extracted callbacks and nested field receivers agree with C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/methods.lua")
    local c = s:emit_c(m)
    H.eq(c, s:emit_c(m))
    assert(not c:find("f_step", 1, true)); assert(not c:find("f_twice", 1, true))
    local source = {c, "#include <assert.h>", "int main(void) {"}
    for _, x in ipairs({0, 1, 65535, 2147483648, 4294967295}) do
        for _, n in ipairs({0, 1, 10, 4294967295}) do
            local p = m.types.Fast{count = x}
            local b = m.types.Box{inner = p}
            source[#source + 1] = string.format(
                "{ wordtype_Fast p = { .f_count = UINT32_C(%d) }; " ..
                "wordtype_Fast q = word_advance(p, UINT32_C(%d)); " ..
                "assert(q.f_count == UINT32_C(%d) && p.f_count == UINT32_C(%d)); " ..
                "assert(word_sibling(p, UINT32_C(%d)).f_count == UINT32_C(%d)); " ..
                "wordtype_Box b = { .f_inner = p }; " ..
                "assert(word_nested(b, UINT32_C(%d)).f_inner.f_count == UINT32_C(%d)); " ..
                "assert(b.f_inner.f_count == UINT32_C(%d)); " ..
                "assert(word_independent(UINT32_C(%d)) == UINT32_C(%d)); }",
                x, n, s:value(m.functions.advance(p, n).count), x,
                n, s:value(m.functions.sibling(p, n).count),
                n, s:value(m.functions.nested(b, n).inner.count), x,
                x, s:value(m.functions.independent(x)))
        end
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("replayed branches agree with concrete scalars, records and ordered receiver effects", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/branches.lua")
    local c = s:emit_c(m); H.eq(c, s:emit_c(m))
    local source = {c, "#include <assert.h>", "int main(void) {"}
    local values = {0, 1, 4, 5, 9, 10, 65535, 2147483648, 4294967295}
    local function bit(value) return value and "true" or "false" end
    for _, x in ipairs(values) do
        source[#source + 1] = string.format("word_unit(UINT32_C(%d)); assert(word_piecewise(UINT32_C(%d)) == UINT32_C(%d));",
            x, x, s:value(m.functions.piecewise(x)))
        for _, y in ipairs(values) do
            for _, flag in ipairs({false, true}) do
                local p = m.types.State{count = x, flag = flag}
                local u = m.functions.update(p, y)
                local short = m.functions.short_circuit(p, x, y)
                local method = m.functions.method(p, y)
                source[#source + 1] = string.format(
                    "{ wordtype_State p = { .f_count = UINT32_C(%d), .f_flag = %s }; " ..
                    "wordtype_State u = word_update(p, UINT32_C(%d)); " ..
                    "assert(u.f_count == UINT32_C(%d) && u.f_flag == %s); " ..
                    "wordtype_State q = word_short_5fcircuit(p, UINT32_C(%d), UINT32_C(%d)); " ..
                    "assert(q.f_count == UINT32_C(%d) && q.f_flag == %s); " ..
                    "wordtype_State r = word_method(p, UINT32_C(%d)); " ..
                    "assert(r.f_count == UINT32_C(%d) && r.f_flag == %s); " ..
                    "assert(p.f_count == UINT32_C(%d) && p.f_flag == %s); " ..
                    "assert(word_logic(UINT32_C(%d), UINT32_C(%d), %s) == %s); }",
                    x, bit(flag), y, s:value(u.count), bit(s:value(u.flag)),
                    x, y, s:value(short.count), bit(s:value(short.flag)),
                    y, s:value(method.count), bit(s:value(method.flag)), x, bit(flag),
                    x, y, bit(flag), bit(s:value(m.functions.logic(x, y, flag))))
            end
        end
    end
    for _, a in ipairs({false, true}) do
        for _, b in ipairs({false, true}) do
            source[#source + 1] = string.format("assert(word_equal(%s, %s) == %s);", bit(a), bit(b), bit(a == b))
        end
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("primitive static constructors and Type aliases erase correctly in C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/primitives.lua")
    local c = s:emit_c(m); H.eq(c, s:emit_c(m))
    local source = {c, "#include <assert.h>", "int main(void) {",
        "assert(word_seven() == 7 && !word_no() && word_maximum() == UINT32_MAX);",
        "assert(word_callback() == 7); word_unit();"}
    for _, x in ipairs({0, 1, 9, 10, 65535, 2147483648, 4294967295}) do
        source[#source + 1] = string.format(
            "{ wordtype_Number n = UINT32_C(%d); " ..
            "assert(word_typed(n) == UINT32_C(%d)); " ..
            "wordtype_Point p = word_make(n); assert(p.f_x == n); " ..
            "assert(word_local_5fbind(n) == UINT32_C(%d)); }",
            x, s:value(m.functions.typed(x)), s:value(m.functions.local_bind(x)))
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("static aggregates erase, materialize by value and preserve replayed copies in C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/aggregate_constants.lua")
    local c = s:emit_c(m); H.eq(c, s:emit_c(m))
    assert(not c:find("f_origin", 1, true)); assert(not c:find("f_meta", 1, true))
    assert(not c:find("f_element", 1, true)); assert(not c:find("f_marker", 1, true))
    local source = {c, "#include <assert.h>", "int main(void) {",
        "wordtype_Point a = word_origin(), b = word_origin(); a.f_x = 99; assert(b.f_x == 3 && a.f_x == 99);"}
    for _, n in ipairs({0, 1, 9, 10, 65535, 2147483648, 4294967295}) do
        local shifted = m.functions.shifted(n)
        local box = m.types.Box{point = {x = n, y = 1}}
        local reset = m.functions.reset(box, n)
        local cfg = m.types.Config{bias = n}
        source[#source + 1] = string.format(
            "{ wordtype_Point p = word_shifted(UINT32_C(%d)); " ..
            "assert(p.f_x == UINT32_C(%d) && p.f_y == 4); " ..
            "wordtype_Config cfg = { .f_bias = UINT32_C(%d) }; " ..
            "assert(word_evaluate(cfg, UINT32_C(%d)) == UINT32_C(%d)); " ..
            "wordtype_Box box = { .f_point = { .f_x = UINT32_C(%d), .f_y = 1 } }; " ..
            "wordtype_Box out = word_reset(box, UINT32_C(%d)); " ..
            "assert(out.f_point.f_x == UINT32_C(%d) && out.f_point.f_y == UINT32_C(%d)); " ..
            "assert(box.f_point.f_x == UINT32_C(%d) && box.f_point.f_y == 1); }",
            n, s:value(shifted.x), n, n, s:value(m.functions.evaluate(cfg, n)),
            n, n, s:value(reset.point.x), s:value(reset.point.y), n)
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("recursive scalar, aggregate and Unit calls agree with concrete execution in C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursion.lua")
    local c = s:emit_c(m); H.eq(c, s:emit_c(m))
    assert(c:find("= word_alias(", 1, true)); assert(c:find("= word_sum(", 1, true))
    local source = {c, "#include <assert.h>", "int main(void) {"}
    for n = 0, 12 do
        source[#source + 1] = string.format(
            "assert(word_sum(%d) == UINT32_C(%d)); assert(word_alias(%d) == word_sum(%d)); " ..
            "assert(word_reverse(%d) == UINT32_C(%d)); assert(word_even(%d) == %s); " ..
            "assert(word_triple(%d) == UINT32_C(%d)); word_unit(%d); " ..
            "assert(word_accumulate(%d, UINT32_MAX) == UINT32_C(%d)); " ..
            "assert(word_swap(%d, 7, 9) == UINT32_C(%d));",
            n, s:value(m.functions.sum(n)), n, n, n, s:value(m.functions.reverse(n)),
            n, tostring(s:value(m.functions.even(n))), n, s:value(m.functions.triple(n)), n,
            n, s:value(m.functions.accumulate(n, 0xffffffff)), n, s:value(m.functions.swap(n, 7, 9)))
    end
    for n = 0, 8 do
        for _, x in ipairs({0, 7, 0xffffffff}) do
            local p = m.types.Point{x = x, y = 0xffffffff}; local result = m.functions.walk(p, n)
            m.functions.after(p, n); H.eq(s:value(p.x), x)
            source[#source + 1] = string.format(
                "{ wordtype_Point p = { .f_x = UINT32_C(%d), .f_y = UINT32_MAX }; " ..
                "wordtype_Point q = word_walk(p, %d); word_after(p, %d); " ..
                "assert(q.f_x == UINT32_C(%d) && q.f_y == UINT32_C(%d)); " ..
                "assert(p.f_x == UINT32_C(%d) && p.f_y == UINT32_MAX); }",
                x, n, n, s:value(result.x), s:value(result.y), x)
        end
    end
    source[#source + 1] = string.format(
        "assert(word_accumulate(100000, 0) == UINT32_C(%d));", (100000 * 100001 / 2) % 4294967296)
    source[#source + 1] = "assert(word_swap(100001, 7, 9) == 9); assert(word_reverse(100000) == 42); word_unit(100000);"
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("entry cycles through inline callees and extra static knowledge survive C lowering", function()
    local s = Word.new(); local U32 = s.U32; local a, b, f, callback, known
    a = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return b(n - 1) + 1 end)
    b = s.word(U32, function(n) if n:eq(0) then return U32(1) end; return a(n - 1) + 1 end)
    f = s.word(s.word(U32), U32, function(op, n)
        if n:eq(0) then return U32(0) end; return op(n - 1) + 1
    end)
    callback = s.word(U32, function(n) return f(callback, n) end)
    local add = s.word(U32, U32, function(x, y) return x + y end)
    known = s.word(U32, function(n)
        if n:eq(0) then return U32(7) end; return add:of(known:of(0)())(n)
    end)
    local root = f:of(callback)
    local source = {s:emit_c{functions = {a = a, b = b, callback = root, known = known}},
        "#include <assert.h>", "int main(void) {"}
    for n = 0, 10 do
        source[#source + 1] = string.format(
            "assert(word_a(%d) == UINT32_C(%d)); assert(word_b(%d) == UINT32_C(%d)); " ..
            "assert(word_callback(%d) == UINT32_C(%d)); assert(word_known(%d) == UINT32_C(%d));",
            n, s:value(a(n)), n, s:value(b(n)), n, s:value(root(n)), n, s:value(known(n)))
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("outlined scalar, Bool, record, Unit and zero-argument helpers agree with concrete C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_helpers.lua")
    local c = s:emit_c(m); H.eq(c, s:emit_c(m)); assert(c:find("static ", 1, true))
    local source = {c, "#include <assert.h>", "int main(void) {"}
    for n = 0, 8 do
        source[#source + 1] = string.format(
            "assert(word_total(%d) == UINT32_C(%d)); assert(word_typed(%d) == UINT32_C(%d)); " ..
            "assert(word_predicate(%d) == UINT32_C(%d)); assert(word_unit(%d)); " ..
            "assert(word_zero(%d) == UINT32_C(%d));",
            n, s:value(m.functions.total(n)), n, s:value(m.functions.typed(n)),
            n, s:value(m.functions.predicate(n)), n, n, s:value(m.functions.zero(n)))
        for _, x in ipairs({0, 7, 0xffffffff}) do
            local p = m.types.Point{x = x, y = 0xffffffff}; local result = m.functions.walk(p, n)
            H.eq(s:value(p.x), x); H.eq(s:value(p.y), 0xffffffff)
            source[#source + 1] = string.format(
                "{ wordtype_Point p = { .f_x = UINT32_C(%d), .f_y = UINT32_MAX }; " ..
                "wordtype_Point q = word_walk(p, %d); " ..
                "assert(q.f_x == UINT32_C(%d) && q.f_y == UINT32_C(%d)); " ..
                "assert(p.f_x == UINT32_C(%d) && p.f_y == UINT32_MAX); }",
                x, n, s:value(result.x), s:value(result.y), x)
        end
    end
    source[#source + 1] = "assert(word_unit(100000)); return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("cross-function tail positions retain the callee ABI and changing static prefixes", function()
    local s = Word.new(); local U32 = s.U32; local accumulate, changed
    accumulate = s.word(U32, U32, function(n, total)
        if n:eq(0) then return total end; return accumulate(n - 1, total + n)
    end)
    local warm = s.word(U32, function(total) return accumulate(10, total) end)
    changed = s.word(U32, U32, function(step, n)
        if n:eq(0) then return U32(0) end; return changed(step + 1, n - 1) + step
    end)
    local roots = {warm = warm, change = changed:of(3)}
    local c = s:emit_c{functions = roots}
    local warm_body = assert(c:match("uint32_t word_warm%b()\n{(.-)\n}"))
    assert(warm_body:find("wordfn_", 1, true)); assert(not warm_body:find("for (;;)", 1, true))
    local source = {c, "#include <assert.h>", "int main(void) {"}
    for _, n in ipairs({0, 1, 5, 8, 12}) do
        source[#source + 1] = string.format("assert(word_change(%d) == UINT32_C(%d));", n, s:value(roots.change(n)))
    end
    for _, total in ipairs({0, 1, 100000, 0xffffffff}) do
        source[#source + 1] = string.format("assert(word_warm(UINT32_C(%d)) == UINT32_C(%d));", total, s:value(warm(total)))
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("helper exports and aliases use forward declarations without duplicate private identities", function()
    local s = Word.new(); local U32 = s.U32; local sum
    sum = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return sum(n - 1) + n end)
    local wrapper = s.word(U32, function(n) return sum(n) + 1 end)
    local c = s:emit_c{functions = {a = wrapper, z = sum, zz = sum}}
    assert(not c:find("wordfn_", 1, true))
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { assert(word_a(10) == 56); " ..
        "assert(word_z(10) == 55 && word_zz(10) == 55); return 0; }"), "")
end)

H.test("nested helper dependencies seal before callers and execute in C", function()
    local s = Word.new(); local U32 = s.U32; local a, b
    a = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return a(n - 1) + n end)
    b = s.word(U32, function(n) if n:eq(0) then return U32(0) end; return a(n) + b(n - 1) end)
    local root = s.word(U32, function(n) return b(n) end)
    local program = s:compile{functions = {f = root}}
    H.eq(#program.functions, 3)
    local edges = 0
    for i = 2, 3 do
        for _, block in ipairs(program.functions[i].blocks) do
            for _, ins in ipairs(block.instructions) do
                if ins.op == "Call" and ins.target ~= "self" then edges = edges + 1 end
            end
        end
    end
    assert(edges > 0)
    local source = {s:emit_c{functions = {f = root}}, "#include <assert.h>", "int main(void) {"}
    for n = 0, 6 do
        source[#source + 1] = string.format("assert(word_f(%d) == UINT32_C(%d));", n, s:value(root(n)))
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("grounded mutual groups execute cross-function cycles with wrapped U32 results", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_groups.lua")
    local source = {s:emit_c{functions = m}, "#include <assert.h>", "int main(void) {"}
    for _, seed in ipairs({0, 1, 0xffffffff}) do
        local a, b = seed, (seed + 1) % 4294967296
        for n = 0, 8 do
            if n <= 4 then H.eq(s:value(m.a(n, seed)), a); H.eq(s:value(m.b(n, seed)), b) end
            source[#source + 1] = string.format(
                "assert(word_a(%d, UINT32_C(%d)) == UINT32_C(%d)); " ..
                "assert(word_b(%d, UINT32_C(%d)) == UINT32_C(%d)); " ..
                "assert(word_wrapped(%d, UINT32_C(%d)) == UINT32_C(%d));",
                n, seed, a, n, seed, b, n, seed, (a + 1) % 4294967296)
            b = (a + b) % 4294967296; a = (a + b) % 4294967296
        end
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("mutually recursive record and void signatures preserve value boundaries in C", function()
    local s = Word.new(); local U32 = s.U32; local P = s.word{x = U32}; local a, b, u, v
    a = s.word(P, U32, function(p, n)
        if n:gt(0) then local q = b(p, n); q.x = q.x + a(p, n - 1).x; return q end
        return p
    end)
    b = s.word(P, U32, function(p, n)
        if n:gt(0) then local q = b(p, n - 1); q.x = q.x + a(p, n - 1).x; return q end
        p.x = p.x + 1; return p
    end)
    u = s.word(U32, function(n) if n:gt(0) then v(n); u(n - 1) end end)
    v = s.word(U32, function(n) if n:gt(0) then v(n - 1); u(n - 1) end end)
    local source = {s:emit_c{types = {P = P}, functions = {a = a, u = u}},
        "#include <assert.h>", "int main(void) {"}
    for n = 0, 4 do
        local p = P{x = 3}; local result = a(p, n); H.eq(s:value(p.x), 3)
        source[#source + 1] = string.format(
            "{ wordtype_P p = { .f_x = 3 }; wordtype_P q = word_a(p, %d); " ..
            "assert(p.f_x == 3 && q.f_x == UINT32_C(%d)); word_u(%d); }", n, s:value(result.x), n)
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("recursive methods preserve nested receiver aliasing, owner schemas and copies in C", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_methods.lua")
    local source = {s:emit_c(m), "#include <assert.h>", "int main(void) {"}
    for _, name in ipairs({"nested", "specialized", "owners", "mutual"}) do
        for n = 0, 4 do
            source[#source + 1] = string.format("assert(%s(%d) == UINT32_C(%d));",
                Word.c_name(name), n, s:value(m.functions[name](n)))
        end
    end
    source[#source + 1] = "wordtype_Counter p = {.f_value = 5, .f_stride = 2}; " ..
        "wordtype_Counter q = word_byvalue(p, 4); assert(p.f_value == 5 && q.f_value == 13); return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("recursive receiver calls retain caller-local storage instead of unsafe tail replacement", function()
    local s = Word.new(); local m = s:load_string([[
        local C
        C = word{value = U32, descend = word(U32, function(n)
            if n:gt(0) then local child = C{value = value + 1}; return child.descend(n - 1) end
            return value
        end)}
        return {f = word(U32, function(n) local c = C{value = 3}; return c.descend(n) + c.value end)}
    ]])
    local c = s:emit_c{functions = m}
    assert(not c:find("for (;;)", 1, true))
    H.eq(s:value(m.f(8)), 14)
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { assert(word_f(100) == 106); return 0; }"), "")
end)

H.test("constant receiver recursion specializes by snapshot contents without mutable pointers", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, read = word(U32, function(n)
            if n:gt(0) then return read(n - 1) + value end; return value
        end)}
        local A = word{c = C}:of{c = {value = 7}}
        local B = word{c = C}:of{c = {value = 11}}
        return {f = word(U32, function(n) return A.c.read(n) * 1000 + B.c.read(n) end)}
    ]])
    local program = s:compile{functions = m}; H.eq(#program.functions, 3)
    for _, fn in ipairs(program.functions) do H.eq(fn.receiver, nil) end
    H.eq(s:value(m.f(3)), 28044)
    H.eq(run_c(s:emit_c{functions = m} ..
        "\n#include <assert.h>\nint main(void) { assert(word_f(3) == 28044); return 0; }"), "")
end)

H.test("all U32 numeric operators agree with C across boundaries and randomized operands", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/numeric.lua")
    local cases = {{0, 0}, {1, 0}, {0xffffffff, 0xffffffff}, {0xffffffff, 3}, {3, 20},
        {2, 31}, {2, 32}, {0xffffffff, 63}, {0xffffffff, 64}, {0x80000000, 31}}
    local seed = 17
    for _ = 1, 100 do
        seed = (1664525 * seed + 1013904223) % 4294967296; local a = seed
        seed = (1664525 * seed + 1013904223) % 4294967296
        cases[#cases + 1] = {a, seed}
    end
    local source = {s:emit_c{functions = m}, "#include <assert.h>", "int main(void) {"}
    for _, row in ipairs(cases) do
        local a, b = row[1], row[2]
        for _, name in ipairs({"quotient", "floor", "remainder", "power", "band", "bor", "bxor", "left", "right"}) do
            if b ~= 0 or (name ~= "quotient" and name ~= "floor" and name ~= "remainder") then
                source[#source + 1] = string.format("assert(%s(UINT32_C(%d), UINT32_C(%d)) == UINT32_C(%d));",
                    Word.c_name(name), a, b, s:value(m[name](a, b)))
            end
        end
        for _, name in ipairs({"negate", "invert"}) do
            source[#source + 1] = string.format("assert(%s(UINT32_C(%d)) == UINT32_C(%d));",
                Word.c_name(name), a, s:value(m[name](a)))
        end
    end
    source[#source + 1] = "return 0; }"
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("dynamic zero quotient and remainder trap before C undefined behavior", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/numeric.lua")
    for _, name in ipairs({"quotient", "floor", "remainder"}) do
        local c = s:emit_c{functions = {f = m[name]}}
        assert(c:find("abort();", 1, true))
        H.eq(run_c(c .. "\nint main(void) { (void)word_f(7, 0); return 0; }", true), "")
    end
end)

H.test("default numeric results agree with C in constants, branches and grounded recursion", function()
    local s = Word.new(); local m = s:load_string([[
        local sum
        sum = word(U32, function(n) if n:gt(0) then return sum(n - 1) + n end; return 0 end)
        return {sum = sum, constant = word(function() return 42 end),
            choose = word(U32, function(n) if n:gt(0) then return 7 end; return n end)}
    ]])
    H.eq(run_c(s:emit_c{functions = m} ..
        "\n#include <assert.h>\nint main(void) { assert(word_constant() == 42); " ..
        "assert(word_sum(10) == 55); assert(word_choose(0) == 0 && word_choose(1) == 7); return 0; }"), "")
end)

H.test("multiple results use typed C structs with erased Unit slots and independent record copies", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/results.lua")
    local source = {s:emit_c(m), "#include <assert.h>", "int main(void) {",
        "wordresult_constants k = word_constants(); assert(k.f_r1 == 7 && !k.f_r2 && k.f_r4 == 9);",
        "wordtype_Point p = {.f_x = 3}; wordresult_copies copies = word_copies(p);",
        "copies.f_r1.f_x = 99; assert(copies.f_r2.f_x == 3 && p.f_x == 3);"}
    for n = 0, 8 do
        local sum, count = m.functions.sum(n)
        source[#source + 1] = string.format(
            "{ wordresult_sum r = word_sum(%d); assert(r.f_r1 == %d && r.f_r2 == %d); " ..
            "wordresult_choose c = word_choose(%d); assert(c.f_r1 == %d && c.f_r2 == %s); " ..
            "assert(word_consume(%d) == %d); }",
            n, s:value(sum), s:value(count), n, n == 0 and 42 or n, n == 0 and "true" or "false", n, n * 1000 + n + 1)
    end
    source[#source + 1] = "return 0; }"
    H.eq(Word.c_result_type_name("a_b"), "wordresult_a_5fb")
    H.eq(run_c(table.concat(source, "\n")), "")
end)

H.test("recursive method result packs and all-Unit result structs execute in C", function()
    local s = Word.new(); local m = s:load_string([[
        local Counter = word{value = U32, step = word(U32, function(n)
            if n:gt(0) then value = value + 1; return step(n - 1) end
            return value, false, nil
        end)}
        local units
        units = word(U32, function(n) if n:gt(0) then return units(n - 1) end; return nil, nil end)
        return {f = word(U32, function(n) local c = Counter{value = 1}; return c.step(n) end), units = units}
    ]])
    H.eq(run_c(s:emit_c{functions = m} ..
        "\n#include <assert.h>\nint main(void) { wordresult_f r = word_f(5); " ..
        "assert(r.f_r1 == 6 && !r.f_r2); (void)word_units(5); return 0; }"), "")
end)

H.test("declared infinite entries compile without executing them, while finite tuple contracts execute", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/result_constraints.lua")
    H.eq(run_c(s:emit_c(m) .. "\n#include <assert.h>\nint main(void) { " ..
        "wordresult_sum r = word_sum(10); assert(r.f_r1 == 55 && r.f_r2 == 10); return 0; }"), "")
    local pair; pair = s.word(s.U32, function(n) return pair(n + 1) end)
    local c = s:emit_c{functions = {f = pair}, results = {[pair] = {s.U32, s.Bool, s.Unit}}}
    assert(c:find("for (;;)", 1, true))
    H.eq(run_c(c .. "\nint main(void) { return 0; }"), "")
end)

H.test("transparent record and tuple forwarding lowers to loops without changing copies", function()
    local s = Word.new(); local U32 = s.U32; local P = s.word{x = U32}; local record, pair
    record = s.word(P, U32, function(p, n) if n:gt(0) then return record(p, n - 1) end; return p end)
    pair = s.word(P, U32, function(p, n) if n:gt(0) then return pair(p, n - 1) end; return p, nil end)
    local c = s:emit_c{types = {P = P}, functions = {record = record, pair = pair}}
    assert(c:find("for (;;)", 1, true))
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { wordtype_P p = {.f_x = 7}; " ..
        "wordtype_P a = word_record(p, 100000); wordresult_pair b = word_pair(p, 100000); " ..
        "assert(a.f_x == 7 && b.f_r1.f_x == 7 && p.f_x == 7); return 0; }"), "")
end)

H.test("return projection permutations and post-call stores forbid transparent tail rewriting", function()
    local s = Word.new(); local U32 = s.U32; local P = s.word{x = U32}; local swap, change
    swap = s.word(U32, function(n) if n:gt(0) then local a, b = swap(n - 1); return b, a end; return 1, 2 end)
    change = s.word(P, U32, function(p, n)
        if n:gt(0) then local q = change(p, n - 1); q.x = q.x + 1; return q end; return p
    end)
    local c = s:emit_c{types = {P = P}, functions = {swap = swap, change = change}}
    assert(not c:find("for (;;)", 1, true))
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { wordtype_P p = {.f_x = 3}; " ..
        "wordtype_P q = word_change(p, 4); assert(q.f_x == 7 && p.f_x == 3); " ..
        "wordresult_swap r = word_swap(9); assert(r.f_r1 == 2 && r.f_r2 == 1); return 0; }"), "")
end)

H.test("same-receiver recursive tails retain mutation semantics over long C runs", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/recursive_methods.lua")
    local c = s:emit_c{functions = {f = m.functions.specialized}}
    assert(c:find("for (;;)", 1, true))
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { assert(word_f(100000) == 600608001); return 0; }"), "")
end)

H.test("direct C method exports borrow caller storage while frozen receivers erase the pointer", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/method_exports.lua")
    H.eq(run_c(s:emit_c(m) .. "\n#include <assert.h>\nint main(void) { " ..
        "wordtype_Counter c = {.f_value = 1}; assert(word_add(&c, 2) == 3 && c.f_value == 3); " ..
        "assert(word_alias(&c, 4) == 7); assert(word_step3(&c) == 10); assert(word_read(&c) == 10); " ..
        "assert(word_sum(&c, 3) == 16 && c.f_value == 16); assert(word_known() == 7); return 0; }"), "")
end)

H.test("closed method interfaces expose zero-argument operations with scalar, record and tuple returns", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/closed_methods.lua")
    H.eq(run_c(s:emit_c(m) .. "\n#include <assert.h>\nint main(void) { " ..
        "wordtype_Counter c = {.f_count = 9}; assert(word_read(&c) == 9 && word_constant(&c) == 7); " ..
        "wordtype_Point p = word_copy(&c); p.f_x = 20; assert(c.f_count == 9); (void)p; " ..
        "word_reset(&c); wordresult_pair pair = word_pair(&c); assert(pair.f_r1 == 0 && !pair.f_r2); " ..
        "wordresult_run r = word_run(5); assert(r.f_r1 == 5 && r.f_r2 == 0 && r.f_r3.f_x == 5 && !r.f_r4 && r.f_r5 == 7); " ..
        "return 0; }"), "")
end)

H.test("namespace C entries erase metadata receivers and keep distinct static owner bindings", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/namespaces.lua")
    H.eq(run_c(s:emit_c(m) .. "\n#include <assert.h>\nint main(void) { " ..
        "assert(word_add(10, 20) == 30 && word_alias(10, 20) == 30 && word_constant() == 30); " ..
        "assert(word_triple(7) == 21 && word_quintuple(7) == 35 && word_twice(7) == 42); " ..
        "assert(word_composed(7) == 56 && word_sum(10) == 55); return 0; }"), "")
end)

H.test("method factories retain unbound receiver ABI or erase a readonly receiver", function()
    local s = Word.new(); local m = s:load_string([[
        local C = word{value = U32, read = word(Unit, function() return value end)}
        local Fixed = C:of{value = 7}
        return {types = {C = C}, functions = {factory = word(function() return C.read end),
            fixed = word(function() return Fixed.read end)}}
    ]])
    H.eq(run_c(s:emit_c(m) .. "\n#include <assert.h>\nint main(void) { " ..
        "wordtype_C c = {.f_value = 13}; assert(word_factory(&c) == 13 && word_fixed() == 7); return 0; }"), "")
end)

H.test("stateful objects return by value and local method aliases share their receiver", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/stateful_objects.lua")
    local object = m.functions.make(10)
    local next_value, read = object.next, object.read
    H.eq(s:value(next_value(nil)), 11); H.eq(s:value(read(nil)), 11)
    local c = s:emit_c(m)
    for _, forbidden in ipairs({"malloc", "wordarena", "wordstorage", "wordout", "(*invoke)"}) do
        assert(not c:find(forbidden, 1, true), forbidden)
    end
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { " ..
        "wordtype_Counter c = word_make(10); assert(word_next(&c) == 11 && word_read(&c) == 11); " ..
        "wordtype_Counter copy = c; assert(word_next(&copy) == 12 && word_read(&c) == 11); " ..
        "wordresult_run r = word_run(20); assert(r.f_r1 == 21 && r.f_r2 == 21); return 0; }"), "")
end)

H.test("recursive stateful factories return ordinary records without output storage", function()
    local s = Word.new(); local m = s:load_string([[
        local Counter = word{value = U32, read = word(Unit, function() return value end)}
        local make
        make = word(U32, function(n)
            if n:eq(0) then return Counter{value = 17} end
            return make(n - 1)
        end)
        return {types = {Counter = Counter}, functions = {make = make, read = Counter.read}}
    ]])
    local c = s:emit_c(m)
    assert(not c:find("wordstorage", 1, true))
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { " ..
        "wordtype_Counter c = word_make(100000); assert(word_read(&c) == 17); return 0; }"), "")
end)

H.test("outlined stateful results use the same ordinary record ABI", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/stateful_objects.lua")
    local program = s:compile{types = m.types, functions = {make = m.functions.make}}
    local IR = require("word.ir")
    local builder = IR.builder(100, nil, program.functions)
    local n = builder:parameter(s.U32)
    local target = program.exports[1].target
    local t = program.functions[target].result
    program.functions[#program.functions + 1] = builder:finish(t, builder:call(t, {n}, target))
    program.exports[#program.exports + 1] = {name = "wrapped", target = #program.functions}
    H.eq(run_c(C.emit(program) .. "\n#include <assert.h>\nint main(void) { " ..
        "wordtype_Counter c = word_wrapped(20); assert(c.f_value == 20); return 0; }"), "")
end)

H.test("tail calls borrowing local closure environments keep their activation alive", function()
    local s = Word.new(); local m = s:load_string([[
        local Read = word(Unit)
        local C = word{value = U32, read = word(Unit, function() return value end)}
        local loop
        loop = word(Read, U32, function(f, n)
            if n:eq(0) then return f(nil) end
            local c = C{value = f(nil) + 1}
            return loop(c.read, n - 1)
        end)
        return {results = {[Read] = U32}, functions = {run = word(U32, function(n)
            return loop(C{value = 0}.read, n)
        end)}}
    ]])
    local c = s:emit_c(m)
    assert(not c:find("for (;;)", 1, true))
    H.eq(run_c(c .. "\n#include <assert.h>\nint main(void) { assert(word_run(30) == 30); return 0; }"), "")
end)

H.test("immutable closures copy their captures by value across returns and recursion", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/immutable_closures.lua")
    H.eq(s:value(m.make(10)(3)), 13)
    H.eq(s:value(m.nested(10)(2)(3)), 15)
    H.eq(s:value(m.recursive(10)(5)), 15)
    local even, odd = m.mutual(10)
    H.eq(s:value(even(5)), 11); H.eq(s:value(odd(5)), 10)
    local c = s:emit_c{functions = m}
    for _, forbidden in ipairs({"malloc", "wordstorage", "wordout", "void *environment", "(*invoke)"}) do
        assert(not c:find(forbidden, 1, true), forbidden)
    end
    H.eq(run_c(c .. [[
        #include <assert.h>
        int main(void) {
            wordresult_make a = word_make(10), copy = a;
            a = word_make(100);
            assert(wordcall_make(copy, 3) == 13 && wordcall_make(a, 3) == 103);
            wordresult_call_nested inner = wordcall_nested(word_nested(10), 2);
            assert(wordcall_nested_result(inner, 3) == 15);
            assert(wordcall_recursive(word_recursive(10), 5) == 15);
            wordresult_mutual p = word_mutual(10);
            assert(wordcall_mutual_r1(p.f_r1, 5) == 11);
            assert(wordcall_mutual_r2(p.f_r2, 5) == 10);
            return 0;
        }
    ]]), "")
end)

H.test("capture templates share code but not values across branches or compilations", function()
    local s = Word.new(); local m = s:load_string([[
        local make = word(U32, Bool, function(n, flag)
            local offset = n
            if flag:eq(true) then offset = offset + 1 end
            local disabled = false
            return word(U32, function(x)
                if disabled == nil then return 0 end
                return offset + x
            end)
        end)
        return {make = make, pair = word(U32, function(n) return make(n, false), make(n + 10, true) end)}
    ]])
    local first = s:emit_c{functions = m}
    local second = s:emit_c{functions = m}
    local main = [[
        #include <assert.h>
        int main(void) {
            assert(wordcall_make(word_make(10, true), 3) == 14);
            assert(wordcall_make(word_make(10, false), 3) == 13);
            wordresult_pair p = word_pair(10);
            assert(wordcall_pair_r1(p.f_r1, 3) == 13);
            assert(wordcall_pair_r2(p.f_r2, 3) == 24);
            return 0;
        }
    ]]
    H.eq(run_c(first .. main), ""); H.eq(run_c(second .. main), "")
end)

H.test("owned callable captures compose across outlined recursive results", function()
    local s = Word.new(); local m = s:load_string([[
        local make
        make = word(U32, function(n)
            if n:eq(0) then return word(U32, function(x) return n + x end) end
            return make(n - 1)
        end)
        return {make = make, compose = word(U32, function(n)
            local f = make(n)
            return word(U32, function(x) return f(x) + 1 end)
        end), local_recursion = word(U32, function(n)
            local f
            f = word(U32, function(x) if x:eq(0) then return n end; return f(x - 1) + 1 end)
            return f(n)
        end)}
    ]])
    H.eq(run_c(s:emit_c{functions = m} .. [[
        #include <assert.h>
        int main(void) {
            assert(wordcall_make(word_make(10000), 5) == 5);
            assert(wordcall_compose(word_compose(0), 5) == 6);
            assert(wordcall_compose(word_compose(10), 5) == 6);
            assert(word_local_5frecursion(7) == 14);
            return 0;
        }
    ]]), "")
end)

H.test("by-value environments interoperate with borrowed runtime callback inputs", function()
    local s = Word.new(); local m = s:load_string([[
        local Unary = word(U32)
        return {types = {Unary = Unary}, results = {[Unary] = U32},
            functions = {make = word(U32, function(n)
                return word(Unary, U32, function(f, x) return n + f(x) end)
            end)}}
    ]])
    H.eq(run_c(s:emit_c(m) .. [[
        #include <assert.h>
        static uint32_t twice(void *environment, uint32_t x) { (void)environment; return x * 2; }
        int main(void) {
            wordtype_Unary f = {.invoke = twice, .environment = NULL};
            assert(wordcall_make(word_make(4), f, 7) == 18);
            return 0;
        }
    ]]), "")
end)

H.test("nested keyed owners compile to root receiver parameters with distinct recursive occurrences", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_owners.lua")
    local c = s:emit_c(m)
    assert(not c:find("malloc", 1, true))
    H.eq(run_c(c .. [[
        #include <assert.h>
        int main(void) {
            wordresult_run r = word_run(10000);
            assert(r.f_r1 == 30011 && r.f_r2 == 40030);
            assert(r.f_r3 == 20010 && r.f_r4 == 20001 && r.f_r5 == 20020);
            assert(word_replace(50) == 53);
            return 0;
        }
    ]]), "")
end)

H.test("lexically nested methods share typed receiver storage without captured owner objects", function()
    local s = Word.new(); local m = s:load(H.root .. "examples/lexical_locals.lua")
    local c = s:emit_c(m)
    assert(not c:find("wordstorage", 1, true) and not c:find("malloc", 1, true))
    H.eq(run_c(c .. [[
        #include <assert.h>
        int main(void) {
            wordtype_Counter c = {.f_count = 3};
            assert(word_step(&c, 5) == 8);
            assert(word_sum(&c, 10000) == 10008);
            wordresult_snapshot f = word_snapshot(&c);
            c.f_count = 0;
            assert(wordcall_snapshot(f, 2) == 10010);
            return 0;
        }
    ]]), "")
end)
