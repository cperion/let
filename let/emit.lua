-- Belt to C. The belt is already the semantic program, so this pass only chooses
-- representations and prints them. It is not a second semantic IR and never decides
-- evaluation order: statements follow the belt's ordered effect chain.
return function(V)
local A,B,C,L=V.AST,V.Belt,V.C,V.List
local literal=require('let.literal')
local Known=V.Known
local scalar=V.scalar

local Emitter={}; Emitter.__index=Emitter


function Emitter.new(options)
    return setmetatable({options=options or {},structs={},struct_names={},results={},result_names={},
        names={},helpers={},used_hosts={},used_destroys={},destroy_pointer={},text=false,stdbool=true,trap=false,
        instances={},pending={},generic={},serial={},self_tail={}},Emitter)
end

-- A host may state the C prototype it calls, because that ABI is an embedding detail (§15.3).
-- The Let types already map to C (`CString` is `const char*`, the scalars are themselves), so
-- only an integer of a different width needs a cast.
local function compact(name) return (name:gsub('%s','')) end
local c_integer={}
for _,name in ipairs{'char','signedchar','unsignedchar','short','unsignedshort','int','unsigned',
    'long','unsignedlong','longlong','unsignedlonglong','size_t','ssize_t','ptrdiff_t','intptr_t',
    'uintptr_t','int8_t','uint8_t','int16_t','uint16_t','int32_t','uint32_t','int64_t','uint64_t'} do
    c_integer[name]=true
end
local function c_integer_type(name) return c_integer[compact(name)]==true end

function Emitter:host_arguments(host,arguments)
    local converted=L()
    for i,value in ipairs(arguments) do
        local spelling=host.c and host.c.params and host.c.params[i]
        if spelling and c_integer_type(spelling) then
            converted:insert(C.Cast(C.Named(spelling),value))
        else
            converted:insert(value)
        end
    end
    return converted
end

function Emitter:host_result(host,call)
    local spelling=host.c and host.c.result
    -- A Unit result discards the value, so there is nothing to convert.
    if spelling and host.signature.results[1]~=B.Unit and c_integer_type(spelling) then
        return C.Cast(C.I64,call)
    end
    return call
end

function Emitter:error(message) error('C emission: ' .. message,0) end

