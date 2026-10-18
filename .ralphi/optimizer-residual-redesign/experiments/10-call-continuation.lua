-- Round-10 probe: is a residual (non-inlined) direct call a control transfer that
-- ends the caller's version body, or an in-body effect after which the caller
-- continues?  Three existing sinks answer differently in code; this probe shows
-- the two that continue in-body, on emitted ABC and generated C, using the
-- existing compiler / abc-opt / C writer and all four execution modes.
--
-- Fixtures have only NON-TAIL recursive calls, so the inline rule cannot inline
-- them: mutual ping/pong, and a same-function self-recursive f.
--
-- This is an experiment, not project tooling.
package.path = 'tools/?.lua;frontend/?.lua;frontend/?/init.lua;build/?.lua;' .. package.path
local Compiler = require('let.compiler')
local abc = 'build/abc'
local outdir = '.ralphi/optimizer-residual-redesign/experiments/10-call-continuation-out'
os.execute('mkdir -p ' .. outdir)

local function spit(path, data) local f = assert(io.open(path, 'wb')); f:write(data); f:close() end
local function capture(command)
  local pipe = assert(io.popen(command, 'r')); local out = pipe:read('*a'); local ok = pipe:close(); return out, ok
end

-- flatten `abc dis` to { {func=, addr=, text=}, ... } in emission order
local listing = {}
local function parse(listing_text)
  local rows, fn = {}, nil
  for line in listing_text:gmatch('[^\n]+') do
    local header = line:match('^function (%d+):')
    if header then fn = tonumber(header)
    elseif fn and line:match('^%s+%x+%s') then
      local addr, text = line:match('^%s+(%x+)%s+(.-)%s*$')
      rows[#rows + 1] = {func = fn, addr = addr, text = text, opcode = text:match('^(%S+)')}
    end
  end
  return rows
end

local function count(rows, opcode) local n = 0; for _, r in ipairs(rows) do if r.opcode == opcode then n = n + 1 end end; return n end

local function around_call(rows, label)
  print(('  %s: total=%d CALL_=%d TCALL_=%d'):format(label, #rows,
    count(rows, 'CALL_A') + count(rows, 'CALL_B') + count(rows, 'CALLI'),
    count(rows, 'TCALL_A') + count(rows, 'TCALL_B')))
  for i, r in ipairs(rows) do
    local is_call = r.opcode:match('^CALL') or r.opcode:match('^TCALL') or r.opcode == 'CALLI'
    if is_call then
      local next = rows[i + 1]
      print(('    f%d %s  %-18s -> next: %s'):format(r.func, r.addr, r.text,
        next and (next.addr .. '  ' .. next.text) or '<end>'))
      -- CALL_A is 6 bytes: the architecture's return pc is the next instruction.
      -- A version boundary at the return pc would show a jump here (or a CALL
      -- whose return lands at another body's label); post-call computation in
      -- the next slot is the in-body form.
      local cont = next and not (next.opcode == 'JMP' or next.opcode == 'JMP32')
      print(('      successor is %s'):format(next and (cont and 'post-call computation in the same emitted sequence (no transfer)'
        or 'an unconditional jump (a separate body)') or 'nothing'))
    end
  end
end

local function run_modes(path, entry)
  local modes = {}
  for _, mode in ipairs({'off', 'threaded', 'eager', 'lazy'}) do
    local out, ok = capture(('%s run %q %s --jit=%s'):format(abc, path, entry, mode))
    modes[#modes + 1] = ('%s=%s'):format(mode, ok and (out:gsub('%s+$', '')) or 'FAILED')
  end
  return table.concat(modes, ' ')
end

local MUTUAL = [[
let ping(n: U32): U32 = do
  if n == 0 then return 7 end
  return pong(n - 1) + 1
end
let pong(n: U32): U32 = do
  if n == 0 then return 9 end
  return ping(n - 1) + 2
end
let main(): U32 = ping(4)
]]

local SELF = [[
let f(n: U32): U32 = do
  if n == 0 then return 0 end
  return f(n - 1) + 3
end
let main(): U32 = f(5)
]]

local function stage(name, source, entry)
  local compiled = Compiler.compile{profile = 'slet', name = name .. '.slet', source = source}
  local optimized = Compiler.stage(compiled.functions,
    {profile = 'slet', entry = entry, exports = {entry}, mode = 'lazy'})
  local raw = Compiler.stage(compiled.functions,
    {profile = 'slet', entry = entry, exports = {entry}, mode = 'lazy', optimize = false})
  local optPath = outdir .. '/' .. name .. '.opt.abc'
  local rawPath = outdir .. '/' .. name .. '.raw.abc'
  spit(optPath, optimized.module); spit(rawPath, raw.module)
  local optDis, rawDis = capture(('%s dis %q'):format(abc, optPath)), capture(('%s dis %q'):format(abc, rawPath))
  spit(outdir .. '/' .. name .. '.opt.dis', optDis); spit(outdir .. '/' .. name .. '.raw.dis', rawDis)
  local c, okc = capture(('%s c %q -o %s'):format(abc, optPath, outdir .. '/' .. name .. '.c'))
  return optPath, rawPath, optDis, rawDis, okc
end

for _, fixture in ipairs({{name = 'mutual-nontail', src = MUTUAL, entry = 'main'},
                          {name = 'self-nontail', src = SELF, entry = 'main'}}) do
  print(('\n== %s =='):format(fixture.name))
  local optPath, rawPath, optDis, rawDis, okc = stage(fixture.name, fixture.src, fixture.entry)
  local optRows, rawRows = parse(optDis), parse(rawDis)
  local value = capture(('%s run %q %s'):format(abc, optPath, fixture.entry))
  print(('  value: abc-opt=%s  execution: %s'):format(tostring(tonumber(value)), run_modes(optPath, fixture.entry)))
  around_call(rawRows, 'pre-optimizer (shared symbolic machine, no path tree)')
  around_call(optRows, 'abc-opt')
  if okc then print(('  portable-C output: %s'):format(outdir .. '/' .. fixture.name .. '.c')) end
end

print('\n== generated C: where does the residual call live? ==')
for _, fixture in ipairs({{name = 'mutual-nontail'}, {name = 'self-nontail'}}) do
  local f = assert(io.open(outdir .. '/' .. fixture.name .. '.c', 'r')); local c = f:read('*a'); f:close()
  print(('-- %s --'):format(fixture.name))
  local block, lines = nil, {}
  for line in (c .. '\n'):gmatch('([^\n]*)\n') do lines[#lines + 1] = line end
  for i, line in ipairs(lines) do
    if line:match('^block_%d+:') then block = line:match('^(block_%d+):') end
    -- a residual call in generated C is a call statement whose value is used:
    -- `v_N=abc_aot_function_K(...)`; declarations/definitions have no `=` lhs.
    local call = line:match('^%s*[%w_%.%[%]]+%s*=%s*abc_aot_function_%d+%(')
    if call then
      local j, next = i + 1, nil
      while j <= #lines do
        if lines[j]:match('^block_%d+:') then next = lines[j]; break end
        if lines[j]:match('%S') and not lines[j]:match('^%s*[{}]%s*$') then next = (lines[j]:gsub('^%s+', '')); break end
        j = j + 1
      end
      print(('  block %s: %s'):format(tostring(block), (line:gsub('^%s+', ''))))
      print(('    next statement: %s'):format(tostring(next)))
      print(('    %s'):format(next and next:match('^block_') and 'a new block (return-pc boundary)'
        or 'same block: the caller continues in-body after the call'))
    end
  end
end
