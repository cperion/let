-- Round-12 probe: what does a sink do with a body it cannot record, and is the
-- refusal a property of the function (decidable before the walk) or of the walk?
--
-- The design currently says: a body the binding cannot record is *retained*: its
-- entry version's residue is the verbatim source, every direct call in it is a
-- residual call, and "if it arrives at a later version of the same owner, that
-- owner's unpublished versions are discarded".  That sentence assumes
--   (a) the refusal can be predicted or at least staged per owner,
--   (b) every sink can emit a verbatim source body.
-- This probe tests both with the existing assembler, abc-opt, the C writer and
-- the four execution modes:
--   * a retained function with float ops, plus an independently foldable 3+4
--     witness (if the owner were optimized the witness would fold);
--   * the same float ops with constant operands, which the DagSink folds, to
--     show recordability depends on the walk, not on the instruction set;
--   * a module where a retained owner and an optimizable sibling coexist, to
--     show the refusal is per owner and does not disturb other owners;
--   * the C writer on each: does it retain, omit, or reject?
-- Experiment, not project tooling.

package.path = 'frontend/?.lua;frontend/?/init.lua;tools/?.lua;build/?.lua;' .. package.path

local Assembler = require('assembler')
local Compiler = require('let.compiler')
local abc = 'build/abc'
local outdir = '.ralphi/optimizer-residual-redesign/experiments/12-refusal-owner-out'
os.execute('mkdir -p ' .. outdir)

local function spit(path, data) local f = assert(io.open(path, 'wb')); f:write(data); f:close() end
local function slurp(path) local f = io.open(path, 'rb'); if not f then return nil end local d = f:read('*a'); f:close(); return d end
local function capture(command)
  local pipe = assert(io.popen(command, 'r')); local out = pipe:read('*a'); local ok = pipe:close(); return out, ok
end
local function functions(path)
  local listing = capture(('%s dis %q'):format(abc, path))
  local _, n = listing:gsub('function %d+:', '')
  return n, listing
end
local function run_modes(path, entry, args)
  local parts = {}
  for _, mode in ipairs({'interpreted', 'compiled', 'lazy', 'jit=threaded'}) do
    local out, ok = capture(('%s run %q %s %s --%s 2>&1'):format(abc, path, entry, args or '', mode))
    parts[#parts + 1] = ('%s=%s'):format(mode, ok and (out:gsub('%s+$', '')) or ('FAILED:' .. out:gsub('%s+$', '')))
  end
  return table.concat(parts, ' ')
end
local function emit_c(path, out)
  local outtext = capture(('build/abc-opt --emit-c %q -o %q 2>&1; printf "\nEXIT=%%s" $?'):format(path, out))
  local status = outtext:match('EXIT=(%d+)%s*$') or '?'
  outtext = outtext:gsub('%s*EXIT=%d+%s*$', '')
  return outtext, status == '0', status
end

-- A non-foldable float op forces the ABC DagSink's BOUNDARY exit (it sets no
-- float handler).  The foldable 3+4 witness after it stays unfolded iff the
-- whole owner was retained.  Float arguments arrive as i64 bit patterns; the
-- CLI passes integer cells, the signature says ff -> i.
local RETAIN_FLOAT = [[
.profile memory
.function calc 2 1 ff i
  CGET.A 0
  CGET.B 1
  FADD.A
  F2IS.A
  PUSH.A 3
  PUSH.B 4
  ADD.A
  DROP.A
  ADDI.A 5
  RET.A 2 1
.export calc
]]

-- The same float instruction sequence, but every float operand is a folded
-- constant.  If this optimizes, recordability depends on the walk (folding),
-- not on a pre-walk scan for float instructions.
local FOLD_FLOAT = [[
.profile memory
.function calc 0 1 - i
  PUSH.A 1
  I2FS.A
  PUSH.B 2
  I2FS.B
  FADD.A
  F2IS.A
  ADDI.A 5
  RET.A 0 1
.export calc
]]

