-- The Let language server.
--
-- It reuses the compiler rather than restating it: ide/tokens.lua drives let/lex.lua for
-- tokens and comments, and ide/analysis.lua runs the compiler's lexical, parse, foreign-
-- declaration and resolution ladder once per document version. ide/symbols.lua turns the
-- resolver's output into locations. Every handler reads that one analysis.
--
-- Navigation runs over the workspace: the union of every open document, each analyzed as a
-- root. An analysis already resolves its own imports into its context, so the union covers the
-- transitive closure, and the index keyed by `(file, offset)` merges the per-root contexts.
--
-- Sync is full-document (TextDocumentSyncKind.Full): each change replaces the text. That is
-- honest for files this size, and it removes a class of incremental-edit bugs. Incremental
-- ranges are still applied correctly if a client sends them.

local V = require('let')
local A = V.AST
local json = require('ide.lsp.json')
local rpc = require('ide.lsp.rpc')
local text = require('ide.text')
local analysis = require('ide.analysis')
local symbols = require('ide.symbols')
local semantic = require('ide.lsp.semantic')
local unpack = table.unpack or unpack

local M = {}
local Server = {}
Server.__index = Server

local MethodNotFound = -32601
local InternalError = -32603

-- SymbolKind and CompletionItemKind values from the specification.
local SymbolKind = {Function = 12, Variable = 13}
local CompletionKind = {Variable = 6, Keyword = 14}

-- `file:///path` to `/path`, undoing percent-encoding. A non-file URI is passed through,
-- so diagnostics and parsing still work for an in-memory document.
local function uri_to_file(uri)
    local path = uri:match('^file://(.*)$') or uri
    return (path:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end))
end

-- A filesystem path to a `file://` URI. The unreserved set plus `/` is left alone and
-- everything else is percent-encoded, so a space in a path survives the round trip.
local function file_to_uri(path)
    if path:match('^%a[%w+.-]*://') then return path end
    local encoded = path:gsub('[^%w%-%._~/]', function(character)
        return ('%%%02X'):format(character:byte())
    end)
    return 'file://' .. encoded
end

