-- Consumer demand across block interfaces. No instruction deletion or renumbering.
-- Input must satisfy verify_flow; this pass does not repair missing effect chains.
return function(V)
local B=V.Belt
function B.Exit:seed() end
function B.Return:seed(mark) for _,ref in ipairs(self.values) do mark(ref) end end
function B.Branch:seed(mark) mark(self.condition) end
function B.Trap:seed(mark) mark(self.effect) end
function B.TailCall:seed(mark) for _,ref in ipairs(self:inputs()) do mark(ref) end end
function B.Function:demands()
    self:verify_numbering()
    local reachable,work={[1]=true},{1}; local at=1
    while at<=#work do
        local id=work[at]; at=at+1
        for _,edge in ipairs(self.blocks[id].exit:edges()) do
            if not reachable[edge.target] then reachable[edge.target]=true; work[#work+1]=edge.target end
        end
    end
    local needed={}
    for id in pairs(reachable) do needed[id]={} end
    local changed
    local function require_output(id,producer,output)
        local block=needed[id]; block[producer]=block[producer] or {}
        if not block[producer][output] then block[producer][output]=true; changed=true end
    end
    local function mark(id,position,ref)
        local producer=self.blocks[id]:resolve(position,ref); require_output(id,producer,ref.output)
    end
    for id in pairs(reachable) do
        local block=self.blocks[id]; local position=#block.parameters+#block.instructions
        block.exit:seed(function(ref) mark(id,position,ref) end)
        -- An infinite ordered loop may have no return root. Its ongoing effects
        -- are still observable, so effect interfaces are roots on reachable blocks.
        for i,param in ipairs(block.parameters) do if param.type==B.Effect then require_output(id,i-1,0) end end
    end
    repeat
        changed=false
        for id=#self.blocks,1,-1 do if reachable[id] then
            local block=self.blocks[id]; local position=#block.parameters+#block.instructions
            for _,edge in ipairs(block.exit:edges()) do
                for i,ref in ipairs(edge.arguments) do
                    local target=needed[edge.target][i-1]
                    if target and target[0] then mark(id,position,ref) end
                end
            end
            for i=#block.instructions,1,-1 do
                local producer=#block.parameters+i-1
                if needed[id][producer] then
                    for _,ref in ipairs(block.instructions[i].operation:inputs()) do mark(id,producer,ref) end
                end
            end
        end end
    until not changed
    return needed,reachable
end
end

