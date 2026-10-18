-- Round-3 probe: are ABC loop headers / version joins ordinary versions?
-- Three facts tested with hand-built ABC (existing assembler + verifier + runtime,
-- incumbent optimizer through frontend/let/optimize.lua):
--   1. Does abc-opt optimize a function with a local backward branch (loop)?
--      (src/optimize.c:281,283,288 refuses target <= origin)
--   2. Is a "versioned sink" emission shape representable and executable:
--      every version boundary drains A/B into C slots; the target body reads
--      CGET; two predecessors + a backedge jump to ONE shared header body?
--   3. Does the verifier require identical A/B/C shapes at joins (verify.c:284)?
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

-- 1. Source loop: accumulator carried on A across the backedge, n in C.
local sumSource = [[
.function sum 1 1
  PUSH.A 0
head:
  CGET.A 0
  JZ.A done
  CGET.B 0
  ADD.A
  CGET.A 0
  PUSH.B 1
  SUB.A
  CSET.A 0
  JMP head
done:
  RET.A 1 1
.export sum
]]

-- 1b. Control: the same loop body plus arithmetic that is trivially foldable.
--     If output == input, the function was retained, not optimized.
local sumFoldSource = [[
.function sum 1 1
  PUSH.A 0
head:
  CGET.A 0
  JZ.A done
  PUSH.A 5
  PUSH.B 6
  ADD.A
  DROP.A
  CGET.B 0
  ADD.A
  CGET.A 0
  PUSH.B 1
  SUB.A
  CSET.A 0
  JMP head
done:
  RET.A 1 1
.export sum
]]

-- 2. Versioned emission of the same loop: every boundary drains A into C;
--    the one header body reads CGET; forward edge and backedge share its shape.
local sumVersioned = [[
.function sum 1 1
  PUSH.A 0
  CPUSH.A
head:
  CGET.A 1
  JZ.A done
  CGET.A 1
  CGET.B 0
  ADD.A
  CSET.A 0
  CGET.A 1
  PUSH.B 1
  SUB.A
  CSET.A 1
  JMP head
done:
  CGET.A 0
  RET.A 2 1
.export sum
]]

-- 3. Diamond with a computed value on A at the join (source form).
local pickSource = [[
.function pick 2 1
  CGET.A 0
  JZ.A other
  CGET.A 1
  PUSH.B 1
  ADD.A
  JMP join
other:
  CGET.A 1
  PUSH.B 2
  ADD.A
join:
  PUSH.B 3
  ADD.A
  RET.A 2 1
.export pick
]]

-- 4. Versioned emission of that join: each arm drains its value into a C slot
--    and jumps to ONE shared body that reads CGET depth 0.
local pickVersioned = [[
.function pick 2 1
  CGET.A 0
  JZ.A other
  CGET.A 1
  PUSH.B 1
  ADD.A
  CPUSH.A
  JMP join
other:
  CGET.A 1
  PUSH.B 2
  ADD.A
  CPUSH.A
join:
  CGET.A 0
  PUSH.B 3
  ADD.A
  RET.A 3 1
.export pick
]]

-- 5. Negative control: two arms reach one join with different C depths, so the
--    join cannot be shared; the verifier must reject it.
local mismatchedJoin = [[
.function bad 2 1
  CGET.A 0
  JZ.A other
  CGET.A 1
  CPUSH.A
  JMP join
other:
  CGET.A 1
join:
  CGET.A 0
  PUSH.B 3
  ADD.A
  RET.A 3 1
.export bad
]]

