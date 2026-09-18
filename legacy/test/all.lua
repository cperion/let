-- Runs every suite and reports the total check count.
-- The count is computed from the suites' own summaries rather than by hand, because a
-- hand-counted total in a commit message is a claim that can silently be wrong.
package.path='./?.lua;./?/init.lua;'..package.path

local suites={
    'test/programs.lua',
    'test/belt.lua','test/vocab.lua','test/build.lua','test/demand.lua','test/source.lua',
    'test/resolve.lua','test/program.lua','test/emit.lua','test/aggregate.lua',
    'test/known.lua','test/import.lua','test/place.lua','test/host_entry.lua',
    'test/native.lua','test/width.lua','test/sum.lua','test/view.lua','test/float.lua','test/ide.lua','test/bundle.lua',
}
-- `test/bundle.lua` runs under either host: the committed bundle is host-independent, so both
-- hosts must regenerate it byte for byte, and running this file under each is what checks that.
-- Run each suite with the interpreter running this file, so the suite runs on LuaJIT or PUC Lua.
local interpreter=arg[-1] or 'luajit'
local total,failed=0,{}
for _,suite in ipairs(suites) do
    local pipe=io.popen(('%s %s 2>&1'):format(interpreter,suite))
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
