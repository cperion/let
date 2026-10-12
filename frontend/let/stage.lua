-- VM-backed compile-time execution. Sessions own persistent VM/module images;
-- source computation executes only through the public ABC API, never in Lua.
local D = require('let.diag')
local ffi = require('let.abi')
local M = {}
local Session, Program = {}, {}
Session.__index, Program.__index = Session, Program
local MODES = {interpreted=0, eager=1, compiled=1, lazy=2, threaded=3}
local ABORTS = {
    [1]='division-zero', [2]='index-range', [3]='numeric-range',
    [4]='negative-exponent', [5]='unreachable', [6]='type-mismatch',
    [7]='field-missing', [8]='key-type', [9]='no-terminal',
    [10]='frozen-store', [11]='overapplication', [12]='dynamic-signature',
    [13]='readonly-field',
}
local function dependency(name)
    local ok, module = pcall(require, name)
    if not ok then D.internal('static-host', 'Cannot load staging dependency `'..name..'`: '..tostring(module)) end
    return module
end
local runtime
local function library()
    if runtime then return runtime end
    local source=debug.getinfo(1,'S').source:sub(2)
    local directory=source:match('^(.*)/[^/]+$') or '.'
    local path=os.getenv('ABC_RUNTIME_LIBRARY') or directory..'/../../build/libabc.so'
    local ok, loaded=pcall(ffi.load,path)
    if not ok then D.internal('static-host','Cannot load the ABC runtime at `'..path..'`: '..tostring(loaded)) end
    runtime=loaded; return runtime
end
local function validateOptions(options)
    for _,name in ipairs{'fuel','budget','instructionLimit','instructionBudget','timeout','allocationLimit','logicalAllocationLimit','specializationLimit','runtime'} do
        if options[name]~=nil then D.reject('static-option','Static execution has no `'..name..'` option') end
    end
end
local function definition(functions, name)
    for _,fn in ipairs(functions) do if fn.id==name then return fn end end
    D.bug('static-entry','Static entry `'..tostring(name)..'` is not an Ir.Fn in this lowering unit')
