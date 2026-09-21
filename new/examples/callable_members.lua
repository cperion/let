local Unary = word(U32)
local Handler = word{callback = Unary,
    run = word(U32, function(n) return callback(n) end),
}
local increment = word(U32, function(n) return n + 1 end)
return {types = {Unary = Unary, Handler = Handler}, results = {[Unary] = U32},
    functions = {run = Handler.run,
        apply = word(Handler, U32, function(h, n) return h.callback(n) end),
        local_handler = word(U32, function(n) return Handler{callback = increment}.run(n) end)},
}
