-- C output vocabulary, not a second semantic/residual IR. No Let ownership or specialization.
return function(context)
    context:Define [[
module C {
    Type = Void | Bool | I64 | F64 | U64 | U8 | U32 | Size
         | Pointer(Type pointee) | Named(string name)
    Expr = Integer(number hi, number lo) | Float(number value) | Boolean(boolean value) | String(string value)
         | Name(string name) | Unary(string operator, Expr operand)
         | Binary(string operator, Expr left, Expr right)
         | Cast(Type type, Expr value) | Call(Expr callee, Expr* arguments)
         | Field(Expr base, string name) | Index(Expr base, Expr index)
         | Compound(Type type, Expr* fields)
    Parameter = (Type type, string name)
    Stmt = Declare(Type type, string name, Expr? initial)
         | Assign(Expr place, Expr value) | Evaluate(Expr value)
         | Block(Stmt* statements) | If(Expr condition, Stmt yes, Stmt? no)
         | While(Expr condition, Stmt body)
         | Label(string name) | Goto(string name) | Return(Expr? value)
    Declaration = Function(string name, boolean external, boolean exported, Type result, Parameter* parameters, Stmt? body)
                | Struct(string name, Parameter* fields)
                | Raw(string code)
                | Global(Type type, string name)
    Unit = (string* includes, Declaration* declarations)
}
    ]]
end

