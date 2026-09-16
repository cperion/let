-- IDE integration: JSON, coordinates, tolerance, the symbol index, and server sessions.
--
-- The server is driven over file streams rather than a subprocess, so a failure points at the
-- handler instead of at process plumbing. The sessions are the sequence a Neovim client sends.
package.path = './?.lua;./?/init.lua;' .. package.path
local V = require('let')
local json = require('ide.lsp.json')
local text = require('ide.text')
local tokens = require('ide.tokens')
local analysis = require('ide.analysis')
local symbols = require('ide.symbols')
local server = require('ide.lsp.server')

local count = 0
local function check(value) assert(value); count = count + 1 end
local function equal(a, b, what)
    if a ~= b then error(('%s: expected %s, got %s'):format(what or 'value', tostring(b), tostring(a)), 0) end
    count = count + 1
end

-- JSON ----------------------------------------------------------------

equal(json.encode({1, 2, 3}), '[1,2,3]', 'array')
equal(json.encode({}), '[]', 'empty table is a list')
equal(json.encode(json.object()), '{}', 'empty object')
equal(json.encode({name = 'x'}), '{"name":"x"}', 'object')
equal(json.encode('a"b\\c\nd'), '"a\\"b\\\\c\\nd"', 'string escapes')
equal(json.encode(42), '42', 'integer')
equal(json.encode(-0.5), '-0.5', 'float')
equal(json.encode(true), 'true', 'boolean')
equal(json.encode(json.null), 'null', 'null')
check(json.decode('{"a":[1,2,{"b":null}],"c":"x"}').a[3].b == json.null)
equal(json.decode('"\\u00e9"'), 'é', 'bmp escape')
equal(json.decode('"\\ud83d\\ude00"'), '\240\159\152\128', 'surrogate pair')
equal(json.decode('-12.5e2'), -1250, 'number')
equal(json.decode('[]')[1], nil, 'empty array')
equal(getmetatable(json.decode('{}')), getmetatable(json.object()), 'decoded object keeps its mark')
equal(json.encode(json.decode('{"a":{}}')), '{"a":{}}', 'object round trip')

-- Coordinates ---------------------------------------------------------
--
-- Line 1 is `let x = "é😀" // c`. `é` is one UTF-16 unit and one scalar; `😀` is two
-- UTF-16 units and one scalar, which is what the conversion exists to handle. A trailing
-- newline is a second, empty line under the LSP line model, so the source omits it.
local source = 'let x = "é😀" // c\r\nlet y = 1'
local document = text.new(source)
equal(document:line_count(), 2, 'two lines')
equal(text.new('a\n'):line_count(), 2, 'trailing newline adds an empty line')
equal(document:utf16_column({line = 1, column = 13}), 13, 'utf16 column counts astral as two')
equal(document:byte_column({line = 1, column = 14}), 17, 'byte column counts bytes')
equal(document:utf16_column({line = 2, column = 5}), 4, 'plain line utf16 column')
equal(document:byte_column({line = 2, column = 5}), 4, 'plain line byte column')
for _, offset in ipairs{0, 9, 11, 15, 16, 17, 21} do
    equal(document:offset_at(document:position_at(offset)), offset, 'round trip at ' .. offset)
end
equal(document:position_at(16).character, 13, 'position past the astral pair')
local range = document:token_range({line = 2, column = 5}, 1)
equal(range.start.line, 1, 'token range line')
equal(range['end'].character, 5, 'token range end')

-- Tolerance and classification ----------------------------------------

