" Recognize Let sources by extension. The compiler's own convention is `.let`
" (see let/file.lua, which assumes that suffix when a host does not override it).
autocmd BufRead,BufNewFile *.let setfiletype let
