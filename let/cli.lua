-- The command-line host: compiles one file to C, and to a complete C program when the file
-- exports a word named `main` that still needs no stage. It is a host, not the compiler: it
-- chooses the vocabulary (libc, then the embedding's, so the embedding wins) and the entry,
-- which is what §15.1 leaves to the embedding.
return function(V,arg)
    arg = arg or {}

    -- An exported word named `main` that needs no stage is the program's entry.
    local function entry(builder)
        for _,candidate in ipairs(builder.host_entries or {}) do
            if candidate.name=='main' and candidate.stages==0 then return candidate end
        end
    end

    -- A complete C program: the module initializer, then the entry, plus the trap hook an
    -- executable must provide. `statistics` carries the entry's C name and the namespace members
    -- it takes as parameters.
    local function executable(unit,statistics)
        local namespace
        for _,declaration in ipairs(unit.declarations) do
            if V.C.Function:isclassof(declaration) and declaration.name=='let_module_init' then
                namespace=declaration.result
            end
        end
        local main
        for _,candidate in ipairs(statistics.entries or {}) do
            if candidate.name=='main' then main=candidate end
        end
        if not (namespace and main and main.c_name) then return unit end
        local arguments={}
        for _,field in ipairs(main.fields) do arguments[#arguments+1]=('ns.r0.f%d'):format(field) end
        local declarations=V.List()
        for _,declaration in ipairs(unit.declarations) do declarations:insert(declaration) end
        declarations:insert(V.C.Raw('void let_trap(char* reason){ fputs(reason,stderr); fputc(10,stderr); abort(); }'))
        declarations:insert(V.C.Raw(('int main(void){ %s ns = let_module_init(); %s(%s); return 0; }')
            :format(namespace:print(),main.c_name,table.concat(arguments,', '))))
        local includes,seen=V.List(),{}
        for _,include in ipairs(unit.includes) do includes:insert(include); seen[include]=true end
        for _,include in ipairs{'stdio.h','stdlib.h'} do
            if not seen[include] then includes:insert(include) end
        end
        return V.C.Unit(includes,declarations)
    end

    local function compile(input,output,options_path)
        local file=assert(io.open(input,'rb'))
        local text=file:read('*a'); file:close()
        local options=options_path and dofile(options_path) or {}
        -- The C vocabulary is a namespace, so it cannot collide with a program's own names;
        -- an embedding or options file that declares `c` itself wins.
        local dictionary=options.dictionary or {}
        if not dictionary.c then dictionary.c={members=V.libc} end
        options.dictionary=dictionary
        local program,builder=V.parse(text,input):build(options)
        -- This is a host, and it publishes every exported word: §15.1's "the host selects".
        options.entries=options.entries or builder.host_entries
        options.statistics=options.statistics or {}
        local unit=program:emit(options)
        if entry(builder) then unit=executable(unit,options.statistics) end
        local source=V.print(unit)
        if output then
            local out=assert(io.open(output,'wb')); out:write(source); out:close()
        else io.write(source) end
    end

    local ok,err=pcall(function()
        if not arg[1] or #arg>3 then
            error('usage: luajit letc.lua input.let [output.c [options.lua]]',0)
        end
        compile(arg[1],arg[2],arg[3])
    end)
    if not ok then io.stderr:write(tostring(err),'\n'); os.exit(1) end
end
