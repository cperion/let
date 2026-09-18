-- The harness: COMPILE A PROGRAM AND RUN IT.
--
-- The old suite asserted things about the phases -- what the belt looked like after Lower, how many
-- definitions Resolve created -- and 990 of those checks did not notice that no one could compile a FILE
-- (§S84), that a module's state was rebuilt inside every word (§S85), or that assignment never destroyed
-- what it replaced (§S86). So a check here is a PROGRAM: it goes through the real pipeline (`let.compile`,
-- which owns it), it is compiled by the same `cc` a user would use, it RUNS, and its stdout is compared.
--
-- A program that must fail instead is asked for its diagnostic, because §13's three kinds are a claim
-- worth testing too: `Reject` is the program, `Missing` is the compiler, `Bug` is the compiler broken.
package.path = './?.lua;./?/init.lua;' .. package.path
local V = require('let')
local Context = V.Context
local Compile = require('let.compile')(V)

local H = { checks = 0, suite = '?' }
H.directory = 'test/out'
os.execute('mkdir -p ' .. H.directory)

local function check(v, m) assert(v, m); H.checks = H.checks + 1 end
local function eq(a, b, m)
    assert(a == b, ('%s: expected %s, got %s'):format(m, tostring(b), tostring(a))); H.checks = H.checks + 1
end
H.check, H.eq = check, eq

-- §13's three kinds, by name, so a test can say which one it means.
H.Reject, H.Missing, H.Bug = V.Report.Reject, V.Report.Missing, V.Report.Bug
H.R = V.Report

-- text -> C source, or nil and a diagnostic. One `Compiler` per program: it owns `modules`, so a program
-- that imports shares one load per file and a test that wants isolation gets it by calling again.
local counter = 0
function H.compile(text, name)
    counter = counter + 1
    name = name or ('case%03d'):format(counter)
    local unit = Context.compiler(V, {}):child{ source = name }
    local source, diagnostic
    local ok = Compile.translation_unit(unit, text, name,
        function(_, emitted) source = emitted; return true end,
        function(_, d) diagnostic = d; return false end)
    if ok then return source, nil, name end
    return nil, diagnostic, name
end

-- LuaJIT's `os.execute` returns a WAIT status, so the exit code is its high byte.
local function status_of(command)
    local executed, _, code = os.execute(command)
    local status = (type(executed) == 'number') and executed or (executed and 0 or (code or 1))
    if status > 255 then status = math.floor(status / 256) end
    return status
end

-- `host` is the part that is NOT the compiler's business: the type, the destructor, the `main` (§2.6).
function H.run(text, host, name, header)
    local source, diagnostic, case = H.compile(text, name)
    if not source then
        error(('a program that should compile did not: %s\n%s'):format(
            diagnostic and tostring(diagnostic.why) or 'no diagnostic',
            debug.traceback('', 2)), 0)
    end
    local path = ('%s/%s.c'):format(H.directory, case)
    local file = assert(io.open(path, 'wb'))
    -- `header` is the host's TYPE, and it has to come before the unit, because the unit names it. That
    -- is the same reason a real host writes a header: the compiler emits the functions, the host the types.
    file:write('#include <stdint.h>\n#include <stdio.h>\n#include <stdbool.h>\n', header or '', '\n',
        source, '\n', host or '')
    file:close()
    local binary = ('%s/%s'):format(H.directory, case)
    local log = ('%s/%s.log'):format(H.directory, case)
    if status_of(('cc -std=c11 -O2 -w -o %s %s > %s 2>&1'):format(binary, path, log)) ~= 0 then
        local contents = io.open(log)
        local message = contents and contents:read('*a') or ''
        if contents then contents:close() end
        error(('the emitted unit did not compile:\n%s'):format(message), 0)
    end
    local pipe = io.popen(binary .. ' 2>&1')
    local output = pipe:read('*a')
    pipe:close()
    return output
end

-- The three shapes a test takes.
function H.runs(text, host, expected, message, header)
    eq(H.run(text, host, nil, header), expected, message)
end

local function diagnostic_of(text)
    local source, diagnostic = H.compile(text)
    if source then return nil end
    return diagnostic
end

function H.refuses(text, why, message)
    local diagnostic = diagnostic_of(text)
    check(diagnostic ~= nil, message .. ' (it is refused)')
    if diagnostic then
        check(H.Reject:isclassof(diagnostic), message .. ' (as a Reject)')
        check(why == nil or why:isclassof(diagnostic.why), message .. ' (with ' .. tostring(why) .. ')')
    end
end

function H.lacks(text, why, message)
    local diagnostic = diagnostic_of(text)
    check(diagnostic ~= nil, message .. ' (it is reported)')
    if diagnostic then
        check(H.Missing:isclassof(diagnostic), message .. ' (as a Missing: the compiler, not the program)')
        check(why == nil or why:isclassof(diagnostic.why), message .. ' (with ' .. tostring(why) .. ')')
    end
end

function H.finish()
    print(('passed %d %s checks'):format(H.checks, H.suite))
end

return H
