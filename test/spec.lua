-- The specification against the code, for the one thing that is mechanical: the ASDL.
--
-- DESIGN.md is the authority (§0). §S63 found seven defects in it in a single reading -- including a
-- sum split in half by an edit that only ADDED -- and nothing in the suite read the document, so
-- nothing could notice. The compiler does not read the specification either, which makes a drifted
-- specification invisible to every other test here.
--
-- What is compared is the ASDL itself, declaration by declaration: every `Name = …` entry of a
-- `module` block in DESIGN.md against the same entry in `let/<name>.lua`'s `context:Define [[ … ]]`.
-- Whitespace and `--` comments are removed, because the document's copy is allowed prose and to line
-- its `= ` up, while `asdl.lua` has no comment syntax at all.
--
-- Declaration order is NOT compared, and that is deliberate: the document groups its entries for a
-- reader, the code orders them by dependency, and neither is wrong. Everything else is compared --
-- the set of names, and the token sequence of each -- so a constructor that moved from one sum to
-- another (the §S63 defect), a field only one side has, a renamed type, and a declaration only one
-- side has are all caught.
--
-- **The comparison is verified by making it fail.** A check that cannot fail is worse than no check:
-- this file's first version compared the code with itself and passed. The first real run then found
-- §11.3 calling a type `Convert` where the code calls it `Conversion`, and §11.6 disagreeing with
-- `judge.lua` about a whole declaration.
--
-- `luajit test/spec.lua --list` prints every disagreement instead of stopping at the first, which is
-- how the size of a drift is measured before it is fixed.
package.path = './?.lua;./?/init.lua;' .. package.path

local listing = arg[1] == '--list'
local checks = 0
local function check(v, m) assert(v, m); checks = checks + 1 end

