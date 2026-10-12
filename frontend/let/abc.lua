-- Checked lowering from verified ASDL Ir to ABC assembly.
--
-- This is the single typed instruction-selection path for staging and residual
-- modules. It does not inspect source filenames and never evaluates user code.
local Check = require("let.check")
local D = require("let.diag")
local S = require("let.schema")
local Walk = require("let.walk")

local M = {}

local REASONS = {
    ["division-zero"] = 1,
    ["index-range"] = 2,
    ["numeric-range"] = 3,
    ["negative-exponent"] = 4,
    unreachable = 5,
}

local function identifier(name)
    return type(name) == "string" and name:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local unsupported
local memoryWidth, layout
local function cellKind(ty)
    if ty == S.unit then return nil end
    if ty:isInteger() or ty == S.bool then return "i" end
    if ty == S.f64 then return "f" end
    if ty:isRef() or ty:isPtr() then return "a" end
    return false
end

local function valueComponents(ty)
    local kind=cellKind(ty)
    if kind then return {ty} end
    if ty==S.unit then return {} end
    if ty:isSlice() then return {S.ref(ty.element),S.u32} end
    if ty:isView() then return {S.ptr(S.unit),S.ptr(S.unit)} end
    local result={}
    if ty:isRecord() then
        for _,field in ipairs(ty.fields) do local parts=valueComponents(field.type);if parts==false then return false end;for _,part in ipairs(parts) do result[#result+1]=part end end
        return result
    end
    if ty:isArray() then
        local parts=valueComponents(ty.element);if parts==false then return false end
        for _=1,ty.length do for _,part in ipairs(parts) do result[#result+1]=part end end
        return result
    end
    return false
end

local function rawAggregateSafe(ty,seen)
    if ty==S.unit or ty:isInteger() or ty==S.bool or ty==S.f64 then return true end
    seen=seen or {};if seen[ty] then return true end;seen[ty]=true
    if ty:isRecord() then for _,field in ipairs(ty.fields) do if not rawAggregateSafe(field.type,seen) then return false end end;return true end
    if ty:isArray() then return rawAggregateSafe(ty.element,seen) end
    if ty:isTaggedType() then for _,field in ipairs(S.alternatives(ty)) do if not rawAggregateSafe(field.type,seen) then return false end end;return true end
    return false
end

local function abiComponents(ty)
    local components=valueComponents(ty)
    if components~=false then return components end
    if ty:isTaggedType() then
        if not rawAggregateSafe(ty) then unsupported("aggregate call ABI with managed or address-bearing sum "..S.display(ty)) end
        local result={} for _=1,math.floor((layout(ty).size+7)/8) do result[#result+1]=S.u64 end;return result
    end
    return false
end

local function cellKinds(ty)
    local components=abiComponents(ty)
    if components==false then return false end
    local result={}
    for _,component in ipairs(components) do result[#result+1]=cellKind(component) end
    return result
end

local function align(value, boundary) return math.floor((value + boundary - 1) / boundary) * boundary end
layout=function(ty, seen)
    if ty == S.unit then return {size=0,align=1} end
    if ty == S.bool or ty == S.u8 then return {size=1,align=1} end
    if ty == S.u16 then return {size=2,align=2} end
    if ty == S.u32 or ty == S.i32 then return {size=4,align=4} end
    if ty == S.u64 or ty == S.i64 or ty == S.f64 or ty:isRef() or ty:isPtr() then return {size=8,align=8} end
    if ty:isSlice() then return {size=16,align=8,fields={data={offset=0,type=S.ref(ty.element)},length={offset=8,type=S.u32}}} end
    if ty:isView() then return {size=16,align=8,fields={code={offset=0,type=S.ptr(S.unit)},environment={offset=8,type=S.ref(S.unit)}}} end
    seen=seen or {};if seen[ty] then unsupported("recursive by-value layout "..S.display(ty)) end;seen[ty]=true
    if ty:isRecord() then
        local result={size=0,align=1,fields={}}
        for _,field in ipairs(ty.fields) do local item=layout(field.type,seen);result.size=align(result.size,item.align);result.fields[field.name]={offset=result.size,type=field.type,layout=item};result.size=result.size+item.size;if item.align>result.align then result.align=item.align end end
        result.size=align(result.size,result.align);seen[ty]=nil;return result
    end
    if ty:isArray() then local item=layout(ty.element,seen);local stride=align(item.size,item.align);seen[ty]=nil;return {size=stride*ty.length,align=item.align,element=item,stride=stride} end
    if ty:isTaggedType() then
        local result={align=4,tags={},payloads={}};local payloadSize=0
        for index,case in ipairs(S.alternatives(ty)) do local item=layout(case.type,seen);result.tags[case.name]=index-1;result.payloads[case.name]={type=case.type,layout=item};if item.align>result.align then result.align=item.align end;if item.size>payloadSize then payloadSize=item.size end end
        result.payloadOffset=align(4,result.align);for _,payload in pairs(result.payloads) do payload.offset=result.payloadOffset end
        result.size=align(result.payloadOffset+payloadSize,result.align);seen[ty]=nil;return result
    end
    seen[ty]=nil;unsupported("layout of type "..S.display(ty))
end

local function rootStorage(place)
    while place and (place.kind=="Project" or place.kind=="Index") do place=place.base end
    if place and place.kind=="Local" then return place.storage.id end
end

unsupported = function(what)
    D.todo("abc-lowering", "ABC lowering is not implemented for " .. what)
end

local function requireScalar(ty, where)
    local kind = cellKind(ty)
    if kind == false then unsupported(where .. " of type " .. S.display(ty)) end
    return kind
end

local function countCells(types)
    local count = 0
    for _,ty in ipairs(types) do local kinds=cellKinds(ty);if kinds==false then unsupported("cell representation of "..S.display(ty)) end;count=count+#kinds end
    return count
end

local function intLiteral(literal)
    if literal.kind == "UInt" then return string.format("%.0f", literal.value) end
    if literal.kind == "UInt64" then
        return string.format("0x%08x%08x", literal.high, literal.low)
    end
    D.bug("ir-literal", "Expected an integer literal during ABC lowering")
end

local floatBits
local function floatLiteral(value)
    if type(value)=='table' then
        if value.kind=='FloatBits' then return string.format('0x%08x%08x',value.high,value.low) end
        value=value.value
    end
    if not floatBits then
        local ffi = require("ffi")
        ffi.cdef("typedef union { double d; uint32_t word[2]; } let_abc_double_bits;")
        floatBits = ffi.new("let_abc_double_bits")
    end
    floatBits.d = value
    return string.format("0x%08x%08x", tonumber(floatBits.word[1]), tonumber(floatBits.word[0]))
end


local function other(stack) return stack == "A" and "B" or "A" end
local Function = {}
Function.__index = Function

function Function.new(fn, definitions, profile, constants, metadata)
    if not identifier(fn.id) then D.reject("lower-name", "Invalid ABC function name " .. tostring(fn.id)) end
    constants = constants or {};metadata=metadata or {}

    local self = setmetatable({
        fn = fn,
        definitions = definitions,
        profile = profile,
        lines = {},
        indirectInfo=metadata.indirectInfo or {},
        lineMap = {},
        labels = 0,
        loops = {},
        views = {},
        aggregates = {},
        valueSlots = {},
        storageSlots = {},
        locals = {},
        blocks = {},
        blockCells = 0,
        addressTaken = {},
        inputCells = 0,
        constants = constants,
        viewInfo=metadata.viewInfo or {},
    }, Function)

    Walk.walk(fn,{enter=function(node)
        if node.kind=="Addr" or node.kind=="BorrowArg" then local id=rootStorage(node.place);if id then self.addressTaken[id]=true end end
    end})
    self.profile=profile
    local physical = 0;self.inputPhysical={}
    for index,input in ipairs(fn.inputs) do
        local kinds=input.kind=="InPlace" and {"a"} or cellKinds(input.type)
        if kinds==false then unsupported("function input of type "..S.display(input.type)) end
        self.inputPhysical[index-1]={base=physical,count=#kinds};physical=physical+#kinds;self.inputCells=self.inputCells+#kinds
    end
    for _,result in ipairs(fn.results) do if cellKinds(result)==false then unsupported("function result of type "..S.display(result)) end end
    for _,param in ipairs(fn.params) do
        local input=self.inputPhysical[param.input];if not input then D.bug("lower-param","Parameter has no physical input") end
        if param.kind=="ValueParam" then
            local components=valueComponents(param.type)
            if components==false and param.type:isTaggedType() then
                local item=layout(param.type);local slot={block=true,type=param.type,layout=item,cells=math.floor((item.size+7)/8),initialParameters={}}
                for i=1,input.count do slot.initialParameters[i]={parameter=input.base+i-1,type=S.u64} end
                self.blocks[#self.blocks+1]=slot;self.blockCells=self.blockCells+slot.cells;self.valueSlots[param.binding.id]=slot
            elseif components==false or #components~=input.count then D.bug("lower-param","Parameter representation disagrees with input")
            elseif #components==1 then self.valueSlots[param.binding.id]={parameter=input.base,type=param.type}
            elseif #components>1 then local holder={type=param.type,cells={}};for i,component in ipairs(components) do holder.cells[i]={parameter=input.base+i-1,type=component} end;self.valueSlots[param.binding.id]=holder end
        elseif param.kind=="PlaceParam" then
            if input.count~=1 then D.bug("lower-param","Place parameter is not one address cell") end
            self.storageSlots[param.binding.id]={parameter=input.base,address=true,type=param.type}
        else unsupported("parameter "..param.kind) end
    end


    local function reserve(map,id,ty,place,forceFrame)
        if map[id] then D.bug("lower-slot","IR slot "..tostring(id).." is defined twice") end
        local components=valueComponents(ty)
        if not place and components and #components>0 and not cellKind(ty) then
            local holder={type=ty,cells={}};for _,component in ipairs(components) do local slot={index=#self.locals+1,type=component};self.locals[#self.locals+1]=slot;holder.cells[#holder.cells+1]=slot end;map[id]=holder;return
        end
        local kind=cellKind(ty)
        if kind and not forceFrame and not (place and self.addressTaken[id]) then local slot={index=#self.locals+1,type=ty};self.locals[#self.locals+1]=slot;map[id]=slot;return end
        if not place then requireScalar(ty,"local value");return end
        local item=layout(ty);if item.size<1 then unsupported("storage for zero-sized type "..S.display(ty)) end
        if item.size>65535 then unsupported("frame object larger than 65535 bytes") end
        local slot={block=true,type=ty,layout=item,cells=math.floor((item.size+7)/8)}
        self.blocks[#self.blocks+1]=slot;self.blockCells=self.blockCells+slot.cells;map[id]=slot
    end

    local scanList
    scanList = function(list)
        for _, stmt in ipairs(list) do
            local kind = stmt.kind
            if kind == "Let" then
                if stmt.type:isRecord() and stmt.expr.kind=="Make" then self.aggregates[stmt.value.id]=stmt.expr end
                reserve(self.valueSlots, stmt.value.id, stmt.type, stmt.type:isTaggedType())
            elseif kind == "Read" then
                reserve(self.valueSlots, stmt.value.id, stmt.type, stmt.type:isTaggedType())
            elseif kind == "Var" then
                reserve(self.storageSlots, stmt.storage.id, stmt.type, true)
            elseif kind == "Call" then
                local target = definitions[stmt.target]
                if not target then D.bug("lower-target", "Unknown call target " .. tostring(stmt.target)) end
                for index, value in ipairs(stmt.results) do
                    local ty=target.results[index];reserve(self.valueSlots,value.id,ty,ty:isTaggedType())
                end
            elseif kind == "View" then
                local info=self.viewInfo[stmt]
                if info and stmt.type:isView() then reserve(self.valueSlots,stmt.value.id,stmt.type) end
                if info and info.environment then reserve(self.storageSlots,stmt.adapter.id,info.environment,true,true) end
                self.views[stmt.value.id]={entry=stmt.entry,type=stmt.type,statement=stmt,info=info}
            elseif kind == "Dynamic" then
                unsupported("dynamic operations")
            elseif kind == "Indirect" then
                if stmt.callable.type==S.any then unsupported("dynamic calls") end
                local results=stmt.callable.type.visible.results
                for index,value in ipairs(stmt.results) do local ty=results[index];reserve(self.valueSlots,value.id,ty,ty:isTaggedType()) end
            elseif kind == "If" then
                scanList(stmt.yes)
                scanList(stmt.no)
            elseif kind == "Loop" then
                scanList(stmt.body)
            elseif kind=="ConstructVariant" then
                reserve(self.valueSlots,stmt.value.id,stmt.type,true)
            elseif kind=="VariantMatches" then
                reserve(self.valueSlots,stmt.value.id,S.bool)
            elseif kind=="VariantPayload" then
                local ty=S.caseOf(stmt.sum,stmt.tag);reserve(self.valueSlots,stmt.value.id,ty,ty:isTaggedType())
            elseif kind=="Switch" then
                for _,case in ipairs(stmt.cases) do scanList(case.body) end
            end
        end
    end
    scanList(fn.body)
    local offset=0
    for index=#self.blocks,1,-1 do local slot=self.blocks[index];offset=offset+slot.cells*8;slot.frameOffset=offset end
    return self
end

function Function:emit(text, node)
    self.lines[#self.lines + 1] = text
    self.lineMap[#self.lines] = node or false
end

function Function:instruction(text, node) self:emit("  " .. text, node) end

function Function:label(node)
    self.labels = self.labels + 1
    return "_abc_" .. self.labels
end

function Function:place(label, node) self:emit(label .. ":", node) end

function Function:depth(slot)
    if slot.parameter ~= nil then return self.blockCells + #self.locals + slot.parameter end
    return self.blockCells + #self.locals - slot.index
end

function Function:valueDepth(value)
    local slot = self.valueSlots[value.id]
    if not slot then D.bug("lower-value", "No ABC slot for value " .. tostring(value.id)) end
    return self:depth(slot)
end

function Function:storageSlot(storage)
    local slot=self.storageSlots[storage.id]
    if not slot then D.bug("lower-storage","No ABC slot for storage "..tostring(storage.id)) end
    return slot
end

function Function:storageDepth(storage) return self:depth(self:storageSlot(storage)) end

function Function:valueBlock(value)
    local slot=self.valueSlots[value.id]
    if not slot or not slot.block then D.bug("lower-value","Value "..tostring(value.id).." has no aggregate frame block") end
    return slot
end

function Function:blockLoad(slot,offset,ty,node,stack)
    stack=stack or "A"
    local item=layout(ty)
    if ty:isRecord() then for _,field in ipairs(ty.fields) do self:blockLoad(slot,offset+item.fields[field.name].offset,field.type,node,stack) end;return end
    if ty:isArray() then for index=0,ty.length-1 do self:blockLoad(slot,offset+index*item.stride,ty.element,node,stack) end;return end
    if ty:isSlice() then self:blockLoad(slot,offset,S.ref(ty.element),node,stack);self:blockLoad(slot,offset+8,S.u32,node,stack);return end
    if ty:isView() then self:blockLoad(slot,offset,S.ptr(S.unit),node,stack);self:blockLoad(slot,offset+8,S.ref(S.unit),node,stack);return end
    if ty:isTaggedType() then for index=0,math.floor((item.size+7)/8)-1 do self:instruction("FADDR."..stack.." "..slot.frameOffset,node);self:instruction("LD64."..stack.." "..(offset+index*8),node) end;return end
    local width=memoryWidth(ty);if not width then unsupported("memory load of "..S.display(ty)) end
    self:instruction("FADDR."..stack.." "..slot.frameOffset,node)
    if ty==S.f64 then self:instruction(".loadkind float",node) elseif ty:isRef() or ty:isPtr() then self:instruction(".loadkind addr",node) end
    self:instruction("LD"..width.."."..stack.." "..offset,node)
end

function Function:blockStore(slot,offset,ty,node,stack)
    stack=stack or "A"
    local address=other(stack)
    local item=layout(ty)
    if ty:isRecord() then for index=#ty.fields,1,-1 do local field=ty.fields[index];self:blockStore(slot,offset+item.fields[field.name].offset,field.type,node,stack) end;return end
    if ty:isArray() then for index=ty.length-1,0,-1 do self:blockStore(slot,offset+index*item.stride,ty.element,node,stack) end;return end
    if ty:isSlice() then self:blockStore(slot,offset+8,S.u32,node,stack);self:blockStore(slot,offset,S.ref(ty.element),node,stack);return end
    if ty:isView() then self:blockStore(slot,offset+8,S.ref(S.unit),node,stack);self:blockStore(slot,offset,S.ptr(S.unit),node,stack);return end
    if ty:isTaggedType() then for index=math.floor((item.size+7)/8)-1,0,-1 do self:instruction("FADDR."..address.." "..slot.frameOffset,node);self:instruction("ST64."..address.." "..(offset+index*8),node) end;return end
    local width=memoryWidth(ty);if not width then unsupported("memory store of "..S.display(ty)) end
    self:instruction("FADDR."..address.." "..slot.frameOffset,node);self:instruction("ST"..width:gsub("S$","").."."..address.." "..offset,node)
end

function Function:placeType(place)
    if place.kind=="Local" then return self:storageSlot(place.storage).type end
    if place.kind=="Project" then local base=self:placeType(place.base);for _,field in ipairs(base.fields) do if field.name==place.field.name then return field.type end end end
    if place.kind=="Deref" or place.kind=="Index" or place.kind=="SliceIndex" or place.kind=="PtrIndex" then return place.type end
    D.bug("lower-place","Cannot determine type of Ir."..tostring(place.kind))
end

function Function:placeBase(place,node,stack)
    stack=stack or "A"
    local opposite=other(stack)
    if place.kind=="Local" then
        local slot=self:storageSlot(place.storage)
        if slot.block then self:instruction("FADDR."..stack.." "..slot.frameOffset,node);return 0 end
        if slot.address then self:instruction("CGET."..stack.." "..self:depth(slot),node);return 0 end
        unsupported("address of non-addressable scalar local")
    elseif place.kind=="Project" then
        local baseType=self:placeType(place.base);local field=layout(baseType).fields[place.field.name]
        if not field then D.bug("lower-field","Unknown projected field "..tostring(place.field.name)) end
        return self:placeBase(place.base,node,stack)+field.offset
    elseif place.kind=="Deref" then
        self:loadPlace(place.base,node,stack);return 0
    elseif place.kind=="Index" then
        local baseType=self:placeType(place.base);local item=layout(baseType)
        self:address(place.base,node,stack)
        self:expr(place.index,opposite)
        self:instruction("DUP."..opposite,node);self:instruction("PUSH."..stack.." "..baseType.length,node);self:instruction("LTU."..opposite,node)
        local valid=self:label(node);self:instruction("JNZ."..opposite.." "..valid,node);self:instruction("ABORT 2",node);self:place(valid,node)
        self:instruction("IDX."..stack.." "..item.stride,node);return 0
    elseif place.kind=="SliceIndex" then
        local item=layout(place.type)
        self:expr(place.view,stack);self:instruction("MOVE."..stack,node)
        self:expr(place.index,stack);self:instruction("DUP."..stack,node);self:instruction("LTU."..stack,node)
        local valid=self:label(node);self:instruction("JNZ."..stack.." "..valid,node);self:instruction("ABORT 2",node);self:place(valid,node)
        self:instruction("MOVE."..stack,node);self:instruction("IDX."..stack.." "..align(item.size,item.align),node);return 0
    elseif place.kind=="PtrIndex" then
        local item=layout(place.type);self:expr(place.view,stack);self:expr(place.index,opposite);self:instruction("IDX."..stack.." "..align(item.size,item.align),node);return 0
    end
    unsupported("Ir."..tostring(place.kind).." place")
end

function Function:address(place,node,stack)
    stack=stack or "A"
    local offset=self:placeBase(place,node,stack)
    if offset~=0 then self:instruction("PUSH."..other(stack).." 1",node);self:instruction("IDX."..stack.." "..offset,node) end
end

memoryWidth=function(ty)
    if ty==S.bool or ty==S.u8 then return "8" end
    if ty==S.u16 then return "16" end
    if ty==S.u32 then return "32" end
    if ty==S.i32 then return "32S" end
    if ty==S.u64 or ty==S.i64 or ty==S.f64 or ty:isRef() or ty:isPtr() then return "64" end
end

function Function:loadPlace(place,node,stack)
    stack=stack or "A"
    if place.kind=="Local" then
        local slot=self:storageSlot(place.storage)
        if slot.block then self:blockLoad(slot,0,slot.type,node,stack);return end
        if not slot.address then self:instruction("CGET."..stack.." "..self:depth(slot),node);return end
    end
    local ty=self:placeType(place)
    if ty:isRecord() then for _,field in ipairs(ty.fields) do self:loadPlace(S.Ir.Project(place,S.Ir.Field(field.name)),node,stack) end;return end
    if ty:isArray() then for index=0,ty.length-1 do self:loadPlace(S.Ir.Index(place,S.Ir.Const(S.u32,S.Ir.UInt(index)),ty.element),node,stack) end;return end
    if ty:isSlice() or ty:isView() then
        local offset=self:placeBase(place,node,stack);self:instruction(".loadkind addr",node);self:instruction("LD64."..stack.." "..offset,node)
        offset=self:placeBase(place,node,stack)
        if ty:isView() then self:instruction(".loadkind addr",node) end
        self:instruction((ty:isView() and "LD64." or "LD32.")..stack.." "..(offset+8),node);return
    end
    local width=memoryWidth(ty);if not width then unsupported("read of "..S.display(ty)) end
    local offset=self:placeBase(place,node,stack)
    if ty==S.f64 then self:instruction(".loadkind float",node) elseif ty:isRef() or ty:isPtr() then self:instruction(".loadkind addr",node) end
    self:instruction("LD"..width.."."..stack.." "..offset,node)
end

function Function:storePlace(place,ty,node,stack)
    stack=stack or "A"
    local address=other(stack)
    if place.kind=="Local" then local slot=self:storageSlot(place.storage);if slot.block then self:blockStore(slot,0,ty,node,stack);return end end
    if ty:isRecord() then for index=#ty.fields,1,-1 do local field=ty.fields[index];self:storePlace(S.Ir.Project(place,S.Ir.Field(field.name)),field.type,node,stack) end;return end
    if ty:isArray() then for index=ty.length-1,0,-1 do self:storePlace(S.Ir.Index(place,S.Ir.Const(S.u32,S.Ir.UInt(index)),ty.element),ty.element,node,stack) end;return end
    if ty:isSlice() or ty:isView() then
        local offset=self:placeBase(place,node,address);self:instruction((ty:isView() and "ST64." or "ST32.")..address.." "..(offset+8),node)
        offset=self:placeBase(place,node,address);self:instruction("ST64."..address.." "..offset,node);return
    end
    local width=memoryWidth(ty);if not width then unsupported("store of "..S.display(ty)) end
    local offset=self:placeBase(place,node,address)
    self:instruction("ST"..width:gsub("S$","").."."..address.." "..offset,node)
end

function Function:normalize(ty, node, stack)
    stack = stack or "A"
    local op = ty == S.u8 and "ZX8" or ty == S.u16 and "ZX16"
        or ty == S.u32 and "ZX32" or ty == S.i32 and "SX32"
    if op then self:instruction(op .. "." .. stack, node) end
end

function Function:zero(ty,node)
    if ty:isRef() or ty:isPtr() then self:instruction("GADDR.A 0",node);return end
    self:instruction("PUSH.A 0",node)
    if ty==S.f64 then self:instruction("I2FU.A",node) end
end

-- Append the ordered value to stack, preserving both existing live prefixes.
function Function:expr(expr, stack)
    stack = stack or "A"
    local kind = expr.kind
    if kind == "Const" then
        if expr.type == S.unit then return end
        if expr.type:isInteger() then
            self:instruction("PUSH." .. stack .. " " .. intLiteral(expr.literal), expr)
        elseif expr.type == S.bool then
            self:instruction("PUSH." .. stack .. " " .. (expr.literal.value and "1" or "0"), expr)
        elseif expr.type == S.f64 then
            local bits = floatLiteral(expr.literal)
            local offset = self.constants.floats[bits]
            if offset == nil then D.bug("lower-constant", "f64 constant is absent from the module pool") end
            self:instruction(".loadkind float", expr)
            self:instruction("GLD64." .. stack .. " " .. offset, expr)
        elseif expr.type==S.unit then
            -- Unit has no runtime cell.
        elseif expr.type:isSlice() and expr.literal.kind=="Str" then
            local offset=self.constants.strings[expr.literal.bytes];if offset==nil then D.bug("lower-constant","slice constant is absent from the module pool") end
            self:instruction("GADDR."..stack.." "..offset,expr);self:instruction("PUSH."..stack.." "..#expr.literal.bytes,expr)
        else
            unsupported("Ir.Const " .. S.display(expr.type))
        end
        return
    end
    if kind=="Ref" then
        if expr.type~=S.unit then
            local slot=self.valueSlots[expr.value.id];if not slot then D.bug("lower-value","Function "..self.fn.id.." has no ABC slot for value "..tostring(expr.value.id)) end
            if slot.block then self:blockLoad(slot,0,expr.type,expr,stack) elseif slot.cells then for _,cell in ipairs(slot.cells) do self:instruction("CGET."..stack.." "..self:depth(cell),expr) end else self:instruction("CGET."..stack.." "..self:depth(slot),expr) end
        end
        return
    end
    if kind=="Addr" then self:address(expr.place,expr,stack);return end
    if kind=="Null" then self:instruction(".loadkind addr",expr);self:instruction("GLD64."..stack.." 0",expr);return end
    if kind=="Make" and (expr.type:isSlice() or expr.type:isRecord() or expr.type:isArray()) then for _,field in ipairs(expr.fields) do self:expr(field,stack) end;return end
    if kind=="SliceLength" then
        self:expr(expr.view,stack);self:instruction("MOVE."..stack,expr);self:instruction("DROP."..stack,expr);self:instruction("MOVE."..other(stack),expr);return
    end
    if kind=="Is" then unsupported("dynamic type tests") end
    if kind == "Un" then
        if expr.operand.type==S.any then unsupported("dynamic unary execution") end
        self:expr(expr.operand,stack)
        local op = expr.op.kind
        if op == "Not" then self:instruction("LNOT."..stack, expr)
        elseif op == "Neg" then self:instruction((expr.type == S.f64 and "FNEG." or "NEG.")..stack, expr)
        elseif op == "BitNot" then self:instruction("NOT."..stack, expr)
        else D.bug("lower-op", "Unknown unary operation " .. tostring(op)) end
        if expr.type:isInteger() then self:normalize(expr.type, expr,stack) end
        return
    end
    if kind == "Get" then
        local aggregate=expr.aggregate
        if aggregate.kind=="Ref" and self.aggregates[aggregate.value.id] then aggregate=self.aggregates[aggregate.value.id] end
        if aggregate.kind=="Make" then for index,field in ipairs(aggregate.type.fields) do if field.name==expr.field.name then return self:expr(aggregate.fields[index],stack) end end end
        if aggregate.kind=="Ref" then
            local holder=self.valueSlots[aggregate.value.id]
            if holder and holder.cells then
                local first=1
                for _,field in ipairs(aggregate.type.fields) do local parts=valueComponents(field.type);if field.name==expr.field.name then for index=first,first+#parts-1 do self:instruction("CGET."..stack.." "..self:depth(holder.cells[index]),expr) end;return end;first=first+#parts end
            end
        end
        unsupported("escaping or unknown Ir.Get aggregate")
    end
    if kind == "Bin" then return self:binary(expr,stack) end
    if kind == "Convert" then
        if expr.operand.type==S.any or expr.type==S.any then unsupported("dynamic conversions") end
        self:expr(expr.operand,stack)
        self:convert(expr.operand.type, expr.type, expr,stack)
        return
    end
    unsupported("Ir." .. tostring(kind))
end

function Function:binary(expr, stack)
    stack = stack or "A"
    local op, ty = expr.op.kind, expr.left.type
    if ty==S.any then unsupported("dynamic binary execution") end
    -- Evaluation stays left-to-right even for > and >=. Swapping which
    -- operand is primary is a placement decision, not an evaluation reorder.
    self:expr(expr.left,stack)
    self:expr(expr.right,other(stack))
    local reverse = op == "Gt" or op == "Ge"
    local selected = reverse and other(stack) or stack
    local signed = ty:isSigned()
    local operations
    if ty == S.f64 then
        operations={Add="FADD",Sub="FSUB",Mul="FMUL",Div="FDIV",
            Eq="FEQ",Ne="FEQ",Lt="FLT",Le="FLE",Gt="FLT",Ge="FLE"}
    else
        operations={Add="ADD",Sub="SUB",Mul="MUL",
            Div=signed and "DIVS" or "DIVU",Rem=signed and "REMS" or "REMU",
            Pow=expr.right.type:isSigned() and "POWS" or "POW",
            BitAnd="AND",BitOr="OR",BitXor="XOR",Shl="SHL",Shr=signed and "SAR" or "SHR",
            Eq="EQ",Ne="NE",Lt=signed and "LT" or "LTU",Le=signed and "LE" or "LEU",
            Gt=signed and "LT" or "LTU",Ge=signed and "LE" or "LEU"}
    end
    local instruction=operations[op]
    if not instruction then D.bug("lower-op","Unsupported binary operation "..tostring(op)) end
    self:instruction(instruction.."."..selected,expr)
    if ty==S.f64 and op=="Ne" then self:instruction("LNOT."..selected,expr) end
    if reverse then self:instruction("MOVE."..selected,expr) end
    if expr.type:isInteger() then self:normalize(expr.type,expr,stack) end
end

function Function:convert(source, target, node, stack)
    stack = stack or "A"
    if source == target then return end
    local function emit(op) self:instruction(op.."."..stack,node) end
    if source == S.f64 then
        emit(target:isSigned() and "F2IS" or "F2IU")
        local check = target == S.u8 and "CHKU8" or target == S.u16 and "CHKU16"
            or target == S.u32 and "CHKU32" or target == S.i32 and "CHKI32"
        if check then emit(check) end
        self:normalize(target,node,stack)
        return
    end
    if target == S.f64 then
        emit(source:isSigned() and "I2FS" or "I2FU")
        return
    end
    local sw, tw = S.widthOf(source), S.widthOf(target)
    if not sw or not tw then D.bug("lower-convert", "Non-numeric conversion reached ABC lowering") end
    if sw == tw then
        if source:isSigned() ~= target:isSigned() and sw == 64 then emit("CHKNN") end
        self:normalize(target,node,stack)
        return
    end
    if source:isSigned() == target:isSigned() and sw < tw then return end
    if source:isSigned() ~= target:isSigned() then emit("CHKNN") end
    local check = target == S.u8 and "CHKU8" or target == S.u16 and "CHKU16"
        or target == S.u32 and "CHKU32" or target == S.i32 and "CHKI32"
    if check then emit(check) end
    self:normalize(target,node,stack)
end

function Function:storeValue(value,ty,node,stack)
    stack=stack or "A"
    if ty==S.unit then return end
    local slot=self.valueSlots[value.id];if not slot then D.bug("lower-value","No ABC slot for value "..tostring(value.id)) end
    if slot.block then self:blockStore(slot,0,ty,node,stack) elseif slot.cells then for index=#slot.cells,1,-1 do self:instruction("CSET."..stack.." "..self:depth(slot.cells[index]),node) end else self:instruction("CSET."..stack.." "..self:depth(slot),node) end
end

function Function:placeLoad(place,node,stack) return self:loadPlace(place,node,stack) end

function Function:placeStore(place,ty,node,stack)
    stack=stack or "A"
    if ty==S.unit then return end
    if place.kind=="Local" then local slot=self:storageSlot(place.storage);if not slot.block and not slot.address then self:instruction("CSET."..stack.." "..self:depth(slot),node);return end end
    self:storePlace(place,ty,node,stack)
end

function Function:arguments(arguments, node, stack)
    stack=stack or "A"
    local cells = 0
    for _,argument in ipairs(arguments) do
        if argument.kind=="ValueArg" then self:expr(argument.value,stack);local kinds=cellKinds(argument.value.type);if kinds==false then unsupported("argument of type "..S.display(argument.value.type)) end;cells=cells+#kinds
        elseif argument.kind=="BorrowArg" then self:address(argument.place,argument,stack);cells=cells+1
        else unsupported("argument "..tostring(argument.kind)) end
    end
    return cells
end

function Function:call(stmt, selected, stack)
    stack=stack or "A"
    selected=selected or stmt.target
    local target = self.definitions[selected]
    local arguments = self:arguments(stmt.arguments,stmt,stack)
    if target.foreign then self:instruction("FCALL."..stack.." "..selected,stmt)
    else self:instruction("CALL."..stack.." "..selected.." "..arguments,stmt) end
    for index = #stmt.results, 1, -1 do
        self:storeValue(stmt.results[index],target.results[index],stmt,stack)
    end
end

function Function:indirect(stmt,stack)
    stack=stack or "A"
    if stmt.callable.kind~="Ref" then unsupported("non-reference Ir.Indirect callable") end
    local holder=self.valueSlots[stmt.callable.value.id]
    if not holder or not holder.cells or #holder.cells~=2 then D.bug("lower-callable","Indirect callable has no code/environment pair") end
    self:instruction("CGET."..other(stack).." "..self:depth(holder.cells[1]),stmt)
    self:instruction("CGET."..stack.." "..self:depth(holder.cells[2]),stmt)
    local arguments=1+self:arguments(stmt.arguments,stmt,stack)
    local info=self.indirectInfo[stmt];if not info then D.bug("lower-callable","Indirect call has no site signature") end
    self:instruction("CALLI."..stack.." "..arguments.." "..info.signature,stmt)
    local results=stmt.callable.type.visible.results
    for index=#stmt.results,1,-1 do self:storeValue(stmt.results[index],results[index],stmt,stack) end
end

-- Ir is already in ANF: a call's continuation is the remaining statement suffix.
-- A transfer is tail exactly when that suffix is the function's existing return
-- continuation. This rule never asks whether the target is recursive.
local function continuation(list, index)
    return { list = list, index = index }
end

local function isReturnContinuation(call, k)
    if k.index ~= #k.list then return false end
    local ret = k.list[k.index]
    if not ret or ret.kind ~= "Return" or #call.results ~= #ret.values then return false end
    for index, value in ipairs(call.results) do
        local expr = ret.values[index]
        if expr.kind ~= "Ref" or expr.value.id ~= value.id then return false end
    end
    return true
end

function Function:tailCall(stmt, selected, stack)
    stack=stack or "A"
    selected=selected or stmt.target
    local arguments = self:arguments(stmt.arguments,stmt,stack)
    self:instruction("TCALL."..stack.." "..selected.." "..(self.inputCells+#self.locals+self.blockCells)
        .." "..arguments,stmt)
end

function Function:statements(list)
    local index = 1
    while index <= #list do
        local stmt = list[index]
        local kind = stmt.kind
        if kind=="Dynamic" then
            unsupported("dynamic operations")
        elseif kind=="Indirect" and stmt.callable.type==S.any then
            unsupported("dynamic calls")
        elseif kind == "Indirect" and self.indirectInfo[stmt] then
            self:indirect(stmt);index=index+1
        elseif kind == "Call" or kind == "Indirect" then
            local selected=stmt.target
            if kind=="Indirect" then
                local view=stmt.callable.kind=="Ref" and self.views[stmt.callable.value.id] or nil
                if not view then unsupported("escaping or unknown owned Ir.Indirect callable") end
                selected=view.entry
            end
            local k = continuation(list, index + 1)
            local tailSafe=true;for _,argument in ipairs(stmt.arguments) do
                if argument.kind=="BorrowArg" or (argument.kind=="ValueArg" and (argument.value.type:isRef() or argument.value.type:isSlice())) then tailSafe=false end
            end
            if tailSafe and not self.definitions[selected].foreign and isReturnContinuation(stmt,k) then
                self:tailCall(stmt,selected)
                index = index + 2
            else
                self:call(stmt,selected)
                index = index + 1
            end
        elseif kind == "View" then
            if stmt.type==S.any then unsupported("dynamic callable values") end
            if stmt.type:isView() and self.viewInfo[stmt] then
                local info=self.viewInfo[stmt]
                if info.environment then
                    local base=S.Ir.Local(stmt.adapter)
                    for slotIndex,slot in ipairs(stmt.slots) do
                        local field=info.fields[slotIndex]
                        if slot.kind=="ValueArg" then self:expr(slot.value) else self:address(slot.place,slot) end
                        self:placeStore(S.Ir.Project(base,S.Ir.Field(field.name)),field.type,stmt)
                    end
                end
                self:instruction(".loadkind addr",stmt);self:instruction("GLD64.A "..info.codeOffset,stmt)
                if info.environment then self:address(S.Ir.Local(stmt.adapter),stmt) else self:instruction(".loadkind addr",stmt);self:instruction("GLD64.A 0",stmt) end
                self:storeValue(stmt.value,stmt.type,stmt)
            end
            index = index + 1
        elseif kind == "Let" then
            self:expr(stmt.expr)
            self:storeValue(stmt.value, stmt.type, stmt)
            index = index + 1
        elseif kind == "Var" then
            if stmt.initial then
                if stmt.initial.kind=="Make" and stmt.type:isRecord() then
                    local base=S.Ir.Local(stmt.storage)
                    for fieldIndex,field in ipairs(stmt.type.fields) do self:expr(stmt.initial.fields[fieldIndex]);self:placeStore(S.Ir.Project(base,S.Ir.Field(field.name)),field.type,stmt) end
                elseif stmt.initial.kind=="Make" and stmt.type:isArray() then
                    local base=S.Ir.Local(stmt.storage)
                    for elementIndex,item in ipairs(stmt.initial.fields) do self:expr(item);self:placeStore(S.Ir.Index(base,S.Ir.Const(S.u32,S.Ir.UInt(elementIndex-1)),stmt.type.element),stmt.type.element,stmt) end
                else self:expr(stmt.initial);self:placeStore(S.Ir.Local(stmt.storage),stmt.type,stmt) end
            end
            index = index + 1
        elseif kind == "Read" then
            if stmt.type ~= S.unit then
                self:placeLoad(stmt.place, stmt)
                self:storeValue(stmt.value, stmt.type, stmt)
            end
            index = index + 1
        elseif kind == "Store" then
            self:expr(stmt.value)
            self:placeStore(stmt.place, stmt.value.type, stmt)
            index = index + 1
        elseif kind=="ConstructVariant" then
            local slot=self:valueBlock(stmt.value);local item=slot.layout
            self:instruction("PUSH.A "..item.tags[stmt.tag],stmt);self:blockStore(slot,0,S.u32,stmt)
            if stmt.payload then self:expr(stmt.payload);self:blockStore(slot,item.payloadOffset,S.caseOf(stmt.type,stmt.tag),stmt) end
            index=index+1
        elseif kind=="VariantMatches" then
            local slot=self:valueBlock(stmt.variant);local item=slot.layout
            self:blockLoad(slot,0,S.u32,stmt);self:instruction("PUSH.B "..item.tags[stmt.tag],stmt);self:instruction("EQ.A",stmt)
            self:storeValue(stmt.value,S.bool,stmt);index=index+1
        elseif kind=="VariantPayload" then
            local slot=self:valueBlock(stmt.variant);local item=slot.layout;local ty=S.caseOf(stmt.sum,stmt.tag)
            if ty~=S.unit then self:blockLoad(slot,item.payloadOffset,ty,stmt);self:storeValue(stmt.value,ty,stmt) end
            index=index+1
        elseif kind=="Switch" then
            local slot=self:valueBlock(stmt.variant);local item=slot.layout;local done=self:label(stmt);local branches={}
            local fallback
            for _,case in ipairs(stmt.cases) do if case.fallback then fallback=case else local target=self:label(case);branches[#branches+1]={case=case,target=target};self:blockLoad(slot,0,S.u32,stmt);self:instruction("PUSH.B "..item.tags[case.tag],stmt);self:instruction("EQ.A",stmt);self:instruction("JNZ.A "..target,stmt) end end
            if not fallback then D.bug("lower-switch","Switch has no fallback") end
            self:statements(fallback.body);if Check.falls(fallback.body) then self:instruction("JMP "..done,stmt) end
            local falls=Check.falls(fallback.body)
            for _,branch in ipairs(branches) do self:place(branch.target,branch.case);self:statements(branch.case.body);if Check.falls(branch.case.body) then falls=true;self:instruction("JMP "..done,stmt) end end
            if falls then self:place(done,stmt) end
            index=index+1
        elseif kind == "If" then
            local no, done = self:label(stmt), self:label(stmt)
            self:expr(stmt.test)
            self:instruction("JZ.A " .. no, stmt)
            self:statements(stmt.yes)
            local yesFalls, noFalls = Check.falls(stmt.yes), Check.falls(stmt.no)
            if yesFalls then self:instruction("JMP " .. done, stmt) end
            self:place(no, stmt)
            self:statements(stmt.no)
            if yesFalls or noFalls then self:place(done, stmt) end
            index = index + 1
        elseif kind == "Loop" then
            local start = self:label(stmt)
            self.loops[#self.loops + 1] = start
            self:place(start, stmt)
            self:statements(stmt.body)
            if Check.falls(stmt.body) then self:instruction("JMP " .. start, stmt) end
            self.loops[#self.loops] = nil
            index = index + 1
        elseif kind == "Next" then
            local target = self.loops[#self.loops]
            if not target then D.bug("lower-next", "Next reached ABC lowering outside a loop") end
            self:instruction("JMP " .. target, stmt)
            index = index + 1
        elseif kind == "Trap" then
            local reason = REASONS[stmt.reason]
            if not reason then D.reject("abort-reason", "Unknown language abort reason " .. tostring(stmt.reason)) end
            local ok = self:label(stmt)
            self:expr(stmt.failure)
            self:instruction("JZ.A " .. ok, stmt)
            self:instruction("ABORT " .. reason, stmt)
            self:place(ok, stmt)
            index = index + 1
        elseif kind == "Return" then
            for _, value in ipairs(stmt.values) do self:expr(value) end
            self:instruction("RET.A "..(self.inputCells+#self.locals+self.blockCells).." "..countCells(self.fn.results),stmt)
            index = index + 1
        else
            unsupported("Ir." .. tostring(kind))
        end
    end
end

function Function:lower()
    local argumentKinds, resultKinds = {}, {}
    for _,input in ipairs(self.fn.inputs) do
        if input.kind=="InPlace" then argumentKinds[#argumentKinds+1]="a" else local kinds=cellKinds(input.type);if kinds==false then unsupported("function input of type "..S.display(input.type)) end;for _,kind in ipairs(kinds) do argumentKinds[#argumentKinds+1]=kind end end
    end
    for _,ty in ipairs(self.fn.results) do local kinds=cellKinds(ty);if kinds==false then unsupported("function result of type "..S.display(ty)) end;for _,kind in ipairs(kinds) do resultKinds[#resultKinds+1]=kind end end
    local header = ".function " .. self.fn.id .. " " .. #argumentKinds .. " " .. #resultKinds
    if self.profile ~= "integer" then
        header = header .. " " .. (#argumentKinds > 0 and table.concat(argumentKinds) or "-")
            .. " " .. (#resultKinds > 0 and table.concat(resultKinds) or "-")
    end
    self:emit(header, self.fn)
    for _,slot in ipairs(self.locals) do
        self:zero(slot.type,self.fn)
        self:instruction("CPUSH.A",self.fn)
    end
    for _,slot in ipairs(self.blocks) do self:instruction("CALLOC "..slot.layout.size,self.fn) end
    for _,slot in ipairs(self.blocks) do if slot.initialParameters then for _,parameter in ipairs(slot.initialParameters) do self:instruction("CGET.A "..self:depth(parameter),self.fn) end;self:blockStore(slot,0,slot.type,self.fn) end end
    self:statements(self.fn.body)
    return self.lines, self.lineMap
end

function M.lower(functions, options)
    options = options or {}
    if options.profile ~= "slet" and options.profile ~= "let" then
        D.reject("source-profile", "ABC lowering requires profile `let` or `slet`")
    end
    if options.profile == "let" then
        D.reject("dynamic-lowering", "Dynamic ABC lowering is unavailable; Let parsing, typechecking and IR construction remain supported. Use SLet for executable ABC.")
    end
    Check.program(functions, options.modules, options.foreigns)

    local definitions,usesFloat,usesMemory,usesAddress,usesCallable={},false,false,false,false
    local floatConstants,floatData,floatCount={},{},0
    local stringConstants,stringOrder,stringData={},{},{}
    local viewInfo,indirectInfo,adapters,signatureNames,signatureLines={},{},{},{},{}
    local function inputKinds(input) if input.kind=="InPlace" then return {"a"} end;local kinds=cellKinds(input.type);if kinds==false then unsupported("callable input of type "..S.display(input.type)) end;return kinds end
    local function signatureFor(sig)
        local key=S.encode(sig);if signatureNames[key] then return signatureNames[key] end
        local name="_let_sig"..(#signatureLines+1);signatureNames[key]=name;local arguments={"a"};for _,input in ipairs(sig.inputs) do for _,kind in ipairs(inputKinds(input)) do arguments[#arguments+1]=kind end end
        local results={};for _,ty in ipairs(sig.results) do local kinds=cellKinds(ty);if kinds==false then unsupported("callable result of type "..S.display(ty)) end;for _,kind in ipairs(kinds) do results[#results+1]=kind end end
        signatureLines[#signatureLines+1]=".signature "..name.." "..#arguments.." "..#results.." "..table.concat(arguments).." "..(#results>0 and table.concat(results) or "-");return name
    end
    local function inspectType(ty)
        if ty==S.any then D.reject("slet-forbidden","SLet cannot lower any values") end
        if ty:isView() or ty:isOwned() then return end
        if ty:isSlice() then usesMemory=true;usesAddress=true;return end
        if ty:isRecord() or ty:isArray() or ty:isTaggedType() then return end
        if ty:isRef() or ty:isPtr() then usesMemory=true;usesAddress=true end
        local kind=requireScalar(ty,"scalar lowering")
        if kind=="f" then usesFloat=true end
    end
    local function retainFloat(value)
        local bits = floatLiteral(value)
        if floatConstants[bits] == nil then
            floatConstants[bits] = floatCount * 8
            local hex, bytes = bits:sub(3), {}
            for at = #hex - 1, 1, -2 do bytes[#bytes + 1] = hex:sub(at, at + 1) end
            floatData[#floatData + 1] = table.concat(bytes)
            floatCount = floatCount + 1
        end
    end
    local function retainString(bytes)
        if stringConstants[bytes]==nil then stringConstants[bytes]=false;stringOrder[#stringOrder+1]=bytes end
    end
    for _,foreign in ipairs(options.foreigns or {}) do if definitions[foreign.target] then D.reject("lower-duplicate","Duplicate foreign "..foreign.target) end;definitions[foreign.target]={id=foreign.target,inputs=foreign.inputs,results=foreign.results,foreign=true} end
    for _,fn in ipairs(functions) do if definitions[fn.id] then D.bug("lower-duplicate","Duplicate function "..fn.id) end;definitions[fn.id]=fn end
    local adapterSerial=0
    for _, fn in ipairs(functions) do
        local localViews={}
        local references,directUses={},{}
        Walk.walk(fn,{enter=function(node) if node.kind=="Ref" then references[node.value.id]=(references[node.value.id] or 0)+1 elseif node.kind=="Indirect" and node.callable.kind=="Ref" then directUses[node.callable.value.id]=(directUses[node.callable.value.id] or 0)+1 end end})
        Walk.walk(fn,{enter=function(node)
            if S.Ir.View:isclassof(node) and node.type:isView() and (#node.slots>0 or (references[node.value.id] or 0)>(directUses[node.value.id] or 0)) then
                adapterSerial=adapterSerial+1;local name="_let_adapter_"..adapterSerial;while definitions[name] do adapterSerial=adapterSerial+1;name="_let_adapter_"..adapterSerial end
                local fields,ordered={},{ };for index,slot in ipairs(node.slots) do local input=definitions[node.entry].inputs[index];local field={name=string.format("_%04d",index),type=slot.kind=="BorrowArg" and S.ref(input.type) or input.type};fields[field.name]=field.type;ordered[index]=field end
                local environment=#node.slots>0 and S.record(fields) or nil;local info={name=name,statement=node,target=definitions[node.entry],environment=environment,fields=ordered};viewInfo[node]=info;localViews[node.value.id]=info;adapters[#adapters+1]=info;usesCallable=true;usesAddress=true;usesMemory=true
            elseif S.Ir.View:isclassof(node) and node.type:isView() then localViews[node.value.id]=false
            elseif S.Ir.Indirect:isclassof(node) and node.callable.type:isView() then
                local known=node.callable.kind=="Ref" and localViews[node.callable.value.id]
                if known~=false then indirectInfo[node]={signature=signatureFor(node.callable.type.visible)};usesCallable=true end
            end
        end})
        Walk.walk(fn, {enter = function(node)
            if S.Ty.V:isclassof(node) then inspectType(node); return false end
            if node.kind=="Const" and node.type==S.f64 then retainFloat(node.literal) end
            if node.kind=="Const" and node.type:isSlice() and node.literal.kind=="Str" then retainString(node.literal.bytes);usesAddress=true;usesMemory=true end
            if node.kind=="InPlace" or node.kind=="PlaceParam" or node.kind=="Addr" or node.kind=="BorrowArg" or ((node.kind=="Read" or node.kind=="Store") and node.place.kind~="Local") then usesMemory=true end
            if node.kind=="Addr" or node.kind=="BorrowArg" then usesAddress=true end
            if (node.kind=="Var" and not cellKind(node.type)) or node.kind=="ConstructVariant" then usesMemory=true end
        end})
    end
    local dataSize=usesAddress and 8 or 0
    for _,info in ipairs(adapters) do info.codeOffset=dataSize;dataSize=dataSize+8 end
    local bias=dataSize
    if bias~=0 then for bits,offset in pairs(floatConstants) do floatConstants[bits]=offset+bias end end
    local stringOffset=floatCount*8
    for _,bytes in ipairs(stringOrder) do
        stringConstants[bytes]=stringOffset+bias;local hex={}
        if #bytes==0 then hex[1]="00" else for i=1,#bytes do hex[#hex+1]=string.format("%02x",bytes:byte(i)) end end
        stringData[#stringData+1]=table.concat(hex);stringOffset=stringOffset+math.max(1,#bytes)
    end
    local profile=#(options.foreigns or {})>0 and "foreign" or usesCallable and "callables" or (usesFloat or usesMemory) and "memory" or "integer"
    local constants={floats=floatConstants,strings=stringConstants}
    local metadata={viewInfo=viewInfo,indirectInfo=indirectInfo}
    local loweredFunctions={}
    for index,fn in ipairs(functions) do loweredFunctions[index]=Function.new(fn,definitions,profile,constants,metadata) end
    local loweredOutput={}
    for index,lowered in ipairs(loweredFunctions) do local fnLines,fnMap=lowered:lower();loweredOutput[index]={lines=fnLines,map=fnMap} end
    local lines, lineMap = {}, {}
    local function append(text, node)
        lines[#lines + 1] = text
        lineMap[#lines] = node or false
    end
    if profile~="integer" then append(".profile "..profile) end
    for _,foreign in ipairs(options.foreigns or {}) do
        local arguments,results={},{}
        for _,input in ipairs(foreign.inputs) do if input.kind~="InValue" then unsupported("foreign borrowed input") end;for _,kind in ipairs(cellKinds(input.type)) do arguments[#arguments+1]=kind end end
        for _,result in ipairs(foreign.results) do for _,kind in ipairs(cellKinds(result)) do results[#results+1]=kind end end
        append(".extern "..foreign.target.." "..(#arguments>0 and table.concat(arguments) or "-").." "..(#results>0 and table.concat(results) or "-"))
    end
    if dataSize>0 then append(".datazero "..dataSize) end
    local rodata=table.concat(floatData)..table.concat(stringData);if #rodata>0 then append(".rodata "..rodata) end
    for _,line in ipairs(signatureLines) do append(line) end
    for _,info in ipairs(adapters) do append(".codeaddr "..info.codeOffset.." "..info.name) end
    for _, output in ipairs(loweredOutput) do
        for index,line in ipairs(output.lines) do append(line,output.map[index]) end
    end
    for _,info in ipairs(adapters) do
        local target,statement=info.target,info.statement;local argumentKinds={"a"};local adapterCells=1
        for index=#statement.slots+1,#target.inputs do local kinds=inputKinds(target.inputs[index]);for _,kind in ipairs(kinds) do argumentKinds[#argumentKinds+1]=kind;adapterCells=adapterCells+1 end end
        local resultKinds={};for _,ty in ipairs(target.results) do for _,kind in ipairs(cellKinds(ty)) do resultKinds[#resultKinds+1]=kind end end
        append(".function "..info.name.." "..adapterCells.." "..#resultKinds.." "..table.concat(argumentKinds).." "..(#resultKinds>0 and table.concat(resultKinds) or "-"),statement)
        if info.environment then
            local envLayout=layout(info.environment)
            for index,input in ipairs(target.inputs) do if index>#statement.slots then break end;local field=info.fields[index];local offset=envLayout.fields[field.name].offset;local ty=field.type
                if ty:isSlice() then
                    append("  CGET.A 0",statement);append("  .loadkind addr",statement);append("  LD64.A "..offset,statement)
                    append("  CGET.A 0",statement);append("  LD32.A "..(offset+8),statement)
                elseif ty:isView() then
                    append("  CGET.A 0",statement);append("  .loadkind addr",statement);append("  LD64.A "..offset,statement)
                    append("  CGET.A 0",statement);append("  .loadkind addr",statement);append("  LD64.A "..(offset+8),statement)
                else
                    local width=memoryWidth(ty);if not width then unsupported("captured adapter load of "..S.display(ty)) end
                    append("  CGET.A 0",statement);if ty==S.f64 then append("  .loadkind float",statement) elseif ty:isRef() or ty:isPtr() then append("  .loadkind addr",statement) end
                    append("  LD"..width..".A "..offset,statement)
                end
            end
        end
        local parameter=1
        for index=#statement.slots+1,#target.inputs do for _ in ipairs(inputKinds(target.inputs[index])) do append("  CGET.A "..parameter,statement);parameter=parameter+1 end end
        local targetCells=0;for _,input in ipairs(target.inputs) do targetCells=targetCells+#inputKinds(input) end
        append("  TCALL.A "..target.id.." "..adapterCells.." "..targetCells,statement)
    end
    for _, name in ipairs(options.exports or {}) do
        if not identifier(name) or not definitions[name] then
            D.reject("lower-export", "Unknown or invalid export " .. tostring(name))
        end
        append(".export " .. name)
    end
    return {
        phase = "lowered",
        profile = profile,
        assembly = table.concat(lines, "\n") .. "\n",
        lineMap = lineMap,
        functions = functions,
    }
end

return M
