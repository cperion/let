-- Round-9 probe: what does a canonical in-repo fixture pin about residual
-- entries, and can the design's generic (all-location) entry key reproduce it?
--
-- The fixture is frontend/tests/compiler.lua:790-804 verbatim: mutual tail
-- recursion even/odd with an invariant `marker`, staged with the default
-- optimize=true.  So the module that test disassembles is abc-opt output, and it
-- asserts 3 functions, a TCALL, and both `PUSH8_A 9` and `PUSH8_A 10`.
-- docs/abc-opt.md:100 documents the same behavior ("mutual or genuinely
-- non-tail SCC transfers remain explicit CALL/TCALL operations while invariant
-- arguments still specialize").
--
-- Facts measured here with the existing compiler, assembler/verifier, abc-opt,
-- four execution modes.  No source changes.
--   A. monomorphic callers (marker = 9): the two callee bodies fold marker to 9
--      and marker+1 to 10.  The pre-optimizer module does not (it reads C4/C3
--      and adds), so the fold is abc-opt's residual-entry argument facts
--      (src/optimize.c:850-873), not frontend lowering.
--   B. two callers disagreeing on marker (9 and 7): the entry join widens
--      marker, and each callee body becomes exactly the shape a GENERIC entry
--      must have -- marker read from a C slot.  The incumbent therefore already
--      emits the design's entry-policy callee bodies whenever callers disagree,
--      so B is the measured oracle for the design's rule on the identical
--      source.  (The portable-C sink is NOT an oracle here: it consumes
--      already-folded abc-opt residue and still prints 9/10.)
--   C. The design's residual entry is the all-location key (no constants can
--      cross a residual call), so its output is B-shaped even in the
--      monomorphic case: the delta is the measured cost of deleting the entry
--      lattice.  It is 2 instructions in odd's body (9 -> 11), module 21 -> 23.
--   D. All four modes return the same value for every variant.
--
-- This is an experiment, not project tooling.
package.path = 'tools/?.lua;frontend/?.lua;frontend/?/init.lua;build/?.lua;' .. package.path
local Compiler = require('let.compiler')
local abc = 'build/abc'
local outdir = '.ralphi/optimizer-residual-redesign/experiments/9-tail-cycle-out'
os.execute('mkdir -p ' .. outdir)

local function spit(path, data) local f = assert(io.open(path, 'wb')); f:write(data); f:close() end
local function slurp(path) local f = assert(io.open(path, 'rb')); local data = f:read('*a'); f:close(); return data end
local function capture(command)
  local pipe = assert(io.popen(command, 'r')); local out = pipe:read('*a'); local ok = pipe:close(); return out, ok
end
local function plain(haystack, needle)
  local n, at = 0, 1
  while true do
    local found = haystack:find(needle, at, true)
    if not found then return n end
    n, at = n + 1, found + #needle
  end
end

