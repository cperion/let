-- The editor's symbol table, built from the compiler's resolution.
--
-- Identity is a declaration's location `(file, byte offset)`, never a definition object:
-- resolving a workspace one root at a time produces a separate Context per root, so the same
-- declaration in an imported file is two different objects. Its location is identical in every
-- context, so that is the stable key.
--
-- Nothing here resolves names or walks scopes. `let/resolve.lua` already did both. This module
-- turns its node-keyed maps into offset-keyed ranges, and answers what an editor asks: what is
-- here, where is it declared, where is it used, and how should it be painted.

local V = require('let')
local A = V.AST
local SourceText = require('ide.text')

local M = {}
local Symbols = {}
Symbols.__index = Symbols

-- A two-part key: paths may contain `@`, so the separator is a byte a path cannot.
local function key(file, offset) return file .. '\0' .. tostring(offset) end

-- A reference arrives as a compiler span plus the written name. A NAME is ASCII (§2.1), so its
-- byte length is its length in scalars.
local function name_range(span, name)
    return {start = span, stop = {file = span.file, line = span.line, column = span.column + #name}}
end

function M.build(...)
    local self = setmetatable({texts = {}, declarations = {}, references = {}, by_file = {}, by_target = {}}, Symbols)
    for _, analysis in ipairs({...}) do self:add(analysis) end
    self:resolve_targets()
    for _, records in pairs(self.by_file) do
        table.sort(records, function(a, b)
            if a.start_offset ~= b.start_offset then return a.start_offset < b.start_offset end
            return a.stop_offset > b.stop_offset
        end)
    end
    return self
end

function Symbols:text(file, source)
    local existing = self.texts[file]
    if existing then return existing end
    local built = SourceText.new(source)
    self.texts[file] = built
    return built
end

function Symbols:insert(record)
    local records = self.by_file[record.file]
    if not records then records = {}; self.by_file[record.file] = records end
    records[#records + 1] = record
end

-- A declaration is a binding or a stage. A dictionary or namespace definition has no source,
-- so it is not a declaration here; a use of one carries the entry descriptor instead.
function Symbols:declare(definition)
    local range = definition.range
    local text = self.texts[range.start.file]
    if not text then return end
    local record = {
        role = 'declaration',
        name = definition.name,
        definition = definition,
        file = range.start.file,
        start_offset = text:offset(range.start),
        stop_offset = text:offset(range.stop),
        range = text:range(range.start, range.stop),
    }
    self.declarations[key(record.file, record.start_offset)] = record
    self:insert(record)
end

function Symbols:reference(definition, range, name, access)
    local text = self.texts[range.start.file]
    if not text then return end
    local record = {
        role = 'reference',
        name = name,
        file = range.start.file,
        start_offset = text:offset(range.start),
        stop_offset = text:offset(range.stop),
        range = text:range(range.start, range.stop),
        access = access,
    }
    if definition.range then
        local target_text = self.texts[definition.range.start.file]
        record.target = {file = definition.range.start.file, offset = target_text:offset(definition.range.start)}
    elseif definition.kind == 'unknown' then
        record.unresolved = true
    else
        record.entry = definition.node
        record.entry_name = definition.name
        record.entry_kind = definition.kind
    end
    self.references[#self.references + 1] = record
    self:insert(record)
end

-- A namespace projection: `c.puts` (a built-in entry) or `codec.JPEG` (a declaration in an
-- imported file). The record is the member name in this file; the target is elsewhere.
function Symbols:projection(project, member)
    if not project.member_range then return end
    local text = self.texts[project.member_range.start.file]
    if not text then return end
    local record = {
        role = 'reference',
        name = project.name,
        file = project.member_range.start.file,
        start_offset = text:offset(project.member_range.start),
        stop_offset = text:offset(project.member_range.stop),
        range = text:range(project.member_range.start, project.member_range.stop),
    }
    if member.range and member.kind then
        -- An imported namespace member is a real declaration in the imported file.
        local target_text = self.texts[member.range.start.file]
        record.target = {file = member.range.start.file, offset = target_text:offset(member.range.start)}
    else
        record.entry = member
        record.entry_name = project.name
        record.entry_kind = 'member'
    end
    self.references[#self.references + 1] = record
    self:insert(record)
end

function Symbols:add(analysis)
    self:text(analysis.file, analysis.text)
    for file, source in pairs(analysis.files or {}) do self:text(file, source) end
    local resolved = analysis.resolved
    if not resolved then return end
    for _, definition in ipairs(resolved.definitions) do
        if definition.range then self:declare(definition) end
    end
    -- A use node is always the Name the resolver saw; a type-word Ref records its definition
    -- in `resolved.type_refs`, keyed by the Ref node, with the Ref's own range.
    local seen = {}
    for _, use in ipairs(resolved.uses) do
        local node = use.node
        if A.Name:isclassof(node) and not seen[node] then
            seen[node] = true
            self:reference(use.definition, name_range(node.span, node.name), node.name, use.access)
        end
    end
    for constraint, definition in pairs(resolved.type_refs) do
        if constraint.name_range then
            self:reference(definition, constraint.name_range, constraint.name)
        end
    end
    -- `c.puts`: a namespace projection, not a lexical use, so the resolver records it apart.
    for project, member in pairs(resolved.namespace_members) do self:projection(project, member) end
    -- `codec.JPEG` where `codec` is bound to an import: the same shape, across files.
    for project, member in pairs(resolved.module_projections or {}) do self:projection(project, member) end
    -- An import site: definition opens the imported file rather than naming a declaration here.
    for node, imported in pairs(resolved.imports) do
        local argument = node.argument
        if argument and argument.span and imported.span and imported.span.file then
            local text = self.texts[argument.span.file]
            if text then
                local length = #argument.value + 2
                local record = {
                    role = 'reference',
                    name = 'import',
                    file = argument.span.file,
                    start_offset = text:offset(argument.span),
                    stop_offset = text:offset(argument.span) + length,
                    range = text:token_range(argument.span, length),
                    target = {file = imported.span.file, offset = 0},
                    import = true,
                }
                self.references[#self.references + 1] = record
                self:insert(record)
            end
        end
    end
end

function Symbols:resolve_targets()
    for _, reference in ipairs(self.references) do
        if reference.target then
            local k = key(reference.target.file, reference.target.offset)
            reference.declaration = self.declarations[k]
            local list = self.by_target[k]
            if not list then list = {}; self.by_target[k] = list end
            list[#list + 1] = reference
        end
    end
end

-- The innermost record covering an offset: the last range that starts at or before it and still
-- contains it. Records are sorted by start, so the scan can stop once it passes the offset.
function Symbols:at(file, offset)
    local records = self.by_file[file]
    if not records then return nil end
    local found
    for _, record in ipairs(records) do
        if record.start_offset > offset then break end
        if offset < record.stop_offset then
            if not found or record.start_offset >= found.start_offset then found = record end
        end
    end
    return found
end

function Symbols:declaration(target)
    return target and self.declarations[key(target.file, target.offset)]
end

-- The declaration a location names, or nil when it names a built-in with no source.
function Symbols:definition(file, offset)
    local record = self:at(file, offset)
    if not record then return nil end
    if record.role == 'declaration' then return {file = record.file, offset = record.start_offset} end
    return record.target
end

-- The declaration plus every use that targets it, in source order. This is what references,
-- rename, and document highlight all read.
function Symbols:occurrences(target)
    local k = key(target.file, target.offset)
    local out = {}
    local declaration = self.declarations[k]
    if declaration then out[#out + 1] = declaration end
    for _, reference in ipairs(self.by_target[k] or {}) do out[#out + 1] = reference end
    if #out > 1 then
        table.sort(out, function(a, b)
            if a.file ~= b.file then return a.file < b.file end
            return a.start_offset < b.start_offset
        end)
    end
    return out
end

-- The definition behind a record: its own for a declaration, its target's for a use.
function Symbols:definition_of(record)
    if not record then return nil end
    if record.role == 'declaration' then return record.definition end
    return (record.declaration or {}).definition
end

local function entry_summary(name, entry)
    -- §11: a built-in type word carries `type`; a resource carries its descriptor; a runtime
    -- host carries its phase, purity and C symbol.
    if entry.members then return 'namespace `' .. name .. '`' end
    if entry.type then return 'built-in type `' .. name .. '`' end
    if entry.resource then return 'resource type `' .. name .. '`' end
    local parts = {}
    if entry.phase then parts[#parts + 1] = entry.phase end
    if entry.purity then parts[#parts + 1] = entry.purity end
    if entry.symbol then parts[#parts + 1] = 'calls `' .. entry.symbol .. '`' end
    local suffix = #parts > 0 and (' (' .. table.concat(parts, ', ') .. ')') or ''
    return 'built-in `' .. name .. '`' .. suffix
end

-- Hover text for the thing at a record. A declaration shows its source line; a built-in shows
-- what the compiler's vocabulary says about it. No type is claimed unless the source states one.
function Symbols:hover(record)
    if not record then return nil end
    if record.unresolved then return 'unresolved name `' .. record.name .. '`' end
    if record.entry then return entry_summary(record.entry_name or record.name, record.entry) end
    local declaration = record.role == 'declaration' and record or record.declaration
    if not declaration then return nil end
    local definition = declaration.definition
    local text = self.texts[declaration.file]
    local line = text:line_text(definition.node.span.line):gsub('^%s+', ''):gsub('%s+$', '')
    local kind = definition.kind == 'stage' and 'stage of this word' or 'binding'
    return '```let\n' .. line .. '\n```\n\n' .. kind .. '.'
end

-- Display classification for semantic tokens. The lexical answer is the base; this refines a
-- name once the resolver has said what it is.
function Symbols:classify(record)
    local definition = self:definition_of(record)
    local modifiers = {}
    if record and record.role == 'declaration' then modifiers[#modifiers + 1] = 'declaration' end
    if record and record.entry then
        local entry = record.entry
        local type_ = 'variable'
        if entry.members then type_ = 'namespace'
        elseif entry.type or entry.resource then type_ = 'type'
        elseif entry.phase == 'constraint' then type_ = 'type'
        elseif entry.phase == 'runtime' or entry.phase == 'construction' then type_ = 'function'
        end
        return {type = type_, modifiers = modifiers}
    end
    if not definition then return nil end
    local type_ = 'variable'
    if definition.kind == 'stage' then
        type_ = 'parameter'
        if definition.node.capability == A.Read then modifiers[#modifiers + 1] = 'readonly' end
    elseif definition.kind == 'binding' then
        local template = definition.template
        if template and (#template.steps > 0 or A.Body:isclassof(template.source.terminal)) then
            type_ = 'function'
        end
        if definition.node.mutable == false then modifiers[#modifiers + 1] = 'readonly' end
    elseif definition.kind == 'dictionary' then
        type_ = 'type'
    elseif definition.kind == 'namespace' then
        type_ = 'namespace'
    end
    return {type = type_, modifiers = modifiers}
end

return M
