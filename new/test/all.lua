local root = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "../"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path
local Word = require("word")
local H = { passed = 0, failed = 0, missing = {}, root = root }

function H.eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
function H.raises(kind, id, fn)
    local ok, err = pcall(fn)
    assert(not ok, "expected " .. kind .. " [" .. id .. "]")
    assert(Word.is_diagnostic(err), "expected structured diagnostic, got " .. tostring(err))
    H.eq(err.kind, kind); H.eq(err.id, id)
    return err
end
function H.test(name, fn)
    local ok, err = pcall(fn)
    if ok then H.passed = H.passed + 1; print("PASS " .. name)
    else H.failed = H.failed + 1; io.stderr:write("FAIL ", name, "\n", tostring(err), "\n") end
end
function H.gap(id, fn)
    local ok, err = pcall(fn)
    if not ok and Word.is_diagnostic(err) and err.kind == "todo" and err.id == id then
        H.missing[id] = (H.missing[id] or 0) + 1
        assert(err.next and err.source, "TODO needs an action and location")
        print("TODO " .. id)
    else
        H.failed = H.failed + 1
        io.stderr:write("FAIL gap ", id, ": ", ok and "now succeeds; promote to a positive test and retire the trap" or tostring(err), "\n")
    end
end

for _, name in ipairs({ "host", "luajit", "model", "normalize", "records", "keyed", "callable", "methods", "replay", "primitive", "aggregate", "recursion", "helpers", "groups", "receiver_recursion", "numeric", "literals", "results", "constraints", "runtime_contracts", "method_interfaces", "namespaces", "borrow", "closures", "lexical", "owners", "c" }) do
    assert(loadfile(root .. "test/" .. name .. ".lua"))(H)
end
-- Roadmap categories can be partially implemented without a remaining TODO trap.
-- H.gap still strictly checks each actual unsupported operation exercised above.
local count = 0
for _ in pairs(H.missing) do count = count + 1 end
print(string.format("\n%d passed; %d TODO diagnostics exercised; %d open implementation areas; %d failed",
    H.passed, count, #Word.todos(), H.failed))
os.exit(H.failed == 0 and 0 or 1)
