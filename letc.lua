-- Usage: luajit letc.lua input.let [output.c [options.lua]]
--
-- Compiles one file and writes the C. `options.lua` is the embedding's: hosts, resources,
-- parameter and result types, an import resolver, and the limits the evaluator runs under.
local path = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') or './'
package.path = path .. '?.lua;' .. path .. '?/init.lua;' .. package.path
local function run()
    if not arg[1] or #arg > 3 then error('usage: luajit letc.lua input.let [output.c [options.lua]]', 0) end
    local input = assert(io.open(arg[1], 'rb'))
    local text = input:read('*a'); input:close()
    local V = require('let')
    local options = arg[3] and dofile(arg[3]) or {}
    local program, builder = V.parse(text, arg[1]):build(options)
    -- This is a host, and it publishes every exported word: §15.1's "the host selects".
    options.entries = options.entries or builder.host_entries
    program:verify_flow(options.hosts or {})
    local source = V.print(program:emit(options))
    if arg[2] then
        local output = assert(io.open(arg[2], 'wb')); output:write(source); output:close()
    else io.write(source) end
end
local ok, err = pcall(run)
if not ok then io.stderr:write(tostring(err), '\n'); os.exit(1) end
