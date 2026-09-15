-- Runs every suite and reports the total check count.
-- The count is computed from the suites' own summaries rather than by hand, because a
-- hand-counted total in a commit message is a claim that can silently be wrong.
package.path='./?.lua;./?/init.lua;'..package.path

local suites={
    'test/vocab.lua','test/build.lua','test/demand.lua','test/source.lua',
    'test/resolve.lua','test/program.lua','test/emit.lua','test/aggregate.lua',
    'test/known.lua','test/import.lua','test/place.lua','test/host_entry.lua',
    'test/native.lua','test/bundle.lua',
}
local total,failed=0,{}
for _,suite in ipairs(suites) do
    local pipe=io.popen(('luajit %s 2>&1'):format(suite))
    local output=pipe:read('*a'); pipe:close()
    local count=output:match('passed (%d+)')
    local summary=output:match('passed [^\n]*')
    if count then
        total=total+tonumber(count)
        print(('%-22s %s'):format(suite:gsub('^',''),summary))
    else
        failed[#failed+1]=suite
        print(('%-22s FAILED %s'):format(suite:gsub('^',''),(output:gsub('\n.*',''):sub(1,60))))
    end
end
print(('%-22s %d checks in %d suites'):format('total',total,#suites-#failed))
if #failed>0 then os.exit(1) end
