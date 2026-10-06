-- LuaJIT binding for the shared C residual-DAG optimizer.
-- This file contains no ABC semantics: CLI and frontend callers invoke abc_optimize.
local ffi = require("ffi")
local D = require("let.diag")

ffi.cdef [[
typedef struct {
    int status;
    uint32_t offset;
    uint8_t reason;
    char message[192];
} abc_error;
typedef struct { uint32_t output_offset, input_offset; } abc_provenance;
int abc_optimize(const void *bytes, size_t size, void **output, size_t *output_size, abc_error *error);
int abc_optimize_mapped(const void *bytes, size_t size, void **output, size_t *output_size, abc_provenance **provenance, size_t *provenance_count, abc_error *error);
void abc_optimized_free(void *bytes);
const char *abc_status_name(int status);
]]

local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = source:match("^(.*)/[^/]+$") or "."
local root = directory .. "/../.."
local library = os.getenv("ABC_OPT_LIBRARY") or (root .. "/build/libabc-opt.so")
local ok, C = pcall(ffi.load, library)
if not ok then
    D.internal("abc-opt-host", "Cannot load the shared ABC optimizer at `" .. library .. "`: " .. tostring(C))
end

local M = {}
local function optimize(bytes, mapped)
    if type(bytes) ~= "string" then D.bug("abc-opt-input", "ABC optimizer input must be a byte string") end
    local output, size, error = ffi.new("void *[1]"), ffi.new("size_t[1]"), ffi.new("abc_error[1]")
    local provenance, count = ffi.new("abc_provenance *[1]"), ffi.new("size_t[1]")
    local status = mapped and C.abc_optimize_mapped(bytes, #bytes, output, size, provenance, count, error)
        or C.abc_optimize(bytes, #bytes, output, size, error)
    if status ~= 0 then
        local name = ffi.string(C.abc_status_name(status)); local message = ffi.string(error[0].message)
        D.bug("abc-opt-" .. name, string.format("ABC optimization failed at byte 0x%x: %s", error[0].offset, message))
    end
    local result = ffi.string(output[0], size[0]); C.abc_optimized_free(output[0])
    if not mapped then return result end
    local map = {}
    for i = 0, tonumber(count[0]) - 1 do map[tonumber(provenance[0][i].output_offset)] = tonumber(provenance[0][i].input_offset) end
    C.abc_optimized_free(provenance[0]); return result, map
end
function M.optimize(bytes) return optimize(bytes, false) end
function M.optimizeMapped(bytes) return optimize(bytes, true) end
return M
