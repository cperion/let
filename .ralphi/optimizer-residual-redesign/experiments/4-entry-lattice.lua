-- Round-4 probe: what IS the "single lattice-keyed entry", and where does a
-- cross-function entry key physically occur?
--
-- Round 3 asserted that the documented recursive-counter fixture
-- (frontend/tests/optimize.lua:229) witnesses the entry-fact lattice.  It does
-- not: every non-recursive direct call is inlined (src/optimize.c:302
-- `effect->virtualize=1`) and a nested-eligible self-recursive callee is inlined
-- once as a loop candidate (:301, :309-318), so the whole counter collapses into
-- `main` and its BLTUI_A 50 / ADDI_A 7 come from inline expansion, not from
-- entry facts.  The real witness is a *residual call*, which the incumbent emits
-- only for recursive components it cannot inline (SCC size > 1, a nontail CALL
-- inside the component, or an already-used loop candidate): optimize.c:299-303,
-- 309-318, build_call_graph :108-114.
--
-- Facts tested here, with the existing assembler / optimizer / runtime and the
-- portable-C sink (no source changes):
--   1. The counter inlines into one function (1 emitted function) and the
--      two-root variant produces two independent specializations (no entry join).
--   2. Mutual recursion keeps real residual calls and the callee bodies are
--      specialized by caller argument facts (folded 100-7 and 200-7 where the
--      step is constant, `i` unknown).
--   3. The entry key is joined PER ARGUMENT: two roots passing step 7 vs 9 make
--      the step unknown at the residual entry (no folded 93/193) while the other
--      argument's treatment is unchanged.
--   4. A single root already forces the join: the recursive tail call into the
--      callee's own entry widens `i` after the first call, so the already-walked
--      body cannot be kept (`CGET0_A; JZ_A` survives instead of a folded
--      comparison).  That is why src/optimize.c:870-873 discards the whole
--      function (`clear_function_code`) and rebuilds it when its entry facts
--      change, and why calls are re-encoded only at module-write time (:826-833).
--   5. Cost of the rebuild: N roots passing the same step (no widening after the
--      first call) vs N roots passing distinct steps (widen once, rebuild).
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

-- The documented fixture, copied verbatim from frontend/tests/optimize.lua:229.
local counter = [[
.function main 0 2
  PUSH.A 50
  CALL.A count_to 1
  RET.A 0 2
.function count_to 1 2
  PUSH.A 0
  CPUSH.A
  PUSH.A 0
  CPUSH.A
  CGET.A 0
  CGET.A 1
  CPOP
  CPOP
  CPUSH.A
  CPUSH.A
  PUSH.A 7
  CPUSH.A
  CGET.A 1
  CGET.A 2
  CGET.A 3
  CGET.A 0
  CALL.A loop 4
  RET.A 4 2
.function loop 4 2
  CGET.A 1
  CGET.B 2
  BLTU.A body
  CGET.A 1
  CGET.A 0
  RET.A 4 2
body:
  CGET.A 0
  CGET.A 1
  CGET.A 3
  CALL.A bump 3
  CSET.A 1
  CSET.A 0
  DROP.A
  CGET.A 0
  CGET.A 1
  CGET.A 2
  CGET.A 3
  TCALL.A loop 4 4
.function bump 3 3
  CGET.A 1
  CGET.B 2
  ADD.A
  ZX32.A
  CSET.A 1
  CGET.A 0
  PUSH.B 1
  ADD.A
  ZX32.A
  CSET.A 0
  CGET.A 1
  CGET.A 0
  CGET.A 1
  RET.A 3 3
.export main
]]

-- Second root with a different limit: each root is a separate residual
-- function, so each inlines and specializes its own copy; the module must NOT
-- contain one joined entry (measurement, not expectation).
local counterTwoLimits = counter:gsub('%.export main\n$', '') .. [[
.function alt 0 2
  PUSH.A 40
  CALL.A count_to 1
  RET.A 0 2
.export main
.export alt
]]

