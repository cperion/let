-- A default import resolver for hosts that do not supply their own.
--
-- §15.2 fixes only the *semantics* of an import: the named file's chain is constructed at
-- the import site. Where a path is looked up, which extension is assumed, and whether
-- anything is cached are embedding decisions, so they live here beside the compiler rather
-- than in the language. A host with its own layout should pass its own resolver instead.
--
-- The path search and the bytes are also separate. A host may supply `read`, which turns a
-- candidate path into text, so an editor can return an unsaved open buffer before the file
-- on disk. The default reads whatever path the search found.
return function(options)
    options=options or {}
    local suffix=options.suffix==nil and '.let' or options.suffix
    local roots=options.roots or {}
    local read=options.read or function(path)
        local file=io.open(path,'r')
        if not file then return nil end
        local text=file:read('*a'); file:close()
        return text
    end
    return function(path,from)
        local directory=from and from:match('^(.*)/') or '.'
        local candidates={path}
        if suffix~='' and path:sub(-#suffix)~=suffix then candidates[#candidates+1]=path..suffix end
        -- Relative to the importing file first, then the configured roots, then as given.
        local bases={directory}
        for _,root in ipairs(roots) do bases[#bases+1]=root end
        bases[#bases+1]=''
        for _,base in ipairs(bases) do
            for _,candidate in ipairs(candidates) do
                local full=(base=='' and candidate) or (base .. '/' .. candidate)
                local text=read(full)
                if text then return {text=text,file=full} end
            end
        end
        return nil
    end
end
