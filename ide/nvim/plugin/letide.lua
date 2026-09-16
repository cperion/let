-- Loaded from ide/nvim/plugin when this directory is on 'runtimepath' at startup.
--
-- A plugin manager may add this directory after 'filetype' processing has already run,
-- so the filetype is registered here instead of relying only on ftdetect/let.vim. The
-- autocmd attaches the lexer highlighter, which also covers 'filetype plugin' being off.

vim.filetype.add({ extension = { let = 'let' } })

vim.api.nvim_create_autocmd({ 'BufRead', 'BufNewFile' }, {
    pattern = '*.let',
    group = vim.api.nvim_create_augroup('letide_highlight', { clear = true }),
    callback = function(args)
        vim.bo[args.buf].filetype = 'let'
        require('letide').attach(args.buf)
    end,
})
