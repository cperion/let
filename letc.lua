-- Usage: luajit letc.lua input.let [output.c [options.lua]]
--
-- The command-line host lives in `let/cli.lua`, so this file only finds the module tree and runs
-- it; the bundled `dist/let.lua` runs the same code.
local path = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') or './'
package.path = path .. '?.lua;' .. path .. '?/init.lua;' .. package.path
local ok, err = pcall(function() require('let.cli')(require('let'), arg) end)
if not ok then io.stderr:write(tostring(err), '\n'); os.exit(1) end
