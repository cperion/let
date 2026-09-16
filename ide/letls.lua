-- The Let language server entry point.
--
--   luajit ide/letls.lua
--
-- The server speaks the Language Server Protocol over stdin/stdout. A Neovim configuration
-- starts it with `vim.lsp.config('letls', {cmd = {'luajit', '/path/to/ide/letls.lua'}})`.
--
-- This file only finds the repository, exactly as letc.lua does, so the module tree is
-- usable from any working directory.
local here = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])') or './'
package.path = here .. '../?.lua;' .. here .. '../?/init.lua;' .. package.path
require('ide.lsp.server').main()
