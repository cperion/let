package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('v2'); local A,B,C,L=V.AST,V.Belt,V.C,V.List
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s:\nexpected %q\ngot      %q'):format(message or 'output',expected,actual)); checks=checks+1
end

local directory='v2/test/out'
local read_parameter=B.Parameter(B.Text,A.Read)
local int_parameter=B.Parameter(B.Int,A.Read)
local hosts={
    print_int={symbol='print_int',phase='runtime',purity='ordered',signature=B.Signature(L{int_parameter},L{B.Unit})},
    print_bool={symbol='print_bool',phase='runtime',purity='ordered',signature=B.Signature(L{B.Parameter(B.Bool,A.Read)},L{B.Unit})},
    runtime_int={symbol='runtime_int',phase='runtime',purity='pure',signature=B.Signature(L{int_parameter},L{B.Int})},
    mark={symbol='mark',phase='runtime',purity='ordered',signature=B.Signature(L{read_parameter},L{B.Text})},
}
local host_code=[[
#include <stdio.h>
#include <stdlib.h>
int64_t runtime_int(int64_t value){ return value; }
void print_bool(bool value){ printf("%d\n",value?1:0); }
void print_int(int64_t value){ printf("%lld\n",(long long)value); }
struct let_text mark(struct let_text text){ fwrite(text.data,1,(size_t)text.size,stdout); fputc('\n',stdout); return text; }
void let_trap(char* reason){ fputs("trap: ",stderr); fputs(reason,stderr); fputc('\n',stderr); abort(); }
]]


-- Emits, compiles, links the host implementations, and runs the module initializer.
local function native(name,source,extra_c)
    local program=V.parse(source,name..'.let'):build{hosts=hosts}
    local unit=program:emit{hosts=hosts}
    local declarations=L()
    for _,declaration in ipairs(unit.declarations) do declarations:insert(declaration) end
    declarations:insert(C.Raw(host_code .. '\n' .. (extra_c or '')))
    local includes=L(); for _,include in ipairs(unit.includes) do if include~='stdint.h' then includes:insert(include) end end
    includes:insert('inttypes.h')
    local text=V.print(C.Unit(includes,declarations))
    os.execute('mkdir -p '..directory)
    local path=('%s/%s.c'):format(directory,name)
    local file=assert(io.open(path,'w')); file:write(text); file:close()
    local executable=('%s/%s'):format(directory,name)
    local status=os.execute(('cc -std=c11 -O1 -w -o %s %s > %s/%s.log 2>&1'):format(executable,path,directory,name))
    if status~=0 then
        local log=io.open(('%s/%s.log'):format(directory,name)); local message=log and log:read('*a') or ''
        if log then log:close() end
        error(name .. ' did not compile:\n' .. message,0)
    end
    local pipe=io.popen(executable .. ' 2>&1')
    local output=pipe:read('*a'); pipe:close()
    return output,path
end

-- §17.1 Currying, specialization, and invocation compiled to native code.
local output,path=native('currying',[[
let multiply =
    let x : Int
    let y : Int
    do
        return x * y
    end
let double = multiply 2
let pending = multiply 6 7
let a = double(21)
let b = pending()
let c = multiply(6, 7)
let show = do print_int(a); print_int(b); print_int(c) end
let shown = show()
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'42\n42\n42\n','§17.1 native currying and invocation')

-- §10.2 Private mutable prelude state survives native invocation and stays per-instance.
output=native('counters',[[
let counter =
    let start : Int
    let value mut = start
    do
        value = value + 1;
        print_int(value)
        return value
    end
let errors = counter 0
let first = errors()
let second = errors()
let requests = counter 100
let third = requests()
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'1\n2\n101\n','§10.2 native interior mutable state')

-- A value the compiler cannot know keeps the real call path: entry function, argument
-- packet and arithmetic helper all survive, and the result is still correct.
output=native('runtime_call',[[
let multiply = let x : Int let y : Int do return x * y end
let seed = runtime_int(6)
let product = multiply(seed, 7)
let show = do print_int(product) end
let shown = show()
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'42\n','runtime arguments still take the emitted call path')

-- Runtime interior state must thread through invocations rather than fold.
output=native('runtime_state',[[
let counter =
    let start : Int
    let value mut = start
    do
        value = value + 1;
        print_int(value);
        return value
    end
let errors = counter runtime_int(0)
let first = errors()
let second = errors()
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'1\n2\n','runtime interior state persists across invocations')

-- §6.2 Prelude effects reached between stages precede the following argument.
output=native('preludes',[[
let staged =
    let first
    let prelude = mark("prelude")
    let second
    do
        return {}
    end
let result = staged(mark("first"), mark("second"))
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'first\nprelude\nsecond\n','§6.2 native prelude ordering')

-- §6.5 Proper tail invocation: 200000 transfers must not grow the native stack.
output=native('tail',[[
let countdown =
    let n : Int
    do
        if n == 0 do
            return 0
        end
        return countdown(n - 1)
    end
let answer = countdown(200000)
let show = do print_int(answer) end
let shown = show()
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'0\n','§6.5 native bounded tail transfer')

-- §13.2 Int arithmetic wraps at 64 bits and traps on a zero divisor.
output=native('arithmetic',[[
let big = 9223372036854775807 + 1
let quotient = -7 / 2
let remainder = -7 % 2
let show = do
    print_int(big); print_int(quotient); print_int(remainder)
end
let shown = show()
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'-9223372036854775808\n-3\n-1\n','§13.2 native wrapping, truncation, dividend sign')

-- §13.3 Text equality compares the UTF-8 byte sequence.
output=native('text',[[
let same = "caf\u{e9}" == "caf\u{e9}"
let different = "a" != "b"
let show = do
    print_bool(same); print_bool(different)
end
let shown = show()
]],'int main(void){ let_fn_1(0); return 0; }')
eq(output,'1\n1\n','§13.3 native Text equality')

-- §14.2 A violated contract leaves through the embedding host's trap hook.
output=native('trap',[[
let quotient = 1 / 0
let show = do print_int(quotient) end
let shown = show()
]],'int main(void){ let_fn_1(0); return 0; }')
check(output:find('trap: division by zero',1,true)~=nil,'§14.2 native division trap')

print(('passed %d v2 native compilation checks (source in %s)'):format(checks,path))
