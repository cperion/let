-- LuaJIT orchestration; native C timing loops keep Lua/FFI overhead out of results.
local ffi, bit = require('ffi'), require('bit')
ffi.cdef [[
typedef struct { long tv_sec; long tv_nsec; } bench_timespec;
int clock_gettime(int clock, bench_timespec *time);
char *realpath(const char *path, char *resolved);
char *getcwd(char *buffer, size_t size);
int chdir(const char *path);
int sched_getaffinity(int pid, size_t size, void *mask);
]]
local clock = ffi.new('bench_timespec[1]')
local function now()
    assert(ffi.C.clock_gettime(1, clock) == 0)
    return tonumber(clock[0].tv_sec) + tonumber(clock[0].tv_nsec) * 1e-9
end
local function read(path) local f = assert(io.open(path, 'rb')); local s = f:read('*a'); f:close(); return s end
local function write(path, text) local f = assert(io.open(path, 'wb')); f:write(text); f:close() end
local function quote(value) return "'" .. tostring(value):gsub("'", "'\\''") .. "'" end
local function join(...)
    local result = {}
    for i = 1, select('#', ...) do for _, value in ipairs(select(i, ...)) do result[#result + 1] = value end end
    return result
end
local function run(command, cpu)
    if cpu then command = join({'taskset', '-c', tostring(cpu)}, command) end
    local words = {}; for _, word in ipairs(command) do words[#words + 1] = quote(word) end
    local output, errors = os.tmpname(), os.tmpname()
    local shell = table.concat(words, ' ') .. ' >' .. quote(output) .. ' 2>' .. quote(errors)
    local start = now(); local status = os.execute(shell); local elapsed = now() - start
    local stdout, stderr = read(output), read(errors); os.remove(output); os.remove(errors)
    assert(status == 0 or status == true, ('command failed (%s): %s\n%s%s'):format(tostring(status), shell, stdout, stderr))
    return stdout, stderr, elapsed
end
local function absolute(path)
    local buffer = ffi.new('char[4096]')
    assert(ffi.C.realpath(path, buffer) ~= nil, 'cannot resolve path: ' .. path)
    return ffi.string(buffer)
end
local function serialize(value, depth)
    depth = depth or 0
    if type(value) == 'string' then return string.format('%q', value) end
    if type(value) ~= 'table' then return tostring(value) end
    local keys, lines = {}, {'{'}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) if type(a) == type(b) then return a < b end; return tostring(a) < tostring(b) end)
    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.rep('  ', depth + 1) .. '[' .. serialize(key) .. '] = ' .. serialize(value[key], depth + 1) .. ','
    end
    lines[#lines + 1] = string.rep('  ', depth) .. '}'
    return table.concat(lines, '\n')
end
local function save_table(path, value) write(path, 'return ' .. serialize(value) .. '\n') end
local function median(values)
    table.sort(values); local middle = math.floor(#values / 2)
    return #values % 2 == 1 and values[middle + 1] or (values[middle] + values[middle + 1]) / 2
end
local function symbols(path)
    local result = {}
    for line in run({'nm', '-S', '--defined-only', path}):gmatch('[^\r\n]+') do
        local size, kind, name = line:match('^%x+%s+(%x+)%s+(%a)%s+(%S+)$')
        if size and kind:lower() == 't' then result[name] = tonumber(size, 16) end
    end
    return result
end
local function text_size(path)
    local total = 0
    for line in run({'size', '-A', path}):gmatch('[^\r\n]+') do
        local section, size = line:match('^(%S+)%s+(%d+)')
        if section and section:match('^%.text') then total = total + tonumber(size) end
    end
    return total
end
-- Fixed unquoted CSV from our native driver; checksums stay strings (full u64).
local function samples_from(text)
    local result, fields = {}, nil
    for line in text:gmatch('[^\r\n]+') do
        local values = {}; for value in (line .. ','):gmatch('(.-),') do values[#values + 1] = value end
        if not fields then fields = values
        else
            assert(#values == #fields, 'invalid native benchmark row')
            local row = {}; for i, name in ipairs(fields) do row[name] = values[i] end
            result[#result + 1] = row
        end
    end
    assert(#result > 0, 'native benchmark produced no samples'); return result
end
local function parse_options(root, cwd)
    local options = { cc = 'gcc', out = root .. '/bench/out', opts = {'O0', 'O2', 'O3'}, samples = 7, seconds = 0.02, cflags = {} }
    local i = 1
    while i <= #arg do
        local key, value = arg[i]:match('^(%-%-[^=]+)=(.*)$'); key = key or arg[i]
        if key == '--help' then
            print('luajit bench/run.lua [--cc gcc] [--out DIR] [--opts O0 O2 O3]')
            print('  [--samples 7] [--seconds 0.02] [--cpu N] [--native] [--cflag=-FLAG]'); return
        elseif key == '--native' then options.native = true
        elseif key == '--opts' then
            options.opts = {}
            if value then for opt in value:gmatch('[^,]+') do options.opts[#options.opts + 1] = opt end
            else while arg[i + 1] and not arg[i + 1]:match('^%-%-') do i = i + 1; options.opts[#options.opts + 1] = arg[i] end end
        else
            if value == nil then i = i + 1; value = assert(arg[i], 'missing value for ' .. key) end
            if key == '--cc' then options.cc = value
            elseif key == '--out' then options.out = value
            elseif key == '--samples' then options.samples = assert(tonumber(value))
            elseif key == '--seconds' then options.seconds = assert(tonumber(value))
            elseif key == '--cpu' then options.cpu = assert(tonumber(value))
            elseif key == '--cflag' then options.cflags[#options.cflags + 1] = value
            else error('unknown option: ' .. key) end
        end
        i = i + 1
    end
    assert(options.samples >= 3 and options.samples <= 31 and options.samples % 1 == 0, 'samples must be 3..31')
    assert(options.seconds >= 0.001 and options.seconds <= 1, 'seconds must be 0.001..1')
    local seen, opts = {}, {}
    for _, opt in ipairs(options.opts) do
        assert(opt == 'O0' or opt == 'O2' or opt == 'O3', 'invalid optimization level: ' .. opt)
        if not seen[opt] then opts[#opts + 1] = opt; seen[opt] = true end
    end
    assert(#opts > 0, 'at least one optimization level is required'); options.opts = opts
    if options.out:sub(1, 1) ~= '/' then options.out = cwd .. '/' .. options.out end
    return options
end
local function main()
    local cwd_buffer = ffi.new('char[4096]'); assert(ffi.C.getcwd(cwd_buffer, 4096) ~= nil)
    local script = absolute(debug.getinfo(1, 'S').source:sub(2))
    local root = assert(script:match('^(.*)/bench/[^/]+$'), 'runner must live in bench/')
    local options = parse_options(root, ffi.string(cwd_buffer)); if not options then return end
    assert(ffi.C.chdir(root) == 0)
    run({'mkdir', '-p', '--', options.out}); local out = absolute(options.out)
    local mask, allowed, allowed_set = ffi.new('uint8_t[128]'), {}, {}
    assert(ffi.C.sched_getaffinity(0, ffi.sizeof(mask), mask) == 0, 'sched_getaffinity failed')
    for cpu = 0, 1023 do
        if bit.band(mask[math.floor(cpu / 8)], bit.lshift(1, cpu % 8)) ~= 0 then allowed[#allowed + 1] = cpu; allowed_set[cpu] = true end
    end
    local cpu = options.cpu or allowed[1]; assert(allowed_set[cpu], 'selected CPU is outside the allowed affinity mask')
    local version = run({options.cc, '--version'}):match('[^\r\n]+')
    local model = read('/proc/cpuinfo'):match('model name%s*:%s*([^\n]+)') or 'unknown'
    local common = join({'-std=c99', '-fno-lto'}, options.native and {'-march=native'} or {}, options.cflags)
    save_table(out .. '/environment.lua', { compiler = version, backend = 'partial-evaluation-c', runner = jit.version, cpu = model, pinned_cpu = cpu,
        target = run({options.cc, '-dumpmachine'}):match('%S+'), allowed_cpus = allowed, flags = common,
        samples = options.samples, minimum_batch_seconds = options.seconds, optimization_levels = options.opts, driver_and_host_optimization = 'O2' })
    local _, _, emission = run({'luajit', root .. '/bench/emit.lua', out .. '/generated.c', out .. '/residual.csv'})
    local generated = read(out .. '/generated.c'); local _, lines = generated:gsub('\n', '\n')
    local metrics = { emission_ms = emission * 1000, generated_c_bytes = #generated, generated_c_lines = lines, builds = {} }
    print(('%s\n%s; pinned CPU %d\nLet -> C: %.1f ms'):format(version, model, cpu, emission * 1000))
    for _, name in ipairs{'driver', 'host'} do
        local stdout, stderr = run(join({options.cc}, common, {'-O2', '-c', root .. '/bench/' .. name .. '.c', '-o', out .. '/' .. name .. '.o'}))
        write(out .. '/' .. name .. '.log', stdout .. stderr)
    end
    local summary, raw = {}, {'optimization,case,implementation,sample,repetitions,ns_per_call,checksum\n'}
    for _, opt in ipairs(options.opts) do
        local objects, sizes = {}, {}
        for _, name in ipairs{'Let', 'C'} do
            local source = name == 'Let' and out .. '/generated.c' or root .. '/bench/reference.c'
            local stem = name:lower() .. '-' .. opt; local object = out .. '/' .. stem .. '.o'
            local command = join({options.cc}, common, {'-' .. opt, '-fopt-info-vec-all=' .. out .. '/' .. stem .. '.vectorization.txt',
                '-fdump-tree-optimized=' .. out .. '/' .. stem .. '.optimized', '-c', source, '-o', object})
            os.remove(out .. '/' .. stem .. '.vectorization.txt') -- GCC otherwise appends on reruns.
            local stdout, stderr, duration = run(command); write(out .. '/' .. stem .. '.log', stdout .. stderr)
            write(out .. '/' .. stem .. '.asm', run({'objdump', '-dr', '-Mintel', object}))
            sizes[name], objects[name] = symbols(object), object
            metrics.builds[stem] = { compile_ms = duration * 1000, text_bytes = text_size(object), symbols = sizes[name], command = command }
        end
        local executable = out .. '/bench-' .. opt
        run({options.cc, '-fno-lto', out .. '/driver.o', out .. '/host.o', objects.Let, objects.C, '-o', executable})
        local csv, stderr = run({executable, options.samples, options.seconds}, cpu)
        write(out .. '/' .. opt .. '.csv', csv); write(out .. '/' .. opt .. '.run.log', stderr)
        local samples, cases, groups = samples_from(csv), {}, {}
        for _, sample in ipairs(samples) do
            local name = sample.case
            if not groups[name] then cases[#cases + 1] = name; groups[name] = {Let = {}, C = {}} end
            local values = assert(groups[name][sample.implementation]); values[#values + 1] = assert(tonumber(sample.ns_per_call))
            raw[#raw + 1] = table.concat({opt, name, sample.implementation, sample.sample, sample.repetitions, sample.ns_per_call, sample.checksum}, ',') .. '\n'
        end
        print(('\n%-3s  %-18s %12s %12s %8s %10s %9s'):format(opt, 'case', 'Let ns', 'C ns', 'Let/C', 'Let bytes', 'C bytes'))
        for _, name in ipairs(cases) do
            local g = groups[name]; assert(#g.Let == options.samples and #g.C == options.samples)
            local let, reference = median(g.Let), median(g.C)
            local row = { optimization = opt, case = name, let_ns = let, c_ns = reference, ratio = let / reference,
                let_min_ns = g.Let[1], let_max_ns = g.Let[#g.Let], c_min_ns = g.C[1], c_max_ns = g.C[#g.C],
                let_bytes = sizes.Let['let_' .. name], c_bytes = sizes.C['ref_' .. name] }
            summary[#summary + 1] = row
            print(('%-3s  %-18s %12.2f %12.2f %8.2f %10d %9d'):format(opt, name, let, reference, row.ratio, row.let_bytes, row.c_bytes))
        end
    end
    save_table(out .. '/metrics.lua', metrics); save_table(out .. '/summary.lua', summary); write(out .. '/timings.csv', table.concat(raw))
    local report = {'# GCC probe results', '', '- Runner: `' .. jit.version .. '`', '- Compiler: `' .. version .. '`',
        '- CPU: ' .. model .. '; pinned CPU ' .. cpu, '- Kernel flags: `' .. table.concat(common, ' ') .. '` plus each optimization level; driver/host always `-O2`.',
        ('- Median of %d alternating samples; calibrated batches >= %gs.'):format(options.samples, options.seconds),
        '- Correctness and allocation/release counts checked before timing.',
        '- Lower Let/C is better. Function sizes exclude separately emitted helpers/callees.', '',
        '| Level | Case | Let ns/call | C ns/call | Let/C | Let function bytes | C function bytes |',
        '|---|---|---:|---:|---:|---:|---:|'}
    for _, row in ipairs(summary) do
        report[#report + 1] = ('| %s | %s | %.2f | %.2f | %.2f | %d | %d |'):format(row.optimization, row.case, row.let_ns, row.c_ns, row.ratio, row.let_bytes, row.c_bytes)
    end
    write(out .. '/summary.md', table.concat(report, '\n') .. '\n')
    for _, name in ipairs{'environment.json', 'metrics.json', 'summary.json', 'graph.csv'} do os.remove(out .. '/' .. name) end
    print('\nRetained C, assembly, GIMPLE, vectorization reports, CSV samples and Lua summaries in ' .. out)
end
local ok, err = pcall(main)
if not ok then io.stderr:write(tostring(err), '\n'); os.exit(1) end

