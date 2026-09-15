-- Immutable semantic producers. Relative references never change during demand analysis.
return function(context)
    context:Define [[
module Belt {
    Destination = Persistent | Transient
    Access = CopyAccess | OwnAccess | ReadAccess | MutAccess
    Field = (string? name, Type type, boolean mutable)
    Type = Int | Float | Bool | Unit | Text | Effect | CString | CPointer
         | Named(string name) | Address(Type pointee)
         | Borrow(Type pointee, boolean stable)
         | Aggregate(Field* fields, boolean is_copy)
         | Word(number template, number supplied, Field* fields, boolean is_copy)
         | Callable(Signature signature)
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
    return B.Aggregate:isclassof(other) and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
function B.Word:same(other)
    return B.Word:isclassof(other) and self.template==other.template and self.supplied==other.supplied
        and self.is_copy==other.is_copy and fields_same(self.fields,other.fields)
end
function B.Type:copyable() return false end
function B.Int:copyable() return true end
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

-- Word records and aggregates are both ordered fields; only words carry a template.
function B.Type:record() return nil end
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
function B.Aggregate:key() return (self.is_copy and 'A' or 'a')..'('..fields_key(self.fields)..')' end
function B.Word:key()
    return 'W'..self.template..'/'..self.supplied..(self.is_copy and '+' or '-')..'('..fields_key(self.fields)..')'
end
function B.Field:key() return (self.name or '')..':'..self.type:key()..(self.mutable and '*' or '') end

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