local scan = tokens.scan('let x = 0xff + 1_000 // note\n"unterminated', 'probe.let')
equal(#scan.errors, 1, 'one lexical error')
equal(#scan.comments, 1, 'one comment')
check(scan.comments[1].span.line == 1 and scan.comments[1].span.column == 22)
local kinds = {}
for _, token in ipairs(scan.tokens) do kinds[token.spelling] = tokens.category(token) end
equal(kinds['let'], 'keyword', 'let is a keyword')
equal(kinds['0xff'], 'number', 'hex is a number')
equal(kinds['+'], 'operator', 'operator')
check(tokens.category({kind = 'name', spelling = 'Int'}) == 'type')
check(tokens.category({kind = 'name', spelling = 'x'}) == 'variable')

local clean = tokens.scan('let t = "do // let 12"\n// let\n', 'probe.let')
local spellings = {}
for _, token in ipairs(clean.tokens) do spellings[#spellings + 1] = token.spelling end
check(table.concat(spellings, ' ') == 'let t = "do // let 12"', 'string contains no inner tokens')
equal(#clean.comments, 1, 'comment after a string is still a comment')

-- Diagnostics ---------------------------------------------------------

equal(#analysis.analyze('let x = 1', 'ok.let', {}).diagnostics, 0, 'clean source')
local bad = analysis.analyze('let x = "open', 'bad.let', {}).diagnostics
equal(#bad, 1, 'unterminated string diagnostic')
equal(bad[1].message, 'unterminated Text literal', 'lexical message')
local parse = analysis.analyze('let x = = 1', 'parse.let', {}).diagnostics
equal(#parse, 1, 'parse diagnostic')
check(parse[1].byte_length ~= nil)

-- Resolution is tolerant: every unknown name is reported and the file still resolves, so
-- navigation keeps working around the error instead of the whole file going dark.
local tolerant = analysis.analyze('let a = 1\nlet b = missing + a\nlet c = also_missing',
    'tolerant.let', V.Host.configure({}))
equal(#tolerant.diagnostics, 2, 'both unknown names are reported')
equal(tolerant.diagnostics[1].message, 'unknown name missing', 'the compiler names the cause')
check(tolerant.resolved ~= nil, 'the rest of the file still resolves')
local tolerant_index = symbols.build(tolerant)
local tolerant_a = tolerant.resolved.module.names.a
check(tolerant_index:at('tolerant.let', tolerant.index:offset(tolerant_a.range.start)) ~= nil,
    'a known name still has a symbol')
local unresolved = tolerant_index:at('tolerant.let', tolerant.text:find('also_missing', 1, true) - 1)
check(tolerant_index:hover(unresolved):find('unresolved', 1, true) ~= nil, 'hover says unresolved')
equal(tolerant_index:definition('tolerant.let', tolerant.text:find('also_missing', 1, true) - 1), nil,
    'an unresolved name has no definition')

-- Symbol index ---------------------------------------------------------
--
-- Identity is the declaration's `(file, offset)`, so a use and its declaration meet even when
-- the resolver produced them from different roots. Nothing is matched by name.
local sample = table.concat({
    'let outer = 1',
    'let double = let n : Int do : Int return n + outer end',
    'let result = double(21)',
}, '\n')
local analyzed = analysis.analyze(sample, 'symbols.let', V.Host.configure({}))
check(analyzed.resolved ~= nil, 'the sample resolves')
local index = symbols.build(analyzed)
local sample_text = analyzed.index

local outer = analyzed.resolved.module.names.outer
local outer_offset = sample_text:offset(outer.range.start)
local declaration = index:at('symbols.let', outer_offset)
check(declaration.role == 'declaration' and declaration.name == 'outer', 'the declaration is at its name')

local outer_use
for _, use in ipairs(analyzed.resolved.uses) do
    if use.definition == outer then outer_use = use end
end
local use_offset = sample_text:offset(outer_use.node.span)
equal(index:at('symbols.let', use_offset).role, 'reference', 'a use is a reference')
local target = index:definition('symbols.let', use_offset)
check(target.offset == outer_offset, 'the use resolves to the declaration')
equal(#index:occurrences(target), 2, 'declaration and one use')
equal(index:classify(declaration).type, 'variable', 'a data binding is a variable')

local double = analyzed.resolved.module.names.double
equal(index:classify(index:at('symbols.let', sample_text:offset(double.range.start))).type, 'function',
    'a word is a function')
local stage = double.template.steps[1].stage
local stage_range = analyzed.resolved.bindings[stage].range
equal(index:classify(index:at('symbols.let', sample_text:offset(stage_range.start))).type, 'parameter',
    'a stage is a parameter')

-- A constraint is a dictionary entry: painted as a type, but with no source to jump to.
local constraint_offset = sample_text:offset(stage.constraint.name_range.start)
local constraint = index:at('symbols.let', constraint_offset)
check(constraint.entry ~= nil, 'a constraint use carries the built-in entry')
equal(index:classify(constraint).type, 'type', 'a constraint is a type')
equal(index:definition('symbols.let', constraint_offset), nil, 'a built-in has no declaration')

-- §11.2 a fixed-width integer is an atomic type word, so it paints as a type too.
local fixed=analysis.analyze('let small : U8 = u8(1)','fixed.let',V.Host.configure({}))
check(fixed.resolved ~= nil, 'the fixed-width sample resolves')
local fixed_index=symbols.build(fixed)
local u8_token=fixed_index:at('fixed.let',fixed.text:find('U8',1,true)-1)
equal(fixed_index:classify(u8_token).type,'type','a fixed-width type word is a type')

check(index:hover(declaration):find('let outer = 1', 1, true) ~= nil, 'hover shows the source line')
check(index:hover(index:at('symbols.let', use_offset)):find('let outer = 1', 1, true) ~= nil,
    'hover on a use shows the declaration')

-- `c.puts` is a namespace member, recorded apart from lexical uses.
local with_c = analysis.analyze('let main = do : Int c.puts(c.string("hi")) end', 'c.let', V.Host.configure({}))
check(with_c.resolved ~= nil, 'the c namespace resolves')
local c_index = symbols.build(with_c)
local puts = c_index:at('c.let', with_c.text:find('puts', 1, true) - 1)
check(puts.entry ~= nil, 'c.puts is a namespace member')
equal(c_index:classify(puts).type, 'function', 'a runtime word is a function')
check(c_index:hover(puts):find('puts', 1, true) ~= nil, 'hover names the member')

-- Server sessions ------------------------------------------------------

local function session(messages)
    local input_path, output_path = 'test/out/ide-request.bin', 'test/out/ide-response.bin'
    local file = assert(io.open(input_path, 'wb'))
    for _, message in ipairs(messages) do
        local body = json.encode(message)
        file:write(('Content-Length: %d\r\n\r\n%s'):format(#body, body))
    end
    file:close()
    local input = assert(io.open(input_path, 'rb'))
    local output = assert(io.open(output_path, 'wb'))
    server.new(input, output):run()
    input:close(); output:close()
    file = assert(io.open(output_path, 'rb'))
    local raw = file:read('*a'); file:close()
    local by_id, notifications, position = {}, {}, 1
    while position <= #raw do
        local _, stop = raw:find('\r\n\r\n', position, true)
        if not stop then break end
        local length = tonumber(raw:sub(position, stop):match('[Cc]ontent%-[Ll]ength:%s*(%d+)'))
        assert(length, 'missing Content-Length')
        local message = json.decode(raw:sub(stop + 1, stop + length))
        if message.id then by_id[message.id] = message else notifications[#notifications + 1] = message end
        position = stop + length + 1
    end
    return by_id, notifications
end

local uri = 'file:///tmp/session.let'
local broken = table.concat({
    'let greeting = "hi"',
    'let double = let n : Int do : Int return n + 1 end',
    'let unfinished = ',
}, '\n')
local by_id, notifications = session({
    {jsonrpc = '2.0', id = 1, method = 'initialize', params = json.object()},
    {jsonrpc = '2.0', method = 'initialized', params = json.object()},
    {jsonrpc = '2.0', method = 'textDocument/didOpen', params = {textDocument = {
        uri = uri, languageId = 'let', version = 1, text = broken}}},
    {jsonrpc = '2.0', id = 2, method = 'textDocument/documentSymbol', params = {textDocument = {uri = uri}}},
    {jsonrpc = '2.0', id = 3, method = 'textDocument/completion', params = {textDocument = {uri = uri}}},
    {jsonrpc = '2.0', id = 4, method = 'textDocument/semanticTokens/full', params = {textDocument = {uri = uri}}},
    {jsonrpc = '2.0', id = 5, method = 'textDocument/unknownMethod', params = json.object()},
    {jsonrpc = '2.0', id = 6, method = 'shutdown', params = json.null},
    {jsonrpc = '2.0', method = 'exit'},
})
equal(#by_id, 6, 'one response per request, none for notifications')
equal(by_id[1].result.serverInfo.name, 'letls', 'initialize result')
check(by_id[1].result.capabilities.documentSymbolProvider == true)
check(by_id[1].result.capabilities.definitionProvider == true)
equal(by_id[1].result.capabilities.textDocumentSync.change, 1, 'full sync advertised')
-- The file does not parse, so the symbol-backed features are withheld; completion and lexical
-- semantic tokens still work because they need only the scanner.
equal(#by_id[2].result, 0, 'symbols withheld while the file does not parse')
local labels = {}
for _, item in ipairs(by_id[3].result.items) do labels[item.label] = item.kind end
equal(labels['let'], 14, 'keyword completion')
equal(labels['greeting'], 6, 'identifier completion')
check(by_id[4].result.data[1] ~= nil, 'semantic tokens present')
equal(by_id[5].error.code, -32601, 'unknown method is MethodNotFound')
check(by_id[6].result == json.null, 'shutdown result is null')
local published
for _, message in ipairs(notifications) do
    if message.method == 'textDocument/publishDiagnostics' then published = message.params end
end
check(published ~= nil, 'diagnostics published')
check(#published.diagnostics >= 1, 'broken file reports a diagnostic')

-- A valid file answers navigation, because the resolver has something to say about it.
local good_uri = 'file:///tmp/good.let'
local good = table.concat({
    'let outer = 1',
    'let double = let n : Int do : Int return n + outer end',
    'let result = double(21)',
}, '\n')
local function position(line, character) return {line = line, character = character} end
local good_by_id = session({
    {jsonrpc = '2.0', id = 1, method = 'initialize', params = json.object()},
    {jsonrpc = '2.0', method = 'initialized', params = json.object()},
    {jsonrpc = '2.0', method = 'textDocument/didOpen', params = {textDocument = {
        uri = good_uri, languageId = 'let', version = 1, text = good}}},
    {jsonrpc = '2.0', id = 2, method = 'textDocument/documentSymbol', params = {textDocument = {uri = good_uri}}},
    {jsonrpc = '2.0', id = 3, method = 'textDocument/definition',
        params = {textDocument = {uri = good_uri}, position = position(2, 13)}},
    {jsonrpc = '2.0', id = 4, method = 'textDocument/references',
        params = {textDocument = {uri = good_uri}, position = position(1, 4), context = {includeDeclaration = true}}},
    {jsonrpc = '2.0', id = 5, method = 'textDocument/hover',
        params = {textDocument = {uri = good_uri}, position = position(1, 4)}},
    {jsonrpc = '2.0', id = 6, method = 'textDocument/documentHighlight',
        params = {textDocument = {uri = good_uri}, position = position(0, 4)}},
    {jsonrpc = '2.0', id = 7, method = 'textDocument/rename',
        params = {textDocument = {uri = good_uri}, position = position(1, 4), newName = 'twice'}},
    {jsonrpc = '2.0', id = 8, method = 'shutdown', params = json.null},
    {jsonrpc = '2.0', method = 'exit'},
})
local names = {}
for _, symbol in ipairs(good_by_id[2].result) do names[#names + 1] = symbol.name end
equal(table.concat(names, ','), 'outer,double,result', 'document symbols in source order')
equal(good_by_id[3].result.uri, good_uri, 'definition uri')
equal(good_by_id[3].result.range.start.line, 1, 'definition line')
equal(good_by_id[3].result.range.start.character, 4, 'definition character')
equal(#good_by_id[4].result, 2, 'references include the declaration and one use')
check(good_by_id[5].result.contents.value:find('let double', 1, true) ~= nil, 'hover shows the declaration')
equal(#good_by_id[6].result, 2, 'highlight covers the declaration and its use')
local edits = good_by_id[7].result.changes[good_uri]
equal(#edits, 2, 'rename edits the declaration and its use')
equal(edits[1].newText, 'twice', 'rename replacement text')

-- Cross-file workspace -------------------------------------------------

-- Two open files, one importing the other. Neither file exists on disk: the import is served
-- from the open buffer, which is the whole point of the reader.
local codec_uri, use_uri = 'file:///tmp/codec.let', 'file:///tmp/use.let'
local codec = 'let JPEG = let quality : Int do : Int return quality end'
local user = 'let codec = import "codec.let"\nlet q = codec.JPEG'
local cross = session({
    {jsonrpc = '2.0', id = 1, method = 'initialize', params = json.object()},
    {jsonrpc = '2.0', method = 'initialized', params = json.object()},
    {jsonrpc = '2.0', method = 'textDocument/didOpen', params = {textDocument = {
        uri = codec_uri, languageId = 'let', version = 1, text = codec}}},
    {jsonrpc = '2.0', method = 'textDocument/didOpen', params = {textDocument = {
        uri = use_uri, languageId = 'let', version = 1, text = user}}},
    {jsonrpc = '2.0', id = 2, method = 'textDocument/definition',
        params = {textDocument = {uri = use_uri}, position = position(1, 14)}},
    {jsonrpc = '2.0', id = 3, method = 'textDocument/definition',
        params = {textDocument = {uri = use_uri}, position = position(0, 19)}},
    {jsonrpc = '2.0', id = 4, method = 'textDocument/references',
        params = {textDocument = {uri = codec_uri}, position = position(0, 4),
            context = {includeDeclaration = true}}},
    {jsonrpc = '2.0', id = 5, method = 'textDocument/rename',
        params = {textDocument = {uri = codec_uri}, position = position(0, 4), newName = 'JPG'}},
    {jsonrpc = '2.0', id = 6, method = 'shutdown', params = json.null},
    {jsonrpc = '2.0', method = 'exit'},
})
equal(cross[2].result.uri, codec_uri, 'a projection into an import resolves across files')
equal(cross[2].result.range.start.line, 0, 'to the imported declaration')
equal(cross[2].result.range.start.character, 4, 'at the imported name')
equal(cross[3].result.uri, codec_uri, 'the import path itself resolves to the file')
equal(cross[3].result.range.start.line, 0, 'at the top of the imported file')
local cross_references = {}
for _, reference in ipairs(cross[4].result) do cross_references[reference.uri] = true end
check(cross_references[codec_uri] and cross_references[use_uri], 'references span both files')
equal(#cross[4].result, 2, 'the declaration and the cross-file use')
local cross_edits = cross[5].result.changes
check(cross_edits[codec_uri] ~= nil and cross_edits[use_uri] ~= nil, 'rename edits both files')
equal(#cross_edits[codec_uri], 1, 'the declaration')
equal(#cross_edits[use_uri], 1, 'the projection use')

print(('passed %d IDE checks'):format(count))