local function split_lines(text)
    local out = {}
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do out[#out + 1] = line end
    return out
end

local function read(path)
    local file = assert(io.open(path), path .. ' must be readable from the repository root')
    local text = file:read('*a')
    file:close()
    return text
end

local function lines_of(text)
    local out = {}
    for line in (text .. '\n'):gmatch('([^\n]*)\n') do out[#out + 1] = line end
    return out
end

-- The entries of a module body: one bucket per `Name = …` line, each canonicalized to a token string.
-- A continuation line is anything that does not open a new entry -- a leading `|`, or a field list,
-- or the `attributes` clause.
local function entries(text)
    local out, name = {}, nil
    for _, raw in ipairs(lines_of(text)) do
        local line = raw:gsub('%-%-.*$', '')
        if not line:match('%S') then goto continue end
        -- The module's own braces are not entries, and a trailing `}` must not land on the last one.
        if line:match('^%s*[{}]%s*$') or line:match('^%s*module%s') then goto continue end
        local declared = line:match('^%s*([A-Z][A-Za-z]*)%s*[=%(%[]')
        if declared then
            name = declared
            assert(out[name] == nil, ('two entries named %s'):format(name))
            out[name] = {}
        end
        if name then
            for token in line:gmatch('%S+') do out[name][#out[name] + 1] = token end
        end
        ::continue::
    end
    local joined = {}
    for key, tokens in pairs(out) do joined[key] = table.concat(tokens, ' ') end
    return joined
end

-- §11's layering paragraph: the vocabularies, in the order `let/init.lua` defines them, with the file
-- each one lives in. `C` is absent because §11.9 says it is built in Lua rather than declared.
local vocabularies = {
    { 'Source', 'source' }, { 'Semantic', 'semantic' }, { 'Dict', 'dict' }, { 'Chain', 'chain' },
    { 'Syntax', 'syntax' }, { 'Judge', 'judge' }, { 'Belt', 'belt' }, { 'Report', 'report' },
}
local known = {}
for _, entry in ipairs(vocabularies) do known[entry[1]] = true end

-- The document's copy: every fenced `text` block that opens with a module header. A real header ends
-- in `{`; §2.6 draws `module value = { … }` as a value sketch, which is why the match is not looser.
local spec, declared = {}, 0
do
    local current, in_text = nil, false
    for _, line in ipairs(lines_of(read('DESIGN.md'))) do
        if not in_text and line:match('^```text') then
            in_text, current = true, nil
        elseif in_text and line:match('^```') then
            in_text = false
            if current then
                declared = declared + 1
                local name = current[1]:match('^module%s+([A-Za-z]+)')
                check(spec[name] == nil, ('DESIGN.md declares %s exactly once'):format(name))
                spec[name] = table.concat(current, '\n')
            end
            current = nil
        elseif in_text then
            if line:match('^module%s+[A-Za-z]+%s*{$') then
                current = { line }
            elseif current then
                current[#current + 1] = line
            end
        end
    end
end

-- A module the document declares and the compiler does not have is a specification describing a
-- compiler that is not this one, so the sets must agree before any entry is compared.
if listing then
    print(('the document declares %d modules, the compiler has %d'):format(declared, #vocabularies))
else
    check(declared == #vocabularies,
        ('the document declares exactly the %d vocabularies, found %d'):format(#vocabularies, declared))
end
for name in pairs(spec) do
    check(known[name], ('DESIGN.md describes only vocabularies that exist: %s'):format(name))
end

local function diff(name, file_, code, by_spec, prefix)
    local names = {}
    for key in pairs(code) do names[key] = true end
    for key in pairs(by_spec) do names[key] = true end
    local ordered = {}
    for key in pairs(names) do ordered[#ordered + 1] = key end
    table.sort(ordered)
    local out = {}
    for _, key in ipairs(ordered) do
        if code[key] == nil then
            out[#out + 1] = ('  %s: %s is in the document and not in let/%s.lua'):format(prefix, key, file_)
        elseif by_spec[key] == nil then
            out[#out + 1] = ('  %s: %s is in let/%s.lua and not in the document'):format(prefix, key, file_)
        elseif code[key] ~= by_spec[key] then
            out[#out + 1] = ('  %s: %s differs\n    code: %s\n    spec: %s'):format(prefix, key,
                code[key], by_spec[key])
        end
    end
    return out, #ordered
end

local found = {}
for _, entry in ipairs(vocabularies) do
    local name, file_ = entry[1], entry[2]
    local block = read('let/' .. file_ .. '.lua'):match('module ' .. name .. ' %{[^\n]*\n(.-)\n%}')
    check(block ~= nil, ('let/%s.lua declares the %s module'):format(file_, name))
    local code, spec_text = entries(block), entries(spec[name] or '')
    local lines, count = diff(name, file_, code, spec_text, name)
    for _, line in ipairs(lines) do found[#found + 1] = line end
    if #lines == 0 then checks = checks + count end
end

if #found > 0 then
    local report = ('DESIGN.md §11 and the vocabularies disagree in %d place(s):\n%s')
        :format(#found, table.concat(found, '\n'))
    if listing then print(report) else error(report, 0) end
end

-- draft §0 says DESIGN.md SUPERSEDES the draft, so a citation to a section DESIGN.md does not have is a
-- citation to the draft -- and its damage is that it looks specified. draft §9 of this document is "The two
-- call shapes" (Apply and Invoke), while a comment citing §1.4 means the draft's "a read of a non-Copy
-- place", which is §1.4 here. §S67 repaired one of these by hand; §S72 found 33 in the document and
-- hundreds in the code, including some written that same day. This is the check that makes the class
-- impossible: every `§N.M` in the document and in every source file must name a section the document
-- HAS. `§S72`-style citations are ledger rows and are deliberately not matched.
local function section_number(text) return (text:gsub('%.$', '')) end
local sections = {}
for number in read('DESIGN.md'):gmatch('\n##+ ([0-9][0-9%.]*)') do
    sections[section_number(number)] = true
end
check(sections['0'] and sections['11.8'] and sections['12.3'],
    'the section numbers are readable from the document headings')

local dangling = {}
local function audit(file_, text)
    for line_number, line in ipairs(split_lines(text)) do
        local at = 1
        while true do
            local start, stop = line:find('§[0-9][0-9%.]*', at)
            if not start then break end
            -- `§` is two bytes in UTF-8, so the number starts at start + 2; a byte-index mistake
            -- here read every section as a control character and reported its own test as dangling.
            local trimmed = section_number(line:sub(start, stop):sub(3))
            -- A citation that SAYS it is to the draft is history and is allowed -- §0 makes the
            -- draft a record of where the language came from, and the ledger's rows quote it. What
            -- is not allowed is a citation that LOOKS like this document and is not.
            local before = line:sub(math.max(1, start - 40), start - 1)
            local historical = before:find('draft') or before:find('specification%.md')
            if not historical and not sections[trimmed] then
                dangling[('%s:%d §%s'):format(file_, line_number, trimmed)] = line
            end
            at = stop + 1
        end
    end
end
audit('DESIGN.md', read('DESIGN.md'))
for file_ in io.popen('ls let/*.lua test/*.lua'):lines() do audit(file_, read(file_)) end

local names = {}
for key in pairs(dangling) do names[#names + 1] = key end
table.sort(names)
if #names > 0 then
    local out = {('citations to sections DESIGN.md does not have: %d'):format(#names)}
    for _, key in ipairs(names) do
        out[#out + 1] = ('  %s\n      %s'):format(key, (dangling[key]:gsub('^%s+', ''):sub(1, 96)))
    end
    local report = table.concat(out, '\n')
    if listing then print(report) else error(report, 0) end
end
check(#names == 0, 'every citation names a section this document has')

print(('passed %d specification checks'):format(listing and 0 or checks))