-- One retained owner (float) next to one optimizable sibling in the same module.
local MIXED = [[
.profile memory
.function calc 2 1 ff i
  CGET.A 0
  CGET.B 1
  FADD.A
  F2IS.A
  PUSH.A 3
  PUSH.B 4
  ADD.A
  DROP.A
  ADDI.A 5
  RET.A 2 1
.export calc
.function good 0 1 - i
  PUSH.A 3
  PUSH.B 4
  ADD.A
  RET.A 0 1
.export good
]]

-- Round-11's callable fixture: ABC retains the CALLI body, native executes it.
local CALLI = [[
.profile callables
.datazero 8
.codeaddr 0 target
.signature op 1 1 a i
.function target 1 1 a i
  PUSH.A 42
  RET.A 1 1
.function entry 0 1 - i
  GADDR.A 0
  .loadkind addr
  GLD64.B 0
  CALLI.A 1 op
  RET.A 0 1
.export entry
]]

local fixtures = {
  {name = 'retain-float', text = RETAIN_FLOAT, entry = 'calc',
   args = '4607182418800017408 4611686018427387904'},
  {name = 'fold-float', text = FOLD_FLOAT, entry = 'calc'},
  {name = 'mixed', text = MIXED, entry = 'good'},
  {name = 'calli', text = CALLI, entry = 'entry'},
}

print('== abc-opt: does the owner optimize or stay verbatim? ==')
for _, fx in ipairs(fixtures) do
  local raw = Assembler.assemble(fx.text)
  local optimized = Compiler.optimize(raw)
  local rawPath = outdir .. '/' .. fx.name .. '.raw.abc'
  local optPath = outdir .. '/' .. fx.name .. '.opt.abc'
  spit(rawPath, raw); spit(optPath, optimized)
  local rawN, rawListing = functions(rawPath)
  local optN, optListing = functions(optPath)
  spit(outdir .. '/' .. fx.name .. '.raw.dis', rawListing)
  spit(outdir .. '/' .. fx.name .. '.opt.dis', optListing)
  local idem = (Compiler.optimize(optimized) == optimized) and 'yes' or 'NO'
  local identical = (raw == optimized) and 'byte-identical' or 'changed'
  print(('%s: functions %d -> %d, whole module %s, opt fixpoint=%s')
    :format(fx.name, rawN, optN, identical, idem))
  print(('  raw: %s'):format((rawListing:gsub('%s+', ' '))))
  print(('  opt: %s'):format((optListing:gsub('%s+', ' '))))
  if fx.entry then
    if fx.name == 'mixed' then
      print(('  run mixed: good=%s calc=%s'):format(
        run_modes(optPath, 'good'),
        run_modes(optPath, 'calc', '4607182418800017408 4611686018427387904')))
    else
      print(('  run: %s'):format(run_modes(optPath, fx.entry, fx.args)))
    end
  end
end

print('\n== the C writer on the same modules: retain, omit, or reject? ==')
for _, fx in ipairs(fixtures) do
  local optPath = outdir .. '/' .. fx.name .. '.opt.abc'
  local cPath = outdir .. '/' .. fx.name .. '.c'
  os.remove(cPath)
  local message, ok, status = emit_c(optPath, cPath)
  local text = slurp(cPath) or ''
  local bodies = 0
  for line in text:gmatch('[^\n]+') do
    if line:match('^static inline [%w_]+ abc_aot_function_%d+%(') and not line:match(';%s*$') then bodies = bodies + 1 end
  end
  print(('%-14s exit=%s bodies=%d  %s'):format(fx.name, status, bodies,
    text == '' and ((message or ''):gsub('%s+$', '')) or 'C emitted'))
end

print('\n== native (compiled/lazy/threaded) on the retained owners ==')
-- native is exercised through the same `abc run`; compiled/lazy/threaded are the
-- residualizer modes, interpreted is the reference.
for _, fx in ipairs({fixtures[1], fixtures[4]}) do
  local optPath = outdir .. '/' .. fx.name .. '.opt.abc'
  print(('%-14s %s'):format(fx.name, run_modes(optPath, fx.entry, fx.args)))
end
