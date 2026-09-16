-- Invariants over the belt's type union (§7). The union is closed, so every constructor has to
-- answer every question about it, and two of those questions have two authorities: a per-type
-- method (`t:owns()`) and a central function reached through `B.Type` (`B.Type.owns(t)`). Two
-- authorities can drift, and one did: `B.Sum:owns` was a hardcoded `false` that stayed behind when
-- the rule moved to the central function, so a sum holding an owned alternative claimed to own
-- nothing. This file pins the agreement, and pins the constructor list against the definition
-- itself, so the next drift is caught here rather than by a program that miscompiles.
package.path='./?.lua;./?/init.lua;'..package.path
local V=require('let'); local B,L=V.Belt,V.List
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

local field=function(name,type_,mutable) return B.Field(name,type_,mutable or false) end

-- One instance per constructor of `Belt.Type`, keyed by the constructor's own name.
local samples={
    Int=B.Int, U8=B.U8, U32=B.U32, Float=B.Float, Float32=B.Float32, Bool=B.Bool,
    Unit=B.Unit, Text=B.Text, Effect=B.Effect, CString=B.CString, CPointer=B.CPointer,
    TypeWord=B.TypeWord,
    Named=B.Named('CAlloc'),
    Address=B.Address(B.Int),
    Borrow=B.Borrow(B.Int,false),
    Aggregate=B.Aggregate(L{field('a',B.Int)},true,nil),
    Word=B.Word(1,1,L{field('a',B.Int)},false),
    Callable=B.Callable(B.Signature(L{},L{B.Int})),
    Arrow=B.Arrow(B.Int,B.Do(B.Unit)),
    Do=B.Do(B.Int),
    Sum=B.Sum(L{B.Int,B.Text},true),
}

-- Other instances the assertions below need, which are not constructors of their own.
local variant={
    AggregateOwned=B.Aggregate(L{field('a',B.Named('CAlloc'))},false,nil),
    AggregateMutable=B.Aggregate(L{field('a',B.Int,true)},false,nil),
    BorrowStable=B.Borrow(B.Int,true),
    SumOwned=B.Sum(L{B.Int,B.Named('CAlloc')},false),
}

-- The union itself is the guard. `B.Type.members` lists every constructor, so a constructor added
-- without a sample fails here -- which is the point: it cannot arrive without someone answering the
-- questions below about it.
local declared={}
for class in pairs(B.Type.members) do
    -- A class prints as `Class(Belt.Sum)`, so the name is taken from inside the parentheses.
    local name=tostring(class):match('Belt%.([%w_]+)')
    if name and name~='Type' then declared[name]=true end
end
local missing={}
for name in pairs(declared) do if not samples[name] then missing[#missing+1]=name end end
-- Proving the list was read rather than silently empty, so the guard above cannot pass vacuously.
check(declared.Sum and declared.TypeWord and declared.Aggregate and declared.Int,
    'the constructor list was read from the definition itself')
table.sort(missing)
eq(#missing,0,'every Belt.Type constructor has a sample; missing: '..table.concat(missing,', '))

-- And each sample is an instance of the constructor it is filed under, so a sample cannot be the
-- wrong type and quietly satisfy the list.
for name,type_ in pairs(samples) do
    check(B[name] and B[name]:isclassof(type_),name..': the sample is an instance of its own constructor')
end

-- §7 The two authorities for owning and borrowing must agree, for every constructor and for the
-- one place where a flag changes the answer (a stable borrow).
local agreement={}
for name,type_ in pairs(samples) do agreement[name]=type_ end
for name,type_ in pairs(variant) do agreement[name]=type_ end
for name,type_ in pairs(agreement) do
    eq(tostring(type_:owns()),tostring(B.Type.owns(type_)),name..': owns agrees between the method and the central function')
    eq(tostring(type_:borrows()),tostring(B.Type.borrows(type_)),name..': borrows agrees between the method and the central function')
end

-- Every question has an answer for every constructor. A missing method is a crash at the first use,
-- and it is cheaper to find here; the answers themselves are checked where they are used.
for name,type_ in pairs(agreement) do
    eq(type(type_:copyable()),'boolean',name..': copyable answers with a boolean')
    eq(type(B.Type.owns(type_)),'boolean',name..': owns answers with a boolean')
    eq(type(B.Type.borrows(type_)),'boolean',name..': borrows answers with a boolean')
    eq(type(type_:key()),'string',name..': key answers with a string')
    eq(type(type_:same(type_)),'boolean',name..': same answers, and a type is itself')
end

-- §7 Owning lives in the structural types. These are the answers the compiler leans on, so they are
-- asserted rather than assumed -- a scalar owns nothing, and a composite owns what its parts do.
eq(B.Type.owns(B.Int),false,'an Int owns nothing')
eq(B.Type.owns(B.Named('CAlloc')),true,'a resource owns')
eq(B.Type.owns(samples.Aggregate),false,'a Copy aggregate owns nothing')
eq(B.Type.owns(variant.AggregateOwned),true,'an aggregate owns what a member owns')
eq(B.Type.owns(samples.Sum),false,'a Copy sum owns nothing')
eq(B.Type.owns(variant.SumOwned),true,'a sum owns what an alternative owns')
eq(B.Type.borrows(samples.Borrow),true,'an unstable borrow borrows')
eq(B.Type.borrows(variant.BorrowStable),false,'a stable borrow outlives its activation, so it does not borrow')

-- §8.5 Copy: every contained value Copy, and no declared mutable member.
eq(samples.Aggregate:copyable(),true,'an aggregate of Copy members is Copy')
eq(variant.AggregateMutable:copyable(),false,'a mutable member makes an aggregate non-Copy')
eq(samples.Sum:copyable(),true,'a sum of Copy alternatives is Copy')
eq(variant.SumOwned:copyable(),false,'a sum with a non-Copy alternative is not Copy')

print(('passed %d belt type checks'):format(checks))
