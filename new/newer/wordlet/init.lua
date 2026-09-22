-- Wordlet facade: compile a module to a verified C artifact.
local S = require("wordlet.schema")
local D = require("wordlet.diag")
local Lex = require("wordlet.lex")
local Parse = require("wordlet.parse")
local Eval = require("wordlet.eval")
local Check = require("wordlet.check")
local C = require("wordlet.cabi")
local Lower = require("wordlet.lower")
local V = require("wordlet.value")

local M = {}

-- options: name, limits, session
function M.compile(options)
    local options = options or {}
    if type(options.source) ~= "string" then
        D.reject("compile-input", "compile needs a `source` string")
    end
    local name = options.name or "<source>"
    local tokens = Lex.tokens(options.source, name)
    local program = Parse.program(tokens)
    local session = options.session or Eval.session(options)
    if options.session and options.session.instances then
        -- A fresh session per compilation is the supported entry point.
        D.bug("compile-session", "Reuse of an existing session is not supported yet")
    end
    local compilation = session:compile(program)
    local functions = {}
    for _, instance in ipairs(session.order) do functions[#functions + 1] = instance.fn end
    Check.program(functions)
    local layouts = C.close(compilation)
    return M.artifact(layouts, compilation)
end

function M.compile_file(path, options)
    local file, err = io.open(path, "rb")
    if not file then D.reject("compile-input", "Cannot read " .. tostring(path) .. ": " .. tostring(err)) end
    local source = file:read("*a")
    file:close()
    local merged = {}
    for key, value in pairs(options or {}) do merged[key] = value end
    merged.source, merged.name = source, path
    return M.compile(merged)
end

function M.artifact(layouts, compilation)
    local artifact = { layouts = layouts, compilation = compilation }
    function artifact:unit() return Lower.unit(self.layouts) end
    function artifact:source(headerName) return Lower.source(self.layouts, headerName) end
    function artifact:header(name) return Lower.header(self.layouts, name) end
    function artifact:exports()
        local names = {}
        for _, entry in ipairs(self.compilation.functions) do names[#names + 1] = entry.name end
        return names
    end
    return artifact
end

-- Reference interpretation: apply an exported word to concrete arguments and return plain Lua
-- values. This is the differential counterpart of the generated C.
function M.interpret(options)
    local options = options or {}
    local program = Parse.source(options.source, options.name or "<source>")
    local session = Eval.session(options)
    session:load(program)
    if type(options.entry) ~= "string" then D.reject("interpret-input", "interpret needs an `entry` name") end
    local word = session:exportedValue(program, options.entry, session.top)
    if V.tag(word) ~= "word" then
        D.reject("function-required", "Entry " .. options.entry .. " is not a word")
    end
    local args = {}
    for index, value in ipairs(options.args or {}) do
        if type(value) == "number" then args[index] = V.u32(value)
        elseif type(value) == "boolean" then args[index] = V.bool(value)
        else D.reject("interpret-arg", "Unsupported argument " .. tostring(value)) end
    end
    local span = word.span
    local result = session:apply(session:context("normalize", session.top, span), word, args, span)
    if V.tag(result) == "word" then
        D.reject("arity", "Entry " .. options.entry .. " needs more arguments to be saturated")
    end
    local out = {}
    for _, value in ipairs(session:expand(result)) do
        if value.ty == S.U32 then out[#out + 1] = value.n
        elseif value.ty == S.Bool then out[#out + 1] = value.b
        elseif value.ty == S.Unit then out[#out + 1] = "unit"
        else D.todo("interpret-result", "Cannot interpret result of type " .. S.encode(value.ty)) end
    end
    return out
end

M.session = Eval.session
M.diagnostic = D.format

return M
