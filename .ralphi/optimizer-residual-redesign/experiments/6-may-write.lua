-- Round-6 probe: is round 5's loop may-write predicate the right static join?
--
-- Round 5 answered Q11 with "the loop-invariant key = the incoming key with
-- every component the loop may write replaced by a location", and sketched the
-- may-write set as an *interval* [header .. largest backedge source] plus a
-- clause for CALL/TCALL argument gathering.  The design also derives the
-- self-tail inline rule from that loop rule, so the documented counter's
-- backedge is a tail call whose argument transport *rebuilds* the frame.
--
-- This probe computes, on real assembled modules (the existing assembler and
-- disassembler), per-pc A/B/C heights by abstract interpretation of the
-- decoded instruction stream, then compares two candidate body sets:
--
--   INTERVAL  pcs in [header .. last backedge pc]          (round 5)
--   CYCLE     pcs on a path header -> a backedge source,
--             excluding the backedge instruction itself     (candidate)
--
-- and, for each, which of the header's C slots are may-write, i.e. which
-- components a loop-invariant header key would have to widen.
--
-- This is an experiment, not project tooling.

package.path = 'tools/?.lua;frontend/?.lua;' .. package.path
local assembler = require('assembler')
local manifest = require('opcodes')

local outdir = '.ralphi/optimizer-residual-redesign/experiments/6-may-write-out'
assert(os.execute('mkdir -p ' .. outdir) == 0)

local function write(path, bytes)
  local f = assert(io.open(path, 'wb')); f:write(bytes); f:close()
end
local function textOf(path)
  local f = assert(io.open(path, 'rb')); local t = f:read('*a'); f:close(); return t
end
-- Function code section of a single-code-section module.
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

-- ---------------------------------------------------------------- decoding --
-- Instruction stream of one function's code with pc, descriptor and the
-- resolved absolute target read from the disassembly listing, so the probe
-- never re-implements displacement encoding.
local function listing(path)
  local p = assert(io.popen(string.format('%q dis %q 2>&1', 'build/abc', path)))
  local text = p:read('*a'); local ok = p:close(); return ok and text or nil, text
end

