-- luajit bench/emit.lua OUTPUT.c STATS.csv
package.path = './?.lua;./?/init.lua;' .. package.path
local file = assert(io.open('bench/kernels.let', 'rb'))
local text = file:read('*a'); file:close()
local source, _, residual, statistics = require('let').compile(text, 'bench/kernels.let', dofile('bench/vocabulary.lua'))
file = assert(io.open(assert(arg[1]), 'wb')); file:write(source); file:close()
file = assert(io.open(assert(arg[2]), 'wb'))
file:write('function,locals,labels,statements,calls\n')
for _, fn in ipairs(residual.functions) do
    local info = statistics[fn.c_name]
    if info then file:write(('%s,%d,%d,%d,%d\n'):format(fn.c_name, info.locals, info.labels, info.statements, info.calls)) end
end
file:close()

