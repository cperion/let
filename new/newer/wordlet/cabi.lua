-- C ABI closure: layouts, names and signatures for a verified program.
local S = require("wordlet.schema")
local D = require("wordlet.diag")
local M = {}

local Ir = S.Ir

-- Encode every non-alphanumeric byte, including underscore, so the mapping is injective.
function M.escape(name)
    return (name:gsub("[^%w]", function(c) return string.format("_%02X", c:byte()) end))
end

function M.functionName(name) return "wordlet_" .. M.escape(name) end

function M.close(compilation)
    local layouts = {
        compilation = compilation,
        tuples = {},        -- result vector -> { name, fields }
        tupleOrder = {},
        records = {},       -- Ty.Record -> { name, fields }
        recordOrder = {},
        signatures = {},
    }

    local function recordLayout(ty)
        local existing = layouts.records[ty]
        if existing then return existing end
        local layout = { name = "wordletrecord_" .. (#layouts.recordOrder + 1), type = ty, fields = {} }
        layouts.records[ty] = layout
        layouts.recordOrder[#layouts.recordOrder + 1] = layout
        for _, field in ipairs(ty.fields) do
            layout.fields[#layout.fields + 1] = { name = "f_" .. M.escape(field.name), type = field.type }
        end
        return layout
    end

    local function resultLayout(results)
        if #results == 0 then return { kind = "void" } end
        if #results == 1 then
            if results[1] == S.Unit then return { kind = "void", unit = true } end
            return { kind = "scalar", type = results[1] }
        end
        local key = S.encode(S.list(results))
        local existing = layouts.tuples[key]
        if existing then return existing end
        local layout = { kind = "tuple", name = "wordlettuple_" .. (#layouts.tupleOrder + 1), fields = {} }
        layouts.tuples[key] = layout
        layouts.tupleOrder[#layouts.tupleOrder + 1] = layout
        for index, ty in ipairs(results) do
            layout.fields[#layout.fields + 1] = { name = "f_" .. index, type = ty }
        end
        return layout
    end

    layouts.recordLayout = recordLayout
    layouts.resultLayout = resultLayout

    function layouts:cType(ty)
        if ty == S.U32 then return "uint32_t" end
        if ty == S.Bool then return "bool" end
        if ty == S.Unit then return "void" end
        if S.isRecord(ty) then return recordLayout(ty).name end
        D.todo("c-type", "No C representation for " .. S.encode(ty))
    end

    -- Public names: the first export of an instance uses the export name; extra aliases become
    -- forwarding wrappers emitted by the backend.
    local exported = {}
    for _, entry in ipairs(compilation.functions) do
        local instance = entry.instance
        local name = M.functionName(entry.name)
        if exported[instance.target] then
            exported[instance.target].aliases[#exported[instance.target].aliases + 1] = name
        else
            exported[instance.target] = { name = name, instance = instance, aliases = {} }
        end
    end

    local signatures = {}
    local function signature(fn, cName, hidden)
        local params, placeParams = {}, {}
        for _, param in ipairs(fn.params) do
            if param.kind == "ValueParam" then
                -- The C parameter is named after the SSA value so Ref() lowers directly.
                params[#params + 1] = { name = "v" .. param.binding.id, type = param.type, input = param.input }
            elseif param.kind == "PlaceParam" then
                -- A borrowed receiver is a pointer; its storage id names the pointed-to object.
                params[#params + 1] = { name = "s" .. param.binding.id, type = param.type,
                    input = param.input, pointer = true }
                placeParams[param.binding.id] = true
            else
                D.todo("c-input", "Only by-value and borrowed inputs have a C representation yet")
            end
        end
        return { fn = fn, name = cName, params = params, placeParams = placeParams,
            results = resultLayout(fn.results), hidden = hidden or 0 }
    end

    for _, instance in ipairs(compilation.session.order) do
        local entry = exported[instance.target]
        local cName = entry and entry.name or instance.target
        signatures[instance.target] = signature(instance.fn, cName)
        signatures[instance.target].aliases = entry and entry.aliases or {}
    end

    -- Exported record types get a public alias so consumers never name a numbered struct.
    layouts.typeExports = {}
    for _, entry in ipairs(compilation.types or {}) do
        local layout = recordLayout(entry.type)
        layouts.typeExports[#layouts.typeExports + 1] = {
            name = "wordtype_" .. M.escape(entry.name), layout = layout, entry = entry,
        }
    end
    layouts.signatures = signatures
    layouts.order = compilation.session.order
    return layouts
end

return M
