local H = ...

local function quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end
local function read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a"); file:close(); return text
end
local function write(path, text)
    local file = assert(io.open(path, "wb")); file:write(text); file:close()
end
local function exit_code(status)
    if type(status) == "number" then
        if status > 255 then return math.floor(status / 256) end
        return status
    end
    return status and 0 or 1
end
local function run(command, seconds)
    local stdout, stderr = os.tmpname(), os.tmpname()
    local inner = command .. " >" .. quote(stdout) .. " 2>" .. quote(stderr)
    local raw = os.execute("timeout --kill-after=1s " .. tostring(seconds or 15) .. "s sh -c " .. quote(inner))
    local code, out, err = exit_code(raw), read(stdout) or "", read(stderr) or ""
    os.remove(stdout); os.remove(stderr)
    assert(code ~= 124 and code ~= 137, "Bundler subprocess timed out: " .. command)
    return code, out, err
end

local root = H.root
if root:sub(1, 1) ~= "/" then root = assert(os.getenv("PWD")) .. "/" .. root end
local bundler, wordc = root .. "bundle.lua", root .. "wordc.lua"

H.test("single-file bundle is deterministic, isolated, embeddable, and CLI-compatible", function()
    local temporary = os.tmpname()
    os.remove(temporary)
    temporary = temporary .. " word bundle's test"
    local made, _, make_error = run("mkdir -p -- " .. quote(temporary), 5)
    assert(made == 0, make_error)

    local ok, failure = pcall(function()
        local artifact_directory = temporary .. "/artifact space's"
        local artifact = artifact_directory .. "/word.lua"
        local code, built, build_error = run("cd " .. quote(temporary) .. "; luajit " ..
            quote(bundler) .. " " .. quote(artifact))
        H.eq(code, 0); H.eq(build_error, "")
        local count = tonumber(built:match("(%d+) modules"))
        assert(count and count >= 10, "bundle did not report discovered modules: " .. built)

        -- The default is relative to the caller, while source discovery remains
        -- relative to bundle.lua. A second build must be byte-identical.
        code, _, build_error = run("cd " .. quote(temporary) .. "; luajit " .. quote(bundler))
        H.eq(code, 0); H.eq(build_error, "")
        local bundled_text = assert(read(artifact))
        H.eq(read(temporary .. "/dist/word.lua"), bundled_text)
        assert(bundled_text:find('module("word.closure"', 1, true))
        assert(bundled_text:find('module("word.cli"', 1, true))

        local program = temporary .. "/program.lua"
        write(program, [[
local affine = word(U32, U32, function(a, b) return a * 3 + b end)
return {affine = affine}
]])

        -- This launcher clears both Lua search paths before loading the artifact.
        -- bit and jit.util must still come from LuaJIT's host preloaders.
        local launcher = temporary .. "/isolated-cli.lua"
        write(launcher, [[
package.path, package.cpath = "", ""
local bundle = arg[1]
local forwarded = {[0] = bundle}
for i = 2, #arg do forwarded[i - 1] = arg[i] end
arg = forwarded
assert(loadfile(bundle))()
]])
        local direct_code, direct_c, direct_error = run("cd " .. quote(temporary) .. "; luajit " ..
            quote(wordc) .. " " .. quote(program))
        local bundle_code, bundle_c, bundle_error = run("cd " .. quote(temporary) .. "; luajit " ..
            quote(launcher) .. " " .. quote(artifact) .. " " .. quote(program))
        H.eq(direct_code, 0); H.eq(bundle_code, direct_code)
        H.eq(bundle_error, direct_error); H.eq(bundle_c, direct_c)
        assert(bundle_c:find("word_affine", 1, true))

        -- Requiring the only Lua file on package.path returns the API without
        -- starting its CLI. Lexical capture compilation exercises LuaJIT terminal
        -- dumping/cloning from bundled module environments.
        local embed = temporary .. "/embed.lua"
        write(embed, string.format([[
package.path, package.cpath = %q, ""
local Word = require("word")
assert(type(Word.new) == "function" and type(Word.todos) == "function")
local session = Word.new()
local module = session:load_string([=[
local make = word(U32, function(x)
    local add = word(U32, function(y) return x + y end)
    return add(2)
end)
return {f = make}
]=])
assert(session:value(module.f(5)) == 7)
local c = session:emit_c{functions = module}
assert(c:find("word_f", 1, true))
io.write("embedded\n")
]], artifact_directory .. "/?.lua"))
        code, built, build_error = run("cd /; luajit " .. quote(embed))
        H.eq(code, 0); H.eq(built, "embedded\n"); H.eq(build_error, "")

        -- --todos and structured diagnostic statuses are part of the same CLI
        -- contract as wordc.lua, not a second implementation in the bundle.
        local function bundled(argument)
            return run("cd " .. quote(temporary) .. "; luajit " .. quote(launcher) .. " " ..
                quote(artifact) .. " " .. quote(argument))
        end
        local todos_code, todos, todos_error = bundled("--todos")
        local tree_todos_code, tree_todos, tree_todos_error = run("cd " .. quote(temporary) ..
            "; luajit " .. quote(wordc) .. " --todos")
        H.eq(todos_code, 0); H.eq(todos_code, tree_todos_code)
        H.eq(todos, tree_todos); H.eq(todos_error, tree_todos_error)
        assert(todos:find("host-captures", 1, true))

        local bad = temporary .. "/bad.lua"
        write(bad, "return {bad = word(U32, function(x) return x + Bool(true) end)}\n")
        local bad_code, bad_output, bad_error = bundled(bad)
        local tree_bad_code, tree_bad_output, tree_bad_error = run("cd " .. quote(temporary) ..
            "; luajit " .. quote(wordc) .. " " .. quote(bad))
        H.eq(bad_code, 1); H.eq(bad_code, tree_bad_code)
        H.eq(bad_output, tree_bad_output); H.eq(bad_error, tree_bad_error)
        assert(bad_error:find("REJECT [type]", 1, true))

        local resource = temporary .. "/resource.lua"
        write(resource, [[return {large = word(U32, function(x)
    local y = x; for _ = 1, 10001 do y = y + 1 end; return y
end)}
]])
        local resource_code, resource_output, resource_error = bundled(resource)
        local tree_resource_code, tree_resource_output, tree_resource_error = run("cd " .. quote(temporary) ..
            "; luajit " .. quote(wordc) .. " " .. quote(resource))
        H.eq(resource_code, 4); H.eq(resource_code, tree_resource_code)
        H.eq(resource_output, tree_resource_output); H.eq(resource_error, tree_resource_error)
        assert(resource_error:find("RESOURCE [ir-values]", 1, true))

        -- A copied source tree with one real missing literal dependency must fail
        -- at bundle time rather than leaving runtime source fallback to find it.
        local fixture = temporary .. "/missing fixture"
        code, _, build_error = run("mkdir -p -- " .. quote(fixture) .. "; cp -- " ..
            quote(bundler) .. " " .. quote(fixture .. "/bundle.lua") .. "; cp -R -- " ..
            quote(root .. "word") .. " " .. quote(fixture .. "/word"), 10)
        H.eq(code, 0); H.eq(build_error, "")
        local init = assert(read(fixture .. "/word/init.lua"))
        local changed, replacements = init:gsub("\nreturn M\n$",
            '\nrequire("word.bundle_missing_fixture")\nreturn M\n')
        H.eq(replacements, 1); write(fixture .. "/word/init.lua", changed)
        local missing_code, _, missing_error = run("cd /; luajit " .. quote(fixture .. "/bundle.lua") ..
            " " .. quote(fixture .. "/out.lua"))
        assert(missing_code ~= 0)
        assert(missing_error:find("cannot find module 'word.bundle_missing_fixture'", 1, true), missing_error)
    end)

    os.execute("timeout --kill-after=1s 5s rm -rf -- " .. quote(temporary))
    assert(ok, failure)
end)