-- Parses `abc dis` into { {header=..., body={ {addr=,text=}, ... } }, ... }.
local function functions(listing)
  local result, current = {}, nil
  for line in listing:gmatch('[^\n]+') do
    local header = line:match('^function (%d+):')
    if header then
      current = {index = tonumber(header), header = line, body = {}}
      result[#result + 1] = current
    elseif current and line:match('^%s+%x+%s') then
      local addr, text = line:match('^%s+(%x+)%s+(.-)%s*$')
      local opcode = text:match('^(%S+)')
      current.body[#current.body + 1] = {addr = addr, opcode = opcode, text = text}
    end
  end
  return result
end

local function describe(name, listing)
  local fs = functions(listing)
  local total = 0
  local columns = {}
  for _, fn in ipairs(fs) do
    local ops = {}
    for _, instruction in ipairs(fn.body) do ops[instruction.opcode] = (ops[instruction.opcode] or 0) + 1 end
    total = total + #fn.body
    columns[#columns + 1] = ('f%d:%d/%s%s'):format(fn.index, #fn.body,
      (ops.PUSH8_A and plain(listing, 'PUSH8_A') >= 0) and '' or '', '')
  end
  print(('%-22s %s   total=%d'):format(name, table.concat(columns, ' '), total))
  for _, fn in ipairs(fs) do
    local body = {}
    for _, instruction in ipairs(fn.body) do body[#body + 1] = instruction.text end
    print(('    f%d: %s'):format(fn.index, table.concat(body, ' | ')))
  end
end

local SCRIPT = [[
let even(n: U32, marker: U32): U32 = do
  if n == 0 then return marker end
  return odd(n - 1, marker)
end
let odd(n: U32, marker: U32): U32 = do
  if n == 0 then return marker + 1 end
  return even(n - 1, marker)
end
let main(): U32 = MAIN_CALL
]]

local variants = {
  {name = 'monomorphic', call = 'even(4, 9)'},
  {name = 'two-callers', call = 'even(4, 9) + even(4, 7)'},
}

print('== A/B/D. canonical fixture: abc-opt vs pre-optimizer vs generic-entry oracle ==')
for _, variant in ipairs(variants) do
  local source = SCRIPT:gsub('MAIN_CALL', variant.call)
  local compiled = Compiler.compile{profile = 'slet', name = variant.name .. '.slet', source = source}
  local options = {profile = 'slet', entry = 'main', exports = {'main'}, mode = 'lazy'}
  local optimized = Compiler.stage(compiled.functions, options)
  local rawOptions = {profile = 'slet', entry = 'main', exports = {'main'}, mode = 'lazy', optimize = false}
  local unoptimized = Compiler.stage(compiled.functions, rawOptions)
  local optimizedPath = outdir .. '/' .. variant.name .. '.opt.abc'
  local rawPath = outdir .. '/' .. variant.name .. '.raw.abc'
  spit(optimizedPath, optimized.module)
  spit(rawPath, unoptimized.module)

  print(('\n-- %s: main = %s   (value %s) --'):format(variant.name, variant.call, tostring(tonumber(optimized.cells[1]))))
  local optimizedListing = capture(('%s dis %q'):format(abc, optimizedPath))
  local rawListing = capture(('%s dis %q'):format(abc, rawPath))
  spit(outdir .. '/' .. variant.name .. '.opt.dis', optimizedListing)
  spit(outdir .. '/' .. variant.name .. '.raw.dis', rawListing)
  describe('abc-opt', optimizedListing)
  if variant.name == 'monomorphic' then describe('pre-optimizer', rawListing) end

  local function tally(pattern) return select(2, optimizedListing:gsub(pattern, '')) end
  print(('    PUSH8 9=%d  PUSH8 10=%d  CGET=%d  ADD=%d  TCALL=%d  CALL=%d'):format(
    tally('PUSH8_A%s+9'), tally('PUSH8_A%s+10'), tally('CGET'), tally('ADD'),
    tally('TCALL_'), tally('%sCALL_A')))

  local modes = {}
  for _, mode in ipairs({'off', 'threaded', 'eager', 'lazy'}) do
    local out, ok = capture(('%s run %q main --jit=%s'):format(abc, optimizedPath, mode))
    modes[#modes + 1] = ('%s=%s'):format(mode, ok and (out:gsub('%s+$', '')) or 'FAILED')
  end
  print('    execution: ' .. table.concat(modes, ' '))

end

print('\n== C. design rule for the monomorphic source ==')
print('residual entry = all-location key, so every callee body reads marker from its C frame:')
print('  even  = unchanged instruction count (PUSH8_A 9 -> CGET1_A)')
print('  odd   = CGET1_A; ADDI_A 1; ZX32_A instead of PUSH8_A 10: 9 -> 11 instructions')
print('  module = 21 -> 23 instructions; the two frontend/tests/compiler.lua:803')
print('  assertions (PUSH8_A 9 and PUSH8_A 10) no longer hold; shape and TCALL still hold.')
print('inlining the tail-only SCC instead would restore the constants as virtual-entry')
print('constants but changes 3 functions/TCALL into 1 function and duplicates the cycle')
print('per call site; after the per-family budget the all-location slot widens marker too,')
print('because no cross-function cycle body exists (Q14).')
