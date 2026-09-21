if type(jit) ~= "table" then error("The Lua Word DSL requires LuaJIT", 0) end
local Eval = require("word.eval")
local C = require("word.c")
local D = require("word.diagnostic")
local Model = require("word.model")
local M = { todo = D.todo, todos = D.todos, is_diagnostic = D.is, c_name = C.name,
    c_type_name = C.type_name, c_field_name = C.field_name, c_result_type_name = C.result_type_name }
local Session = {}
Session.__index = Session

function M.new(options)
    local engine = Eval.new(options)
    return setmetatable({ _engine = engine, word = engine.word, U32 = engine.U32,
        Bool = engine.Bool, Unit = engine.Unit, Type = engine.Type }, Session)
end
function Session:load(path)
    return self._engine.scope:load(path, path, self._engine.prelude, true)
end
function Session:load_string(source, name)
    return self._engine.scope:load(source, name or "=(word module)", self._engine.prelude, false)
end
function Session:normalize(value) return self._engine:unpack_result(self._engine:normalize(value)) end
function Session:type(word) return self._engine:as_type(word) end
function Session:value(value)
    value = self._engine:scalar(value)
    local p = Model.get(value)
    if p and Model.record(p.type) then return self._engine:unbox_record(value) end
    if not p or p.tag ~= "known" or p.engine ~= self._engine then
        D.reject("expected-known", "Expected a concrete value from this session")
    end
    return p.value
end
function Session:compile(exports) return self._engine:compile(exports) end
function Session:emit_c(exports) return C.emit(self:compile(exports)) end

return M
