# Let IDE integration

Editor support for Let, built on the compiler rather than beside it. There is exactly one
tokenizer — `let/lex.lua` — and one parser — `let/parse.lua`. The highlighting and the
language server both consume them, so a token the compiler accepts is a token the editor
knows about, and the language cannot drift into two definitions.

| Consumer | Reuses |
| --- | --- |
| Neovim highlighting | `ide/tokens.lua` over `let/lex.lua`; comments from the scanner's own `//` rule |
| Diagnostics | `ide/tokens.lua` (tolerant scan) and `let/parse.lua` |
| Document symbols | `let/parse.lua` AST |
| Completion | `Lexer.spellings` and the names the scanner found |
| Semantic tokens | `ide/tokens.lua` (same classification as highlighting) |

## Layout

```
ide/
  letls.lua            language server entry point (stdio)
  text.lua             Source.Span <-> LSP position conversion
  tokens.lua           lexer-driven token/comment classification
  lsp/
    json.lua           minimal JSON
    rpc.lua            Content-Length framing
    diagnostics.lua    syntax diagnostics
    semantic.lua       semantic-token legend and encoding
    server.lua         lifecycle, document store, handlers
  nvim/                a Neovim runtime directory
    ftdetect/let.vim
    ftplugin/let.vim
    plugin/letide.lua
    lua/letide.lua     lexer-driven highlighter
```

## Neovim

The `ide/nvim` directory is a normal runtime directory.

### Without a plugin manager

Add it to `'runtimepath'` in `init.lua`, before `filetype` processing runs:

```lua
vim.opt.runtimepath:append(vim.fn.expand('~/dev/let-compiler/ide/nvim'))
```

### With lazy.nvim

```lua
return {
  {
    dir = vim.fn.expand('~/dev/let-compiler/ide/nvim'),
    name = 'letide',
    lazy = false,
    config = function()
      vim.lsp.config('letls', {
        cmd = { 'luajit', vim.fn.expand('~/dev/let-compiler/ide/letls.lua') },
        filetypes = { 'let' },
        root_markers = { '.git' },
      })
      vim.lsp.enable('letls')
    end,
  },
}
```

`plugin/letide.lua` registers the `let` filetype with `vim.filetype.add`, so detection
works even when the directory joins `'runtimepath'` after startup, and it attaches
highlighting even when `'filetype plugin'` is off.

### What you get

- **Highlighting** is painted from the compiler's scanner with buffer-local extmarks, so
  `let` inside a Text literal or a comment is never a keyword, and `Int` paints as a type
  because the compiler says it is one. It works with or without the server.
- **Diagnostics** are lexical, syntactic, and to the extent the resolver can check a name.
  Resolution collects every problem instead of stopping at the first, so a file with several
  unknown names reports all of them while navigation keeps working around them, and a problem in
  an imported file is published against that file. Construction diagnostics (constraints,
  ownership, arity) are the next layer and are not claimed yet.
- **Document symbols** are the file's top-level bindings and `extern` declarations.
- **Navigation** -- definition, references, hover, document highlight, and rename -- comes
  from the compiler's own resolver, so shadowing is distinguished and a rename edits exactly
  one declaration's occurrences. Identity is a declaration's `(file, offset)`, not a name.
- **Completion** offers the reserved spellings and the identifiers already in the buffer.
- **Semantic tokens** refine names through the same resolver: a stage is a parameter, a word
  is a function, and a binding keeps its mutability.

## Running the server

```sh
luajit ide/letls.lua
```

It speaks LSP over stdin/stdout. Neovim's client starts it as shown above.

## Tests

`test/ide.lua` covers JSON, coordinate conversion, tolerance, the symbol index, and three
full request/response sessions, and is part of `luajit test/all.lua`.

## Coordinates

The compiler counts 1-based lines and 1-based Unicode scalars within a line
(`let/lex.lua` §2). LSP counts 0-based lines and UTF-16 code units. `ide/text.lua` is the
one conversion; an astral character is two UTF-16 units but one scalar.

## Deliberately absent

- A Vim regex syntax file. The lexer already decides tokens; a second pattern language
  would be a second owner of the same rules.
- Incremental sync. The server advertises full sync (`change = 1`), which is honest for
  files this size and removes a class of edit bugs. It still applies ranged changes.
- Structural member resolution on records. `record.field` needs the record's shape from types;
  built-in namespaces (`c.puts`) and imported module members (`codec.JPEG`) navigate today.
- A workspace scan when no root reaches a declaration. Navigation, references, and rename cover
  the transitive closure of every open document's imports; a declaration used only by a file
  that is neither open nor imported by an open root is not found.
