-- The word field packet: the ordered bundle of values a word carries between its stages, and
-- the one owner of what a field means.
--
-- A field descriptor is `{name, type, value, mutable, owned, retained, span}` plus whatever the
-- site knows: `capability` for a stage, `definition` for a prelude, `borrows` for a capture. The
-- derived questions -- is it a place, is it owned by the entry, is it written back, what is the
-- entry key -- live here, so the six sites that build a packet and the four that consume one do
-- not each restate them. See DESIGN.md.
return function(V)
local A,B=V.AST,V.Belt

local Packet={}

-- A field that reaches the callee as a place -- an address or a borrow -- is written through,
-- not copied. This is the one place the question is asked.
function Packet.place(type_) return B.Address:isclassof(type_) or B.Borrow:isclassof(type_) end

-- Normalize a descriptor: a site supplies what it knows, and the shared defaults live here.
function Packet.field(spec)
    spec.mutable=spec.mutable==true
    spec.owned=spec.owned==true
    spec.retained=spec.retained==true
    return spec
end

-- A field parameterized into an entry is owned by that entry when it is non-Copy, is not a place,
-- and the word already owned it or its stage takes ownership.
function Packet.entry_owned(field)
    if Packet.place(field.type) or field.type:copyable() then return false end
    return field.owned or A.owns(field.capability)
end

-- The type a stage delivers and who owns it. `mut` and `own mut` reach the callee as a place
-- through a borrow; `own` and `own mut` carry ownership. One rule, so the generic builder and a
-- host entry cannot disagree about what a stage delivers.
function Packet.stage_field(capability,name,span,type_)
    local place=A.places(capability)
    local owned=not type_:copyable() and A.owns(capability)
    return Packet.field{name=name,type=place and B.Borrow(type_,false) or type_,
        mutable=A.places(capability),owned=owned,retained=false,
        span=span,capability=capability,external=place or (not owned and not type_:copyable())}
end

-- The parameter a host entry receives for a stage. The host supplies the value, so there is no
-- field packet here; the shape and the mode are all that matter.
function Packet.stage_parameter(ctx,capability,type_,span)
    local place=A.places(capability)
    local value=ctx:parameter(place and B.Borrow(type_,false) or type_,A.Read)
    if capability==A.Mut then value.mode='mut'
    elseif capability==A.Own or capability==A.OwnMut then value.mode='fresh' end
    return value
end

-- The fields an invocation hands back to the receiver: interior mutable state it can receive. A
-- place is written through the callee itself, so it is never a result.
function Packet.written_back(field)
    return field.mutable and field.retained and not B.Address:isclassof(field.type)
end


-- The entry a field packet names. One key per shape, so call sites that agree share one function
-- and its signature. The per-field flag runs are separate so a shape cannot collide with a longer
-- one that happens to reuse the same type keys.
function Packet.key(template_id,fields)
    local parts={tostring(template_id)}
    for _,field in ipairs(fields) do parts[#parts+1]=field.type:key() end
    for _,field in ipairs(fields) do parts[#parts+1]=field.retained and '1' or '0' end
    for _,field in ipairs(fields) do parts[#parts+1]=field.owned and '1' or '0' end
    return table.concat(parts,'|')
end

-- Bind a field the packet already holds, in the scope the caller opened. A place is bound as its
-- own storage, so the body reaches the caller's value rather than a copy.
function Packet.bind(ctx,field)
    local address=Packet.place(field.value.type) and field.value or false
    ctx:force_bind(field.name,field.value,field.mutable,field.owned,false,address,field.span)
end

function Packet.bind_all(ctx,fields)
    for _,field in ipairs(fields) do Packet.bind(ctx,field) end
end

-- Bind a field as a fresh parameter of an entry, in its own scope. An entry owns a non-Copy,
-- non-place field, and the parameter is what the caller's field becomes here. Returns the binding
-- id, the parameter value and the ownership the entry took, so a caller can record or trace it.
function Packet.bind_parameter(ctx,field,name,span)
    ctx:push(); if field.retained then ctx:retain() end
    local parameter=ctx:parameter(field.type,A.Read)
    if field.capability==A.Mut then parameter.mode='mut'
    elseif field.capability==A.Own or field.capability==A.OwnMut then parameter.mode='fresh' end
    local owned=Packet.entry_owned(field)
    local address=Packet.place(field.type) and parameter or false
    -- The flag `build.lua` reads for a tail-call borrow is "does this binding's storage outlive my
    -- activation". Two things do: a field reached from the caller (`external`), and a *retained*
    -- field, whose storage lives in the word bundle rather than in the frame. A prelude is retained,
    -- so `return c.load_byte(cells, i)` over the word's own prelude is not a dangling borrow and
    -- was wrongly refused.
    local outlives=field.external==true or field.retained==true
    local binding=ctx:force_bind(name or field.name,parameter,field.mutable,owned,outlives,address,span or field.span)
    return binding,parameter,owned
end

return Packet
end
