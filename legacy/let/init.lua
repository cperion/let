-- Module entry point: assembles the one ASDL context, loads the vocabulary and the compiler
-- phases, and returns the table `require('let')` hands to a caller.
local asdl=require('asdl')
local context=asdl.NewContext()
require('let.ast')(context)
require('let.belt')(context)
require('let.c')(context)
local V={Source=context.Source,AST=context.AST,Belt=context.Belt,C=context.C,List=asdl.List}
-- Vocabulary a construction phase needs, loaded before the phase that reads it.
V.Contract=require('let.contract')(V)
V.Packet=require('let.packet')(V)
V.Vocabulary=require('let.vocabulary')(V)
V.libc=require('let.libc')(V)
V.Extern=require('let.extern')(V)
require('let.numbering')(V)
require('let.build')(V)
require('let.verify')(V)
require('let.demand')(V)
V.Lexer=require('let.lex')(V)
V.parse=require('let.parse')(V)
require('let.binding')(V)
require('let.resolve')(V)
require('let.program')(V)
V.Op=require('let.op')(V)
V.Known=require('let.known')(V)
V.scalar=require('let.scalar')
V.file_resolver=require('let.file')
require('let.print')(V)
V.Host=require('let.host')(V)
require('let.emit')(V)
return V

