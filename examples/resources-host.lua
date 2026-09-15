-- Host contracts for examples/resources.let. The embedding supplies app_open, app_size and
-- app_close; the compiler only declares them and calls them.
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local buffer=B.Named('Buffer')
return {
    resources = { Buffer = { destroy = 'app_close' } },
    hosts = {
        open_buffer = { symbol='app_open', phase='runtime', purity='ordered',
            signature=B.Signature(L{B.Parameter(B.Int,A.Read)},L{buffer}) },
        buffer_size = { symbol='app_size', phase='runtime', purity='ordered',
            signature=B.Signature(L{B.Parameter(buffer,A.Read)},L{B.Int}) },
    },
}
