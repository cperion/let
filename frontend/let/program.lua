-- A completed IR graph owns its proofs. Consumers share this result, never
-- annotations on shared Fn nodes. Treat the graph as frozen after analyze;
-- transformations construct a new graph and analyze it explicitly.
local Check=require('let.check')
local Access=require('let.access')
local Ownership=require('let.ownership')
local M={}
local function vector(items)
 local result={};for i,item in ipairs(items or {}) do result[i]=item end;return result
end
function M.analyze(functions,modules,foreigns)
 local program={phase='checked-program',functions=vector(functions),
  modules=vector(modules or functions.moduleData),foreigns=vector(foreigns)}
 Check.program(program.functions,program.modules,program.foreigns)
 local queries,access,stats,flow=Access.analyze(program.functions)
 program.access=access;program.accessStats=stats;program.flow=flow
 program.ownership=Ownership.analyze(program.functions,queries,flow)
 Ownership.validate(program.functions,program.ownership)
 Access.validate(program.functions,queries)
 return program
end
return M
