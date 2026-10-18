-- Round-5 probe: what key form must a non-entry loop header take under the
-- "keys are exact" rule?
--
-- The disputed point (Q11): round 3 chose the generic all-location key at a
-- loop header, round 4 chose exact keys everywhere.  Both are *canonicalizations
-- of the incoming key*.  This probe measures the emission each one produces for
-- one loop whose bound and step are compile-time constants known before the
-- header (the documented counter's shape), and compares it with the incumbent's
-- measured output for the documented fixture.
--
-- Emission shapes compared (hand-built ABC, existing assembler/verifier/runtime,
-- incumbent optimizer for idempotence, portable-C sink for the shipped
-- loop-entry rule):
--   P  pre-widened key  = the entry key minus the components the loop body may
--                         write: bound/step stay constants in the key, the
--                         counter and accumulator are C slots.  ONE header body.
--   G  generic key      = every component a C slot (round-3 rule, and the C
--                         sink today).  ONE header body, bound/step read from C.
--   E  exact keys       = one header version per distinct key, budget 8 total
--                         versions per pc; the budget key is all-location.
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
local function write(path, bytes) local f = assert(io.open(path, 'wb')); f:write(bytes); f:close() end
local function listing(path)
  local p = assert(io.popen(string.format('%q dis %q 2>&1', 'build/abc', path)))
  local text = p:read('*a'); local ok = p:close(); return ok and text or nil, text
end
local function run(path, name, mode)
  local p = assert(io.popen(string.format('%q run %q %s --%s 2>&1', 'build/abc', path, name, mode)))
  local text = p:read('*a'); local ok = p:close(); return ok, (text:gsub('%s+$', ''))
end
local function textFile(path)
  local f = assert(io.open(path, 'rb')); local t = f:read('*a'); f:close(); return t
end

local outdir = '.ralphi/optimizer-residual-redesign/experiments/5-loop-key-out'
assert(os.execute('mkdir -p ' .. outdir) == 0)

-- Semantics shared by every shape: acc = sum of i for i = 0, step, ...
-- while i < limit; limit = 120 (fits the i8 immediate branch), step = 7, so
-- the answer is 0+7+...+119 = 7*(0+...+17) = 1071.

-- P: versioned emission, pre-widened header key.  limit=120 and step=7 are
--    constants in the key (the loop body never writes them); the counter and
--    accumulator are C locations.  Every edge into the header canonicalizes to
--    this one key, so there is exactly one body.
local preWidened = [[
.function main 0 1
  PUSH.A 0
  CPUSH.A
  PUSH.A 0
  CPUSH.A
head:
  CGET.A 0
  BLTUI.A 120 body
  CGET.A 1
  RET.A 2 1
body:
  CGET.A 1
  CGET.B 0
  ADD.A
  CSET.A 1
  CGET.A 0
  ADDI.A 7
  CSET.A 0
  JMP head
.export main
]]

-- G: versioned emission, generic header key: every component is a C slot (the
--    round-3 rule, also the shipped portable-C rule).  limit and step are
--    materialized into the frame before the header and read with CGET.
local generic = [[
.function main 0 1
  PUSH.A 120
  CPUSH.A
  PUSH.A 7
  CPUSH.A
  PUSH.A 0
  CPUSH.A
  PUSH.A 0
  CPUSH.A
head:
  CGET.A 0
  CGET.B 3
  BLTU.A body
  CGET.A 1
  RET.A 4 1
body:
  CGET.A 1
  CGET.B 0
  ADD.A
  CSET.A 1
  CGET.A 0
  CGET.B 2
  ADD.A
  CSET.A 0
  JMP head
.export main
]]

-- E: versioned emission, exact header keys, budget 8 total versions per pc
--    (Q2: seven exact versions plus the general one).  The entry key is
--    (i=0, acc=0, limit=120, step=7), all constants, so every header version
--    folds the condition and the update; its body is one jump.  The eighth key
--    is the canonical all-location key (round-4 budget rule), so the tail is a
--    generic body and the surviving constants are materialized at that edge.
local function exactEmission()
  local limit, step = 120, 7
  local acc, i = 0, 0
  local parts = { '.function main 0 1\n' }
  for k = 0, 6 do
    parts[#parts + 1] = ('head%d:\n  JMP head%d\n'):format(k, k + 1)
    acc = acc + i
    i = i + step
  end
  parts[#parts + 1] = ('head7:\n  PUSH.A %d\n  CPUSH.A\n  PUSH.A %d\n  CPUSH.A\n  PUSH.A %d\n  CPUSH.A\n  PUSH.A %d\n  CPUSH.A\n'):format(limit, step, acc, i)
  parts[#parts + 1] = [[
head_generic:
  CGET.A 0
  CGET.B 3
  BLTU.A body
  CGET.A 1
  RET.A 4 1
body:
  CGET.A 1
  CGET.B 0
  ADD.A
  CSET.A 1
  CGET.A 0
  CGET.B 2
  ADD.A
  CSET.A 0
  JMP head_generic
.export main
]]
  return table.concat(parts)
end
local exact = exactEmission()

local cases = {
  { name = 'P-pre-widened', src = preWidened },
  { name = 'G-generic', src = generic },
  { name = 'E-exact', src = exact },
}

local expected = nil
local failures = 0
local function check(ok, message)
  if not ok then failures = failures + 1; print('  FAIL: ' .. message) end
end

for _, case in ipairs(cases) do
  local input = assert(assembler.assemble(case.src))
  local srcPath = outdir .. '/' .. case.name .. '.abc'
  local optPath = outdir .. '/' .. case.name .. '.opt.abc'
  write(srcPath, input)
  local results = {}
  for _, mode in ipairs({ 'interpreted', 'jit=threaded', 'compiled', 'lazy' }) do
    local ok, text = run(srcPath, 'main', mode)
    results[mode] = ok and text or ('FAIL[' .. text .. ']')
    check(ok, case.name .. ': does not run in ' .. mode .. ' (' .. text .. ')')
    if expected == nil then expected = results[mode] end
    check(results[mode] == expected, case.name .. '/' .. mode .. ': result ' .. results[mode] .. ' != ' .. tostring(expected))
  end
  local optimized = optimizer.optimizeMapped(input)
  local second = optimizer.optimize(optimized)
  write(optPath, optimized)
  local okDis, listingText = listing(optPath)
  listingText = listingText or ''
  check(okDis, case.name .. ': optimized module does not disassemble')
  check(second == optimized, case.name .. ': optimized module is not idempotent')
  local limitImmediate = listingText:match('BLTUI_A%s+120') ~= nil
  local stepImmediate = listingText:match('ADDI_A%s+7') ~= nil
  print(('%-15s in %3d out %3d instr  limit-imm=%s step-imm=%s  result=%s'):format(
    case.name, #instructions(code(input)), #instructions(code(optimized)),
    tostring(limitImmediate), tostring(stepImmediate), results.interpreted))
end
check(expected == '1071', 'unexpected result: ' .. tostring(expected))

print('\nP-pre-widened listing (one body; bound and step are immediates):')
print((listing(outdir .. '/P-pre-widened.abc')))
print('\nG-generic listing (one body; bound and step are C-frame reads):')
print((listing(outdir .. '/G-generic.abc')))
print('\nE-exact listing (seven folded header versions, then a generic tail):')
print((listing(outdir .. '/E-exact.abc')))

-- The shipped portable-C sink's loop-entry rule: forget every constant at a
-- loop header (src/residual_builder.c:1090-1091, 1195-1207).  Compile the
-- generic-shape module (a valid ordinary loop) and show the bound/step leave
-- the key and become frame/block values.
do
  local path = outdir .. '/G-generic.abc'
  local cpath = outdir .. '/G-generic.c'
  local p = assert(io.popen(string.format('%q c %q -o %q 2>&1', 'build/abc', path, cpath)))
  local text = p:read('*a'); local ok = p:close()
  print('\nportable-C sink on G-generic: ' .. (ok and 'wrote G-generic.c' or ('failed: ' .. text)))
  if ok then
    local c = textFile(cpath)
    local _, functions = c:gsub('static inline uint64_t abc_aot_function_%d+%s*%(', '')
    print('  generated static functions: ' .. functions)
    print('  bound materialized before the loop: ' .. tostring(c:match('0x0000000000000078') ~= nil))
    local compare = c:match('if%s*%(%s*v_%d+%s*<%s*v_%d+%s*%)')
    print('  loop header compare: ' .. tostring(compare) ..
      ' (a block-argument read, not `v_N<120`: the loop-entry key forgot the constant)')
  end
end

-- The documented fixture: the incumbent's optimized counter.  This is the
-- behavior a new sink must reproduce (frontend/tests/optimize.lua:502,505).
do
  local path = '.ralphi/optimizer-residual-redesign/experiments/4-entry-lattice-out/counter.opt.abc'
  local f = io.open(path, 'rb')
  if f then
    f:close()
    print('\nincumbent optimized counter listing (documented fixture, 53 -> 18):')
    print((listing(path)))
  end
end

print(failures == 0 and 'ALL CHECKS PASSED' or (failures .. ' CHECKS FAILED'))
os.exit(failures == 0 and 0 or 1)
