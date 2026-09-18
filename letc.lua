-- Usage: luajit letc.lua input.let [-o output.c]
--
-- The launcher only finds the module tree; the compiler is `let/cli.lua`, so the same code runs from a
-- checkout, from a symlink, and from a bundle.
local path = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') or './'
package.path = path .. '?.lua;' .. path .. '?/init.lua;' .. package.path

local ok, err = pcall(function() os.exit(require('let.cli')(require('let'))(arg)) end)
if not ok then
    io.stderr:write('letc: ', tostring(err), '\n')
    os.exit(2)
end
