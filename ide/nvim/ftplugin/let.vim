" Filetype settings for Let.
"
" `_` is part of a NAME (§2.1), so it must be a keyword character for word
" motions and completion to agree with the language. Line comments use `//`
" (§2.2).
setlocal iskeyword+=_
setlocal commentstring=//\ %s
setlocal comments=://
setlocal suffixesadd=.let

" Highlighting is lexer-driven: ide/nvim/lua/letide.lua paints what the compiler's own
" scanner reports, so there is no Vim regex grammar to keep in step with let/lex.lua.
" Neovim-only: the highlighter is a Lua module over the compiler's scanner.
if has('nvim')
  lua require('letide').attach()
endif
