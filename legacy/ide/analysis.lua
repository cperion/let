-- One analysis of one document, shared by every editor feature.
--
-- The ladder is lexical, then parse, then foreign declarations, then resolution. Each rung
-- runs only when the one below produced something, so a broken file reports the earliest
-- cause instead of a cascade. Nothing here re-implements the compiler: ide/tokens.lua drives
-- let/lex.lua, and let/parse.lua, let/extern.lua and let/resolve.lua do the rest.
--
-- A diagnostic is `{message, start, stop}` in the compiler's Source.Span coordinates, or
-- `{message, start, byte_length}` when a token's own spelling gives the extent. The LSP
-- layer converts those to ranges; this module stays in compiler coordinates.
--
-- Resolution still fails fast, so at most one resolution diagnostic is produced until the
-- resolver collects problems instead (step 4). The code below already accepts a list.

local V = require('let')
local SourceText = require('ide.text')
local tokens = require('ide.tokens')

local M = {}

-- A compiler failure is reported as `file:line:column: message`. The file may contain colons,
-- so the numbers are taken from the right.
local function failure(message)
    local line, column, text = tostring(message):match(':(%d+):(%d+): (.*)$')
    if not line then return {message = tostring(message)} end
    return {
        message = text,
        start = {line = tonumber(line), column = tonumber(column)},
        stop = {line = tonumber(line), column = tonumber(column) + 1},
    }
end

-- `V.Extern.merge` adds the hosts and namespaces a file declares to the options it is given.
-- A long-running server analyzes many files with one configured vocabulary, so the file gets
-- its own copy. Dotted externs extend a namespace's `members`, so those tables are copied too,
-- not just the outer dictionary.
local function file_options(base)
    local options = {}
    for key, value in pairs(base) do options[key] = value end
    local dictionary = {}
    for name, entry in pairs(base.dictionary or {}) do
        if entry.members then
            local members = {}
            for member, descriptor in pairs(entry.members) do members[member] = descriptor end
            local copy = {}
            for key, value in pairs(entry) do copy[key] = value end
            copy.members = members
            dictionary[name] = copy
        else
            dictionary[name] = entry
        end
    end
    options.dictionary = dictionary
    local hosts = {}
    for name, descriptor in pairs(base.hosts or {}) do hosts[name] = descriptor end
    options.hosts = hosts
    return options
end

function M.analyze(text, file, base_options)
    local analysis = {file = file, text = text, index = SourceText.new(text), diagnostics = {}}
    analysis.scan = tokens.scan(text, file)
    if #analysis.scan.errors > 0 then
        for _, problem in ipairs(analysis.scan.errors) do
            analysis.diagnostics[#analysis.diagnostics + 1] =
                {message = problem.message, start = problem.start, stop = problem.stop}
        end
        return analysis
    end
    local parsed, program = pcall(V.parse, text, file)
    if not parsed then
        -- A parse error points at a token, so that token's spelling gives the extent.
        local problem = failure(program)
        for _, token in ipairs(analysis.scan.tokens) do
            if problem.start and token.span.line == problem.start.line
                and token.span.column == problem.start.column then
                problem.byte_length = #token.spelling
                problem.stop = nil
                break
            end
        end
        analysis.diagnostics[#analysis.diagnostics + 1] = problem
        return analysis
    end
    analysis.program = program
    local options = file_options(base_options or {})
    -- Capture every file the resolver reads, so a span in an imported file converts with that
    -- file's own line map. Resolution parses the import itself; only the text passes through here.
    local files = {}
    analysis.files = files
    if options.resolve then
        local resolve = options.resolve
        options.resolve = function(path, from)
            local loaded = resolve(path, from)
            if loaded and loaded.file and files[loaded.file] == nil then files[loaded.file] = loaded.text end
            return loaded
        end
    end
    local merged, merge_problem = pcall(V.Extern.merge, program.file, options)
    if not merged then
        analysis.diagnostics[#analysis.diagnostics + 1] = failure(merge_problem)
        return analysis
    end
    local resolved, context, problems = pcall(program.resolve, program, options)
    if not resolved then
        analysis.diagnostics[#analysis.diagnostics + 1] = failure(context)
        return analysis
    end
    analysis.resolved = context
    analysis.options = options
    for _, problem in ipairs(problems or {}) do
        analysis.diagnostics[#analysis.diagnostics + 1] = {
            message = problem.message,
            start = problem.span,
            stop = {line = problem.span.line, column = problem.span.column + 1},
        }
    end
    return analysis
end

-- An analysis is a pure function of `(text, file, options)`. The cache keys on the file and
-- the document version the editor assigned, so a keystroke analyzes once and every handler
-- reads the same result.
function M.cache()
    local entries = {}
    local api = {}
    function api:get(file, version, text, options)
        local entry = entries[file]
        if entry and entry.version == version then return entry.analysis end
        local analysis = M.analyze(text, file, options)
        entries[file] = {version = version, analysis = analysis}
        return analysis
    end
    function api:invalidate(file) entries[file] = nil end
    function api:clear() entries = {} end
    return api
end

return M
