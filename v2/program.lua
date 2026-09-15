-- Program construction: one advancement protocol for persistent specialization and
-- transient invocation. See WORDS.md. Word values are SSA bundles (Belt.Word); a
-- statically known template's terminal becomes a belt function reached by CallFunction.
return function(V)
local A,B,L=V.AST,V.Belt,V.List
local Build=V.Build; local Context=Build.Context
local expect,fail,gap,copy=Build.expect,Build.fail,Build.gap,Build.copy
local literal=require('v2.literal')

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
    if B.Named:isclassof(type_) then return 'named(' .. type_.name .. ')' end
    return tostring(type_)
end

function Builder.new(ast,resolved,options)
    return setmetatable({ast=ast,resolved=resolved,options=options or {},
        layouts={},functions={false,false},entries={},templates={}},Builder)
end

function Builder:types()
    local types={Int=B.Int,Bool=B.Bool,Unit=B.Unit,Text=B.Text}
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

local function copyable_types(types)
    for _,type_ in ipairs(types) do if not type_:copyable() then return false end end
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
                value=copy(ctx.cells[id].value); value.mode='borrow'
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
            ctx:force_bind(field.name,field.value,field.mutable,field.owned,false,false,field.span)
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

function Builder:supply(ctx,value,argument,destination)
    local word=clone_word(assert(value.word,'specialization requires a word value'))
    local layout=self:layout(word.template)
    local step=layout.steps[word.supplied+1]
    if not step then fail(argument.span,'oversaturated specialization: the terminal already has every stage') end
    local item=step.item
    local supplied=argument:build(ctx)
    if supplied.word and not supplied.type:copyable() then
        gap(argument.span,'word-valued stages')
    end
    local _,temporary=item.capability:bind_argument(supplied,destination,function(message) fail(argument.span,message) end)
    if temporary then gap(argument.span,'transient read borrow of owned state') end
    -- A mutable stage is a place, so its argument is the declared type's address and the
    -- constraint describes what that place contains.
    local mut=item.capability==A.Mut
    local subject=mut and (B.Address:isclassof(supplied.type) and supplied.type.pointee or supplied.type) or supplied.type
    local type_=ctx:constraint(item.constraint,subject,argument.span)
    if type_ then expect(supplied,mut and B.Address(type_) or type_,argument.span) end
    if (item.capability==A.Own or item.capability==A.OwnMut) and ctx:borrows(supplied.type) then
        gap(argument.span,'passing a word that borrows enclosing state to an ownership-taking stage')
    end
    local owned=not supplied.type:copyable() and (item.capability==A.Own or item.capability==A.OwnMut)
    -- Advancement happens in a scope holding every field the word already has. Earlier steps
    -- closed their own scopes, so without this a prelude reached at this stage could not see
    -- a prelude reached at an earlier one.
    ctx:push()
    local ok,result=pcall(function()
        for _,field in ipairs(word.fields) do
            ctx:force_bind(field.name,field.value,field.mutable,field.owned,false,false,field.span)
        end
        ctx:force_bind(item.name,supplied,owned or item.capability==A.Mut or item.capability==A.OwnMut,owned,false,false,item.span)
        word.fields[#word.fields+1]={name=item.name,value=supplied,type=supplied.type,mutable=item.capability==A.Mut or item.capability==A.OwnMut,
            owned=owned,retained=destination==B.Persistent,span=item.span}
        word.supplied=word.supplied+1
        self:prepare(ctx,word,layout,step.prepare,destination)
        if word.supplied==#layout.steps then
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
    -- `import` is a construction entry: the named file's chain is constructed here, and the
    -- arguments that follow specialize it like any other word.
    if value.construction=='import' then
        local file=ctx.resolved.imports[expression]
        if not file then fail(expression.span,'unresolved import') end
        return self:instantiate(ctx,{template=ctx.resolved.chains[file]})
    end
    if not value.word then fail(expression.span,'specialization requires a word value') end
    -- The receiver is unchanged. A Copy receiver is copied; a fresh receiver transfers
    -- its state; an existing non-Copy receiver needs explicit independent-copy vocabulary.
    if value.mode=='borrow' then
        fail(expression.span,'specialization of an existing non-copyable word requires an explicit independent copy')
    end
    return self:supply(ctx,value,expression.argument,self:destination())
end

function Builder:entry(template,field_types,capabilities,mutable_mask,retained_mask)
    local parts={tostring(template.id)}
    for _,type_ in ipairs(field_types) do parts[#parts+1]=typekey(type_) end
    for i=1,#field_types do parts[#parts+1]=retained_mask[i] and '1' or '0' end
    local key=table.concat(parts,'|')
    local existing=self.entries[key]
    if existing then return existing end
    local id=#self.functions+1
    self.entries[key]=id
    local fields={}
    for i,type_ in ipairs(field_types) do
        fields[i]={type=type_,capability=capabilities[i],mutable=mutable_mask[i],retained=retained_mask[i]}
    end
    self.functions[id]=false
    self.functions[id]=self:build_entry(template,fields,id)
    return id
end

function Builder:build_entry(template,fields,id)
    local layout=self:layout(template)
    local names={}
    local index=1
    for _,capture in ipairs(layout.captures) do names[index]=capture.name; index=index+1 end
    for _,item in ipairs(layout.items) do names[index]=item.name; index=index+1 end
    local fn={name=(template.name or 'word') .. '_' .. id,span=template.source.span,blocks={},bindings={},next_value=0,
        result=nil,resources=self.options.resources or {},hosts=self.options.hosts or {},types=self:types()}
    local ctx=setmetatable({fn=fn,locations={},cells={},scopes={},pins={},locks={},builder=self,resolved=self.resolved},Context)
    ctx.block=ctx:new_block(); ctx:push(); ctx.effect=ctx:parameter(B.Effect)
    ctx.entry_id=id
    local records={}
    for i,field in ipairs(fields) do
        ctx:push(); if field.retained then ctx:retain() end
        local value=ctx:parameter(field.type,A.Read)
        -- A mutable stage arrives as an address, so the field is that place, not a copy.
        local address=B.Address:isclassof(field.type) and value or false
        local owned=not address and not field.type:copyable() and not field.mutable
        local binding=ctx:force_bind(names[i],value,field.mutable,owned,false,address,template.source.span)
        records[i]={field=field,id=binding,value=value}
    end
    if template.self then ctx.self_name=template.self.name; ctx.self_definition=template.self end
    ctx.finish=function(self_,value,span)
        -- §10.1: the storage this word borrowed belongs to this activation, so the word
        -- cannot leave it.
        if self_:borrows(value.type) then
            fail(span,'a word that borrows enclosing state cannot be returned from the invocation that owns it')
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
    ctx:statements(template.source.terminal.statements)
    if not ctx.block.exit then ctx:finish(ctx:emit(B.UnitLiteral,L{B.Unit},template.source.span),template.source.span) end
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
        local field_types,capabilities,mutable_mask,retained_mask,refs=L(),L(),{}, {},L()
        for i,field in ipairs(word.fields) do
            field_types:insert(field.type); capabilities:insert(field.mutable and A.Mut or A.Read)
            mutable_mask[i]=field.mutable; retained_mask[i]=field.retained; refs:insert(ctx:ref(field.value))
        end
        local target=self:entry(word.template,field_types,capabilities,mutable_mask,retained_mask)
        if tail then
            -- §6.5: the *caller's* own word state is not a local, so it must survive the
            -- transfer. Carrying it through the tail result needs address-taken state.
            if ctx.mutable_state then gap(expression.span,'tail invocation from a word with mutable state') end
            -- §6.5: a tail transfer retires this activation, so a place this activation owns
            -- cannot be passed. Only a borrow of module storage would survive, and the type
            -- does not distinguish that, so any borrow is conservative here.
            for _,field in ipairs(word.fields) do
                if B.Address:isclassof(field.type) then
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
            if not ctx.fn.result then
                if not (callee and callee.signature) then
                    gap(expression.span,'result type of a word whose only exit is a self tail call')
                end
                ctx.fn.result=callee.signature.results[1]
            end
            ctx:cleanup()
            ctx.block.exit=B.TailCall(target,ctx:ref(ctx.effect),refs)
            return nil
        end
        local callee=self.functions[target]
        local result_type
        if callee and callee.signature then
            result_type=callee.signature.results[1]
        elseif target==ctx.entry_id and ctx.fn.result then
            -- A direct self call: the entry is still being built, and a recursive call
            -- returns whatever this word returns.
            result_type=ctx.fn.result
        else
            gap(expression.span,'the result type of a recursive call must be fixed by another return in the same word')
        end
        local types=L{result_type}
        for i,field in ipairs(word.fields) do if field.mutable and field.retained then types:insert(field.type) end end
        types:insert(B.Effect)
        local results={ctx:emit(B.CallFunction(target,ctx:ref(ctx.effect),refs),types,expression.span)}
        ctx.effect=results[#results]
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
                ctx.cells[origin]={value=packed,initialized=true,alive=binding.owned}
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
    local fn={name='__module_init',span=file.span,
        blocks={},bindings={},next_value=0,result=nil,state=nil,resources=self.options.resources or {},hosts=self.options.hosts or {},types=self:types()}
    local ctx=setmetatable({fn=fn,locations={},cells={},scopes={},pins={},locks={},builder=self,resolved=self.resolved},Context)
    ctx.block=ctx:new_block(); ctx:push(); ctx.effect=ctx:parameter(B.Effect)
    local order,values,fields=L(),L(),L()
    for index,item in ipairs(file.items) do
        if A.Stage:isclassof(item) then item:entry(ctx,index,self.options)
        else
            A.Local(item.binding,item.binding.span):build(ctx)
            local id=ctx:find(item.binding.name)
            -- The value is recorded even when the terminal later moves it out: the state
            -- keeps its original construction position, which is what destruction order
            -- needs, and only the state is destroyed.
            values:insert(ctx.cells[id].value)
            order:insert(item.binding.name)
            fields:insert({name=item.binding.name,type=ctx.cells[id].value.type,mutable=item.binding.mutable})
        end
    end
    -- Module bindings live until module unload, not until initialization returns, so a
    -- borrow of module storage outlives any value that holds it.
    ctx.scopes[1].retained=true
    ctx.allow_borrow_escape=true
    self.module_order=order
    local namespace
    if file.terminal==nil then
        -- The common case: the namespace is exactly the prelude record, so it is its own
        -- state and there is nothing to duplicate.
        local state=ctx:construct_record(values,fields,fn.span)
        self.module_exports=self:export_map(fields)
        ctx:finish_pair(state,state,fn.span)
    elseif A.Data:isclassof(file.terminal) then
        ctx.module_preludes={}
        for _,item in ipairs(file.items) do
            if A.Prelude:isclassof(item) then ctx.module_preludes[ctx:find(item.binding.name)]=true end
        end
        namespace=file.terminal.value:build(ctx)
        ctx.module_preludes=nil
        local state=ctx:construct_record(values,fields,fn.span)
        self.module_exports=self:export_map(namespace.type)
        ctx:finish_pair(namespace,state,fn.span)
    else
        -- A written do terminal is the initialization body; its return is the namespace.
        ctx:statements(file.terminal.statements)
        if not ctx.block.exit then ctx:finish(ctx:emit(B.UnitLiteral,L{B.Unit},fn.span),fn.span) end
        ctx.fn.state=ctx.fn.result
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
    local fn={name='__module_unload',span=self.ast.file.span,
        blocks={},bindings={},next_value=0,result=nil,resources=self.options.resources or {},hosts=self.options.hosts or {},types=self:types()}
    local ctx=setmetatable({fn=fn,locations={},cells={},scopes={},pins={},locks={},builder=self,resolved=self.resolved},Context)
    ctx.block=ctx:new_block(); ctx:push(); ctx.effect=ctx:parameter(B.Effect)
    ctx:destroy(ctx:parameter(state_type),fn.span)
    ctx:finish(ctx:emit(B.UnitLiteral,L{B.Unit},fn.span),fn.span)
    local blocks=L()
    for _,block in ipairs(fn.blocks) do assert(block.exit,'unfinished block'); blocks:insert(B.Block(block.parameters,block.instructions,block.exit)) end
    return B.Function(fn.name,B.Signature(blocks[1].parameters,L{fn.result,B.Effect}),blocks)
end

function Builder:build()
    local module=self:build_module()
    self.functions[1]=module
    self.functions[2]=self:build_unload(module.signature.results[2])
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
