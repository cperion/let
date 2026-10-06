-- Lexical facts that are purely syntactic, computed once from the ASDL AST: the names a lambda
-- body captures. Tailness is intentionally not a source-level prepass; continuation-directed IR
-- lowering decides locally whether each transfer keeps or replaces the current continuation.
--
-- Semantic name and type resolution belongs to the real compiler's explicit passes. This module never
-- evaluates source values and does not decide whether a name denotes a word, value, schema or field.
local Walk = require("let.walk")

local M = {}

-- A set copy, so a nested scope can add bindings without leaking them to its siblings.
local function copy(bound)
    local out = {}
    for key in pairs(bound) do out[key] = true end
    return out
end

-- Free names of a lambda body: referenced but not bound by its parameters or its own `let`s.
-- Structure comes from let.walk, so every expression position -- a record field, an array
-- element, an index -- is covered by construction. Only the scoping cases are written out,
-- because which names bind where is the part structure cannot express.
local function freeNames(node, bound, out)
    if node == nil then return end
    local kind = node.kind
    if kind == "Reference" then
        local name = node.name.text
        if not bound[name] then out[name] = true end
        return
    elseif kind == "Lambda" then
        -- A nested lambda is a separate function, but the names it needs travel through this one:
        -- an environment cannot hold a name its enclosing environment does not have. Its parameter
        -- annotations are read here; its parameters bind in its body.
        for _, param in ipairs(node.params) do
            if param.annotation then freeNames(param.annotation, bound, out) end
        end
        local inner = copy(bound)
        for _, param in ipairs(node.params) do inner[param.name.text] = true end
        return freeNames(node.body, inner, out)
    elseif kind == "SchemaExpr" then
        -- A method body belongs to the schema it is written in, not to the enclosing lambda.
        return
    elseif kind == "Block" then
        local inner = copy(bound)
        for _, stmt in ipairs(node.statements) do freeNames(stmt, inner, out) end
        return
    elseif kind == "ValueStmt" then
        -- Annotations and values see the bindings declared so far; the binders join afterwards.
        for _, binder in ipairs(node.def.binders) do
            if binder.annotation then freeNames(binder.annotation, bound, out) end
        end
        for _, value in ipairs(node.def.values) do freeNames(value, bound, out) end
        for _, binder in ipairs(node.def.binders) do bound[binder.name.text] = true end
        return
    elseif kind == "WordStmt" then
        -- A local named word is called inside its own activation, so it sees that scope directly
        -- and needs no capture; only its name binds, from here on.
        bound[node.def.name.text] = true
        return
    elseif kind == "IfStmt" then
        freeNames(node.test, bound, out)
        -- Each arm is its own scope, so a declaration in one does not bind the other.
        for _, arm in ipairs({ node.yes, node.no }) do
            local inner = copy(bound)
            for _, stmt in ipairs(arm) do freeNames(stmt, inner, out) end
        end
        return
    end
    -- Every other form is walked structurally, so a new expression position is covered without a
    -- table here to keep in step with the schema.
    for _, child in ipairs(Walk.children(node)) do
        if child.list then
            for _, item in ipairs(child.value) do freeNames(item, bound, out) end
        else
            freeNames(child.value, bound, out)
        end
    end
end


-- `label` names anonymous words (lambdas); named definitions use their own name.
-- The names a lambda body refers to but does not bind, in a stable order.
function M.captures(node)
    local bound, out = {}, {}
    for _, param in ipairs(node.params) do bound[param.name.text] = true end
    freeNames(node.body, bound, out)
    local order = {}
    for name in pairs(out) do order[#order + 1] = name end
    table.sort(order)
    return order
end


return M
