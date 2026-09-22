-- Lowering a closed artifact to C11. Header and source are two views of the same layouts.
local S = require("wordlet.schema")
local D = require("wordlet.diag")
local M = {}

local Ir = S.Ir

-- Same injective escape as the ABI layer: every non-alphanumeric byte becomes _XX.
function M.escape(name)
    return (name:gsub("[^%w]", function(c) return string.format("_%02X", c:byte()) end))
end

local function fieldName(name) return "f_" .. M.escape(name) end

local BINARY_OP = {
    Add = "+", Sub = "-", Mul = "*", Div = "/", Rem = "%",
    BitAnd = "&", BitOr = "|", BitXor = "^", Shl = "<<", Shr = ">>",
    Eq = "==", Ne = "!=", Lt = "<", Le = "<=", Gt = ">", Ge = ">=",
}
local UNARY_OP = { Neg = "-", BitNot = "~" }

local Emitter = {}
Emitter.__index = Emitter
local function newEmitter(layouts, signature)
    return setmetatable({ layouts = layouts, lines = {}, indent = 1,
        placeParams = (signature and signature.placeParams) or {} }, Emitter)
end
function Emitter:line(text) self.lines[#self.lines + 1] = string.rep("    ", self.indent) .. text end
function Emitter:raw(text) self.lines[#self.lines + 1] = text end
function Emitter:value(id) return "v" .. id end
function Emitter:storage(id) return "s" .. id end

function Emitter:expr(expr)
    local kind = expr.kind
    if kind == "Const" then
        if expr.literal.kind == "UInt" then return "UINT32_C(" .. expr.literal.value .. ")" end
        if expr.literal.kind == "Boolean" then return expr.literal.value and "true" or "false" end
        D.bug("c-literal", "Unknown literal")
    elseif kind == "Ref" then
        return self:value(expr.value.id)
    elseif kind == "Un" then
        local op = expr.op.kind
        if op == "Not" then return "(!(" .. self:expr(expr.operand) .. "))" end
        return "((uint32_t)(" .. UNARY_OP[op] .. "(" .. self:expr(expr.operand) .. ")))"
    elseif kind == "Bin" then
        local op, left, right = expr.op.kind, self:expr(expr.left), self:expr(expr.right)
        if op == "Pow" then return "wordlet_pow(" .. left .. ", " .. right .. ")" end
        local cOp = BINARY_OP[op]
        if not cOp then D.bug("c-op", "No C operator for " .. tostring(op)) end
        if op == "Add" or op == "Sub" or op == "Mul" then
            return "(uint32_t)((uint64_t)(" .. left .. ") " .. cOp .. " (uint64_t)(" .. right .. "))"
        end
        if op == "Shl" or op == "Shr" then
            return "(uint32_t)((" .. right .. ") >= UINT32_C(32) ? UINT32_C(0) : ((uint64_t)("
                .. left .. ") " .. cOp .. " (" .. right .. ")))"
        end
        if op == "BitAnd" or op == "BitOr" or op == "BitXor" then
            return "(uint32_t)((" .. left .. ") " .. cOp .. " (" .. right .. "))"
        end
        return "((" .. left .. ") " .. cOp .. " (" .. right .. "))"
    elseif kind == "Make" then
        -- An Owned callable is represented by its environment record.
        local record = S.environmentOf(expr.type)
        local layout = self.layouts.recordLayout(record)
        local fields = {}
        for index, field in ipairs(record.fields) do
            fields[#fields + 1] = "." .. layout.fields[index].name .. " = " .. self:expr(expr.fields[index])
        end
        return "(" .. layout.name .. "){" .. table.concat(fields, ", ") .. "}"
    elseif kind == "Get" then
        return "(" .. self:expr(expr.aggregate) .. ")." .. fieldName(expr.field.name)
    end
    D.todo("c-expr", "No C lowering for expression " .. tostring(kind))
end

function Emitter:placeC(place)
    if place.kind == "Local" then
        local name = self:storage(place.storage.id)
        -- A place parameter is already a pointer; a Var is the storage itself.
        return self.placeParams[place.storage.id] and ("(*" .. name .. ")") or name
    end
    if place.kind == "Project" then
        return self:placeC(place.base) .. "." .. fieldName(place.field.name)
    end
    D.todo("c-place", "No C lowering for place " .. tostring(place.kind))
end

function Emitter:borrow(place)
    return "&(" .. self:placeC(place) .. ")"
end

function Emitter:declare(ty, name, initial)
    local cType = self.layouts:cType(ty)
    if initial then
        self:line(cType .. " " .. name .. " = " .. initial .. ";")
    else
        local zero = (ty == S.U32 and "UINT32_C(0)") or (ty == S.Bool and "false") or "0"
        self:line(cType .. " " .. name .. " = " .. zero .. ";")
    end
end

function Emitter:statements(list)
    for _, stmt in ipairs(list) do
        local kind = stmt.kind
        if kind == "Let" then
            self:declare(stmt.type, self:value(stmt.value.id), self:expr(stmt.expr))
        elseif kind == "Var" then
            self:declare(stmt.type, self:storage(stmt.storage.id), stmt.initial and self:expr(stmt.initial))
        elseif kind == "Read" then
            self:declare(stmt.type, self:value(stmt.value.id), self:placeC(stmt.place))
        elseif kind == "Store" then
            self:line(self:placeC(stmt.place) .. " = " .. self:expr(stmt.value) .. ";")
        elseif kind == "If" then
            self:line("if (" .. self:expr(stmt.test) .. ") {")
            self.indent = self.indent + 1
            self:statements(stmt.yes)
            self.indent = self.indent - 1
            if #stmt.no > 0 then
                self:line("} else {")
                self.indent = self.indent + 1
                self:statements(stmt.no)
                self.indent = self.indent - 1
            end
            self:line("}")
        elseif kind == "Loop" then
            self:line("for (;;) {")
            self.indent = self.indent + 1
            self:statements(stmt.body)
            self.indent = self.indent - 1
            self:line("}")
        elseif kind == "Next" then
            self:line("continue;")
        elseif kind == "Trap" then
            self:line("if (" .. self:expr(stmt.failure) .. ") abort();")
        elseif kind == "Call" then
            self:call(stmt)
        elseif kind == "Return" then
            self:line(self:returnText(stmt.values))
        else
            D.todo("c-stmt", "No C lowering for statement " .. tostring(kind))
        end
    end
end

function Emitter:call(stmt)
    local signature = self.layouts.signatures[stmt.target]
    if not signature then D.bug("c-target", "Call to unknown function " .. stmt.target) end
    local args = {}
    for _, arg in ipairs(stmt.arguments) do
        if arg.kind == "ValueArg" then
            args[#args + 1] = self:expr(arg.value)
        elseif arg.kind == "BorrowArg" then
            args[#args + 1] = self:borrow(arg.place)
        else
            D.todo("c-arg", "No C lowering for argument " .. tostring(arg.kind))
        end
    end
    local call = signature.name .. "(" .. table.concat(args, ", ") .. ")"
    -- Call results are Ir.Value ids; their types are the target's declared results, positionally.
    local types = signature.fn.results
    if #stmt.results == 0 then
        self:line(call .. ";")
    elseif #stmt.results == 1 then
        self:declare(types[1], self:value(stmt.results[1].id), call)
        self:line("(void)" .. self:value(stmt.results[1].id) .. ";")
    else
        local layout = self.layouts.resultLayout(types)
        if not layout.name then D.bug("c-results", "Multiple results need a tuple layout") end
        -- The call produces one aggregate temporary; each logical result becomes its own value.
        local packed = "t" .. stmt.results[1].id
        self:line(layout.name .. " " .. packed .. " = " .. call .. ";")
        for index = 1, #stmt.results do
            self:declare(types[index], self:value(stmt.results[index].id), packed .. ".f_" .. index)
        end
        -- A discarded call still must not leave an unused local behind under -Werror.
        self:line("(void)" .. packed .. ";")
        for index = 1, #stmt.results do self:line("(void)" .. self:value(stmt.results[index].id) .. ";") end
    end
end

function Emitter:returnText(values)
    if #values == 0 then return "return;" end
    if #values == 1 then return "return " .. self:expr(values[1]) .. ";" end
    local types = {}
    for index, value in ipairs(values) do types[index] = value.type end
    local layout = self.layouts.resultLayout(types)
    local fields = {}
    for index, value in ipairs(values) do
        fields[#fields + 1] = ".f_" .. index .. " = " .. self:expr(value)
    end
    return "return (" .. layout.name .. "){" .. table.concat(fields, ", ") .. "};"
end

-- Declarations ---------------------------------------------------------------------------------

function M.typeDeclarations(layouts)
    local lines = {}
    local function aggregate(name, fields)
        local body, any = {}, false
        for _, field in ipairs(fields) do
            if field.type ~= S.Unit then
                body[#body + 1] = "    " .. layouts:cType(field.type) .. " " .. field.name .. ";"
                any = true
            end
        end
        if not any then body[#body + 1] = "    unsigned char wordlet_pad;" end
        lines[#lines + 1] = "typedef struct " .. name .. " {\n" .. table.concat(body, "\n") .. "\n} " .. name .. ";"
    end
    for _, tuple in ipairs(layouts.tupleOrder) do aggregate(tuple.name, tuple.fields) end
    for _, record in ipairs(layouts.recordOrder) do aggregate(record.name, record.fields) end
    for _, exported in ipairs(layouts.typeExports or {}) do
        lines[#lines + 1] = "typedef " .. exported.layout.name .. " " .. exported.name .. ";"
    end
    return lines
end

function M.signatureText(layouts, signature)
    local parameters = {}
    if #signature.params == 0 then parameters[1] = "void" end
    for _, param in ipairs(signature.params) do
        local pointer = param.pointer and " *" or " "
        parameters[#parameters + 1] = layouts:cType(param.type) .. pointer .. param.name
    end
    local returns = "void"
    if signature.results.kind == "scalar" then returns = layouts:cType(signature.results.type) end
    if signature.results.kind == "tuple" then returns = signature.results.name end
    return returns .. " " .. signature.name .. "(" .. table.concat(parameters, ", ") .. ")"
end

local function aliasOf(signature, name)
    local copy = {}
    for key, value in pairs(signature) do copy[key] = value end
    copy.name = name
    return copy
end

function M.prototypes(layouts)
    local lines = {}
    for _, instance in ipairs(layouts.order) do
        local signature = layouts.signatures[instance.target]
        lines[#lines + 1] = M.signatureText(layouts, signature) .. ";"
        for _, alias in ipairs(signature.aliases) do
            lines[#lines + 1] = M.signatureText(layouts, aliasOf(signature, alias)) .. ";"
        end
    end
    return lines
end

function M.prelude()
    return {
        "uint32_t wordlet_pow(uint32_t base, uint32_t exponent) {",
        "    uint32_t result = UINT32_C(1);",
        "    while (exponent > UINT32_C(0)) {",
        "        if ((exponent & UINT32_C(1)) != UINT32_C(0)) {",
        "            result = (uint32_t)((uint64_t)result * (uint64_t)base);",
        "        }",
        "        exponent = exponent >> 1;",
        "        if (exponent > UINT32_C(0)) {",
        "            base = (uint32_t)((uint64_t)base * (uint64_t)base);",
        "        }",
        "    }",
        "    return result;",
        "}",
    }
end

function M.bodies(layouts)
    local lines = {}
    for _, instance in ipairs(layouts.order) do
        local signature = layouts.signatures[instance.target]
        local emitter = newEmitter(layouts, signature)
        emitter:raw(M.signatureText(layouts, signature) .. " {")
        emitter:statements(instance.fn.body)
        emitter:raw("}")
        lines[#lines + 1] = table.concat(emitter.lines, "\n")
        for _, alias in ipairs(signature.aliases) do
            local args = {}
            for index, param in ipairs(signature.params) do args[index] = param.name end
            local call = signature.name .. "(" .. table.concat(args, ", ") .. ")"
            local body = signature.results.kind == "void" and (call .. ";") or ("return " .. call .. ";")
            lines[#lines + 1] = M.signatureText(layouts, aliasOf(signature, alias)) .. " {\n    " .. body .. "\n}"
        end
    end
    return lines
end

local INCLUDES = { "#include <stdint.h>", "#include <stdbool.h>", "#include <stdlib.h>" }

function M.unit(layouts)
    local lines = {}
    for _, line in ipairs(INCLUDES) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, line in ipairs(M.typeDeclarations(layouts)) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, line in ipairs(M.prototypes(layouts)) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, line in ipairs(M.prelude()) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, body in ipairs(M.bodies(layouts)) do
        lines[#lines + 1] = body
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

function M.source(layouts, headerName)
    local lines = {}
    if headerName then lines[#lines + 1] = '#include "' .. headerName .. '"' end
    for _, line in ipairs(INCLUDES) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, line in ipairs(M.typeDeclarations(layouts)) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, line in ipairs(M.prototypes(layouts)) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, line in ipairs(M.prelude()) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    for _, body in ipairs(M.bodies(layouts)) do
        lines[#lines + 1] = body
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

function M.header(layouts, name)
    local guard = "WORDLET_" .. M.escape(name or "unit"):upper() .. "_H"
    local lines = { "#ifndef " .. guard, "#define " .. guard, "", "#include <stdint.h>", "#include <stdbool.h>", "" }
    for _, line in ipairs(M.typeDeclarations(layouts)) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "#ifdef __cplusplus"
    lines[#lines + 1] = 'extern "C" {'
    lines[#lines + 1] = "#endif"
    lines[#lines + 1] = ""
    local any = false
    for _, instance in ipairs(layouts.order) do
        local signature = layouts.signatures[instance.target]
        if signature.name:sub(1, 8) == "wordlet_" then
            any = true
            lines[#lines + 1] = M.signatureText(layouts, signature) .. ";"
            for _, alias in ipairs(signature.aliases) do
                lines[#lines + 1] = M.signatureText(layouts, aliasOf(signature, alias)) .. ";"
            end
        end
    end
    if not any then lines[#lines + 1] = "/* no exported functions */" end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "#ifdef __cplusplus"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = "#endif"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "#endif"
    return table.concat(lines, "\n")
end

return M
