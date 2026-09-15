-- Program construction: one advancement protocol for persistent specialization and
-- transient invocation. See WORDS.md. Word values are SSA bundles (Belt.Word); a
-- statically known template's terminal becomes a belt function reached by CallFunction.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local Build=V.Build; local Context=Build.Context
local expect,fail,gap,copy=Build.expect,Build.fail,Build.gap,Build.copy
local literal=require('let.literal')

local Builder={}; Builder.__index=Builder

local function typekey(type_)
    if B.Aggregate:isclassof(type_) then
        local parts={} for _,member in ipairs(type_.members) do parts[#parts+1]=typekey(member) end
        return 'aggregate(' .. table.concat(parts,',') .. ')'
    end
    if B.Word:isclassof(type_) then
        local parts={} for _,field in ipairs(type_.fields) do parts[#parts+1]=typekey(field) end
        return 'word(' .. tostring(type_.is_copy) .. ';' .. table.concat(parts,',') .. ')'
    end
    if B.Address:isclassof(type_) then return 'address(' .. typekey(type_.pointee) .. ')' end
    if B.Borrow:isclassof(type_) then return 'borrow(' .. tostring(type_.stable) .. typekey(type_.pointee) .. ')' end
    if B.Named:isclassof(type_) then return 'named(' .. type_.name .. ')' end
    return tostring(type_)
end

function Builder.new(ast,resolved,options)
    return setmetatable({ast=ast,resolved=resolved,options=options or {},
        layouts={},functions={false,false},entries={},templates={}},Builder)
end

function Builder:types()
    local types={Int=B.Int,Float=B.Float,Bool=B.Bool,Unit=B.Unit,Text=B.Text}
    for name,descriptor in pairs(self.options.resources or {}) do
        assert(type(descriptor.destroy)=='string' and descriptor.destroy:match('^[A-Za-z_][A-Za-z0-9_]*$'),'resource requires a destructor symbol')
        types[name]=B.Named(name)
    end
    return types
end

-- Template layout: captures first, then items in source order, so field order equals
-- the order in which advancement produces them.
function Builder:layout(template)
    local cached=self.layouts[template.id]
    if cached then return cached end
    local items={}
    for index,item in ipairs(template.source.items) do
        if A.Stage:isclassof(item) then
            items[index]={kind='stage',name=item.name,capability=item.capability,constraint=item.constraint,span=item.span}
        else
            local binding=item.binding
            items[index]={kind='prelude',name=binding.name,mutable=binding.mutable,span=binding.span,definition=self.resolved.bindings[binding]}
        end
    end
    local captures={}
    for _,definition in ipairs(template.captures) do
        captures[#captures+1]={name=definition.name,span=definition.node.span}
    end
    local steps={}
    for _,step in ipairs(template.steps) do
        steps[#steps+1]={index=step.index,prepare=step.prepare,item=items[step.index],stage=step.stage}
    end
    cached={captures=captures,items=items,steps=steps,initial=template.initial}
    self.layouts[template.id]=cached
    return cached
end

-- A word bundle is immutable construction state: advancing clones it so that the
-- original receiver keeps its own stage count and field list (§5.2).
local function clone_word(word)
    local fields={} for i,field in ipairs(word.fields) do fields[i]=field end
    return {template=word.template,fields=fields,supplied=word.supplied}
end
local function copyable_fields(fields)
    for _,field in ipairs(fields) do
        if field.mutable or not field.type:copyable() then return false end
    end
    return true
end

function Builder:pack(ctx,word)
    local declared,refs=L(),L()
    for _,field in ipairs(word.fields) do
        declared:insert(B.Field(field.name,field.type,field.mutable)); refs:insert(ctx:ref(field.value))
    end
    local copy=copyable_fields(word.fields)
    local type_=B.Word(word.template.id,word.supplied,declared,copy)
    local value=ctx:emit(B.Construct(refs,copy),L{type_})
    value.word=word; value.mode='fresh'
    return value
end

-- Build one prelude binding: its initializer runs exactly once per instance, in the
-- caller's region, when advancement reaches it.
-- §5.4: a prelude reached by construction belongs to the constructed word, but one reached
-- while transiently saturating an invocation is an invocation local that the activation
-- destroys. The destination decides which, exactly like a supplied stage.
function Builder:prepare(ctx,word,layout,range,destination)
    if not range or range.last<range.first then return end
    for index=range.first,range.last do
        local item=layout.items[index]
        if item and item.kind=='prelude' then
            local value=self:value_of_binding(ctx,item.definition)
            local owned=not value.type:copyable() and not value.word
            ctx:force_bind(item.name,value,item.mutable,owned,false,false,item.span)
            word.fields[#word.fields+1]={name=item.name,definition=item.definition,value=value,type=value.type,
                mutable=item.mutable,owned=owned,retained=destination==B.Persistent,span=item.span}
        end
    end
end

-- The ambient destination for construction work: a word being built as the callee of an
-- invocation is constructed transiently, everything else is constructed persistently.
function Builder:destination() return self.construction_destination or B.Persistent end

function Builder:value_of_binding(ctx,definition)
    local binding=definition.node
    if #binding.value.items==0 and A.Data:isclassof(binding.value.terminal) then
        return binding.value.terminal.value:build(ctx)
    end
    return self:instantiate(ctx,definition)
end

function Builder:instantiate(ctx,definition)
    local template=definition.template
    local layout=self:layout(template)
    local word={template=template,fields={},supplied=0}
    ctx:push(); ctx:retain()
    local function captures()
        for _,capture in ipairs(layout.captures) do
            local id=ctx:find(capture.name)
            local binding=ctx.fn.bindings[id]
            local value,borrows
            if binding.address then
                -- §10.1: a non-escaping word captures an owned binding as a read borrow, and
                -- a borrow of a value is the owner's storage. The word therefore holds the
                -- owner's address, and invoking through it mutates the owner in place.
                local address=ctx.cells[id].value
                value=ctx:emit(B.BorrowPlace(ctx:ref(address),binding.lifetime=='module'),
                    L{B.Borrow(address.type.pointee,binding.lifetime=='module')},capture.span)
                value.mode='borrow'
                borrows={id}
            else
                value=ctx:read(capture.name,capture.span)
                if not value.type:copyable() then
                    gap(capture.span,'a non-Copy capture needs the owner to be a place')
                end
            end
            word.fields[#word.fields+1]={name=capture.name,value=value,type=value.type,
                mutable=binding.mutable,owned=false,retained=true,span=capture.span,borrows=borrows}
        end
        for _,field in ipairs(word.fields) do
            -- Every field the word already has, including a mutable one, which is a place for the
            -- same reason a stage is: its binding is its address.
            local address=(B.Address:isclassof(field.value.type) or B.Borrow:isclassof(field.value.type)) and field.value or false
            ctx:force_bind(field.name,field.value,field.mutable,field.owned,false,address,field.span)
        end
    end
    local ok,result=pcall(function()
        captures()
        self:prepare(ctx,word,layout,layout.initial,self:destination())
        if #layout.steps==0 then
            local data=self:terminal_value(ctx,template)
            if data then return data end
        end
        return self:pack(ctx,word)
    end)
    ctx:pop()
    if not ok then error(result,0) end
    return result
end

function Builder:self_value(ctx,definition)
    local template=definition.template
    local layout=self:layout(template)
    local word={template=template,fields={},supplied=0}
    ctx:push(); ctx:retain()
    for _,capture in ipairs(layout.captures) do
        local value=ctx:read(capture.name,capture.span)
        if not value.type:copyable() then gap(capture.span,'non-Copy lexical captures (ownership/borrow capture of §10.1)') end
        word.fields[#word.fields+1]={name=capture.name,value=value,type=value.type,mutable=false,owned=false,retained=true,span=capture.span}
    end
    local result=self:pack(ctx,word)
    ctx:pop()
    return result
end

-- Advancing a word by one stage, whatever the value came from: an argument a call site built,
-- or a parameter a host entry was handed. There is one implementation of this, because two
-- would disagree about which stage is next and which preludes belong to it.
function Builder:advance(ctx,value,supplied,span,destination,complete)
    if not value.word then fail(span,'specialization requires a word value') end
    local word=clone_word(value.word)
    local layout=self:layout(word.template)
    local step=layout.steps[word.supplied+1]
    if not step then fail(span,'oversaturated specialization: the terminal already has every stage') end
    local item=step.item
    if supplied.word and not supplied.type:copyable() then
        gap(span,'word-valued stages')
    end
    local _,temporary=item.capability:bind_argument(supplied,destination,function(message) fail(span,message) end)
    if temporary then gap(span,'transient read borrow of owned state') end
    -- A mutable stage is a place, so its argument is the declared type's address and the
    -- constraint describes what that place contains.
    local mut=item.capability==A.Mut
    -- A mutable stage is a place, so what its constraint describes is the place's contents,
    -- not the borrow that reaches them.
    local type_=ctx:constraint(item.constraint,mut and supplied.type.pointee or supplied.type,span)
    if type_ then
        if mut then expect({type=supplied.type.pointee,origin=supplied.origin},type_,span)
        else expect(supplied,type_,span) end
    end
    if (item.capability==A.Own or item.capability==A.OwnMut) and ctx:borrows(supplied.type) then
        gap(span,'passing a word that borrows enclosing state to an ownership-taking stage')
    end
    local owned=not supplied.type:copyable() and (item.capability==A.Own or item.capability==A.OwnMut)
    -- Advancement happens in a scope holding every field the word already has. Earlier steps
    -- closed their own scopes, so without this a prelude reached at this stage could not see
    -- a prelude reached at an earlier one.
    ctx:push()
    -- A hand-off scope does not release what it bound: a call site's fields go to the callee's
    -- entry, which owns them, and a specialization's go into the word bundle. Every advancing
    -- step hands off, including a `complete` step that runs the terminal here.
    ctx:retain()
    local ok,result=pcall(function()
        for _,field in ipairs(word.fields) do
            -- Every field the word already has, including a mutable one, which is a place for the
            -- same reason a stage is: its binding is its address, not a copy of the borrow.
            local address=(B.Address:isclassof(field.value.type) or B.Borrow:isclassof(field.value.type)) and field.value or false
            ctx:force_bind(field.name,field.value,field.mutable,field.owned,false,address,field.span)
        end
        -- A mutable stage is a place, exactly as it is in an entry: `build_entry` binds it as its
        -- address, so the preludes here and a host entry's terminal must see the same thing.
        local address=(B.Address:isclassof(supplied.type) or B.Borrow:isclassof(supplied.type)) and supplied or false
        ctx:force_bind(item.name,supplied,owned or item.capability==A.Mut or item.capability==A.OwnMut,owned,false,address,item.span)
        word.fields[#word.fields+1]={name=item.name,value=supplied,type=supplied.type,mutable=item.capability==A.Mut or item.capability==A.OwnMut,
            owned=owned,retained=destination==B.Persistent,span=item.span,capability=item.capability}
        word.supplied=word.supplied+1
        self:prepare(ctx,word,layout,step.prepare,destination)
        if word.supplied==#layout.steps then
            -- Everything the word needs is bound right here and nowhere else: the bindings made
            -- above are discarded when this call returns, so a caller that wants to run the
            -- terminal does it now, through `complete`.
            if complete then return complete(ctx,word) end
            local data=self:terminal_value(ctx,word.template)
            if data then return data end
        end
        return self:pack(ctx,word)
    end)
    ctx:pop()
    if not ok then error(result,0) end
    return result
end

-- The value of a data terminal. A file chain with no written terminal is data too: its
-- value is the named record of its own prelude bindings, which is the module namespace.
function Builder:terminal_value(ctx,template)
    local terminal=template.source.terminal
    if terminal==nil then return self:namespace_record(ctx,template) end
    if A.Data:isclassof(terminal) then return terminal.value:build(ctx) end
    return nil
end

function Builder:namespace_record(ctx,template)
    local values,fields=L(),{}
    for _,item in ipairs(template.source.items) do
        if A.Prelude:isclassof(item) then
            local id=ctx:find(item.binding.name)
            local value=ctx.cells[id].value
            values:insert(value)
            fields[#fields+1]={name=item.binding.name,type=value.type,mutable=item.binding.mutable}
        end
    end
    return ctx:construct_record(values,fields,template.source.span)
end

function Builder:specialize(ctx,expression)
    local value=expression.word:build(ctx)
    if value.conversion then return ctx:convert(value.conversion,expression.argument,expression.span) end
    -- `import` is a construction entry: the named file's chain is constructed here, and the
    -- arguments that follow specialize it like any other word.
    if value.construction=='import' then
        local file=ctx.resolved.imports[expression]
        if not file then fail(expression.span,'unresolved import') end
        return self:instantiate(ctx,{template=ctx.resolved.chains[file]})
    end
    if not value.word then
        -- Adjacent statements juxtapose: `f() g()` is a specialization whose receiver is an
        -- invocation. That is legal shape, illegal meaning, and almost always a missing `;`.
        if A.Invoke:isclassof(expression.word) then
            fail(expression.span,'an invocation cannot be specialized: separate the two statements with ";"')
        end
        fail(expression.span,'specialization requires a word value')
    end
    -- The receiver is unchanged. A Copy receiver is copied; a fresh receiver transfers
    -- its state; an existing non-Copy receiver needs explicit independent-copy vocabulary.
    if value.mode=='borrow' then
        fail(expression.span,'specialization of an existing non-copyable word requires an explicit independent copy')
    end
    return self:supply(ctx,value,expression.argument,self:destination())
end

-- The call-site spelling of advancement: build the argument, then hand it to `advance`.
function Builder:supply(ctx,value,argument,destination)
    return self:advance(ctx,value,argument:build(ctx),argument.span,destination,nil)
end

-- The belt function for one field packet. `fields` is the packet the word already carries
-- ({type,capability,mutable,retained,owned}), which is the shape `build_entry` consumes, so
-- callers do not unpack it into parallel arrays only to have it repacked here.
function Builder:entry_function(template,fields)
    local parts={tostring(template.id)}
    for _,field in ipairs(fields) do parts[#parts+1]=typekey(field.type) end
    for _,field in ipairs(fields) do parts[#parts+1]=field.retained and '1' or '0' end
    for _,field in ipairs(fields) do parts[#parts+1]=field.owned and '1' or '0' end
    local key=table.concat(parts,'|')
    local existing=self.entries[key]
    if existing then return existing end
    local id=#self.functions+1
    -- Cached before the build: an entry that recurses must find itself, or it would be built twice
    -- and its callers would disagree about its signature.
    self.entries[key]=id
    self.functions[id]=false
    self.functions[id]=self:build_entry(template,fields,id)
    return id
end

-- An entry binds its parameters and runs whatever preludes lie between them. For a saturated
-- entry the call site already ran every prelude, so `supplied` is every stage and the parameters
-- are the word's fields. For a host entry the word is part way through: the parameters are its
-- captures and the items it already has, then the stages it has left, and the preludes belonging
-- to those stages run here because nobody else can run them.
function Builder:build_entry(template,fields,id)
    local layout=self:layout(template)
    local names={}
    local index=1
    for _,capture in ipairs(layout.captures) do names[index]=capture.name; index=index+1 end
    for _,item in ipairs(layout.items) do names[index]=item.name; index=index+1 end
    local ctx=Context.new_function{name=(template.name or 'word') .. '_' .. id,span=template.source.span,
        resources=self.options.resources,hosts=self.options.hosts,types=self:types(),
        builder=self,resolved=self.resolved,function_id=id}
    local fn=ctx.fn
    fn.template=template
    local records={}
    for i,field in ipairs(fields) do
        ctx:push(); if field.retained then ctx:retain() end
        local value=ctx:parameter(field.type,A.Read)
        -- A mutable stage arrives as an address, so the field is that place, not a copy.
        local address=(B.Address:isclassof(field.type) or B.Borrow:isclassof(field.type)) and value or false
        -- A prelude the call site built carries ownership even though it has no stage
        -- capability: the entry it is handed to is where it dies.
        local owned=not address and not field.type:copyable()
            and (field.owned or field.capability==A.Own or field.capability==A.OwnMut)
        local binding=ctx:force_bind(names[i],value,field.mutable,owned,false,address,template.source.span)
        records[i]={field=field,id=binding,value=value}
    end
    if template.self then ctx.self_name=template.self.name; ctx.self_definition=template.self end
    ctx.finish=function(self_,value,span)
        -- §10.1: the storage this word borrowed belongs to this activation, so the word
        -- cannot leave it.
        if self_:borrows(value.type) then
            fail(span,'a word that borrows activation state cannot be returned from the invocation that owns it')
        end
        self_:accept_owned(value,span)
        if self_.fn.result then expect(value,self_.fn.result,span) else self_.fn.result=value.type end
        self_:pin(value)
        local updated={}
        for _,record in ipairs(records) do
            -- A place is written back by the callee itself, so it is not a result.
            if record.field.mutable and record.field.retained and not B.Address:isclassof(record.field.type) then
                updated[#updated+1]=self_:ref(self_.cells[record.id].value)
            end
        end
        self_:cleanup()
        local values=L{self_:ref(value)}; values:insertall(updated); values:insert(self_:ref(self_.effect))
        self_.block.exit=B.Return(values); self_:unpin()
    end
    for _,record in ipairs(records) do
        if record.field.mutable and record.field.retained then ctx.mutable_state=true end
    end
    -- The word's own state lives in the field scopes above; its body's locals are
    -- activation state and must be destroyed by the return, so they get their own scope
    -- rather than landing in whichever field scope happens to be current.
    ctx:push()
    ctx:statements(template.source.terminal.statements)
    if not ctx.block.exit then
        ctx:finish(ctx:emit(B.UnitLiteral,L{B.Unit},template.source.span),template.source.span)
    end
    local blocks=L()
    for _,block in ipairs(fn.blocks) do assert(block.exit,'unfinished block'); blocks:insert(B.Block(block.parameters,block.instructions,block.exit)) end
    local results=L{fn.result}
    for _,record in ipairs(records) do
        if record.field.mutable and record.field.retained and not B.Address:isclassof(record.field.type) then
            results:insert(record.field.type)
        end
    end
    results:insert(B.Effect)
    return B.Function(fn.name,B.Signature(blocks[1].parameters,results),blocks)
end

function Builder:invoke(ctx,expression,tail)
    -- A callee that is constructed at this site is built transiently, because its reached
    -- preludes are invocation locals (§5.4); a named or projected word already has an owner.
    local inline=not (A.Name:isclassof(expression.word) or A.Project:isclassof(expression.word))
    local previous=self.construction_destination
    if inline then self.construction_destination=B.Transient end
    local callee=expression.word:build(ctx)
    self.construction_destination=previous
    if callee.conversion then
        if #expression.arguments~=1 then fail(expression.span,'a conversion takes exactly one argument') end
        local result=ctx:convert(callee.conversion,expression.arguments[1],expression.span)
        if tail then ctx:finish(result,expression.span); return nil end
        return result
    end
    if callee.host then
        if tail then ctx:finish(ctx:call(expression,true),expression.span) else return ctx:call(expression,false) end
        return
    end
    if not callee.word then fail(expression.span,'invocation requires a runtime word') end
    local origin=callee.origin
    -- The receiver's own bundle: transient stages are appended to a clone, and only
    -- interior mutable state may be written back into this original.
    local original=callee.word
    -- Transient saturation: each argument binds one stage, and the preludes it reaches
    -- run before the next argument is evaluated (§6.2).
    ctx:push(); ctx:retain()
    local ok,result=pcall(function()
        local value=callee
        for _,argument in ipairs(expression.arguments) do value=self:supply(ctx,value,argument,B.Transient) end
        local word=clone_word(assert(value.word,'invocation of a saturated data terminal'))
        local layout=self:layout(word.template)
        if word.supplied~=#layout.steps then fail(expression.span,'invocation must exactly saturate remaining stages') end
        -- The fields are kept as *values*, not as references. A reference is a distance from the
        -- instruction that carries it, so building one before this block emits anything else --
        -- and `cleanup` below emits destroys -- would make it mean a different producer.
        local field_values=L()
        for _,field in ipairs(word.fields) do field_values:insert(field.value) end
        local target=self:entry_function(word.template,word.fields)
        if tail then
            -- §6.5: the *caller's* own word state is not a local, so it must survive the
            -- transfer. Carrying it through the tail result needs address-taken state.
            if ctx.mutable_state then gap(expression.span,'tail invocation from a word with mutable state') end
            -- §6.5: a tail transfer retires this activation, so a place this activation owns
            -- cannot be passed. Only a borrow of module storage would survive, and the type
            -- does not distinguish that, so any borrow is conservative here.
            for _,field in ipairs(word.fields) do
                if ctx:borrows(field.type) then
                    fail(expression.span,'tail invocation borrow does not outlive caller cleanup')
                end
            end
            local callee=self.functions[target]
            if callee and #callee.signature.results>2 then
                local borrowed=false
                for _,field in ipairs(word.fields) do
                    if B.Address:isclassof(field.type) then borrowed=true end
                end
                if borrowed then
                    gap(expression.span,'tail invocation of a captured word: its state must be written back, which a tail transfer cannot do')
                end
                gap(expression.span,'tail invocation of a word whose state belongs to the retiring activation')
            end
            -- A function whose only exit is a tail call takes its result type from the callee.
            -- A function whose only exit is a tail call takes its result type from the callee.
            if not ctx.fn.result then
                if callee and callee.signature then
                    ctx.fn.result=callee.signature.results[1]
                else
                    -- A self tail transfer: the result is the word's own, which a return states.
                    local peeked=ctx:peek_result_type()
                    if not peeked then gap(expression.span,'result type of a word whose only exit is a self tail call') end
                    ctx.fn.result=peeked
                end
            end
            ctx:cleanup()
            ctx.block.exit=B.TailCall(target,ctx:ref(ctx.effect),ctx:refs(field_values))
            return nil
        end
        local callee=self.functions[target]
        local result_type
        if callee and callee.signature then
            result_type=callee.signature.results[1]
        elseif target==ctx.function_id then
            -- A direct self call: the entry is still being built, and a recursive call returns
            -- whatever this word returns. A return states that type, but construction is source
            -- ordered, so ask the returns directly when the fixing return is not built yet.
            result_type=ctx.fn.result or ctx:peek_result_type()
            if not result_type then
                gap(expression.span,'the result type of a recursive call must be fixed by another return in the same word')
            end
        else
            gap(expression.span,'the result type of a recursive call must be fixed by another return in the same word')
        end
        local types=L{result_type}
        for i,field in ipairs(word.fields) do if field.mutable and field.retained then types:insert(field.type) end end
        types:insert(B.Effect)
        local results={ctx:emit(B.CallFunction(target,ctx:ref(ctx.effect),ctx:refs(field_values)),types,expression.span)}
        ctx.effect=results[#results]
        -- §3.4: an invocation is a specialization atom. A Word-typed result names its template and
        -- supplied count, and its fields are the members of what the callee returned, so the word
        -- identity survives the call. Copy only: an owned word crossing a call boundary needs the
        -- ownership rules for that stated first, and says so rather than being guessed at.
        if B.Word:isclassof(result_type) then
            if not result_type.is_copy then
                gap(expression.span,'a returned word with owned state needs ownership vocabulary')
            end
            local template
            for _,candidate in ipairs(self.resolved.templates) do
                if candidate.id==result_type.template then template=candidate end
            end
            if not template then gap(expression.span,'unresolved word template ' .. tostring(result_type.template)) end
            local fields={}
            for i,field in ipairs(result_type.fields) do
                fields[i]={name=field.name,type=field.type,mutable=field.mutable,owned=false,retained=false,
                    span=expression.span,
                    value=ctx:emit(B.LoadField(ctx:ref(results[1]),i-1),L{field.type},expression.span)}
            end
            local rebuilt=copy(results[1])
            rebuilt.word={template=template,fields=fields,supplied=result_type.supplied}
            rebuilt.mode='fresh'
            results[1]=rebuilt
        end
        -- Only interior mutable state is written back, and only into the receiver's
        -- existing bundle. A transient specialization of a partial word must not
        -- replace that binding with a saturated one.
        local updated=original
        local changed=false
        local at=2
        for i,field in ipairs(word.fields) do
            if field.mutable and field.retained and i<=#original.fields then
                if not changed then
                    updated=clone_word(original); changed=true
                end
                local replaced={} for key,value in pairs(updated.fields[i]) do replaced[key]=value end
                replaced.value=results[at]; updated.fields[i]=replaced; at=at+1
            end
        end
        if changed then
            -- Interior state must be written back to its owner. A projected word member has
            -- no writable place of its own yet, so its state update would be silently lost.
            if not origin then gap(expression.span,'invoking a projected word member with mutable state') end
            local packed=self:pack(ctx,updated)
            local binding=ctx.fn.bindings[origin]
            if binding.address then
                -- The owner's record is a place: write the updated record back into it, which
                -- is what lets a captured word share its state with the capture's owner.
                ctx:ordered(B.Store(ctx:ref(ctx.effect),ctx:ref(ctx.cells[origin].value),ctx:ref(packed)),nil,expression.span)
            else
                ctx.cells[origin]={value=packed,initialized=true,alive=binding.owned,moved={}}
            end
        end
        local result=results[1]; result.mode=result.type:copyable() and 'copy' or 'fresh'; result.origin=origin
        return result
    end)
    ctx:pop()
    if not ok then error(result,0) end
    return result
end

-- §15.1: the module initializer constructs the namespace, and the module's owned state
-- lives until unload. Both are returned: the namespace is what the host projects, and the
-- state is the owner, destroyed once by the unload function in reverse successful-
-- construction order. One owner avoids the namespace and the state each destroying the same
-- value; a written terminal that moves an owned prelude into the namespace only changes what
-- the host can *see*, not who destroys it.
function Builder:build_module()
    local file=self.ast.file
    local ctx=Context.new_function{name='__module_init',span=file.span,state=nil,
        resources=self.options.resources,hosts=self.options.hosts,types=self:types(),
        builder=self,resolved=self.resolved,lifetime='module'}
    local fn=ctx.fn
    local order,ids,fields=L(),L(),L()
    for index,item in ipairs(file.items) do
        if A.Stage:isclassof(item) then item:bind_parameter(ctx,index,self.options)
        else
            A.Local(item.binding,item.binding.span):build(ctx)
            local id=ctx:find(item.binding.name)
            -- The binding id is recorded, not its value handle: the terminal body may split
            -- the CFG, and a prelude's current value is then the block parameter that carried
            -- it, which only the context at the return point knows. The state keeps the
            -- binding's construction position, which is what destruction order needs.
            ids:insert(id)
            order:insert(item.binding.name)
            fields:insert({name=item.binding.name,type=ctx.cells[id].value.type,mutable=item.binding.mutable})
        end
    end
    -- The current value of each prelude binding, asked where the state record is built.
    local function state_values(target)
        local values=L()
        for _,id in ipairs(ids) do values:insert(target.cells[id].value) end
        return values
    end
    -- Module bindings live until module unload, not until initialization returns, so a
    -- borrow of module storage outlives any value that holds it.
    ctx.scopes[1].retained=true
    self.module_order=order
    local namespace
    if file.terminal==nil then
        -- The common case: the namespace is exactly the prelude record, so it is its own
        -- state and there is nothing to duplicate.
        local state=ctx:construct_record(state_values(ctx),fields,fn.span)
        self.module_exports=self:export_map(fields)
        -- A field that is a word is a host entry point: the namespace holds it, and the host
        -- invokes it by supplying its remaining stages. Recorded here, where the preludes are
        -- still values rather than references.
        self.exports={}
        for i,field in ipairs(fields) do
            if B.Word:isclassof(field.type) then
                self.exports[#self.exports+1]={name=field.name,value=ctx.cells[ids[i]].value,span=fn.span}
            end
        end
        ctx:finish_pair(state,state,fn.span)
    elseif A.Data:isclassof(file.terminal) then
        ctx.module_preludes={}
        for _,item in ipairs(file.items) do
            if A.Prelude:isclassof(item) then ctx.module_preludes[ctx:find(item.binding.name)]=true end
        end
        namespace=file.terminal.value:build(ctx)
        ctx.module_preludes=nil
        local state=ctx:construct_record(state_values(ctx),fields,fn.span)
        self.module_exports=self:export_map(namespace.type)
        ctx:finish_pair(namespace,state,fn.span)
    else
        -- A written do terminal is the initialization body; its return is the namespace.
        -- The module's preludes are still the module's own state, so the body's return is
        -- paired with the state record rather than being returned as the state, and the
        -- same pairing is installed for every return inside the body.
        ctx.module_preludes={}
        for _,item in ipairs(file.items) do
            if A.Prelude:isclassof(item) then ctx.module_preludes[ctx:find(item.binding.name)]=true end
        end
        fn.module_pending=function(target,namespace,span)
            -- The restriction applies to the namespace the body produced; the state record
            -- is where untouched preludes belong, exactly as for a written terminal.
            target.module_preludes=nil
            local state=target:construct_record(state_values(target),fields,span)
            target:finish_pair(namespace,state,span)
        end
        -- The body's own locals are activation state, not module state: they live in their
        -- own scope so that the return destroys them, while the preludes stay retained.
        ctx:push()
        ctx:statements(file.terminal.statements)
        if not ctx.block.exit then
            fn.module_pending(ctx,ctx:emit(B.UnitLiteral,L{B.Unit},fn.span),fn.span)
        end
        fn.module_pending=nil
        ctx.module_preludes=nil
        if not ctx.block.exit then ctx:pop() end
        self.module_exports=self:export_map(ctx.fn.result)
    end
    return self:module_function(fn,'__module_init')
end

-- A host projects exports by index, so record the mapping instead of making it guess.
function Builder:export_map(source)
    local exports={}
    if B.Aggregate:isclassof(source) then
        for i,field in ipairs(source.fields) do if field.name then exports[field.name]=i-1 end end
    elseif type(source)=='table' then
        for i,field in ipairs(source) do if field.name then exports[field.name]=i-1 end end
    end
    return exports
end

function Builder:module_function(fn,label)
    local blocks=L()
    for _,block in ipairs(fn.blocks) do assert(block.exit,'unfinished block'); blocks:insert(B.Block(block.parameters,block.instructions,block.exit)) end
    local results=L{fn.result,fn.state}
    results:insert(B.Effect)
    return B.Function(label,B.Signature(blocks[1].parameters,results),blocks)
end

-- §15.1: destroy the module's owned state in reverse successful-construction order. The
-- state record's members are already in construction order, so destroying it is the whole
-- function; a record destroys its own contents in reverse (§8.5).
function Builder:build_unload(state_type)
    local ctx=Context.new_function{name='__module_unload',span=self.ast.file.span,
        resources=self.options.resources,hosts=self.options.hosts,types=self:types(),
        builder=self,resolved=self.resolved}
    local fn=ctx.fn
    ctx:destroy(ctx:parameter(state_type),fn.span)
    ctx:finish(ctx:emit(B.UnitLiteral,L{B.Unit},fn.span),fn.span)
    local blocks=L()
    for _,block in ipairs(fn.blocks) do assert(block.exit,'unfinished block'); blocks:insert(B.Block(block.parameters,block.instructions,block.exit)) end
    return B.Function(fn.name,B.Signature(blocks[1].parameters,L{fn.result,B.Effect}),blocks)
end

-- What a stage's capability requires of the value that satisfies it. A source argument is
-- checked against this; a host entry *is* it, since the entry's signature is the host's contract.
-- A mutable stage is a place reached through a borrow, and an owned stage arrives fresh.
function Builder:host_parameter(ctx,capability,type_,span)
    if capability==A.Mut or capability==A.OwnMut then
        local placed=ctx:parameter(B.Borrow(type_,false),A.Read)
        placed.mode=capability==A.Mut and 'mut' or 'fresh'
        return placed
    end
    local value=ctx:parameter(type_,A.Read)
    if capability==A.Own then value.mode='fresh' end
    return value
end

-- The host's way into an exported word: its first arguments are the word's own fields -- the
-- construction trace so far, which the host reads from the namespace -- and the stages it still
-- needs follow. Advancing uses the same protocol a call site uses, so nothing here decides which
-- stage is next or which preludes belong to it: `advance` already knows, because it does it for
-- call sites every day.
function Builder:host_entry(name,value,span)
    local word=value.word
    if not word then return nil,'not a word value' end
    local template=word.template
    local layout=self:layout(template)
    -- Decide before allocating anything: a stage whose type only an argument can determine means
    -- there is no signature to publish, and leaving a hole in the function list would be worse
    -- than having no entry.
    local resolve=Context.new_function{name='resolve',span=span,types=self:types(),
        hosts=self.options.hosts,resolved=self.resolved}
    local stages,items={},{}
    for i=word.supplied+1,#layout.steps do
        local item=layout.steps[i].item
        local type_=resolve:constraint(item.constraint,nil,item.span)
        if not type_ then
            return nil,'stage ' .. tostring(item.name) .. ' has no type without an argument'
        end
        stages[i]=type_; items[i]=item
    end
    local id=#self.functions+1
    -- A host entry is named apart from the word it stands for: the word's own name is what a host
    -- embedding already projects, and a benchmark driver calls `let_<case>`, so the entry must not
    -- claim that spelling. `statistics` publishes the name the host should call.
    local ctx=Context.new_function{name=name .. '_host',span=span,
        resources=self.options.resources,hosts=self.options.hosts,types=self:types(),
        builder=self,resolved=self.resolved,function_id=id}
    local fn=ctx.fn
    fn.template=template
    self.functions[id]=false
    -- §4.2 the defining word is visible in its own terminal body.
    if template.self then ctx.self_name=template.self.name; ctx.self_definition=template.self end
    -- The word's own fields are parameters like any other: they are the construction trace, and a
    -- mutable one is a place, so its binding is its address.
    -- The trace is rebuilt from the host's parameters, not from the word's own field values.
    -- `advance` re-binds the trace by name at every stage, so a trace still holding the values the
    -- *initializer* produced would shadow these parameters with values from another context.
    local trace={}
    for _,field in ipairs(word.fields) do
        ctx:push(); if field.retained then ctx:retain() end
        local parameter=ctx:parameter(field.type,A.Read)
        local address=(B.Address:isclassof(field.type) or B.Borrow:isclassof(field.type)) and parameter or false
        -- A prelude the call site built carries ownership even though it has no stage
        -- capability: the entry it is handed to is where it dies.
        local owned=not address and not field.type:copyable()
            and (field.owned or field.capability==A.Own or field.capability==A.OwnMut)
        ctx:force_bind(field.name,parameter,field.mutable,owned,false,address,span)
        trace[#trace+1]={name=field.name,value=parameter,type=field.type,mutable=field.mutable,
            owned=owned,retained=field.retained,span=span,capability=field.capability}
    end
    -- Every parameter exists before the first instruction: a parameter created once emission has
    -- started takes a position after an instruction and collides with it.
    local parameters={}
    for i=word.supplied+1,#layout.steps do
        parameters[i]=self:host_parameter(ctx,items[i].capability,stages[i],items[i].span)
    end
    -- What a saturated word means for a host: the fields the entry was handed, plus the ones its
    -- stages produced, are exactly the parameters of the word's own entry. Running that entry is
    -- what a call site does, so the host entry is a wrapper and one template emits one body.
    local function complete(c,saturated)
        local data=self:terminal_value(c,template)
        if data then
            -- No entry is built to own the fields, so the host entry destroys them here.
            for i=#saturated.fields,1,-1 do
                local field=saturated.fields[i]
                if field.owned then c:destroy(field.value,field.span or span) end
            end
            return c:finish(data,span)
        end
        local field_values=L()
        for _,field in ipairs(saturated.fields) do field_values:insert(field.value) end
        local target=self:entry_function(saturated.template,saturated.fields)
        local callee=assert(self.functions[target],'a host entry calls an entry this build just made')
        local types=L()
        for i=1,#callee.signature.results do types:insert(callee.signature.results[i]) end
        local results={c:emit(B.CallFunction(target,c:ref(c.effect),c:refs(field_values)),types,span)}
        c.effect=results[#results]
        return c:finish(results[1],span)
    end
    local current={type=value.type,word={template=template,fields=trace,supplied=word.supplied}}
    for i=word.supplied+1,#layout.steps do
        current=self:advance(ctx,current,parameters[i],items[i].span,B.Transient,
            i==#layout.steps and complete or nil)
    end
    -- A word that is already saturated has no stages left to advance, so its terminal has not run
    -- yet: the fields bound above are the whole of its state.
    if word.supplied>=#layout.steps then complete(ctx,{template=template,fields=trace,supplied=word.supplied}) end
    local blocks=L()
    for _,block in ipairs(fn.blocks) do
        assert(block.exit,'unfinished host entry'); blocks:insert(B.Block(block.parameters,block.instructions,block.exit))
    end
    self.functions[id]=B.Function(fn.name,B.Signature(blocks[1].parameters,L{fn.result,B.Effect}),blocks)
    return {name=name,id=id,bundle=#word.fields,stages=#layout.steps-word.supplied}
end

function Builder:build()
    local module=self:build_module()
    self.functions[1]=module
    self.functions[2]=self:build_unload(module.signature.results[2])
    -- After the module interface, so ids 1 and 2 stay what the host already expects.
    self.host_entries={}
    -- One host entry per exported word: the interface the embedding calls (§15.1). A word that
    -- cannot offer an ABI is skipped with its reason recorded (see the loop below).
    if self.options.host_entries~=false then
        self.host_entry_skips={}
        for _,export in ipairs(self.exports or {}) do
            -- An entry is an interface the word may not be able to offer: a body that invokes a
            -- captured word reaches fields belonging to the initializer's context, which is a gap
            -- in this compiler rather than a fault in the program. The word is still legal, so the
            -- entry is skipped and the reason recorded.
            local before=#self.functions
            local ok,entry,reason=pcall(self.host_entry,self,export.name,export.value,export.span)
            if ok and entry then self.host_entries[#self.host_entries+1]=entry
            else
                -- A failed entry may already have interned the functions it built on the way down,
                -- so both the function slots and the cache entries naming them are dropped.
                for i=before+1,#self.functions do self.functions[i]=nil end
                for key,id in pairs(self.entries) do if id>before then self.entries[key]=nil end end
                self.host_entry_skips[export.name]= ok and reason or tostring(entry):gsub('^.*: ','')
            end
        end
    end
    local functions=L()
    for _,fn in ipairs(self.functions) do functions:insert(fn) end
    local templates=L()
    for _,template in ipairs(self.resolved.templates) do
        templates:insert(B.Template(tostring(template.id),#template.steps,#template.captures,template.source.span))
    end
    return B.Program(self.options.name or '__program',templates,functions):verify_flow(self.options.hosts)
end

function A.Program:build(options)
    local resolved=self:resolve(options)
    local builder=Builder.new(self,resolved,options)
    local program=builder:build()
    builder.program=program
    return program,builder
end

function A.Word:build(ctx)
    local builder=ctx.builder; if not builder then gap(self.span,'word values require a program builder') end
    local template=ctx.resolved.chains[self.chain]
    if not template then gap(self.span,'unresolved word construction') end
    return builder:instantiate(ctx,{template=template})
end
end
