-- Round-2 probe: what does abc-opt actually emit on branchy fixtures?
-- Answers: how much code the path tree duplicates, when it gives up (path
-- limit), whether a non-call effect after a branch disables optimization, and
-- whether the documented motivating canonicalization is what is emitted today.
-- This is an experiment, not project tooling.
package.path = 'tools/?.lua;frontend/?.lua;' .. package.path
local assembler = require('assembler')
local manifest = require('opcodes')
local optimizer = require('let.optimize')

local function u32(s, p) local a, b, c, d = s:byte(p, p + 3); return a + b * 256 + c * 65536 + d * 16777216 end
local function code(bytes)
  local p = 17
  for _ = 1, u32(bytes, 9) do
    local tag, n = u32(bytes, p), u32(bytes, p + 4); p = p + 8
    if tag == 2 then return bytes:sub(p, p + n - 1) end
    p = p + n
  end
  error('missing code section')
end
local function instructions(bytes)
  local result = {}; local p = 1
  while p <= #bytes do
    local opcode = bytes:byte(p); local descriptor = manifest.ops[opcode + 1]
    if opcode == 0xf8 or opcode == 0xf9 then descriptor = manifest.ext_ops[bytes:byte(p + 1) + 1] end
    assert(descriptor and descriptor.len > 0, 'invalid emitted encoding')
    local n = descriptor.len
    if descriptor.kind == manifest.kind.SWITCH then n = n + 4 * (bytes:byte(p + 1) + 256 * bytes:byte(p + 2)) end
    result[#result + 1] = { pc = p - 1, name = descriptor.name }
    p = p + n
  end
  return result
end

local function diamonds(n)
  local lines = { ('.function many %d 1'):format(n) }
  for i = 0, n - 1 do
    lines[#lines + 1] = (' CGET.B %d'):format(i)
    lines[#lines + 1] = (' JZ.B d%d'):format(i)
    lines[#lines + 1] = (' PUSH.A %d'):format(i + 1)
    lines[#lines + 1] = (' JMP j%d'):format(i)
    lines[#lines + 1] = ('d%d:'):format(i)
    lines[#lines + 1] = ' PUSH.A 0'
    lines[#lines + 1] = ('j%d:'):format(i)
    lines[#lines + 1] = ' DROP.A'
  end
  -- a fixed, meaningful suffix: every one of the 2^n paths emits it
  lines[#lines + 1] = ' PUSH.A 42'
  for k = 1, 7 do
    lines[#lines + 1] = (' PUSH.B %d'):format(k)
    lines[#lines + 1] = (k % 2 == 0) and ' MUL.A' or ' ADD.A'
  end
  lines[#lines + 1] = (' RET.A %d 1'):format(n)
  lines[#lines + 1] = '.export many'
  return table.concat(lines, '\n')
end

local cases = {
  { name = 'motivating-f', fn = 'f', args = '3 4', expected = '25', source = [[
.function sq 1 1
  CGET.A 0
  CGET.B 0
  MUL.A
  RET.A 1 1
.function f 2 1
  CGET.A 0
  CALL.A sq 1
  CGET.A 1
  CALL.A sq 1
  MOVE.A
  ADD.A
  RET.A 2 1
.export f
]] },
  { name = 'diamond', fn = 'diamond', args = '1', expected = '11', source = [[
.function diamond 1 1
  CGET.A 0
  JZ.A otherwise
  PUSH.A 10
  JMP join
otherwise:
  PUSH.A 20
join:
  PUSH.B 1
  ADD.A
  RET.A 1 1
.export diamond
]] },
  { name = 'phi', fn = 'choose', args = '1', expected = '10 20', source = [[
.function choose 1 2
  CGET.A 0
  JZ.A other
  PUSH.A 10
  PUSH.A 20
  JMP done
other:
  PUSH.A 30
  PUSH.A 40
done:
  RET.A 1 2
.export choose
]] },
  { name = 'choices', fn = 'choices', args = '0', expected = '11', source = [[
.function choices 1 1
  CGET.A 0
  SWITCH.A choice0 choice1
  PUSH.A 9
  JMP choiceDone
choice0:
  PUSH.A 10
  JMP choiceDone
choice1:
  PUSH.A 11
choiceDone:
  PUSH.B 1
  ADD.A
  RET.A 1 1
.export choices
]] },
  { name = 'effect-then-branch', fn = 'main', args = '1', expected = '11', source = [[
.profile memory
.datazero 8
.function main 1 1 i i
  GADDR.A 0
  PUSH.B 7
  ST64.A 0
  CGET.A 0
  JZ.A skip
  PUSH.A 11
  RET.A 1 1
skip:
  PUSH.A 42
  RET.A 1 1
.export main
]] },
  { name = 'branch-then-effect', fn = 'main', args = '1', expected = '42', source = [[
.profile memory
.datazero 8
.function main 1 1 i i
  CGET.A 0
  JZ.A skip
  GADDR.A 0
  PUSH.B 11
  ST64.A 0
skip:
  PUSH.A 42
  RET.A 1 1
.export main
]] },
  { name = 'branch-then-trap', fn = 'main', args = '10 0', expected = nil, source = [[
.function main 2 1
  CGET.A 0
  JZ.A skip
  CGET.B 1
  CGET.A 0
  DIVU.A
  RET.A 2 1
skip:
  PUSH.A 42
  RET.A 2 1
.export main
]] },
  { name = 'branch-then-call', fn = 'main', args = '1', expected = '7', source = [[
.function main 1 1
  CGET.A 0
  JZ.A skip
  CALL.A helper 0
  RET.A 1 1
skip:
  PUSH.A 42
  RET.A 1 1
.function helper 0 1
  PUSH.A 7
  RET.A 0 1
.export main
.export helper
]] },
}

for _, n in ipairs({ 4, 8, 10, 12, 13 }) do
  local args = {}
  for i = 1, n do args[i] = tostring(i % 2) end
  cases[#cases + 1] = { name = 'diamonds-' .. n, fn = 'many', args = table.concat(args, ' '), expected = nil, run = true, source = diamonds(n) }
end

local outdir = '.ralphi/optimizer-residual-redesign/experiments/2-abc-probe-out'
assert(os.execute('mkdir -p ' .. outdir) == 0)
local function write(path, bytes) local f = assert(io.open(path, 'wb')); f:write(bytes); f:close() end
local function run(path, name, args, mode)
  local p = assert(io.popen(string.format('%q run %q %s %s --%s 2>&1', 'build/abc', path, name, args, mode)))
  local text = p:read('*a'); local ok = p:close(); return ok, text:gsub('%s+$', '')
end

print(('%-20s %6s %7s %6s %6s %6s %7s %11s  %s'):format('case', 'instr', 'out', 'retain', 'idem', 'maxdup', 'bytes', 'compile', 'exec'))
for _, case in ipairs(cases) do
  local input = assembler.assemble(case.source)
  local started = os.clock()
  local optimized, map = optimizer.optimizeMapped(input)
  local elapsed = (os.clock() - started) * 1000
  local second = optimizer.optimize(optimized)
  local input_instructions = #instructions(code(input))
  local output_instructions = #instructions(code(optimized))
  local multiplicity = {}
  for _, origin in pairs(map) do multiplicity[origin] = (multiplicity[origin] or 0) + 1 end
  local maxdup = 0
  for _, count in pairs(multiplicity) do if count > maxdup then maxdup = count end end
  local before, after = outdir .. '/' .. case.name .. '.abc', outdir .. '/' .. case.name .. '.opt.abc'
  write(before, input); write(after, optimized)
  local modes = ''
  if case.run then
    local ok1, a = run(before, case.fn, case.args, 'interpreted')
    local ok2, b = run(after, case.fn, case.args, 'interpreted')
    local ok3, c = run(after, case.fn, case.args, 'jit=threaded')
    modes = ((ok1 and ok2 and a == b) and 'interp:ok ' or ('interp:FAIL[' .. tostring(a) .. '|' .. tostring(b) .. '] '))
      .. ((ok3 and c == a) and 'threaded:ok' or ('threaded:FAIL[' .. tostring(c) .. ']'))
  elseif case.expected then
    local ok1, a = run(before, case.fn, case.args, 'interpreted')
    local ok2, b = run(after, case.fn, case.args, 'interpreted')
    local ok3, c = run(after, case.fn, case.args, 'jit=threaded')
    modes = ((ok1 and ok2 and a == b and a == case.expected) and 'interp:ok ' or ('interp:FAIL[' .. tostring(a) .. '|' .. tostring(b) .. '] '))
      .. ((ok3 and c == case.expected) and 'threaded:ok' or ('threaded:FAIL[' .. tostring(c) .. ']'))
  end
  print(('%-20s %6d %7d %6s %6s %6d %7d %8.1fms  %s'):format(case.name, input_instructions, output_instructions,
    tostring(optimized == input), tostring(second == optimized), maxdup, #optimized, elapsed, modes))
end
