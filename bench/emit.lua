-- luajit bench/emit.lua OUTPUT.c STATS.csv [--compiler=v1|v2]
--
-- v1 is the original compiler, which emits `let_<case>` functions directly. v2 emits a module:
-- an initializer that builds the namespace, and one entry function per exported word. The host's
-- way in is the entry, so this writes a shim that reads each word's own fields out of the
-- namespace the initializer returned and passes them ahead of the stages the probe supplies.
package.path = './?.lua;./?/init.lua;' .. package.path
local compiler = 'v1'
for _, value in ipairs(arg) do
    local found = value:match('^%-%-compiler=(%w+)$')
    if found then compiler = found end
end
local output, stats_path = arg[1], arg[2]
local file = assert(io.open('bench/kernels.let', 'rb'))
local text = file:read('*a')
file:close()

local function write(path, contents)
    local handle = assert(io.open(path, 'wb'))
    handle:write(contents)
    handle:close()
end

if compiler == 'v2' then
    local V = require('v2')
    local options = dofile('bench/vocabulary_v2.lua')
    local program, builder = V.parse(text, 'bench/kernels.let'):build(options)
    program:verify_flow(options.hosts)
    local statistics = {}
    local unit = program:emit{hosts = options.hosts, resources = options.resources,
        entries = builder.host_entries, statistics = statistics}
    local names = {}
    for _, entry in ipairs(statistics.entries) do names[entry.name] = entry end
    -- One probe per case: the driver calls `let_<case>(int64_t)`, and every timed entry takes one
    -- stage. The word's own fields come from the namespace, which the initializer returns once.
    local shim = {'', '/* Host entry points: the entries, called the way the driver calls them. */'}
    local missing = {}
    local function probe(name)
        local entry = names[name]
        if not entry then missing[#missing + 1] = name; return end
        local index = builder.module_exports[name]
        if index == nil then missing[#missing + 1] = name; return end
        -- The fields the entry's signature kept, read from the namespace the initializer returned,
        -- then the stage the probe supplies.
        local arguments = {}
        for _, field in ipairs(entry.fields) do
            arguments[#arguments + 1] = ('m.r0.f%d.f%d'):format(index, field)
        end
        arguments[#arguments + 1] = 'n'
        shim[#shim + 1] = ('int64_t let_%s(int64_t n){ static int started=0; static struct let_ret_1 m;'
            .. ' if(!started){ m=let_module_init(); started=1; } return %s(%s); }')
            :format(name, entry.c_name, table.concat(arguments, ', '))
    end
    for _, name in ipairs{'constant', 'affine', 'sum_loop', 'sum_tail', 'fib_loop', 'fib_recursive',
        'mix', 'gcd', 'prelude_tail', 'resource_loop', 'resource_tail'} do probe(name) end
    if #missing > 0 then
        io.stderr:write('no host entry for: ' .. table.concat(missing, ', ') .. '\n')
    end
    write(assert(output), V.print(unit) .. table.concat(shim, '\n') .. '\n')
    local rows = {'function,folded,blocks,widened,parameters\n'}
    for _, instance in ipairs(statistics.instances) do
        rows[#rows + 1] = ('%s,%s,%d,%d,%d\n'):format(instance.name, tostring(instance.folded),
            instance.blocks, instance.widened, #instance.parameters)
    end
    for _, entry in ipairs(statistics.entries) do
        rows[#rows + 1] = ('let_%s,entry,,,%d\n'):format(entry.name, entry.stages)
    end
    write(assert(stats_path), table.concat(rows))
else
    local source, _, residual, statistics = require('let').compile(text, 'bench/kernels.let', dofile('bench/vocabulary.lua'))
    write(assert(output), source)
    local rows = {'function,locals,labels,statements,calls\n'}
    for _, fn in ipairs(residual.functions) do
        local info = statistics[fn.c_name]
        if info then rows[#rows + 1] = ('%s,%d,%d,%d,%d\n'):format(fn.c_name, info.locals, info.labels, info.statements, info.calls) end
    end
    write(assert(stats_path), table.concat(rows))
end
