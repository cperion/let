-- Explicit embedding vocabulary. Resources are opaque signed 64-bit handles.
local V = require('let.vocab')
local S, I, L, T, CT = V.Semantic, V.Analysis, V.List, V.Residual, V.Residual
local fail = require('let.lexer').fail
function S.Shape:is_copy() return true end
function S.Resource:is_copy() return false end
function S.Int:ctype() return T.I64 end
function S.Resource:ctype() return T.I64 end
function S.Bool:ctype() return T.Bool end
function S.Unit:ctype() return T.U8 end
function S.Read:is_owned() return false end
function S.Mut:is_owned() return false end
function S.Own:is_owned() return true end
function S.OwnMut:is_owned() return true end
function S.Read:is_mutable() return false end
function S.Mut:is_mutable() return true end
function S.Own:is_mutable() return false end
function S.OwnMut:is_mutable() return true end
function S.Capability:abi(shape) return shape:ctype() end
function S.Mut:abi(shape) return CT.Pointer(shape:ctype()) end
local function symbol(name)
    assert(type(name) == 'string' and name:match('^[A-Za-z_][A-Za-z_0-9]*$'), 'invalid host C symbol')
    assert(not name:match('^let_') and not name:match('^letbody_'), 'host symbol uses compiler-reserved prefix')
    return name
end
local function sorted(t) local keys = {}; for k in pairs(t or {}) do keys[#keys + 1] = k end; table.sort(keys); return keys end
local M = {}
function M.install(program, options)
    options = options or {}
    program.resources, program.hosts, program.destructors = {}, L(), L()
    program.shapes = { Int = S.Int, Bool = S.Bool, Unit = S.Unit }
    local seen = {}
    for _, name in ipairs(sorted(options.resources)) do
        assert(not program.shapes[name], 'duplicate resource constraint ' .. name)
        local drop = symbol(options.resources[name].destroy)
        assert(not seen[drop], 'duplicate host C symbol ' .. drop); seen[drop] = true
        local shape = S.Resource(name, drop)
        program.resources[name], program.shapes[name] = shape, shape
        program.destructors:insert(shape)
    end
    local caps = { read = S.Read, mut = S.Mut, own = S.Own, ['own mut'] = S.OwnMut }
    for _, name in ipairs(sorted(options.hosts)) do
        local config = options.hosts[name]
        assert(name:match('^[A-Za-z_][A-Za-z_0-9]*$'), 'invalid host name')
        assert(config.purity == nil or config.purity == 'ordered', 'host operations currently require ordered purity')
        local c_name = symbol(config.symbol)
        assert(not seen[c_name], 'duplicate host C symbol ' .. c_name); seen[c_name] = true
        local stages = L()
        for _, stage in ipairs(config.stages or {}) do
            local shape = assert(program.shapes[stage.constraint], 'unknown host stage constraint')
            local cap = assert(caps[stage.capability or 'read'], 'unknown host capability')
            stages:insert({ shape = shape, capability = cap })
        end
        local result = assert(program.shapes[config.result or 'Unit'], 'unknown host result constraint')
        local id = #program.hosts + 1
        program.hosts:insert({ name = name, symbol = c_name, stages = stages, result = result })
        program.env[name] = S.Binding(S.Host(id), false)
    end
end
function M.declarations(program)
    local functions = L()
    program.drop_ids = {}
    for i, host in ipairs(program.hosts) do
        host.callable = #program.exports + i
        local types = L()
        for _, stage in ipairs(host.stages) do types:insert(stage.capability:abi(stage.shape)) end
        local result = host.result ~= S.Unit and host.result:ctype() or nil
        functions:insert(T.Function(host.callable, host.symbol, false, true, types, result, nil))
    end
    for i, shape in ipairs(program.destructors) do
        local id = #program.exports + #program.hosts + i
        program.drop_ids[shape] = id
        functions:insert(T.Function(id, shape.destructor, false, true, L{shape:ctype()}, nil, nil))
    end
    return functions
end
function S.Host:abstract() return I.Host(self.id) end
function I.Host:scalar(span) fail(span, 'expected data, got host word') end
function I.Host:specialize(_, _, span) fail(span, 'host specialization is not supported; wrap the host word in a source word') end
function I.Host:invoke(ctx, arguments, span)
    local host = ctx.solver.program.hosts[self.id]
    if #arguments ~= #host.stages then fail(span, 'host invocation must exactly saturate its stages') end
    for i, arg in ipairs(arguments) do ctx:require(arg:infer(ctx), host.stages[i].shape, span) end
    return ctx:scalar(host.result)
end
return M

