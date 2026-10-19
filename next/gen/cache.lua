-- Cache topology from docs/spec.md, "The operand bank" and Decisions 1 and 9.
-- This module describes placement, not the VM's architectural stack semantics.
local M = {}

M.operand_registers = 4
M.interpreter_c_registers = 3
M.jit_c_registers = 4

local function check_depth(n, max)
  assert(type(n) == 'number' and n == math.floor(n) and n >= 0 and n <= max, 'invalid cache depth')
end

function M.state(a, b, c, c_registers)
  c_registers = c_registers or M.interpreter_c_registers
  assert(c_registers == M.interpreter_c_registers or c_registers == M.jit_c_registers, 'invalid C bank size')
  check_depth(a, M.operand_registers)
  check_depth(b, M.operand_registers - a)
  check_depth(c, c_registers)
  return { a = a, b = b, c = c, c_registers = c_registers }
end

local function copy(s) return M.state(s.a, s.b, s.c, s.c_registers) end

-- Depth zero is the top; nil means the cell is in stack memory.
function M.register(s, stack, depth)
  assert(type(depth) == 'number' and depth == math.floor(depth) and depth >= 0)
  if stack == 'A' then
    if depth < s.a then return 'h' .. (s.a - depth - 1) end
  elseif stack == 'B' then
    if depth < s.b then return 'h' .. (M.operand_registers - s.b + depth) end
  elseif stack == 'C' then
    if depth < s.c then return 'c' .. (s.c - depth - 1) end
  else error('invalid stack') end
end

-- A spill removes the deepest cached cell, leaving the other cached cells
-- in their anchored positions. The emitter must store the spilled value and
-- perform the indicated shifts before applying the resulting state.
function M.push(s, stack)
  local t = copy(s)
  local spill
  if stack == 'C' then
    if t.c == t.c_registers then spill = 'C'; t.c = t.c - 1 end
    t.c = t.c + 1
  elseif stack == 'A' or stack == 'B' then
    if t.a + t.b == M.operand_registers then
      spill = t[stack:lower()] > 0 and stack or (stack == 'A' and 'B' or 'A')
      t[spill:lower()] = t[spill:lower()] - 1
    end
    t[stack:lower()] = t[stack:lower()] + 1
  else error('invalid stack') end
  return t, spill
end
-- Transfer a top cell. The caller must capture the source value before
-- applying any spill shifts, then pop (if consuming), spill, and write the
-- destination register. A nil source/destination is a memory-stack access.
function M.transfer(s, from, to, consume)
  assert((from == 'A' or from == 'B' or from == 'C') and
         (to == 'A' or to == 'B' or to == 'C') and from ~= to, 'invalid transfer')
  local source = M.register(s, from, 0)
  local after_pop = consume and M.pop(s, from) or copy(s)
  local result, spill = M.push(after_pop, to)
  local destination = M.register(result, to, 0)
  return result, { source = source, destination = destination, spill = spill }
end

-- Ordered physical actions for spilling the deepest cached cell. Perform
-- these after capturing any instruction inputs and before writing the push.
function M.spill_steps(s, stack)
  local count = s[assert(({ A = 'a', B = 'b', C = 'c' })[stack], 'invalid stack')]
  assert(count > 0, 'cannot spill an empty cache')
  local steps = {}
  local bank = stack == 'C' and 'c' or 'h'
  local anchor = stack == 'B' and M.operand_registers - 1 or 0
  steps[1] = { kind = 'store', stack = stack, source = bank .. anchor }
  if stack == 'B' then
    for i = anchor, anchor - count + 2, -1 do
      steps[#steps + 1] = { kind = 'move', destination = bank .. i, source = bank .. (i - 1) }
    end
  else
    for i = anchor, anchor + count - 2 do
      steps[#steps + 1] = { kind = 'move', destination = bank .. i, source = bank .. (i + 1) }
    end
  end
  return steps
end

-- A same-stack DUP is a push with the old top captured first.
function M.duplicate(s, stack)
  local source = M.register(s, stack, 0)
  local result, spill = M.push(s, stack)
  return result, { source = source, destination = M.register(result, stack, 0), spill = spill }
end

-- A pop never refills from memory.
function M.pop(s, stack)
  local t = copy(s)
  local key = ({ A = 'a', B = 'b', C = 'c' })[stack]
  assert(key, 'invalid stack')
  if t[key] > 0 then t[key] = t[key] - 1 end
  return t
end

function M.states(c_registers)
  c_registers = c_registers or M.interpreter_c_registers
  local states = {}
  for a = 0, M.operand_registers do
    for b = 0, M.operand_registers - a do
      for c = 0, c_registers do
        states[#states + 1] = M.state(a, b, c, c_registers)
      end
    end
  end
  return states
end

return M

