-- Shared command-line behavior for wordc.lua and the single-file bundle.
-- It returns an exit status instead of exiting, so requiring this module has no side effects.
return function(Word, argv)
    local function main()
        if argv[1] == "--todos" then
            for _, item in ipairs(Word.todos()) do print(item.id .. "\t" .. item.next) end
            return
        end
        if not argv[1] or argv[2] then error("usage: luajit new/wordc.lua module.lua | --todos", 0) end
        local session = Word.new()
        local exports = session:load(argv[1])
        local function plain(t) return type(t) == "table" and getmetatable(t) == nil end
        local spec = (plain(exports.functions) or plain(exports.types) or plain(exports.results)) and exports
            or { functions = exports }
        io.write(session:emit_c(spec))
    end

    local ok, err = pcall(main)
    if ok then return 0 end
    io.stderr:write(tostring(err), "\n")
    local code = Word.is_diagnostic(err)
        and ({ reject = 1, bug = 2, todo = 3, resource = 4, lua = 1 })[err.kind]
        or 1
    return code or 1
end
