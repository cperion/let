-- Source `extern` declarations become ordinary host descriptors, so a pure Let file can call a C
-- function with no embedding registration. The declaration states the Let signature; the C
-- prototype is derived from it, and the embedding may still refine a C width through options.
--
-- This is the producer side of spec §12.4: the program says what the foreign word means, and the
-- same descriptor a Lua options file would have written is what reaches the builder and emitter.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
-- `V.Lexer` is loaded after this module, so the diagnostic is looked up when it is used.
local function fail(span,message) V.Lexer.fail(span,message) end

local Extern={}

-- Merge every `extern` declaration in `file` into `options.hosts`, so resolution, construction
-- and emission all see one vocabulary.
function Extern.merge(file,options)
    local hosts=options.hosts or {}
    local types={Int=B.Int,Float=B.Float,Bool=B.Bool,Unit=B.Unit,Text=B.Text,CString=B.CString,CPointer=B.CPointer}
    for name in pairs(options.resources or {}) do types[name]=B.Named(name) end
    local function declared(constraint,span,message)
        if not constraint then return nil end
        local type_=types[constraint.name]
        if not type_ then fail(span,message .. ' ' .. constraint.name) end
        return type_
    end
    for _,item in ipairs(file.items) do
        if A.Extern:isclassof(item) then
            local parameters=L()
            for _,stage in ipairs(item.parameters) do
                local type_=declared(stage.constraint,stage.span,'unknown foreign type')
                if not type_ then fail(stage.span,'foreign parameter ' .. stage.name .. ' needs a type') end
                parameters:insert(B.Parameter(type_,stage.capability))
            end
            local result=declared(item.result,item.span,'unknown foreign type') or B.Unit
            hosts[item.name]={symbol=item.symbol or item.name,phase='runtime',
                purity=item.pure and 'pure' or 'ordered',
                signature=B.Signature(parameters,L{result})}
        end
    end
    options.hosts=hosts
    return hosts
end

return Extern
end
