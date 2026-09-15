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
    local types={Int=B.Int,Float=B.Float,Bool=B.Bool,Unit=B.Unit,Text=B.Text}
    local destroy={}
    for name,descriptor in pairs(options.resources or {}) do
        assert(type(descriptor.destroy)=='string' and descriptor.destroy:match('^[A-Za-z_][A-Za-z0-9_]*$'),
            'resource requires a destructor symbol')
        types[name]=B.Named(name)
        destroy[name]=descriptor.destroy
    end
    local hosts={}
    local symbols={}
    for name,host in pairs(options.hosts or {}) do
        assert(host.phase=='runtime' and (host.purity=='ordered' or host.purity=='pure'),
            'host must declare runtime phase and purity')
        assert(type(host.symbol)=='string' and host.symbol:match('^[A-Za-z_][A-Za-z0-9_]*$'),
            'host requires a symbol')
        assert(B.Signature:isclassof(host.signature) and #host.signature.results==1,
            'host requires one Let result')
        assert(not symbols[host.symbol],'duplicate host symbol')
        symbols[host.symbol]=true
        hosts[name]=host
    end
    return setmetatable({types=types,destroy=destroy,hosts=hosts},Vocabulary)
end

function Vocabulary:type(name) return self.types[name] end
function Vocabulary:host(name) return self.hosts[name] end
function Vocabulary:destructor(name) return self.destroy[name] end

return Vocabulary
end
