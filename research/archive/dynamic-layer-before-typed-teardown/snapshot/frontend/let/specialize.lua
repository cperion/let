-- Residual specialization from values produced by abc_vm. This module builds ordinary verified IR;
-- it does not execute or fold user operations in Lua. The shared C optimizer performs specialization.
local ffi = require("ffi")
local S = require("let.schema")
local IR = require("let.ir")
local Check = require("let.check")
local ABC = require("let.abc")
local Optimizer = require("let.optimize")
local D = require("let.diag")

ffi.cdef [[ typedef union { uint64_t u; uint32_t word[2]; double d; } let_specialize_bits; ]]
local Bits = ffi.typeof("let_specialize_bits")
local I, L = S.Ir, S.ASDL.List
local M = {}

local function definition(functions, name)
    for _,fn in ipairs(functions) do if fn.id==name then return fn end end
    D.reject("specialize-entry","Unknown specialization entry `"..tostring(name).."`")
end

local function constant(builder, value, expected)
    if type(value)~="table" or value.type~=expected or value.bits==nil then
        D.reject("specialize-value","Known arguments must be typed values returned by VM staging")
    end
    local bits=Bits();bits.u=value.bits
    if expected==S.bool then return builder:bool(bits.word[0]~=0) end
    if expected==S.unit then return builder:const(S.unit,I.UInt(0)) end
    if expected==S.f64 then return builder:float(S.f64,bits.d) end
    if expected:isInteger() then
        if expected:isWide() then return builder:int64(expected,tonumber(bits.word[1]),tonumber(bits.word[0])) end
        return builder:int(expected,tonumber(bits.word[0]))
    end
    D.todo("specialize-type","Known-value specialization is not implemented for "..S.display(expected))
end

function M.build(functions, options)
    options=options or {};local target=definition(functions,options.entry or "main")
    if target.hidden~=0 then D.todo("specialize-hidden","Specialization of hidden callable inputs is not implemented") end
    local name=options.name or (target.id.."__specialized")
    for _,fn in ipairs(functions) do if fn.id==name then D.reject("specialize-name","Specialized function name already exists: "..name) end end
    local known=options.known or {};local builder=IR.builder();local inputs,params,args={}, {}, {}
    for index,input in ipairs(target.inputs) do
        if input.kind~="InValue" then D.todo("specialize-borrow","Known-value specialization of borrowed inputs is not implemented") end
        local fixed=known[index]
        if fixed then args[index]=I.ValueArg(constant(builder,fixed,input.type))
        else
            inputs[#inputs+1]=S.inValue(input.type);local value=builder:valueId()
            params[#params+1]=I.ValueParam(#inputs-1,value,input.type)
            args[index]=I.ValueArg(builder:ref(value,input.type))
        end
    end
    for index in pairs(known) do if type(index)~="number" or index<1 or index>#target.inputs or index%1~=0 then D.reject("specialize-argument","Known argument index is outside the entry signature") end end
    local results={} for index=1,#target.results do results[index]=builder:valueId() end
    local body={I.Call(L(results),target.id,L(args))};local returned={}
    for index,value in ipairs(results) do returned[index]=builder:ref(value,target.results[index]) end
    body[#body+1]=I.Return(L(returned))
    local wrapper=I.Fn(name,I.Entry,0,L(inputs),L(target.results),L(params),L(body))
    local combined={} for _,fn in ipairs(functions) do combined[#combined+1]=fn end;combined[#combined+1]=wrapper
    Check.program(combined)
    return wrapper,combined
end

function M.specialize(functions, options)
    local wrapper,combined=M.build(functions,options)
    local lower={} for key,value in pairs(options or {}) do lower[key]=value end
    lower.profile=lower.profile or "slet";lower.exports={wrapper.id}
    local artifact=ABC.lower(combined,lower)
    local ok,Assembler=pcall(require,"assembler");if not ok then D.internal("specialize-host","Cannot load assembler: "..tostring(Assembler)) end
    local bytes,locations=Assembler.assemble(artifact.assembly)
    local module,provenance=Optimizer.optimizeMapped(bytes)
    return {phase="specialized",entry=wrapper.id,fn=wrapper,functions=combined,artifact=artifact,module=module,locations=locations,provenance=provenance}
end

return M

