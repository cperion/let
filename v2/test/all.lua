-- Runs every v2 suite and reports the total check count.
-- The count is computed from the suites' own summaries rather than by hand, because a
-- hand-counted total in a commit message is a claim that can silently be wrong.
package.path='./?.lua;./?/init.lua;'..package.path

local suites={
    'v2/test.lua','v2/test/build.lua','v2/test/demand.lua','v2/test/source.lua',
    'v2/test/resolve.lua','v2/test/program.lua','v2/test/emit.lua','v2/test/aggregate.lua',
    'v2/test/known.lua','v2/test/import.lua','v2/test/place.lua','v2/test/host_entry.lua',
    'v2/test/native.lua',
}
local total,failed=0,{}
for _,suite in ipairs(suites) do
    local pipe=io.popen(('luajit %s 2>&1'):format(suite))
    local output=pipe:read('*a'); pipe:close()
    local count=output:match('passed (%d+)')
    local summary=output:match('passed [^\n]*')
    if count then
        total=total+tonumber(count)
        print(('%-22s %s'):format(suite:gsub('^v2/',''),summary))
    else
        failed[#failed+1]=suite
        print(('%-22s FAILED %s'):format(suite:gsub('^v2/',''),(output:gsub('\n.*',''):sub(1,60))))
    end
end
print(('%-22s %d checks in %d suites'):format('total',total,#suites-#failed))
if #failed>0 then os.exit(1) end
