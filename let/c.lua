-- The C output vocabulary. Output only: no Let ownership, specialization, or binding-time domain.
--
-- `C.Expr.Comma` exists for exactly one reason: §3.6's trapping division has to be written
-- INLINE. There is no helper function, because a helper would be a second implementation of a
-- Let operator in C, and a trap is a property of the operation rather than of a runtime the
-- program links. `(abort(), 0)` is what lets a void expression stand where a value is wanted.
return function(context)
    context:Define [[
module C {
    Type = Void | Bool | I64 | F64 | F32 | U64 | U8 | U32 | Size | CString
         | Pointer(Type pointee) | Named(string name)
    Expr = Integer(number hi, number lo) | Float(number value) | Boolean(boolean value) | String(string value)
         | Name(string name) | Unary(string operator, Expr operand)
         | Binary(string operator, Expr left, Expr right)
         | Cast(Type type, Expr value) | Call(Expr callee, Expr* arguments)
         | Field(Expr base, string name) | Index(Expr base, Expr index)
         | Compound(Type type, Expr* fields)
         | Conditional(Expr condition, Expr yes, Expr no)
         | Comma(Expr* values)
         | Init(Type type, Designator* fields)
    Parameter = (Type type, string name)
    Designator = (string name, Expr value)
    Case = (Expr? value, Stmt* body)
    Stmt = Declare(Type type, string name, Expr? initial)
         | Assign(Expr place, Expr value) | Evaluate(Expr value)
         | Block(Stmt* statements) | If(Expr condition, Stmt yes, Stmt? no)
         | While(Expr condition, Stmt body)
         | Label(string name) | Goto(string name) | Return(Expr? value)
         | Switch(Expr value, Case* cases) | Break
    Declaration = Function(string name, boolean external, boolean exported, Type result, Parameter* parameters, Stmt? body)
                | Struct(string name, Parameter* fields)
                | Union(string name, Parameter* fields)
                | Raw(string code)
                | Global(Type type, string name)
    Unit = (string* includes, Declaration* declarations)
}
    ]]
end
