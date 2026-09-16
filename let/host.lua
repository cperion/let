-- The host vocabulary a program gets when no embedding supplies its own.
--
-- This is one decision in one place. `let/cli.lua` compiles a file and the language server
-- analyzes one; if they configured differently, the editor would report errors the compiler
-- does not, or miss names the compiler resolves. So the `c` namespace, the owned C memory
-- resource, and the default import resolver are installed here, and an embedding's own
-- dictionary, resources, or resolver always win.
--
-- `input.read` lets a host supply the bytes of an import, so an editor can return an open
-- buffer before the file on disk. `input.roots` adds search roots. Both are the resolver's
-- inputs; see let/file.lua.
return function(V)
local Host={}

function Host.configure(options,input)
    options=options or {}
    input=input or {}
    -- The C vocabulary is a namespace, so it cannot collide with a program's own names. The
    -- members are copied because a source `extern c.name` extends this namespace when it is
    -- merged, and a shared table would carry that declaration into every later program.
    local dictionary=options.dictionary or {}
    if not dictionary.c then
        local members={}
        for name,descriptor in pairs(V.libc.members) do members[name]=descriptor end
        dictionary.c={members=members}
    end
    options.dictionary=dictionary
    -- The C memory resource, with the embedding's own resources still winning.
    local resources={}
    for name,descriptor in pairs(V.libc.resources or {}) do resources[name]=descriptor end
    for name,descriptor in pairs(options.resources or {}) do resources[name]=descriptor end
    options.resources=resources
    if not options.resolve then
        options.resolve=V.file_resolver{roots=input.roots,read=input.read}
    end
    return options
end

return Host
end
