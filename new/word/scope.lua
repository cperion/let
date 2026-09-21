-- Stable module environments and protected, coroutine-local invocation frames.
local D = require("word.diagnostic")
local table = require("word.host").table
local M = {}
M.__index = M

function M.new()
    return setmetatable({ stacks = setmetatable({}, { __mode = "k" }),
        environments = setmetatable({}, { __mode = "k" }), main_thread = {} }, M)
end
function M:stack()
    local thread = coroutine.running() or self.main_thread
    local stack = self.stacks[thread]
    if not stack then stack = {}; self.stacks[thread] = stack end
    return stack
end
function M:current()
    local stack = self:stack()
    return stack[#stack]
end

function M:find(key, value)
    local stack = self:stack()
    for i = #stack, 1, -1 do if stack[i][key] == value then return stack[i] end end
end
function M:count(key)
    local n = 0
    for _, frame in ipairs(self:stack()) do if frame[key] then n = n + 1 end end
    return n
end

function M:with(frame, action)
    local stack = self:stack()
    local depth = #stack
    local function restore_frames()
        for i = #stack, depth + 1, -1 do stack[i] = nil end
    end
    -- Restore the original depth even when a nested call exits with an error.
    local results = table.pack(xpcall(function()
        stack[depth + 1] = frame
        local values = table.pack(action())
        restore_frames()
        return table.unpack(values, 1, values.n)
    end, function(err)
        restore_frames()
        return err
    end))
    restore_frames()
    if not results[1] then error(D.annotate(results[2], frame.source), 0) end
    return table.unpack(results, 2, results.n)
end

function M:environment(prelude)
    local entries = {}
    for key, value in pairs(prelude) do entries[key] = value end
    local env = setmetatable({}, {
        __index = function(_, key)
            local frame = self:current()
            if frame and frame.lookup_names and frame.terminal == debug.getinfo(2, "f").func then frame.lookup_names[key] = true end
            if frame and frame.has_member and frame.terminal == debug.getinfo(2, "f").func and frame.has_member(key) then
                return frame.read_member(key)
            end
            local value = entries[key]
            if value == nil then D.reject("unknown-name", "Unknown or unavailable module name: " .. tostring(key)) end
            return value
        end,
        __newindex = function(_, key, value)
            local frame = self:current()
            if frame and frame.has_member and frame.terminal == debug.getinfo(2, "f").func and frame.has_member(key) then
                return frame.write_member(key, value)
            end
            D.reject("module-write", "Use a Lua local; module environments are read-only: " .. tostring(key))
        end,
        __metatable = "word module environment",
    })
    self.environments[env] = true
    return env
end

function M:load(source, name, prelude, is_file)
    local env = self:environment(prelude)
    local chunk, err
    if is_file then chunk, err = loadfile(source, "t", env)
    else chunk, err = load(source, name, "t", env) end
    if not chunk then D.reject("lua-load", err) end
    local exports = self:with({ mode = "load", source = name }, chunk)
    if type(exports) ~= "table" or getmetatable(exports) ~= nil then
        D.reject("module-exports", "A DSL module must return a plain Lua export table")
    end
    return exports
end

return M
