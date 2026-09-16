-- The host numeric primitives the compiler needs beyond what Lua gives portably: a signed
-- 64-bit integer value, and rounding a binary64 to binary32. The backend is chosen for the
-- runtime, so nothing above this file names LuaJIT or PUC Lua.
--
-- LuaJIT provides FFI `int64_t` and `float`; PUC Lua 5.3/5.4 provides native 64-bit integers
-- and `string.pack`/`string.unpack`. Lua 5.1 and 5.2 have neither, and are rejected rather than
-- silently miscompiled.
if type(jit) == 'table' then return require('let.numeric_ffi') end
if math and math.maxinteger then return require('let.numeric_native') end
error('Let needs LuaJIT or PUC Lua 5.3+ (a 64-bit integer type)')
