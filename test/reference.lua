-- LANGUAGE_REFERENCE.md is checked, not asserted.
--
-- A reference document is prose, and prose is checked by nothing -- which is how a document comes to
-- describe a language that no longer exists. So every fenced block in it is a claim, and the fence's
-- info string is the claim's kind:
--
--     ```let                  a complete file that must COMPILE
--     ```let refuse: Reason   a complete file that must be a Reject, with that reason
--     ```let missing: Reason  a complete file that must be a Missing, with that reason
--     ```text / ```c          a sketch; not a program, so not a claim
--
-- This is the same discipline the language suite follows -- a check is a PROGRAM -- applied to the
-- document that describes the programs.
local H = require('test.harness')
H.suite = 'reference'

local path = 'LANGUAGE_REFERENCE.md'
local file = assert(io.open(path, 'rb'), path .. ' is missing')
local text = file:read('*a')
file:close()

-- The document's blocks, in order, as `{ info, body }`.
local blocks, info, body = {}, nil, {}
for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    if line:sub(1, 3) == '```' then
        if info then
            blocks[#blocks + 1] = { info = info, body = table.concat(body, '\n') .. '\n' }
            info, body = nil, {}
        else
            info = line:sub(4)
        end
    elseif info then
        body[#body + 1] = line
    end
end
H.check(info == nil, 'every fence in ' .. path .. ' is closed')

-- The kinds, and the ONE thing each asserts. A block whose tag this file does not know is an error
-- rather than a skip: a typo in a fence would otherwise make a claim silently unchecked, which is the
-- failure this suite exists to prevent.
local scratch = 0
for _, block in ipairs(blocks) do
    local kind, reason = block.info:match('^let%s+([a-z]+):%s*(%w+)$')
    if block.info == 'let' or kind then
        scratch = scratch + 1
        local where = ('%s block %d'):format(path, scratch)
        local source, diagnostic = H.compile(block.body, ('reference%03d'):format(scratch))
        if not kind then
            H.check(source ~= nil, where .. ' compiles' ..
                (diagnostic and (' (but: ' .. tostring(diagnostic.why) .. ')') or ''))
        else
            H.check(diagnostic ~= nil, where .. ' is refused')
            local want = H.R[reason]
            H.check(want ~= nil, where .. ' names a real ' .. reason)
            if diagnostic and want then
                if kind == 'refuse' then
                    H.check(H.Reject:isclassof(diagnostic), where .. ' is a Reject')
                elseif kind == 'missing' then
                    H.check(H.Missing:isclassof(diagnostic), where .. ' is a Missing')
                else
                    assert(false, where .. ' has an unknown fence tag `' .. kind .. '`')
                end
                H.check(want:isclassof(diagnostic.why), where .. ' is ' .. reason ..
                    ', got ' .. tostring(diagnostic.why))
            end
        end
    elseif block.info ~= 'text' and block.info ~= 'c' then
        assert(false, 'unknown fence info string `' .. block.info .. '` in ' .. path)
    end
end

H.finish()
