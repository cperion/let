-- Recursive-descent parser for syntax.md. Produces ast.asdl nodes; spans come from tokens.
local D = require("let.diag")
local A = require("let.ast")
local Lex = require("let.lex")
local M = {}

-- Token spans are plain tables; AST nodes need Ast.Span values.
local function S(span)
    if span == nil then return nil end
    return A.c.Span(span.file, span.line, span.start, span.finish)
end

local function mergeSpan(a, b)
    if not a then return b end
    if not b then return a end
    return A.c.Span(a.file, a.line, a.start, b.finish)
end
local function spanOf(value)
    return value and value.span or nil
end
local function listSpan(list)
    -- Not every node carries a span (bodies, export items), so take the envelope of those that do.
    local first, last
    for _, item in ipairs(list or {}) do
        if item.span then
            first = first or item.span
            last = item.span
        end
    end
    if first then return A.c.Span(first.file, first.line, first.start, last.finish) end
end
-- Lists carry a span so declarations and bodies can be reported precisely.
local function asList(items)
    local list = A.List(items)
    list.span = listSpan(items)
    return list
end
M.mergeSpan, M.spanOf = mergeSpan, spanOf

local Parser = {}
Parser.__index = Parser

local function setOf(names)
    local set = {}
    for _, name in ipairs(names) do set[name] = true end
    return set
end

local COMPARISONS = setOf({ "==", "!=", "<", "<=", ">", ">=" })
local LEVELS = {
    setOf({ "or" }), setOf({ "and" }), COMPARISONS,
    setOf({ "|" }), setOf({ "~" }), setOf({ "&" }),
    setOf({ "<<", ">>" }), setOf({ ".." }), setOf({ "+", "-" }), setOf({ "*", "/", "%" }),
}
local UNARY = setOf({ "-", "~", "not" })
local ASSIGN = setOf({ "=", "+=", "-=", "*=", "/=", "%=", "^=", "&=", "|=", "~=", "<<=", ">>=", "..=" })

