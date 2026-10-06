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
local memoryWidth
local function cellKind(ty)
    if ty == S.unit then return nil end
    if ty:isInteger() or ty == S.bool then return "i" end
    if ty==S.any then return "d" end
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
    return false
end

local function cellKinds(ty)
    local components=valueComponents(ty)
    if components==false then return false end
    local result={}
    for _,component in ipairs(components) do result[#result+1]=cellKind(component) end
    return result
end

local function align(value, boundary) return math.floor((value + boundary - 1) / boundary) * boundary end
local function layout(ty, seen)
    if ty == S.unit then return {size=0,align=1} end
    if ty == S.bool or ty == S.u8 then return {size=1,align=1} end
    if ty == S.u16 then return {size=2,align=2} end
    if ty == S.u32 or ty == S.i32 then return {size=4,align=4} end
    if ty == S.u64 or ty == S.i64 or ty == S.f64 or ty==S.any or ty:isRef() or ty:isPtr() then return {size=8,align=8} end
    if ty:isSlice() then return {size=16,align=8,fields={data={offset=0,type=S.ref(ty.element)},length={offset=8,type=S.u32}}} end
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
    if not floatBits then
        local ffi = require("ffi")
        ffi.cdef("typedef union { double d; uint32_t word[2]; } let_abc_double_bits;")
        floatBits = ffi.new("let_abc_double_bits")
    end
    floatBits.d = value
    return string.format("0x%08x%08x", tonumber(floatBits.word[1]), tonumber(floatBits.word[0]))
end


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
        descriptorOf=metadata.descriptorOf,
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
            local components=valueComponents(param.type);if components==false or #components~=input.count then D.bug("lower-param","Parameter representation disagrees with input") end
            if #components==1 then self.valueSlots[param.binding.id]={parameter=input.base,type=param.type}
            elseif #components>1 then local holder={type=param.type,cells={}};for i,component in ipairs(components) do holder.cells[i]={parameter=input.base+i-1,type=component} end;self.valueSlots[param.binding.id]=holder end
        elseif param.kind=="PlaceParam" then
            if input.count~=1 then D.bug("lower-param","Place parameter is not one address cell") end
            self.storageSlots[param.binding.id]={parameter=input.base,address=true,type=param.type}
        else unsupported("parameter "..param.kind) end
    end


    local function reserve(map,id,ty,place,forceManaged)
        if map[id] then D.bug("lower-slot","IR slot "..tostring(id).." is defined twice") end
        local components=valueComponents(ty)
        if not place and components and #components>1 then
            local holder={type=ty,cells={}};for _,component in ipairs(components) do local slot={index=#self.locals+1,type=component};self.locals[#self.locals+1]=slot;holder.cells[#holder.cells+1]=slot end;map[id]=holder;return
        end
        if place and self.profile=="dynamic" and (forceManaged or self.addressTaken[id]) then
            local slot={index=#self.locals+1,type=ty,cellType=S.ptr(S.unit),address=true,managed=true,descriptor=self.descriptorOf(ty,true)}
            self.locals[#self.locals+1]=slot;map[id]=slot;return
        end
        local kind=cellKind(ty)
        if kind and not (place and self.addressTaken[id]) then local slot={index=#self.locals+1,type=ty};self.locals[#self.locals+1]=slot;map[id]=slot;return end
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
                if stmt.type:isRecord() and stmt.expr.kind=="Make" then self.aggregates[stmt.value.id]=stmt.expr
                else reserve(self.valueSlots, stmt.value.id, stmt.type) end
            elseif kind == "Read" then
                reserve(self.valueSlots, stmt.value.id, stmt.type)
            elseif kind == "Var" then
                reserve(self.storageSlots, stmt.storage.id, stmt.type, true)
            elseif kind == "Call" then
                local target = definitions[stmt.target]
                if not target then D.bug("lower-target", "Unknown call target " .. tostring(stmt.target)) end
                for index, value in ipairs(stmt.results) do
                    reserve(self.valueSlots, value.id, target.results[index])
                end
            elseif kind == "View" then
                local info=self.viewInfo[stmt]
                if (info and stmt.type:isView()) or stmt.type==S.any then reserve(self.valueSlots,stmt.value.id,stmt.type) end
                if info and info.environment then reserve(self.storageSlots,stmt.adapter.id,info.environment,true,true) end
                self.views[stmt.value.id]={entry=stmt.entry,type=stmt.type,statement=stmt,info=info}
            elseif kind == "Indirect" then
                local results;if stmt.callable.type~=S.any then results=stmt.callable.type.visible.results end
                for index,value in ipairs(stmt.results) do reserve(self.valueSlots,value.id,results and results[index] or S.any) end
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
                reserve(self.valueSlots,stmt.value.id,S.caseOf(stmt.sum,stmt.tag))
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

function Function:blockLoad(slot,offset,ty,node)
    local width=memoryWidth and memoryWidth(ty)
    if not width then unsupported("sum payload "..S.display(ty)) end
    self:instruction("FADDR.A "..slot.frameOffset,node)
    if ty==S.f64 then self:instruction(".loadkind float",node) elseif ty==S.any then self:instruction(".loadkind any",node) elseif ty:isRef() or ty:isPtr() then self:instruction(".loadkind addr",node) end
    self:instruction("LD"..width..".A "..offset,node)
end

function Function:blockStore(slot,offset,ty,node)
    local width=memoryWidth and memoryWidth(ty)
    if not width then unsupported("sum payload "..S.display(ty)) end
    self:instruction("MOVE.AB",node);self:instruction("FADDR.A "..slot.frameOffset,node);self:instruction("ST"..width:gsub("S$","").." "..offset,node)
end

function Function:placeType(place)
    if place.kind=="Local" then return self:storageSlot(place.storage).type end
    if place.kind=="Project" then local base=self:placeType(place.base);for _,field in ipairs(base.fields) do if field.name==place.field.name then return field.type end end end
    if place.kind=="Deref" or place.kind=="Index" or place.kind=="SliceIndex" or place.kind=="PtrIndex" then return place.type end
    D.bug("lower-place","Cannot determine type of Ir."..tostring(place.kind))
end

function Function:placeBase(place,node)
    if place.kind=="Local" then
        local slot=self:storageSlot(place.storage)
        if slot.block then self:instruction("FADDR.A "..slot.frameOffset,node);return 0 end
        if slot.address then self:instruction("CGET.A "..self:depth(slot),node);return 0 end
        unsupported("address of non-addressable scalar local")
    elseif place.kind=="Project" then
        local baseType=self:placeType(place.base);local field=layout(baseType).fields[place.field.name]
        if not field then D.bug("lower-field","Unknown projected field "..tostring(place.field.name)) end
        return self:placeBase(place.base,node)+field.offset
    elseif place.kind=="Deref" then
        self:loadPlace(place.base,node);return 0
    elseif place.kind=="Index" then
        local baseType=self:placeType(place.base);local item=layout(baseType)
        self:address(place.base,node)
        self:expr(place.index)
        self:instruction("DUP.A",node);self:instruction("PUSH.B "..baseType.length,node);self:instruction("LTU.A",node)
        local valid=self:label(node);self:instruction("JNZ.A "..valid,node);self:instruction("ABORT 2",node);self:place(valid,node)
        self:instruction("MOVE.AB",node);self:instruction("IDX "..item.stride,node);return 0
    elseif place.kind=="SliceIndex" then
        local item=layout(place.type);self:expr(place.view);self:instruction("MOVE.AB",node);self:expr(place.index);self:instruction("DUP.A",node);self:instruction("LTU.A",node)
        local valid=self:label(node);self:instruction("JNZ.A "..valid,node);self:instruction("ABORT 2",node);self:place(valid,node)
        self:instruction("MOVE.AB",node);self:instruction("IDX "..align(item.size,item.align),node);return 0
    elseif place.kind=="PtrIndex" then
        local item=layout(place.type);self:expr(place.view);self:expr(place.index);self:instruction("MOVE.AB",node);self:instruction("IDX "..align(item.size,item.align),node);return 0
    end
    unsupported("Ir."..tostring(place.kind).." place")
end

function Function:address(place,node)
    local offset=self:placeBase(place,node)
    if offset~=0 then self:instruction("PUSH.B 1",node);self:instruction("IDX "..offset,node) end
end

memoryWidth=function(ty)
    if ty==S.bool or ty==S.u8 then return "8" end
    if ty==S.u16 then return "16" end
    if ty==S.u32 then return "32" end
    if ty==S.i32 then return "32S" end
    if ty==S.u64 or ty==S.i64 or ty==S.f64 or ty==S.any or ty:isRef() or ty:isPtr() then return "64" end
end

function Function:loadPlace(place,node)
    if place.kind=="Local" then local slot=self:storageSlot(place.storage);if not slot.block and not slot.address then self:instruction("CGET.A "..self:depth(slot),node);return end end
    local ty=self:placeType(place)
    if ty:isSlice() then
        local offset=self:placeBase(place,node);self:instruction(".loadkind addr",node);self:instruction("LD64.A "..offset,node)
        offset=self:placeBase(place,node);self:instruction("LD32.A "..(offset+8),node);return
    end
    local width=memoryWidth(ty);if not width then unsupported("read of "..S.display(ty)) end
    local offset=self:placeBase(place,node)
    if ty==S.f64 then self:instruction(".loadkind float",node) elseif ty==S.any then self:instruction(".loadkind any",node) elseif ty:isRef() or ty:isPtr() then self:instruction(".loadkind addr",node) end
    self:instruction("LD"..width..".A "..offset,node)
end

function Function:storePlace(place,ty,node)
    if ty:isSlice() then
        self:instruction("MOVE.AB",node);local offset=self:placeBase(place,node);self:instruction("ST32 "..(offset+8),node)
        self:instruction("MOVE.AB",node);offset=self:placeBase(place,node);self:instruction("ST64 "..offset,node);return
    end
    local width=memoryWidth(ty);if not width then unsupported("store of "..S.display(ty)) end
    self:instruction("MOVE.AB",node);local offset=self:placeBase(place,node);self:instruction("ST"..width:gsub("S$","").." "..offset,node)
end

function Function:normalize(ty, node)
    local op = ty == S.u8 and "ZX8" or ty == S.u16 and "ZX16"
        or ty == S.u32 and "ZX32.A" or ty == S.i32 and "SX32.A"
    if op then self:instruction(op, node) end
end

function Function:zero(ty,node)
    if ty==S.any then self:instruction("ANY_BOX "..self.descriptorOf(S.unit,true),node);return end
    if ty:isRef() or ty:isPtr() then self:instruction("GADDR.A 0",node);return end
    self:instruction("PUSH.A 0",node)
    if ty==S.f64 then self:instruction("I2FU",node) end
end

function Function:expr(expr)
    local kind = expr.kind
    if kind == "Const" then
        if expr.type == S.unit then return end
        if expr.type:isInteger() then
            self:instruction("PUSH.A " .. intLiteral(expr.literal), expr)
        elseif expr.type == S.bool then
            self:instruction("PUSH.A " .. (expr.literal.value and "1" or "0"), expr)
        elseif expr.type == S.f64 then
            local bits = floatLiteral(expr.literal.value)
            local offset = self.constants.floats[bits]
            if offset == nil then D.bug("lower-constant", "f64 constant is absent from the module pool") end
            self:instruction(".loadkind float", expr)
            self:instruction("GLD64 " .. offset, expr)
        elseif expr.type:isSlice() and expr.literal.kind=="Str" then
            local offset=self.constants.strings[expr.literal.bytes];if offset==nil then D.bug("lower-constant","slice constant is absent from the module pool") end
            self:instruction("GADDR.A "..offset,expr);self:instruction("PUSH.A "..#expr.literal.bytes,expr)
        else
            unsupported("Ir.Const " .. S.display(expr.type))
        end
        return
    end
    if kind=="Ref" then
        if expr.type~=S.unit then
            local slot=self.valueSlots[expr.value.id];if not slot then D.bug("lower-value","No ABC slot for value "..tostring(expr.value.id)) end
            if slot.cells then for _,cell in ipairs(slot.cells) do self:instruction("CGET.A "..self:depth(cell),expr) end else self:instruction("CGET.A "..self:depth(slot),expr) end
        end
        return
    end
    if kind=="Addr" then self:address(expr.place,expr);return end
    if kind=="Null" then unsupported("Ir.Null address representation") end
    if kind=="Make" and expr.type:isSlice() then self:expr(expr.fields[1]);self:expr(expr.fields[2]);return end
    if kind=="SliceLength" then
        self:expr(expr.view);self:instruction("MOVE.AB",expr);self:instruction("DROP.A",expr);self:instruction("MOVE.BA",expr);return
    end
    if kind=="Is" then self:expr(expr.operand);self:instruction("ANY_IS "..self.descriptorOf(expr.tested,true),expr);return end
    if kind == "Un" then
        self:expr(expr.operand)
        local op = expr.op.kind
        if op == "Not" then self:instruction(expr.operand.type==S.any and "DLNOT" or "LNOT.A", expr)
        elseif op == "Neg" then self:instruction(expr.operand.type==S.any and "DNEG" or expr.type == S.f64 and "FNEG" or "NEG.A", expr)
        elseif op == "BitNot" then self:instruction(expr.operand.type==S.any and "DNOT" or "NOT.A", expr)
        else D.bug("lower-op", "Unknown unary operation " .. tostring(op)) end
        if expr.type:isInteger() then self:normalize(expr.type, expr) end
        return
    end
    if kind == "Get" then
        local aggregate=expr.aggregate
        if aggregate.kind=="Ref" and self.aggregates[aggregate.value.id] then aggregate=self.aggregates[aggregate.value.id] end
        if aggregate.kind~="Make" then unsupported("escaping or unknown Ir.Get aggregate") end
        for index,field in ipairs(aggregate.type.fields) do if field.name==expr.field.name then return self:expr(aggregate.fields[index]) end end
        D.bug("lower-field","Record projection names no field "..tostring(expr.field.name))
    end
    if kind == "Bin" then return self:binary(expr) end
    if kind == "Convert" then
        if expr.operand.type==S.any then self:expr(expr.operand);self:instruction("ANY_CAST "..self.descriptorOf(expr.type,true),expr);return end
        if expr.type==S.any then
            if valueComponents(expr.operand.type)==false then unsupported("boxing "..S.display(expr.operand.type).." into any") end
            self:expr(expr.operand);self:instruction("ANY_BOX "..self.descriptorOf(expr.operand.type,true),expr);return
        end
        self:expr(expr.operand)
        self:convert(expr.operand.type, expr.type, expr)
        return
    end
    unsupported("Ir." .. tostring(kind))
end

function Function:binary(expr)
    local op, ty = expr.op.kind, expr.left.type
    local reverse = op == "Gt" or op == "Ge"
    if reverse then
        self:expr(expr.right)
        self:expr(expr.left)
    else
        self:expr(expr.left)
        self:expr(expr.right)
    end
    if ty==S.any then
        local dynamic={Add="DADD",Sub="DSUB",Mul="DMUL",Div="DDIV",Rem="DREM",Pow="DPOW",BitAnd="DAND",BitOr="DOR",BitXor="DXOR",Shl="DSHL",Shr="DSHR",Eq="DEQ",Ne="DNE",Lt="DLT",Le="DLE",Gt="DLT",Ge="DLE"}
        local instruction=dynamic[op];if not instruction then D.bug("lower-op","Unsupported dynamic operation "..tostring(op)) end
        self:instruction(instruction,expr);return
    end
    self:instruction("MOVE.AB", expr)
    if ty == S.f64 then
        local float = { Add = "FADD.A", Sub = "FSUB.A", Mul = "FMUL.A", Div = "FDIV.A",
            Eq = "FEQ.A", Ne = "FEQ.A", Lt = "FLT.A", Le = "FLE.A",
            Gt = "FLT.A", Ge = "FLE.A" }
        local instruction = float[op]
        if not instruction then D.bug("lower-op", "Unsupported f64 operation " .. tostring(op)) end
        self:instruction(instruction, expr)
        if op == "Ne" then self:instruction("LNOT.A", expr) end
        return
    end

    local signed = ty:isSigned()
    local instruction = ({
        Add = "ADD.A", Sub = "SUB.A", Mul = "MUL.A",
        Div = signed and "DIVS.A" or "DIVU.A",
        Rem = signed and "REMS.A" or "REMU.A",
        Pow = expr.right.type:isSigned() and "POWS" or "POW",
        BitAnd = "AND.A", BitOr = "OR.A", BitXor = "XOR.A",
        Shl = "SHL.A", Shr = signed and "SAR.A" or "SHR.A",
        Eq = "EQ.A", Ne = "NE.A",
        Lt = signed and "LT.A" or "LTU.A", Le = signed and "LE.A" or "LEU.A",
        Gt = signed and "LT.A" or "LTU.A", Ge = signed and "LE.A" or "LEU.A",
    })[op]
    if not instruction then D.bug("lower-op", "Unknown binary operation " .. tostring(op)) end
    self:instruction(instruction, expr)
    if expr.type:isInteger() then self:normalize(expr.type, expr) end
end

function Function:convert(source, target, node)
    if source == target then return end
    if source == S.f64 then
        self:instruction(target:isSigned() and "F2IS" or "F2IU", node)
        local check = target == S.u8 and "CHKU8" or target == S.u16 and "CHKU16"
            or target == S.u32 and "CHKU32" or target == S.i32 and "CHKI32"
        if check then self:instruction(check, node) end
        self:normalize(target, node)
        return
    end
    if target == S.f64 then
        self:instruction(source:isSigned() and "I2FS" or "I2FU", node)
        return
    end
    local sw, tw = S.widthOf(source), S.widthOf(target)
    if not sw or not tw then D.bug("lower-convert", "Non-numeric conversion reached ABC lowering") end
    if sw == tw then
        if source:isSigned() ~= target:isSigned() and sw == 64 then self:instruction("CHKNN", node) end
        self:normalize(target, node)
        return
    end
    if source:isSigned() == target:isSigned() and sw < tw then return end
    if source:isSigned() ~= target:isSigned() then self:instruction("CHKNN", node) end
    local check = target == S.u8 and "CHKU8" or target == S.u16 and "CHKU16"
        or target == S.u32 and "CHKU32" or target == S.i32 and "CHKI32"
    if check then self:instruction(check, node) end
    self:normalize(target, node)
end

function Function:storeValue(value,ty,node)
    if ty==S.unit then return end
    local slot=self.valueSlots[value.id];if not slot then D.bug("lower-value","No ABC slot for value "..tostring(value.id)) end
    if slot.cells then for index=#slot.cells,1,-1 do self:instruction("CSET.A "..self:depth(slot.cells[index]),node) end
    else self:instruction("CSET.A "..self:depth(slot),node) end
end

function Function:placeLoad(place,node) return self:loadPlace(place,node) end

function Function:placeStore(place,ty,node)
    if ty==S.unit then return end
    if place.kind=="Local" then local slot=self:storageSlot(place.storage);if not slot.block and not slot.address then self:instruction("CSET.A "..self:depth(slot),node);return end end
    self:storePlace(place,ty,node)
end

function Function:arguments(arguments, node)
    local cells = 0
    for _,argument in ipairs(arguments) do
        if argument.kind=="ValueArg" then self:expr(argument.value);local kinds=cellKinds(argument.value.type);if kinds==false then unsupported("argument of type "..S.display(argument.value.type)) end;cells=cells+#kinds
        elseif argument.kind=="BorrowArg" then self:address(argument.place,argument);cells=cells+1
        else unsupported("argument "..tostring(argument.kind)) end
    end
    return cells
end

function Function:call(stmt, selected)
    selected=selected or stmt.target
    local target = self.definitions[selected]
    local arguments = self:arguments(stmt.arguments, stmt)
    self:instruction("CALL.A " .. selected .. " " .. arguments, stmt)
    for index = #stmt.results, 1, -1 do
        local ty = target.results[index]
        self:storeValue(stmt.results[index], ty, stmt)
    end
end

function Function:indirect(stmt)
    if stmt.callable.kind~="Ref" then unsupported("non-reference Ir.Indirect callable") end
    local holder=self.valueSlots[stmt.callable.value.id]
    if not holder or not holder.cells or #holder.cells~=2 then D.bug("lower-callable","Indirect callable has no code/environment pair") end
    self:instruction("CGET.B "..self:depth(holder.cells[1]),stmt)
    self:instruction("CGET.A "..self:depth(holder.cells[2]),stmt)
    local arguments=1+self:arguments(stmt.arguments,stmt)
    local info=self.indirectInfo[stmt];if not info then D.bug("lower-callable","Indirect call has no site signature") end
    self:instruction("CALLI.A "..arguments.." "..info.signature,stmt)
    local results=stmt.callable.type.visible.results
    for index=#stmt.results,1,-1 do self:storeValue(stmt.results[index],results[index],stmt) end
end

function Function:dynamicCall(stmt)
    self:expr(stmt.callable);local arguments=self:arguments(stmt.arguments,stmt)
    self:instruction("DCALL "..arguments.." "..#stmt.results.." adjust",stmt)
    for index=#stmt.results,1,-1 do self:storeValue(stmt.results[index],S.any,stmt) end
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

function Function:tailCall(stmt, selected)
    selected=selected or stmt.target
    local arguments = self:arguments(stmt.arguments, stmt)
    self:instruction("TCALL "..selected.." "..(self.inputCells+#self.locals+self.blockCells)
        .." "..arguments,stmt)
end

function Function:statements(list)
    local index = 1
    while index <= #list do
        local stmt = list[index]
        local kind = stmt.kind
        if kind=="Indirect" and stmt.callable.type==S.any then
            self:dynamicCall(stmt);index=index+1
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
            if tailSafe and isReturnContinuation(stmt,k) then
                self:tailCall(stmt,selected)
                index = index + 2
            else
                self:call(stmt,selected)
                index = index + 1
            end
        elseif kind == "View" then
            if stmt.type==S.any then
                if #stmt.slots>0 then unsupported("captured callable conversion to any") end
                local target=self.definitions[stmt.entry]
                self:instruction("WORD_DIRECT "..stmt.entry.." "..self.descriptorOf(S.sig(target.inputs,target.results),true),stmt)
                self:storeValue(stmt.value,S.any,stmt)
            elseif stmt.type:isView() and self.viewInfo[stmt] then
                local info=self.viewInfo[stmt]
                if info.environment then
                    local base=S.Ir.Local(stmt.adapter)
                    for slotIndex,slot in ipairs(stmt.slots) do
                        local field=info.fields[slotIndex]
                        if slot.kind=="ValueArg" then self:expr(slot.value) else self:address(slot.place,slot) end
                        self:placeStore(S.Ir.Project(base,S.Ir.Field(field.name)),field.type,stmt)
                    end
                end
                self:instruction(".loadkind addr",stmt);self:instruction("GLD64 "..info.codeOffset,stmt)
                if info.environment then self:address(S.Ir.Local(stmt.adapter),stmt) else self:instruction("GADDR.A 0",stmt) end
                self:storeValue(stmt.value,stmt.type,stmt)
            end
            index = index + 1
        elseif kind == "Let" then
            if not self.aggregates[stmt.value.id] then
                self:expr(stmt.expr)
                self:storeValue(stmt.value, stmt.type, stmt)
            end
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
            self:instruction("RET "..(self.inputCells+#self.locals+self.blockCells).." "..countCells(self.fn.results),stmt)
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
        self:zero(slot.cellType or slot.type,self.fn)
        self:instruction("CPUSH.A",self.fn)
    end
    for _,slot in ipairs(self.blocks) do self:instruction("CALLOC "..slot.layout.size,self.fn) end
    for _,slot in ipairs(self.locals) do if slot.managed then self:instruction("MANAGED_NEW "..slot.descriptor,self.fn);self:instruction("CSET.A "..self:depth(slot),self.fn) end end
    self:statements(self.fn.body)
    return self.lines, self.lineMap
end

function M.lower(functions, options)
    options = options or {}
    if options.profile ~= "slet" and options.profile ~= "let" then
        D.reject("source-profile", "ABC lowering requires profile `let` or `slet`")
    end
    Check.program(functions, options.modules, options.foreigns)

    local definitions,usesFloat,usesMemory,usesAddress,usesCallable={},false,false,false,false
    local floatConstants,floatData,floatCount={},{},0
    local stringConstants,stringOrder,stringData={},{},{}
    local function hasManagedRoots(ty,seen)
        if ty==S.any or ty:isRef() or ty:isSlice() then return true end
        if ty:isPtr() or ty==S.unit or ty:isInteger() or ty==S.bool or ty==S.f64 then return false end
        seen=seen or {};if seen[ty] then return false end;seen[ty]=true
        local result=false
        if ty:isRecord() then for _,field in ipairs(ty.fields) do if hasManagedRoots(field.type,seen) then result=true;break end end
        elseif ty:isArray() then result=hasManagedRoots(ty.element,seen)
        elseif ty:isTaggedType() then for _,case in ipairs(S.alternatives(ty)) do if hasManagedRoots(case.type,seen) then result=true;break end end end
        seen[ty]=nil;return result
    end
    local descriptorNames,descriptorLines,descriptorCount={},{},0
    local function descriptorOf(ty,managed)
        local key=S.encode(ty)..(managed and ":managed" or ":strict");if descriptorNames[key] then return descriptorNames[key] end
        local primitive=ty==S.unit and "unit" or ty==S.bool and "bool" or ty==S.u8 and "u8" or ty==S.u16 and "u16" or ty==S.u32 and "u32" or ty==S.u64 and "u64" or ty==S.i32 and "i32" or ty==S.i64 and "i64" or ty==S.f64 and "f64" or ty==S.any and "any" or nil
        if primitive then local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name;descriptorLines[#descriptorLines+1]=".descriptor primitive "..name.." "..primitive;return name end
        if ty:isSig() then
            local components={}
            for _,input in ipairs(ty.inputs) do if input.kind=="InPlace" then unsupported("dynamic direct word with borrowed input") end;components[#components+1]=descriptorOf(input.type,managed) end
            for _,result in ipairs(ty.results) do components[#components+1]=descriptorOf(result,managed) end
            local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name
            local parts={".descriptor signature",name,tostring(#ty.inputs),tostring(#ty.results)};for _,component in ipairs(components) do parts[#parts+1]=component end;descriptorLines[#descriptorLines+1]=table.concat(parts," ");return name
        end
        if ty:isRef() or ty:isPtr() then
            local child=descriptorOf(ty.target,managed);local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name
            local owner=ty:isPtr() and "raw" or managed and "managed" or "strict";descriptorLines[#descriptorLines+1]=".descriptor pointer "..name.." "..owner.." "..child;return name
        end
        if ty:isString() then
            local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name;descriptorLines[#descriptorLines+1]=".descriptor primitive "..name.." string";return name
        end
        if ty:isSlice() then
            local child=descriptorOf(ty.element,managed);local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name
            descriptorLines[#descriptorLines+1]=".descriptor slice "..name.." "..(managed and "managed" or "strict").." "..child;return name
        end
        if ty:isRecord() then
            local item=layout(ty);local children={};for _,field in ipairs(ty.fields) do if hasManagedRoots(field.type) then children[#children+1]={field=field,name=descriptorOf(field.type,managed)} end end
            local emptyChild;if #children==0 then emptyChild=descriptorOf(S.unit,managed) end
            local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name;local parts={".descriptor record",name,tostring(item.size),tostring(emptyChild and 1 or #children)}
            if emptyChild then parts[#parts+1]="0";parts[#parts+1]="0";parts[#parts+1]="0";parts[#parts+1]=emptyChild end
            for _,child in ipairs(children) do local at=item.fields[child.field.name].offset;parts[#parts+1]="0";parts[#parts+1]="0";parts[#parts+1]=tostring(at);parts[#parts+1]=child.name end
            descriptorLines[#descriptorLines+1]=table.concat(parts," ");return name
        end
        if ty:isArray() then
            if not hasManagedRoots(ty) then local child=descriptorOf(S.unit,managed);local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name;descriptorLines[#descriptorLines+1]=".descriptor record "..name.." "..layout(ty).size.." 1 0 0 0 "..child;return name end
            local child=descriptorOf(ty.element,managed);local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name
            descriptorLines[#descriptorLines+1]=".descriptor array "..name.." "..layout(ty).size.." "..ty.length.." "..child;return name
        end
        if ty:isTaggedType() then
            if not hasManagedRoots(ty) then local child=descriptorOf(S.unit,managed);local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name;descriptorLines[#descriptorLines+1]=".descriptor record "..name.." "..layout(ty).size.." 1 0 0 0 "..child;return name end
            local item=layout(ty);local children={};for index,case in ipairs(S.alternatives(ty)) do children[#children+1]={tag=index-1,name=hasManagedRoots(case.type) and descriptorOf(case.type,managed) or descriptorOf(S.unit,managed)} end
            local name="_let_D"..descriptorCount;descriptorCount=descriptorCount+1;descriptorNames[key]=name;local parts={".descriptor sum",name,tostring(item.size),"0","4",tostring(#children)}
            for _,child in ipairs(children) do parts[#parts+1]=tostring(child.tag);parts[#parts+1]=tostring(item.payloadOffset);parts[#parts+1]=child.name end
            descriptorLines[#descriptorLines+1]=table.concat(parts," ");return name
        end
        unsupported("managed descriptor for "..S.display(ty))
    end
    local viewInfo,indirectInfo,adapters,signatureNames,signatureLines={},{},{},{},{}
    local function inputKinds(input) if input.kind=="InPlace" then return {"a"} end;local kinds=cellKinds(input.type);if kinds==false then unsupported("callable input of type "..S.display(input.type)) end;return kinds end
    local function signatureFor(sig)
        local key=S.encode(sig);if signatureNames[key] then return signatureNames[key] end
        local name="_let_sig"..(#signatureLines+1);signatureNames[key]=name;local arguments={"a"};for _,input in ipairs(sig.inputs) do for _,kind in ipairs(inputKinds(input)) do arguments[#arguments+1]=kind end end
        local results={};for _,ty in ipairs(sig.results) do local kinds=cellKinds(ty);if kinds==false then unsupported("callable result of type "..S.display(ty)) end;for _,kind in ipairs(kinds) do results[#results+1]=kind end end
        signatureLines[#signatureLines+1]=".signature "..name.." "..#arguments.." "..#results.." "..table.concat(arguments).." "..(#results>0 and table.concat(results) or "-");return name
    end
    local function inspectType(ty)
        if ty==S.any then if options.profile~="let" then D.reject("slet-forbidden","SLet cannot lower any values") end;return end
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
    for _,fn in ipairs(functions) do if definitions[fn.id] then D.bug("lower-duplicate","Duplicate function "..fn.id) end;definitions[fn.id]=fn end
    local adapterSerial=0
    for _, fn in ipairs(functions) do
        local localViews={}
        Walk.walk(fn,{enter=function(node)
            if S.Ir.View:isclassof(node) and node.type:isView() and #node.slots>0 then
                adapterSerial=adapterSerial+1;local name="_let_adapter_"..adapterSerial;while definitions[name] do adapterSerial=adapterSerial+1;name="_let_adapter_"..adapterSerial end
                local fields,ordered={},{ };for index,slot in ipairs(node.slots) do local input=definitions[node.entry].inputs[index];local field={name=string.format("_%04d",index),type=slot.kind=="BorrowArg" and S.ref(input.type) or input.type};fields[field.name]=field.type;ordered[index]=field end
                local environment=S.record(fields);local info={name=name,statement=node,target=definitions[node.entry],environment=environment,fields=ordered};viewInfo[node]=info;localViews[node.value.id]=info;adapters[#adapters+1]=info;usesCallable=true;usesAddress=true;usesMemory=true
            elseif S.Ir.View:isclassof(node) and node.type:isView() then
                localViews[node.value.id]=false
            elseif S.Ir.Indirect:isclassof(node) and node.callable.type:isView() then
                local known=node.callable.kind=="Ref" and localViews[node.callable.value.id]
                if known~=false then indirectInfo[node]={signature=signatureFor(node.callable.type.visible)};usesCallable=true end
            end
        end})
        Walk.walk(fn, {enter = function(node)
            if S.Ty.V:isclassof(node) then inspectType(node); return false end
            if node.kind=="Const" and node.type==S.f64 then retainFloat(node.literal.value) end
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
    local profile=options.profile=="let" and "dynamic" or usesCallable and "callables" or (usesFloat or usesMemory) and "memory" or "integer"
    local constants={floats=floatConstants,strings=stringConstants}
    local metadata={descriptorOf=descriptorOf,viewInfo=viewInfo,indirectInfo=indirectInfo}
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
    if dataSize>0 then append(".datazero "..dataSize) end
    local rodata=table.concat(floatData)..table.concat(stringData);if #rodata>0 then append(".rodata "..rodata) end
    for _,line in ipairs(descriptorLines) do append(line) end
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
        append("  TCALL "..target.id.." "..adapterCells.." "..targetCells,statement)
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
