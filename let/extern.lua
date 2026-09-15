-- Source `extern` declarations become ordinary host descriptors, so a pure Let file can call a C
-- function with no embedding registration. The declaration states the Let signature; the C
-- prototype is derived from it, and a Text argument on a type states the exact C spelling where
-- the natural mapping is not what the function wants -- `Int "size_t"`, `CString "const void *"`.
--
-- This is the producer side of spec §12.4, and it produces the very descriptor a Lua options file
-- would have written, so resolution, construction and emission see one vocabulary.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
-- `V.Lexer` is loaded after this module, so the diagnostic is looked up when it is used.
local function fail(span,message) V.Lexer.fail(span,message) end

local Extern={}

-- The C spelling a Let type maps to when the declaration does not state one.
local function natural(type_,representations)
    if type_==B.Int then return 'int64_t' end
    if type_==B.Float then return 'double' end
    if type_==B.Bool then return 'bool' end
    if type_==B.Unit then return 'void' end
    if type_==B.CString then return 'const char*' end
    if type_==B.CPointer then return 'void*' end
    if B.Named:isclassof(type_) then
        return representations[type_.name]=='pointer' and 'void*' or 'int64_t'
    end
end

-- Merge every `extern` declaration in `file` into `options.hosts`, so resolution, construction
-- and emission all see one vocabulary.
function Extern.merge(file,options)
    local hosts=options.hosts or {}
    local types={Int=B.Int,Float=B.Float,Bool=B.Bool,Unit=B.Unit,Text=B.Text,CString=B.CString,CPointer=B.CPointer}
    local representations={}
    for name,descriptor in pairs(options.resources or {}) do
        types[name]=B.Named(name)
        representations[name]=descriptor.representation or 'value'
    end
    -- A constraint is a Let type, optionally followed by a Text naming its exact C spelling.
    local function declared(constraint,span,message)
        if not constraint then return nil,nil end
        local type_=types[constraint.name]
        if not type_ then fail(span,message .. ' ' .. constraint.name) end
        local spelling
        if #constraint.arguments>0 then
            local argument=constraint.arguments[1]
            if not A.Text:isclassof(argument) then fail(span,'a C spelling must be a Text') end
            if #constraint.arguments>1 then fail(span,'a foreign type takes one C spelling') end
            spelling=argument.value
        end
        return type_,spelling
    end
    for _,item in ipairs(file.items) do
        if A.Extern:isclassof(item) then
            local parameters,cparams=L(),{}
            for i,stage in ipairs(item.parameters) do
                local type_,spelling=declared(stage.constraint,stage.span,'unknown foreign type')
                if not type_ then fail(stage.span,'foreign parameter ' .. stage.name .. ' needs a type') end
                parameters:insert(B.Parameter(type_,stage.capability))
                spelling=spelling or natural(type_,representations)
                if not spelling then fail(stage.span,'no C type for foreign parameter ' .. stage.name) end
                -- A mutable stage is a place, so it is passed by address.
                if stage.capability==A.Mut and spelling:sub(-1)~='*' then spelling=spelling .. '*' end
                cparams[i]=spelling
            end
            local result,spelling=declared(item.result,item.span,'unknown foreign type')
            result=result or B.Unit
            hosts[item.name]={symbol=item.symbol or item.name,phase='runtime',
                purity=item.pure and 'pure' or 'ordered',
                signature=B.Signature(parameters,L{result}),
                c={params=cparams,result=spelling or natural(result,representations) or 'void'}}
        end
    end
    options.hosts=hosts
    return hosts
end

return Extern
end
