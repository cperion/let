-- Structural regression: both bindings must traverse the complete same
-- semantic computation, not independently orchestrate shared arithmetic leaves.
package.path='./?.lua;'..package.path
local flow=require('gen.scalar_semantics')
local manifest=require('tools.opcodes')
local families={unary=true,binary=true,literal=true,compare=true,condition=true}
local expected={ANY_BOX=true,ANY_CAST=true,ANY_IS=true}
for _,op in ipairs(manifest.ext_ops) do if families[op.family] then expected[op.name]=true end end
for _,name in ipairs(flow.names) do assert(expected[name],name);expected[name]=nil end
assert(not next(expected),'scalar selector missing from common flow')
local function value(v)
  if type(v)=='table' then local out={}for _,x in ipairs(v)do out[#out+1]=value(x)end;return '{'..table.concat(out,',')..'}' end
  return tostring(v)
end
local trace,original={},flow.emit
flow.emit=function(backend,name)
  local proxy=setmetatable({},{__index=function(_,method)
    return function(_, ...)
      local args={};for i=1,select('#',...)do args[i]=value(select(i,...))end
      trace[#trace+1]=method..'('..table.concat(args,',')..')'
      return backend[method](backend,...)
    end
  end})
  original(proxy,name)
end
local function builder()
  return {peek=function(_,_,depth)return 'operand'..depth end,pop=function()end,push=function()end,
    forget_unused=function()end,finish=function()return ''end}
end
local concrete={}
require('gen.scalar_banked').emit_handlers(function(text)concrete[#concrete+1]=text end,builder,{a=0,b=0,c=0},'test_EXT')
local first=table.concat(trace,'\n');trace={}
require('gen.scalar_symbolic').emit(function()end)
assert(first==table.concat(trace,'\n'),'concrete/symbolic scalar control flow differs')
flow.emit=original
local code=table.concat(concrete,'\n')
assert(not code:find('abc_scalar_binary_bits',1,true) and not code:find('abc_scalar_unary_bits',1,true),'second arithmetic dispatch retained')
print(('validated one shared control-flow definition for %d scalar instructions (%d semantic binding events)'):format(#flow.names,#trace))
