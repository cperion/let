-- Immutable semantic producers. Relative references never change during demand analysis.
return function(context)
    context:Define [[
module Belt {
    Destination = Persistent | Transient
    Access = CopyAccess | OwnAccess | ReadAccess | MutAccess
    Field = (string? name, Type type, boolean mutable)
    Type = Int | U8 | U32 | Float | Bool | Unit | Text | Effect | CString | CPointer
         | Named(string name) | Address(Type pointee)
         | Borrow(Type pointee, boolean stable)
         | Aggregate(Field* fields, boolean is_copy, string? name)
         | Word(number template, number supplied, Field* fields, boolean is_copy)
         | Callable(Signature signature)
         | Arrow(Type from, Type to) | Do(Type result)
         | Sum(Type* alternatives, boolean is_copy)
         | TypeWord
    Parameter = (Type type, AST.Capability capability)
    Signature = (Parameter* parameters, Type* results)
    Ref = (number distance, number output)
    Instruction = (Op operation, Type* results, Source.Span? span)
    Op = IntegerLiteral(string spelling) | FloatLiteral(string spelling) | BooleanLiteral(boolean value) | UnitLiteral | TextLiteral(string value)
       | TextOf(Ref pointer, Ref size)
       | Unary(AST.UnaryOp operator, Ref operand)
       | Binary(AST.BinaryOp operator, Ref left, Ref right)
       | CheckedBinary(AST.BinaryOp operator, Ref effect, Ref left, Ref right)
       | BorrowPlace(Ref address, boolean stable)
       | FieldAddress(Ref place, number field, boolean stable)
       | Construct(Ref* fields, boolean is_copy)
       | LoadField(Ref record, number field)
       | StoreField(Ref record, number field, Ref value)
       | CallFunction(number target, Ref effect, Ref* arguments)
       | HostCall(string symbol, Ref effect, Ref* arguments)
       | PureHostCall(string symbol, Ref* arguments)
       | Allocate(Ref effect, Ref initial)
       | Load(Ref effect, Ref address) | Store(Ref effect, Ref address, Ref value)
       | Move(Ref effect, Ref value) | Destroy(Ref effect, Ref value, string destructor)
    Edge = (number target, Ref* arguments)
    Exit = Return(Ref* values) | Jump(Edge edge)
         | Branch(Ref condition, Edge yes, Edge no)
         | TailCall(number target, Ref effect, Ref* arguments)
         | Trap(Ref effect, string reason)
    Block = (Parameter* parameters, Instruction* instructions, Exit exit)
    Function = (string name, Signature signature, Block* blocks)
    Template = (string name, number stages, number captures, Source.Span? span)
    Program = (string name, Template* templates, Function* functions)
}
    ]]

    local B=context.Belt
    local L=require('terralist')
    -- Type semantics belong to the belt vocabulary, not to one consumer: construction,
    -- verification, demand analysis and emission all ask these questions.
function B.Type:same(other) return self==other end
function B.Named:same(other) return B.Named:isclassof(other) and self.name==other.name end
function B.Address:same(other) return B.Address:isclassof(other) and self.pointee:same(other.pointee) end
local function fields_same(a,b)
    if #a~=#b then return false end
    for i,field in ipairs(a) do
        if field.name~=b[i].name or field.mutable~=b[i].mutable or not field.type:same(b[i].type) then return false end
    end
    return true
end
-- A borrow is a view of a place: the same pointee, but not the same thing to own.
function B.Borrow:same(other)
    return B.Borrow:isclassof(other) and self.stable==other.stable and self.pointee:same(other.pointee)
end
function B.Aggregate:same(other)
    return B.Aggregate:isclassof(other) and self.name==other.name
        and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
function B.Word:same(other)
    return B.Word:isclassof(other) and self.template==other.template and self.supplied==other.supplied
        and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
-- §11.1: a word's type is a unary spine of arrows ending in its terminal. `Arrow` is one unary
-- step, `Do` is the runtime terminal modality, and `Sum` is a tagged union (§11.5).
function B.Arrow:same(other)
    return B.Arrow:isclassof(other) and self.from:same(other.from) and self.to:same(other.to)
end
function B.Do:same(other)
    return B.Do:isclassof(other) and self.result:same(other.result)
end
function B.Sum:same(other)
    if not B.Sum:isclassof(other) or self.is_copy~=other.is_copy then return false end
    if #self.alternatives~=#other.alternatives then return false end
    for i,alternative in ipairs(self.alternatives) do
        if not alternative:same(other.alternatives[i]) then return false end
    end
    return true
