-- The bench vocabulary: host contracts as belt
-- signatures (capability per parameter) rather than as constraint words, so `Cell` is a Named
-- resource with a destructor and the two hosts take Read parameters.
package.path = './?.lua;./?/init.lua;' .. package.path
local V = require('let')
local A, B, L = V.AST, V.Belt, V.List
local cell = B.Named('Cell')
return {
    hosts = {
        acquire = { symbol = 'bench_acquire', phase = 'runtime', purity = 'ordered',
            signature = B.Signature(L{B.Parameter(B.Int, A.Read)}, L{cell}) },
        peek = { symbol = 'bench_peek', phase = 'runtime', purity = 'ordered',
            signature = B.Signature(L{B.Parameter(cell, A.Read)}, L{B.Int}) },
    },
    resources = { Cell = { destroy = 'bench_release' } },
}
