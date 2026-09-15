-- Shared capability decisions for both advancement destinations. These are
-- compile-time contracts, not runtime borrow objects or an evaluator.
return function(V)
local A,B=V.AST,V.Belt
local function mode(destination)
    assert(destination==B.Persistent or destination==B.Transient,'binding needs an explicit destination')
end
local function ordinary(value,fail)
    if value.mode=='mut' then fail('mutable borrow requires a mutable stage') end
end
function A.Read:bind_argument(value,destination,fail)
    mode(destination); ordinary(value,fail)
    if value.type:copyable() then return B.CopyAccess,false end
    if destination==B.Persistent then fail('persistent read stage requires a Copy value') end
    return B.ReadAccess,value.mode=='fresh'
end
local function own(_,value,destination,fail)
    mode(destination); ordinary(value,fail)
    if value.type:copyable() then return B.CopyAccess,false end
    if value.mode~='fresh' then fail('owned stage requires move or a fresh result') end
    return B.OwnAccess,false
end
A.Own.bind_argument=own; A.OwnMut.bind_argument=own
function A.Mut:bind_argument(value,destination,fail)
    mode(destination)
    if destination==B.Persistent then fail('mutable borrow cannot become persistent state') end
    if value.mode~='mut' then fail('mutable stage requires mut place') end
    return B.MutAccess,false
end
-- The receiver is distinct from the argument supplied to its next stage.
-- Freshness comes from ownership analysis, never a runtime flag.
function V.specialization_access(value,fail)
    ordinary(value,fail)
    if value.type:copyable() then return B.CopyAccess end
    if value.mode=='fresh' then return B.OwnAccess end
    fail('specialization of an existing non-copyable word requires an explicit independent copy')
end
end