-- Imports name files with paths, and one file can be reached as `/tmp/a.let` or `/tmp/./a.let`.
-- Normalizing to one absolute spelling lets the open-buffer map be consulted by path.
local function normalize(path)
    if path:sub(1, 1) ~= '/' then path = (os.getenv('PWD') or '.') .. '/' .. path end
    local parts = {}
    for segment in path:gmatch('[^/]+') do
        if segment == '..' then
            if #parts > 0 then parts[#parts] = nil end
        elseif segment ~= '.' then
            parts[#parts + 1] = segment
        end
    end
    return '/' .. table.concat(parts, '/')
end

function M.new(input, output)
    local server = setmetatable({input = input, output = output, documents = {}, by_path = {},
        texts = {}, published = {}, generation = 0, workspace_cache = nil,
        analyses = analysis.cache()}, Server)
    -- The reader consults open buffers first, so a definition into an unsaved import is correct.
    server.options = V.Host.configure({}, {read = function(path) return server:read_file(path) end})
    return server
end

function Server:send(message) rpc.write(self.output, message) end

function Server:respond(id, result)
    self:send({jsonrpc = '2.0', id = id, result = result})
end

function Server:notify(method, params)
    self:send({jsonrpc = '2.0', method = method, params = params})
end

function Server:error(id, code, message)
    self:send({jsonrpc = '2.0', id = id, error = {code = code, message = message}})
end

function Server:initialize(id)
    self:respond(id, {
        capabilities = {
            positionEncoding = 'utf-16',
            textDocumentSync = {openClose = true, change = 1, save = {includeText = false}},
            documentSymbolProvider = true,
            definitionProvider = true,
            referencesProvider = true,
            hoverProvider = true,
            documentHighlightProvider = true,
            renameProvider = true,
            completionProvider = {triggerCharacters = {'.'}},
            semanticTokensProvider = {
                legend = {tokenTypes = semantic.types, tokenModifiers = semantic.modifiers},
                full = true,
            },
        },
        serverInfo = {name = 'letls', version = '0.2'},
    })
end

function Server:did_open(_, params)
    local document = params.textDocument
    local entry = {text = document.text or '', version = document.version}
    self.documents[document.uri] = entry
    self.by_path[normalize(uri_to_file(document.uri))] = entry
    self:changed()
    self:publish(document.uri)
end

local function apply_change(document, change)
    if not change.range or change.range == json.null then
        document.text = change.text
        return
    end
    local current = text.new(document.text)
    local start = current:offset_at(change.range.start)
    local stop = current:offset_at(change.range['end'])
    document.text = document.text:sub(1, start) .. change.text .. document.text:sub(stop + 1)
end

function Server:did_change(_, params)
    local document = self.documents[params.textDocument.uri]
    if not document then return end
    for _, change in ipairs(params.contentChanges or {}) do apply_change(document, change) end
    document.version = params.textDocument.version
    self:changed()
    self:publish(params.textDocument.uri)
end

function Server:did_save()
    -- The buffer text did not change, but an import on disk may have; drop the cached analyses.
    self:changed()
end

function Server:did_close(_, params)
    local uri = params.textDocument.uri
    local document = self.documents[uri]
    if document then self.by_path[normalize(uri_to_file(uri))] = nil end
    self.documents[uri] = nil
    -- Clear the root and every imported file this root reported diagnostics for.
    for file in pairs(self.published[uri] or {}) do
        self:notify('textDocument/publishDiagnostics', {uri = file_to_uri(file), diagnostics = {}})
    end
    self.published[uri] = nil
    self:notify('textDocument/publishDiagnostics', {uri = uri, diagnostics = {}})
    self:changed()
end

-- The cached analysis for a document's current version. Every handler reads this one result, so
-- a keystroke parses and resolves once rather than once per request.
function Server:analysis(uri)
    local document = self.documents[uri]
    if not document then return nil end
    return self.analyses:get(uri_to_file(uri), document.version, document.text, self.options)
end

-- Any edit invalidates the whole workspace. A file's meaning depends on the files it imports,
-- and tracking that edge set is work the per-file cache cannot do alone; for the handful of
-- files an editor has open, reanalyzing the union is cheap and cannot go stale.
function Server:changed()
    self.generation = self.generation + 1
    self.workspace_cache = nil
    self.texts = {}
    self.analyses:clear()
end

-- An import reads the open buffer first, then the file on disk. `V.file_resolver` calls this
-- for every candidate path, so an unsaved import is used before it is saved.
function Server:read_file(path)
    local document = self.by_path[normalize(path)]
    if document then return document.text end
    local file = io.open(path, 'rb')
    if not file then return nil end
    local source = file:read('*a'); file:close()
    return source
end

-- The union of every open root. Each analysis already resolved its own imports into its
-- context, so this covers the transitive closure; keyed by `(file, offset)`, the per-root
-- contexts merge and a declaration used from two roots is one symbol.
function Server:workspace()
    if self.workspace_cache and self.workspace_cache.generation == self.generation then
        return self.workspace_cache.index
    end
    local analyses = {}
    for uri, document in pairs(self.documents) do
        analyses[#analyses + 1] = self.analyses:get(uri_to_file(uri), document.version, document.text, self.options)
    end
    local index = symbols.build(unpack(analyses))
    self.workspace_cache = {generation = self.generation, index = index}
    return index
end

-- The ide/text for a file within an analysis: the root's own, or a memoized one for an import.
function Server:text_for(analyzed, file)
    if file == analyzed.file then return analyzed.index end
    local memo = self.texts[file]
    if memo then return memo end
    local source = (analyzed.files or {})[file]
    if not source then return nil end
    local built = text.new(source)
    self.texts[file] = built
    return built
end

-- Diagnostics are published per file: resolution reaches into an imported file, and a problem
-- there belongs to that file's URI. A root always republishes, even empty, and files it
-- previously reported are cleared.
function Server:publish(uri)
    local document = self.documents[uri]
    if not document then return end
    local analyzed = self:analysis(uri)
    local grouped = {[analyzed.file] = {}}
    for _, problem in ipairs(analyzed.diagnostics) do
        local file = (problem.start and problem.start.file) or analyzed.file
        local problems = grouped[file]
        if not problems then problems = {}; grouped[file] = problems end
        problems[#problems + 1] = problem
    end
    for file in pairs(self.published[uri] or {}) do
        if not grouped[file] then
            self:notify('textDocument/publishDiagnostics', {uri = file_to_uri(file), diagnostics = {}})
        end
    end
    local reported = {}
    for file, problems in pairs(grouped) do
        local current = self:text_for(analyzed, file)
        if current then
            reported[file] = true
            local list = {}
            for _, problem in ipairs(problems) do
                local range
                if problem.start then
                    if problem.byte_length then
                        range = current:token_range(problem.start, problem.byte_length)
                    elseif problem.stop then
                        range = current:range(problem.start, problem.stop)
                    else
                        range = {start = current:position(problem.start), ['end'] = current:position(problem.start)}
                    end
                else
                    range = {start = {line = 0, character = 0}, ['end'] = {line = 0, character = 0}}
                end
                list[#list + 1] = {range = range, severity = 1, source = 'let', message = problem.message}
            end
            self:notify('textDocument/publishDiagnostics', {uri = file_to_uri(file), diagnostics = list})
        end
    end
    self.published[uri] = reported
end

-- The file's top-level declarations. `extern` declarations become hosts rather than lexical
-- names, so they come from the AST; the rest are the module namespace the resolver built.
function Server:symbols(id, params)
    local uri = params.textDocument.uri
    local analyzed = self:analysis(uri)
    if not analyzed or not analyzed.resolved then return self:respond(id, {}) end
    local index = self:workspace()
    local file = analyzed.file
    local items = {}
    for _, definition in pairs(analyzed.resolved.module.names) do
        if definition.range and definition.range.start.file == file then
            items[#items + 1] = {name = definition.name, span = definition.node.span,
                name_range = definition.range, definition = definition}
        end
    end
    for _, item in ipairs(analyzed.program.file.items) do
        if A.Extern:isclassof(item) and item.name_range then
            items[#items + 1] = {name = item.name, span = item.span, name_range = item.name_range}
        end
    end
    table.sort(items, function(a, b)
        return analyzed.index:offset(a.span) < analyzed.index:offset(b.span)
    end)
    local out = {}
    for position, item in ipairs(items) do
        local start = analyzed.index:offset(item.span)
        local stop = position < #items and analyzed.index:offset(items[position + 1].span) or #analyzed.text
        local kind = SymbolKind.Function
        if item.definition then
            local record = index:declaration({file = file, offset = analyzed.index:offset(item.name_range.start)})
            local classified = index:classify(record)
            if classified and classified.type ~= 'function' then kind = SymbolKind.Variable end
        end
        out[#out + 1] = {
            name = item.name,
            kind = kind,
            range = {start = analyzed.index:position_at(start), ['end'] = analyzed.index:position_at(stop)},
            selectionRange = analyzed.index:range(item.name_range.start, item.name_range.stop),
        }
    end
    self:respond(id, out)
end

function Server:completion(id, params)
    local document = self.documents[params.textDocument.uri]
    if not document then return self:respond(id, {isIncomplete = false, items = {}}) end
    local seen, items = {}, {}
    local function add(label, kind)
        if not seen[label] then
            seen[label] = true
            items[#items + 1] = {label = label, kind = kind}
        end
    end
    for _, spelling in ipairs(V.Lexer.spellings) do add(spelling, CompletionKind.Keyword) end
    for _, token in ipairs(self:analysis(params.textDocument.uri).scan.tokens) do
        if token.kind == 'name' then add(token.spelling, CompletionKind.Variable) end
    end
    self:respond(id, {isIncomplete = false, items = items})
end

function Server:semantic_tokens(id, params)
    local uri = params.textDocument.uri
    local analyzed = self:analysis(uri)
    if not analyzed then return self:respond(id, {data = {}}) end
    self:respond(id, semantic.encode(analyzed.index, analyzed.file, analyzed.scan, self:workspace()))
end

-- The file, byte offset, analysis, and index a position names. Every navigation handler starts
-- here, so none of them repeats the conversion.
function Server:positioned(uri, position)
    local analyzed = self:analysis(uri)
    if not analyzed then return nil end
    return {analysis = analyzed, symbols = self:workspace(), file = analyzed.file,
        offset = analyzed.index:offset_at(position)}
end

function Server:definition(id, params)
    local located = self:positioned(params.textDocument.uri, params.position)
    if not located then return self:respond(id, json.null) end
    local target = located.symbols:definition(located.file, located.offset)
    if not target or not target.file then return self:respond(id, json.null) end
    local declaration = located.symbols:declaration(target)
    if declaration then
        self:respond(id, {uri = file_to_uri(declaration.file), range = declaration.range})
    else
        -- An import names a file, which has no declaration at its start; open the file itself.
        self:respond(id, {uri = file_to_uri(target.file),
            range = {start = {line = 0, character = 0}, ['end'] = {line = 0, character = 0}}})
    end
end

function Server:references(id, params)
    local located = self:positioned(params.textDocument.uri, params.position)
    if not located then return self:respond(id, {}) end
    local target = located.symbols:definition(located.file, located.offset)
    if not target then return self:respond(id, {}) end
    local include = params.context and params.context.includeDeclaration
    local out = {}
    for _, record in ipairs(located.symbols:occurrences(target)) do
        if include or record.role ~= 'declaration' then
            out[#out + 1] = {uri = file_to_uri(record.file), range = record.range}
        end
    end
    self:respond(id, out)
end

function Server:hover(id, params)
    local located = self:positioned(params.textDocument.uri, params.position)
    if not located then return self:respond(id, json.null) end
    local record = located.symbols:at(located.file, located.offset)
    local value = located.symbols:hover(record)
    if not value then return self:respond(id, json.null) end
    self:respond(id, {contents = {kind = 'markdown', value = value}, range = record.range})
end

-- DocumentHighlightKind: Text, Read, Write.
function Server:document_highlight(id, params)
    local located = self:positioned(params.textDocument.uri, params.position)
    if not located then return self:respond(id, {}) end
    local target = located.symbols:definition(located.file, located.offset)
    if not target then return self:respond(id, {}) end
    local out = {}
    for _, record in ipairs(located.symbols:occurrences(target)) do
        if record.file == located.file then
            local kind = 1
            if record.role == 'reference' then kind = record.access == 'read' and 2 or 3 end
            out[#out + 1] = {range = record.range, kind = kind}
        end
    end
    self:respond(id, out)
end

-- A rename edits every occurrence of the resolved declaration. Identity comes from the resolver,
-- so shadowed names are distinguished. A built-in or an import target has no declaration to
-- rename, so it is refused.
function Server:rename(id, params)
    local located = self:positioned(params.textDocument.uri, params.position)
    if not located then return self:respond(id, json.null) end
    local target = located.symbols:definition(located.file, located.offset)
    local declaration = target and located.symbols:declaration(target)
    if not declaration then return self:respond(id, json.null) end
    local changes = {}
    for _, record in ipairs(located.symbols:occurrences(target)) do
        local target_uri = file_to_uri(record.file)
        local edits = changes[target_uri]
        if not edits then edits = {}; changes[target_uri] = edits end
        edits[#edits + 1] = {range = record.range, newText = params.newName}
    end
    self:respond(id, {changes = changes})
end

Server.handlers = {
    ['initialize'] = Server.initialize,
    ['initialized'] = function() end,
    ['shutdown'] = function(self, id) self.shutdown = true; self:respond(id, json.null) end,
    ['exit'] = function(self) self.exit = true end,
    ['textDocument/didOpen'] = Server.did_open,
    ['textDocument/didChange'] = Server.did_change,
    ['textDocument/didClose'] = Server.did_close,
    ['textDocument/didSave'] = Server.did_save,
    ['textDocument/documentSymbol'] = Server.symbols,
    ['textDocument/definition'] = Server.definition,
    ['textDocument/references'] = Server.references,
    ['textDocument/hover'] = Server.hover,
    ['textDocument/documentHighlight'] = Server.document_highlight,
    ['textDocument/rename'] = Server.rename,
    ['textDocument/completion'] = Server.completion,
    ['textDocument/semanticTokens/full'] = Server.semantic_tokens,
    ['$/cancelRequest'] = function() end,
    ['$/setTrace'] = function() end,
}

function Server:dispatch(message)
    local handler = self.handlers[message.method]
    local id = message.id
    if not handler then
        if id then self:error(id, MethodNotFound, 'method not found: ' .. tostring(message.method)) end
        return
    end
    local ok, problem = pcall(handler, self, id, message.params)
    if ok then return end
    if id then
        self:error(id, InternalError, tostring(problem))
    else
        io.stderr:write('letls: ' .. tostring(problem) .. '\n')
    end
end

function Server:run()
    while not self.exit do
        local message = rpc.read(self.input)
        if not message then break end
        self:dispatch(message)
    end
    return self
end

function M.main(input, output)
    return M.new(input or io.stdin, output or io.stdout):run()
end

return M
