-- The names a program may refer to and the contracts behind them: the scalar types, the
-- registered resources with their destructors, and the runtime hosts. Validated once, so a call
-- site, an entry and the verifier cannot disagree about a descriptor, and no phase rebuilds the
-- base type table.
return function(V)
local B=V.Belt

local Vocabulary={}; Vocabulary.__index=Vocabulary

-- One validated vocabulary for a program. A descriptor that is malformed fails here, with the
-- message naming the contract, rather than at whichever consumer happened to read it first.
function Vocabulary.new(options)
    options=options or {}
    local types={Int=B.Int,Float=B.Float,Bool=B.Bool,Unit=B.Unit,Text=B.Text,CString=B.CString,CPointer=B.CPointer}
    local representations={}
    local destroy={}
    for name,descriptor in pairs(options.resources or {}) do
        assert(type(descriptor.destroy)=='string' and descriptor.destroy:match('^[A-Za-z_][A-Za-z0-9_]*$'),
            'resource requires a destructor symbol')
        if descriptor.representation~=nil then
            assert(descriptor.representation=='pointer' or descriptor.representation=='value',
                'resource representation must be pointer or value')
        end
        types[name]=B.Named(name)
        destroy[name]=descriptor.destroy
        representations[name]=descriptor.representation or 'value'
    end
    local hosts={}
    local symbols={}
    -- The C spelling a host declares must describe its Let type: an integer width for `Int` or a
    -- value resource, an object pointer for a borrowed view or a pointer resource, and
    -- `double`/`bool`/`void` for the rest. This is where the one declaration is checked, rather
    -- than in the C compiler.
    local function compact(name) return (name:gsub('%s','')) end
    local c_integer={}
    for _,name in ipairs{'char','signedchar','unsignedchar','short','unsignedshort','int','unsigned',
        'long','unsignedlong','longlong','unsignedlonglong','size_t','ssize_t','ptrdiff_t','intptr_t',
        'uintptr_t','int8_t','uint8_t','int16_t','uint16_t','int32_t','uint32_t','int64_t','uint64_t'} do
        c_integer[name]=true
    end
    local function c_kind(spelling)
        local c=compact(spelling)
        if c_integer[c] then return 'integer' end
        if c=='double' or c=='float' then return c end
        if c=='bool' or c=='_Bool' then return 'bool' end
        if c=='void' then return 'void' end
        if c:sub(-1)=='*' then return 'pointer' end
        return 'unknown'
    end
    local function compatible(let_type,kind)
        if kind=='integer' then
            return let_type==B.Int or (B.Named:isclassof(let_type) and representations[let_type.name]~='pointer')
        end
        if kind=='double' or kind=='float' then return let_type==B.Float end
        if kind=='bool' then return let_type==B.Bool end
        if kind=='pointer' then
            return let_type==B.CString or let_type==B.CPointer
                or (B.Named:isclassof(let_type) and representations[let_type.name]=='pointer')
        end
        if kind=='void' then return let_type==B.Unit end
        return false
    end
    local function add_host(name,host)
        assert(host.phase=='runtime' and (host.purity=='ordered' or host.purity=='pure'),
            'host must declare runtime phase and purity')
        assert(type(host.symbol)=='string' and host.symbol:match('^[A-Za-z_][A-Za-z0-9_]*$'),
            'host requires a symbol')
        assert(B.Signature:isclassof(host.signature) and #host.signature.results==1,
            'host requires one Let result')
        if host.c then
            for i,spelling in ipairs(host.c.params or {}) do
                local parameter=host.signature.parameters[i]
                assert(parameter,'the C prototype has more parameters than the Let signature')
                -- A mutable stage is a place, so it is a pointer whatever its pointee is.
                local ok=(parameter.capability==V.AST.Mut and c_kind(spelling)=='pointer')
                    or (parameter.capability~=V.AST.Mut and c_kind(spelling)~='unknown' and compatible(parameter.type,c_kind(spelling)))
                assert(ok,('C type %s does not describe Let parameter %d'):format(spelling,i))
            end
            if host.c.result then
                -- A Unit result discards the C value, so any C result type describes it.
                local result=host.signature.results[1]
                if result~=B.Unit then
                    local kind=c_kind(host.c.result)
                    assert(kind~='unknown' and compatible(result,kind),
                        ('C result %s does not describe the Let result'):format(host.c.result))
                end
            end
        end
        -- The boundary declares ownership and nullability, which C's type system cannot: they
        -- only mean anything for a pointer result.
        if host.ownership~=nil then
            assert(host.ownership=='owned' or host.ownership=='borrowed',
                'host ownership must be owned or borrowed')
        end
        if host.nullable~=nil then
            assert(type(host.nullable)=='boolean','host nullability must be a boolean')
        end
        if host.ownership~=nil or host.nullable~=nil then
            local result=host.signature.results[1]
            assert(result==B.CString or result==B.CPointer,
                'ownership and nullability apply to a pointer result')
        end
        -- A symbol may be declared twice with the same Let signature: a source `extern` for a
        -- libc name the embedding also registers, for instance. The first declaration wins.
        local existing=symbols[host.symbol]
        if existing then
            local same=#existing.signature.parameters==#host.signature.parameters
                and #existing.signature.results==#host.signature.results
            if same then
                for i,parameter in ipairs(existing.signature.parameters) do
                    local other=host.signature.parameters[i]
                    same=same and parameter.capability==other.capability and parameter.type:same(other.type)
                end
                for i,result in ipairs(existing.signature.results) do same=same and result:same(host.signature.results[i]) end
            end
            assert(same,'host symbol ' .. host.symbol .. ' is declared with two different signatures')
        else
            symbols[host.symbol]=host
        end
        hosts[name]=host
    end
    for name,host in pairs(options.hosts or {}) do add_host(name,host) end
    -- A namespace member is a host too, but it has no top-level name; symbol lookup still needs it.
    for _,namespace in pairs(options.dictionary or {}) do
        for name,member in pairs(namespace.members or {}) do
            if member.signature then add_host(name,member) end
        end
    end
    return setmetatable({types=types,destroy=destroy,representations=representations,
        hosts=hosts,symbols=symbols},Vocabulary)
end

function Vocabulary:type(name) return self.types[name] end
function Vocabulary:host(name) return self.hosts[name] end
function Vocabulary:destructor(name) return self.destroy[name] end
function Vocabulary:representation(name) return self.representations[name] end

return Vocabulary
end
