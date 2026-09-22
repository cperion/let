-- Verification of well-formed IR. Reaching a `bug` here means the builder produced something
-- inconsistent; source mistakes are rejected earlier with spans.
local S = require("wordlet.schema")
local IR = require("wordlet.ir")
local D = require("wordlet.diag")
local M = {}

local Ir = S.Ir

-- A statement list falls through unless its last statement definitely terminates.
local function falls(list)
    if #list == 0 then return true end
    local last = list[#list]
    local kind = last.kind
    if kind == "Return" or kind == "Trap" or kind == "Next" then return false end
    if kind == "Loop" then return false end
    if kind == "If" then return falls(last.yes) or falls(last.no) end
    return true
end
M.falls = falls

-- Definite initialisation: storage assigned on every reachable path to this point.
local function initialized(list, input)
    local set = {}
    for key in pairs(input or {}) do set[key] = true end
    for _, stmt in ipairs(list) do
        local kind = stmt.kind
        if kind == "Var" then
            set[stmt.storage.id] = true
        elseif kind == "If" then
            local yes = initialized(stmt.yes, set)
            local no = initialized(stmt.no, set)
            local both = {}
            for key in pairs(yes) do if no[key] then both[key] = true end end
            set = both
        elseif kind == "Loop" then
            -- Loop does not fall through, so it contributes nothing to the continuation.
        elseif kind == "Store" then
            -- A store to uninitialised storage is still a store; the storage itself is declared
            -- by Var or is an input, both of which are checked separately.
        end
    end
    return set
end

function M.function_(fn, definitions)
    -- `visible` is the set of values in scope at this point. Arm bodies get a copy so an
    -- arm-local definition cannot be referenced from the continuation.
    local function bind(visible, id)
        if visible[id] then D.bug("value-duplicate", "IR defines value " .. id .. " twice") end
        visible[id] = true
    end
    local function copy(set)
        local out = {}
        for key in pairs(set) do out[key] = true end
        return out
    end
    local function checkList(list, inputs, visible)
        local set = initialized(list, inputs)
        for _, stmt in ipairs(list) do
            local kind = stmt.kind
            if kind == "Let" then
                M.expr(stmt.expr, visible)
                bind(visible, stmt.value.id)
            elseif kind == "Read" then
                M.place(stmt.place, visible)
                if stmt.place.kind == "Local" and not set[stmt.place.storage.id] then
                    D.bug("ir-init", "Read of storage " .. stmt.place.storage.id .. " before initialisation")
                end
                bind(visible, stmt.value.id)
            elseif kind == "Var" then
                if stmt.initial then M.expr(stmt.initial, visible) end
            elseif kind == "Store" then
                M.place(stmt.place, visible)
                M.expr(stmt.value, visible)
            elseif kind == "If" then
                M.expr(stmt.test, visible)
                checkList(stmt.yes, set, copy(visible))
                checkList(stmt.no, set, copy(visible))
            elseif kind == "Loop" then
                checkList(stmt.body, set, copy(visible))
            elseif kind == "Call" or kind == "Indirect" then
                for _, result in ipairs(stmt.results) do bind(visible, result.id) end
                for _, arg in ipairs(stmt.arguments) do M.arg(arg, visible) end
                if kind == "Indirect" then M.expr(stmt.callable, visible) end
                local target = definitions[stmt.target]
                if kind == "Call" and not target then
                    D.bug("ir-target", "Call to unknown function " .. stmt.target)
                end
                if target and #stmt.results ~= #target.results then
                    D.bug("ir-arity", "Call result count does not match " .. stmt.target)
                end
            elseif kind == "Trap" then
                M.expr(stmt.failure, visible)
            elseif kind == "Return" then
                if #stmt.values ~= #fn.results then
                    D.bug("ir-return", "Function " .. fn.id .. " returns " .. #stmt.values
                        .. " values but declares " .. #fn.results)
                end
                for index, value in ipairs(stmt.values) do
                    if M.expr(value, visible) ~= fn.results[index] then
                        D.bug("ir-return", "Returned value type does not match the declared result")
                    end
                end
            elseif kind == "Next" then
                -- no operands
            else
                D.bug("ir-stmt", "Unknown statement variant " .. tostring(kind))
            end
        end
    end
    local visible = {}
    for _, param in ipairs(fn.params) do
        if param.kind ~= "ValueParam" and param.kind ~= "PlaceParam" and param.kind ~= "BundleParam" then
            D.bug("ir-param", "Unknown parameter variant " .. tostring(param.kind))
        end
        if param.kind == "ValueParam" then bind(visible, param.binding.id) end
    end
    checkList(fn.body, {}, visible)
    if falls(fn.body) then
        D.bug("ir-fallthrough", "Function " .. fn.id .. " can fall through without returning")
    end
    return true
end

function M.expr(expr, locals)
    local kind = expr.kind
    if kind == "Const" then
        if expr.type == S.U32 then
            if expr.literal.kind ~= "UInt" then D.bug("ir-literal", "U32 constant needs a UInt literal") end
        elseif expr.type == S.Bool then
            if expr.literal.kind ~= "Boolean" then D.bug("ir-literal", "Bool constant needs a Boolean literal") end
        else
            D.bug("ir-const", "Unsupported constant type " .. S.encode(expr.type))
        end
        return expr.type
    elseif kind == "Ref" then
        if not locals[expr.value.id] then
            D.bug("ir-scope", "Reference to value " .. expr.value.id .. " is not in scope")
        end
        return expr.type
    elseif kind == "Un" then
        local operand = M.expr(expr.operand, locals)
        local op = expr.op.kind
        if op == "Not" then
            if operand ~= S.Bool or expr.type ~= S.Bool then D.bug("ir-type", "Not requires Bool") end
        elseif op == "Neg" or op == "BitNot" then
            if operand ~= S.U32 or expr.type ~= S.U32 then D.bug("ir-type", "Unary " .. op .. " requires U32") end
        else
            D.bug("ir-op", "Unknown unary operation " .. tostring(op))
        end
        return expr.type
    elseif kind == "Bin" then
        local left = M.expr(expr.left, locals)
        local right = M.expr(expr.right, locals)
        local op = expr.op.kind
        local arithmetic = { Add = true, Sub = true, Mul = true, Div = true, Rem = true, Pow = true,
            BitAnd = true, BitOr = true, BitXor = true, Shl = true, Shr = true }
        if arithmetic[op] then
            if left ~= S.U32 or right ~= S.U32 or expr.type ~= S.U32 then
                D.bug("ir-type", "Arithmetic " .. op .. " requires U32")
            end
        elseif op == "Eq" or op == "Ne" then
            if left ~= right or expr.type ~= S.Bool then D.bug("ir-type", "Equality requires matching types") end
        elseif op == "Lt" or op == "Le" or op == "Gt" or op == "Ge" then
            if left ~= S.U32 or right ~= S.U32 or expr.type ~= S.Bool then
                D.bug("ir-type", "Ordering requires U32")
            end
        else
            D.bug("ir-op", "Unknown binary operation " .. tostring(op))
        end
        return expr.type
    end
    D.bug("ir-expr", "Unknown expression variant " .. tostring(kind))
end

function M.place(place, locals)
    local kind = place.kind
    if kind == "Local" then return true end
    if kind == "Captured" then return true end
    if kind == "Project" then return M.place(place.base, locals) end
    D.bug("ir-place", "Unknown place variant " .. tostring(kind))
end

function M.arg(arg, locals)
    if arg.kind == "ValueArg" then return M.expr(arg.value, locals) end
    if arg.kind == "BorrowArg" then return M.place(arg.place, locals) end
    if arg.kind == "BundleArg" then return true end
    D.bug("ir-arg", "Unknown argument variant " .. tostring(arg.kind))
end

function M.program(fnList)
    local definitions = {}
    for _, fn in ipairs(fnList) do
        if definitions[fn.id] then D.bug("ir-duplicate", "Duplicate function id " .. fn.id) end
        if fn.role.kind ~= "Body" and fn.role.kind ~= "Entry" then
            D.bug("ir-role", "Unknown function role")
        end
        if fn.hidden > #fn.inputs then D.bug("ir-hidden", "Hidden prefix exceeds the input vector") end
        if #fn.params ~= #fn.inputs then
            D.bug("ir-param", "Function " .. fn.id .. " must declare one parameter per input")
        end
        for index, param in ipairs(fn.params) do
            if param.input ~= index - 1 then
                D.bug("ir-param", "Function " .. fn.id .. " parameters must be ordered by input index")
            end
        end
        definitions[fn.id] = { results = fn.results, inputs = fn.inputs }
    end
    for _, fn in ipairs(fnList) do M.function_(fn, definitions) end
    return true
end

return M
