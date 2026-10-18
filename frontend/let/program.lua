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
  modules=vector(modules or functions.moduleData),foreigns=vector(foreigns),typeCells={}}
 for name,ty in pairs(functions.typeCells or {}) do program.typeCells[name]=ty end
 Check.program(program.functions,program.modules,program.foreigns,false,program.typeCells)
 local queries,access,stats,construction=Access.analyze(program.functions)
 Access.validate(program.functions,queries)
 program.access=access;program.accessStats=stats
 program.ownership=Ownership.analyze(program.functions,queries,construction)
 return program
end
-- Entry selection is code reachability, independent of ownership choices.
function M.select(program,entries)
 local S=require('let.schema');local I=S.Ir;local Walk=require('let.walk')
 local byName,needed,external,queue={},{},{},{}
 for _,fn in ipairs(program.functions) do byName[fn.id]=fn end
 local function need(id)
  if byName[id] then if not needed[id] then needed[id]=true;queue[#queue+1]=byName[id] end
  else external[id]=true end
 end
 local roots={}
 for _,id in ipairs(entries) do assert(byName[id],'unknown source entry '..id);roots[id]=true;need(id) end
 local cursor=1
 while cursor<=#queue do
  Walk.walk(queue[cursor],{enter=function(node)
   if S.Ty.V:isclassof(node) then return false end
   if I.Call:isclassof(node) then need(node.target)
   elseif I.View:isclassof(node) or I.Code:isclassof(node) then need(node.entry) end
  end});cursor=cursor+1
 end
 local selected={phase='selected-program',source=program,entries=roots,functions={},modules=program.modules,foreigns={}}
 for _,fn in ipairs(program.functions) do if needed[fn.id] then selected.functions[#selected.functions+1]=fn end end
 for _,f in ipairs(program.foreigns) do if external[f.target] then selected.foreigns[#selected.foreigns+1]=f end end
 return selected
end
return M
