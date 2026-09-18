-- The bundle: one file, no checkout, the same compiler.
--
-- Every other suite runs the compiler FROM THE TREE, which is exactly why a bundler is worth testing
-- against the thing a user gets: the tree is on `package.path` during a test, so a module the bundle
-- forgot is invisible here and fatal there. So this suite builds the bundle and then uses ONLY the
-- bundle -- compile a program, run the `cc` the harness would have run, and compare what it prints.
local H = require('test.harness')
H.suite = 'bundle'
local check, eq = H.check, H.eq

local directory = H.directory
local bundle = ('%s/let-bundle.lua'):format(directory)

-- LuaJIT's `os.execute` returns a wait status, so the exit code is its high byte.
local function status_of(command)
    -- Redirected, because a status is a status: the diagnostics belong to the check that asked for
    -- them (it captures them itself), not to the suite's summary.
    local executed, _, code = os.execute(command .. ' > /dev/null 2>&1')
    local status = (type(executed) == 'number') and executed or (executed and 0 or (code or 1))
    if status > 255 then status = math.floor(status / 256) end
    return status
end

local function output_of(command)
    local pipe = io.popen(command .. ' 2>&1')
    local output = pipe:read('*a')
    pipe:close()
    return output
end

local function write(path, text)
    local file = assert(io.open(path, 'wb'))
    file:write(text)
    file:close()
end

-- 1. It builds, and it builds from DISCOVERY rather than a list -- so the count is a fact about the
--    compiler, not a number somebody kept up to date.
local built = output_of(('luajit bundle.lua %s'):format(bundle))
check(status_of(('luajit bundle.lua %s'):format(bundle)) == 0, 'the bundle builds')
local modules = tonumber(built:match('(%d+) modules'))
check(modules and modules >= 20, 'and it discovered the modules rather than being told them')
local text = io.open(bundle):read('*a')
check(text:match("module%('let%.cli'") ~= nil,
    'including `let.cli`, which nothing requires and only the generated script reaches')
check(text:match("module%('asdl'") ~= nil, 'and the ASDL runtime the compiler is built on')

-- 2. The bundle COMPILES A PROGRAM -- and what it writes is what a host can link and run, which is the
--    only check that says the bundle carries the whole compiler rather than most of it.
local program = [[let square = let x : Int do : Int
    return x * x
end
let sum = let a : Int let b : Int do : Int
    return a + b
end
let answer = sum with (square with 3) with (square with 4)
]]
write(directory .. '/bundle_case.let', program)
local emitted = ('%s/bundle_case.c'):format(directory)
eq(status_of(('luajit %s %s/bundle_case.let -o %s'):format(bundle, directory, emitted)), 0,
    'the bundled compiler compiles a file')
-- `stdio.h` is the HOST's include: the unit carries what the compiler uses and the host prints.
write(directory .. '/bundle_case.host.c', '#include <stdio.h>\n' .. io.open(emitted):read('*a') .. [[
int main(void){ struct let_s1 m = let_module_init();
    printf("%lld\n", (long long)m.answer);
    return 0; }
]])
eq(status_of(('cc -std=c11 -O2 -w -o %s/bundle_case %s/bundle_case.host.c')
    :format(directory, directory)), 0, 'what it wrote links against a host')
eq(output_of(('%s/bundle_case'):format(directory)), '25\n',
    'and the program it compiled computes 25, so the bundle carries the whole compiler')

-- 3. §13's three kinds survive the bundling, because they are the CLI's contract with a build script:
--    `Reject` is the program (1), `Missing` is the compiler (2).
write(directory .. '/bundle_bad.let', 'let f = let n : Int do : Int\n    let x : Bool = 1\n    return n\nend\nlet a = f with 1\n')
local bad = output_of(('luajit %s %s/bundle_bad.let -o %s/bundle_bad.c'):format(bundle, directory, directory))
eq(status_of(('luajit %s %s/bundle_bad.let -o %s/bundle_bad.c'):format(bundle, directory, directory)), 1,
    'a wrong program exits 1 through the bundle')
check(bad:match('bundle_bad%.let:%d+:%d+: error:') ~= nil, 'with a located message')
-- The gap moved: a runtime index as a VALUE is derived (`Judge.Element`), and as a DESTINATION it is
-- the one thing left in the inventory. This test is about the exit CODE, so it follows the gap.
-- §2.6's written form: `{ let handle = move buffer }` -- a written terminal takes what it owns, so the
-- module's value owns it -- and THAT is the half of §2.6 the compiler does not have: no `state` member,
-- no `unload` for it, and a resource in one would leak silently at unload.
-- The gap moved with the work: a written terminal's module OWNS its value and `unload` destroys it, so
-- what is left is §2.6's `state` -- "whatever the namespace does NOT reach" -- which is needed only when
-- the terminal leaves a top-level binding behind. `h` here is initialized, unreached by the terminal and
-- owns a resource, so the module value would have to carry it.
write(directory .. '/bundle_gap.let', 'host Handle release\nextern pure made (n : Int) : Handle\nlet h = made with 1\n; { let x = 1 }\n')
eq(status_of(('luajit %s %s/bundle_gap.let -o %s/bundle_gap.c'):format(bundle, directory, directory)), 2,
    'and a gap exits 2, which is the difference between "your program" and "the compiler"')

-- 4. Required rather than run, it is the compiler -- the launcher asks whether the chunk IS the running
--    script, so loading the bundle into a program must not start a command line.
-- A FILE rather than `-e`, because the path has to be quoted inside the program and nesting quote
-- styles in a shell is how a check ends up testing the shell.
write(directory .. '/bundle_require.lua', ([[
local V = dofile(%q)
print(V.Semantic ~= nil and V.Belt ~= nil and V.Report ~= nil)
]]):format(bundle))
eq(output_of(('luajit %s/bundle_require.lua'):format(directory)), 'true\n',
    'requiring it returns the compiler and runs no command line')

-- 5. THE COMMITTED ARTIFACT IS CURRENT, which is the check that was missing when a STALE
--    `dist/let.lua` was handed to a reader: everything above tests the bundle BUILT FROM THE TREE, so
--    the file a user actually runs was checked by NOTHING -- and a rebuild that never happened is
--    invisible to a suite that always rebuilds. The bundler is deterministic (it discovers the modules
--    by following `require` from the entry), so this is byte equality rather than a list of
--    expectations, and the failure message is the fix.
local fresh = ('%s/let-fresh.lua'):format(directory)
eq(status_of(('luajit bundle.lua %s'):format(fresh)), 0, 'a fresh bundle builds to a named path')
local function read(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local contents = file:read('*a')
    file:close()
    return contents
end
local committed = read('dist/let.lua')
check(committed ~= nil, 'the committed bundle exists')
eq(committed, read(fresh), 'and it is what the sources build (run: luajit bundle.lua)')

H.finish()
