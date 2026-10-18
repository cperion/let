-- Round-11 probe: what is the residual-function set, i.e. which functions must
-- get a residual entry version and survive module rewriting, and does the
-- incumbent derive that set before or after the walk?
--
-- Four hand-built modules through the existing assembler, verifier, abc-opt and
-- all four execution modes:
--   (1) export + acyclic helper   -> helper inlined, then deleted (no root, no
--                                    residual call)
--   (2) export + nontail recursion -> callee survives (residual call)
--   (3) no export at all           -> every function survives (the incumbent's
--                                    "no explicit roots" rule)
--   (4) code-address relocation    -> an otherwise-uncalled function survives
--                                    because a relocation roots its address
--
-- This is an experiment, not project tooling.
package.path = 'frontend/?.lua;frontend/?/init.lua;tools/?.lua;build/?.lua;' .. package.path

local Compiler = require('let.compiler')
local Assembler = require('assembler')
local abc = 'build/abc'
local outdir = '.ralphi/optimizer-residual-redesign/experiments/11-residual-root-set-out'
os.execute('mkdir -p ' .. outdir)

local function spit(path, data) local f = assert(io.open(path, 'wb')); f:write(data); f:close() end
local function capture(command)
  local pipe = assert(io.popen(command, 'r')); local out = pipe:read('*a'); local ok = pipe:close(); return out, ok
end
local function functions(path)
  local listing = capture(('%s dis %q'):format(abc, path))
  local _, n = listing:gsub('function %d+:', '')
  return n, listing
end
local function run_modes(path, entry)
  local parts = {}
  for _, mode in ipairs({'interpreted', 'compiled', 'lazy', 'jit=threaded'}) do
    local out, ok = capture(('%s run %q %s --%s 2>&1'):format(abc, path, entry, mode))
    parts[#parts + 1] = ('%s=%s'):format(mode, ok and (out:gsub('%s+$', '')) or 'FAILED')
  end
  return table.concat(parts, ' ')
end

local ACYCLIC = [[
.function helper 1 1
  CGET.A 0
  ADDI.A 1
  RET.A 1 1
.function entry 0 1
  PUSH.A 41
  CALL.A helper 1
  RET.A 0 1
.export entry
]]

local ACYCLIC_NO_EXPORT = ACYCLIC:gsub('%s*%.export entry%s*$', '\n')

local RECURSIVE = [[
.function rec 1 1
  CGET.A 0
  JZ.A base
  CGET.A 0
  SUBI.A 1
  CALL.A rec 1
  ADDI.A 3
  RET.A 1 1
base:
  PUSH.A 0
  RET.A 1 1
.function entry 0 1
  PUSH.A 5
  CALL.A rec 1
  RET.A 0 1
.export entry
]]

local RELOC_ROOT = [[
.profile callables
.datazero 8
.codeaddr 0 target
.signature op 1 1 a i
.function dead 0 1
  PUSH.A 99
  RET.A 0 1
.function target 1 1 a i
  PUSH.A 42
  RET.A 1 1
.function entry 0 1
  GADDR.A 0
  .loadkind addr
  GLD64.B 0
  CALLI.A 1 op
  RET.A 0 1
.export entry
]]

local fixtures = {
  {name = 'acyclic-export', text = ACYCLIC, entry = 'entry'},
  {name = 'acyclic-no-export', text = ACYCLIC_NO_EXPORT, entry = nil},
  {name = 'recursive-export', text = RECURSIVE, entry = 'entry'},
  {name = 'reloc-root', text = RELOC_ROOT, entry = 'entry'},
}

print('== residual-function set after abc-opt (function count in the emitted module) ==')
for _, fixture in ipairs(fixtures) do
  local raw = Assembler.assemble(fixture.text)
  local optimized = Compiler.optimize(raw)
  local rawPath = outdir .. '/' .. fixture.name .. '.raw.abc'
  local optPath = outdir .. '/' .. fixture.name .. '.opt.abc'
  spit(rawPath, raw); spit(optPath, optimized)
  local rawDis, rawListing = functions(rawPath)
  local optDis, optListing = functions(optPath)
  spit(outdir .. '/' .. fixture.name .. '.raw.dis', rawListing)
  spit(outdir .. '/' .. fixture.name .. '.opt.dis', optListing)
  local fixpoint = (Compiler.optimize(optimized) == optimized) and 'yes' or 'NO'
  local calls = 0
  for _ in optListing:gmatch('CALL_') do calls = calls + 1 end
  local tailcalls = 0
  for _ in optListing:gmatch('TCALL_') do tailcalls = tailcalls + 1 end
  local label = fixture.name
  if fixture.entry then
    print(('%-18s functions %d -> %d   CALL_=%d TCALL_=%d fixpoint=%s   %s')
      :format(label, rawDis, optDis, calls, tailcalls, fixpoint, run_modes(optPath, fixture.entry)))
  else
    print(('%-18s functions %d -> %d   CALL_=%d TCALL_=%d fixpoint=%s   (no export: not runnable by name)')
      :format(label, rawDis, optDis, calls, tailcalls, fixpoint))
  end
  print(('  raw shape: %s'):format(rawListing:gsub('%s+', ' ')))
  print(('  opt shape: %s'):format(optListing:gsub('%s+', ' ')))
end

print('\n== what the C sink emits for the same modules (function definitions) ==')
for _, fixture in ipairs(fixtures) do
  local optPath = outdir .. '/' .. fixture.name .. '.opt.abc'
  local cPath = outdir .. '/' .. fixture.name .. '.c'
  local message, ok = capture(('%s c %q -o %q 2>&1'):format(abc, optPath, cPath))
  local text = ''
  local f = io.open(cPath, 'r')
  if f then text = f:read('*a'); f:close() end
  local n = 0
  for line in text:gmatch('[^\n]+') do
    if line:match('^static inline [%w_]+ abc_aot_function_%d+%(') and not line:match(';%s*$') then n = n + 1 end
  end
  if text == '' then
    print(('%-18s no C output: %s'):format(fixture.name, (message:gsub('%s+$', ''))))
  else
    print(('%-18s C writer ok=%s  function bodies=%d'):format(fixture.name, tostring(ok), n))
  end
end
