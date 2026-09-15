-- luajit bench/emit.lua OUTPUT.c STATS.csv
--
-- Emits the kernel set and appends a shim that exposes each exported word as `let_<case>` for the
-- driver: a host reaches a word through its entry, passing the word's own fields -- which the host
-- reads from the namespace the initializer returned -- and then the stages it still needs.
package.path = './?.lua;./?/init.lua;' .. package.path
local output, stats_path = arg[1], arg[2]
local file = assert(io.open('bench/kernels.let', 'rb'))
local text = file:read('*a')
file:close()

local function write(path, contents)
    local handle = assert(io.open(path, 'wb'))
    handle:write(contents)
    handle:close()
end

local V = require('let')
local options = dofile('bench/vocabulary.lua')
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
    -- The probe supplies one Int; an entry only takes it when its signature kept that stage,
    -- since a stage the body never reads is not part of the ABI.
    if entry.stages > 1 then missing[#missing + 1] = name .. ' (wants ' .. entry.stages .. ' stages)' end
    for _ = 1, math.min(entry.stages, 1) do arguments[#arguments + 1] = 'n' end
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
