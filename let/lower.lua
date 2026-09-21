-- The demanded instances: Judge.Program -> Belt.Function* (DESIGN §12.3, §S23, §S25).
--
-- **Lower is demand-driven from the roots.** The roots are the module initializer and each exported
-- word's entry point (spec §2.6); a root demands what it needs, and the set of demanded instances
-- is progress on `Unit` because it outlives any one `Function` (§6).
--
-- That is not an optimization. Spec §5.2 makes an instance exist *because something demanded it*:
-- "each specialization constructs a new semantic result". §S25 refines the granularity to the
-- **prefix**: a word value is `R(t,0)`, demanded by the definition that binds it, while `advance_k`
-- and `run` are demanded by applications. So a word nothing applies is demanded at prefix 0 only --
-- its value exists, its later prefixes and its terminal do not, and it can never fail compilation.
--
-- `demand` reserves an instance's id **before** lowering it, which is what makes a cycle terminate:
-- a self-application finds the id already there instead of recursing.
--
-- Numbering, restated because it is the rule that has to be exactly right: within a block, producer
-- positions are zero-based, parameters first and then instructions; at consumer position `p`,
-- `Ref(distance, output)` denotes producer `p - 1 - distance`; the exit's position is the end of the
-- instruction sequence.
return function(V)
    local B, Semantic, Syntax, Chain, Judge, Report, L =
        V.Belt, V.Semantic, V.Syntax, V.Chain, V.Judge, V.Report, V.List

    local Lower = {}

    -- Representation. The semantic type word is what the program means; the belt type is what the
    -- emitter materializes, and the two are different vocabularies (DESIGN §S5).
    local residual_type

    local function rep(L_, type_)
        -- §10: `Semantic` owns meaning and `Belt` owns representation, and this is the ONLY mapping
        -- between them. So anything else here is a caller mistake -- and it used to be a SILENT one,
        -- because `rep` fell through to nil and every caller reads nil as "no representation for
        -- this". Twice that meant a value which was ALREADY a belt type was mapped a second time,
        -- and the check that asks whether it has a representation answered no. The guard costs
        -- nothing and makes the whole class impossible: a belt type is not a `Semantic.Type`, so it
        -- cannot be mapped twice by accident.
        assert(Semantic.Type:isclassof(type_),
            'rep maps a Semantic.Type to a Belt.Type, not a ' ..
            tostring(getmetatable(type_) and getmetatable(type_).kind or type_))
        if type_ == Semantic.Int then return B.Int end
        if type_ == Semantic.Bool then return B.Bool end
        if type_ == Semantic.Unit then return B.Unit end
        -- §11.3: Text is a module-lifetime literal, and its representation is the belt's `Text` --
        -- a pointer to static storage. The two foreign views (`CString`, `CPointer`) are host
        -- vocabulary (§3.6) and arrive with it.
        if type_ == Semantic.Text then return B.Text end
        -- §11.7's scalar types, one for one. The foreign pair is a representation and nothing more:
        -- §3.6 says a view's extent is the scope that made it, so there is no belt type for "borrowed"
        -- and there should not be.
        if type_ == Semantic.U8 then return B.U8 end
        if type_ == Semantic.U32 then return B.U32 end
        -- §2.2: a WORD's value is its PACKET, so a word type maps to its residual. This is why the
        -- mapping takes the lowerer at all: `residual_type` builds a packet out of the template's
        -- items, which `Semantic` cannot see (a word type names its template by number, §11.4) and
        -- which `Chain` cannot map into `Belt`. Everything else here is structural, which is what `rep`
        -- was when it had one argument -- and one argument made a record CONTAINING a word impossible:
        -- an imported file's namespace is exactly that, so `import` was
        -- `Bug(NoLowering(form = representation))`.
        if Semantic.Word:isclassof(type_) then
            local declaration = L_.declarations[type_.template]
            if declaration and Judge.Word:isclassof(declaration) then
                return residual_type(L_, declaration.word, type_.prefix)
            end
            return nil
        end
        if type_ == Semantic.Float then return B.Float end
        if type_ == Semantic.Float32 then return B.Float32 end
        -- A DECLARED host type's representation is its own name: the host owns the C definition, so
        -- the compiler names it and nothing more. That is §3.6's "the host's contract; Let holds
        -- nothing and checks nothing" made concrete.
        if Semantic.Named:isclassof(type_) then return B.Named(type_.name) end
        -- §11.7 has a sum on both sides, so the mapping is structural like a record's. An ARROW and a
        -- `do`, by contrast, have no representation at all: a word's type is nominal in its template
        -- (§S3) and a `do` describes a chain, so neither is a layout -- and `rep` returning nil is
        -- how that is said.
        if Semantic.Sum:isclassof(type_) then
            local alternatives = L()
            for _, alternative in ipairs(type_.alternatives) do
                local mapped = rep(L_, alternative)
                if not mapped then return nil end
                alternatives:insert(mapped)
            end
            return B.Sum(alternatives)
        end
        if type_ == Semantic.CString then return B.CString end
        if type_ == Semantic.CPointer then return B.CPointer end
        -- A record's representation is a record of its members' representations, so the mapping is
        -- recursive and the mutability of a member is part of the representation (§3.7).
        if Semantic.Aggregate:isclassof(type_) then
            local fields = L()
            for _, field in ipairs(type_.fields) do
                local field_type = rep(L_, field.type)
                if not field_type then return nil end
                fields:insert(B.Field(field.name, field_type, field.mutable))
            end
            return B.Aggregate(fields)
        end
        return nil
    end

    local function stages_of(template)
        local stages = {}
        for _, item in ipairs(template.items) do
            if Chain.Stage:isclassof(item) then stages[#stages + 1] = item end
        end
        return stages
    end

    ---------------------------------------------------------------------------------------------
    -- The lowerer: the demanded set, the functions produced, and the lookup tables a declaration
    -- needs. All of it is progress on one transition, so it lives beside `Unit`, not on a God
    -- object.
    ---------------------------------------------------------------------------------------------

    local function lowerer(unit, program)
        local L_ = { unit = unit, program = program, demanded = {}, functions = {},
                     next_id = 0, diagnostic = nil,
                     definitions = {}, declarations = {}, names = {}, types = {} }
        for _, definition in ipairs(program.definitions) do
            L_.definitions[definition.id] = definition
            L_.declarations[definition.id] = definition.declaration
            L_.names[definition.id] = definition.name
        end
        for _, entry in ipairs(program.typed) do L_.types[entry.definition] = entry.interface end
        -- The one thing `Judge.word_of` needs from this layer: where a declaration lives (§S101). It is
        -- a function rather than the table because `Resolve` keeps the same table in the other shape --
        -- it holds the DEFINITION and the declaration is its `.declaration` field.
        L_.lookup = function(id) return L_.declarations[id] end
        -- §3.2's captures, indexed BOTH ways: by the binder a body names, and by the binding whose
        -- storage that binder is -- because that second one is the binding that has to become a CELL.
        -- A capture is not a copy of the owner's state; it is a second name for the same storage.
        L_.capture_of_binder, L_.capture_of_owner = {}, {}
        for _, definition in ipairs(program.definitions) do
            local declaration = definition.declaration
            if Judge.Word:isclassof(declaration) then
                for _, capture in ipairs(declaration.word.captures or {}) do
                    L_.capture_of_binder[capture.binder] = capture
                    local inner = L_.definitions[capture.binder]
                    if inner then
                        L_.capture_of_owner[inner.declaration.value.definition] = capture
                    end
                end
            end
        end
        -- What destroys a value of each named type, by name. §3.6 puts the destructor in the type's
        -- DECLARATION, and §3.3 puts destruction in `Lower`, so this is where the two meet.
        L_.destructors = {}
        for _, definition in ipairs(program.definitions) do
            local declaration = definition.declaration
            if Judge.Host:isclassof(declaration) and declaration.destroys then
                L_.destructors[definition.name] = declaration.destroys
            end
        end
        return L_
    end

    -- Reserve an instance's id before lowering it, so a cycle finds the id rather than recursing.
    local function demand(L_, key, build)
        local existing = L_.demanded[key]
        if existing then return existing end
        L_.next_id = L_.next_id + 1
        local id = L_.next_id
        L_.demanded[key] = id
        local belt, diagnostic = build(L_, id)
        if not belt then L_.diagnostic = diagnostic; return nil end
        L_.functions[id] = belt
        return id
    end

    ---------------------------------------------------------------------------------------------
    -- Regions. Each instance gets its own `Function` child, and within it a region owns the current
    -- block, the locations and the effect thread.
    ---------------------------------------------------------------------------------------------

    -- A draft block. Blocks are indexed from ONE in their function, and an `Edge` names a block by
    -- that id -- so a split can wire a join before the join's own body exists.
    local function new_block(C)
        local block = { parameters = L{}, instructions = L{}, id = #C.out.blocks + 1 }
        C.out.blocks:insert(block)
        return block
    end

    local function open(L_, name)
        local node = L_.unit:child{ instance = name }
        local C = node:region()
        C.out.name = name
        C.out.next_value = 0
        C.out.blocks = L{}
        local entry = new_block(C)
        C.state.block = entry
        C.state.locations = {}
        C.state.values = {}      -- definition id -> the belt value standing for it
        C.state.places = {}      -- definition id -> §1.4's Initialized | Moved
                                 -- (progress: the scan's current point, not a fact in a value)
        return C
    end

    local function parameter(C, type_, capability)
        local block = C.state.block
        local position = #block.parameters
        block.parameters:insert(B.Parameter(type_, capability))
        local value = { id = C.out.next_value, type = type_ }
        C.out.next_value = C.out.next_value + 1
        C.state.locations[value.id] = { position = position, output = 0 }
        return value
    end

    local function ref(C, value)
        local at = C.state.locations[value.id]
        local position = #C.state.block.parameters + #C.state.block.instructions
        return B.Ref(position - 1 - at.position, at.output)
    end

    local function emit(C, op, types)
        local block = C.state.block
        local position = #block.parameters + #block.instructions
        block.instructions:insert(B.Instruction(op, types, nil))
        local values = L()
        for i = 1, #types do
            local value = { id = C.out.next_value, type = types[i] }
            C.out.next_value = C.out.next_value + 1
            C.state.locations[value.id] = { position = position, output = i - 1 }
            values:insert(value)
        end
        return values
    end

    local function pure(C, op, type_) return emit(C, B.Pure(op), L{type_})[1] end

    -- An ordered operation produces its effect successor **last**, and the region carries it: that
    -- is what keeps the effect chain unbroken without the emitter inventing a value for it.
    local function ordered(C, op, type_)
        local types = type_ and L{type_, B.Effect} or L{B.Effect}
        local values = emit(C, B.Ordered(op), types)
        C.state.effect = values[#types]
        if type_ then return values[1] end
    end

    local function freeze(C, results, exported)
        -- Every draft block, frozen in id order: a split's arms and join are blocks of the SAME
        -- function, so the function's body is the list, not the block the region happened to end in.
        local blocks = L()
        for _, block in ipairs(C.out.blocks) do
            blocks:insert(B.Block(block.parameters, block.instructions, block.exit))
        end
        return B.Function(C.out.name, B.Signature(C.out.blocks[1].parameters, results), blocks,
            exported and true or false)
    end

    ---------------------------------------------------------------------------------------------
    -- The packet. `R(t,k)` is the record after k stable stages, and its members are exactly the
    -- chain's declarations in the order the chain produced them: group 0's preludes, stage 0,
    -- group 1's preludes, stage 1, ..., group k's preludes.
    ---------------------------------------------------------------------------------------------

    local function packet_of(L_, template, k) return template:members(k) end

    local function packet_members_are_in_chain(L_, template, k)
        local members = {}
        -- §2.2: `R(t,k) = captures + stage values 0…k-1 + prelude bindings of groups 0…k`. The
        -- captures are the FRAME, so they come first at EVERY prefix -- which is what makes the packet
        -- structurally the same record at every stage, and what lets a nested word reach the storage
        -- its enclosing instance owns.
        for _, capture in ipairs(template.captures or {}) do
            members[#members + 1] = capture.binder
        end
        for _, item in ipairs(template.items) do
            if Chain.Group:isclassof(item) then
                if item.at <= k then
                    for _, id in ipairs(item.preludes) do
                        members[#members + 1] = id
                    end
                end
            elseif item.index < k then
                members[#members + 1] = item.binder
            end
        end
        return members
    end

    local field_type_of

    -- What a name HOLDS, which is the question every packet field and every place's content asks.
    -- §2.4's ERASURE, as ONE question: a type word is "evaluated at construction time and erased", so
    -- a definition whose interface result is a type word has NO runtime presence -- no slot, no packet
    -- member, nothing to materialize. `rep` answers nil for `TypeWord` and that is CORRECT (a type word
    -- is not a layout); the builders ask THIS instead, which is why `let P = Int` then `x : P` compiles
    -- while `P` never becomes a value. It was `Missing(TypeWordValue)` while the erasure was absent --
    -- a name for a gap, not for a mechanism -- and the mechanism is what the callers now consult.
    -- §S110: and a type that MENTIONS a variable is not a layout either -- `rep` answers nil for it,
    -- correctly -- so a definition whose type mentions one (a generic word, or a binding of one) has no
    -- runtime presence UNTIL IT IS INSTANTIATED, and an instance is concrete by construction because the
    -- substitution happened in `Resolve`.
    local function erased(L_, id)
        local interface = L_.types[id]
        if interface == nil then return false end
        if Semantic.TypeWord:isclassof(interface.result) or interface.result:mentions_variable() then
            return true
        end
        -- §S110: and a word whose STAGES do is erased for the same reason -- a `Type` stage is a
        -- PARAMETER (there is nothing to store), and a stage typed by a variable has no layout until an
        -- instantiation supplies one. So a generic word has no runtime presence at all: what runs is
        -- the INSTANCE, and an instance is concrete by construction.
        for _, stage in ipairs(interface.stages) do
            if Semantic.TypeWord:isclassof(stage.type) or stage.type:mentions_variable() then
                return true
            end
        end
        return false
    end

    local function belt_type_of(L_, id)
        local declaration = L_.declarations[id]
        if Judge.Bound:isclassof(declaration) then return rep(L_, declaration.declared) end
        -- A WORD's value is its PACKET and not its result (§2.2), and a CAPTURE's value is whatever the
        -- binding it captures holds -- its own declaration is a second NAME for somebody else's
        -- storage, so following it is the difference between typing the frame and typing its answer.
        --
        -- ONLY a capture may be followed, and `L_.capture_of_binder` is that question. Asking it
        -- STRUCTURALLY -- "a Value whose value is a Reference" -- also matched an ordinary binding
        -- that happens to hold a word value, so `let chosen : square | inc = inc` was typed as the
        -- PACKET, the sum was never injected, and the host got `uint8_t` where the module struct
        -- wanted the sum. The captures are known before anything is lowered (`Judge.Resolved`
        -- carries them), so this is the definition rather than a proxy for it.
        if L_.capture_of_binder[id] and declaration and Judge.Value:isclassof(declaration)
                and Judge.Reference:isclassof(declaration.value) then
            local outer = L_.declarations[declaration.value.definition]
            if outer and Judge.Word:isclassof(outer) then
                return residual_type(L_, outer.word, 0)
            end
        end
        local interface = L_.types[id]
        return interface and rep(L_, interface.result)
    end

    -- The SEMANTIC counterpart of `belt_type_of`, and it exists because §3.5's injection is a question
    -- about MEANING rather than shape: a word definition's slot holds a word VALUE, so its type is
    -- nominal in the definition itself (§S3) and is not `L_.types[id].result`, which is what the word
    -- RETURNS. That is the same rule `Contract` reads off a Reference (`type_of`), derived here from
    -- the same declaration -- the shape §S92 already uses for copyability, and the reason the two
    -- layers agree without either asking the other.
    local function slot_type_of(L_, id)
        local declaration = L_.declarations[id]
        if Judge.Bound:isclassof(declaration) then return declaration.declared end
        if L_.capture_of_binder[id] and declaration and Judge.Value:isclassof(declaration)
                and Judge.Reference:isclassof(declaration.value) then
            local outer = L_.declarations[declaration.value.definition]
            if outer and Judge.Word:isclassof(outer) then
                return Semantic.Word(declaration.value.definition, 0)
            end
        end
        local interface = L_.types[id]
        return interface and interface.result
    end

    residual_type = function(L_, template, k)
        local fields = L()
        for _, id in ipairs(packet_of(L_, template, k)) do
            local field_type = field_type_of(L_, id)
            local type_ = field_type
            if not type_ then return nil end
            fields:insert(B.Field(L_.names[id], type_, false))
        end
        return B.Aggregate(fields)
    end

    -- The word a callee names, and how many stages it already holds. The question is `Judge.word_of`'s
    -- (§S101), because `Resolve` asks it too -- a name in TYPE position is the type of the value it
    -- denotes -- and two copies of this walk is the defect this design keeps finding. The only thing
    -- this layer adds is where declarations live.
    local function word_of(L_, initializer)
        return Judge.word_of(L_.lookup, initializer)
    end

    ---------------------------------------------------------------------------------------------
    -- Initializers. One alternative plus its method.
    ---------------------------------------------------------------------------------------------

    -- Forward declarations: an application demands a callee's instance, and the builders below are
    -- what run when it does, so the dependency runs both ways.
    local build_construct, build_advance, build_run, lower_body, lower_if, lower_while, is_cell,
        place_value, capture_arguments, lower_place, live, arguments_of, destroy_value, destroy_sum,
        lower_element
    local lower_assign, lower_switch, lower_short_circuit, lower_entry

    -- The construction of a word value: `construct` plus §2.2's capture frame, in ONE place, because
    -- three sites build `R(t,0)` -- naming a word, supplying its first stage, and invoking it with no
    -- arguments -- and the capture arguments must be computed in the ENCLOSING instance in all three.
    local function construct_base(L_, C, template, word)
        local construct = demand(L_, 'construct:' .. template, function(M, id)
            return build_construct(M, template, id)
        end)
        if not construct then return nil, L_.diagnostic end
        local captures, diagnostic = capture_arguments(L_, C, word)
        if not captures then return nil, diagnostic end
        return ordered(C, B.CallFunction(construct, ref(C, C.state.effect), captures),
            residual_type(L_, word, 0))
    end

    -- The base of an application, `R(t,0)`: CONSTRUCTED when the callee is a word named in this scope,
    -- and READ when it is a CAPTURE. §3.2's "one indirection" is exactly this -- the packet already
    -- exists, in the enclosing instance's frame or behind the cell it holds -- so constructing a second
    -- one would give the word a state of its own instead of the owner's, which is the same defect
    -- §S75 records for a module prelude one level up.
    local function base_of(L_, C, template, word, callee)
        if callee and Judge.Reference:isclassof(callee) and L_.capture_of_binder[callee.definition] then
            local p, diagnostic = lower_place(L_, C, callee)
            if not p then return nil, diagnostic end
            return place_value(C, p)
        end
        -- §3.6/§11.1: a stage whose type is a WORD already HOLDS its packet -- the caller built it and
        -- passed it -- so the base is that value rather than a construction from source, which a stage
        -- has none of. This is the other half of naming one: `word_of` says WHICH word, and this says
        -- where its prefix values come from.
        if callee and Judge.Reference:isclassof(callee) then
            local bound = L_.declarations[callee.definition]
            if bound and Judge.Bound:isclassof(bound) and bound.declared
                    and Semantic.Word:isclassof(bound.declared) then
                local p, diagnostic = lower_place(L_, C, callee)
                if not p then return nil, diagnostic end
                return place_value(C, p)
            end
        end
        return construct_base(L_, C, template, word)
    end


    -- A place's state. DESIGN §3.3: ownership is a *sequential scan with an agreement check at
    -- every join*, so the state is progress on the region -- not a dataflow solution and not a
    -- value. A definition is initialized once it is lowered, and `move` is what falsifies it.
    local function place(C, id)
        local state = C.state.places[id]
        if not state then state = { moved = {} }; C.state.places[id] = state end
        return state
    end

    -- Two paths conflict when either contains the other: a moved subplace makes every place that
    -- contains it, and every place inside it, unusable until a value is assigned (§1.4).
    local function contains(outer, inner)
        if outer == inner or outer == '' then return true end
        return inner:sub(1, #outer + 1) == outer .. '.'
    end

    -- §1.4's path check. `intermediate` is a read *through* a place -- a projection reads its base
    -- to reach a member, which never touches a hole elsewhere in it, and §1.4 says so.
    local function check_place(C, root, path, span, intermediate)
        for was in pairs(place(C, root).moved) do
            if contains(was, path) then
                return Report.reject(Report.UninitializedPlace, span)
            end
            if not intermediate and contains(path, was) then
                return Report.reject(Report.PartiallyInitialized, span)
            end
        end
    end

    local materialize

    -- Take ownership of a place: §1.4's `move place`. On a Copy place it is that value, copied,
    -- and the place stays initialized; on a non-Copy one the source becomes uninitialized. The
    -- transfer is recorded in the belt as a `Move`, which has no runtime representation of its
    -- own -- the value is already in hand, and the source is simply not destroyed.
    -- §3.1's second rule: "destruction: reverse initialization order, at scope exit / return /
    -- replacement." This is the SCOPE EXIT half, and it is a scan rather than an analysis for the
    -- same reason ownership is (§3.3): the region's environment already says what is live, and the
    -- place state already says what was moved out. A moved-out binding has no value left to destroy,
    -- which is why a `move` out of a scope is not a leak.
    --
    -- Whether a value of this type must be DESTROYED. A derived property, like Copy (§2.5) and
    -- derived the same way -- structurally, from the type: a declared host type says so in its
    -- declaration (§3.6), a record says so if ANY member does, and a scalar owns nothing. It is the
    -- mirror image of Copy, which asks whether every member is Copy.
    local destroys
    destroys = function(L_, type_)
        if not type_ then return false end
        if Semantic.Named:isclassof(type_) then return L_.destructors[type_.name] ~= nil end
        if Semantic.Aggregate:isclassof(type_) then
            for _, field in ipairs(type_.fields) do
                if destroys(L_, field.type) then return true end
            end
        end
        -- §3.5: a sum is destructible when ANY alternative is -- the exact MIRROR of §2.5's `Copy` rule
        -- for a sum ("every alternative"). They cannot be one rule: `Copy` asks whether every part may be
        -- duplicated, while destruction is chosen by the TAG, so one alternative that owns something is
        -- enough to make destroying the sum mean something.
        if Semantic.Sum:isclassof(type_) then
            for _, alternative in ipairs(type_.alternatives) do
                if destroys(L_, alternative) then return true end
            end
        end
        return false
    end

    local function destructor_of(L_, id)
        local interface = L_.types[id]
        if not interface or not destroys(L_, interface.result) then return nil end
        return interface.result
    end

    -- §12.3: "a block's parameters are `[Effect] + the values live at the split`, and an edge's arguments
    -- match them one for one" -- so a value that has to CROSS a split must be nameable, and a lowered
    -- value that is not a definition (a call's result, a load, a field read) is not. This is the same
    -- reason §S34's switch subject is bound, and it is the only binding this phase invents.
    local function name_it(L_, C, value, type_)
        L_.synthetic = (L_.synthetic or 0) - 1
        C.state.values[L_.synthetic] = value
        return L_.synthetic
    end

    -- Will destroying this build BLOCKS? A sum's destruction is a dispatch on its tag (§3.5), and a
    -- record's is one when a member's is. Asked by the RETURN path, because a value that crosses a split
    -- has to be named and naming one that stays put would put a C variable in every function.
    local function dispatches(L_, type_)
        if Semantic.Sum:isclassof(type_) then
            for _, alternative in ipairs(type_.alternatives) do
                if destroys(L_, alternative) then return true end
            end
            return false
        end
        if Semantic.Aggregate:isclassof(type_) then
            for _, field in ipairs(type_.fields) do
                if destroys(L_, field.type) and dispatches(L_, field.type) then return true end
            end
        end
        return false
    end

    -- Every binding THIS region introduced whose type declares a destructor, in initialization
    -- order. A region's `values` is the carried parameters plus what it bound itself, and only the
    -- second has a scope that ends with the region -- a parameter belongs to whoever created it.
    -- That is the same distinction the interface draws, so it is drawn the same way: a parameter's
    -- position is inside the parameter list.
    local function destroyable(L_, C)
        local found = {}
        for id, value in pairs(C.state.values) do
            local location = C.state.locations[value.id]
            -- §3.2: a CAPTURE is not owned HERE. Its storage belongs to the enclosing instance -- one
            -- indirection, shared -- so destroying it from a frame that merely borrowed it destroys the
            -- owner's value a second time. The owner's own scope exit is what destroys it.
            -- ... and a WORD is not owned here either: a word's value is its PACKET (§2.2), while its
            -- interface's result is the type its `run` RETURNS -- so destroying one as a value of that
            -- type hands a host destructor a struct where it wants a handle.
            local declaration = L_.declarations[id]
            if location and location.position >= #C.state.block.parameters
                and not Judge.Word:isclassof(declaration)
                and not L_.capture_of_binder[id] and destructor_of(L_, id) then
                found[#found + 1] = id
            end
        end
        table.sort(found)
        return found
    end

    -- Destroy ONE value, and its parts. §3.1 rule 2 is about INITIALIZATION order, so a record's
    -- members go in reverse member order -- and a member that was moved out has no value left to
    -- destroy, which is the same place state the scan already keeps, one path deeper. Without this a
    -- record that owns a resource destroys only the record, and the resource leaks.
    destroy_value = function(L_, C, root, path, type_, value)
        if Semantic.Named:isclassof(type_) then
            ordered(C, B.Destroy(ref(C, C.state.effect), ref(C, value),
                L_.destructors[type_.name]), nil)
            return
        end
        -- §3.5: a sum's destructor is chosen by its TAG, so it is a dispatch and not a sequence. Until
        -- this existed a sum fell through the line below and NOTHING was emitted for it: a silent leak,
        -- and one only a host counting its own allocations could see (§S81, §S83).
        if Semantic.Sum:isclassof(type_) then
            destroy_sum(L_, C, root, path, type_, value)
            return
        end
        if not Semantic.Aggregate:isclassof(type_) then return end
        for index = #type_.fields, 1, -1 do
            local field = type_.fields[index]
            local inner = path == '' and tostring(index - 1) or (path .. '.' .. (index - 1))
            if destroys(L_, field.type) and not place(C, root).moved[inner] then
                local member = pure(C, B.LoadField(ref(C, value), index - 1), rep(L_, field.type))
                destroy_value(L_, C, root, inner, field.type, member)
            end
        end
    end

    -- Destroy them in REVERSE initialization order, which is rule 2's other half.
    local function destroy_all(L_, C)
        local found = destroyable(L_, C)
        for index = #found, 1, -1 do
            local id = found[index]
            if not place(C, id).moved[''] then
                -- §S32: a cell's VALUE is its address, so destroying what it holds is a LOAD of
                -- the content and not a call on the storage. Without this the emitter hands the
                -- destructor `&v` where it wants a value -- invalid C for a host type, and a
                -- destroy of the wrong thing for a record, whose members are read off `value`.
                local value = C.state.values[id]
                if is_cell(L_, id) then
                    -- `belt_type_of` and not `L_.types[id].result`: the Load produces the CONTENT,
                    -- and the interface's result is the content's SEMANTIC type -- what a cell holds
                    -- is a belt type, and `destroy_value` below still wants the semantic one.
                    value = ordered(C, B.Load(ref(C, C.state.effect), ref(C, value)),
                        belt_type_of(L_, id))
                end
                destroy_value(L_, C, id, '', L_.types[id].result, value)
            end
        end
    end

    -- §3.2's table has three rows and this decides between them: "captured by a sibling word ⇒ celled
    -- (one indirection)", "captured read of a Copy value ⇒ copied; no cell", "not captured ⇒ zero
    -- cost". Celling is therefore a property of the (mode, type) PAIR, derived here and asked twice --
    -- once for the capture's own binder and once for the binding it captures -- because the cell IS
    -- the owner's storage: one indirection, shared, and no second allocation.
    local copyable

    -- §2.5: `Copy` is derived, and a WORD's value is its PACKET, so a word type is Copy exactly when
    -- every member of that packet is -- the rule a record follows, asked of a template because that is
    -- where the members are named. `Semantic.Word(template, prefix)` cannot answer it (it names its
    -- template by NUMBER and `Semantic` sits below `Chain`, §11.4), which is the same reason `rep` takes
    -- the lowerer. Until this existed a word value the design calls COPY -- an imported file's
    -- namespace, whose only member is an `Int`-staged word -- was reported non-Copy, so `import` could
    -- not even be bound.
    local function word_value_is_copy(L_, template, k)
        for _, id in ipairs(template:members(k)) do
            local declaration = L_.declarations[id]
            local type_ = Judge.Bound:isclassof(declaration) and declaration.declared
                or (L_.types[id] and L_.types[id].result)
            if not copyable(L_, type_) then return false end
        end
        return true
    end

    copyable = function(L_, type_)
        if not type_ then return false end
        if Semantic.Word:isclassof(type_) then
            local declaration = L_.declarations[type_.template]
            if not declaration or not Judge.Word:isclassof(declaration) then return false end
            return word_value_is_copy(L_, declaration.word, type_.prefix)
        end
        -- A record or a sum CONTAINING a word is why this cannot simply be `type_:copyable()`: the
        -- semantic derivation recurses into its members by asking `Semantic.Word`, which cannot see a
        -- template -- so a namespace whose only member is a word was reported non-Copy and could not be
        -- bound at all. Recursing HERE keeps one rule and reaches every member.
        if Semantic.Aggregate:isclassof(type_) then
            for _, field in ipairs(type_.fields) do
                if not copyable(L_, field.type) then return false end
            end
            return true
        end
        if Semantic.Sum:isclassof(type_) then
            for _, alternative in ipairs(type_.alternatives) do
                if not copyable(L_, alternative) then return false end
            end
            return true
        end
        return type_:copyable()
    end

    -- The type of a name's SLOT in a packet -- the question `residual_type`, `unpack` and
    -- `build_construct` all ask. It is NOT `belt_type_of`, which answers what reading the place GIVES:
    -- a celled capture's slot holds the owner's ADDRESS (§3.2's one indirection), so the slot is a
    -- cell while the content is a value, and one answer cannot be both.
    local capture_is_celled

    -- The type of a name's SLOT in a packet -- the question `residual_type`, `unpack` and
    -- `build_construct` all ask. It is NOT `belt_type_of`, which answers what reading the place GIVES:
    -- a CELLED binding's slot holds its ADDRESS (§3.2's one indirection), so the slot is a cell while
    -- the content is a value, and one answer cannot be both. `is_cell` is the whole rule -- captures,
    -- `mut`, and interior mutability -- and it is the same question `materialize` asks before it
    -- allocates, so a slot and its value cannot disagree about which of the two it is (§S84).
    field_type_of = function(L_, id)
        local content = belt_type_of(L_, id)
        if not content then return nil end
        if is_cell(L_, id) then return B.Cell(content) end
        return content
    end

    capture_is_celled = function(L_, capture)
        if capture.mode == Semantic.Mut then return true end
        local inner = L_.definitions[capture.binder]
        local outer = inner and inner.declaration.value.definition
        local declaration = outer and L_.declarations[outer]
        -- A WORD's value is its PACKET (§2.2), so §3.2's cheap row asks whether every member of that
        -- packet is Copy -- and an EMPTY packet is Copy, which is the case of an extern or a pure
        -- word: there is nothing to own, so one indirection would buy nothing.
        if declaration and Judge.Word:isclassof(declaration) then
            return not word_value_is_copy(L_, declaration.word, 0)
        end
        local interface = L_.types[capture.binder]
        return interface ~= nil and not copyable(L_, interface.result)
    end

    -- A binding is a CELL when it is declared `mut`. §3.4 makes such a binding a writable
    -- destination, and a destination is a location rather than a name for a value; §3.2's cell is
    -- that location. Because the cell is a *value* whose identity is fixed at its declaration,
    -- assignment never forces a phi at a join -- the cell is the same on every path and only its
    -- contents change. That is the whole reason cells are the representation for assignment.
    is_cell = function(L_, id)
        local declaration = L_.declarations[id]
        if declaration == nil or not Judge.Value:isclassof(declaration) then return false end
        if declaration.mutable then return true end
        -- §3.7: a `mut` MEMBER is interior mutability -- the value is writable through the name
        -- whatever the binding's own mutability says -- so the binding is a cell for exactly the
        -- reason a `mut` binding is: writing through a projected place needs the storage addressable.
        -- Derived from the type (§S71), and asked of the INTERFACE because a binding need not carry an
        -- annotation -- `let r = { let x mut = 1 }` has no declared type to read. What made this
        -- collide before was §3.2's conflict, which is conditional and was being applied
        -- unconditionally; a non-Copy record in a cell can now be MOVED, which is what lets it be
        -- exported and read by its owner rather than copied.
        if L_.types[id] ~= nil and L_.types[id].result:interior_mutability() then return true end
        -- §3.2: and a binding somebody CAPTURES is address-taken, because the capture is a pointer to
        -- its storage rather than a copy of it. This is the reason §S71's condition had none: "moving
        -- the owner while a view is live" was satisfiable only in the vacuous case, because no view
        -- existed anywhere for a `mut` binding to conflict with.
        local capture = L_.capture_of_binder[id] or L_.capture_of_owner[id]
        return capture ~= nil and capture_is_celled(L_, capture)
    end

    local function take_place(L_, C, p, span)
        -- §3.2's conflict is CONDITIONAL: "moving ... the owner WHILE A VIEW IS LIVE is a conflict."
        -- A view is a pointer into the storage, and this phase has no pointers that outlive an
        -- expression -- the field addresses `FieldAddress` builds do not, and captures are not built
        -- at all -- so the condition is not met and a cell can be moved out of. Equating "celled"
        -- with "viewed" was the condition DROPPED, and it made every `mut` binding immovable, which
        -- is what made §3.7's interior mutability collide with moves, reads and export (§S70).
        local diagnostic = check_place(C, p.root, p.path, span, false)
        if diagnostic then return nil, diagnostic end
        -- What is handed over is what the place HOLDS, and for a cell that is its content: a cell's
        -- value is its address (§S32), so the storage is not the value.
        local value = place_value(C, p)
        if copyable(L_, p.type) then return value end
        -- §3.2's condition, now REAL: "moving ... the owner WHILE A VIEW IS LIVE is a conflict", and a
        -- **celled** capture is exactly that view -- a pointer into this storage, alive in another
        -- word's frame -- while a copied one is a copy and conflicts with nothing. The check belongs
        -- HERE and not earlier, because a Copy read is not a move at all: `c = c + 1` reads the old
        -- value to destroy it, and refusing that would call a correct program wrong. §S71 recorded
        -- this check as correct and VACUOUS, and said captures were the piece that would give it
        -- meaning; this is that piece arriving.
        -- The question is about the OWNER's storage, so a move written THROUGH a capture (`move c`
        -- inside a word that captures `c`) asks about the binding the capture is a second name for and
        -- not about the capture's own binder -- otherwise the rule would depend on which word happened
        -- to be asking, which is exactly the kind of accident a rule must not have.
        local owner = p.root
        local through = L_.capture_of_binder[owner]
        if through then owner = L_.definitions[owner].declaration.value.definition end
        local view = L_.capture_of_owner[owner]
        if view and capture_is_celled(L_, view) then
            return nil, Report.reject(Report.ConflictingBorrow, span)
        end
        ordered(C, B.Move(ref(C, C.state.effect), ref(C, value)), nil)
        place(C, p.root).moved[p.path] = true
        return value
    end

    -- A name is the root place: everything lives in a definition, and the empty path is it.
    local function take(L_, C, id, span)
        local value = C.state.values[id]
        if not value then
            local lowered, diagnostic = materialize(L_, C, id, span)
            if not lowered then return nil, diagnostic end
            value = lowered
        end
        -- The place carries whether it is a CELL, because that is what decides if it can be moved
        -- out of at all (§3.2) and whether a read loads it. A place record that omitted it would
        -- silently treat a cell as an ordinary value.
        local cell = is_cell(L_, id)
        return take_place(L_, C, { value = value, path = '', type = L_.types[id].result, root = id,
            cell = cell, content = cell and belt_type_of(L_, id) or nil }, span)
    end

    -- Read a place as a value: the path check, then §1.4's rule that an existing non-copyable
    -- place must be moved rather than read -- a read is a borrow, and a borrow is not a value.
    -- §S69: a place is a LOCATION and a value is what reading it gives. This is the ONE place that
    -- turns one into the other, so a read and a move cannot disagree about what a place holds -- which
    -- they did the moment `lower_place` stopped building a value for a place that has an address.
    place_value = function(C, p)
        if p.cell and p.path == '' then
            return ordered(C, B.Load(ref(C, C.state.effect), ref(C, p.value)), p.content)
        end
        if p.address then
            local field_address = pure(C, B.FieldAddress(ref(C, p.address), p.offset),
                B.Cell(rep(L_, p.type)))
            return ordered(C, B.Load(ref(C, C.state.effect), ref(C, field_address)), rep(L_, p.type))
        end
        return p.value
    end

    local function read_place(L_, C, p, span)
        -- §1.4 decided what a read COSTS, and a cell is the one place it is not a copy: a cell is
        -- STORAGE, so reading it is a load. A load of something that cannot be copied would hand
        -- out a second owner of the same value -- so a non-Copy binding that is `mut` is
        -- unreadable: it cannot be copied, and §3.2 forbids moving out of a live cell, which is the
        -- same fact `take_place` states from the other side (`ConflictingBorrow`).
        local diagnostic = check_place(C, p.root, p.path, span, false)
        if diagnostic then return nil, diagnostic end
        -- §1.4: a read of a non-Copy place is not a copy, and a cell read is a load -- so a load of
        -- something that cannot be copied would hand out a second owner. The checks come first, so a
        -- refused read builds nothing at all.
        if not copyable(L_, p.type) then return nil, Report.reject(Report.NeedsMove, span) end
        return place_value(C, p)
    end

    -- Walk a place: the aggregate it lives in, the path to it, and its semantic type. The path is
    -- what partial initialization is keyed by, so it is built as the place is walked.
    lower_place = function(L_, C, initializer)
        if Judge.Reference:isclassof(initializer) then
            local value = C.state.values[initializer.definition]
            if not value then
                local lowered, diagnostic = materialize(L_, C, initializer.definition, initializer.span)
                if not lowered then return nil, diagnostic end
                value = lowered
            end
            local cell = is_cell(L_, initializer.definition)
            return { value = value, path = '', type = L_.types[initializer.definition].result,
                     root = initializer.definition, cell = cell,
                     content = cell and belt_type_of(L_, initializer.definition) or nil }
        end
        if Judge.Project:isclassof(initializer) or Judge.Index:isclassof(initializer) then
            local base, diagnostic = lower_place(L_, C, initializer.base)
            if not base then return nil, diagnostic end
            diagnostic = check_place(C, base.root, base.path, initializer.span, true)
            if diagnostic then return nil, diagnostic end
            -- A projection is a RECORD's field read and nothing else. A sum has no members: its
            -- payload is reached by the arm that MATCHED it (§S59), which `Contract` enforces
            -- before this runs -- so there is no fallible read to make safe here.
            local offset, field
            if Judge.Project:isclassof(initializer) then
                for index, candidate in ipairs(Semantic.Aggregate:isclassof(base.type)
                        and base.type.fields or {}) do
                    if candidate.name == initializer.name then offset, field = index - 1, candidate end
                end
                if not offset then return nil, Report.reject(Report.UnknownName, initializer.span) end
            else
                offset = initializer.offset
                field = Semantic.Aggregate:isclassof(base.type) and base.type.fields[offset + 1]
                if not field then return nil, Report.reject(Report.IndexOutOfRange, initializer.span) end
            end
            -- A projection through a CELL loads first: the cell is the record's storage, so the
            -- record the field is read from is its contents. The result is an ordinary value, so
            -- the projected place is not itself a cell -- which is why a field of a `mut` binding
            -- cannot be moved out of while the cell is live (§3.2).
            -- §S69: reading a MEMBER is a different question from reading the RECORD. When the base
            -- lives in storage -- a cell, or a chain of them -- the field is read through the
            -- STORAGE: its address, then a `Load`. The old shape loaded the whole record into a
            -- temporary first, and that is a copy of an owning value whenever the record is not
            -- `Copy` -- which a record with a `mut` member is not (§2.5), so the very case §3.7 is
            -- about was the one that could not be read.
            --
            -- §S68: an address CHAINS. A projection's address is the address of the record that
            -- CONTAINS its field -- exactly what `StoreField` takes, and it prints
            -- `(*addr).field = v` -- so one level is the base's own storage and a deeper one is the
            -- field's address taken through it.
            local address = base.value
            if not base.cell then
                if base.address then
                    address = pure(C, B.FieldAddress(ref(C, base.address), base.offset),
                        B.Cell(rep(L_, base.type)))
                else
                    address = nil
                end
            end
            -- §S69: a place is a LOCATION and a value is what reading it gives, so this builds a
            -- value only for the path that has no address at all -- a field of a VALUE -- where it
            -- is read off the value itself and costs no copy. Where there IS an address the value
            -- belongs to `read_place`, which also means a store destination never builds one: that
            -- is what removed a whole-record copy from every projected store.
            local value
            if not address then
                value = pure(C, B.LoadField(ref(C, base.value), offset), rep(L_, field.type))
            end
            local path = base.path == '' and tostring(offset) or (base.path .. '.' .. offset)
            return { value = value, path = path, type = field.type, root = base.root,
                     offset = offset, cell = false, depth = (base.depth or 0) + 1,
                     -- The CELL to store through, when there is one. A read needs the loaded
                     -- record; a write needs the storage. They are different questions and the
                     -- place carries both, so `r.x = v` has somewhere to put the write.
                     address = address }
        end
        if Judge.Element:isclassof(initializer) then
            -- A runtime index is not a PLACE: a place is one address and the index decides WHICH address
            -- at run time. `lower_element_store` answers a destination and `lower_element` a value, so
            -- reaching here means one of them missed a case -- the compiler disagreeing with itself.
            return nil, Report.bug(Report.NoLowering('element place'), initializer.span)
        end
        return nil, Report.bug(Report.NoLowering('place'), initializer.span)
    end

    -- §2.6: "a word's fields come from the namespace". This is the ONE place a capture's value is
    -- computed, and it is computed in the ENCLOSING instance -- where the captured binding is either
    -- that instance's own storage or one of its OWN captures, so a capture of a capture chains with
    -- no new vocabulary. A celled capture passes the owner's ADDRESS, which is why one indirection is
    -- enough and why nothing is copied: the capture and the owner are the same cell.
    capture_arguments = function(L_, C, template)
        local values = L()
        for _, capture in ipairs(template.captures or {}) do
            local definition = L_.definitions[capture.binder]
            local outer = definition.declaration.value.definition
            -- If THIS instance already holds the binding -- because it is itself a word that captures
            -- it -- then that IS the value. §3.2's one indirection is the OWNER's storage, so a
            -- recursive or nested construction hands on what it was given instead of rebuilding it,
            -- which is exactly what stopped `f`'s recursive call from constructing `made` again.
            local source
            for id in pairs(C.state.values) do
                local held = L_.capture_of_binder[id]
                if held and L_.definitions[id].declaration.value.definition == outer then
                    source = id
                    break
                end
            end
            local outer, diagnostic
            if source then
                outer, diagnostic = lower_place(L_, C, Judge.Reference(source, definition.span))
            else
                outer, diagnostic = lower_place(L_, C, definition.declaration.value)
            end
            if not outer then return nil, diagnostic end
            -- A celled capture passes the owner's ADDRESS -- a cell's value IS its address -- and a
            -- copied one passes what reading the place gives. That single branch is §3.2's whole table.
            -- A `Belt.Ref`, like every other argument list: the caller's operand convention is the
            -- belt's, and the numbering rule is that every operand's ref is computed after all of them
            -- are emitted -- which is why the values are collected here and referred to at the call.
            local value = capture_is_celled(L_, capture) and outer.value or place_value(C, outer)
            values:insert(ref(C, value))
        end
        return values
    end

    -- §3.6's borrow, as opposed to §1.4's move: the place must be initialized and readable, but a
    -- non-Copy value is FINE here -- that is the whole point of viewing one. `read_place` refuses a
    -- non-Copy read because a read of a place is a value and a borrow is not; a borrow is exactly
    -- what a borrowing stage wants.
    local function lower_borrow(L_, C, initializer)
        local p, diagnostic = lower_place(L_, C, initializer)
        if not p then return nil, diagnostic end
        diagnostic = check_place(C, p.root, p.path, initializer.span, false)
        if diagnostic then return nil, diagnostic end
        if p.cell and p.path == '' then
            return ordered(C, B.Load(ref(C, C.state.effect), ref(C, p.value)), p.content)
        end
        return p.value
    end

    -- §1.5's operators, as DATA -- and one table per question, because the division is not the same
    -- for operands as it is for results. A comparison takes two Ints and produces a Bool, while
    -- `and`, `or` and `not` are Bool to Bool because they are about truth and not arithmetic. The
    -- check in §12.2 and these two rules must state the same thing, and the folding rule in `Known`
    -- must not disagree with either: `not`'s operand was the one place they did, because it was
    -- being lowered with the Int that arithmetic asks for.
    local COMPARISON = {
        [Semantic.Equal] = true, [Semantic.NotEqual] = true, [Semantic.Less] = true,
        [Semantic.LessEqual] = true, [Semantic.Greater] = true, [Semantic.GreaterEqual] = true,
    }
    local TRUTH = { [Semantic.Not] = true, [Semantic.And] = true, [Semantic.Or] = true }

    local function operand_type_of(operator)
        return TRUTH[operator] and B.Bool or B.Int
    end
    local function result_type_of(operator, left)
        return (TRUTH[operator] or COMPARISON[operator]) and B.Bool or left
    end

    -- §S61: a term's type is not a question this layer ASKS, it is what lowering the term
    -- PRODUCES -- §11.7's `Instruction` already carries its results -- so `type_` below means one
    -- thing only: the type the value must BECOME. Every branch produces a value that says its own
    -- type, and the injection is decided by reading that value instead of re-deriving it.
    -- §3.5/§S48's injection: WHICH alternative the value already inhabits. The question is SEMANTIC and
    -- it has to be asked semantically, because the belt representation of two alternatives can be ONE
    -- type -- two word values with empty packets are both `uint8_t` -- and then `Belt.Sum:alternative`
    -- finds two matches and the first was taken. That is a WRONG PROGRAM rather than a wrong message,
    -- and at a borrowed stage it was no injection at all, which `cc` reported as a type error.
    --
    -- A word value's identity is nominal in `(template, prefix)` and `Lower` derives it from the
    -- DECLARATION (`word_of`), which is the same answer that selects a callee (§S99); every other
    -- type's equality is mirrored by the belt (§S49), so the representation is asked only after the
    -- declaration has been. When neither can say, that is a disagreement with `Contract` -- which
    -- accepted the program, so it decided an alternative -- and it is reported rather than skipped.
    local function injection_tag(L_, initializer, value, semantic, type_)
        if semantic and Semantic.Sum:isclassof(semantic) then
            local template, prefix = word_of(L_, initializer)
            if template then
                local index, count = semantic:alternative(Semantic.Word(template, prefix))
                if index and count == 1 then return index end
            end
        end
        local index, count = type_:alternative(value.type)
        if index and count == 1 then return index end
        return nil
    end

    -- §3.5's construction, in ONE place: a site that expects a sum and a value that is not one.
    local function inject(L_, C, type_, semantic, value, initializer)
        if not type_ or not B.Sum:isclassof(type_) then return value end
        if B.Sum:isclassof(value.type) then return value end
        local tag = injection_tag(L_, initializer, value, semantic, type_)
        if not tag then
            return nil, Report.bug(Report.NoLowering('injection'), initializer.span)
        end
        return pure(C, B.InjectSum(tag, ref(C, value)), type_)
    end

    local function lower_initializer(L_, C, initializer, type_, semantic)
        -- §3.5's construction, and the reason it lives HERE: every construct that expects a type
        -- goes through this function -- a binding, a stage argument, a return, a record member -- so
        -- injection is one rule in one place rather than a case at each site.
        --
        -- §S61: the value is lowered FIRST and its type is read back off the value, so which
        -- alternative it inhabits is answered by the belt rather than derived from the term. The
        -- SEMANTIC type travels beside the belt one because the belt cannot always answer -- see
        -- `injection_tag` -- and it is the DECLARATION that is asked, never the term.
        if type_ and B.Sum:isclassof(type_) then
            local value, diagnostic = lower_initializer(L_, C, initializer, nil)
            if not value then return nil, diagnostic end
            return inject(L_, C, type_, semantic, value, initializer)
        end
        if Judge.Literal:isclassof(initializer) then
            local expr = initializer.value
            -- §S61: a literal's type is its own form, so each of these names the type it
            -- produces rather than being told it -- and a `Text` literal is a `Text`, because a
            -- conversion to `CString` is a dictionary word and never a silent retype (§S42).
            if Syntax.Unit:isclassof(expr) then
                return pure(C, B.UnitLiteral, B.Unit)
            end
            if Syntax.Integer:isclassof(expr) then
                return pure(C, B.IntegerLiteral(expr.spelling), B.Int)
            end
            if Syntax.Float:isclassof(expr) then
                return pure(C, B.FloatLiteral(expr.spelling), B.Float)
            end
            if Syntax.Boolean:isclassof(expr) then
                return pure(C, B.BooleanLiteral(expr.value), B.Bool)
            end
            if Syntax.Text:isclassof(expr) then
                return pure(C, B.TextLiteral(expr.value), B.Text)
            end
            return nil, Report.bug(Report.NoLowering('literal'), expr.span)
        end

        if Judge.Aggregate:isclassof(initializer) then
            -- §3.3: members initialize top to bottom, so each is lowered in order and the record
            -- is a `Construct` of them. A member that is a definition materializes on demand.
            local values = L()
            for i, member in ipairs(initializer.members) do
                -- The record OWNS its members. A member that names a definition is taken from it
                -- -- which for a non-Copy member is a move -- and anything else is an rvalue
                -- already owned. Reading a named member instead would be a borrow, and a borrow
                -- is not something a record can hold (§1.4).
                local value, diagnostic
                if Judge.Reference:isclassof(member.value) then
                    value, diagnostic = take(L_, C, member.value.definition, member.value.span)
                else
                    -- §S61: no type is handed in. The member's own type is what lowering it
                    -- PRODUCES, and passing an expected type here was the last place this layer
                    -- asked a question it can answer by producing one -- it also CRASHED when the
                    -- aggregate was an injection payload, because the expected type is the sum and
                    -- a sum has no `fields` to read a member's type from.
                    value, diagnostic = lower_initializer(L_, C, member.value)
                end
                if not value then return nil, diagnostic end
                values:insert(value)
            end
            -- A ref is relative to the CONSUMER's position, so the refs are computed only once
            -- every operand has been emitted -- the same rule `construct_record` obeys, and the
            -- third time it decides whether the output is right.
            local refs = L()
            for _, value in ipairs(values) do refs:insert(ref(C, value)) end
            -- §S61: the record's type is built from the types the members just PRODUCED -- the
            -- same construction `Contract.type_of` performs on the semantic side, because §10 keeps
            -- a vocabulary per layer and neither has to ask the other for this one.
            local fields = L()
            for i, value in ipairs(values) do
                fields:insert(B.Field(initializer.members[i].name, value.type,
                    initializer.members[i].mutable))
            end
            return pure(C, B.Construct(refs), B.Aggregate(fields))
        end

        -- §3.4's operators. The pure ones are a `Pure.Binary`, which is what lets `Known` fold
        -- them; `/` and `%` are `CheckedBinary` because they TRAP on a zero divisor and a trap
        -- is observable, so the operation is ordered and carries the effect.
        if Judge.Unary:isclassof(initializer) then
            local operand, diagnostic = lower_initializer(L_, C, initializer.operand,
                operand_type_of(initializer.operator))
            if not operand then return nil, diagnostic end
            return pure(C, B.Unary(initializer.operator, ref(C, operand)),
                result_type_of(initializer.operator, operand.type))
        end
        if Judge.Binary:isclassof(initializer) then
            -- §3.4 has `and`/`or` short-circuit, and that is a CONTROL decision rather than an
            -- arithmetic one: the right operand must not run when the left decides.
            if initializer.operator == Semantic.And or initializer.operator == Semantic.Or then
                return lower_short_circuit(L_, C, initializer, B.Bool)
            end
            local operand_type = operand_type_of(initializer.operator)
            local left, diagnostic = lower_initializer(L_, C, initializer.left, operand_type)
            if not left then return nil, diagnostic end
            local right
            right, diagnostic = lower_initializer(L_, C, initializer.right, operand_type)
            if not right then return nil, diagnostic end
            -- Both refs are computed only NOW, because a ref is relative to the CONSUMER and the
            -- consumer is this instruction. Computing one inside the loop that lowers the operands
            -- makes it relative to wherever that loop had reached -- the second corollary.
            if initializer.operator == Semantic.Divide or initializer.operator == Semantic.Remainder then
                return ordered(C, B.CheckedBinary(initializer.operator, ref(C, C.state.effect),
                    ref(C, left), ref(C, right)), B.Int)
            end
            return pure(C, B.Binary(initializer.operator, ref(C, left), ref(C, right)),
                result_type_of(initializer.operator, left.type))
        end

        -- §1.4: `move place` transfers ownership. The place is a name in this slice; a member or
        -- index place arrives with postfix on the left of a place.
        if Judge.Move:isclassof(initializer) then
            local p, diagnostic = lower_place(L_, C, initializer.place)
            if not p then return nil, diagnostic end
            return take_place(L_, C, p, initializer.span)
        end

        -- A projection or a constant index is a place, so reading it is the same question a name
        -- asks: is it initialized, and is it Copy.
        -- §12.1's runtime index, and it is a VALUE and not a place: the dispatch reads one member and
        -- hands it over, so `a[i]` as a destination is a different rule (see the gap below).
        if Judge.Element:isclassof(initializer) then
            return lower_element(L_, C, initializer)
        end

        if Judge.Project:isclassof(initializer) or Judge.Index:isclassof(initializer) then
            local p, diagnostic = lower_place(L_, C, initializer)
            if not p then return nil, diagnostic end
            return read_place(L_, C, p, initializer.span)
        end


        -- §2.6: a name is visible through the namespace, so a Reference to a WORD denotes the word
        -- VALUE `R(t,0)` and not its result -- which is why naming one has to CONSTRUCT it. This
        -- belongs here rather than in `lower_module`, because an imported file's namespace is an
        -- ordinary value that Resolve builds, and its word members need exactly the same treatment.
        if Judge.Reference:isclassof(initializer)
            and Judge.Word:isclassof(L_.declarations[initializer.definition]) then
            local template = initializer.definition
            local word = L_.declarations[template].word
            local value, diagnostic = base_of(L_, C, template, word, initializer)
            if not value then return nil, diagnostic end
            return value
        end

        if Judge.Reference:isclassof(initializer) then
            local p, diagnostic = lower_place(L_, C, initializer)
            if not p then return nil, diagnostic end
            return read_place(L_, C, p, initializer.span)
        end

        if Judge.Apply:isclassof(initializer) then
            local template, prefix = word_of(L_, initializer.callee)
            if not template then
                return nil, Report.reject(Report.NotExecutable, initializer.span)
            end
            local word = L_.declarations[template].word
            local stages = stages_of(word)
            local stage = stages[prefix + 1]
            if not stage then
                -- `word_of` says WHICH word and at WHICH prefix, so a prefix with no stage means an
                -- application of something that is not a word of this callee -- §1.2's saturation
                -- rule, reported rather than indexed.
                return nil, Report.reject(Report.Oversaturated, initializer.span)
            end
            local argument_type = rep(L_, stage.type)
            if not argument_type then
                return nil, Report.bug(Report.NoLowering('representation'), initializer.span)
            end
            -- §3.6's table, and §11.3's capability: a `Read` or `Mut` stage VIEWS its argument and
            -- an `Own` one takes it. That is the difference between a borrow and a move, and it is
            -- declared rather than inferred -- so the borrower writes `f x` and the owner writes
            -- `f (move x)`, and `Lower` must not demand the second from the first.
            --
            -- A borrow is not a belt VALUE and has no representation (§3.6: "a reference is never a
            -- value, its representation is unobservable"). So it lowers to the value itself, and what
            -- makes it a borrow is precisely that the source's place is NOT marked moved: the owner
            -- still owns it. Whether the host retains it is the host's contract, and §3.6 says the
            -- declaration, not the implementation, is what the compiler holds a host to.
            local capability = stage.capability
            local borrowed = capability == Semantic.Read or capability == Semantic.Mut
            local argument, diagnostic
            if borrowed and Judge.Reference:isclassof(initializer.argument) then
                argument, diagnostic = lower_borrow(L_, C, initializer.argument)
                -- §3.5: the callee's stage has the SUM's type, so the caller BUILDS the sum even when
                -- it borrows -- the tag is part of what the callee reads, and a borrow says only that
                -- the caller keeps ownership. Passing the value itself was the C type error, and the
                -- only reason it survived is that nothing had built a sum from a borrowed place.
                if argument then
                    argument, diagnostic = inject(L_, C, argument_type, stage.type, argument,
                        initializer.argument)
                    if not argument then return nil, diagnostic end
                end
            else
                argument, diagnostic = lower_initializer(L_, C, initializer.argument, argument_type,
                    stage.type)
            end
            if not argument then return nil, diagnostic end

            -- The roots of this application: whatever the value at `prefix` is, the step that
            -- reaches `prefix + 1`, and -- only when that step saturates the chain -- the terminal.
            --
            -- The base is the CALLEE when the callee is itself an application: `f a b` has prefix 1
            -- at the outer step, so its base is `f a` and not a fresh `construct`. Calling
            -- `construct` unconditionally hands `advance_1` a `R(t,0)` where it wants `R(t,1)` --
            -- which is a type error in the emitted C and, before that, a second construction of a
            -- chain that had already been built.
            local base
            if prefix == 0 then
                local constructed, diagnostic = base_of(L_, C, template, word, initializer.callee)
                if not constructed then return nil, diagnostic end
                base = constructed
            else
                base, diagnostic = lower_initializer(L_, C, initializer.callee,
                    residual_type(L_, word, prefix))
                if not base then return nil, diagnostic end
            end
            local advance = demand(L_, 'advance:' .. template .. ':' .. (prefix + 1), function(M, id)
                return build_advance(M, template, prefix + 1, id)
            end)
            if not advance then return nil, L_.diagnostic end

            local reached = ordered(C, B.CallFunction(advance, ref(C, C.state.effect),
                L{ref(C, base), ref(C, argument)}), residual_type(L_, word, prefix + 1))
            if prefix + 1 < #stages then return reached end

            local run = demand(L_, 'run:' .. template, function(M, id)
                return build_run(M, template, id)
            end)
            if not run then return nil, L_.diagnostic end
            return ordered(C, B.CallFunction(run, ref(C, C.state.effect), L{ref(C, reached)}),
                rep(L_, L_.types[template].result))
        end

        -- §1.2: `f(a, b)` and `f with a with b` lower to the SAME operations in the same order -- the
        -- only difference is the residual's lifetime, which the belt does not yet distinguish -- so the
        -- arguments are folded into `Apply`s and the existing path does the work. `f()` is the one
        -- case `with` cannot spell: it supplies no stage, so it runs the terminal directly
        -- and is legal only where the word has no stages left to supply.
        if Judge.Invoke:isclassof(initializer) then
            if #initializer.arguments == 0 then
                local template, prefix = word_of(L_, initializer.callee)
                if not template then
                    return nil, Report.reject(Report.NotExecutable, initializer.span)
                end
                local word = L_.declarations[template].word
                if prefix ~= 0 or #stages_of(word) ~= 0 then
                    return nil, Report.reject(Report.Undersaturated, initializer.span)
                end
                local base, diagnostic = base_of(L_, C, template, word, initializer.callee)
                if not base then return nil, diagnostic end
                local run = demand(L_, 'run:' .. template, function(M, id)
                    return build_run(M, template, id)
                end)
                if not run then return nil, L_.diagnostic end
                return ordered(C, B.CallFunction(run, ref(C, C.state.effect), L{ref(C, base)}),
                    rep(L_, L_.types[template].result))
            end
            local folded = initializer.callee
            for _, argument in ipairs(initializer.arguments) do
                folded = Judge.Apply(folded, argument, initializer.span)
            end
            return lower_initializer(L_, C, folded, type_, semantic)
        end

        local class = getmetatable(initializer)
        return nil, Report.bug(Report.NoLowering('initializer ' .. tostring(class and class.kind)),
            L_.definitions[1].span)
    end


    -- A `do` body: statements in order, and its exit is its `return`. §12.3: "Bare `return` and
    -- falling through the end of a runtime body both return Unit" -- so a body that never returns
    -- is an exit returning Unit, and whether that matches the declared result is Contract's check.
    local function copy(t)
        local out = {}
        for key, value in pairs(t) do out[key] = value end
        return out
    end

    -- A place's state is copied per arm: a move in one arm must not be visible in the other, or
    -- the agreement check at the join could not see the very difference it exists to reject.
    local function copy_places(places)
        local out = {}
        for id, state in pairs(places) do out[id] = { moved = copy(state.moved) } end
        return out
    end

    -- The live values of a region: what the sequential scan has bound and not yet left scope.
    --
    -- This is §3.3's transport list, and it is deliberately NOT a liveness analysis. The region's
    -- environment already IS the live set -- a binding enters it when it is bound and leaves it when
    -- its scope ends -- so the scan that checks ownership is the same scan that knows what is live.
    -- Order is by definition id, which is what makes an edge's arguments and its target's
    -- parameters agree without either side sorting anything.
    live = function(C)
        local ids = {}
        for id in pairs(C.state.values) do ids[#ids + 1] = id end
        table.sort(ids)
        return ids
    end

    -- The arguments of an edge into a block whose parameters are `[Effect] + carried`, in the SAME
    -- order those parameters were created. One owner, because an edge whose arguments and whose
    -- target's parameters disagree is a read of an uninitialized C variable -- a wrong program the
    -- belt's own numbering rule warns about and that no later phase can detect.
    arguments_of = function(region, carried)
        local arguments = L{ref(region, region.state.effect)}
        for _, id in ipairs(carried) do
            arguments:insert(ref(region, region.state.values[id]))
        end
        return arguments
    end

    -- One successor region of the control the parent is building: its own block, its own region,
    -- and the interface that carries the parent's live values in. Returns the region and the
    -- arguments its incoming edge must pass.
    --
    -- `target` is where the region's own fallthrough goes -- a join for a split, the header for a
    -- loop -- so `arm` is the one place that knows how control continues.
    --
    -- The interface is DEGENERATE, and that is the design's own claim rather than a shortcut.
    -- §3.3 makes ownership state path-independent, so no place ever crosses as a parameter; and
    -- with no assignment (C8), no VALUE differs across the arms either. Every edge therefore
    -- passes on exactly what it received: this is an identity, not a phi, and the phi arrives with
    -- assignment. What remains is transport -- a value built before the split lives in the
    -- parent's block, and a block names only its own positions, so it must be named here.
    local function arm(L_, C, block, statements, result_type, span, target, carried, binds)
        local child = C:region()
        child.state.block = block
        child.state.locations = {}
        child.state.places = copy_places(C.state.places)
        -- Shared, not copied: a `break` inside a nested `if` inside this body belongs to THIS loop.
        child.state.loop = C.state.loop
        child.state.effect = parameter(child, B.Effect, Semantic.Read)
        child.state.values = {}
        for _, id in ipairs(carried) do
            child.state.values[id] = parameter(child, C.state.values[id].type, Semantic.Read)
        end

        -- §S59: an arm that matched by SHAPE binds what it matched. Field `1+K` of a sum is
        -- alternative `K`'s payload -- a KNOWN offset, so this is a plain `LoadField`: pure, of
        -- known type, and unable to fail, because the arm's own test established that tag is K.
        if binds then
            local payload = pure(child, B.LoadField(
                ref(child, child.state.values[binds.subject]), 1 + binds.tag), binds.type)
            -- §3.5/§S65: taking a NON-COPY payload consumes the WHOLE subject, because a sum has no
            -- partial state to be in -- its tag would otherwise name a value that is no longer
            -- there. The path that is marked is the ROOT (`''`), so every alternative reads as gone
            -- and the subject is never destroyed half-taken.
            --
            --     A COPY payload is a copy (§1.4) and consumes nothing, so the arms of a sum that
            --     mixes the two disagree about the subject's state. That is §3.3's
            --     `OwnershipDiverges` doing its job, and it is a consequence of §3.5 rather than
            --     a limitation added here.
            if not binds.copyable then
                ordered(child, B.Move(ref(child, child.state.effect), ref(child, payload)), nil)
                place(child, binds.subject).moved[''] = true
            end
            child.state.values[binds.id] = payload
        end

        local arguments = arguments_of(C, carried)
        local ok, diagnostic = lower_body(L_, child, statements, result_type, span, function(region)
            -- The region's OWN `let`s die with it, so only the carried values cross -- and they
            -- cross as the very parameters they arrived as. That is the identity phi.
            return B.Jump(B.Edge(target.id, arguments_of(region, carried)))
        end)
        if not ok then return nil, diagnostic end
        return child, arguments
    end

    -- Set equality for a place's holes. Ownership state is a SET of moved paths, and every place
    -- §3.3 talks about is compared this way: at a split, at a backedge, and at a `break`.
    local function same_holes(left, right)
        for key in pairs(left) do
            if right[key] == nil then return false end
        end
        for key in pairs(right) do
            if left[key] == nil then return false end
        end
        return true
    end

    local function holes(C, id)
        local place = C.state.places[id]
        return place and place.moved or {}
    end

    -- §3.3: at a join, every place that OUTLIVES it must agree on every incoming path.
    -- Divergence is a **Reject** -- not a guard, not a dynamic flag, not a fixpoint. That single
    -- rule is why ownership is a scan and not a pass, and it is the claim this design rests on.
    -- `C` is the region whose places are the ones that outlive the join.
    -- §3.3's rule is about "every place that OUTLIVES" the join, and a path that does not arrive at it
    -- imposes nothing -- an arm ending in `return` is the obvious case. What is NOT obvious, and what
    -- makes the conservative version the right one, is that **a path's state outlives the join whenever
    -- the PLACE outlives the path**: §S66's own test moves a FILE-level place inside a returning arm,
    -- and a place whose scope is the module outlives the arm, the switch and the function. So `agree`
    -- compares every path, and getting cleverer here needs scope information it does not have.
    local function agree(C, yes, no, span)
        -- With fewer than two arriving paths there is nothing to agree about: one path's state IS the
        -- join's state, and none leaves the parent's -- because nothing after the join observes it.
        local agreed = {}
        -- §S66: the ids are the UNION of what the three paths know about, not the parent's set.
        -- A place's entry is created when something first marks it, and the first marking usually
        -- happens INSIDE an arm -- so iterating the parent's table silently skipped exactly the
        -- place the two arms disagreed about, which made this check blind to the divergence it
        -- exists for. An id one path has and another does not is compared too, through `holes`:
        -- absent means `{}`, which is "not moved" and not "unknown".
        local ids = {}
        for id in pairs(yes.state.places) do ids[id] = true end
        for id in pairs(no.state.places) do ids[id] = true end
        for id in pairs(C.state.places) do ids[id] = true end
        for id in pairs(ids) do
            local left = holes(yes, id)
            if not same_holes(left, holes(no, id)) then
                return nil, Report.reject(Report.OwnershipDiverges, span)
            end
            agreed[id] = { moved = copy(left) }
        end
        return agreed
    end

    -- A split, and its join. The join block exists before either arm, because an `Edge` names its
    -- target by block id -- and its parameters are created after both arms, because what the arms
    -- must agree about is exactly what the join is allowed to keep.
    -- A DISPATCH over `count` alternatives on a value that is known only at run time: one test per
    -- alternative, in order, then a trap for a value that names none. §3.5's destructor chooses its arm
    -- by TAG and §12.1's runtime index chooses by OFFSET, and both are this shape -- a value compared
    -- against a constant -- so this is the one place that builds it.
    --
    -- All of the caller's values must already be NAMED, because §12.3 makes a block's parameters the
    -- values live at the split and an edge's arguments match them one for one. A caller that needs a
    -- value to come OUT of the dispatch uses a CELL, which is how this design carries a value across a
    -- join that differs per path (§11.7: its identity is fixed, only its contents differ, "and contents
    -- are memory, not an SSA name"); `build_arm(k)` emits into the arm for the k-th alternative.
    local function dispatch(L_, C, count, subject, reason, build_arm)
        local carried = live(C)
        local types = {}
        for _, id in ipairs(carried) do types[id] = C.state.values[id].type end
        local join, trap = new_block(C), new_block(C)
        local tests, arms = {}, {}
        for k = 1, count do
            tests[k] = new_block(C)
            arms[k] = new_block(C)
        end
        C.state.block.exit = B.Jump(B.Edge(tests[1].id, arguments_of(C, carried)))

        local function adopt(block)
            C.state.block = block
            C.state.effect = parameter(C, B.Effect, Semantic.Read)
            C.state.values = {}
            for _, id in ipairs(carried) do
                C.state.values[id] = parameter(C, types[id], Semantic.Read)
            end
        end

        for k = 1, count do
            adopt(tests[k])
            local literal = pure(C, B.IntegerLiteral(tostring(k - 1)), B.Int)
            local equal = pure(C, B.Binary(Semantic.Equal, ref(C, C.state.values[subject]),
                ref(C, literal)), B.Bool)
            local next_block = tests[k + 1] and tests[k + 1].id or trap.id
            tests[k].exit = B.Branch(ref(C, equal),
                B.Edge(arms[k].id, arguments_of(C, carried)),
                B.Edge(next_block, arguments_of(C, carried)))
        end

        for k = 1, count do
            adopt(arms[k])
            build_arm(k)
            arms[k].exit = B.Jump(B.Edge(join.id, arguments_of(C, carried)))
        end

        adopt(trap)
        trap.exit = B.Trap(ref(C, C.state.effect), reason)
        adopt(join)
        return true
    end

    -- §12.1's row, DERIVED: "is this step a constant or a runtime index?" An index whose value is not
    -- known until run time is a DISPATCH on it -- one test per member, in the order the members are
    -- written -- and each arm reads the CONSTANT offset it is about. That is the shape of §3.5's
    -- destructor (a dispatch on a tag) and it needs no new opcode.
    --
    -- **The value crosses the join in a CELL, because this design has no value phi.** §S35 says the value
    -- phi appears in exactly one place, `and`/`or`, and §11.7 says why the cell is the alternative: "a
    -- cell is a belt value whose identity is fixed before any control flow can reach it, so it crosses a
    -- join unchanged and only its contents differ per path -- and contents are memory, not an SSA name."
    -- Arm 0 stores nothing, because the cell is initialised with member 0, and an index that names no
    -- member TRAPS: a runtime index cannot be checked statically, and §1.5 already traps where C would be
    -- undefined (`/` by zero), so this is the same rule and not a new one.
    lower_element = function(L_, C, initializer)
        local record, diagnostic = lower_initializer(L_, C, initializer.base)
        if not record then return nil, diagnostic end
        local index, index_diagnostic = lower_initializer(L_, C, initializer.index, B.Int)
        if not index then return nil, index_diagnostic end
        local aggregate = record.type
        if not B.Aggregate:isclassof(aggregate) or #aggregate.fields == 0 then
            return nil, Report.bug(Report.NoLowering('element'), initializer.span)
        end
        local element_type = aggregate.fields[1].type
        local record_id = name_it(L_, C, record, aggregate)
        local index_id = name_it(L_, C, index, B.Int)
        local first = pure(C, B.LoadField(ref(C, C.state.values[record_id]), 0), element_type)
        local cell = ordered(C, B.Allocate(ref(C, C.state.effect), ref(C, first)),
            B.Cell(element_type))
        local cell_id = name_it(L_, C, cell, B.Cell(element_type))

        -- The index that names no member TRAPS, and that is what lets a cell stand in for the phi this
        -- design does not have: the trap EXITS, so every path that arrives at the join has the cell set.
        dispatch(L_, C, #aggregate.fields, index_id, 'index out of range', function(k)
            if k > 1 then
                local member = pure(C, B.LoadField(ref(C, C.state.values[record_id]), k - 1),
                    element_type)
                ordered(C, B.Store(ref(C, C.state.effect), ref(C, C.state.values[cell_id]),
                    ref(C, member)), nil)
            end
        end)
        return ordered(C, B.Load(ref(C, C.state.effect), ref(C, C.state.values[cell_id])), element_type)
    end

    -- §12.1's runtime index as a DESTINATION: the same dispatch, with a `StoreField` in each arm instead
    -- of a `LoadField`. It cannot be a PLACE -- a place is one address and the index decides WHICH
    -- address at run time -- so it is the one destination `lower_place` does not answer, and the address
    -- it writes through is the base record's, which §S68 says chains like any other.
    local function lower_element_store(L_, C, statement)
        local initializer = statement.place
        local target, diagnostic = lower_place(L_, C, initializer.base)
        if not target then return nil, diagnostic end
        local address = target.cell and target.value or target.address
        if not address then
            return nil, Report.bug(Report.UnaddressableDestination, statement.span)
        end
        local aggregate = target.type
        if not Semantic.Aggregate:isclassof(aggregate) or #aggregate.fields == 0 then
            return nil, Report.bug(Report.NoLowering('element store'), statement.span)
        end
        local element_type = rep(L_, aggregate.fields[1].type)
        local index, index_diagnostic = lower_initializer(L_, C, initializer.index, B.Int)
        if not index then return nil, index_diagnostic end
        local value, value_diagnostic = lower_initializer(L_, C, statement.value, element_type)
        if not value then return nil, value_diagnostic end

        local address_id = name_it(L_, C, address, address.type)
        local index_id = name_it(L_, C, index, B.Int)
        local value_id = name_it(L_, C, value, element_type)
        dispatch(L_, C, #aggregate.fields, index_id, 'index out of range', function(k)
            ordered(C, B.StoreField(ref(C, C.state.values[address_id]), k - 1,
                ref(C, C.state.values[value_id])), nil)
        end)
        return true
    end

    -- §3.5: "destroying a sum needs a destructor chosen by its TAG". Every destructor before this one was
    -- straight-line; this one cannot be, because which alternative is live is not a fact about the sum's
    -- TYPE -- the tag says so, and the tag is a runtime value. So it is a chain of tests whose arms are
    -- blocks, and this is where §3.3's scope-exit destruction and §12.3's block graph meet.
    --
    -- Nothing else here is new. §3.5 puts the tag at field 0 and alternative K's payload at field 1+K --
    -- the numbers `InjectSum` writes and `lower_switch` compares -- so every read is a pure `LoadField`
    -- at a known offset, and the ops are the ones the graph already has.
    destroy_sum = function(L_, C, root, path, type_, value)
        local alternatives = {}
        for index, alternative in ipairs(type_.alternatives) do
            if destroys(L_, alternative) then alternatives[#alternatives + 1] = index end
        end
        if #alternatives == 0 then return end

        -- The value must be visible in every arm, and a `Ref` is relative to its CONSUMER, so it crosses
        -- the edges as an argument -- which needs a name (§12.3, and the same reason as §S34).
        local subject = name_it(L_, C, value, type_)
        local carried = live(C)
        local types = {}
        for _, id in ipairs(carried) do types[id] = C.state.values[id].type end

        local join = new_block(C)
        local tests, arms = {}, {}
        for position in ipairs(alternatives) do tests[position] = new_block(C) end
        for _, index in ipairs(alternatives) do arms[index] = new_block(C) end
        C.state.block.exit = B.Jump(B.Edge(tests[1].id, arguments_of(C, carried)))

        -- Adopt a block the chain entered: its parameters are `[Effect] + the live values`, in the order
        -- `arguments_of` wrote them -- the adoption `lower_if` performs at its join.
        local function adopt(block)
            C.state.block = block
            C.state.effect = parameter(C, B.Effect, Semantic.Read)
            C.state.values = {}
            for _, id in ipairs(carried) do
                C.state.values[id] = parameter(C, types[id], Semantic.Read)
            end
        end

        for position, index in ipairs(alternatives) do
            adopt(tests[position])
            local tag = pure(C, B.LoadField(ref(C, C.state.values[subject]), 0), B.Int)
            -- The tag is ZERO-based: `InjectSum` writes `index - 1` and `lower_switch` compares the same.
            local literal = pure(C, B.IntegerLiteral(tostring(index - 1)), B.Int)
            local equal = pure(C, B.Binary(Semantic.Equal, ref(C, tag), ref(C, literal)), B.Bool)
            -- The LAST test has nothing after it: the tag must name one of the alternatives, so its `no`
            -- edge goes straight to the join.
            local next_block = tests[position + 1] and tests[position + 1].id or join.id
            tests[position].exit = B.Branch(ref(C, equal),
                B.Edge(arms[index].id, arguments_of(C, carried)),
                B.Edge(next_block, arguments_of(C, carried)))
        end

        for _, index in ipairs(alternatives) do
            adopt(arms[index])
            local payload = pure(C, B.LoadField(ref(C, C.state.values[subject]), 1 + (index - 1)),
                rep(L_, type_.alternatives[index]))
            local inner = path == '' and tostring(index) or (path .. '.' .. index)
            destroy_value(L_, C, root, inner, type_.alternatives[index], payload)
            arms[index].exit = B.Jump(B.Edge(join.id, arguments_of(C, carried)))
        end

        -- Adopt the join, so whatever the caller destroys next lands after the dispatch on every path.
        -- The place state is NOT reset and nothing is agreed, because a destruction changes no place's
        -- state -- which is why this needs no `agree` where `lower_if` does.
        adopt(join)
    end

    lower_if = function(L_, C, statement, result_type)
        -- The statement carries its own span, so Lower is not told where the statement is.
        local span = statement.span
        local condition, diagnostic = lower_initializer(L_, C, statement.condition, B.Bool)
        if not condition then return nil, diagnostic end

        local carried = live(C)
        local types = {}
        for _, id in ipairs(carried) do types[id] = C.state.values[id].type end

        local join = new_block(C)
        -- The caller keeps the block it allocated. A region's `state.block` moves on as it builds
        -- nested control, so reading it back would wire the branch to wherever the arm ENDED --
        -- which is a wrong program that compiles and only shows up with nesting.
        local yes_block, no_block = new_block(C), new_block(C)
        local yes, yes_arguments = arm(L_, C, yes_block, statement.yes, result_type, span, join, carried)
        if not yes then return nil, yes_arguments end
        local no, no_arguments = arm(L_, C, no_block, statement.no, result_type, span, join, carried)
        if not no then return nil, no_arguments end
        if not no then return nil, no_arguments end

        local agreed, diverged = agree(C, yes, no, span)
        if not agreed then return nil, diverged end

        C.state.block.exit = B.Branch(ref(C, condition),
            B.Edge(yes_block.id, yes_arguments), B.Edge(no_block.id, no_arguments))

        -- Adopt the join. The arms' own bindings are gone, the ownership state is the agreed one,
        -- and each carried value is now the join's parameter -- the same value on every path,
        -- which is what "no phi yet" means precisely.
        C.state.block = join
        C.state.locations = {}
        C.state.places = agreed
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        C.state.values = {}
        for _, id in ipairs(carried) do
            C.state.values[id] = parameter(C, types[id], Semantic.Read)
        end
        return true
    end

    -- §3.3's uniformity with a loop: the backedge must agree with the header, and so must every
    -- `break` and every `continue` inside the body. This is a LOCAL check and NOT a fixed point --
    -- the header's state is the state on entry, which is already known -- and that is precisely
    -- why a loop needs no initialization analysis.
    --
    -- A `while` never terminates on its own, because the condition may be false first, so the
    -- exit block is always reachable: the loop joins the enclosing code rather than ending it.
    lower_while = function(L_, C, statement, result_type)
        local span = statement.span
        local carried = live(C)
        local types = {}
        for _, id in ipairs(carried) do types[id] = C.state.values[id].type end

        -- The header, entered from here and again from the backedge.
        local header = new_block(C)
        local exit = new_block(C)
        local enclosing = C.state.loop
        C.state.block.exit = B.Jump(B.Edge(header.id, arguments_of(C, carried)))

        local head = C:region()
        head.state.block = header
        head.state.locations = {}
        head.state.places = copy_places(C.state.places)
        head.state.effect = parameter(head, B.Effect, Semantic.Read)
        head.state.values = {}
        for _, id in ipairs(carried) do
            head.state.values[id] = parameter(head, types[id], Semantic.Read)
        end

        local condition, diagnostic = lower_initializer(L_, head, statement.condition, B.Bool)
        if not condition then return nil, diagnostic end

        -- The loop's own control state. `break` and `continue` are jumps into it, and each site
        -- records the ownership state it leaves in, so the agreement below covers all of them.
        head.state.loop = { header = header, exit = exit, carried = carried, sites = {} }

        local body_block = new_block(C)
        local body, body_diagnostic = arm(L_, head, body_block, statement.body, result_type,
            span, header, carried)
        if not body then return nil, body_diagnostic end

        local agreed, diverged = agree(head, body, head, span)
        if not agreed then return nil, diverged end
        for _, site in ipairs(head.state.loop.sites) do
            for _, id in ipairs(carried) do
                if not same_holes(holes(head, id), site.moved[id] or {}) then
                    return nil, Report.reject(Report.OwnershipDiverges, span)
                end
            end
        end

        head.state.block.exit = B.Branch(ref(head, condition),
            B.Edge(body_block.id, arguments_of(head, carried)),
            B.Edge(exit.id, arguments_of(head, carried)))

        -- Adopt the exit: the loop is over, and the ownership state is the one every edge into it
        -- agreed on.
        C.state.block = exit
        C.state.locations = {}
        C.state.places = agreed
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        C.state.values = {}
        for _, id in ipairs(carried) do
            C.state.values[id] = parameter(C, types[id], Semantic.Read)
        end
        C.state.loop = enclosing
        return true
    end

    -- §3.4: assignment. The destination is established first and NOT replaced -- the place is
    -- computed, not written -- then the right-hand side is evaluated, and only then does the write
    -- happen. Because a `mut` binding is a cell, the write is a `Store` into storage, so the
    -- destination's identity is untouched and no phi is needed at a join.
    -- §12.3: `switch` evaluates its subject EXACTLY ONCE, so the subject crosses every edge. It has
    -- no source definition, and `live` is keyed by definition id, so it gets a SYNTHETIC one -- the
    -- only binding Lower invents, and it exists because an edge argument has to be nameable.
    --
    -- One TEST block per LABEL, chained: each compares the subject and branches to its arm or on to
    -- the next test. So `case 1, 2` is two tests into one arm, which is what a label LIST means --
    -- and it needs no `or`, which short-circuits and would need the value phi this design avoided.
    -- There is no fallthrough, so an arm's body simply ends; and a `switch` is not a loop, so a
    -- `break` inside an arm belongs to the enclosing `while` and is not this form's business.
    lower_switch = function(L_, C, statement, result_type)
        local span = statement.span
        -- §S61: no type is handed in, because the subject's type is whatever lowering it produces
        -- -- and there is nothing here that needs to know it in advance.
        local subject, diagnostic = lower_initializer(L_, C, statement.subject)
        if not subject then return nil, diagnostic end

        -- A `switch` with nothing to match is a no-op: the subject is evaluated (its effects are
        -- the source's) and control continues. Nothing is emitted, so no block is created either.
        if #statement.cases == 0 and #statement.otherwise == 0 then return true end

        L_.synthetic = (L_.synthetic or 0) - 1
        local subject_id = L_.synthetic
        C.state.values[subject_id] = subject

        local carried = live(C)
        local types = {}
        for _, id in ipairs(carried) do types[id] = C.state.values[id].type end

        -- §S60: a shape label CARRIES its type, so this reads the label itself and never a
        -- declaration -- which is the read §S52 warns about: a type word's definition is created
        -- while resolving the very switch it labels, so its interface may not exist yet.
        local function binding_of(case)
            local denotes = case.labels[1].denotes
            -- §S60: the label SAYS WHICH alternative it is -- `Contract` filled that in, because it
            -- is the phase with the SUBJECT's type -- so the tag is READ here and not re-derived.
            local tag = case.labels[1].alternative
            if tag == nil then return nil end
            if not tag then return nil end
            -- §S65: §1.4 decides whether the binder copies or takes, so it is derived from the
            -- payload's type and not from a spelling at the call site.
            return { id = case.binds, subject = subject_id, tag = tag, type = rep(L_, denotes),
                     copyable = copyable(L_, denotes) }
        end
        local join = new_block(C)
        local arm_blocks = {}
        for index in ipairs(statement.cases) do arm_blocks[index] = new_block(C) end
        local fallback = #statement.otherwise > 0 and new_block(C) or join

        local tests = {}
        for index, case in ipairs(statement.cases) do
            for _, label in ipairs(case.labels) do
                tests[#tests + 1] = { block = new_block(C), label = label, arm = arm_blocks[index] }
            end
        end

        -- The entry leaves for the first test, or straight past the switch when there are no arms.
        C.state.block.exit = B.Jump(B.Edge((tests[1] and tests[1].block or fallback).id,
            arguments_of(C, carried)))

        -- The arms, and the `else` if there is one, all continue at the join.
        local regions = {}
        for index, case in ipairs(statement.cases) do
            local binds
            if case.binds then
                binds = binding_of(case)
                -- `Contract` established that the label IS an alternative of the subject, so a
                -- refusal here is the compiler disagreeing with itself.
                if not binds then
                    return nil, Report.bug(Report.NoLowering('case binder'), span)
                end
            end
            local region, arguments = arm(L_, C, arm_blocks[index], case.body, result_type, span,
                join, carried, binds)
            if not region then return nil, arguments end
            regions[#regions + 1] = region
        end
        if #statement.otherwise > 0 then
            local region, arguments = arm(L_, C, fallback, statement.otherwise, result_type, span,
                join, carried)
            if not region then return nil, arguments end
            regions[#regions + 1] = region
        end

        -- The tests. Each carries the same parameters as an arm, so the edge that reaches it names
        -- the effect first and then the carried values, in the order they were created.
        for index, test in ipairs(tests) do
            local next_block = tests[index + 1] and tests[index + 1].block or fallback
            local region = C:region()
            region.state.block = test.block
            region.state.locations = {}
            region.state.places = copy_places(C.state.places)
            region.state.loop = C.state.loop
            region.state.effect = parameter(region, B.Effect, Semantic.Read)
            region.state.values = {}
            for _, id in ipairs(carried) do
                region.state.values[id] = parameter(region, types[id], Semantic.Read)
            end
            local other = region.state.values[subject_id]

            -- §3.5: a SUM subject is discriminated by its TAG, which is field 0 of `{tag, payload}`.
            -- The tag is never exposed as a field -- nothing in the language names it -- so this is
            -- the one place that knows where it lives, and `Contract` has already established that a
            -- SHAPE label is an alternative of this subject.
            local equal
            if Judge.Shape:isclassof(test.label) then
                -- §S60: WHICH alternative this label is, read off the label -- see `binding_of`.
                -- The subject must still be a sum, because a tag is field 0 of `{tag, payload}`.
                if not B.Sum:isclassof(types[subject_id]) then
                    return nil, Report.bug(Report.NoLowering('case subject'), statement.span)
                end
                local tag = test.label.alternative
                if tag == nil then
                    return nil, Report.bug(Report.NoLowering('case alternative'), statement.span)
                end
                local at = pure(region, B.LoadField(ref(region, other), 0), B.Int)
                local index = pure(region, B.IntegerLiteral(tostring(tag)), B.Int)
                equal = pure(region, B.Binary(Semantic.Equal, ref(region, at), ref(region, index)),
                    B.Bool)
            else
                local label, label_diagnostic = lower_initializer(L_, region, test.label.value,
                    types[subject_id])
                if not label then return nil, label_diagnostic end
                equal = pure(region, B.Binary(Semantic.Equal, ref(region, other),
                    ref(region, label)), B.Bool)
            end
            region.state.block.exit = B.Branch(ref(region, equal),
                B.Edge(test.arm.id, arguments_of(region, carried)),
                B.Edge(next_block.id, arguments_of(region, carried)))
            regions[#regions + 1] = region
        end

        -- §S66: does the switch cover every value its subject can hold? Then its fall-through is not
        -- a path, and comparing it invents one. Two subject kinds can be exhaustive in the belt: a
        -- sum whose every alternative is labelled, and a Bool whose both values are. The same fact
        -- §12.3 states as "a switch terminates only when every value is caught" -- derived here from
        -- the belt types, because the labels' alternatives are belt types and this is where the
        -- agreement is decided.
        local function covers_everything()
            if #statement.otherwise > 0 or #statement.cases == 0 then return false end
            local subject_type = types[subject_id]
            if B.Sum:isclassof(subject_type) then
                for _, alternative in ipairs(subject_type.alternatives) do
                    local matched = false
                    for _, test in ipairs(tests) do
                        if Judge.Shape:isclassof(test.label)
                            and alternative:equals(rep(L_, test.label.denotes)) then
                            matched = true
                        end
                    end
                    if not matched then return false end
                end
                return true
            end
            if subject_type == B.Bool then
                local seen = {}
                for _, test in ipairs(tests) do
                    local constant = Judge.Constant:isclassof(test.label) and test.label.value
                    if constant and Judge.Literal:isclassof(constant)
                        and Syntax.Boolean:isclassof(constant.value) then
                        seen[constant.value] = true
                    end
                end
                return seen[true] == true and seen[false] == true
            end
            return false
        end
        local exhaustive = covers_everything()

        -- §3.3 at the merge: the paths that can REACH the join must agree about the places that
        -- outlive the switch. The arms and the `else` are those paths. A test block's state is the
        -- parent's and its fall-through carries it into the join, so a test is a path too -- which is
        -- why it is compared unless the switch covers everything, when that edge cannot be taken.
        local agreed, diverged
        for index = 1, exhaustive and #statement.cases or #regions do
            local one
            one, diverged = agree(C, regions[1], regions[index], span)
            if not one then return nil, diverged end
            agreed = one
        end

        C.state.block = join
        C.state.locations = {}
        C.state.places = agreed
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        C.state.values = {}
        for _, id in ipairs(carried) do
            C.state.values[id] = parameter(C, types[id], Semantic.Read)
        end
        return true
    end

    -- §3.4's short-circuiting operators, and the ONE place a value genuinely differs per path.
    -- `a and b` is `b` when `a` is true and `a` when it is false, and only one of them runs -- so
    -- this is where the VALUE PHI appears: a parameter of the join that the two arms fill with
    -- different producers. Nothing else in the design needed one. §S32 made the thing that differs
    -- MEMORY (a cell, whose identity is fixed), and §S28 made it AGREE across paths (the identity
    -- interface, because no assignment existed to disagree about). Neither is available here: not
    -- running the right operand is the operator's whole meaning, so the difference is irreducible.
    --
    -- The short arm needs the LEFT value as a parameter, because that value lives in the parent's
    -- block and a block names only its own positions. The long arm needs nothing extra: its merge
    -- value is the right operand, which it evaluates itself.
    lower_short_circuit = function(L_, C, initializer, type_)
        local span = initializer.span
        local is_and = initializer.operator == Semantic.And
        local left, diagnostic = lower_initializer(L_, C, initializer.left, rep(L_, Semantic.Bool))
        if not left then return nil, diagnostic end

        local carried = live(C)
        local types = {}
        for _, id in ipairs(carried) do types[id] = C.state.values[id].type end

        local join = new_block(C)
        local short_block, long_block = new_block(C), new_block(C)

        -- `and` evaluates the right operand only when the left is TRUE; `or` only when it is FALSE.
        -- So the operators differ in which edge is the short one and what the short arm merges --
        -- nothing else, which is why this is one function and not two.
        local yes_block = is_and and long_block or short_block
        local no_block = is_and and short_block or long_block
        -- The SHORT arm merges the left value itself -- `and` yields false, `or` yields true -- so its
        -- edge carries one more argument than the long one, and the list has to exist BEFORE the branch
        -- or the short arm reads an uninitialised parameter. That was a MISCOMPILE: `and` passed by
        -- luck (its short value is false, which is what a fresh parameter held), and `or` returned
        -- false where it owed true.
        local short_arguments = arguments_of(C, carried)
        short_arguments:insert(ref(C, left))
        C.state.block.exit = B.Branch(ref(C, left),
            B.Edge(yes_block.id, is_and and arguments_of(C, carried) or short_arguments),
            B.Edge(no_block.id, is_and and short_arguments or arguments_of(C, carried)))

        -- The short arm: no statements at all, one extra parameter for the value it merges.
        local short = C:region()
        short.state.block = short_block
        short.state.locations = {}
        short.state.places = copy_places(C.state.places)
        short.state.loop = C.state.loop
        short.state.effect = parameter(short, B.Effect, Semantic.Read)
        short.state.values = {}
        for _, id in ipairs(carried) do
            short.state.values[id] = parameter(short, types[id], Semantic.Read)
        end
        local merged = parameter(short, B.Bool, Semantic.Read)
        local short_out = L{ref(short, short.state.effect)}
        for _, id in ipairs(carried) do short_out:insert(ref(short, short.state.values[id])) end
        short_out:insert(ref(short, merged))
        short.state.block.exit = B.Jump(B.Edge(join.id, short_out))

        -- The long arm: the right operand, evaluated here and passed on as the merge value.
        local long = C:region()
        long.state.block = long_block
        long.state.locations = {}
        long.state.places = copy_places(C.state.places)
        long.state.loop = C.state.loop
        long.state.effect = parameter(long, B.Effect, Semantic.Read)
        long.state.values = {}
        for _, id in ipairs(carried) do
            long.state.values[id] = parameter(long, types[id], Semantic.Read)
        end
        local right, right_diagnostic = lower_initializer(L_, long, initializer.right, rep(L_, Semantic.Bool))
        if not right then return nil, right_diagnostic end
        local long_out = arguments_of(long, carried)
        long_out:insert(ref(long, right))
        long.state.block.exit = B.Jump(B.Edge(join.id, long_out))

        local agreed, diverged = agree(C, short, long, span)
        if not agreed then return nil, diverged end

        -- Adopt the join. Its parameters are `[Effect] + carried + the merged value`, so the value
        -- the expression denotes is the join's LAST parameter -- the other side of the phi the two
        -- arms just filled in.
        C.state.block = join
        C.state.locations = {}
        C.state.places = agreed
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        C.state.values = {}
        for _, id in ipairs(carried) do
            C.state.values[id] = parameter(C, types[id], Semantic.Read)
        end
        return parameter(C, B.Bool, Semantic.Read)
    end

    lower_assign = function(L_, C, statement)
        -- The one destination that is not a place (§12.1's runtime index), answered BEFORE `lower_place`
        -- because there is no single address to build.
        if Judge.Element:isclassof(statement.place) then
            return lower_element_store(L_, C, statement)
        end
        local target, diagnostic = lower_place(L_, C, statement.place)
        if not target then return nil, diagnostic end
        diagnostic = check_place(C, target.root, target.path, statement.span, false)
        if diagnostic then return nil, diagnostic end
        -- §3.4's destination is the *binding*. A projected one is a `StoreField` through the address
        -- the place carries, and §S68 gives every projection inside addressable storage one, at any
        -- depth, because the address chains. This guard is where TWO DERIVATIONS of one fact have to
        -- agree, which is why it stays: `Contract` answers "is this place writable" by walking the
        -- PATH (`writes_through_a_member`), and `is_cell` answers "is this storage addressable" by
        -- asking the TYPE (`interior_mutability`). Writable must imply addressable, and the only way
        -- it cannot is the compiler disagreeing with itself -- an interface not yet built when
        -- `is_cell` asks for it. So it is a `Bug` and not a `Missing`: a `Missing` says the language
        -- needs a mechanism, and §S71 built this one.
        local projected = target.path ~= ''
        if projected and not target.address then
            return nil, Report.bug(Report.UnaddressableDestination, statement.span)
        end

        local value
        if Judge.Move:isclassof(statement.value) then
            -- §3.4: "the right-hand side either definitely moved the destination ... or
            -- definitely did not". Taking the source marks it moved, which is what makes the
            -- replaced-value question static -- there is nothing left to destroy.
            local source, taken = lower_place(L_, C, statement.value.place)
            if not source then return nil, taken end
            value, diagnostic = read_place(L_, C, source, statement.value.span)
            if not value then return nil, diagnostic end
            if not source.cell then
                local moved = take_place(L_, C, source, statement.value.span)
                if not moved then return nil, moved end
            end
        else
            value, diagnostic = lower_initializer(L_, C, statement.value, rep(L_, target.type))
            if not value then return nil, diagnostic end
        end

        -- §3.1 rule 2: destruction happens "at scope exit, on return, and on REPLACEMENT" -- and
        -- replacement is this statement. So the old value goes before the new one is stored, and only
        -- in the branch where the right-hand side did NOT move the destination (§3.4 and §S17: "the
        -- RHS either definitely moved the destination ... or definitely did not", which is what makes
        -- the question static and the destruction unconditional). `place_value` is what the old value
        -- IS -- the cell's content for a root, the member read through its address for a projection --
        -- so this asks the one owner of that question instead of loading a record by hand.
        -- ... and "is there an old value at all?" is the place's own state: a destination that was
        -- MOVED OUT has nothing left to destroy, which is §3.4's sentence again from the other side --
        -- `move h` then `h = made(n)` must not release the handle the move already handed over.
        if not Judge.Move:isclassof(statement.value) and destroys(L_, target.type)
                and not place(C, target.root).moved[target.path] then
            destroy_value(L_, C, target.root, target.path, target.type, place_value(C, target))
        end

        if target.path == '' then
            ordered(C, B.Store(ref(C, C.state.effect), ref(C, target.value), ref(C, value)), nil)
        else
            -- The store goes through the CELL, not through the loaded record: a field of a
            -- record that is not address-taken cannot be written at all, which is why `is_cell`
            -- asks whether any place inside the binding is.
            ordered(C, B.StoreField(ref(C, target.address), target.offset, ref(C, value)), nil)
        end
        -- §3.4: assignment REPLACES, so the destination is initialized afterwards however it was
        -- before -- which is the same fact §3.1 rule 2's "on replacement" is the other half of. Without
        -- this a `move` followed by an assignment left the place marked moved forever, and the next
        -- read of it was refused as uninitialized.
        place(C, target.root).moved[target.path] = nil
        return true
    end

    lower_body = function(L_, C, statements, result_type, span, fallthrough)
        for _, statement in ipairs(statements) do
            if C.state.block.exit then
                return nil, Report.bug(Report.NoLowering('statement after an exit'), span)
            end
            if Judge.Local:isclassof(statement) then
                -- §2.4: a local that names a TYPE has no slot to initialize -- the name is STATIC (the
                -- type position reads the declaration) and there is no runtime value to bind.
                if not erased(L_, statement.definition) then
                    local value, diagnostic = materialize(L_, C, statement.definition, span)
                    if not value then return nil, diagnostic end
                    C.state.values[statement.definition] = value
                end
            elseif Judge.Return:isclassof(statement) then
                local value
                if statement.value then
                    local diagnostic
                    value, diagnostic = lower_initializer(L_, C, statement.value, result_type,
                        L_.word_result)
                    if not value then return nil, diagnostic end
                else
                    value = pure(C, B.UnitLiteral, B.Unit)
                end
                -- A value that crosses a split must be nameable (§12.3), and the destruction below is a
                -- dispatch when a sum is live here -- so the return value is bound BEFORE it and read from
                -- the binding afterwards. Only when there IS a dispatch: naming one that stays put would
                -- put a C variable in every function that returns.
                local named
                for _, id in ipairs(destroyable(L_, C)) do
                    if dispatches(L_, L_.types[id].result) then
                        named = name_it(L_, C, value, result_type)
                        break
                    end
                end
                destroy_all(L_, C)
                C.state.block.exit = B.Return(L{ref(C, named and C.state.values[named] or value),
                    ref(C, C.state.effect)})
            elseif Judge.Discard:isclassof(statement) then
                -- Contract proved it Copy, so nothing is destroyed and nothing is emitted; the
                -- value is built because building it is what its effects are.
                local diagnostic
                if Judge.Reference:isclassof(statement.value) or Judge.Project:isclassof(statement.value)
                    or Judge.Index:isclassof(statement.value) then
                    local p
                    p, diagnostic = lower_place(L_, C, statement.value)
                    if not p then return nil, diagnostic end
                    local read
                    read, diagnostic = read_place(L_, C, p, statement.span)
                    if not read then return nil, diagnostic end
                else
                    local value
                    value, diagnostic = lower_initializer(L_, C, statement.value)
                    if not value then return nil, diagnostic end
                end
            elseif Judge.Switch:isclassof(statement) then
                local ok, diagnostic = lower_switch(L_, C, statement, result_type)
                if not ok then return nil, diagnostic end
            elseif Judge.Assign:isclassof(statement) then
                local ok, diagnostic = lower_assign(L_, C, statement)
                if not ok then return nil, diagnostic end
            elseif Judge.If:isclassof(statement) then
                local ok, diagnostic = lower_if(L_, C, statement, result_type)
                if not ok then return nil, diagnostic end
            elseif Judge.While:isclassof(statement) then
                local ok, diagnostic = lower_while(L_, C, statement, result_type)
                if not ok then return nil, diagnostic end
            elseif Judge.Break:isclassof(statement) or Judge.Continue:isclassof(statement) then
                -- `break` and `continue` are statements with no operand, and both are errors outside
                -- Inside one they are jumps, and the ownership state they leave in is checked by
                -- the loop that owns them -- which is why the site is recorded rather than
                -- checked here, where the header's state is not in hand.
                local loop = C.state.loop
                if not loop then
                    return nil, Report.reject(Report.NotExecutable, statement.span)
                end
                loop.sites[#loop.sites + 1] = { moved = {} }
                local site = loop.sites[#loop.sites]
                for _, id in ipairs(loop.carried) do site.moved[id] = copy(holes(C, id)) end
                local target = Judge.Break:isclassof(statement) and loop.exit or loop.header
                C.state.block.exit = B.Jump(B.Edge(target.id, arguments_of(C, loop.carried)))
            else
                return nil, Report.bug(Report.NoLowering('statement'), statement.span)
            end
        end
        -- §3.3, again: the tail of a body is the region's EXIT, and the caller owns what that exit
        -- is. A word body that reaches its end returns Unit (§12.3); an arm that reaches its end
        -- continues at its join. Same rule, two regions -- so the tail is a parameter, not a case.
        if not C.state.block.exit then
            destroy_all(L_, C)
            C.state.block.exit = fallthrough(C)
        end
        return true
    end

    -- A definition's value, lowered on demand: an aggregate's member is a definition too, and it
    -- is scoped to the enclosing chain, so the top-level walk does not reach it (§S23).
    materialize = function(L_, C, id, span)
        -- §2.4's erasure, on the other side: a type word has no representation, so a definition whose
        -- value is one has no storage to give it. That is a MECHANISM the compiler lacks (`rep` answers
        -- nil for `TypeWord`, correctly), not a fault in the program -- and this is the one place an id
        -- becomes a value, so it is the one place that can say so. `let P = Int` then `x : P` works
        -- because the type position reads the DECLARATION; using `P` where a runtime VALUE is wanted
        -- needs the erasure to go further.
        -- §2.4's erasure REACHES every builder now, so an erased definition arriving here is the
        -- compiler disagreeing with itself -- the one shape that is a `Bug` rather than a `Missing`.
        -- This was `Missing(TypeWordValue)`, which named a mechanism that was ABSENT; the mechanism is
        -- here, so what is left is the invariant's backstop.
        if erased(L_, id) then
            return nil, Report.bug(Report.NoLowering('representation'), span)
        end
        local declaration = L_.declarations[id]
        if not declaration then
            return nil, Report.reject(Report.UseBeforeInitializer, span)
        end
        -- A WORD is a value too -- `R(t,0)`, which is what §2.6's "all top-level names are visible
        -- through the module namespace" means for a name that denotes a word -- so materializing one
        -- CONSTRUCTS it. Refusing it here is what made a capture of a word unreachable: the capture's
        -- declaration is a reference to the word, and a reference to a word is a value.
        if Judge.Word:isclassof(declaration) then
            local lowered, diagnostic = construct_base(L_, C, id, declaration.word)
            if not lowered then return nil, diagnostic end
            if is_cell(L_, id) then
                lowered = ordered(C, B.Allocate(ref(C, C.state.effect), ref(C, lowered)),
                    B.Cell(belt_type_of(L_, id)))
            end
            C.state.values[id] = lowered
            place(C, id)
            return lowered
        end
        if not Judge.Value:isclassof(declaration) then
            return nil, Report.reject(Report.UseBeforeInitializer, span)
        end
        local lowered, diagnostic = lower_initializer(L_, C, declaration.value, belt_type_of(L_, id),
            slot_type_of(L_, id))
        if not lowered then return nil, diagnostic end
        -- §3.4/§3.2: an assignable binding is address-taken, so it is allocated ONCE, at its
        -- declaration -- which is before any control flow can reach it. Every read loads it and
        -- every write stores it, and the cell's identity never changes.
        -- `is_cell` and not `declaration.mutable`: §3.7 makes a `mut` MEMBER a second reason for the
        -- storage to be addressable, and this was the second place the rule was written -- the other
        -- is `lower_place` -- so implementing it in one of them produced a binding that was celled for
        -- reads and not for writes. One owner, asked twice.
        if is_cell(L_, id) then
            lowered = ordered(C, B.Allocate(ref(C, C.state.effect), ref(C, lowered)),
                B.Cell(belt_type_of(L_, id)))
        end
        C.state.values[id] = lowered
        place(C, id)
        return lowered
    end

    -- Bind a packet's members from an incoming record: each is a LoadField of the parameter, so
    -- `advance_k` can rebuild the next record without re-running anything.
    local function unpack(L_, C, template, k, record)
        for i, id in ipairs(packet_of(L_, template, k)) do
            C.state.values[id] = pure(C, B.LoadField(ref(C, record), i - 1), field_type_of(L_, id))
        end
    end

    -- Run the preludes of one group, binding each. A member already bound is a field the record
    -- already carries, so it is skipped rather than recomputed.
    local function run_group(L_, C, template, k)
        for _, id in ipairs(packet_of(L_, template, k)) do
            if not C.state.values[id] then
                local declaration = L_.declarations[id]
                if not declaration or not declaration.value then
                    return nil, Report.bug(Report.NoLowering('prelude'), L_.definitions[1].span)
                end
                local value, diagnostic = lower_initializer(L_, C, declaration.value, belt_type_of(L_, id),
                    slot_type_of(L_, id))
                if not value then return nil, diagnostic end
                C.state.values[id] = value
            end
        end
        return true
    end

    local function construct_record(L_, C, template, k)
        local type_ = residual_type(L_, template, k)
        local refs = L()
        for _, id in ipairs(packet_of(L_, template, k)) do refs:insert(ref(C, C.state.values[id])) end
        return pure(C, B.Construct(refs), type_), type_
    end

    ---------------------------------------------------------------------------------------------
    -- The three generated functions of a word. `construct` and `advance_k` build the residual
    -- records; `run` enters the terminal with the packet as its parameters (spec §2.3).
    ---------------------------------------------------------------------------------------------

    build_construct = function(L_, template, id)
        local definition = L_.definitions[template]
        local C = open(L_, 'let_' .. definition.name .. '_construct')
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        -- §2.2's frame: the captures are PARAMETERS, declared before anything is emitted (parameters
        -- first, then instructions) and bound to their binders, so the chain uses them exactly as it
        -- uses its own storage. `unpack` refills them from the packet at every advance, and
        -- `run_group` then skips them rather than recomputing them -- which is what stops a word from
        -- rebuilding the module state it was given.
        for _, capture in ipairs(definition.declaration.word.captures or {}) do
            C.state.values[capture.binder] =
                parameter(C, field_type_of(L_, capture.binder), Semantic.Read)
        end
        local ok, diagnostic = run_group(L_, C, definition.declaration.word, 0)
        if not ok then return nil, diagnostic end
        local record, type_ = construct_record(L_, C, definition.declaration.word, 0)
        C.state.block.exit = B.Return(L{ref(C, record), ref(C, C.state.effect)})
        return freeze(C, L{type_, B.Effect}, false)
    end

    -- **Parameters first, then instructions.** A producer's position is its index among the
    -- block's parameters followed by its instructions, so emitting an instruction before a later
    -- parameter exists gives both the same position, and `ref` then silently resolves to the
    -- wrong one. Every builder declares its whole packet before it emits anything.
    build_advance = function(L_, template, k, id)
        local definition = L_.definitions[template]
        local word = definition.declaration.word
        local C = open(L_, ('let_%s_advance_%d'):format(definition.name, k - 1))
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        local previous = parameter(C, residual_type(L_, word, k - 1), Semantic.Read)
        local stage = stages_of(word)[k]
        local stage_value = parameter(C, rep(L_, stage.type), Semantic.Read)
        unpack(L_, C, word, k - 1, previous)
        C.state.values[stage.binder] = stage_value
        local ok, diagnostic = run_group(L_, C, word, k)
        if not ok then return nil, diagnostic end
        local record, type_ = construct_record(L_, C, word, k)
        C.state.block.exit = B.Return(L{ref(C, record), ref(C, C.state.effect)})
        return freeze(C, L{type_, B.Effect}, false)
    end

    build_run = function(L_, template, id)
        local definition = L_.definitions[template]
        local word = definition.declaration.word
        local C = open(L_, 'let_' .. definition.name .. '_run')
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        unpack(L_, C, word, word.stages, parameter(C, residual_type(L_, word, word.stages), Semantic.Read))
        local type_ = rep(L_, L_.types[template].result)
        if not type_ then
            return nil, Report.bug(Report.NoLowering('representation'), definition.span)
        end
        -- The terminal is a data expression, a `do` body, or -- for a DECLARED host word -- a host
        -- symbol. They lower differently: the first is a value, the second a sequence of statements
        -- whose exit is its `return`, and the third is one call whose arguments are the packet's
        -- members in order. Falling off the end of a body returns Unit (§12.3).
        --
        -- Purity decides which host op: a pure host word folds and carries no effect (§12.2's full
        -- promise), an ordered one takes the effect and threads it.
        -- A CONVERSION word's run is one pure op over the packet's member. §11.7 puts `Convert` among
        -- the pure ops, which is what lets the folder fold one whose operand it knows -- and a folded
        -- conversion is why `ToCString "x"` costs nothing at all.
        if word.terminal and Chain.Convert:isclassof(word.terminal) then
            local members = packet_of(L_, word, word.stages)
            -- The sole member is the LAST one: §2.2 puts the capture frame first, and a conversion
            -- word is built by the resolver where there is nothing to capture -- so this is its stage,
            -- and reading it as `[1]` would be reading the frame.
            local member = members[#members]
            local value = pure(C, B.Convert(word.terminal.kind, ref(C, C.state.values[member])), type_)
            C.state.block.exit = B.Return(L{ref(C, value), ref(C, C.state.effect)})
            return freeze(C, L{type_, B.Effect}, false)
        end
        if not definition.declaration.terminal then
            local arguments = L()
            for index in ipairs(packet_of(L_, word, word.stages)) do
                arguments:insert(ref(C, C.state.values[packet_of(L_, word, word.stages)[index]]))
            end
            local symbol = word.terminal.symbol
            if word.purity == Semantic.Pure then
                local result = pure(C, B.PureHostCall(symbol, arguments), type_)
                C.state.block.exit = B.Return(L{ref(C, result), ref(C, C.state.effect)})
            else
                local result = ordered(C, B.HostCall(symbol, ref(C, C.state.effect), arguments), type_)
                C.state.block.exit = B.Return(L{ref(C, result), ref(C, C.state.effect)})
            end
        elseif Judge.Data:isclassof(definition.declaration.terminal) then
            local result, diagnostic =
                lower_initializer(L_, C, definition.declaration.terminal.value, type_)
            if not result then return nil, diagnostic end
            C.state.block.exit = B.Return(L{ref(C, result), ref(C, C.state.effect)})
        else
            -- §S110/§S114: a `return` is a place where a value must BECOME the word's result, so it is
            -- an injection site like a binding or a stage argument -- and the injection is a SEMANTIC
            -- question (`Lower` cannot read an alternative off a representation). So the word's semantic
            -- result travels beside the belt one while its body is lowered. Without it, `return { … }`
            -- in a sum-returning word was `MismatchedType`, and every parser grew `ok`/`fail` words.
            local saved_result = L_.word_result
            L_.word_result = L_.types[template].result
            local ok, diagnostic = lower_body(L_, C, definition.declaration.terminal.statements,
                type_, definition.span, function(region)
                    -- §S66 + §3.6's trap: a body that FALLS OFF ITS END is only reachable when the
                    -- result is Unit -- `Contract` refuses a non-Unit body that does not return -- so
                    -- reaching this with any other result means the path is IMPOSSIBLE, and an
                    -- impossible path is a TRAP, never a default value. It was `return 0`, which does
                    -- not even compile for a sum result: the C returned `long int` from a function
                    -- returning the sum struct.
                    if type_ ~= B.Unit then
                        return B.Trap(ref(region, region.state.effect), 'fell off the end')
                    end
                    local unit = pure(region, B.UnitLiteral, B.Unit)
                    return B.Return(L{ref(region, unit), ref(region, region.state.effect)})
                end)
            L_.word_result = saved_result
            if not ok then return nil, diagnostic end
        end
        return freeze(C, L{type_, B.Effect}, false)
    end

    ---------------------------------------------------------------------------------------------
    -- The root. The module initializer IS the file chain's run (spec §2.6), so it is lowered
    -- inline: every top-level value prelude runs in source order because spec §2.6 makes
    -- initialization observable, and a written terminal replaces the namespace (§2.6).
    ---------------------------------------------------------------------------------------------

    -- §2.6: "an embedding host selects and invokes an exported top-level word after initialization
    -- completes." So every top-level word gets an ENTRY POINT -- a function taking the module value
    -- plus that word's remaining stages -- and it is a ROOT of demand, alongside the initializer.
    --
    -- That is the whole point: without it, a word nothing inside the module applies is demanded at
    -- prefix 0 only (S25), so its `advance_k` and `run` do not exist and the host has nothing to
    -- call. Being a root is what makes an exported word lowerable on its own.
    --
    -- The word VALUE comes out of the namespace, because the initializer constructed it and put it
    -- there. That is also why entries are generated only for the implicit namespace: a written
    -- terminal CHOOSES the export surface (§2.6), so which names it exposes is not structural.
    lower_entry = function(L_, template, id)
        local declaration = L_.declarations[template]
        if not declaration or not Judge.Word:isclassof(declaration) then
            return nil, Report.bug(Report.NoLowering('entry point'), L_.definitions[1].span)
        end
        local word = declaration.word
        local stages = stages_of(word)
        -- The initializer is demanded first, so the namespace's type is already known. A written
        -- terminal does not produce entries at all -- it CHOOSES the export surface (§2.6), so
        -- which names it exposes is not a structural fact and the entry cannot read one out of it.
        local namespace_type = L_.namespace_type
        local result_type = rep(L_, L_.types[template].result)
        if not namespace_type or not result_type then
            return nil, Report.bug(Report.NoLowering('representation'), L_.definitions[1].span)
        end

        -- The member's index in the namespace, which is source order among the top-level names --
        -- the same order `lower_module` builds the record in.
        -- The member's index in the namespace, which is the order `lower_module` BUILT the record in --
        -- asked of the RECORD rather than re-derived. The re-derivation was a second copy of "which
        -- definitions are members", and it was missing §2.4's erasure: with `let P = Int` erased the
        -- index counted it, the struct did not have it, and the entry point loaded a field past the
        -- end of the record (`emit.lua:31`). One owner -- the list the record was built from.
        local index
        for position, member in ipairs(L_.namespace_members or {}) do
            if member.id == template then index = position - 1 break end
        end
        if not index then
            return nil, Report.bug(Report.NoLowering('entry point'), L_.definitions[1].span)
        end

        local C = open(L_, 'let_' .. L_.names[template] .. '_entry')
        -- Every parameter exists BEFORE any instruction: the numbering rule's first corollary, and
        -- the reason the stages are created in one pass and only then consumed.
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        local module = parameter(C, namespace_type, Semantic.Read)
        local supplied = L()
        for _, stage in ipairs(stages) do
            supplied:insert(parameter(C, rep(L_, stage.type), Semantic.Read))
        end

        local value = pure(C, B.LoadField(ref(C, module), index), residual_type(L_, word, 0))
        for k = 0, #stages - 1 do
            local advance = demand(L_, 'advance:' .. template .. ':' .. (k + 1), function(M, which)
                return build_advance(M, template, k + 1, which)
            end)
            if not advance then return nil, L_.diagnostic end
            value = ordered(C, B.CallFunction(advance, ref(C, C.state.effect),
                L{ref(C, value), ref(C, supplied[k + 1])}), residual_type(L_, word, k + 1))
        end
        local run = demand(L_, 'run:' .. template, function(M, which)
            return build_run(M, template, which)
        end)
        if not run then return nil, L_.diagnostic end
        local result = ordered(C, B.CallFunction(run, ref(C, C.state.effect), L{ref(C, value)}),
            result_type)
        C.state.block.exit = B.Return(L{ref(C, result), ref(C, C.state.effect)})
        return freeze(C, L{result_type, B.Effect}, true)
    end

    local function lower_module(L_, id)
        local C = open(L_, 'let_module_init')
        C.state.effect = parameter(C, B.Effect, Semantic.Read)

        local members = L()
        for _, definition in ipairs(L_.definitions) do
            if not definition.scope and not erased(L_, definition.id) then
                local declaration = definition.declaration
                if Judge.Value:isclassof(declaration) then
                    -- §2.4: "a type word is a chain with `Type` domains and a data terminal, evaluated
                    -- at construction time and ERASED" -- and the ERASING is the part this compiler
                    -- does not have, so a binding whose value is one has no storage to give it. `rep`
                    -- answering nil for `TypeWord` is CORRECT (a type word is not a layout); calling
                    -- that a `Bug` was not, because it blamed the compiler for a program the GRAMMAR
                    -- accepts (§S99's lesson). The erasure has to reach the PACKET as well -- a word
                    -- that captures such a binding still lists it -- and until it does, this is a
                    -- `Missing`: the mechanism, not the program.
                    -- `field_type_of` and not `rep`: what a namespace member's SLOT holds is the same
                    -- question a capture's slot and a packet member's slot ask, and it is not the same
                    -- question as "what does this type look like" -- a WORD-typed value's layout is its
                    -- packet, and a CELLED member's slot is its address. This site bypassed both rules,
                    -- which is why binding a partial application was a `Bug(NoLowering)`.
                    local type_ = field_type_of(L_, definition.id)
                    if not type_ then
                        return nil, Report.bug(Report.NoLowering('representation'),
                            definition.span)
                    end
                    -- `materialize` and not `lower_initializer`: a top-level `mut` prelude is a CELL
                    -- exactly as a local one is, and this was the second place the cell was decided --
                    -- so the namespace held the value where every word's capture expected the address.
                    local value, diagnostic = materialize(L_, C, definition.id, definition.span)
                    if not value then return nil, diagnostic end
                    members:insert({ name = definition.name, id = definition.id,
                        span = definition.span })
                elseif Judge.Word:isclassof(declaration) then
                    -- §2.6: "all top-level names are visible through the module namespace", so a
                    -- top-level WORD is a value in it -- `R(t,0)`, which is what the name denotes
                    -- before it is applied. The initializer CONSTRUCTS it and the namespace owns it;
                    -- advancing and running it is the host entry point's business (§2.6), so the
                    -- word's own `advance_k`/`run` are demanded there and not here.
                    local constructed, diagnostic = construct_base(L_, C, definition.id,
                        declaration.word)
                    if not constructed then return nil, diagnostic end
                    C.state.values[definition.id] = constructed
                    members:insert({ name = definition.name, id = definition.id, span = definition.span })
                end
            end
        end

        local record, result
        local program = L_.program
        if program.namespace then
            result = rep(L_, program.namespace_type)
            if not result then
                return nil, Report.bug(Report.NoLowering('representation'), L_.definitions[1].span)
            end
            local value, diagnostic = lower_initializer(L_, C, program.namespace, result)
            if not value then return nil, diagnostic end
            record = value
            -- §2.6: the module value is `{ export, state }` and "the returned value must own what the
            -- namespace does not reach". For a WRITTEN terminal the export IS the terminal's value, so
            -- the module owns it -- and that is what `unload` destroys, which is the half this phase did
            -- not have: a written terminal holding a resource leaked it at unload in silence.
            --
            -- The `state` member is the other half, and it is needed only when the terminal did NOT take
            -- everything: a prelude the terminal moved into its value is owned there and must not be
            -- owned twice, and one it left behind is still the module's. Building that member turns the
            -- module value into a PAIR, which is a mechanism this phase does not have -- so it is
            -- reported, and only when something is actually left over.
            -- "What the namespace does NOT REACH" is §2.6's own phrase and it is computable: the
            -- terminal's value reaches a definition when it names it -- including through the
            -- declarations it names, because `{ let x = move h }` reaches `h` -- so the members it
            -- reaches are owned by the terminal, and the ones it does not are still the module's.
            local reached = {}
            local function mark(initializer, depth)
                if depth > 16 then return end
                if Judge.Reference:isclassof(initializer) then
                    if reached[initializer.definition] then return end
                    reached[initializer.definition] = true
                    local declaration = L_.declarations[initializer.definition]
                    if declaration and Judge.Value:isclassof(declaration) then
                        mark(declaration.value, depth + 1)
                    end
                elseif Judge.Aggregate:isclassof(initializer) then
                    for _, member in ipairs(initializer.members) do mark(member.value, depth + 1) end
                elseif Judge.Move:isclassof(initializer) then
                    mark(initializer.place, depth + 1)
                end
            end
            mark(program.namespace, 0)

            -- And "owns something" is a question about the VALUE's representation, not about a word's
            -- TYPE: a word's interface result is what its `run` RETURNS, so a word whose packet is empty
            -- -- `made`, in the program this was written for -- looked like a `Handle` and was counted
            -- as a resource. A word owns what its packet owns.
            local function owns_member(id)
                local declaration = L_.declarations[id]
                if declaration and Judge.Word:isclassof(declaration) then
                    for _, packet_id in ipairs(declaration.word:members(0)) do
                        local interface = L_.types[packet_id]
                        if interface and destroys(L_, interface.result) then return true end
                    end
                    return false
                end
                return destroys(L_, L_.types[id].result)
            end

            local left = 0
            for _, member in ipairs(members) do
                if not reached[member.id] and C.state.values[member.id]
                        and not place(C, member.id).moved[''] and owns_member(member.id) then
                    left = left + 1
                end
            end
            if left > 0 then
                return nil, Report.missing(Report.ModuleState, program.namespace.span)
            end
            -- What the unloader needs: the module VALUE's type, by belt and by meaning.
            L_.namespace_type, L_.namespace_semantic = result, program.namespace_type
            L_.namespace_members = nil
        else
            -- §2.6: the namespace takes ownership of its members, so a non-Copy one is MOVED into
            -- it -- which is why `{ let handle = move buffer }` is the written form. Every `take`
            -- runs before any ref is computed, because a ref is relative to the consumer.
            local taken = L()
            for _, member in ipairs(members) do
                local value, diagnostic
                if is_cell(L_, member.id) then
                    -- §3.2: a celled member's storage IS its cell, and a word may already hold that
                    -- address (§S76's captures) -- so the namespace keeps the CELL rather than moving
                    -- the content out from under a live pointer. One indirection, shared, no second
                    -- allocation: the same rule a capture follows, because it is the same relationship.
                    local p
                    p, diagnostic = lower_place(L_, C, Judge.Reference(member.id, member.span))
                    if not p then return nil, diagnostic end
                    value = p.value
                else
                    value, diagnostic = take(L_, C, member.id, member.span)
                    if not value then return nil, diagnostic end
                end
                taken:insert({ name = member.name, value = value })
            end
            -- §2.6's unloader destroys what the namespace owns, so the namespace's own member list is
            -- the thing it needs -- and it is built here, which makes this the one owner of "what is in
            -- the namespace" as well. A WRITTEN terminal is a different case and gets no unloader yet:
            -- §2.6's `state` member ("whatever the namespace does not reach") is its other half, and
            -- neither half is worth doing alone.
            L_.namespace_members = members
            local fields, refs = L(), L()
            for _, member in ipairs(taken) do
                fields:insert(B.Field(member.name, member.value.type, false))
                refs:insert(ref(C, member.value))
            end
            result = B.Aggregate(fields)
            -- The namespace's belt type, recorded because a HOST ENTRY POINT needs it: the entry
            -- takes the module value and reads the word out of it, and the implicit namespace has no
            -- `Judge.Program.namespace_type` to read the type from -- only a written terminal does.
            L_.namespace_type = result
            record = pure(C, B.Construct(refs), result)
        end

        C.state.block.exit = B.Return(L{ref(C, record), ref(C, C.state.effect)})
        return freeze(C, L{result, B.Effect}, true)
    end

    -- §2.6: "`unload` takes the module value by value -- the host gives it up -- and destroys it in
    -- reverse successful-construction order. It is generated, and emitted only when the module owns
    -- something: a module owning nothing has no unload."
    --
    -- It is a FUNCTION rather than a continuation of the initializer for the reason the sentence
    -- gives: the initializer RETURNS the module value, so it cannot destroy what it returns. And
    -- `destroy_all` already implements the order -- §3.1 rule 2, reverse initialization -- so the body
    -- is the namespace's members bound from the module value and then the ordinary destruction pass.
    -- That is why there is no new belt operation here and no new rule: the module value is a packet
    -- like any other, and the unloader is a function that takes one.
    local function build_unload(L_, id)
        local C = open(L_, 'let_module_unload')
        C.state.effect = parameter(C, B.Effect, Semantic.Read)
        local module = parameter(C, L_.namespace_type, Semantic.Read)
        if L_.namespace_members then
            -- The IMPLICIT namespace: the module value IS the namespace, so its members are bound by
            -- index and destroyed in the order the initializer built them.
            for index, member in ipairs(L_.namespace_members) do
                C.state.values[member.id] = pure(C, B.LoadField(ref(C, module), index - 1),
                    field_type_of(L_, member.id))
            end
            destroy_all(L_, C)
        else
            -- A WRITTEN terminal: the module value is the terminal's value, and the module owns it --
            -- so `unload` destroys the VALUE and not a record of names. The root is synthetic because
            -- destruction is the one place that asks a PLACE for its state, and this value is a
            -- parameter rather than a binding.
            L_.synthetic = (L_.synthetic or 0) - 1
            destroy_value(L_, C, L_.synthetic, '', L_.namespace_semantic, module)
        end
        C.state.block.exit = B.Return(L{ref(C, C.state.effect)})
        -- `L{effect}` and nothing else: a function whose only result is the effect returns NOTHING in
        -- C, which is exactly the `void` §2.6 writes, and the emitter already prints it that way.
        return freeze(C, L{B.Effect}, true)
    end

    function Lower.run(unit, program, syntax, k_ok, k_diag)
        local L_ = lowerer(unit, program)
        -- §S23's roots, and there are two kinds of them. The module initializer is one. The other
        -- is one entry point per exported top-level word: a word the host invokes is demanded even
        -- when nothing inside the module applies it.
        local root = demand(L_, 'module', function(M) return lower_module(M, 0) end)
        if not root then return k_diag(unit, L_.diagnostic) end
        if not program.namespace then
            for _, definition in ipairs(L_.definitions) do
                -- §2.4: a TYPE word has no runtime terminal and its stages are types, so it is erased
                -- (§S107) and must not be given an entry point -- the host calls words, and a type is
                -- not one.
                if not definition.scope and not erased(L_, definition.id)
                        and Judge.Word:isclassof(definition.declaration) then
                    local entry = demand(L_, 'entry:' .. definition.id, function(M)
                        return lower_entry(M, definition.id, 0)
                    end)
                    if not entry then return k_diag(unit, L_.diagnostic) end
                end
            end
        end
        -- §2.6: the unloader is a THIRD root, and it exists only when the module OWNS something --
        -- which makes the demand a question about the namespace's members rather than about the
        -- module existing. "Owning" is §3.1's own question: a type that has a destructor.
        local owns = L_.namespace_semantic ~= nil and destroys(L_, L_.namespace_semantic)
        if not owns then
            for _, member in ipairs(L_.namespace_members or {}) do
                if destructor_of(L_, member.id) then owns = true break end
            end
        end
        if owns then
            local unload = demand(L_, 'unload', function(M, id) return build_unload(M, id) end)
            if not unload then return k_diag(unit, L_.diagnostic) end
        end

        local functions = L()
        for id = 1, L_.next_id do functions:insert(L_.functions[id]) end
        unit.ambient.belt = functions
        return k_ok(unit, functions)
    end

    return Lower
end
