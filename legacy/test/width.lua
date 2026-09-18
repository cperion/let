-- Fixed-width integers: U8 and U32 (§13.2). The width is the language's, not the host's, so
-- every operation computes the mathematical result and then reduces it modulo 2^width; the
-- interpreter oracle and the emitted C must agree on that. `>>` is logical for these unsigned
-- widths, and a shift count is reduced modulo the width.
package.path='./?.lua;./?/init.lua;'..package.path
local V=require('let'); local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

-- Evaluate one expression as a module binding, through construction, emission, and the belt
-- interpreter. Emission is forced so a value the emitter cannot represent is a failure too.
local function eval(expr)
    local program=V.parse('let result = '..expr,'width.let'):build{}
    program:verify_flow{}
    V.print(program:emit{})
    local namespace=execute(program.functions[1],{}, {}, 100000, program.functions)
    return namespace.fields[#namespace.fields]
end
local function number(expr) return V.scalar.int_string(eval(expr)) end
local function truth(expr) return eval(expr)==true end

-- Wrapping arithmetic: the result is reduced modulo 2^width.
eq(number('u32(4294967295) + u32(1)'),'0','U32 addition wraps')
eq(number('u32(0) - u32(1)'),'4294967295','U32 subtraction wraps below zero')
eq(number('u32(4294967295) * u32(4294967295)'),'1','U32 multiplication wraps')
eq(number('u32(65536) * u32(65536)'),'0','U32 multiplication loses the high bits')
eq(number('u32(-1)'),'4294967295','a negative Int truncates to its low 32 bits')
eq(number('u8(255) + u8(1)'),'0','U8 addition wraps')
eq(number('u8(255) * u8(255)'),'1','U8 multiplication wraps')

-- Shifts: the count is modulo the width, `<<` keeps the low bits, and `>>` is logical.
eq(number('u32(1) << u32(31)'),'2147483648','U32 left shift reaches the top bit')
eq(number('u32(1) << u32(32)'),'1','a U32 shift count is modulo 32')
eq(number('u32(2147483648) >> u32(31)'),'1','U32 right shift is logical')
eq(number('u8(255) << u8(8)'),'255','a U8 shift count is modulo 8')
eq(number('u8(128) >> u8(7)'),'1','U8 right shift is logical')

-- Bitwise, complement, division, and remainder.
eq(number('~u32(0)'),'4294967295','U32 complement fills the width')
eq(number('~u8(0)'),'255','U8 complement fills the width')
eq(number('u32(5) & u32(3)'),'1','U32 and')
eq(number('u32(5) | u32(3)'),'7','U32 or')
eq(number('u32(5) ^ u32(3)'),'6','U32 xor')
eq(number('u32(10) / u32(3)'),'3','U32 division')
eq(number('u32(10) % u32(3)'),'1','U32 remainder')

-- Comparisons are unsigned, and the type is Copy.
check(truth('u32(4294967295) > u32(0)'),'U32 comparison is unsigned')
check(truth('u32(7) == u32(7)'),'U32 equality')
check(not truth('u8(255) == u8(254)'),'U8 inequality')

-- Float32 (§13.3) is a binary32: every operation rounds back to binary32, and the conversion
-- from a Float rounds to nearest, ties to even. It is not the binary64 result.
eq(string.format('%.0f',eval('f32(16777217.0)')),'16777216','2^24+1 is not representable in binary32')
check(eval('f32(0.1) + f32(0.2)') ~= 0.1 + 0.2,'Float32 addition rounds to binary32')
check(eval('f32(1.0) / f32(3.0)') == V.scalar.to_f32(1.0/3.0),'Float32 division rounds to binary32')
check(eval('-f32(1.5)') == -1.5,'Float32 negation')
check(truth('f32(1.0) < f32(2.0)'),'Float32 comparison')
check(truth('f32(2.0) == f32(2.0)') and not truth('f32(1.0) == f32(2.0)'),'Float32 equality')

print(('passed %d fixed-width and Float32 checks'):format(checks))
