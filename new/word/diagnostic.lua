-- Missing mechanisms are executable progress markers, never successful stubs.
local M = {}
local features = {
    ["host-captures"] = "Define freezing/registration for host tables, functions, and foreign environments.",
    ["keyed-words"] = "Complete outer-owner bindings for nested immutable snapshots and unbound nested member interfaces.",
    ["staged-definitions"] = "Transport immutable runtime captures alongside outlined lexical receiver parameters.",
}
local mt = { __tostring = function(d)
    local text = string.format("%s [%s] %s", d.kind:upper(), d.id, d.message)
    if d.detail then text = text .. "\n  " .. d.detail end
    if d.source then text = text .. "\n  at " .. d.source end
    if d.origin and d.origin ~= d.source then text = text .. "\n  trap: " .. d.origin end
    if d.next then text = text .. "\n  next: " .. d.next end
    return text
end }

-- Internal unwind tokens are not diagnostics and must survive scope annotation unchanged.
local controls = setmetatable({}, {__mode = "k"})
function M.control()
    local token = {}; controls[token] = true; return token
end

function M.is(value) return type(value) == "table" and getmetatable(value) == mt end
function M.new(kind, id, message, detail)
    return setmetatable({ kind = kind, id = id, message = message, detail = detail }, mt)
end
function M.reject(id, message) error(M.new("reject", id, message), 0) end
function M.bug(id, message) error(M.new("bug", id, message), 0) end
function M.resource(id, message) error(M.new("resource", id, message), 0) end

function M.todo(id, detail)
    local next_step = features[id]
    if not next_step then M.bug("unknown-todo", "Register the feature ID before using todo(): " .. tostring(id)) end
    local at = debug.getinfo(2, "Sl")
    local d = M.new("todo", id, "Implementation required", detail)
    d.next = next_step
    d.source = at.short_src .. ":" .. at.currentline
    d.origin = d.source
    error(d, 0)
end

function M.annotate(err, source)
    if type(err) == "table" and controls[err] then return err end
    if not M.is(err) then err = M.new("lua", "terminal-error", tostring(err)) end
    if source then err.source = source end
    return err
end

function M.todos()
    local out = {}
    for id, next_step in pairs(features) do out[#out + 1] = { id = id, next = next_step } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

return M
