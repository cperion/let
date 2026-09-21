local root = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
package.path = root .. "?.lua;" .. root .. "?/init.lua;" .. package.path
local Word = require("word")

local function main()
    if arg[1] == "--todos" then
        for _, item in ipairs(Word.todos()) do print(item.id .. "\t" .. item.next) end
        return
    end
    if not arg[1] or arg[2] then error("usage: luajit new/wordc.lua module.lua | --todos", 0) end
    local session = Word.new()
    local exports = session:load(arg[1])
    local function plain(t) return type(t) == "table" and getmetatable(t) == nil end
    local spec = (plain(exports.functions) or plain(exports.types) or plain(exports.results)) and exports or { functions = exports }
    io.write(session:emit_c(spec))
end

local ok, err = pcall(main)
if not ok then
    io.stderr:write(tostring(err), "\n")
    local code = Word.is_diagnostic(err) and ({ reject = 1, bug = 2, todo = 3, resource = 4, lua = 1 })[err.kind] or 1
    os.exit(code)
end