function Parser:peek(offset) return self.tokens[self.pos + (offset or 0)] or self.tokens[#self.tokens] end
function Parser:next() local token = self.tokens[self.pos]; self.pos = self.pos + 1; return token end
function Parser:at(text)
    local token = self:peek()
    return (token.kind == "op" or token.kind == "keyword") and token.text == text
end
function Parser:take(text) if self:at(text) then return self:next() end end
function Parser:expect(text, what)
    if self:at(text) then return self:next() end
    D.reject("parse", string.format("Expected %s but found %q", what or ("'" .. text .. "'"), self:peek().text), self:peek().span)
end
-- Delimited lists accept a trailing comma. Returns true when another item follows.
function Parser:more(closing)
    if not self:take(",") then return false end
    if self:at(closing) then return false end
    return true
end

function Parser:expectName(what)
    local token = self:peek()
    if token.kind ~= "name" then
        D.reject("parse", string.format("Expected %s but found %q", what or "a name", token.text), token.span)
    end
    return self:next()
end

-- expressions ----------------------------------------------------------------

function Parser:expression()
    if self:at("if") then return self:ifExpression() end
    local left = self:binary(1)
    if self:at("::") then
        D.reject("parse", "A signature is written '(inputs): results'", self:peek().span)
    end
    if self:at(":") then
        D.reject("parse", "Signature inputs must be parenthesized: '(u32): u32'", self:peek().span)
    end
    return left
end

function Parser:binary(level)
    if level > #LEVELS then return self:unary() end
    local ops = LEVELS[level]
    local left = self:binary(level + 1)
    local seen = false
    while true do
        local token = self:peek()
        if (token.kind == "op" or token.kind == "keyword") and ops[token.text] then
            if seen and ops == COMPARISONS then
                D.reject("parse", "Comparison operators do not chain; group them explicitly", token.span)
            end
            self:next()
            local right = self:binary(token.text=='..' and level or level + 1)
            left = A.c.BinaryExpr(token.text, left, right, mergeSpan(left.span, right.span))
            seen = true
        else
            break
        end
    end
    return left
end

function Parser:unary()
    local token = self:peek()
    if (token.kind == "op" or token.kind == "keyword") and UNARY[token.text] then
        self:next()
        local operand = self:unary()
        return A.c.UnaryExpr(token.text, operand, mergeSpan(token.span, operand.span))
    end
    return self:power()
end

function Parser:power()
    local base = self:postfix()
    if self:at("^") then
        self:next()
        local exponent = self:unary()
        return A.c.BinaryExpr("^", base, exponent, mergeSpan(base.span, exponent.span))
    end
    return base
end

local function atomicLiteral(token)
    return token.kind=='number' or token.kind=='float' or token.kind=='byte' or token.kind=='string'
        or token.text=='true' or token.text=='false'
end

function Parser:postfix(literalOnly)
    local blockAtom=self:at('do')
    local expr = self:primary()
    if blockAtom then return expr end
    local lastSuffix
    while true do
        if self:at("(") then
            local args = self:argumentList()
            expr = A.c.Apply(expr, args, mergeSpan(expr.span, spanOf(args)))
            lastSuffix='arguments'
        elseif not literalOnly and self:at("{") then
            lastSuffix='keyed'
            -- A keyed definition -- `name: type`, or a method -- is a schema, and attaching it to a
            -- word supplies that word's keyed requirement: `oneof { circle: circle_shape }` is the
            -- keyed spelling of `oneof({ circle: circle_shape })`. `name = value` is a keyed supply,
            -- which constructs or specializes. The entry separator decides which, so the two forms
            -- never mix.
            local first, after = self:peek(1), self:peek(2)
            if first.kind == "name" and (after.text == ":" or after.text == "(") then
                local schema = self:schema()
                local list = asList({ schema })
                list.span = schema.span
                expr = A.c.Apply(expr, list, mergeSpan(expr.span, schema.span))
            else
                local fields = self:fieldSupplies()
                expr = A.c.RecordSupply(expr, fields, mergeSpan(expr.span, spanOf(fields)))
            end
        elseif self:at("[") then
            lastSuffix='index'
            self:next()
            local index = self:expression()
            local close = self:expect("]")
            expr = A.c.IndexExpr(expr, index, mergeSpan(expr.span, close.span))
        elseif self:at(".") then
            lastSuffix='field'
            self:next()
            local field = self:expectName("a field name")
            expr = A.c.FieldSelect(expr, A.name(field), mergeSpan(expr.span, field.span))
        elseif not literalOnly and self:at('do') then
            if lastSuffix=='keyed' then D.reject('parse','Group a keyed supply before applying its result to a block',self:peek().span) end
            local block=self:lambda()
            if lastSuffix=='arguments' then
                local args={} for _,arg in ipairs(expr.arguments) do args[#args+1]=arg end
                args[#args+1]=block
                return A.c.Apply(expr.callee,asList(args),mergeSpan(expr.span,block.span))
            end
            return A.c.Apply(expr,asList{block},mergeSpan(expr.span,block.span))
        elseif not literalOnly and atomicLiteral(self:peek()) then
            local argument=self:postfix(true)
            return A.c.Apply(expr,asList{argument},mergeSpan(expr.span,argument.span))
        else
            return expr
        end
    end
end

function Parser:supplyItem()
    local spread=self:take('...')
    local value=self:expression()
    return spread and A.c.Spread(value,mergeSpan(spread.span,value.span)) or value
end

function Parser:argumentList()
    local open = self:expect("(")
    local items = {}
    if not self:at(")") then
        repeat items[#items + 1] = self:supplyItem() until not self:more(")")
    end
    local close = self:expect(")")
    local list = asList(items)
    list.span = mergeSpan(open.span, close.span)
    return list
end

function Parser:fieldSupplies()
    local open = self:expect("{")
    local fields = {}
    if not self:at("}") then
        repeat
            local spread=self:take('...')
            if spread then
                local value=self:expression()
                fields[#fields+1]=A.c.FieldSpread(value,mergeSpan(spread.span,value.span))
            else
                local key = self:expectName("a field name")
                self:expect("=")
                local value = self:expression()
                fields[#fields + 1] = A.c.FieldSupply(A.name(key), value, mergeSpan(key.span, value.span))
            end
        until not self:more("}")
    end
    local close = self:expect("}")
    local list = asList(fields)
    list.span = mergeSpan(open.span, close.span)
    return list
end

-- `[e1, e2, ...]`: an array literal. Its length and element type are the elements unless an
-- annotation says otherwise, so an empty literal needs one.
function Parser:arrayLiteral()
    local open = self:expect("[")
    local items = {}
    if not self:at("]") then
        repeat items[#items + 1] = self:supplyItem() until not self:more("]")
    end
    local close = self:expect("]")
    return A.c.ArrayExpr(asList(items), mergeSpan(open.span, close.span))
end

function Parser:primary()
    local token = self:peek()
    if self:at('do') then return self:lambda() end
    if self:at('...') then D.reject('spread-context','Spread requires a supply list or name-binding declaration',token.span) end
    if token.kind == "number" then
        self:next()
        -- A literal that does not fit a word arrives as its two words.
        if type(token.value) == "table" then
            return A.c.U64Literal(token.value.high, token.value.low, S(token.span))
        end
        return A.c.U32Literal(token.value, S(token.span))
    elseif token.kind == "float" then
        self:next()
        return A.c.FloatLiteral(token.value, S(token.span))
    elseif token.kind == "byte" then
        self:next()
        -- A byte literal is a numeric literal written readably, so it adapts to the type of the
        -- expression it sits in exactly as `97` would.
        return A.c.U32Literal(token.value, S(token.span))
    elseif token.kind == "string" then
        self:next()
        return A.c.StringLiteral(token.value, S(token.span))
    elseif token.kind == "keyword" and (token.text == "true" or token.text == "false") then
        self:next()
        return A.c.BoolLiteral(token.text == "true", S(token.span))
    elseif token.kind == "op" and token.text == "(" then
        return self:parenOrSignature()
    elseif token.kind == "op" and token.text == "{" then
        local name,separator=self.tokens[self.pos+1],self.tokens[self.pos+2]
        if name and name.kind=="name" and separator and separator.text=="=" then return self:openSupply() end
        return self:schema()
    elseif token.kind == "op" and token.text == "[" then
        return self:arrayLiteral()
    elseif token.kind == "keyword" and token.text == "if" then
        return self:ifExpression()
    elseif token.kind == "name" then
        self:next()
        return A.c.Reference(A.name(token), S(token.span))
    end
    D.reject("parse", string.format("Expected an expression but found %q", token.text), token.span)
end

function Parser:openSupply()
    local fields=self:fieldSupplies()
    return A.c.OpenSupply(fields,fields.span)
end

-- `(e)` groups; `(a, b)` and `()` are signature input lists and require `:` with a result.
-- Requiring the parentheses is what keeps `:` after a name (an annotation) distinguishable.
function Parser:parenOrSignature()
    local open = self:expect("(")
    local items = {}
    if not self:at(")") then
        repeat items[#items + 1] = self:expression() until not self:more(")")
    end
    local close = self:expect(")")
    if #items == 1 and not self:at(":") then return A.c.Group(items[1],mergeSpan(open.span,close.span)) end
    self:expect(":", "':' and a result type after a parenthesized input list")
    local results = self:resultSpec()
    return A.c.SignatureExpr(asList(items), results, mergeSpan(open.span, spanOf(results) or close.span))
end

function Parser:schema()
    local open = self:expect("{")
    local members = {}
    if not self:at("}") then
        repeat
            local key = self:expectName("a schema member name")
            if self:at(":") then
                self:next()
                local annotation = self:expression()
                members[#members + 1] = A.c.FieldMember(A.name(key), annotation,mergeSpan(key.span,annotation.span))
            else
                self:expect("(", "'(' after a method name")
                local params = self:parameters(")", false, true)
                self:expect(")")
                local def = self:methodSuffix(A.name(key), params)
                members[#members + 1] = A.c.MethodMember(def,mergeSpan(key.span,spanOf(def) or key.span))
            end
        until not self:more("}")
    end
    local close = self:expect("}")
    return A.c.SchemaExpr(asList(members), mergeSpan(open.span, close.span))
end

function Parser:lambda()
    local open=self:expect('do')
    local params=asList{}
    local explicit=self:take('(')
    if explicit then params=self:parameters(')',false);self:expect(')') end
    local result
    if self:take(':') then result=self:resultSpec() end
    if self:take('=') then
        if not explicit then D.reject('parse','An expression lambda requires parenthesized parameters, including do()',open.span) end
        local value=self:expression()
        return A.c.Lambda(params,result,A.c.Expression(value),mergeSpan(open.span,value.span))
    end
    local statements=self:statementList('end')
    local close=self:expect('end')
    return A.c.Lambda(params,result,A.c.Block(asList(statements)),mergeSpan(open.span,close.span))
end

function Parser:ifExpression()
    local open = self:expect("if")
    local test = self:expression()
    self:expect("then")
    local yes = self:expression()
    self:expect("else")
    local no = self:expression()
    return A.c.Condition(test, yes, no, mergeSpan(open.span, no.span))
end

-- parameters -----------------------------------------------------------------

-- Groups of `Name (',' Name)*` optionally followed by `':' expr`. Annotations are
-- mandatory for foreign declarations and profile-checked later for definitions;
-- optional/contextual in lambdas. Every callable uses the same parenthesized syntax.
function Parser:parameters(closing, requireAnnotation, allowRest)
    local params = {}
    if self:at(closing) then return asList(params) end
    repeat
        local spread=self:take('...')
        if spread then
            if not allowRest then D.reject('rest-position','Rest is only supported in named ordered requirements',spread.span) end
            local name=self:expectName('a rest requirement name')
            params[#params+1]=A.c.RestParam(A.name(name),mergeSpan(spread.span,name.span))
            self:take(',')
            if not self:at(closing) then D.reject('rest-position','One unannotated rest requirement must be last',self:peek().span) end
            return asList(params)
        end
        local names = { self:expectName("a parameter name") }
        while self:at(",") and self:peek(1).kind == "name" do
            self:next()
            names[#names + 1] = self:expectName("a parameter name")
        end
        local annotation = nil
        if self:take(":") then
            annotation = self:expression()
        elseif requireAnnotation then
            D.reject("parse", "Every parameter of a named definition needs a type annotation",
                self:peek().span)
        end
        for _, name in ipairs(names) do
            params[#params + 1] = A.c.Param(A.name(name), annotation,
                mergeSpan(name.span, annotation and annotation.span or name.span))
        end
    until not self:more(closing)
    return asList(params)
end

-- declarations ---------------------------------------------------------------

-- `use util.helper`: a dotted module name, so no string literal and no new token is needed. The
-- last segment is the namespace the module's exports are reached through. `use` is not a keyword:
-- every definition begins with `let`, so a declaration starting with the name `use` can only be an
-- import, and `let use = ...` keeps working.
function Parser:useDecl()
    local start = self:expectName("a module name")
    local spread=self:take('...')~=nil
    local path = {}
    while true do
        local name = self:expectName("a module name")
        path[#path + 1] = name.text
        if not self:at(".") then break end
        self:next()
    end
    return A.c.UseDecl(table.concat(path, "."),spread,S(start.span))
end

function Parser:declaration()
    local first = self:peek()
    if first.kind == "keyword" and first.text == "extern" then
        -- A host function has no body to infer from, so its result is required rather than optional,
        -- and every requirement is annotated for the same reason.
        self:next()
        self:expect("let")
        local name = self:expectName("a foreign name")
        self:expect("(")
        local params = self:parameters(")", true)
        self:expect(")")
        self:expect(":", "a result declaration such as `: u32`, because a foreign word has no body")
        local result = self:resultSpec()
        local def = A.c.ForeignDef(A.name(name), params, result)
        return A.c.ForeignDecl(def, mergeSpan(first.span, spanOf(result) or name.span))
    end
    if first.kind == "name" and first.text == "use" then return self:useDecl() end
    local let = self:expect("let")
    if self:take('...') then
        local value=self:expression()
        return A.c.SpreadDecl(value,mergeSpan(let.span,value.span))
    end
    local name = self:expectName("a definition name")
    if self:at("{") then
        -- `let f { a: T, b: U }: R = body`: a word whose requirements are keyed. Each key is
        -- annotated, because a keyed requirement has no position to infer its type from.
        local keyed = self:keyedParameters()
        local def = self:definitionBody(A.name(name), asList({}), keyed)
        return A.c.WordDecl(def, mergeSpan(let.span, spanOf(def) or name.span))
    end
    if self:at("(") then
        self:next()
        local params = self:parameters(")", false, true)
        self:expect(")")
        local def = self:definitionBody(A.name(name), params)
        return A.c.WordDecl(def, mergeSpan(let.span, spanOf(def) or name.span))
    end
    local binders = {}
    local firstBinder = true
    repeat
        local binder = firstBinder and name or self:expectName("a binding name")
        firstBinder = false
        local annotation = nil
        if self:take(":") then annotation = self:expression() end
        binders[#binders + 1] = A.c.Binder(A.name(binder), annotation,
            mergeSpan(binder.span, annotation and annotation.span or binder.span))
    until not self:take(",")
    self:expect("=")
    local values = self:expressionList()
    local def = A.c.ValueDef(asList(binders), values)
    return A.c.ValueDecl(def, mergeSpan(let.span, spanOf(values) or name.span))
end

-- Shared tail of a named definition and a method: `: result? = body`, after the `)`.
function Parser:definitionBody(name, params, keyed)
    keyed = keyed or asList({})
    if #params > 0 and #keyed > 0 then
        -- Positional requirements and keyed requirements are different productions, so a
        -- definition that has both is a parser bug, not a source error.
        D.bug("worddef-requirements",
            "A word definition cannot take positional and keyed requirements at once")
    end
    local result = nil
    if self:at(":") then
        self:next()
        result = self:resultSpec()
    elseif self:at("::") then
        D.reject("parse", "A result is declared with ':'", self:peek().span)
    end
    self:expect("=")
    return A.c.WordDef(name, params, keyed, result, self:body())
end

-- `{ name: type, ... }`: a word's keyed requirements, in the form a schema literal uses. A word
-- definition writes them after its name; the same braces with `=` supply them at a call site.
function Parser:keyedParameters()
    local open = self:expect("{")
    local params = {}
    if not self:at("}") then
        repeat
            if self:at('...') then D.reject('rest-position','Keyed rest requirements are not supported',self:peek().span) end
            local name = self:expectName("a keyed requirement name")
            self:expect(":", "':' and a type after a keyed requirement name")
            local annotation = self:expression()
            params[#params + 1] = A.c.Param(A.name(name), annotation,mergeSpan(name.span,annotation.span))
        until not self:more("}")
    end
    local close = self:expect("}")
    local list = asList(params)
    list.span = mergeSpan(open.span, close.span)
    return list
end

Parser.methodSuffix = Parser.definitionBody

function Parser:resultSpec()
    if self:at("(") then
        local mark = self.pos
        self:next()
        local items = {}
        if not self:at(")") then
            repeat items[#items + 1] = self:expression() until not self:more(")")
        end
        self:expect(")")
        if self:at(":") then
            -- The parentheses were a signature's input list, so reparse the whole thing.
            self.pos = mark
            return A.c.Single(self:expression())
        end
        if #items == 1 then return A.c.Single(items[1]) end
        return A.c.Many(asList(items))
    end
    return A.c.Single(self:expression())
end

function Parser:expressionList()
    local values = { self:supplyItem() }
    while self:take(",") do values[#values + 1] = self:supplyItem() end
    return asList(values)
end

-- bodies and statements ------------------------------------------------------

function Parser:body()
    if not self:at("do") then return A.c.Expression(self:expression()) end
    local open = self:peek()
    self:next()
    if self:at('(') then D.reject('parse','A named definition executes its do body; group a lambda to return it',self:peek().span) end
    local statements = self:statementList("end")
    local close = self:expect("end")
    local list = asList(statements)
    list.span = #statements > 0 and mergeSpan(statements[1].span, close.span)
        or mergeSpan(open.span, close.span)
    return A.c.Block(list)
end

-- A statement list ends at any of `closers`. `return` terminates the list, so a statement after it
-- could never run and is rejected here rather than silently dropped (syntax.md §5). Because the list
-- is not required to end in `return`, a block may close with a statement conditional whose arms all
-- return; the structured completion verifier requires every path to return.
function Parser:statementList(...)
    local closers = { ... }
    local function closed()
        for _, text in ipairs(closers) do if self:at(text) then return true end end
        return false
    end
    local statements = {}
    while not closed() do
        local statement = self:statement()
        statements[#statements + 1] = statement
        while self:take(';') do end
        if statement.kind == "ReturnStmt" and not closed() then
            D.reject("unreachable", "A statement after `return` can never run", self:peek().span)
        end
    end
    return statements
end

function Parser:statement()
    local token = self:peek()
    if token.kind == "keyword" and token.text == "return" then
        return self:returnStatement()
    end
    if token.kind == "keyword" and token.text == "defer" then
        -- A deferred action is a call statement, so it needs the saturation a call statement has.
        self:next()
        local call = self:expression()
        if call.kind ~= "Apply" then
            D.reject("parse", "`defer` takes a call, such as `defer host_free(p)`", call.span)
        end
        return A.c.Defer(call, mergeSpan(token.span, call.span))
    end
    if token.kind == "keyword" and token.text == "let" then
        if self:peek(1).kind=="name" and self:peek(2).text=="." then
            local let=self:next();local receiver=self:expectName("an open-word receiver");self:expect(".")
            local name=self:expectName("a method name");self:expect("(")
            local params=self:parameters(")",false,true);self:expect(")")
            local def=self:definitionBody(A.name(name),params)
            return A.c.OpenMethodStmt(A.name(receiver),def,mergeSpan(let.span,spanOf(def) or name.span))
        end
        local decl = self:declaration()
        if decl.kind == "WordDecl" then return A.c.WordStmt(decl.def, decl.span) end
        if decl.kind == 'SpreadDecl' then return A.c.SpreadStmt(decl.value,decl.span) end
        return A.c.ValueStmt(decl.def, decl.span)
    elseif token.kind == "keyword" and token.text == "if" then
        return self:ifStatement()
    end
    local expr = self:expression()
    local operator = self:assignmentOperator()
    if operator then
        self:next()
        local value = self:expression()
        return A.c.StoreStmt(expr, operator, value, mergeSpan(expr.span, value.span))
    end
    if expr.kind ~= "Apply" then
        D.reject("parse", "Only calls, stores, `let`, `if` and `return` are statements", expr.span)
    end
    return A.c.CallStmt(expr, expr.span)
end

function Parser:assignmentOperator()
    local token = self:peek()
    if token.kind == "op" and ASSIGN[token.text] then return token.text end
end

function Parser:statementArm()
    -- `asList` already spans the items it is given, so an arm needs no span of its own here.
    return asList(self:statementList("else", "end"))
end

function Parser:ifStatement()
    local open = self:expect("if")
    local test = self:expression()
    self:expect("then")
    local yes = self:statementArm()
    local no = A.List({})
    if self:take("else") then no = self:statementArm() end
    local close = self:expect("end")
    return A.c.IfStmt(test, yes, no, mergeSpan(open.span, close.span))
end

-- A bare `return` denotes one unit result, not zero results (syntax.md §6). A `;` spells the same
-- thing explicitly, which is how a unit return before an expression statement is written
-- (syntax.md §1); that following statement is unreachable and is rejected by the statement list.
function Parser:returnStatement()
    local open = self:expect("return")
    local explicit = self:take(";")
    if explicit or self:at("end") or self:at("else") then
        return A.c.ReturnStmt(A.List({ A.c.UnitLiteral(S(open.span)) }), S(open.span))
    end
    local values = self:expressionList()
    return A.c.ReturnStmt(values, mergeSpan(open.span, spanOf(values) or open.span))
end

-- module export --------------------------------------------------------------

function Parser:export()
    local open = self:expect("return")
    self:expect("{")
    local types, functions, results = {}, {}, {}
    if not self:at("}") then
        repeat
            local section = self:expectName("an export section")
            self:expect("=")
            self:expect("{")
            local target = types
            if section.text == "functions" then target = functions
            elseif section.text == "results" then target = results
            elseif section.text ~= "types" then
                D.reject("parse", "Unknown export section: " .. section.text, section.span)
            end
            if not self:at("}") then
                repeat
                    if target == results then
                        self:expect("[")
                        local key = self:expression()
                        self:expect("]")
                        self:expect("=")
                        target[#target + 1] = A.c.ResultEntry(key, self:resultSpec())
                    else
                        local item = self:expectName("an exported name")
                        if self:take("=") then
                            target[#target + 1] = A.c.ExportAlias(A.name(item), self:expression())
                        else
                            target[#target + 1] = A.c.ExportName(A.name(item))
                        end
                    end
                until not self:more("}")
            end
            self:expect("}")
        until not self:more("}")
    end
    local close = self:expect("}")
    return A.c.Export(asList(types), asList(functions), asList(results)), mergeSpan(open.span, close.span)
end

-- A file that defines a top-level `main` needs no export configuration: `main` is the entry point,
-- which is what lets a host run a `.slet` string that was written as a program rather than a module.
function Parser:implicitMain(declarations)
    for _, decl in ipairs(declarations) do
        local name
        if decl.kind=='WordDecl' and decl.def.name.text=='main' then name=decl.def.name end
        if decl.kind=='ValueDecl' then
            for _,binder in ipairs(decl.def.binders) do if binder.name.text=='main' then name=binder.name end end
        end
        if name then return A.c.Export(asList{},asList{A.c.ExportName(name)},asList{}) end
    end
    return nil
end

function Parser:program()
    local declarations = {}
    while not self:at("return") do
        if self:peek().kind == "eof" then
            local export = self:implicitMain(declarations)
            if not export then
                D.reject("parse",
                    "A module must end with a `return { ... }` export, or define a top-level word `main`",
                    self:peek().span)
            end
            return A.c.Program(asList(declarations), export)
        end
        declarations[#declarations + 1] = self:declaration()
        while self:take(';') do end
    end
    local export = self:export()
    if self:peek().kind ~= "eof" then
        D.reject("parse", "Unexpected input after the module export", self:peek().span)
    end
    return A.c.Program(asList(declarations), export)
end

function M.program(tokens) return setmetatable({ tokens = tokens, pos = 1 }, Parser):program() end
function M.source(text, name) return M.program(Lex.tokens(text, name)) end

return M
