-- Lexical identities and preparation boundaries over the original source AST.
-- No checked-AST clone, execution, storage choice, or scalar-only word path.
return function(V)
local A=V.AST; local fail=V.Lexer.fail
local Context={}; Context.__index=Context
function Context:scope(parent)
    local scope={id=#self.scopes+1,parent=parent,names={}}
    self.scopes[#self.scopes+1]=scope; return scope
end
function Context:definition(name,kind,node,owner)
    -- The name's own range, when the declaring node has one; a dictionary or namespace node has
    -- no source, so it has none.
    local definition={id=#self.definitions+1,name=name,kind=kind,node=node,owner=owner,range=node and node.name_range}
    self.definitions[definition.id]=definition; self.bindings[node]=definition; return definition
end
-- A resolution problem is data, not a thrown error: the editor wants them all, and `build`
-- turns the first back into the fail-fast error the compiler has always reported.
function Context:problem(span,message)
    self.diagnostics[#self.diagnostics+1]={span=span,message=message}
end

-- An unresolved name still gets a definition so the walk can continue. It is not added to
-- `definitions`, so no later pass mistakes it for a declared binding.
function Context:unknown(name,span)
    local definition=self.unknowns[name]
    if not definition then
        definition={name=name,kind='unknown',unknown=true}
        self.unknowns[name]=definition
    end
    return definition
end

function Context:publish(scope,definition,span)
    local existing=scope.names[definition.name]
    if existing then
        -- The declaring pass and the statement that initializes the name both publish it, so the
        -- same definition arriving twice is the normal case rather than a duplicate.
        if existing==definition then return end
        -- Reported once, by whichever pass reaches it first: a duplicate is a fact about the scope,
        -- not about the pass that noticed.
        if not definition.duplicate_reported then
            definition.duplicate_reported=true
            self:problem(span,'duplicate binding ' .. definition.name)
        end
        return
    end
    scope.names[definition.name]=definition
end
-- A lookup that reports absence instead of failing, for a form that may name a value or a
-- namespace.
function Context:peek(scope,name)
    while scope do
        if scope.names[name] then return scope.names[name] end
        scope=scope.parent
    end
end
-- §: a name is *declared* before the statement that initializes it, so a word that runs later may
-- name a binding whose initializer has not run -- which is what mutual recursion between two
-- top-level words needs. The declaration is memoized on its node, because the statement is walked
-- twice: once to declare, once to initialize.
function Context:declaration(node,name,kind,scope,span)
    local existing=self.bindings[node]
    if existing then return existing end
    local definition=self:definition(name,kind,node,self.current)
    -- Module-level storage is allocated with the module's state record, so it exists from the start
    -- and a later word may capture it by address. An activation binding's cell does not exist until
    -- its own statement runs, so reaching one early is refused rather than guessed at.
    if self.declaring_module then definition.module_level=true end
    definition.pending=true
    -- Published by the declaring pass, not here: `publish` is idempotent for one definition.
    return definition
end
function Context:lookup(scope,name,span)
    local definition=self:peek(scope,name)
    if definition then
        -- A binding is not visible in its own initializer. The check is by identity because the
        -- declaration already exists: names are declared ahead of the statements that initialize
        -- them, so absence cannot be the signal any more.
        -- §4.2: the defining word is visible inside its own terminal body, so a recursive call is
        -- not an early use. Anywhere else it is: `let b = 1` followed by `f(b)` makes `1 f(b)` the
        -- value, and `b` is not yet visible.
        if self.resolving[name]==definition then
            -- §4.2: the defining word is visible inside its own terminal body, so a recursive call is
            -- not an early use -- and it is not a *forward* reference either, which is why this is
            -- tested before `pending` rather than inside the branch for it.
            if not self.in_word then
                self:problem(span,'a binding is not visible in its own initializer; end the value with ";" if the next statement is separate')
            end
        elseif definition.pending then
            -- A name declared but not yet initialized is reachable only from a word, which runs
            -- later than the sequence it stands in, and only when its storage is the module's, which
            -- exists from the start.
            if self.in_word and definition.module_level then
                if self.current then
                    local refs=self.current.forward_refs
                    if not refs then refs={}; self.current.forward_refs=refs end
                    refs[definition]=span
                end
            else
                self:problem(span,name .. ' is used before its initializer runs')
            end
        end
        return definition
    end
    -- An adjacent expression can continue a value, so `let b = 1` followed by `f(b)` makes `1 f(b)`
    -- the value and `b` is not yet visible. Name that cause rather than a plain unknown name.
    if self.resolving[name] then
        self:problem(span,'a binding is not visible in its own initializer; end the value with ";" if the next statement is separate')
    else
        self:problem(span,'unknown name ' .. name)
    end
    return self:unknown(name,span)
end
function Context:use(scope,name,node,access,path)
    local definition=self:lookup(scope,name,node.span)
    -- A mutable borrow needs the binding's address, so its storage must be observable. This
    -- is a declaration-level fact, so it is decided here rather than by promotion later.
    if access=='mut' then definition.address_taken='mutable borrow' end
    local use={definition=definition,node=node,scope=scope,access=access,path=path,template=self.current}
    self.uses[#self.uses+1]=use
    local occurrences=self.references[node] or {}; self.references[node]=occurrences
    occurrences[#occurrences+1]=use
    -- A nested constructor's free input must also be available to its containing
    -- delayed construction/body. Stop at the defining template or a self link.
    if not definition.unknown then
        local template=self.current
        while template and template~=definition.owner and definition.kind~='dictionary' and definition.kind~='namespace' do
            if template.self==definition then break end
            -- Crossing a template boundary is not yet a capture: §10.1 is about a *word body*
            -- reaching out, and a binding initializer is not a word. Which enclosing templates
            -- are words is only known once they are fully resolved, so record and decide later.
            local seen=definition.capture_templates
            if not seen then seen={}; definition.capture_templates=seen end
            seen[#seen+1]=template
            if not template.capture_set[definition.id] then
                template.capture_set[definition.id]=true; template.captures[#template.captures+1]=definition
            end
            template.capture_uses[#template.capture_uses+1]=use; template=template.parent
        end
    end
    return definition
end
-- §: a statement list declares its names before resolving any of them, so a word defined
-- here may name a word defined below it. Whether a *use* may reach a pending declaration
-- is decided in `lookup`, because only that knows where the use sits.
function Context:statements(statements,scope)
    for _,statement in ipairs(statements) do statement:declare(self,scope) end
    for _,statement in ipairs(statements) do statement:resolve(self,scope) end
end
-- Most statements declare no name.
function A.Stmt:declare() end
function Context:region(statements,parent)
    local scope=self:scope(parent); self:statements(statements,scope); return scope
end
local function prepare_range(first,last) return {first=first,last=last} end
function Context:chain(chain,outer,self_definition,name)
    -- The source name makes the emitted C self-describing; anonymous chains get a stable
    -- generated name rather than an opaque index.
    local template={id=#self.templates+1,source=chain,parent=self.current,steps={},captures={},capture_set={},capture_uses={},
        name=name or (self_definition and self_definition.name) or ('lambda' .. (#self.templates+1))}
    self.templates[#self.templates+1]=template; self.chains[chain]=template
    local previous=self.current; self.current=template
    local scope=self:scope(outer); template.scope=scope
    template.initial=prepare_range(1,0); template.preparation=template.initial
    local is_module=name=='<module>'
    local declaring_module=self.declaring_module
    self.declaring_module=is_module
    -- A chain declares its items before resolving them, for the same reason a statement list does: a
    -- word here may name a word declared below it.
    for _,item in ipairs(chain.items) do item:declare(self,scope) end
    for index,item in ipairs(chain.items) do item:resolve(self,scope,index) end
    self.declaring_module=declaring_module
    template.preparation.last=#chain.items; template.preparation=nil
    -- A file chain may have no written terminal: its value is then the named record of its
    -- own prelude bindings, which is exactly the module namespace of §15.1.
    if chain.terminal then
        -- A word's body runs at invocation, later than the sequence it stands in, so a use there may
        -- name a module binding declared below it. The module's own body runs while the module is
        -- initializing, so it does not get that permission.
        local in_word=self.in_word
        self.in_word=in_word or (A.Body:isclassof(chain.terminal) and not is_module)
        chain.terminal:resolve_terminal(self,scope,outer,self_definition)
        self.in_word=in_word
    else template.namespace=true end
    self.current=previous; return template
end

-- §18 defers imports and package resolution, so the language fixes only the *semantics* of
-- an import: the named file's chain is constructed here, in a nested scope, and its
-- namespace is the result. Where a path is looked up is the embedding's business.
function Context:import_file(node,scope)
    local path=node.argument.value
    if not self.import_resolver then
        self:problem(node.span,'no import resolver is configured')
        return
    end
    local loaded=self.import_resolver(path,self.file)
    if not loaded or not loaded.text or not loaded.file then
        self:problem(node.argument.span,'cannot resolve import ' .. path)
        return
    end
    if self.importing[loaded.file] then
        self:problem(node.span,'import cycle through ' .. loaded.file)
        return
    end
    self.importing[loaded.file]=true
    local ok,program=pcall(V.parse,loaded.text,loaded.file)
    if not ok then
        local detail=tostring(program):match(':%d+:%d+: (.*)$') or tostring(program)
        self:problem(node.span,'imported file: ' .. detail)
        self.importing[loaded.file]=nil
        return
    end
    self:chain(program.file,scope,nil,loaded.file)
    self.imports[node]=program.file
    self.importing[loaded.file]=nil
end
function A.Body:resolve_terminal(ctx,scope,outer,self_definition)
    local template=ctx.current; template.self=self_definition
    if self.result then self.result:resolve(ctx,scope,template.source.span) end
    -- Self is a fallback behind stage/prelude names, ahead of outer declarations.
    -- It is never published into initializer/prelude scopes.
    local self_scope=ctx:scope(outer)
    if template.self then self_scope.names[template.self.name]=template.self end
    local bindings=ctx:scope(self_scope)
    for name,definition in pairs(scope.names) do bindings.names[name]=definition end
    template.body_scope=ctx:region(self.statements,bindings)
end
function A.Data:resolve_terminal(ctx,scope) self.value:resolve(ctx,scope) end
-- A type name written in expression position (an `or` union alternative) resolves as a type-
-- word use, so the editor can follow it and the builder can read the type it denotes.
function Context:resolve_type_name(node,scope)
    -- The Name node itself is the use, so the editor finds a type-word use the same way it
    -- finds a value use; its span is already the name's.
    self.type_refs[node]=self:use(scope,node.name,node,'type')
end
function A.Ref:resolve(ctx,scope,span)
    -- §11: a type word resolves as an ordinary name. Whether it names a known type word is a
    -- vocabulary question, answered when the annotation is checked, not here.
    local head={span=(self.name_range and self.name_range.start) or span}; local definition=ctx:use(scope,self.name,head,'type')
    ctx.type_refs[self]=definition
    for _,argument in ipairs(self.arguments) do argument:resolve(ctx,scope) end
end
-- §11 type words: an arrow, sum, record, or tuple resolves its type words; a plain name is Ref.
function A.Arrow:resolve(ctx,scope,span) self.from:resolve(ctx,scope,span); self.to:resolve(ctx,scope,span) end
function A.Sum:resolve(ctx,scope,span) self.left:resolve(ctx,scope,span); self.right:resolve(ctx,scope,span) end
function A.Do:resolve(ctx,scope,span) self.result:resolve(ctx,scope,span) end
function A.Record:resolve(ctx,scope,span) for _,field in ipairs(self.fields) do field:resolve(ctx,scope,span) end end
function A.Tuple:resolve(ctx,scope,span) for _,element in ipairs(self.elements) do element:resolve(ctx,scope,span) end end
function A.TypeField:resolve(ctx,scope,span) self.type:resolve(ctx,scope,span) end
function A.Apply:resolve(ctx,scope,span) self.constructor:resolve(ctx,scope,span); self.argument:resolve(ctx,scope,span) end
-- §: declaring a name is separate from initializing it, so a statement list can declare every name
-- before resolving any initializer.
function A.Binding:declare(ctx,scope)
    local definition=ctx:declaration(self,self.name,'binding',scope,self.span)
    ctx:publish(scope,definition,definition.range and definition.range.start or self.span)
end
function A.Binding:resolve(ctx,scope)
    local definition=ctx:declaration(self,self.name,'binding',scope,self.span)
    if self.constraint then self.constraint:resolve(ctx,scope,self.span) end
    -- A value ends at the next statement only when that statement cannot continue it; an
    -- adjacent expression can, so `let b = 1` followed by `f(b)` makes `1 f(b)` the value and
    -- then `b` is not yet visible. Name that cause instead of reporting the name as unknown.
    local previous=ctx.resolving[self.name]
    ctx.resolving[self.name]=definition
    local template=ctx:chain(self.value,scope,definition)
    ctx.resolving[self.name]=previous
    definition.template=template
    -- §11.5: a binding whose value is exactly an import names a namespace value, so
    -- `codec.JPEG` projects a member of the imported file. The kind stays 'binding', so the
    -- binding is still captured by a body.
    if #self.value.items==0 and A.Data:isclassof(self.value.terminal) then
        local expression=self.value.terminal.value
        while A.Specialize:isclassof(expression) and not ctx.imports[expression] do expression=expression.word end
        if A.Specialize:isclassof(expression) and ctx.imports[expression] then
            definition.module_members=ctx:module_members(ctx.imports[expression])
        end
    end
    -- §11.2: a binding whose value is a word value names that word, so an aggregate type and
    -- its constructor share the binding's name for nominal identity.
    local terminal=template.source.terminal
    if A.Data:isclassof(terminal) and A.Word:isclassof(terminal.value) then
        local inner=ctx.chains[terminal.value.chain]
        if inner then inner.name=definition.name end
    end
    -- Initialized now, so a later use of the name is no longer a forward reference.
    definition.pending=nil
    ctx:publish(scope,definition,definition.range and definition.range.start or self.span)
    return definition
end
function A.Stage:declare(ctx,scope)
    local stage=ctx:declaration(self,self.name,'stage',scope,self.span)
    ctx:publish(scope,stage,stage.range and stage.range.start or self.span)
end
function A.Stage:resolve(ctx,scope,index)
    local template=ctx.current; template.preparation.last=index-1
    local preparation=prepare_range(index+1,#template.source.items)
    template.steps[#template.steps+1]={stage=self,index=index,prepare=preparation}
    template.preparation=preparation
    if self.constraint then self.constraint:resolve(ctx,scope,self.span) end
    local stage=ctx:declaration(self,self.name,'stage',scope,self.span)
    -- A stage's value is supplied by the caller before the body runs, so a use of it is never a
    -- forward reference and the declaration is not pending once it has been resolved.
    stage.pending=nil
    ctx:publish(scope,stage,stage.range and stage.range.start or self.span)
end
function A.Prelude:declare(ctx,scope) self.binding:declare(ctx,scope) end
function A.Prelude:resolve(ctx,scope) self.binding:resolve(ctx,scope) end
-- A foreign declaration's constraints are type names, so resolving them catches an unknown one
-- here, with a span, rather than in the vocabulary. The word itself is a host descriptor.
-- An extern names a host rather than a lexical binding, so there is nothing to declare.
function A.Extern:declare() end
function A.Extern:resolve(ctx,scope)
    for _,stage in ipairs(self.parameters) do if stage.constraint then stage.constraint:resolve(ctx,scope,stage.span) end end
    if self.result then self.result:resolve(ctx,scope,self.span) end
end
function A.Expr:resolve(ctx,scope)
    -- §11.5: a sum type literal is an Expr alternative without its own resolver method.
    if A.SumType:isclassof(self) then self.left:resolve(ctx,scope); self.right:resolve(ctx,scope); return end
    error('missing lexical resolver for expression',0)
end
function A.Integer:resolve() end
function A.Float:resolve() end
function A.Boolean:resolve() end
function A.Text:resolve() end
function A.Unit:resolve() end
function A.Name:resolve(ctx,scope) ctx:use(scope,self.name,self,'read',self) end
function A.Unary:resolve(ctx,scope) self.operand:resolve(ctx,scope) end
-- §11.5: `or` is disjunction. Between two type words it forms the tagged union, exactly where
-- `|` did before; between values it is the short-circuiting logical or of §13.1. Only the
-- operands can tell the two apart, so the decision is recorded here and the builder reads it.
local function union_operand(ctx,scope,node)
    if A.Binary:isclassof(node) and node.operator==A.Or then
        return union_operand(ctx,scope,node.left) and union_operand(ctx,scope,node.right)
    end
    if not A.Name:isclassof(node) then return false end
    local definition=ctx:peek(scope,node.name)
    if not definition or definition.unknown then return false end
    -- A built-in type word, or a resource, which is a type word too (§12.4).
    if definition.node and (definition.node.type or definition.node.resource) then return true end
    -- A binding whose value is itself a union type word is a type word (`let Pair = Int or Text`).
    -- The value is a chain, so the type word is the chain's terminal expression.
    if definition.kind=='binding' and definition.node and definition.node.value then
        local terminal=definition.node.value.terminal
        if A.Data:isclassof(terminal) then
            local value=terminal.value
            if A.Binary:isclassof(value) and value.operator==A.Or and ctx.unions[value] then return true end
        end
    end
    return false
end
local function resolve_union_operand(ctx,scope,node)
    if A.Binary:isclassof(node) and node.operator==A.Or then return node:resolve(ctx,scope) end
    ctx:resolve_type_name(node,scope)
end
function A.Binary:resolve(ctx,scope)
    if self.operator==A.Or and union_operand(ctx,scope,self.left) and union_operand(ctx,scope,self.right) then
        ctx.unions[self]=true
        resolve_union_operand(ctx,scope,self.left); resolve_union_operand(ctx,scope,self.right)
        return
    end
    self.left:resolve(ctx,scope); self.right:resolve(ctx,scope)
end
function A.Specialize:resolve(ctx,scope)
    -- `import` is a dictionary entry, so a lexical binding of that name still wins.
    if A.Name:isclassof(self.word) and self.word.name=='import' then
        local definition=ctx:lookup(scope,'import',self.word.span)
        local entry=definition and definition.kind=='dictionary' and definition.node
        if entry and entry.phase=='construction' then
            if not A.Text:isclassof(self.argument) then
                ctx:problem(self.argument.span,'an import path must be a constant Text')
                self.word:resolve(ctx,scope); self.argument:resolve(ctx,scope); return
            end
            ctx.import_words[self.word]=true
            ctx:import_file(self,scope)
            return
        end
    end
    self.word:resolve(ctx,scope); self.argument:resolve(ctx,scope)
end
function A.Invoke:resolve(ctx,scope)
    -- A word invoked while the module is initializing runs before anything declared below it, so a
    -- word with a forward reference must not be reached that way. Recorded here and checked at the
    -- end of the program, because the callee's template is not known until its binding resolves.
    self.word:resolve(ctx,scope)
    -- The callee's definition, when the callee is a plain name: `A.Name:resolve` looks it up and
    -- discards it, and asking `peek` rather than `lookup` keeps an unknown name reported once.
    local callee=A.Name:isclassof(self.word) and ctx:peek(scope,self.word.name) or nil
    if callee then
        if ctx.in_word then callee.invoked_in_word=true else callee.invoked_eagerly=self.span end
    end
    for _,argument in ipairs(self.arguments) do argument:resolve(ctx,scope) end
end
function A.Word:resolve(ctx,scope) ctx:chain(self.chain,scope) end
function A.NamedAggregate:resolve(ctx,scope)
    local members=ctx:scope(scope)
    for _,binding in ipairs(self.members) do binding:resolve(ctx,members) end
end
function A.PositionalAggregate:resolve(ctx,scope)
    for _,chain in ipairs(self.elements) do ctx:chain(chain,scope) end
end
function A.Expr:resolve_place(ctx,scope) ctx:problem(self.span,'expression is not a place') end
function A.Name:resolve_place(ctx,scope,access,path) ctx:use(scope,self.name,self,access,path or self) end
function A.Project:resolve_place(ctx,scope,access,path) self.base:resolve_place(ctx,scope,access,path or self) end
function A.Index:resolve_place(ctx,scope,access,path)
    self.base:resolve_place(ctx,scope,access,path or self); self.index:resolve(ctx,scope)
end
function A.Expr:resolve_read(ctx,scope) self:resolve(ctx,scope) end
function A.Name:resolve_read(ctx,scope,path) ctx:use(scope,self.name,self,'read',path or self) end
function A.Project:resolve_read(ctx,scope,path) self.base:resolve_read(ctx,scope,path or self) end
function A.Index:resolve_read(ctx,scope,path)
    self.base:resolve_read(ctx,scope,path or self); self.index:resolve(ctx,scope)
end
-- `c.member` where `c` is a namespace is a dictionary lookup, not a value projection: the
-- member is a word, so `c.puts(...)` invokes it exactly like a top-level one.
function A.Project:resolve(ctx,scope)
    if A.Name:isclassof(self.base) then
        local definition=ctx:peek(scope,self.base.name)
        if definition and definition.kind=='namespace' then
            local member=definition.members[self.name]
            if not member then
                ctx:problem(self.span,'no ' .. self.name .. ' in ' .. self.base.name)
                return
            end
            ctx.namespace_members[self]=member
            return
        end
        -- An imported namespace is projected structurally; record the link so the editor can
        -- follow it, without changing what construction does.
        if definition and definition.module_members then
            local member=definition.module_members[self.name]
            if member then ctx.module_projections[self]=member end
        end
    end
    self:resolve_read(ctx,scope,self)
end
function A.Index:resolve(ctx,scope) self:resolve_read(ctx,scope,self) end
function A.Move:resolve(ctx,scope) self.place:resolve_place(ctx,scope,'move') end
function A.Borrow:resolve(ctx,scope) self.place:resolve_place(ctx,scope,'mut') end
function A.Local:declare(ctx,scope) self.binding:declare(ctx,scope) end
function A.Local:resolve(ctx,scope) self.binding:resolve(ctx,scope) end
function A.Assign:resolve(ctx,scope)
    self.place:resolve_place(ctx,scope,'write'); self.value:resolve(ctx,scope)
end
function A.Return:resolve(ctx,scope) if self.value then self.value:resolve(ctx,scope) end end
function A.Break:resolve() end
function A.Continue:resolve() end
function A.Discard:resolve(ctx,scope) self.value:resolve(ctx,scope) end
function A.If:resolve(ctx,scope)
    self.condition:resolve(ctx,scope); ctx:region(self.yes,scope); ctx:region(self.no,scope)
end
function A.While:resolve(ctx,scope) self.condition:resolve(ctx,scope); ctx:region(self.body,scope) end
function A.Switch:resolve(ctx,scope)
    self.subject:resolve(ctx,scope)
    for _,arm in ipairs(self.cases) do
        for _,label in ipairs(arm.labels) do label:resolve(ctx,scope) end
        ctx:region(arm.body,scope)
    end
    ctx:region(self.otherwise,scope)
end
local function dictionary(ctx,parent,entries)
    local scope=ctx:scope(parent); local names={}
    for name in pairs(entries) do names[#names+1]=name end; table.sort(names)
    for _,name in ipairs(names) do
        local entry=entries[name]
        local definition=ctx:definition(name,entry.members and 'namespace' or 'dictionary',entry)
        if entry.members then definition.members=entry.members end
        scope.names[name]=definition
    end
    return scope
end
-- The members an imported file exposes as a namespace: its own names when it has no written
-- terminal, or the members of the record its terminal writes. This is a navigation link, not a
-- resolution rule, so it is kept apart from the dictionary namespaces A.Project resolves.
function Context:module_members(chain)
    local template=self.chains[chain]
    if not chain.terminal then return template and template.scope.names end
    if A.Data:isclassof(chain.terminal) and A.NamedAggregate:isclassof(chain.terminal.value) then
        local members={}
        for _,binding in ipairs(chain.terminal.value.members) do
            local definition=self.bindings[binding]
            if definition then members[binding.name]=definition end
        end
        return members
    end
end

function A.Program:resolve(options)
    options=options or {}
    local ctx=setmetatable({definitions={},bindings={},chains={},uses={},references={},type_refs={},scopes={},templates={},
        imports={},import_words={},importing={},namespace_members={},module_projections={},diagnostics={},unknowns={},resolving={},unions={},
        import_resolver=options.resolve,file=self.file.span.file},Context)
    -- §11: the primitive type words are ordinary names, not a phase; the vocabulary decides
    -- what a type word means at a boundary.
    local builtins={}
    for _,name in ipairs{'Bool','Int','U8','U32','Float','Float32','Unit','Text','CString','CPointer','Type'} do builtins[name]={type=true} end
    -- The core numeric conversions are runtime words (§13.3), shadowable like any binding.
    for _,name in ipairs{'float','int','u8','u32','f32'} do builtins[name]={phase='runtime'} end
    local outer=dictionary(ctx,nil,builtins)
    outer=dictionary(ctx,outer,options.dictionary or {})
    local resources={}
    for name,descriptor in pairs(options.resources or {}) do resources[name]={resource=descriptor} end
    outer=dictionary(ctx,outer,resources)
    outer=dictionary(ctx,outer,options.hosts or {})
    -- Construction-phase entries are dictionary names, not reserved words.
    outer=dictionary(ctx,outer,{['import']={phase='construction'}})
    ctx.module=ctx:scope(outer)
    ctx.importing[ctx.file]=true
    -- The file chain's own scope holds the module's top-level names, so it *is* the module
    -- namespace: the terminal and every nested chain resolve through it.
    ctx.module=ctx:chain(self.file,ctx.module,nil,'<module>').scope
    ctx.importing[ctx.file]=nil
    -- A binding is captured when a *word* reaches out to it. A word is a template that has
    -- stages or a runtime do terminal; a binding initializer is neither.
    for _,definition in ipairs(ctx.definitions) do
        for _,template in ipairs(definition.capture_templates or {}) do
            if #template.steps>0 or A.Body:isclassof(template.source.terminal) then
                definition.captured=true
            end
        end
    end
    -- §: a forward reference is sound only if the word that makes it is not reached while the module
    -- is initializing, because the binding it names is initialized later in that same sequence. The
    -- reference and the eager invocation are recorded apart -- by `lookup` and by `A.Invoke:resolve`
    -- -- because the word's own template is not known until its binding resolves, so the two can
    -- only be joined here.
    for _,definition in ipairs(ctx.definitions) do
        local template=definition.template
        if template and template.forward_refs and definition.invoked_eagerly then
            for other in pairs(template.forward_refs) do
                ctx:problem(definition.invoked_eagerly,
                    definition.name .. ' names ' .. other.name .. ', which is initialized after it, and is invoked while the module initializes')
            end
        end
    end
    return ctx,ctx.diagnostics
end
end

