-- Lexical member occurrences carried by selections, never mutable parent links
-- on shared definitions. A retained aggregate root is an actual owner binding;
-- a detached value does not acquire one from the dynamic caller.
local Model = require("word.model")
local Host = require("word.host")
local table = Host.table
local M = {}

function M.path_key(path)
    local parts = {}
    for _, name in ipairs(path or {}) do parts[#parts + 1] = #name .. ":" .. name end
    return table.concat(parts, "/")
end

function M.extend_path(path, name)
    local result = {table.unpack(path or {})}
    result[#result + 1] = name
    return result
end

-- Keep the existing immediate-receiver ABI unless this scope (including its
-- children/siblings) can refer to a name supplied by an enclosing occurrence.
-- Conservatively including unused methods keeps recursive sibling calls sound.
function M.needs_outer(t, root_type, path)
    local candidates, owner = {}, root_type
    for _, name in ipairs(path) do
        local def = Model.record(owner)
        for key in pairs(def.fields) do candidates[key] = true end
        for key in pairs(def.methods) do candidates[key] = true end
        owner = def.fields[name]
    end
    local def = Model.record(t)
    for name in pairs(def.fields) do candidates[name] = nil end
    for name in pairs(def.methods) do candidates[name] = nil end
    if not next(candidates) then return false end
    local seen = {}
    local function scan(schema)
        if seen[schema] then return false end; seen[schema] = true
        local record = Model.record(schema)
        if not record then return false end
        for _, method in pairs(record.methods) do
            local terminal = Model.word(method).definition.terminal
            if terminal then
                for name in pairs(Host.environment_names(terminal)) do
                    if candidates[name] then return true end
                end
            end
        end
        for _, field in pairs(record.fields) do if scan(field) then return true end end
        return false
    end
    return scan(t)
end

-- Propagate names along declared field edges only. The type-demand stack is
-- not a lexical chain: an unrelated type demanded inside a factory has no owner.
function M.child_names(parents, fields)
    local names = {}
    for name in pairs(parents or {}) do names[name] = true end
    for name in pairs(fields) do names[name] = true end
    return names
end

return M