function Emitter:register_struct(fields)
    local key='s'
    for _,field in ipairs(fields) do key=key .. '|' .. field:key() end
    local existing=self.struct_names[key]
    if existing then return "struct " .. existing end
    -- Nested aggregate fields must be declared first, so the name is chosen only
    -- after this struct's own fields have registered theirs.
    local declarations=L()
    -- Field names are zero-based to match belt member indices.
    for i,field in ipairs(fields) do declarations:insert(C.Parameter(self:ctype(field.type),'f' .. (i-1))) end
    local name='let_val_' .. (#self.structs+1)
    self.struct_names[key]=name
    self.structs[#self.structs+1]=C.Struct(name,declarations)
    return 'struct ' .. name
end

function Emitter:ctype(type_)
    if type_==B.Int then return C.I64 end
    if type_==B.Bool then return C.Bool end
    if type_==B.Unit then return C.U8 end
    if type_==B.Effect then return C.U64 end
    if type_==B.Float then self.math=true; return C.F64 end
    if type_==B.Text then self.text=true; return C.Named('struct let_text') end
    if type_==B.CString then return C.Pointer(C.Named('const char')) end
    if type_==B.CPointer then return C.Pointer(C.Named('void')) end
    if B.Named:isclassof(type_) then
        -- A resource is an integer handle by default, or a C pointer when it declares one.
        local descriptor=self.options.resources and self.options.resources[type_.name]
        if descriptor and descriptor.representation=='pointer' then return C.Pointer(C.Named('void')) end
        return C.I64
    end
    if B.Address:isclassof(type_) or B.Borrow:isclassof(type_) then return C.Pointer(self:ctype(type_.pointee)) end
    if B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        -- A record with no fields carries no information, and an empty struct is not ISO C.
        if #type_.fields==0 then return C.U8 end
        return C.Named(self:register_struct(type_.fields))
    end
    if B.Sum:isclassof(type_) then return C.Named(self:register_struct(type_:record())) end
    if type_==B.TypeWord then return C.U8 end
    self:error('no representation for ' .. tostring(type_))
end

-- Effect tokens are ordering evidence for the frontend and have no C representation: the
-- belt's statement order already carries the order. Dropping them removes the effect
-- parameter, the effect field of every result, and every effect update.
function Emitter:value_types(types)
    local values={}
    for _,type_ in ipairs(types) do if type_~=B.Effect then values[#values+1]=type_ end end
    return values
end

-- A function returning no value is `void`; one returning a single value returns that type
-- directly. Only a genuine multiple result needs a struct.
function Emitter:return_shape(types)
    local values=self:value_types(types)
    if #values==0 then return C.Void,0 end
    if #values==1 then return self:ctype(values[1]),1 end
    local key='r'
    for _,type_ in ipairs(values) do key=key .. '|' .. type_:key() end
    local existing=self.result_names[key]
    if existing then return C.Named('struct ' .. existing),#values end
    local name='let_ret_' .. (#self.results+1)
    self.result_names[key]=name
    local declarations=L()
    for i,type_ in ipairs(values) do declarations:insert(C.Parameter(self:ctype(type_),'r' .. (i-1))) end
    self.results[#self.results+1]=C.Struct(name,declarations)
    return C.Named('struct ' .. name),#values
end

-- `values` are the materialized results only; the effect has already been dropped.
function Emitter:return_value(type_,values)
    if type_==C.Void then return nil end
    if #values==1 then return values[1] end
    return C.Compound(type_,values)
end

-- Negation is applied in 64-bit two's-complement form here rather than in C, where
-- negating INT64_MIN would be undefined and the magnitude may exceed a Lua number.
function Emitter:literal(spelling)
    local negative=spelling:sub(1,1)=='-'
    local _,_,hi,lo=literal.integer(negative and spelling:sub(2) or spelling,negative,function(m) self:error(m) end)
    if not negative or (hi==0 and lo==0) then return C.Integer(hi,lo) end
    local borrowed=lo==0 and 0 or 1
    return C.Integer((4294967296-hi-borrowed)%4294967296, lo==0 and 0 or 4294967296-lo)
end

function Emitter:param(belt_id,index) return 'p' .. belt_id .. '_' .. index end
function Emitter:value(belt_id,index,output) return 'v' .. belt_id .. '_' .. index .. '_' .. output end

-- Answers come from the abstract evaluator. A known answer is inlined at every use and its
-- producer is never written out, so folding removes work rather than hiding it. Which answers
-- exist, and where a producer's answer lives, is `disposition`'s business, not the emitter's:
-- reaching for an answer directly is how one rule became several.

function Emitter:constant(answer)
    local type_=answer.type
    if type_==B.Int then local hi,lo=scalar.limbs(answer.value); return C.Integer(hi,lo) end
    if type_==B.Float then self.math=true; return C.Float(answer.value) end
    if type_==B.Bool then return C.Boolean(answer.value) end
    if type_==B.Unit then return C.Integer(0,0) end
    if type_==B.Text then return C.Compound(self:ctype(B.Text),L{C.String(answer.value),C.Integer(0,#answer.value)}) end
    if B.Word:isclassof(type_) or B.Aggregate:isclassof(type_) or B.Sum:isclassof(type_) then
        if #answer.value.fields==0 then return C.Integer(0,0) end
        local fields=L()
        for _,field in ipairs(answer.value.fields) do fields:insert(self:constant(field)) end
        return C.Compound(self:ctype(type_),fields)
    end
    self:error('no C constant for ' .. tostring(type_))
end

-- Resolve a belt reference to the C expression holding that output.
function Emitter:ref(block,block_id,position,ref)
    -- Unit has exactly one value. It is materialized by whatever produced it -- an ordered call
    -- emits a statement rather than a variable -- so a use of it is the constant, never a name.
    local _,ref_type=block:resolve(position,ref)
    if ref_type==B.Unit then return C.Integer(0,0) end
    local producer=position-1-ref.distance
    local fate,answer=self:disposition(self.current_instance.analysis,self.current,block_id,producer,ref.output)
    if fate=='constant' then return self:constant(answer) end
    if producer<#block.parameters then return C.Name(self:param(block_id,producer)) end
    return C.Name(self:value(block_id,producer-#block.parameters+1,ref.output))
end

function Emitter:arglist(block,block_id,position,refs)
    local out=L() for _,ref in ipairs(refs) do out:insert(self:ref(block,block_id,position,ref)) end
    return out
end

local symbolic={[A.Add]='+',[A.Subtract]='-',[A.Multiply]='*',[A.Divide]='/',[A.Less]='<',[A.LessEqual]='<=',
    [A.Greater]='>',[A.GreaterEqual]='>=',[A.Equal]='==',[A.NotEqual]='!=',[A.And]='&&',[A.Or]='||',
    [A.BitAnd]='&',[A.BitOr]='|',[A.BitXor]='^'}
local arithmetic={[A.Add]={'add','LET_ADD'}, [A.Subtract]={'sub','LET_SUB'}, [A.Multiply]={'mul','LET_MUL'}}


local function statement_list(list)
    local declarations=L(); for _,entry in ipairs(list) do declarations:insert(entry) end; return declarations
end

-- Emits one instruction. Returns a statement list; output variables are named by
-- (block, instruction index, output) so relative references stay resolvable.
function Emitter:instruction(block,block_id,index,instruction)
    local position=#block.parameters+index-1
    local operation=instruction.operation
    local out={}
    -- One question, asked of the same place the body filter and every reference asks.
    local function known(output)
        return self:disposition(self.current_instance.analysis,self.current,block_id,position,output)=='constant'
    end
    local function declare(output,type_,expr)
        if type_==B.Effect then return false end
        if known(output) then return false end
        out[#out+1]=C.Declare(self:ctype(type_),self:value(block_id,index,output),expr)
        return true
    end
    if B.IntegerLiteral:isclassof(operation) then
        declare(0,B.Int,self:literal(operation.spelling))
    elseif B.FloatLiteral:isclassof(operation) then
        self.math=true
        declare(0,B.Float,C.Float(scalar.float(operation.spelling,error)))
    elseif B.BooleanLiteral:isclassof(operation) then
        declare(0,B.Bool,C.Boolean(operation.value))
    elseif B.UnitLiteral:isclassof(operation) then
        declare(0,B.Unit,C.Integer(0,0))
    elseif B.TextLiteral:isclassof(operation) then
        self.text=true
        declare(0,B.Text,C.Compound(self:ctype(B.Text),L{C.String(operation.value),C.Integer(0,#operation.value)}))
    elseif B.Unary:isclassof(operation) then
        local operand=self:arglist(block,block_id,position,{operation.operand})[1]
        if operation.operator==A.Not then declare(0,B.Bool,C.Unary('!',operand))
        elseif operation.operator==A.ToFloat then declare(0,B.Float,C.Cast(self:ctype(B.Float),operand))
        elseif operation.operator==A.ToInt then
            if declare(0,B.Int,C.Call(C.Name('let_to_int'),L{operand})) then self.helpers.to_int=true end
        elseif operation.operator==A.ToCString then
            declare(0,B.CString,C.Field(operand,'data'))
        elseif operation.operator==A.ToText then
            self.text=true; self.helpers.text_from_c=true
            declare(0,B.Text,C.Call(C.Name('let_text_from_c'),L{operand}))
        elseif operation.operator==A.TextSize then
            declare(0,B.Int,C.Cast(C.I64,C.Field(operand,'size')))
        elseif operation.operator==A.IsNull then
            declare(0,B.Bool,C.Binary('==',operand,C.Integer(0,0)))
        elseif operation.operator==A.BitNot then declare(0,B.Int,C.Unary('~',operand))
        elseif instruction.results[1]==B.Float then declare(0,B.Float,C.Unary('-',operand))
        elseif declare(0,B.Int,C.Call(C.Name('LET_NEG'),L{operand})) then self.helpers.neg=true end
    elseif B.Binary:isclassof(operation) then
        local arguments=self:arglist(block,block_id,position,{operation.left,operation.right})
        local _,type_=block:resolve(position,operation.left)
        if known(0) then return statement_list(out) end
        if type_==B.Float then
            self.math=true
            declare(0,instruction.results[1],C.Binary(symbolic[operation.operator],arguments[1],arguments[2]))
        elseif operation.operator==A.Equal or operation.operator==A.NotEqual then
            -- `symbolic` already spells the operator: `==` or `!=` for a scalar, and the one Text
            -- macro *is* equality, so only that case has anything left to negate. Negating the
            -- scalar case too made `!=` compare equal and vice versa.
            local call,negated
            if type_==B.Text then
                self.helpers.text_eq=true
                call=C.Call(C.Name('LET_TEXT_EQ'),L{arguments[1],arguments[2]})
                negated=operation.operator==A.NotEqual
            else
                call=C.Binary(symbolic[operation.operator],arguments[1],arguments[2])
                negated=false
            end
            declare(0,B.Bool,negated and C.Unary('!',call) or call)
        elseif arithmetic[operation.operator] then
            local helper=arithmetic[operation.operator]
            self.helpers[helper[1]]=true
            declare(0,B.Int,C.Call(C.Name(helper[2]),L{arguments[1],arguments[2]}))
        elseif operation.operator==A.ShiftLeft or operation.operator==A.ShiftRight then
            if operation.operator==A.ShiftLeft then
                self.helpers.shl=true
                declare(0,B.Int,C.Call(C.Name('LET_SHL'),L{arguments[1],arguments[2]}))
            else
                self.helpers.shr=true
                declare(0,B.Int,C.Call(C.Name('let_shr'),L{arguments[1],arguments[2]}))
            end
        else
            declare(0,instruction.results[1],C.Binary(symbolic[operation.operator],arguments[1],arguments[2]))
        end
    elseif B.CheckedBinary:isclassof(operation) then
        local arguments=self:arglist(block,block_id,position,{operation.left,operation.right})
        local helper=operation.operator==A.Divide and 'let_div' or 'let_rem'
        if not known(0) then self.helpers[operation.operator==A.Divide and 'div' or 'rem']=true end
        local effect=self:ref(block,block_id,position,operation.effect)
        -- §16.2: a non-zero known divisor proves the check cannot fail, so it is omitted.
        if declare(0,B.Int,C.Call(C.Name(helper),L{arguments[1],arguments[2]})) then
            self.trap=true
            declare(1,B.Effect,C.Binary('+',effect,C.Integer(0,1)))
        else declare(1,B.Effect,effect) end
    elseif B.FieldAddress:isclassof(operation) then
        -- A field's address: the same storage, reached one level in.
        local place=self:ref(block,block_id,position,operation.place)
        declare(0,instruction.results[1],C.Unary('&',C.Field(C.Unary('*',place),'f' .. operation.field)))
    elseif B.TextOf:isclassof(operation) then
        -- A Text view over a borrowed pointer and a length, built like a literal's struct.
        self.text=true
        local pointer=self:ref(block,block_id,position,operation.pointer)
        local size=self:ref(block,block_id,position,operation.size)
        declare(0,B.Text,C.Compound(self:ctype(B.Text),
            L{C.Cast(C.Pointer(C.Named('char')),pointer),C.Cast(C.U64,size)}))
    elseif B.BorrowPlace:isclassof(operation) then
        -- A borrow is the same storage, so nothing is emitted for the operation itself; only
        -- the type changed, and that is a frontend matter.
        declare(0,instruction.results[1],self:ref(block,block_id,position,operation.address))
    elseif B.Construct:isclassof(operation) then
        if #operation.fields==0 then declare(0,instruction.results[1],C.Integer(0,0))
        else declare(0,instruction.results[1],C.Compound(self:ctype(instruction.results[1]),self:arglist(block,block_id,position,operation.fields))) end
    elseif B.LoadField:isclassof(operation) then
        local base=self:ref(block,block_id,position,operation.record)
        declare(0,instruction.results[1],C.Field(base,'f' .. operation.field))
    elseif B.StoreField:isclassof(operation) then
        local word=self:ref(block,block_id,position,operation.record)
        local type_=instruction.results[1]
        local fields=L()
        for i=0,#type_:record()-1 do
            if i==operation.field then fields:insert(self:ref(block,block_id,position,operation.value))
            else fields:insert(C.Field(word,'f' .. i)) end
        end
        declare(0,type_,C.Compound(self:ctype(type_),fields))
    elseif B.Allocate:isclassof(operation) then
        -- A cell is storage whose address is taken. Storage is chosen after the contract is
        -- known (WORDS.md §9): a value that must be observable as a place becomes memory, and
        -- an address that never escapes can still be promoted by the C compiler.
        local address=instruction.results[1]
        local cell=self:value(block_id,index,'c')
        if self.current_id==1 then
            -- Module state lives until unload, so a module cell needs storage that outlives
            -- the initializer's frame: a captured word holds this address.
            self.statics[#self.statics+1]=C.Global(self:ctype(address.pointee),cell)
            out[#out+1]=C.Assign(C.Name(cell),self:ref(block,block_id,position,operation.initial))
        else
            out[#out+1]=C.Declare(self:ctype(address.pointee),cell,self:ref(block,block_id,position,operation.initial))
        end
        declare(0,address,C.Unary('&',C.Name(cell)))
        declare(1,B.Effect,C.Binary('+',self:ref(block,block_id,position,operation.effect),C.Integer(0,1)))
    elseif B.Load:isclassof(operation) then
        declare(0,instruction.results[1],C.Unary('*',self:ref(block,block_id,position,operation.address)))
        declare(1,B.Effect,C.Binary('+',self:ref(block,block_id,position,operation.effect),C.Integer(0,1)))
    elseif B.Store:isclassof(operation) then
        out[#out+1]=C.Assign(C.Unary('*',self:ref(block,block_id,position,operation.address)),
            self:ref(block,block_id,position,operation.value))
        declare(0,B.Effect,C.Binary('+',self:ref(block,block_id,position,operation.effect),C.Integer(0,1)))
    elseif B.CallFunction:isclassof(operation) then
        -- The callee's effect parameter is not part of its C signature.
        local callee=self:callee_instance(operation.target,block,block_id,position,operation.arguments)
        local call=C.Call(C.Name(callee.name),
            self:call_arguments(callee,block,block_id,position,operation.arguments))
        local type_,count=self:return_shape(self.functions[operation.target].signature.results)
        -- A call the evaluator answered but kept still happens, even when every result it
        -- returns is a constant: the answer replaces the *uses*, not the call. Only the
        -- declaration is dropped, never the evaluation.
        if count==0 then
            out[#out+1]=C.Evaluate(call)
        elseif count==1 then
            if known(0) then out[#out+1]=C.Evaluate(call) else declare(0,instruction.results[1],call) end
        else
            local temporary=self:value(block_id,index,'t')
            out[#out+1]=C.Declare(type_,temporary,call)
            local output=0
            for _,result in ipairs(instruction.results) do
                if result~=B.Effect then
                    if not known(output) then declare(output,result,C.Field(C.Name(temporary),'r' .. output)) end
                    output=output+1
                end
            end
        end
    elseif B.HostCall:isclassof(operation) or B.PureHostCall:isclassof(operation) then
        local host=self.hosts[operation.symbol] or self:error('missing host contract for ' .. operation.symbol)
        self.used_hosts[host.symbol]=host
        local arguments=self:host_arguments(host,self:arglist(block,block_id,position,operation.arguments))
        local call=self:host_result(host,C.Call(C.Name(operation.symbol),statement_list(arguments)))
        local pure=B.PureHostCall:isclassof(operation)
        if instruction.results[1]==B.Unit then out[#out+1]=C.Evaluate(call)
        else out[#out+1]=C.Declare(self:ctype(instruction.results[1]),self:value(block_id,index,0),call) end
        if not pure then
            local effect=self:ref(block,block_id,position,operation.effect)
            declare(#instruction.results-1,B.Effect,C.Binary('+',effect,C.Integer(0,1)))
        end
    elseif B.Move:isclassof(operation) then
        local value=self:ref(block,block_id,position,operation.value)
        if declare(0,instruction.results[1],value) then
            declare(1,B.Effect,C.Binary('+',self:ref(block,block_id,position,operation.effect),C.Integer(0,1)))
        else declare(1,B.Effect,self:ref(block,block_id,position,operation.effect)) end
    elseif B.Destroy:isclassof(operation) then
        self.used_destroys[operation.destructor]=true
        local value=self:ref(block,block_id,position,operation.value)
        out[#out+1]=C.Evaluate(C.Call(C.Name(operation.destructor),L{value}))
        declare(0,B.Effect,C.Binary('+',self:ref(block,block_id,position,operation.effect),C.Integer(0,1)))
    else
        self:error('no representation for ' .. tostring(operation))
    end
    return statement_list(out)
end

-- Instances ----------------------------------------------------------------------------
--
-- The unit of emission is an *instance*: a belt function together with the answers of the
-- entry packet it is called with, which is the same key `Run` caches an analysis under. One
-- function per belt id was the special case of that where nothing is known about the packet,
-- so the generic instance is not a fallback bolted on beside specialization -- it is the
-- instance with no information, and it is what the module interface itself uses.

-- The instance a function has knowing nothing about its entry packet.
function Emitter:generic_instance(id)
    local existing=self.generic[id]
    if existing then return existing end
    local instance=self:add_instance(id,self.run:instance(id,nil),self.run:key(id,nil),true)
    self.generic[id]=instance
    return instance
end

function Emitter:add_instance(id,analysis,key,generic)
    local serial=(self.serial[id] or 0)+1
    self.serial[id]=serial
    local instance={id=id,belt=self.functions[id],analysis=analysis,key=key,generic=generic,
        name=generic and self:function_name(id) or (self:function_name(id) .. '_' .. serial)}
    self.instances[key]=instance
    self.pending[#self.pending+1]=instance
    return instance
end

-- A self tail transfer changes the entry packet in place, so no packet of such a function is
-- fixed and every call to it uses the generic instance.
function Emitter:self_tail_recursive(id)
    local known=self.self_tail[id]
    if known~=nil then return known end
    local found=false
    for _,block in ipairs(self.functions[id].blocks) do
        if B.TailCall:isclassof(block.exit) and block.exit.target==id then found=true end
    end
    self.self_tail[id]=found
    return found
end

-- The instance a call names. A packet with no constant is the generic instance; one with a
-- constant gets an instance of its own, unless the budget is spent or the instance is already
-- being analysed, in which case the generic one is used and every call still resolves.
function Emitter:callee_instance(target,block,block_id,position,arguments)
    local generic=self:generic_instance(target)
    if self:self_tail_recursive(target) then return generic end
    local seeded={Known.runtime(B.Effect)}
    local useful=false
    for i,ref in ipairs(arguments) do
        local answer=self.current_instance.analysis:resolve(block,block_id,position,ref)
        seeded[i+1]=answer
        if Known.is_known(answer) then useful=true end
    end
    if not useful then return generic end
    return self:specialized_instance(target,seeded) or generic
end

-- The instance for a packet, if one can be built: nil when the budget is spent or the same
-- instance is already being analysed, which is how a cycle terminates.
function Emitter:specialized_instance(id,seeded)
    local key=self.run:key(id,seeded)
    local existing=self.instances[key]
    if existing then return existing end
    local analysis=self.run:instance(id,seeded)
    if not analysis then return nil end
    return self:add_instance(id,analysis,key,false)
end

-- What a function's body needs, as one set of producer positions and outputs. The demand pass
-- over its instructions, plus the entry parameters block 1 reads.
--
-- The second part is not redundant. The demand pass reports the module unload's state -- which
-- a `Destroy` consumes -- as unneeded, so its answer for an entry packet cannot be used on its
-- own. The scan is local to block 1 on purpose: anything read in another block was copied
-- there by an edge, and that copy is itself a reference, so a parameter block 1 never reads is
-- one nothing reads. It is recomputed per belt rather than cached beside the demand table,
-- because a callee and its call sites must reach the same answer.
local requirements={}
-- The parameters block 1 reads. A call argument counts as a use only when the callee's parameter
-- is live: a dead parameter is dropped from the callee's signature and from the call, so treating
-- the argument as a use would keep the caller's parameter alive for a value never passed. One
-- rule reaches both. On a cycle the callee is still being computed, so its parameters are live.
function Emitter:entry_parameters_read(belt)
    local block=belt.blocks[1]
    local used={}
    local function note(position,ref)
        local producer=block:resolve(position,ref)
        if producer<#block.parameters then used[producer]=true end
    end
    for index,instruction in ipairs(block.instructions) do
        local at=#block.parameters+index-1
        local operation=instruction.operation
        local callee=B.CallFunction:isclassof(operation) and self.functions[operation.target]
        if callee and requirements[callee]~='pending' then
            for i,ref in ipairs(operation.arguments) do
                if self:parameter_live(nil,callee,1,i+1) then note(at,ref) end
            end
        else
            for _,ref in ipairs(operation:inputs()) do note(at,ref) end
        end
    end
    local at=#block.parameters+#block.instructions
    for _,ref in ipairs(block.exit:inputs()) do note(at,ref) end
    return used
end

function Emitter:requirements(belt)
    local cached=requirements[belt]
    if cached then return cached end
    requirements[belt]='pending'
    local needed=belt:demands()
    local read=self:entry_parameters_read(belt)
    needed[1]=needed[1] or {}
    for position in pairs(read) do
        needed[1][position]=needed[1][position] or {}
        needed[1][position][0]=true
    end
    -- Block 1's read set is the whole story for its parameters, so a parameter no instruction
    -- reads is not needed, even though the demand pass marked it as a call argument.
    for position=0,#belt.blocks[1].parameters-1 do
        if not read[position] then
            local entry=needed[1][position]
            if entry then entry[0]=nil end
        end
    end
    requirements[belt]=needed
    return needed
end

-- What happens to one output of one producer.
--   'constant' -- its value is known, so every use of it is that constant;
--   'value'    -- it is materialized, and uses read it by name;
--   'dropped'  -- nothing needs it, so neither it nor its producer is written out.
--
-- A parameter asks the same question with `position` being its 0-based index, which is where
-- its value lives in the entry packet.
-- Whether a function is part of the program's interface to its host: the module initializer and
-- the entry points published for the host to call. Both are named for the linker rather than
-- `static`, and that is a property of the program, not of anything a caller passes in.
function Emitter:hosted(instance)
    return instance.id==1 or (self.host_ids and self.host_ids[instance.id]==true)
end

function Emitter:disposition(analysis,belt,block_id,position,output)
    local block=belt.blocks[block_id]
    local parameter=block.parameters[position+1]
    -- An effect is not a value and never a declaration; it exists to order the body.
    if parameter and parameter.type==B.Effect then return 'value' end
    -- A parameter's value is the packet the caller supplied; an instruction's is its own
    -- result. That is the only difference between the two, so it is stated here.
    local answer
    if parameter then answer=analysis and analysis:param(block_id,position+1)
    else answer=analysis and analysis:answer(block_id,position,output) end
    if Known.is_known(answer) then return 'constant',answer end
    local needed=self:requirements(belt)[block_id]
    if needed and needed[position] and needed[position][output] then return 'value' end
    return 'dropped'
end

-- Whether an instruction is written out at all. A call the evaluator folded is not, and a
-- pure producer whose outputs are all dropped is not either.
function Emitter:instruction_runs(analysis,belt,block_id,position,instruction)
    if analysis and B.CallFunction:isclassof(instruction.operation)
        and analysis:call_was_folded(block_id,position) then return false end
    for output=0,#instruction.results-1 do
        if self:disposition(analysis,belt,block_id,position,output)~='dropped' then return true end
    end
    return false
end

-- Does this parameter of this block exist in C at all? The function's signature, every call
-- site and every edge copy ask here, so they cannot disagree. An effect never does: statement
-- order carries it, so it is neither declared, nor passed, nor copied.
function Emitter:parameter_live(analysis,belt,block_id,index)
    if belt.blocks[block_id].parameters[index].type==B.Effect then return false end
    return self:disposition(analysis,belt,block_id,index-1,0)=='value'
end

function Emitter:needed_parameter(block_id,index)
    return self:parameter_live(self.current_instance.analysis,self.current,block_id,index)
end

-- The arguments a call passes: belt argument i lands on entry parameter i+1, the effect being
-- carried separately.
-- The arguments a call passes, asked of the instance it names: belt argument i lands on entry
-- parameter i+1, and the effect is carried separately. Signature and call site ask the same
-- rule of the same instance, so they cannot disagree.
function Emitter:call_arguments(instance,block,block_id,position,refs)
    local out=L()
    for i,ref in ipairs(refs) do
        if self:parameter_live(instance.analysis,instance.belt,1,i+1) then
            out:insert(self:ref(block,block_id,position,ref))
        end
    end
    return out
end

-- Edge packets are parallel assignments, so a temporary breaks any clobber cycle.
function Emitter:edge(target_id,edge,block,block_id,position)
    local target=self.current.blocks[target_id]
    local statements=L()
    local temporaries=L()
    local live={}
    for i,ref in ipairs(edge.arguments) do
        if self:needed_parameter(target_id,i) then
            local name=self:value(block_id,position,'e' .. i)
            live[#live+1]=i
            temporaries:insert(C.Declare(self:ctype(target.parameters[i].type),name,self:ref(block,block_id,position,ref)))
        end
    end
    statements:insertall(temporaries)
    for _,i in ipairs(live) do
        statements:insert(C.Assign(C.Name(self:param(target_id,i-1)),C.Name(self:value(block_id,position,'e' .. i))))
    end
    statements:insert(C.Goto('b' .. target_id))
    return C.Block(statements)
end

function Emitter:exit(target_id,block,block_id,exit)
    local position=#block.parameters+#block.instructions
    if B.Return:isclassof(exit) then
        local types=self.functions[target_id].signature.results
        local given=self:arglist(block,block_id,position,exit.values)
        local values=L()
        for i,type_ in ipairs(types) do if type_~=B.Effect then values:insert(given[i]) end end
        local type_=self:return_shape(types)
        return C.Return(self:return_value(type_,values))
    elseif B.Jump:isclassof(exit) then
        return self:edge(exit.edge.target,exit.edge,block,block_id,position)
    elseif B.Branch:isclassof(exit) then
        local taken=self.decision[block_id]
        if taken then return self:edge(taken.target,taken,block,block_id,position) end
        local condition=self:ref(block,block_id,position,exit.condition)
        return C.If(condition,self:edge(exit.yes.target,exit.yes,block,block_id,position),self:edge(exit.no.target,exit.no,block,block_id,position))
    elseif B.TailCall:isclassof(exit) then
        local arguments=self:arglist(block,block_id,position,exit.arguments)
        if exit.target==target_id then
            -- A self tail transfer reuses this activation: assign the entry packet and
            -- jump back to the entry block instead of growing a continuation chain.
            local entry=self.current.blocks[1]
            local statements,live=L(),{}
            -- A tail call's arguments exclude the effect, so argument i lands on belt
            -- parameter i+1 (1-based for the packet, 0-based for the C name).
            for i,argument in ipairs(exit.arguments) do
                if self:needed_parameter(1,i+1) then
                    local name=self:value(block_id,position,'t' .. i)
                    live[#live+1]=i
                    statements:insert(C.Declare(self:ctype(entry.parameters[i+1].type),name,self:ref(block,block_id,position,argument)))
                end
            end
            for _,i in ipairs(live) do statements:insert(C.Assign(C.Name(self:param(1,i)),C.Name(self:value(block_id,position,'t' .. i)))) end
            statements:insert(C.Goto('b1'))
            return C.Block(statements)
        end
        local callee=self:callee_instance(exit.target,block,block_id,position,exit.arguments)
        return C.Return(C.Call(C.Name(callee.name),
            self:call_arguments(callee,block,block_id,position,exit.arguments)))
    elseif B.Trap:isclassof(exit) then
        self.trap=true
        local statements=L()
        statements:insert(C.Evaluate(C.Call(C.Name('let_trap'),L{C.String(exit.reason)})))
        local type_=self:return_shape(self.functions[target_id].signature.results)
        statements:insert(C.Return(type_==C.Void and nil or C.Integer(0,0)))
        return C.Block(statements)
    end
    self:error('no representation for ' .. tostring(exit))
end

-- C names come from the belt: the module initializer and each word entry by its source
-- name, so a reader can tell what a function is without a legend.
local function sanitize(name)
    name=name:gsub('[^%w_]','_')
    if name:match('^%d') then name='w' .. name end
    return name
end

function Emitter:function_name(id)
    local name=self.program.functions[id] and self.program.functions[id].name
    if name=='__module_init' then return 'let_module_init' end
    if name=='__module_unload' then return 'let_module_unload' end
    return 'let_' .. sanitize(name or ('fn_' .. id))
end

-- The signature of an instance, asked through the same rule a call site uses, so the two
-- cannot disagree about what is passed.
function Emitter:function_parameters_for(instance)
    local belt=instance.belt
    local parameters=L()
    for i,parameter in ipairs(belt.blocks[1].parameters) do
        if self:parameter_live(instance.analysis,belt,1,i) then
            parameters:insert(C.Parameter(self:ctype(parameter.type),self:param(1,i-1)))
        end
    end
    return parameters
end

function Emitter:emit_instance(instance)
    local belt,analysis=instance.belt,instance.analysis
    -- A fully folded function has no residual work at all, so its body is the constant it
    -- computes. Nothing inside it is walked: no blocks, no labels, no gotos.
    if analysis.folded then
        local type_=self:return_shape(belt.signature.results)
        local values=L()
        for i,result in ipairs(belt.signature.results) do
            if result~=B.Effect then values:insert(self:constant(analysis.results[i])) end
        end
        local external=self:hosted(instance)
        return C.Function(instance.name,external,external,type_,
            self:function_parameters_for(instance),
            C.Block(L{C.Return(self:return_value(type_,values))}))
    end
    self.current_instance=instance
    self.current=belt
    self.current_id=instance.id
    self.live=analysis.live_blocks
    self.decision=analysis.decision
    -- Consumer demand is a frontend decision: an unneeded pure producer is never
    -- written out, so the emitted C does not rely on a C compiler to delete it.
    -- Ordered operations always carry a demanded effect output and are therefore kept.
    local result=self:return_shape(belt.signature.results)
    local parameters=self:function_parameters_for(instance)
    local body=L()
    -- Non-entry block parameters are assigned only by edges, so they are declared once.
    -- The entry block's packet is the function's ABI and is never pruned.
    for block_id=2,#belt.blocks do
        for i,parameter in ipairs(belt.blocks[block_id].parameters) do
            if self:needed_parameter(block_id,i) then
                body:insert(C.Declare(self:ctype(parameter.type),self:param(block_id,i-1),nil))
            end
        end
    end
    body:insert(C.Goto('b1'))
    for block_id,block in ipairs(belt.blocks) do
        if not self.live[block_id] then goto continue_block end
        body:insert(C.Label('b' .. block_id))
        for index,instruction in ipairs(block.instructions) do
            local position=#block.parameters+index-1
            if self:instruction_runs(analysis,belt,block_id,position,instruction) then
                body:insertall(self:instruction(block,block_id,index,instruction))
            end
        end
        body:insert(self:exit(instance.id,block,block_id,block.exit))
        ::continue_block::
    end
    local external=self:hosted(instance)
    return C.Function(instance.name,external,external,result,parameters,C.Block(body))
end

-- Resources and hosts are foreign code: the emitter declares the symbols it calls, and
-- the embedding supplies the implementations.
function Emitter:host_declarations()
    local declarations=L()
    local names={}
    -- Symbol sources are Lua tables, so sort them: an emitted unit must not depend on
    -- `pairs` order, or two builds of one program would differ byte for byte.
    -- A destructor is declared only when a `Destroy` names it, for the same reason hosts are: a
    -- registered resource the program does not use must not appear in its C.
    local destroys={}
    for symbol in pairs(self.used_destroys) do destroys[#destroys+1]=symbol end
    table.sort(destroys)
    for _,symbol in ipairs(destroys) do
        -- A resource that is a C pointer is destroyed through that pointer; a handle stays an
        -- integer. The representation belongs to the resource, not to the destructor's spelling.
        local type_=self.destroy_pointer[symbol] and C.Pointer(C.Named('void')) or C.I64
        declarations:insert(C.Function(symbol,true,false,C.Void,L{C.Parameter(type_,'a0')},nil))
    end
    local symbols={}
    -- Only a host the program actually calls is declared: a vocabulary may be registered for
    -- names a program does not use, and those must not appear in its C.
    for _,host in pairs(self.used_hosts) do
        if not names[host.symbol] then names[host.symbol]=true; symbols[#symbols+1]=host.symbol end
    end
    table.sort(symbols)
    for _,symbol in ipairs(symbols) do
        local host=self.hosts[symbol]
        -- A declared prototype may name `size_t` or `ptrdiff_t`, so the includes follow the
        -- hosts actually written out, not every registered one.
        if host.c then self.c_hosts=true end
        local parameters=L()
        for i,parameter in ipairs(host.signature.parameters) do
            local spelling=host.c and host.c.params and host.c.params[i]
            local type_
            if spelling then type_=C.Named(spelling)
            else type_=parameter.capability==A.Mut and C.Pointer(self:ctype(parameter.type)) or self:ctype(parameter.type) end
            parameters:insert(C.Parameter(type_,'a' .. i))
        end
        local result=host.signature.results[1]
        local result_type
        if host.c and host.c.result then result_type=C.Named(host.c.result)
        else result_type=result==B.Unit and C.Void or self:ctype(result) end
        declarations:insert(C.Function(host.symbol,true,false,result_type,parameters,nil))
    end
    return declarations
end

function Emitter:helper_declarations()
    local declarations=L()
    if self.text or self.helpers.text_eq or self.helpers.text_from_c then declarations:insert(C.Struct('let_text',L{C.Parameter(C.Pointer(C.Named('char')),'data'),C.Parameter(C.U64,'size')})) end
    declarations:insert(C.Function('let_trap',true,false,C.Void,L{C.Parameter(C.Pointer(C.Named('char')),'reason')},nil))
    local function raw(code) declarations:insert(C.Raw(code)) end
    -- A `char*` the host returns has no length; the Let Text takes its size from the bytes up
    -- to the terminator, which is the contract a C string already implies.
    if self.helpers.text_from_c then raw('static struct let_text let_text_from_c(const char* s){struct let_text t;t.data=(char*)s;t.size=s?(size_t)strlen(s):0;return t;}') end
    -- Signed overflow is undefined in C, so wrapping arithmetic must go through unsigned.
    -- These are one-line and branch-free, so a macro inlines them without adding a function.
    if self.helpers.add then raw('#define LET_ADD(a,b) ((int64_t)((uint64_t)(a)+(uint64_t)(b)))') end
    if self.helpers.sub then raw('#define LET_SUB(a,b) ((int64_t)((uint64_t)(a)-(uint64_t)(b)))') end
    if self.helpers.mul then raw('#define LET_MUL(a,b) ((int64_t)((uint64_t)(a)*(uint64_t)(b)))') end
    if self.helpers.neg then raw('#define LET_NEG(a) ((int64_t)(0-(uint64_t)(a)))') end
    -- A shift count is reduced modulo the width, and a left shift keeps the low bits, so neither
    -- shift is undefined and a huge count is defined rather than a trap.
    if self.helpers.shl then raw('#define LET_SHL(a,b) ((int64_t)((uint64_t)(a) << ((uint64_t)(b) & 63)))') end
    if self.helpers.shr then raw('static int64_t let_shr(int64_t a,int64_t b){unsigned n=(unsigned)((uint64_t)b & 63u);uint64_t u=(uint64_t)a >> n;if(a<0 && n)u|=~(uint64_t)0 << (64u-n);return (int64_t)u;}') end
    -- Division and remainder keep one shared helper each: inlining the trap check at every
    -- site would duplicate control flow rather than remove a function.
    if self.helpers.div then raw('static int64_t let_div(int64_t a,int64_t b){if(b==0)let_trap("division by zero");if(b==-1)return (int64_t)(0-(uint64_t)a);return a/b;}') end
    if self.helpers.rem then raw('static int64_t let_rem(int64_t a,int64_t b){if(b==0)let_trap("remainder by zero");if(b==-1)return 0;return a%b;}') end
    -- The conversion is total (§13.3): a NaN becomes zero and an out-of-range value saturates at
    -- the nearer Int bound, so it needs no effect and can be folded or dropped.
    if self.helpers.to_int then raw('static int64_t let_to_int(double x){if(x!=x)return 0;if(x>=9223372036854775808.0)return INT64_MAX;if(x<-9223372036854775808.0)return INT64_MIN;return (int64_t)x;}') end
    if self.helpers.text_eq then raw('#define LET_TEXT_EQ(a,b) ((a).size==(b).size&&memcmp((a).data,(b).data,(size_t)(a).size)==0)') end
    return declarations
end

-- What was emitted, for a caller that wants to know rather than guess: one entry per
-- instance, with the ABI it ended up with, and how stable the analysis that produced it was.
-- `widened` counts packet fields the fixed point had to forget, which is the honest measure of
-- how much precision a loop cost.
function Emitter:report(statistics)
    statistics.instances={}
    local specialized,folded,widened=0,0,0
    for _,instance in ipairs(self.pending) do
        local analysis=instance.analysis
        local parameters={}
        for i,parameter in ipairs(instance.belt.blocks[1].parameters) do
            if self:parameter_live(analysis,instance.belt,1,i) then
                parameters[#parameters+1]=tostring(parameter.type)
            end
        end
        local blocks=0
        for _ in pairs(analysis.live_blocks or {}) do blocks=blocks+1 end
        local forgotten=0
        for _ in pairs(analysis.widened or {}) do forgotten=forgotten+1 end
        widened=widened+forgotten
        if not instance.generic then specialized=specialized+1 end
        if analysis.folded then folded=folded+1 end
        statistics.instances[#statistics.instances+1]={name=instance.name,id=instance.id,
            generic=instance.generic,folded=analysis.folded==true,parameters=parameters,
            blocks=blocks,widened=forgotten}
    end
    -- What the host must pass, which only the emitter knows: a field whose fate is not `value`
    -- is not a parameter -- a constant is materialized inside the entry -- so the fields the host
    -- supplies are those the signature kept, in their own order, followed by the stages.
    statistics.entries={}
    for _,entry in ipairs(self.options.entries or {}) do
        local instance=self.generic[entry.id]
        local fields,stages={},0
        if instance then
            local belt=instance.belt
            -- The entry's parameters are its effect first, then the fields, then the stages.
            for i=1,entry.bundle do
                if self:parameter_live(instance.analysis,belt,1,i+1) then fields[#fields+1]=i-1 end
            end
            -- The same rule for the stages: one the body never reads is not in the signature, so
            -- the host does not supply it. A generic instance never has a *constant* parameter, so
            -- a stage left out here is one nothing reads.
            for i=entry.bundle+1,#belt.blocks[1].parameters-1 do
                if self:parameter_live(instance.analysis,belt,1,i+1) then stages=stages+1 end
            end
        end
        statistics.entries[#statistics.entries+1]={name=entry.name,id=entry.id,
            c_name=instance and instance.name or nil,fields=fields,stages=stages}
    end
    statistics.specialized=specialized
    statistics.folded=folded
    statistics.widened=widened
    statistics.functions=#self.pending
    return statistics
end

function Emitter:program(program,options)
    self.statics=L()
    self.program=program
    self.functions=program.functions
    -- Symbols to declare and call, from the top-level hosts and from any namespace member that
    -- is a host (`c.puts`).
    self.hosts={}
    for _,host in pairs(options.hosts or {}) do self.hosts[host.symbol]=host end
    for _,descriptor in pairs(options.resources or {}) do
        self.destroy_pointer[descriptor.destroy]=descriptor.representation=='pointer'
    end
    for _,namespace in pairs(options.dictionary or {}) do
        for _,member in pairs(namespace.members or {}) do
            if member.signature then self.hosts[member.symbol]=member end
        end
    end
    -- One shared run: an instance is analysed once and reused by every call site that asks
    -- for the same entry packet.
    self.run=Known.run(program,options)
    -- Which entries the host publishes. The host selects (§15.1); a command-line compiler is a
    -- host that selects every exported word, and says so by passing them.
    self.host_ids={}
    for _,entry in ipairs(options.entries or {}) do self.host_ids[entry.id]=true end
    -- The module interface is the root of the instance graph, and emission discovers the rest
    -- by writing the calls it finds -- which is the same discovery that decides liveness.
    self:generic_instance(1)
    self:generic_instance(2)
    -- A host entry has no caller inside the belt, so nothing would make it live: the entries the
    -- program publishes as its host interface are roots, like the module interface itself.
    for _,entry in ipairs(options.entries or {}) do self:generic_instance(entry.id) end
    local functions=L()
    local at=1
    while self.pending[at] do
        functions:insert(self:emit_instance(self.pending[at]))
        at=at+1
    end
    if options.statistics then self:report(options.statistics) end
    local host_declarations=self:host_declarations()
    local helpers=self:helper_declarations()
    -- A host that declares its C prototype may name `size_t` or `ptrdiff_t` (§15.3); a program
    -- that does not keeps the smaller include set.
    local includes=L()
    if self.c_hosts then includes:insert('stddef.h') end
    includes:insert('stdint.h'); includes:insert('stdbool.h')
    if self.text and (self.helpers.text_eq or self.helpers.text_from_c) then includes:insert('string.h') end
    if self.math then includes:insert('math.h') end
    local declarations=L()
    declarations:insertall(helpers)
    declarations:insertall(self.statics)
    for _,struct in ipairs(self.structs) do declarations:insert(struct) end
    for _,struct in ipairs(self.results) do declarations:insert(struct) end
    declarations:insertall(host_declarations)
    for _,instance in ipairs(self.pending) do
        declarations:insert(C.Function(instance.name,self:hosted(instance),self:hosted(instance),
            self:return_shape(instance.belt.signature.results),
            self:function_parameters_for(instance),nil))
    end
    declarations:insertall(functions)
    return C.Unit(includes,declarations)
end

function B.Program:emit(options)
    options=options or {}
    local emitter=Emitter.new(options)
    return emitter:program(self,options)
end
end