end
local function transportTypes(fn,field)
    local S=require('let.schema');local Layout=require('let.layout')
    local Snapshot=require('let.snapshot');local cells,values={},{}
    for _,value in ipairs(fn[field]) do
        local ty=field=='inputs' and value.type or value
        if field=='inputs' and value.kind~='InValue' then D.reject('static-transport','Staging cannot transport borrowed inputs') end
        Snapshot.contract(ty)
        if ty~=S.Unit then values[#values+1]=ty end
        for _,part in ipairs(Layout.abiComponents(ty)) do cells[#cells+1]=part end
    end
    return cells,values
end
local function asCell(value, Int, expected)
    if type(value)=='table' and value.bits~=nil then
        if value.type and value.type~=expected then D.reject('static-argument','Static argument type does not match the entry signature') end
        value=value.bits
    end
    if type(value)=='cdata' then
        if not ffi.istype('uint64_t',value) and not ffi.istype('int64_t',value) then
            D.reject('static-argument','Static cell cdata must contain exact 64-bit integer bits')
        end
        return Int.u(value)
    end
    if type(value)=='string' then return Int.parse(value) end
    if type(value)=='number' then
        if value~=value or value==math.huge or value==-math.huge or value%1~=0 or math.abs(value)>9007199254740991 then
            D.reject('static-argument','Static cell arguments must be exact integers or 64-bit strings')
        end
        return Int.parse(string.format('%.0f',value))
    end
    D.reject('static-argument','Static cell arguments must be exact integers, 64-bit strings, or `{bits=...}`')
end
local function executionError(C, err, program)
    local status=ffi.string(C.abc_status_name(err.status))
    local offset=tonumber(err.offset)
    if offset==4294967295 then offset=nil end
    if offset and program and program.provenance[offset] then offset=program.provenance[offset] end
    local line=offset and program and program.locations.offsetToLine[offset] or nil
    local node=line and program.artifact.lineMap and program.artifact.lineMap[line] or nil
    local reason=tonumber(err.reason)
    local kind,code,text
    if status=='abort' then
        local name=ABORTS[reason] or ('reason-'..reason)
        kind,code,text='reject','static-'..name,'Compile-time execution aborted: '..name
    elseif status=='stack-limit' then
        kind,code,text='resource','static-stack','Compile-time VM stack limit reached'
    elseif status=='out-of-memory' then
        kind,code,text='resource','static-memory','Compile-time VM memory allocation failed'
    elseif status=='invalid' or status=='arguments' or status=='result-capacity' or status=='export-not-found' then
        kind,code,text='bug','static-vm-'..status,'Generated static module failed: '..ffi.string(err.message)
    else
        kind,code,text='internal','static-vm','Cannot execute the static module: '..ffi.string(err.message)
    end
    local diagnostic=D.make(kind,code,text,node and node.span or nil)
    diagnostic.bytecodeOffset,diagnostic.assemblyLine,diagnostic.ir=offset,line,node
    diagnostic.vmStatus,diagnostic.abortReason=status,reason
    error(diagnostic,0)
end
local function usable(session)
    if session.closed then D.reject('static-session','Staging session is closed') end
    if session.busy then D.reject('static-session','Staging session is already executing a call') end
end
function M.open(options)
    options=options or {}; validateOptions(options)
    if MODES[options.mode]==nil then D.reject('execution-policy','Static execution requires mode `interpreted`, `threaded`, `eager`, or `lazy`') end
    if options.stackCells~=nil and (type(options.stackCells)~='number' or options.stackCells%1~=0 or options.stackCells<=0 or options.stackCells>9007199254740991) then
        D.reject('static-stack','The static VM stack limit must be a positive exact cell count')
    end
    if options.optimize~=nil and type(options.optimize)~='boolean' then D.reject('static-option','Static optimize must be boolean') end
    local C=library(); local limits=ffi.new('abc_limits[1]')
    limits[0].mode=MODES[options.mode]; limits[0].stack_cells=options.stackCells or 0
    local pointer,err=ffi.new('abc_vm *[1]'),ffi.new('abc_error[1]')
    if C.abc_vm_create(limits,pointer,err)~=0 then executionError(C,err[0]) end
    -- Capture the library, not the session, in defensive finalizers. This keeps
    -- dlopen ownership alive without rooting a session through its own finalizer.
    return setmetatable({C=C,vm=ffi.gc(pointer[0],function(p) C.abc_vm_free(p) end),mode=options.mode,
        optimize=options.optimize~=false,programs={},closed=false,busy=false},Session)
end
function Session:close()
    if self.closed then return end
    usable(self)
    self.closed=true
    self.C.abc_vm_free(ffi.gc(self.vm,nil)); self.vm=nil
    for _,program in ipairs(self.programs) do
        self.C.abc_module_free(ffi.gc(program.handle,nil)); program.handle=nil
    end
    self.programs={}
end
function Session:prepare(artifact, functions)
    usable(self)
    local code='\n'..artifact.assembly
    if (code:match('\n%s*%.extern%s') or code:match('\n%s*FCALL[%.%s]')) and not require('let.runtime').staging(code) then
        D.reject('static-foreign','Foreign effects cannot execute during compilation')
    end
    local Assembler=dependency('assembler')
    local ok,image,locations,provenance=pcall(function()
        local bytes,map=Assembler.assemble(artifact.assembly); local origins={}
        if self.optimize then bytes,origins=dependency('let.optimize').optimizeMapped(bytes) end
        return bytes,map,origins
    end)
    if not ok then
        if D.is(image) then error(image,0) end
        D.bug('static-assembly','Checked IR produced invalid ABC assembly: '..tostring(image))
    end
    local pointer,err=ffi.new('abc_module *[1]'),ffi.new('abc_error[1]')
    local program=setmetatable({session=self,artifact=artifact,functions=functions,
        image=image,locations=locations,provenance=provenance},Program)
    if self.C.abc_module_load(image,#image,pointer,err)~=0 then executionError(self.C,err[0],program) end
    local C=self.C
    program.handle=ffi.gc(pointer[0],function(p) C.abc_module_free(p) end)
    -- Register ownership before eager preparation, including failed preparation.
    self.programs[#self.programs+1]=program
    if self.C.abc_vm_load(self.vm,program.handle,err)~=0 then executionError(self.C,err[0],program) end
    program.ready=true
    return program
end
function Program:call(options)
    options=options or {}; validateOptions(options)
    local session=self.session; usable(session)
    if not self.ready then D.reject('static-session','Staging program was not prepared successfully') end
    for _,name in ipairs{'mode','stackCells','optimize'} do
        if options[name]~=nil then D.reject('static-option','Session policy `'..name..'` cannot change per call') end
    end
    local entry=options.entry or 'main'; local fn=definition(self.functions,entry)
    local argumentTypes,inputValues=transportTypes(fn,'inputs')
    local resultTypes,outputValues=transportTypes(fn,'results')
    local supplied=options.arguments or {}
    if #supplied~=#inputValues then D.reject('static-arguments',string.format('Static entry `%s` needs %d values but received %d',entry,#inputValues,#supplied)) end
    local Snapshot=require('let.snapshot');local flattened={}
    for index,ty in ipairs(inputValues) do
        if require('let.layout').cellKind(ty) then flattened[#flattened+1]=supplied[index]
        else
            local snapshot=supplied[index]
            if type(snapshot)~='table' or snapshot.type~=ty then D.reject('static-argument','Aggregate argument needs an exact typed snapshot') end
            for _,cell in ipairs(Snapshot.cells(snapshot)) do flattened[#flattened+1]=cell end
        end
    end
    local signature,err=ffi.new('abc_signature[1]'),ffi.new('abc_error[1]')
    if session.C.abc_module_export_signature(self.handle,entry,signature,err)~=0 then executionError(session.C,err[0],self) end
    local sig=signature[0]; local S=require('let.schema')
    if sig.arguments~=#argumentTypes or sig.results~=#resultTypes or sig.hidden_result_bytes~=0 then D.bug('static-signature','Staging transport contract disagrees with the module export') end
    for _,spec in ipairs{{argumentTypes,sig.argument_kinds},{resultTypes,sig.result_kinds}} do
        for index,ty in ipairs(spec[1]) do
            if spec[2][index-1]~=(ty==S.F64 and 2 or 0) then D.bug('static-signature','Staging cell kind disagrees with the module export') end
        end
    end
    local Int=dependency('int64')
    local arguments=ffi.new('uint64_t[?]',math.max(1,#flattened))
    for index,value in ipairs(flattened) do arguments[index-1]=asCell(value,Int,argumentTypes[index]) end
    local output,count=ffi.new('uint64_t[?]',math.max(1,#resultTypes)),ffi.new('size_t[1]')
    local progress=options.progress
    session.busy=true
    local ok,result=pcall(function()
        if progress then progress{phase='start',binding=entry,mode=session.mode} end
        local status=session.C.abc_vm_call(session.vm,self.handle,entry,arguments,#flattened,output,#resultTypes,count,err)
        if status~=0 then
            -- Preserve the VM failure even if an abort notification also fails.
            if progress then pcall(progress,{phase='abort',binding=entry,mode=session.mode}) end
            executionError(session.C,err[0],self)
        end
        if tonumber(count[0])~=#resultTypes then D.bug('static-results','Static VM returned an unexpected result count') end
        local cells,values={},{}
        for index in ipairs(resultTypes) do cells[index]=ffi.new('uint64_t',output[index-1]) end
        local at=1
        for index,ty in ipairs(outputValues) do
            if require('let.layout').cellKind(ty) then values[index]={type=ty,bits=cells[at]};at=at+1
            else values[index],at=Snapshot.fromCells(ty,cells,at) end
        end
        local moduleData={}
        for index,data in ipairs(self.artifact.moduleData or {}) do
            local size=#data.bytes;local bytes=ffi.new('uint8_t[?]',math.max(1,size))
            local status=session.C.abc_vm_read_image(session.vm,self.handle,self.artifact.moduleOffsets[data.root],bytes,size,err)
            if status~=0 then executionError(session.C,err[0],self) end
            moduleData[index]=S.Ir.ModuleData(data.root,ffi.string(bytes,size))
        end
        if progress then progress{phase='finish',binding=entry,mode=session.mode} end
        return {phase='executed',profile=self.artifact.profile,mode=session.mode,entry=entry,
            artifact=self.artifact,module=self.image,locations=self.locations,cells=cells,values=values,moduleData=moduleData}
    end)
    session.busy=false
    if not ok then error(result,0) end
    return result
end
function M.execute(artifact, functions, options)
    options=options or {}
    local session=M.open(options)
    local ok,result=pcall(function()
        local program=session:prepare(artifact,functions)
        return program:call{entry=options.entry,arguments=options.arguments,progress=options.progress}
    end)
    session:close()
    if not ok then error(result,0) end
    return result
end
return M