-- Parse `build/abc dis` output.  One line per instruction:
--   <offset> <NAME> [operands]   and target labels like "body:" between.
local function functionsOf(listingText)
  local functions, current = {}, nil
  for line in listingText:gmatch('[^\n]+') do
    local head, args, results = line:match('^function (%d+):%s*(%d+) arguments, (%d+) results')
    if head then
      current = { index = tonumber(head), arguments = tonumber(args), results = tonumber(results),
        instructions = {}, labels = {}, points = {} }
      functions[#functions + 1] = current
    elseif current then
      local offset = line:match('^%s*([0-9a-f]+)%s+([A-Z][A-Z0-9_]*)(.*)$')
      if offset then
        local pc = tonumber(offset, 16)
        current.instructions[#current.instructions + 1] = {
          pc = pc, name = line:match('^%s*[0-9a-f]+%s+([A-Z][A-Z0-9_]*)'),
          text = line,
        }
        current.points[#current.points + 1] = pc
      elseif line:match('^([A-Za-z_][A-Za-z_0-9]*):') then
        -- a label line precedes the instruction at the next printed offset
      end
    end
  end
  return functions
end

-- Height effect per instruction name (the fixtures use this subset; an
-- unknown name aborts the probe rather than silently assuming zero).
-- Returns deltaA, deltaB, deltaC, and kind: 'linear' | 'branch|<target>' |
-- 'jump|<target>' | 'call' | 'tail' | 'ret'.
local function effect(instruction, site)
  local t = instruction.text
  local name = instruction.name
  local function labelTarget()
    local hex = t:match('0x([0-9a-fA-F]+)')
    if hex then return tonumber(hex, 16) end
    return nil
  end
  local n = t:match('^%s*[0-9a-f]+%s+[A-Z][A-Z0-9_]*%s+(%S+)')
  if name == 'PUSH8_A' or name == 'PUSH32_A' or name == 'PUSH64_A' then return 1, 0, 0, 'linear' end
  if name == 'PUSH8_B' or name == 'PUSH32_B' or name == 'PUSH64_B' then return 0, 1, 0, 'linear' end
  if name == 'CPUSH_A' then return -1, 0, 1, 'linear' end
  if name == 'CPUSH_B' then return 0, -1, 1, 'linear' end
  if name == 'CPOP' then return 0, 0, -1, 'linear' end
  if name == 'DROP_A' then return -1, 0, 0, 'linear' end
  if name == 'DROP_B' then return 0, -1, 0, 'linear' end
  if name:match('^CGET%d?N?_A$') then return 1, 0, 0, 'linear' end
  if name:match('^CGET%d?N?_B$') then return 0, 1, 0, 'linear' end
  if name:match('^CSET%d?N?_A$') then return -1, 0, 0, 'linear' end
  if name:match('^CSET%d?N?_B$') then return 0, -1, 0, 'linear' end
  if name == 'JMP' then return 0, 0, 0, 'jump|' .. tostring(labelTarget()) end
  if name:match('^BLTUI_A$') or name:match('^BLEUI_A$') or name:match('^BEQI_A$') or
     name:match('^BNEI_A$') or name:match('^BLTI_A$') or name:match('^BGEI_A$') or
     name:match('^BGTI_A$') or name:match('^BLEI_A$') or name:match('^BGTUI_A$') or
     name:match('^BGEUI_A$') then
    return -1, 0, 0, 'branch|' .. tostring(labelTarget())
  end
  if name == 'BLTU_A' or name == 'BLEU_A' or name == 'BEQ_A' or name == 'BNE_A' or
     name == 'BLT_A' or name == 'BLE_A' or name == 'BGT_A' or name == 'BGE_A' or
     name == 'BGTU_A' or name == 'BGEU_A' then
    return -1, -1, 0, 'branch|' .. tostring(labelTarget())
  end
  if name:match('^ADD_A$') or name:match('^SUB_A$') or name:match('^MUL_A$') then return 0, -1, 0, 'linear' end
  if name:match('^ADD_B$') or name:match('^SUB_B$') or name:match('^MUL_B$') then return -1, 0, 0, 'linear' end
  if name:match('^ADDI_A$') or name:match('^SUBI_A$') or name:match('^ANDI_A$') or name:match('^ORI_A$') then return 0, 0, 0, 'linear' end
  if name == 'ZX32_A' or name == 'ZX8_A' or name == 'ZX16_A' or name == 'SX32_A' or name == 'NEG_A' or name == 'NOT_A' then return 0, 0, 0, 'linear' end
  if name:match('^CALL_A$') then
    -- "CALL_A <target> <arguments>": the listing omits the result count, which
    -- is the callee's signature; site.results is filled in from the function
    -- table by the caller of effect().
    local args = tonumber(t:match('CALL_A%s+%S+%s+(%d+)')) or 0
    local results = site and site.resultsFor and site.resultsFor[tonumber(t:match('CALL_A%s+0x(%x+)'), 16)] or 0
    return -args + (results or 0), 0, 0, 'call'
  end
  if name:match('^TCALL_A$') then
    -- "TCALL_A <target> <arguments> <frame cells>": the current frame (of
    -- `cells`) is replaced by the argument vector (of `arguments`), taken from
    -- the selected stack, so the callee entry state is (0,0,arguments).
    local args, cells = t:match('TCALL_A%s+%S+%s+(%d+)%s+(%d+)')
    args, cells = tonumber(args) or 0, tonumber(cells) or 0
    return -args, 0, args - cells, 'tail|' .. tostring(labelTarget() or '')
  end
  if name:match('^RET_A$') then return 0, 0, 0, 'ret' end
  error('probe has no effect model for ' .. tostring(name) .. ' at pc ' .. instruction.pc .. ': ' .. t)
end

-- ------------------------------------------------------- height analysis ----
-- Abstract interpretation of A/B/C heights over the function CFG.  Joins must
-- agree (the verifier checks the same shapes); disagreement aborts the probe.
-- Function-local CFG.  A tail call is a control transfer: when its target is
-- this same function (self-tail recursion) it is a backedge; a tail call to
-- another function ends this function's path.  An ordinary call falls through
-- to the return pc (the callee's frame is above the caller's).
local function successors(instruction, effectKind, next, inFunction)
  local kind, target = effectKind:match('^([a-z]+)|?(.*)$')
  target = target ~= '' and tonumber(target) or nil
  if kind == 'branch' then return { next, target } end
  if kind == 'jump' then return { target } end
  if kind == 'call' then return { next } end
  if kind == 'tail' then
    if target and (not inFunction or inFunction[target]) then return { target } end
    return {}
  end
  if kind == 'ret' then return {} end
  return { next }
end

local function heights(fn, site)
  local byPc = {}
  for _, instruction in ipairs(fn.instructions) do byPc[instruction.pc] = instruction end
  local order = fn.points
  local height = {}
  local stable = false
  height[order[1]] = { a = 0, b = 0, c = fn.arguments or 0 }
  local function merge(pc, h)
    local previous = height[pc]
    if previous then
      assert(previous.a == h.a and previous.b == h.b and previous.c == h.c,
        ('height disagreement at pc %d: (%d,%d,%d) vs (%d,%d,%d)'):format(pc, previous.a, previous.b, previous.c, h.a, h.b, h.c))
      return false
    end
    height[pc] = h; return true
  end
  local inFunction = {}
  for _, instruction in ipairs(fn.instructions) do inFunction[instruction.pc] = true end
  local pending = { order[1] }
  while #pending > 0 do
    local pc = table.remove(pending)
    local instruction = assert(byPc[pc], 'branch target outside the function: ' .. tostring(pc))
    local da, db, dc, kind = effect(instruction, site)
    local h = height[pc]
    local after = { a = h.a + da, b = h.b + db, c = h.c + dc }
    assert(after.a >= 0 and after.b >= 0 and after.c >= 0, 'negative height at pc ' .. pc)
    local next = instruction.pc + 1 -- unused: successors come from listing targets
    -- next pc is the next instruction in pc order
    local following = nil
    for index, other in ipairs(order) do if other == pc then following = order[index + 1] end end
    for _, target in ipairs(successors(instruction, kind, following, inFunction)) do
      if target and merge(target, after) then pending[#pending + 1] = target end
    end
  end
  return height
end

-- ------------------------------------------------------------ loop facts ----
local function cfg(fn, height, site)
  local byPc = {}
  for _, instruction in ipairs(fn.instructions) do byPc[instruction.pc] = instruction end
  local inFunction = {}
  for _, instruction in ipairs(fn.instructions) do inFunction[instruction.pc] = true end
  local order = fn.points
  local followingOf = {}
  for index, pc in ipairs(order) do followingOf[pc] = order[index + 1] end
  local succ, pred = {}, {}
  for _, pc in ipairs(order) do
    succ[pc] = {}; pred[pc] = pred[pc] or {}
  end
  for _, pc in ipairs(order) do
    local _, _, _, kind = effect(byPc[pc], site)
    for _, target in ipairs(successors(byPc[pc], kind, followingOf[pc], inFunction)) do
      if target then
        succ[pc][#succ[pc] + 1] = target
        pred[target] = pred[target] or {}
        pred[target][#pred[target] + 1] = pc
      end
    end
  end
  return byPc, succ, pred, followingOf
end

-- Backedges: edge s -> h with s >= h (and h a leader).
local function backedges(fn)
  local _, succ = cfg(fn, nil, nil)
  local result = {}
  for _, pc in ipairs(fn.points) do
    for _, target in ipairs(succ[pc] or {}) do
      if target <= pc then result[#result + 1] = { source = pc, header = target } end
    end
  end
  return result
end

local function reachableFrom(start, succ, stopAt)
  local seen, pending = {}, { start }
  if stopAt then seen[stopAt] = true end
  while #pending > 0 do
    local pc = table.remove(pending)
    for _, target in ipairs(succ[pc] or {}) do
      if not seen[target] then
        seen[target] = true; pending[#pending + 1] = target
      end
    end
  end
  return seen
end

-- CYCLE body: pcs that can reach a backedge source without passing the header
-- (backward walk from each backedge source, not expanding through the header).
local function cycleBody(header, sources, pred)
  local seen = {}
  local pending = {}
  for _, source in ipairs(sources) do seen[source] = true; pending[#pending + 1] = source end
  while #pending > 0 do
    local pc = table.remove(pending)
    for _, previous in ipairs(pred[pc] or {}) do
      if previous ~= header and not seen[previous] then
        seen[previous] = true; pending[#pending + 1] = previous
      end
    end
  end
  -- keep only pcs reachable from the header, and drop the backedge sources
  -- themselves from the write scan only if they are the backedge instruction
  seen[header] = true
  return seen
end

local function intervalBody(header, lastSource, order)
  local seen = {}
  for _, pc in ipairs(order) do
    if pc >= header and pc <= lastSource then seen[pc] = true end
  end
  return seen
end

-- may-write C slots of a header under one body set.  A C slot i (0-based from
-- the frame base) is may-write iff the body's minimum C height is <= i (a pop
-- reached it, so a later push reuses it) or the body holds a CSET whose target
-- slot is i.  Round 5 additionally widened every slot for a CALL/TCALL in the
-- interval; that clause is reported separately.
local function mayWriteC(body, byPc, height, header, opts)
  local minC = math.huge
  local written = {}
  local callInBody = false
  for pc in pairs(body) do
    local instruction = byPc[pc]
    local h = height[pc]
    if h.c < minC then minC = h.c end
    local _, _, _, kind = effect(instruction, opts)
    if kind:match('^%a+') == 'call' or kind:match('^%a+') == 'tail' then callInBody = true end
    -- CSET target slot: depth from the top, so absolute index = height-1-depth
    local depth = instruction.name:match('^CSET%d?N?_A$') and
      (instruction.name == 'CSET0_A' and 0 or instruction.name == 'CSET1_A' and 1 or tonumber(instruction.text:match('%s(%d+)%s*$')))
    if depth then written[h.c - 1 - depth] = true end
    -- an inlined tail/call argument push does not write below the caller top;
    -- handled by the transport rule, not here.
  end
  return minC, written, callInBody
end

-- ------------------------------------------------------------------ cases ---

-- The documented counter fixture (frontend/tests/optimize.lua:229-290).
local counter = ([[
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
]])

-- A loop whose exit path pops the frame before returning (a break that discards
-- a temporary) but which never cycles through the pop: the interval includes it.
local exitPop = [[
.function main 0 1
  PUSH.A 0
  CPUSH.A
  PUSH.A 40
  CPUSH.A
  PUSH.A 3
  CPUSH.A
head:
  CGET.A 0
  CGET.B 1
  BLTU.A body
  CGET.A 0
  CPOP
  CPOP
  CPOP
  RET.A 0 1
body:
  CGET.A 0
  CGET.B 2
  ADD.A
  CSET.A 2
  JMP head
.export main
]]

local cases = {
  { name = 'counter', source = counter },
  { name = 'exit-pop', source = exitPop },
}

for _, case in ipairs(cases) do
  local input = (assembler.assemble(case.source))
  local path = outdir .. '/' .. case.name .. '.abc'
  write(path, input)
  local okList, listingText = listing(path)
  assert(okList, listingText)
  write(outdir .. '/' .. case.name .. '.dis', listingText)
  local functions = functionsOf(listingText)
  print(('== %s ==  functions: %d'):format(case.name, #functions))
  for _, fn in ipairs(functions) do
    if #fn.instructions > 0 then
      local resultsFor = {}
      for _, other in ipairs(functions) do resultsFor[other.points[1]] = other.results end
      local site = { resultsFor = resultsFor }
      local height = heights(fn, site)
      local byPc, succ, pred = cfg(fn, height, site)
      local back = backedges(fn)
      if #back > 0 then
        local headers = {}
        for _, edge in ipairs(back) do
          headers[edge.header] = headers[edge.header] or { sources = {} }
          table.insert(headers[edge.header].sources, edge.source)
        end
        for header, info in pairs(headers) do
          table.sort(info.sources)
          local sourceSet = {}
          for _, s in ipairs(info.sources) do sourceSet[s] = true end
          local lastSource = info.sources[#info.sources]
          local interval = intervalBody(header, lastSource, fn.points)
          local cycle = cycleBody(header, info.sources, pred)
          local hc = height[header].c
          local function scanOf(body, dropSources)
            local scan = {}
            for pc in pairs(body) do
              local drop = dropSources and (pc == header or sourceSet[pc])
              if not drop then scan[pc] = true end
            end
            return scan
          end
          local function setOf(t)
            local r = {}
            for i in pairs(t) do r[#r + 1] = i end
            table.sort(r)
            return '{' .. table.concat(r, ',') .. '}'
          end
          local function bodyFacts(scan)
            local minC, written = mayWriteC(scan, byPc, height, header, site)
            local widened = {}
            for i = 0, hc - 1 do if minC <= i or written[i] then widened[i] = true end end
            -- round 5's extra clause: a CALL/TCALL in the scanned set gathers
            -- arguments at or below h's index, widening every slot from the
            -- call's C base upward.
            local base = math.huge
            for pc in pairs(scan) do
              local _, _, _, kind = effect(byPc[pc], site)
              if kind:match('^tail') then
                local cells = tonumber(byPc[pc].text:match('TCALL_A%s+%S+%s+%d+%s+(%d+)'))
                if cells then base = math.min(base, height[pc].c - cells) end
              end
            end
            local round5 = {}
            for i in pairs(widened) do round5[i] = true end
            if base ~= math.huge then for i = base, hc - 1 do round5[i] = true end end
            return widened, round5, minC, written, base
          end
          local iw, i5, iminC, iwritten, ibase = bodyFacts(scanOf(interval, false))
          local cw, c5, cminC, cwritten, cbase = bodyFacts(scanOf(cycle, true))
          local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
          print(('-- function %d, header pc %d, C height %d, backedge sources %s'):format(
            fn.index, header, hc, table.concat(info.sources, ',')))
          print(('   body writes (CSET slots): %s   min C height: interval %d / cycle %d'):format(
            setOf(iwritten), iminC, cminC))
          print(('   round-5 rule   (interval + CALL/TCALL clause, body pcs %d): may-write C slots %s  (%d of %d)'):format(
            count(scanOf(interval, false)), setOf(i5), count(i5), hc))
          print(('   corrected rule (cycle body, backedge is the join, body pcs %d): may-write C slots %s  (%d of %d)'):format(
            count(scanOf(cycle, true)), setOf(c5), count(c5), hc))
          print(('   constants kept: round-5 %d, corrected %d   (documented counter: 4 slots, 2 carried -> corrected keeps 2)'):format(
            hc - count(i5), hc - count(c5)))
        end
      end
    end
  end
  print()
end

print('wrote artifacts under ' .. outdir)
