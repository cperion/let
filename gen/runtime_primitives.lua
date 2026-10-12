-- Private runtime-call ABI v1. FCALL transports ordinary cells; neither the ISA
-- nor its verifier infers source ownership. This catalog is shared by generated
-- C bindings and compiler lowering/staging policy. No user callback is a primitive.
local M={prefix='__let_rt_v1_'}
M.operations={
 {name='scope_enter',inputs='ai',results='',holding_inputs='borrow storage',holding_results='none',memory='initialize scope and slots',allocation='none',failure='invalid extent',suspension='never',clobbers='call ABI',binding='scope'},
 {name='scope_leave',inputs='a',results='',holding_inputs='consume initialized slots',holding_results='none',memory='unlink scope; release slots',allocation='none',failure='invalid nesting',suspension='never',clobbers='call ABI',binding='scope'},
 {name='owner_new',inputs='aiii',results='a',holding_inputs='borrow scope',holding_results='new holding in slot',memory='initialize allocation and slot',allocation='possible',failure='size or allocation; unchanged slot',suspension='never',clobbers='call ABI',binding='allocation'},
 {name='owner_retain',inputs='aia',results='',holding_inputs='borrow protected owner',holding_results='new holding in slot',memory='count and slot',allocation='none',failure='overflow; unchanged count and slot',suspension='never',clobbers='call ABI',binding='retain'},
 {name='owner_drop',inputs='ai',results='',holding_inputs='consume slot',holding_results='none',memory='clear slot; decrement and release',allocation='none',failure='invalid slot',suspension='never',clobbers='call ABI',binding='release'},
 {name='owner_move',inputs='aiai',results='',holding_inputs='consume source slot',holding_results='transferred holding in destination slot',memory='two slots; no count change',allocation='none',failure='invalid slots; unchanged slots',suspension='never',clobbers='call ABI',binding='transfer'},
 {name='owner_data',inputs='a',results='a',holding_inputs='borrow protected owner',holding_results='borrow with same origin',memory='read immutable layout',allocation='none',failure='none for valid owner',suspension='never',clobbers='call ABI',binding='address'},
 {name='owner_set',inputs='aa',results='',holding_inputs='borrow holder and protected target',holding_results='new field holding; release displaced holding',memory='retain target before replace and release',allocation='none',failure='layout or overflow; unchanged field',suspension='never',clobbers='call ABI',binding='replace'},
}
M.by_name={}
for i,p in ipairs(M.operations) do
 for _,field in ipairs{'name','inputs','results','holding_inputs','holding_results','memory','allocation','failure','suspension','clobbers','binding'} do assert(type(p[field])=='string','missing primitive field '..field) end
 p.symbol=M.prefix..p.name;p.id=i-1
 assert(not M.by_name[p.symbol],'duplicate runtime primitive');M.by_name[p.symbol]=p
 assert(p.inputs:match('^[iaf]*$') and #p.inputs<=6 and p.results:match('^[iaf]?$'),'invalid primitive cell signature')
end
function M.reserved(name) return name:sub(1,9)=='__let_rt_' end
return M
