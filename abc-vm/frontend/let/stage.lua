-- VM-backed compile-time execution for already verified typed IR.
-- Language operations are never reproduced in Lua: this module assembles the output of
-- let.abc, loads it through the public runtime, and asks abc_vm_call to execute it.
local D = require("let.diag")

local M = {}

local MODES = { interpreted = "interpreted", eager = "compiled", compiled = "compiled", lazy = "lazy" }
local ABORTS = {
    [1] = "null-access", [2] = "index-range", [3] = "numeric-range",
    [4] = "arity-mismatch", [5] = "missing-result", [6] = "invalid-callable",
    [7] = "layout-mismatch", [8] = "missing-key", [9] = "generic-operands",
    [10] = "variant-mismatch",
}

local function dependency(name)
    local ok, module = pcall(require, name)
    if not ok then
        D.internal("static-host", "VM-backed static execution cannot load host module `" .. name .. "`: " .. tostring(module))
    end
    return module
end

local function scalarTypes(fn, field)
    local out = {}
    for _, value in ipairs(fn[field]) do
        local ty = field == "inputs" and value.type or value
        if ty ~= require("let.schema").unit then out[#out + 1] = ty end
    end
    return out
end

local function definition(functions, name)
    for _, fn in ipairs(functions) do if fn.id == name then return fn end end
    D.bug("static-entry", "Static entry `" .. tostring(name) .. "` is not an Ir.Fn in this lowering unit")
end

local function asCell(value, Int)
    if type(value) == "table" and value.bits ~= nil then value = value.bits end
    if type(value) == "cdata" then return Int.u(value) end
    if type(value) == "string" then return Int.parse(value) end
    if type(value) == "number" then
        if value ~= value or value == math.huge or value == -math.huge or value % 1 ~= 0
                or math.abs(value) > 9007199254740991 then
            D.reject("static-argument", "Static cell arguments must be exact integers or 64-bit strings")
        end
        return Int.parse(string.format("%.0f", value))
    end
    D.reject("static-argument", "Static cell arguments must be exact integers, 64-bit strings, or `{bits=...}`")
end

local function sourceAt(artifact, locations, offset)
    local line = offset and locations.offsetToLine[offset] or nil
    return line, line and artifact.lineMap[line] or nil
end

local function executionError(message, artifact, locations, provenance)
    message = tostring(message):gsub("%s+$", "")
    local status = message:match("abc: ([a-z%-]+)") or "internal"
    local hex = message:match("at byte 0x([0-9a-fA-F]+)")
    local offset = hex and tonumber(hex, 16) or nil
    if offset and provenance and provenance[offset] then offset = provenance[offset] end
    local line, node = sourceAt(artifact, locations, offset)
    local reasonNumber = tonumber(message:match("language abort (%d+)"))
    local reason = reasonNumber and (ABORTS[reasonNumber] or ("reason-" .. reasonNumber)) or nil
    local kind, code, text
    if status == "abort" then
        kind, code = "reject", "static-" .. (reason or "abort")
        text = "Compile-time execution aborted" .. (reason and ": " .. reason or "")
    elseif status == "stack-limit" then
        kind, code, text = "resource", "static-stack", "Compile-time VM stack limit reached"
    elseif status == "out-of-memory" then
        kind, code, text = "resource", "static-memory", "Compile-time VM memory allocation failed"
    elseif status == "invalid" or status == "arguments" or status == "result-capacity"
            or status == "export-not-found" then
        kind, code, text = "bug", "static-vm-" .. status, "Generated static module failed: " .. message
    else
        kind, code, text = "internal", "static-vm", "Cannot execute the static module: " .. message
    end
    local diagnostic = D.make(kind, code, text, node and node.span or nil)
    diagnostic.bytecodeOffset, diagnostic.assemblyLine, diagnostic.ir = offset, line, node
    error(diagnostic, 0)
end

function M.execute(artifact, functions, options)
    options = options or {}
    for _,name in ipairs{"fuel","budget","instructionLimit","instructionBudget","timeout","allocationLimit","logicalAllocationLimit","specializationLimit"} do
        if options[name]~=nil then D.reject("static-option","Static execution has no `"..name.."` budget option") end
    end
    local code = "\n" .. artifact.assembly
    if code:match("\n%s*%.extern%s") or code:match("\n%s*FCALL%s") then
        D.reject("static-foreign", "Foreign effects cannot execute during compilation")
    end
    local selected = options.mode
    local runtimeMode = MODES[selected]
    if not runtimeMode then
        D.reject("execution-policy", "Static execution requires mode `interpreted`, `eager`, or `lazy`")
    end
    local entry = options.entry or "main"
    local fn = definition(functions, entry)
    local argumentTypes, resultTypes = scalarTypes(fn, "inputs"), scalarTypes(fn, "results")
    local supplied = options.arguments or {}
    if #supplied ~= #argumentTypes then
        D.reject("static-arguments", string.format("Static entry `%s` needs %d cells but received %d",
            entry, #argumentTypes, #supplied))
    end
    if options.stackCells ~= nil and (type(options.stackCells) ~= "number"
            or options.stackCells % 1 ~= 0 or options.stackCells <= 0) then
        D.reject("static-stack", "The static VM stack limit must be a positive cell count")
    end

    local Assembler, Util, Int = dependency("assembler"), dependency("tool_util"), dependency("int64")
    local Optimizer = dependency("let.optimize")
    local ok, image, locations, provenance = pcall(function()
        local bytes, map = Assembler.assemble(artifact.assembly)
        local provenanceMap = {}
        if options.optimize ~= false then bytes, provenanceMap = Optimizer.optimizeMapped(bytes) end
        return bytes, map, provenanceMap
    end)
    if not ok then D.bug("static-assembly", "Checked IR produced invalid ABC assembly: " .. tostring(image)) end

    local cells, command = {}, {options.runtime or Util.runtime, "run"}
    for index, value in ipairs(supplied) do
        cells[index] = asCell(value, Int)
    end
    local path = os.tmpname() .. ".abc"
    os.remove(path)
    local progress = options.progress
    if progress then progress({phase = "start", binding = entry, mode = selected}) end
    local ran, output, errors
    local protected, failure = pcall(function()
        Util.publish(image, path) -- abc-runtime check: loading also verifies the generated module.
        command[#command + 1] = path
        command[#command + 1] = entry
        command[#command + 1] = "--" .. runtimeMode
        if options.stackCells then command[#command + 1] = "--stack=" .. options.stackCells end
        for _, cell in ipairs(cells) do command[#command + 1] = Int.format(cell, false) end
        ran, output, errors = Util.capture(command)
    end)
    os.remove(path)
    if not protected then
        if D.is(failure) then error(failure, 0) end
        D.internal("static-host", "Cannot prepare the static VM: " .. tostring(failure))
    end
    if not ran then
        if progress then progress({phase = "abort", binding = entry, mode = selected}) end
        executionError(errors ~= "" and errors or output, artifact, locations, provenance)
    end

    local results = {}
    for token in output:gmatch("%S+") do results[#results + 1] = Int.parse(token) end
    if #results ~= #resultTypes then
        D.bug("static-results", string.format("Static entry `%s` returned %d cells; its IR declares %d",
            entry, #results, #resultTypes))
    end
    local values = {}
    for index, bits in ipairs(results) do values[index] = {type = resultTypes[index], bits = bits} end
    if progress then progress({phase = "finish", binding = entry, mode = selected}) end
    return {
        phase = "executed", profile = artifact.profile, mode = selected, entry = entry,
        artifact = artifact, module = image, locations = locations, cells = results, values = values,
    }
end

return M
