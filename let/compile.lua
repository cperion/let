-- The whole pipeline, in ONE place: text -> `C.Unit`.
--
-- It lived in `test/native.lua`, assembled by hand, which made the TEST the only thing that knew how
-- the phases fit together -- so nothing but a test could compile a file, and a pipeline written twice
-- is a pipeline that can disagree with itself about which phases ran or in what order. §12's order is
-- Resolve, Contract, Lower, Known, Emit; `Known` runs once per DEMANDED INSTANCE because an instance
-- is one belt function plus the answers of its entry packet (§12.4), and `Emit` consumes those
-- answers instead of recomputing them.
return function(V)
    local Context = V.Context

    -- `compiler` is the root context the caller owns: it holds `modules`, so two files that import the
    -- same third one share it, and a `Unit` is one source file under it (§6).
    local compile = {}

    -- `run` is the phases and their exits; the two below are the two USES of it, so nothing else has to
    -- know the order `Known` and `Emit` are driven in.
    function compile.run(compiler, text, name, k_ok, k_diag)
        local unit = compiler:child{ source = name }
        -- §13: a SYNTAX error is the PROGRAM's fault, so it is a `Reject` like any other. The lexer
        -- and the parser SIGNAL one by raising, because a malformed token stream has no judgment to
        -- return -- so this is where that becomes a diagnostic. Without it a typo escaped to the
        -- launcher and came out as "the compiler is broken" (exit 2), which is the one confusion
        -- §13's three kinds exist to prevent.
        local parsed, syntax = pcall(function() return V.parse(V.Lexer(text, name), name, text) end)
        if not parsed then
            -- The span is the unit's START and the position is inside the detail, because a token
            -- stream has no judgment to hang one on: the parser says `file:line:column: ...` in its
            -- message, and the CLI prints that message for a `Syntax` Reject rather than a span.
            return k_diag(unit, V.Report.reject(V.Report.Syntax(tostring(syntax)),
                V.Source.Span(name, 1, 1)))
        end

        local out, diagnostic
        local function ok(C, value) out = value; return true end
        local function bad(C, d) diagnostic = d; return false end

        if not V.Resolve.run(unit, syntax, ok, bad) then return k_diag(unit, diagnostic) end
        local resolved = out
        if not V.Contract.run(unit, resolved, ok, bad) then return k_diag(unit, diagnostic) end
        local program = out
        if not V.Lower.run(unit, program, syntax, ok, bad) then return k_diag(unit, diagnostic) end
        local belts = out

        local answers = {}
        for index, belt in ipairs(belts) do
            local region = unit:child{ instance = belt.name }:region()
            if not V.Known.run(region, belt, ok, bad) then return k_diag(unit, diagnostic) end
            answers[index] = out
        end
        if not V.Emit.run(unit, belts, answers, ok, bad) then return k_diag(unit, diagnostic) end
        return k_ok(unit, out, belts)
    end

    -- Generate, and then RENDER: the emitter produces a `C.Unit` because a host may still add to it
    -- (its own `main`, its own declarations), and rendering is what turns that into text.
    function compile.translation_unit(compiler, text, name, k_ok, k_diag)
        return compile.run(compiler, text, name, function(unit, c_unit)
            return k_ok(unit, V.print(c_unit), c_unit)
        end, k_diag)
    end

    function compile.source(compiler, path, span, k_ok, k_diag)
        local file = io.open(path, 'rb')
        if not file then return k_diag(nil, V.Report.reject(V.Report.MissingModule, span)) end
        local text = file:read('*a')
        file:close()
        return compile.translation_unit(compiler, text, path, k_ok, k_diag)
    end

    return compile
end
