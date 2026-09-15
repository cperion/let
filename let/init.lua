-- Independent vocabulary entry point. This does not load any current compiler phase.
local asdl=require('asdl')
local context=asdl.NewContext()
require('let.ast')(context)
require('let.belt')(context)
require('let.c')(context)
local V={Source=context.Source,AST=context.AST,Belt=context.Belt,C=context.C,List=asdl.List}
require('let.numbering')(V)
require('let.build')(V)
require('let.verify')(V)
require('let.demand')(V)
V.Lexer=require('let.lex')(V)
V.parse=require('let.parse')(V)
require('let.binding')(V)
require('let.resolve')(V)
require('let.program')(V)
V.Known=require('let.known')(V)
V.scalar=require('let.scalar')
V.file_resolver=require('let.file')
require('let.print')(V)
require('let.emit')(V)
return V