local cases = {
  { name = 'sum-source', src = sumSource, fn = 'sum', args = '3', expect = '6' },
  { name = 'sum-fold-source', src = sumFoldSource, fn = 'sum', args = '3', expect = '6' },
  { name = 'sum-versioned', src = sumVersioned, fn = 'sum', args = '3', expect = '6' },
  { name = 'sum-source-n1', src = sumSource, fn = 'sum', args = '1', expect = '1' },
  { name = 'sum-versioned-n1', src = sumVersioned, fn = 'sum', args = '1', expect = '1' },
  { name = 'sum-source-n0', src = sumSource, fn = 'sum', args = '0', expect = '0' },
  { name = 'sum-versioned-n0', src = sumVersioned, fn = 'sum', args = '0', expect = '0' },
  { name = 'pick-source', src = pickSource, fn = 'pick', args = '1 10', expect = '14' },
  { name = 'pick-versioned', src = pickVersioned, fn = 'pick', args = '1 10', expect = '14' },
  { name = 'pick-source-f', src = pickSource, fn = 'pick', args = '0 10', expect = '15' },
  { name = 'pick-versioned-f', src = pickVersioned, fn = 'pick', args = '0 10', expect = '15' },
  { name = 'mismatched-join', src = mismatchedJoin, fn = 'bad', args = '1 10', reject = true },
}

local outdir = '.ralphi/optimizer-residual-redesign/experiments/3-loop-join-out'
assert(os.execute('mkdir -p ' .. outdir) == 0)
local function write(path, bytes) local f = assert(io.open(path, 'wb')); f:write(bytes); f:close() end
local function run(path, name, args, mode)
  local p = assert(io.popen(string.format('%q run %q %s %s --%s 2>&1', 'build/abc', path, name, args, mode)))
  local text = p:read('*a'); local ok = p:close(); return ok, text:gsub('%s+$', '')
end

print(('%-20s %6s %7s %7s %6s %6s  %s'):format('case', 'instr', 'out', 'retain', 'idem', 'ver', 'exec (interp | threaded | compiled | lazy)'))
for _, case in ipairs(cases) do
  local okAssemble, input = pcall(assembler.assemble, case.src)
  if not okAssemble then
    print(('%-20s ASSEMBLER REJECTED: %s'):format(case.name, tostring(input)))
  else
    local path = outdir .. '/' .. case.name .. '.abc'
    write(path, input)
    local modes = {}
    local results = {}
    for _, mode in ipairs({ 'interpreted', 'jit=threaded', 'compiled', 'lazy' }) do
      local ok, text = run(path, case.fn, case.args, mode)
      results[mode] = text
      modes[#modes + 1] = (ok and (case.reject and 'accepted' or text)) or ('FAIL[' .. text .. ']')
    end
    local verdict = ''
    if case.reject then
      -- load/verify runs before execution, so every mode reports the same error
      verdict = 'rejected=' .. tostring(results.interpreted:match('incompatible') ~= nil or results.interpreted:match('invalid') ~= nil)
    else
      for _, mode in ipairs({ 'interpreted', 'jit=threaded', 'compiled', 'lazy' }) do
        local ok = results[mode] == case.expect
        verdict = verdict .. (ok and 'ok ' or ('BAD(' .. results[mode] .. ') '))
      end
    end
    local okOpt, optimized = pcall(optimizer.optimizeMapped, input)
    if not okOpt then
      print(('%-20s %6d %7s %7s %6s %6s  %s'):format(case.name, #instructions(code(input)), '-', '-', '-', '-', verdict))
      print(('  optimizer error: %s'):format(tostring(optimized)))
    else
      local second = optimizer.optimize(optimized)
      local oi, oo = #instructions(code(input)), #instructions(code(optimized))
      print(('%-20s %6d %7d %7s %6s %6s  %s'):format(case.name, oi, oo,
        tostring(optimized == input), tostring(second == optimized),
        tostring(true), verdict))
    end
    -- The portable-C sink is the working precedent for versioned loops/joins.
    if case.name == 'sum-source' or case.name == 'pick-versioned' then
      local target = outdir .. '/' .. case.name .. '.c'
      local okc = os.execute(string.format('%q c %q -o %q >/dev/null 2>&1', 'build/abc', path, target)) == 0
      print(('%-20s portable-C sink: %s'):format('', okc and ('wrote ' .. target) or 'REJECTED'))
    end
  end
end
