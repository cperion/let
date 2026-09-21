-- LuaJIT host operations. Helpers are local; Lua globals are never patched.
local bit = require("bit")
local util = require("jit.util")
local M = {}
M.table = setmetatable({pack = function(...) return {n = select("#", ...), ...} end, unpack = unpack}, {__index = table})
M.math = setmetatable({}, {__index = math})
function M.math.tointeger(n)
    if type(n) == "number" and n > -math.huge and n < math.huge and n == math.floor(n) then return n == 0 and 0 or n end
end
function M.math.type(n)
    if type(n) ~= "number" then return nil end
    return M.math.tointeger(n) and "integer" or "float"
end
function M.mul32(a, b)
    local lo_a, lo_b = a % 65536, b % 65536
    local cross = (math.floor(a / 65536) * lo_b + lo_a * math.floor(b / 65536)) % 65536
    return (lo_a * lo_b + cross * 65536) % 4294967296
end
M.bit = bit

-- Discover global-access opcodes from this VM, not a hard-coded bytecode version.
-- Only environment dependencies are inspected; terminals still execute as Lua.
local read_global = util.funcbc(function() return __word_environment_probe end, 1) % 256
local write_global = util.funcbc(function(v) __word_environment_probe = v end, 1) % 256
function M.lua_terminal(fn) return util.funcinfo(fn).bytecodes ~= nil end

-- LuaJIT can change prototype flags after execution. Never use repeated dumps
-- as identities. Clones and their nested prototypes share a stable recipe entry.
local recipes, next_recipe = setmetatable({}, {__mode = "k"}), 0
local function prototype(fn) return type(fn) == "proto" and fn or util.funcinfo(fn).proto end
local function recipe(fn)
    local proto = prototype(fn)
    if not recipes[proto] then
        next_recipe = next_recipe + 1; recipes[proto] = {identity = next_recipe}
    end
    return recipes[proto]
end
function M.code_identity(fn) return recipe(fn).identity end
function M.code(fn)
    local entry = recipe(fn)
    if not entry.bytecode then entry.bytecode = string.dump(fn) end
    return entry.bytecode
end
function M.clone(fn)
    local copy = assert(loadstring(M.code(fn)))
    setfenv(copy, getfenv(fn))
    local function associate(original, duplicate)
        recipes[prototype(duplicate)] = recipe(original)
        for i = 1, util.funcinfo(original).gcconsts do
            local child = util.funck(original, -i)
            if type(child) == "proto" then associate(child, util.funck(duplicate, -i)) end
        end
    end
    associate(fn, copy)
    return copy
end
function M.uses_environment(fn)
    local info = util.funcinfo(fn)
    if not info.bytecodes then return true end -- C terminals require registration.
    for pc = 1, info.bytecodes - 1 do
        local op = util.funcbc(fn, pc) % 256
        if op == read_global or op == write_global then return true end
    end
    for i = 1, info.gcconsts do
        local child = util.funck(fn, -i)
        if type(child) == "proto" and M.uses_environment(child) then return true end
    end
    return false
end

-- Construction-site membership, not the dynamic caller stack, establishes lexical scope.
function M.nested_terminal(parent, child)
    if not M.lua_terminal(parent) or not M.lua_terminal(child) then return false end
    local wanted = util.funcinfo(child).proto
    local function visit(fn)
        local info = util.funcinfo(fn)
        for i = 1, info.gcconsts do
            local item = util.funck(fn, -i)
            if type(item) == "proto" then
                if item == wanted or visit(item) then return true end
            end
        end
        return false
    end
    return visit(parent)
end

function M.environment_names(fn, names)
    names = names or {}
    local info = util.funcinfo(fn)
    if not info.bytecodes then return names end
    for pc = 1, info.bytecodes - 1 do
        local instruction = util.funcbc(fn, pc)
        local op = instruction % 256
        if op == read_global or op == write_global then
            local index = bit.rshift(instruction, 16)
            names[util.funck(fn, -index - 1)] = true
        end
    end
    for i = 1, info.gcconsts do
        local child = util.funck(fn, -i)
        if type(child) == "proto" then M.environment_names(child, names) end
    end
    return names
end
return M