end
function B.Type:copyable() return false end
function B.Int:copyable() return true end
-- §13.2 fixed-width integers are Copy values, like Int.
function B.U8:copyable() return true end
function B.U32:copyable() return true end
function B.Float:copyable() return true end
function B.Bool:copyable() return true end
function B.Unit:copyable() return true end
function B.Text:copyable() return true end
-- A C string is a borrowed `const char*`: Copy as a value, owned by C rather than by Let.
function B.CString:copyable() return true end
-- An opaque C pointer: Copy as a value, and never dereferenced or owned by Let.
function B.CPointer:copyable() return true end
-- §8.5: an aggregate is Copy exactly when every contained value is Copy and it declares
-- no mutable member. Both facts are recorded in the type, because member types alone
-- cannot express a declared mutable member.
function B.Aggregate:copyable() return self.is_copy end
-- A word type promises no copyability by itself: the word a stage holds may carry owned or
-- mutable state, so an Arrow and a Do thunk are conservatively non-copyable. A tagged union is
-- Copy exactly when every alternative is (and no alternative is mutable).
function B.Arrow:copyable() return false end
function B.Do:copyable() return false end
function B.Sum:copyable() return self.is_copy end
-- §11.5: a sum is represented as a tagged record -- the tag first, then one field per
-- alternative. The existing Construct/LoadField machinery then builds and projects it, and
-- `switch` on the tag eliminates it. `left`/`right` name a binary sum; more alternatives are
-- `f1`, `f2`, ....
local function sum_fields(alternatives)
    local L=require('terralist')
    local fields=L{B.Field('tag',B.Int,false)}
    for i,alternative in ipairs(alternatives) do
        local name
        if #alternatives==2 and i==1 then name='left'
        elseif #alternatives==2 and i==2 then name='right'
        else name='f' .. i end
        fields:insert(B.Field(name,alternative,false))
    end
    return fields
end
function B.Sum:record() return sum_fields(self.alternatives) end
-- §11.2: a `Type` value is a type word itself. It is a compile-time value: copyable, with no
-- runtime representation, and it never appears in an emitted signature.
function B.TypeWord:copyable() return true end
function B.TypeWord:key() return 'typeword' end
-- A type word is a compile-time value with no data; it has an empty shape and a one-byte
-- representation so a module may carry a type alias in its state without a special case.
function B.TypeWord:record() return L() end

-- Word records and aggregates are both ordered fields; only words carry a template.
function B.Type:record()
    -- §11.5: a sum is a tagged record -- tag first, then one field per alternative.
    if B.Sum:isclassof(self) then return sum_fields(self.alternatives) end
    return nil
end
function B.Aggregate:record() return self.fields end
function B.Word:record() return self.fields end
function B.Word:copyable() return self.is_copy end

-- A canonical structural key, for interning and naming only. Two types with one key have the
-- same shape; it is not `same`, which also compares declared mutability. One owner for the
-- question, so entry interning and C struct naming cannot drift apart.
local function fields_key(fields)
    local parts={}
    for _,field in ipairs(fields) do parts[#parts+1]=(field.name or '')..':'..field.type:key() end
    return table.concat(parts,',')
end
function B.Type:key() return tostring(self) end
function B.Int:key() return 'int' end
function B.U8:key() return 'u8' end
function B.U32:key() return 'u32' end
function B.Float:key() return 'float' end
function B.Bool:key() return 'bool' end
function B.Unit:key() return 'unit' end
function B.Text:key() return 'text' end
function B.CString:key() return 'cstring' end
function B.CPointer:key() return 'cpointer' end
function B.Effect:key() return 'effect' end
function B.Named:key() return 'named('..self.name..')' end
function B.Address:key() return '&'..self.pointee:key() end
function B.Borrow:key() return (self.stable and '&~' or '~')..self.pointee:key() end
function B.Aggregate:key() return (self.name and ('N'..self.name) or (self.is_copy and 'A' or 'a'))..'('..fields_key(self.fields)..')' end
function B.Word:key()
    return 'W'..self.template..'/'..self.supplied..(self.is_copy and '+' or '-')..'('..fields_key(self.fields)..')'
end
function B.Field:key() return (self.name or '')..':'..self.type:key()..(self.mutable and '*' or '') end
function B.Arrow:key() return self.from:key()..'->'..self.to:key() end
function B.Do:key() return 'do('..self.result:key()..')' end
-- §11.5: a sum is a tagged record: the tag field, then one field per alternative.
function B.Sum:key()
    local parts={}
    for _,alternative in ipairs(self.alternatives) do parts[#parts+1]=alternative:key() end
    return (self.is_copy and 'S' or 's')..'('..table.concat(parts,'|')..')'
end
function B.Sum:owns() return false end

-- §8.5, §10.1: ownership is a property of the type, not of one consumer. An address owns what
-- it points at, a borrow never owns, and a record owns when any member does. These are facts
-- about a small immutable type graph, so the answers are remembered.
local owns_cache=setmetatable({},{__mode='k'})
local borrows_cache=setmetatable({},{__mode='k'})
local function owns(type_)
    local cached=owns_cache[type_]
    if cached~=nil then return cached end
    local result
    if B.Address:isclassof(type_) then result=owns(type_.pointee)
    elseif B.Named:isclassof(type_) then result=true
    elseif B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        result=false
        for _,field in ipairs(type_.fields) do if owns(field.type) then result=true; break end end
    else result=false end
    owns_cache[type_]=result
    return result
end
local function borrows(type_)
    local cached=borrows_cache[type_]
    if cached~=nil then return cached end
    local result
    if B.Borrow:isclassof(type_) then result=not type_.stable
    elseif B.Aggregate:isclassof(type_) or B.Word:isclassof(type_) then
        result=false
        for _,field in ipairs(type_.fields) do if borrows(field.type) then result=true; break end end
    else result=false end
    borrows_cache[type_]=result
    return result
end
function B.Type:owns() return owns(self) end
function B.Type:borrows() return borrows(self) end

end