-- Mutual recursion: SCC size 2 => recursive but never `nested_eligible`
-- (optimize.c:113), so every call between even/odd is a real residual call.
-- `i` is decremented (must widen to unknown), `step` is carried unchanged
-- (must stay constant and fold into the callee's done case and call sites).
local mutual = [[
.function main 0 1
  PUSH.A 50
  PUSH.A 7
  CALL.A even 2
  RET.A 0 1
.function even 2 1
  CGET.A 0
  JZ.A even_done
  CGET.A 0
  PUSH.B 1
  SUB.A
  CGET.A 1
  TCALL.A odd 2 2
even_done:
  PUSH.A 100
  CGET.B 1
  SUB.A
  RET.A 2 1
.function odd 2 1
  CGET.A 0
  JZ.A odd_done
  CGET.A 0
  PUSH.B 1
  SUB.A
  CGET.A 1
  TCALL.A even 2 2
odd_done:
  PUSH.A 200
  CGET.B 1
  SUB.A
  RET.A 2 1
.export main
]]

-- Same mutual recursion with two roots: step 7 vs step 9.  The residual callee
-- entry key must widen per argument (step unknown), so neither 93 nor 193 can
-- stay folded; the runtime results must still match the source for both roots.
local mutualTwoSteps = mutual:gsub('%.export main\n$', '') .. [[
.function alt 0 1
  PUSH.A 50
  PUSH.A 9
  CALL.A even 2
  RET.A 0 1
.export main
.export alt
]]

-- N roots over mutual recursion: same step (no widening after the first call
-- fact) vs distinct steps (one widening + one rebuild of each callee).
local function mutualMany(stepOf)
  local parts = { [[
.function even 2 1
  CGET.A 0
  JZ.A even_done
  CGET.A 0
  PUSH.B 1
  SUB.A
  CGET.A 1
  TCALL.A odd 2 2
even_done:
  PUSH.A 100
  CGET.B 1
  SUB.A
  RET.A 2 1
.function odd 2 1
  CGET.A 0
  JZ.A odd_done
  CGET.A 0
  PUSH.B 1
  SUB.A
  CGET.A 1
  TCALL.A even 2 2
odd_done:
  PUSH.A 200
  CGET.B 1
  SUB.A
  RET.A 2 1
]] }
  local exports = {}
  for i = 1, 40 do
    parts[#parts + 1] = ('.function root%d 0 1\n  PUSH.A 50\n  PUSH.A %d\n  CALL.A even 2\n  RET.A 0 1\n'):format(i, stepOf(i))
    exports[#exports + 1] = ('.export root%d\n'):format(i)
  end
  return table.concat(parts) .. table.concat(exports)
end

local outdir = '.ralphi/optimizer-residual-redesign/experiments/4-entry-lattice-out'
assert(os.execute('mkdir -p ' .. outdir) == 0)
local function write(path, bytes) local f = assert(io.open(path, 'wb')); f:write(bytes); f:close() end
local function listing(path)
  local p = assert(io.popen(string.format('%q dis %q 2>&1', 'build/abc', path)))
  local text = p:read('*a'); local ok = p:close(); return ok and text or nil, text
end
local function run(path, name, mode)
  local p = assert(io.popen(string.format('%q run %q %s --%s 2>&1', 'build/abc', path, name, mode)))
  local text = p:read('*a'); local ok = p:close(); return ok, (text:gsub('%s+$', ''))
end
local function timed(fn, n)
  local t = os.clock(); for _ = 1, n do fn() end; return (os.clock() - t) * 1000 / n
end
local function countFunctions(text)
  local _, n = text:gsub('function %d+:', '')
  return n
end

local cases = {
  { name = 'counter', src = counter, roots = { 'main' }, expectFunctions = 1,
    must = { 'BLTUI_A%s+50', 'ADDI_A%s+7' }, mustNot = { 'CALL_A' } },
  { name = 'counter-two-limits', src = counterTwoLimits, roots = { 'main', 'alt' }, expectFunctions = 2,
    must = { 'BLTUI_A%s+50', 'BLTUI_A%s+40', 'ADDI_A%s+7' }, mustNot = {} },
  { name = 'mutual', src = mutual, roots = { 'main' }, expectFunctions = 3,
    must = { 'PUSH%d*_A%s+7', 'PUSH%d*_A%s+93', 'PUSH%d*_A%s+193', 'CALL_A', 'TCALL_A' },
    mustNot = { 'ADDI_A%s+50' } },
  { name = 'mutual-two-steps', src = mutualTwoSteps, roots = { 'main', 'alt' }, expectFunctions = 4,
    must = { 'CALL_A' }, mustNot = { 'PUSH%d*_A%s+93', 'PUSH%d*_A%s+193' } },
}

local failures = 0
local function check(ok, message)
  if not ok then failures = failures + 1; print('  FAIL: ' .. message) end
end

for _, case in ipairs(cases) do
  local input = assert(assembler.assemble(case.src))
  local srcPath = outdir .. '/' .. case.name .. '.abc'
  local optPath = outdir .. '/' .. case.name .. '.opt.abc'
  write(srcPath, input)
  local expected = {}
  for _, root in ipairs(case.roots) do
    expected[root] = {}
    for _, mode in ipairs({ 'interpreted', 'jit=threaded', 'compiled', 'lazy' }) do
      local ok, text = run(srcPath, root, mode)
      expected[root][mode] = ok and text or ('SOURCE-FAIL[' .. text .. ']')
    end
  end
  local optimized = optimizer.optimizeMapped(input)
  local second = optimizer.optimize(optimized)
  write(optPath, optimized)
  local okDis, listingText = listing(optPath)
  listingText = listingText or ''
  check(okDis, case.name .. ': optimized module does not disassemble')
  local functions = countFunctions(listingText)
  check(functions == case.expectFunctions,
    case.name .. ': expected ' .. case.expectFunctions .. ' functions, got ' .. functions)
  local folds = {}
  for _, pattern in ipairs(case.must) do
    local found = listingText:match(pattern) ~= nil
    folds[#folds + 1] = (found and '+' or 'MISSING!') .. ' ' .. pattern:gsub('%%s%+', ' '):gsub('%%d%*', '*')
    check(found, case.name .. ': expected /' .. pattern .. '/ in optimized listing')
  end
  for _, pattern in ipairs(case.mustNot) do
    local found = listingText:match(pattern) ~= nil
    folds[#folds + 1] = (found and 'PRESENT!' or '-') .. ' ' .. pattern:gsub('%%s%+', ' '):gsub('%%d%*', '*')
    check(not found, case.name .. ': unexpected /' .. pattern .. '/ in optimized listing')
  end
  local verdict = {}
  for _, root in ipairs(case.roots) do
    for _, mode in ipairs({ 'interpreted', 'jit=threaded', 'compiled', 'lazy' }) do
      local ok, text = run(optPath, root, mode)
      local same = ok and text == expected[root][mode]
      verdict[#verdict + 1] = same and 'ok' or ('BAD(' .. tostring(text) .. ')')
      check(same, case.name .. '/' .. root .. ': optimized != source in ' .. mode)
    end
  end
  print(('%-18s in %4d out %4d funcs %d idem %s  folds[%s] exec[%s]'):format(
    case.name, #instructions(code(input)), #instructions(code(optimized)), functions,
    tostring(second == optimized), table.concat(folds, '; '), table.concat(verdict, ' ')))
  local roots = {}
  for _, root in ipairs(case.roots) do roots[#roots + 1] = root .. '=' .. expected[root].interpreted end
  print(('%-18s source results: %s'):format('', table.concat(roots, ' ')))
end

-- Byte fixpoint of the residual-entry module (widening must converge).
do
  local input = assert(assembler.assemble(mutual))
  local first, second, third = optimizer.optimize(input), nil, nil
  second = optimizer.optimize(first); third = optimizer.optimize(second)
  check(second == first and third == second, 'mutual: not a byte fixpoint')
  print(('%-18s opt(opt(x)) == opt(x) == opt(opt(opt(x))): %s (%d bytes)'):format(
    'mutual-fixpoint', tostring(second == first), #first))
end

-- Cost of the entry-fact fixpoint: identical call facts vs widening call facts.
do
  local same = assert(assembler.assemble(mutualMany(function() return 7 end)))
  local diff = assert(assembler.assemble(mutualMany(function(i) return 6 + i end)))
  write(outdir .. '/mutual-many-same.abc', same)
  write(outdir .. '/mutual-many-diff.abc', diff)
  local msSame = timed(function() optimizer.optimizeMapped(same) end, 10)
  local msDiff = timed(function() optimizer.optimizeMapped(diff) end, 10)
  local sameOut = optimizer.optimizeMapped(same)
  local diffOut = optimizer.optimizeMapped(diff)
  local function folds(bytes)
    local path = outdir .. '/tmp.opt.abc'
    write(path, bytes)
    local _, text = listing(path)
    return text:match('PUSH%d*_A%s+93') ~= nil, text:match('PUSH%d*_A%s+193') ~= nil
  end
  local same93 = folds(sameOut)
  local diff93, diff193 = folds(diffOut)
  check(same93, 'many-same: folded 93 expected')
  check(not diff93 and not diff193, 'many-diff: folded 93/193 must be gone')
  print(('%-18s same-step %.2f ms (folded 93=%s)   distinct-step %.2f ms (folded 93=%s 193=%s)'):format(
    'many-roots-40', msSame, tostring(same93), msDiff, tostring(diff93), tostring(diff193)))
end

-- The same residual boundary through the portable-C sink: it passes NULL
-- argument facts (src/residual_c.c:1239) and its embedded/virtual entries keep
-- incoming constants (src/residual_builder.c:898-933); the lattice API in
-- src/residual_analysis.c:215-266 has no caller.
do
  local ok = os.execute(string.format('%q c %q -o %q >/dev/null 2>&1', 'build/abc',
    outdir .. '/mutual.abc', outdir .. '/mutual.c')) == 0
  local text = ''
  if ok then local f = assert(io.open(outdir .. '/mutual.c', 'rb')); text = f:read('*a'); f:close() end
  print(('%-18s portable-C sink: %s, static functions=%d, literal 93=%s, literal 193=%s'):format(
    'mutual.c', ok and 'wrote' or 'REJECTED', select(2, text:gsub('\nstatic ', '')),
    tostring(text:match('%f[%d]93%f[^%d]') ~= nil), tostring(text:match('%f[%d]193%f[^%d]') ~= nil)))
end

print(failures == 0 and '\nALL CHECKS PASSED' or ('\n' .. failures .. ' CHECKS FAILED'))
os.exit(failures == 0 and 0 or 1)
