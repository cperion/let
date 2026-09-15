-- Independent vocabulary entry point. This does not load any current compiler phase.
local asdl=require('asdl')
local context=asdl.NewContext()
require('v2.ast')(context)
require('v2.belt')(context)
require('v2.c')(context)
local V={Source=context.Source,AST=context.AST,Belt=context.Belt,C=context.C,List=asdl.List}
require('v2.numbering')(V)
require('v2.build')(V)
require('v2.verify')(V)
require('v2.demand')(V)
V.Lexer=require('v2.lex')(V)
V.parse=require('v2.parse')(V)
require('v2.binding')(V)
require('v2.resolve')(V)
require('v2.program')(V)
V.Known=require('v2.known')(V)
V.scalar=require('v2.scalar')
require('v2.print')(V)
require('v2.emit')(V)
return V

