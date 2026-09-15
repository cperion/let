-- Usage: luajit letc.lua input.let [output.c [host-config.lua]]
local path = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') or './'
package.path = path .. '?.lua;' .. path .. '?/init.lua;' .. package.path
local function run()
    if not arg[1] or #arg > 3 then error('usage: luajit letc.lua input.let [output.c [host-config.lua]]', 0) end
    local input = assert(io.open(arg[1], 'rb'))
    local text = input:read('*a'); input:close()
    local options = arg[3] and dofile(arg[3]) or nil
    local source = require('let').compile(text, arg[1], options)
    if arg[2] then
        local output = assert(io.open(arg[2], 'wb')); output:write(source); output:close()
    else io.write(source) end
end
local ok, err = pcall(run)
if not ok then io.stderr:write(tostring(err), '\n'); os.exit(1) end

