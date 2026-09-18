-- The context record: the only mutable state of a transition (DESIGN §8).
--
-- A **node** is a containment level. It owns `out` -- the draft IR it is building -- and reaches
-- its ambient tables *through* `parent`. A **region** is a control position inside one transition:
-- it shares the node's `out`, and it creates its own `state` on entry (DESIGN §7.3).
--
-- Contexts are constructed, never cloned. There is no `clone` and no allowlist of shared fields,
-- because the split is structural: `parent` and `out` are the two things a child may share, and
-- everything else is a fresh `state` table it made itself. A forgotten field is therefore a nil
-- error rather than a fact silently shared by every region.
--
-- The exit vocabulary is a convention, not a method: every machine method has the shape
--
--     machine:run(in, k_ok, k_diag)
--
-- and calls `k_ok(C, value)` or `k_diag(C, diagnostic)` by tail call. A node never decides whether
-- its own diagnostic is fatal -- that is the parent's wiring, so the policy is decided once per
-- parent instead of at every site.
local Context = {}
Context.__index = Context

local function make(parent, ambient)
    return setmetatable({ parent = parent, ambient = ambient or {}, out = {}, state = {} }, Context)
end

-- The root: it holds the ambient every transition below it can reach.
-- The root: it holds the ambient every transition below it can reach.
--
-- `modules` is §6's "loaded units by name": a unit is loaded ONCE, so two `import`s of one file share
-- one `Syntax.Program` -- which matters because that file's resolution must be one resolution, and
-- two of them could disagree. It is compiler-scoped rather than unit-scoped for exactly that reason.
function Context.compiler(vocabulary, options)
    return make(nil, { vocabulary = vocabulary, options = options or {}, reports = {}, modules = {} })
end

-- A nested node. It gets its own `out`, because containment is lifetime: this is the draft *this*
-- transition owns, and a child must not write into its parent's.
function Context:child(ambient)
    return make(self, ambient)
end

-- A region. Same `out`, own `state`, and `parent` is the node it belongs to, so ambient reads walk
-- the containment chain exactly as they do for a node.
function Context:region(state)
    return setmetatable({ parent = self, ambient = {}, out = self.out, state = state or {} }, Context)
end

-- Ambient is read in one direction: up. This is the whole of "reached through the parent".
function Context:find(name)
    local at = self
    while at do
        local value = at.ambient[name]
        if value ~= nil then return value end
        at = at.parent
    end
end

function Context:get(name)
    local value = self:find(name)
    if value == nil then error('no ambient ' .. name, 2) end
    return value
end

return Context
