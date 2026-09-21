-- Runs every suite and reports the total check count.
--
-- The count is computed from the suites' own summaries rather than by hand, because a hand-counted total
-- in a commit message is a claim that can silently be wrong.
package.path = './?.lua;./?/init.lua;' .. package.path

local suites = {
    'test/spec.lua',        -- the document and the vocabularies agree, declaration by declaration
    'test/language.lua',    -- one program per construct, compiled and RUN
    'test/bundle.lua',      -- the same compiler in one file, with no checkout on package.path
    'test/reference.lua',   -- LANGUAGE_REFERENCE.md's own examples: every one is compiled
    'test/examples.lua',    -- the corpus: real programs in examples/, compiled and RUN
}
local interpreter = arg[-1] or 'luajit'
local total, failed = 0, {}
for _, suite in ipairs(suites) do
    local pipe = io.popen(('%s %s 2>&1'):format(interpreter, suite))
    local output = pipe:read('*a'); pipe:close()
    local count = output:match('passed (%d+)')
    local summary = output:match('passed [^\n]*')
    if count then
        total = total + tonumber(count)
        print(('%-22s %s'):format(suite, summary))
    else
        failed[#failed + 1] = suite
        print(('%-22s FAILED %s'):format(suite, (output:gsub('\n.*', ''):sub(1, 90))))
    end
end
print(('%-22s %d checks in %d suites'):format('total', total, #suites - #failed))
if #failed > 0 then os.exit(1) end
