-- The command line: one file in, one C translation unit out, diagnostics on stderr.
--
-- The generated unit is a MODULE and not a program. §2.6 makes the host a separate thing that supplies
-- `main`, calls `let_module_init`, and -- only when the module owns something -- calls
-- `let_module_unload` and gives the value up. So this writes the unit and says nothing about linking,
-- because linking is the host's business and every attempt to guess it would be a lie about the ABI.
--
-- The exit codes are §13's three kinds, because a script that cannot tell "your program is wrong" from
-- "the compiler is wrong" cannot report either: 0 ok, 1 Reject, 2 Missing or Bug.
return function(V)
    local Context = V.Context
    local compile = require('let.compile')(V)

    local function report(diagnostic)
        if not diagnostic then
            io.stderr:write('letc: the compiler stopped without a diagnostic\n')
            return 2
        end
        local span = diagnostic.span
        local where = ''
        if span then
            where = ('%s:%d:%d: '):format(tostring(span.file), tonumber(span.line) or 0,
                tonumber(span.column) or 0)
        end
        local kind = 'error'
        local code = 1
        if diagnostic:is_missing() then
            kind = 'unimplemented'
            code = 2
        elseif diagnostic:is_bug() then
            kind = 'internal'
            code = 2
        end
        -- `why` is a Report value, so its own spelling carries the vocabulary's name. A message a
        -- person reads should not: `MismatchedType`, not `Report.MismatchedType`.
        local why = tostring(diagnostic.why):gsub('^Report%.', '')
        -- A SYNTAX error carries the parser's own message, and that message already says where --
        -- `file:line:column: expected ...` -- so the constructor around it would say the position
        -- twice and the vocabulary once too often.
        if V.Report.Syntax:isclassof(diagnostic.why) then
            io.stderr:write(diagnostic.why.detail .. '\n')
            return code
        end
        io.stderr:write(('%s%s: %s\n'):format(where, kind, why))
        return code
    end

    return function(argv)
        local input, output
        local index = 1
        while argv[index] do
            local argument = argv[index]
            if argument == '-h' or argument == '--help' then
                io.stderr:write('usage: letc input.let [-o output.c]\n')
                return 0
            elseif argument == '-o' then
                index = index + 1
                output = argv[index]
                if not output then
                    io.stderr:write('letc: -o wants a path\n')
                    return 2
                end
            elseif argument:sub(1, 1) ~= '-' then
                input = input or argument
            else
                io.stderr:write('letc: unknown option ' .. argument .. '\n')
                return 2
            end
            index = index + 1
        end
        if not input then
            io.stderr:write('usage: letc input.let [-o output.c]\n')
            return 2
        end
        -- `-o -` writes to stdout, which is what a build system wants when it pipes.
        if not output then output = (input:gsub('%.let$', '')) .. '.c' end

        local file = io.open(input, 'rb')
        if not file then
            io.stderr:write('letc: cannot read ' .. input .. '\n')
            return 2
        end
        local text = file:read('*a')
        file:close()

        -- One `Compiler` for the whole run, because it owns `modules`: two files that import the same
        -- third one must share it, and a second load could disagree about the same bytes (§S39).
        local compiler = Context.compiler(V, {})
        local source, diagnostic
        local ok = compile.translation_unit(compiler, text, input,
            function(C, emitted) source = emitted; return true end,
            function(C, d) diagnostic = d; return false end)
        if not ok then return report(diagnostic) end

        if output == '-' then
            io.write(source)
            return 0
        end
        local out = io.open(output, 'wb')
        if not out then
            io.stderr:write('letc: cannot write ' .. output .. '\n')
            return 2
        end
        out:write(source)
        out:close()
        return 0
    end
end
