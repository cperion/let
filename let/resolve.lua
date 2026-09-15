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
    local definition={id=#self.definitions+1,name=name,kind=kind,node=node,owner=owner}
    self.definitions[definition.id]=definition; self.bindings[node]=definition; return definition
end
function Context:publish(scope,definition,span)
    if scope.names[definition.name] then fail(span,'duplicate binding ' .. definition.name) end
    scope.names[definition.name]=definition
end
function Context:lookup(scope,name,span)
    while scope do
        if scope.names[name] then return scope.names[name] end
        scope=scope.parent
    end
    fail(span,'unknown name ' .. name)
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
    local template=self.current
    while template and template~=definition.owner and definition.kind~='dictionary' do
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
    return definition
end
function Context:statements(statements,scope)
    for _,statement in ipairs(statements) do statement:resolve(self,scope) end
end
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
    for index,item in ipairs(chain.items) do item:resolve(self,scope,index) end
    template.preparation.last=#chain.items; template.preparation=nil
    -- A file chain may have no written terminal: its value is then the named record of its
    -- own prelude bindings, which is exactly the module namespace of §15.1.
    if chain.terminal then chain.terminal:resolve_terminal(self,scope,outer,self_definition)
    else template.namespace=true end
    self.current=previous; return template
end

-- §18 defers imports and package resolution, so the language fixes only the *semantics* of
-- an import: the named file's chain is constructed here, in a nested scope, and its
-- namespace is the result. Where a path is looked up is the embedding's business.
function Context:import_file(node,scope)
    local path=node.argument.value
    if not self.import_resolver then fail(node.span,'no import resolver is configured') end
    local loaded=self.import_resolver(path,self.file)
    if not loaded or not loaded.text or not loaded.file then
        fail(node.argument.span,'cannot resolve import ' .. path)
    end
    if self.importing[loaded.file] then fail(node.span,'import cycle through ' .. loaded.file) end
    self.importing[loaded.file]=true
    local file=V.parse(loaded.text,loaded.file).file
    self:chain(file,scope,nil,loaded.file)
    self.imports[node]=file
    self.importing[loaded.file]=nil
end
function A.Body:resolve_terminal(ctx,scope,outer,self_definition)
    local template=ctx.current; template.self=self_definition
    -- Self is a fallback behind stage/prelude names, ahead of outer declarations.
    -- It is never published into initializer/prelude scopes.
    local self_scope=ctx:scope(outer)
    if template.self then self_scope.names[template.self.name]=template.self end
    local bindings=ctx:scope(self_scope)
    for name,definition in pairs(scope.names) do bindings.names[name]=definition end
    template.body_scope=ctx:region(self.statements,bindings)
end
function A.Data:resolve_terminal(ctx,scope) self.value:resolve(ctx,scope) end
function A.Constraint:resolve(ctx,scope,span)
    -- Phase/shape checking follows lexical resolution. Arguments can name semantic
    -- descriptions of stages; being a runtime binding does not itself reject them.
    local head={span=span}; ctx:use(scope,self.name,head,'constraint')
    ctx.constraints[self]=ctx.references[head][1]
    for _,argument in ipairs(self.arguments) do argument:resolve(ctx,scope) end
end
function A.Binding:resolve(ctx,scope)
    local definition=ctx:definition(self.name,'binding',self,ctx.current)
    if self.constraint then self.constraint:resolve(ctx,scope,self.span) end
    definition.template=ctx:chain(self.value,scope,definition)
    ctx:publish(scope,definition,self.span); return definition
end
function A.Stage:resolve(ctx,scope,index)
    local template=ctx.current; template.preparation.last=index-1
    local preparation=prepare_range(index+1,#template.source.items)
    template.steps[#template.steps+1]={stage=self,index=index,prepare=preparation}
    template.preparation=preparation
    if self.constraint then self.constraint:resolve(ctx,scope,self.span) end
    ctx:publish(scope,ctx:definition(self.name,'stage',self,ctx.current),self.span)
end
function A.Prelude:resolve(ctx,scope) self.binding:resolve(ctx,scope) end
function A.Expr:resolve() error('missing lexical resolver for expression',0) end
function A.Integer:resolve() end
function A.Boolean:resolve() end
function A.Text:resolve() end
function A.Unit:resolve() end
function A.Name:resolve(ctx,scope) ctx:use(scope,self.name,self,'read',self) end
function A.Unary:resolve(ctx,scope) self.operand:resolve(ctx,scope) end
function A.Binary:resolve(ctx,scope) self.left:resolve(ctx,scope); self.right:resolve(ctx,scope) end
function A.Specialize:resolve(ctx,scope)
    -- `import` is a dictionary entry, so a lexical binding of that name still wins.
    if A.Name:isclassof(self.word) and self.word.name=='import' then
        local definition=ctx:lookup(scope,'import',self.word.span)
        local entry=definition and definition.kind=='dictionary' and definition.node
        if entry and entry.phase=='construction' then
            if not A.Text:isclassof(self.argument) then
                fail(self.argument.span,'an import path must be a constant Text')
            end
            ctx.import_words[self.word]=true
            ctx:import_file(self,scope)
            return
        end
    end
    self.word:resolve(ctx,scope); self.argument:resolve(ctx,scope)
end
function A.Invoke:resolve(ctx,scope)
    self.word:resolve(ctx,scope); for _,argument in ipairs(self.arguments) do argument:resolve(ctx,scope) end
end
function A.Word:resolve(ctx,scope) ctx:chain(self.chain,scope) end
function A.NamedAggregate:resolve(ctx,scope)
    local members=ctx:scope(scope)
    for _,binding in ipairs(self.members) do binding:resolve(ctx,members) end
end
function A.PositionalAggregate:resolve(ctx,scope)
    for _,chain in ipairs(self.elements) do ctx:chain(chain,scope) end
end
function A.Expr:resolve_place() fail(self.span,'expression is not a place') end
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
function A.Project:resolve(ctx,scope) self:resolve_read(ctx,scope,self) end
function A.Index:resolve(ctx,scope) self:resolve_read(ctx,scope,self) end
function A.Move:resolve(ctx,scope) self.place:resolve_place(ctx,scope,'move') end
function A.Borrow:resolve(ctx,scope) self.place:resolve_place(ctx,scope,'mut') end
function A.Local:resolve(ctx,scope) self.binding:resolve(ctx,scope) end
function A.Assign:resolve(ctx,scope)
    self.place:resolve_place(ctx,scope,'write'); self.value:resolve(ctx,scope)
end
function A.Return:resolve(ctx,scope) if self.value then self.value:resolve(ctx,scope) end end
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
        local definition=ctx:definition(name,'dictionary',entries[name]); scope.names[name]=definition
    end
    return scope
end
function A.Program:resolve(options)
    options=options or {}
    local ctx=setmetatable({definitions={},bindings={},chains={},uses={},references={},constraints={},scopes={},templates={},
        imports={},import_words={},importing={},import_resolver=options.resolve,file=self.file.span.file},Context)
    local builtins={}
    for _,name in ipairs{'Bool','Int','Unit','Text','Copy','Executable'} do builtins[name]={phase='constraint'} end
    local outer=dictionary(ctx,nil,builtins)
    outer=dictionary(ctx,outer,options.dictionary or {})
    local resources={}
    for name,descriptor in pairs(options.resources or {}) do resources[name]={phase='constraint',resource=descriptor} end
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
    return ctx
end
end

