-- The module entry point: assemble the one ASDL context, expose the vocabularies, and hang the
-- phases off them.
--
-- Load order is dependency order, because `asdl.lua` resolves a cross-module type name at Define
-- time: a module may only reference one already defined. Semantic and Source reference nothing;
-- Dict references nothing; Chain references Semantic and Dict; Syntax references Source and
-- Semantic; Judge references Chain and Semantic; Belt references Semantic, Chain and Source;
-- Report references Source. A cycle would be a layer violation, so none exists.
local asdl = require('asdl')
local context = asdl.NewContext()

require('let.source')(context)
require('let.semantic')(context)
require('let.dict')(context)
require('let.chain')(context)
require('let.syntax')(context)
require('let.belt')(context)
require('let.judge')(context)
require('let.report')(context)
require('let.c')(context)

local V = {
    Source   = context.Source,
    Semantic = context.Semantic,
    Dict     = context.Dict,
    Chain    = context.Chain,
    Syntax   = context.Syntax,
    Judge    = context.Judge,
    Belt     = context.Belt,
    Report   = context.Report,
    C        = context.C,
    List     = asdl.List,
}

-- §6: `Compiler` owns "modules -- loaded units by name". Loading is reading and parsing, and it is
-- cached, because the same file imported twice is one unit and not two.
--
-- A file that is not there is a REJECT: the program named it, so the program is wrong -- as opposed
-- to a `Missing`, which would mean the compiler lacks a mechanism. A file that is there but does not
-- parse propagates its parse error the way the entry file's does, because a syntax error is a syntax
-- error wherever it is.
function V.load(compiler, path, span)
    local modules = compiler:get('modules')
    local loaded = modules[path]
    if loaded then return loaded end
    local file = io.open(path, 'rb')
    if not file then return nil, V.Report.reject(V.Report.MissingModule, span) end
    local text = file:read('*a')
    file:close()
    local program = V.parse(V.Lexer(text, path), path, text)
    modules[path] = program
    return program
end

V.Context = require('let.context')
V.Lexer   = require('let.lex')(V)
V.parse   = require('let.parse')(V)
V.Resolve  = require('let.resolve')(V)
V.Contract = require('let.contract')(V)
V.Lower    = require('let.lower')(V)
V.Op       = require('let.op')(V)
V.Known    = require('let.known')(V)
V.Emit     = require('let.emit')(V)
require('let.print')(V)

return V
