-- Float (§13.3): literals, arithmetic, comparisons and the IEEE edge cases, checked by the
-- belt interpreter and by native C. A Float operation that folded differently from native
-- execution would print a different bit pattern rather than merely look wrong.
package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,L=V.AST,V.Belt,V.List
local execute=require('test.execute')
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s: expected %s, got %s'):format(message or 'value',tostring(expected),tostring(actual)))
    checks=checks+1
end

-- Builds a program and exposes each exported word as a callable the interpreter runs.
local function build(source)
    local program,builder=V.parse(source,'float.let'):build{}
    program:verify_flow{}
    local entries={}
    for _,entry in ipairs(builder.host_entries or {}) do entries[entry.name]=entry end
    local function call(name,...)
        local entry=assert(entries[name],'no host entry for ' .. name)
        return execute(program.functions[entry.id],{...},{},100000,program.functions)
    end
    return {program=program,entries=entries,call=call,
        namespace=function() return (execute(program.functions[1],{},{},100000,program.functions)) end}
end

-- §2.2 The four spellings the grammar admits, each preserved as a binary64 value.
local host=build[[
let a = 1.5
let b = 1_000.25
let c = 1e9
let d = 1.5e-3
let e = 6.02E23
]]
local namespace=host.namespace()
eq(namespace.fields[1],1.5,'a dotted Float literal')
eq(namespace.fields[2],1000.25,'underscores between Float digits')
eq(namespace.fields[3],1e9,'an exponent without a dot')
eq(namespace.fields[4],1.5e-3,'a signed exponent')
eq(namespace.fields[5],6.02e23,'an upper-case exponent')

-- §13.3 Arithmetic returns Float and never traps on zero: it is IEEE, not Int.
host=build[[
let add = let x : Float do : Float return x + 1.5 end
let sub = let x : Float do : Float return x - 2.0 end
let mul = let x : Float do : Float return x * 3.0 end
let div = let x : Float do : Float return x / 2.0 end
let neg = let x : Float do : Float return -x end
let byzero = let x : Float do : Float return 1.0 / x end
]]
eq(host.call('add',1.0),2.5,'Float addition')
eq(host.call('sub',5.0),3.0,'Float subtraction')
eq(host.call('mul',4.0),12.0,'Float multiplication')
eq(host.call('div',5.0),2.5,'Float division')
eq(host.call('neg',1.5),-1.5,'unary negation')
eq(host.call('byzero',0.0),1/0,'division by zero is an infinity, not a trap')
eq(host.call('byzero',-0.0),-1/0,'and keeps the sign of zero')

-- §13.3 Comparisons and equality follow IEEE: NaN is unequal to everything, and signed
-- zero is equal to zero.
host=build[[
let less = let x : Float do : Bool return x < 1.0 end
let leq = let x : Float do : Bool return x <= 1.0 end
let equal = let x : Float do : Bool return x == 1.0 end
let unequal = let x : Float do : Bool return x != 1.0 end
let selfeq = let x : Float do : Bool return x == x end
let zero = let x : Float do : Bool return x == 0.0 end
]]
eq(host.call('less',0.5),true,'Float less-than')
eq(host.call('less',1.5),false,'Float less-than is false above')
eq(host.call('leq',1.0),true,'Float less-or-equal')
eq(host.call('equal',1.0),true,'Float equality')
eq(host.call('zero',-0.0),true,'negative zero equals zero')
eq(host.call('unequal',1.0),false,'Float inequality')
eq(host.call('selfeq',0/0),false,'a NaN is unequal to itself')
eq(host.call('less',0/0),false,'a NaN is not less than anything')

-- §13.2 Explicit conversion, not promotion: mixing Int and Float, or `%`, is rejected.
local function rejects(source)
    local ok=pcall(function() V.parse(source,'float.let'):build{} end)
    assert(not ok,'expected a rejection: ' .. source)
    checks=checks+1
end
rejects('let x = 1 + 1.0')
rejects('let x = 1.0 + 1')
rejects('let x = 1.0 % 2.0')
-- A word body is built when it is invoked, so the mix is reached by applying it.
rejects('let f = let y : Int do : Int return y * 2.0 end\nlet x = f(3)')
rejects('let x = float(1.5)')
rejects('let x = int(1)')
rejects('let x = float(1, 2)')

-- §13.3 The core conversions are ordinary names: `float` widens and `int` narrows, both pure
-- and total. `int` truncates toward zero, saturates at the Int bounds and maps NaN to zero.
host=build[[
let widen = let n : Int do : Float return float(n) * 0.5 end
let narrow = let x : Float do : Int return int(x) end
let big = 9007199254740993
let rounded = float(big)
let shadow = do : Int
    let float = let n : Int do : Int return n + 1 end
    return float(2)
end
]]
eq(host.call('widen',7),3.5,'float(Int) widens explicitly')
eq(host.call('narrow',3.9),3,'int(Float) truncates toward zero')
eq(host.call('narrow',-3.9),-3,'and toward zero below zero')
eq(tostring(host.call('narrow',1e300)),'9223372036854775807LL','int saturates at the upper bound')
eq(tostring(host.call('narrow',-1e300)),'-9223372036854775808LL','int saturates at the lower bound')
eq(host.call('narrow',0/0),0,'a NaN narrows to zero')
local converted=host.namespace()
eq(tostring(converted.fields[3]),'9007199254740993LL','an Int literal keeps 2^53+1 exactly')
eq(converted.fields[4],9007199254740992.0,'float rounds it to the nearest binary64')
eq(host.call('shadow'),3,'a lexical binding named float shadows the conversion')
local juxtaposed=V.parse('let seven = float 7','float.let'):build{}
check(V.print(juxtaposed:emit{}):find('0x1.cp+2',1,true)~=nil,'float by juxtaposition is the same conversion')

-- A pure Float producer folds to a constant, so the C carries the value, not the arithmetic.
for _,case in ipairs{
    {'let x = 1.0 + 2.0','0x1.8p+1','Float arithmetic folds'},
    {'let x = 1.0 / 0.0','INFINITY','a folded infinity prints as INFINITY'},
    {'let x = 0.0 / 0.0','NAN','a folded NaN prints as NAN'},
    {'let x = -0.0','-0x0p+0','negative zero keeps its sign'},
} do
    local program=V.parse(case[1],'float.let'):build{}
    local text=V.print(program:emit{})
    check(text:find(case[2],1,true)~=nil,case[3])
end

-- Native execution: the emitted C must agree with the interpreter down to the IEEE cases.
local native=[[
let area = let r : Float do : Float return r * r * 3.0 end
let neg = let x : Float do : Float return -x end
let lt = let x : Float do : Bool return x < 2.0 end
let scale = let x : Float do : Float return x * 2.0 end
let half = let x : Float do : Float return x / 2.0 end
let divzero = let x : Float do : Float return x / 0.0 end
let nan = 0.0 / 0.0
let inf = 1.0 / 0.0
let widen = let n : Int do : Float return float(n) * 0.5 end
let narrow = let x : Float do : Int return int(x) end
let sat = let x : Float do : Int return int(x) end
]]
local program,builder=V.parse(native,'float_native.let'):build{}
program:verify_flow{}
local stem='/tmp/let_float_native'
local out=assert(io.open(stem .. '.c','wb'))
out:write(V.print(program:emit{entries=builder.host_entries}))
out:write([[
void let_trap(char* reason){ (void)reason; __builtin_trap(); }
int main(void){
    let_module_init();
    if (let_area_host(2.0)!=12.0) return 1;
    if (let_neg_host(1.5)!=-1.5) return 2;
    if (let_lt_host(1.0)!=true) return 3;
    if (let_lt_host(3.0)!=false) return 4;
    if (let_scale_host(3.0)!=6.0) return 5;
    if (let_half_host(5.0)!=2.5) return 6;
    if (let_divzero_host(1.0)!=INFINITY) return 7;
    if (let_divzero_host(-1.0)!=-INFINITY) return 8;
    double n=let_divzero_host(0.0);
    if (n==n) return 9;
    if (let_widen_host(7)!=3.5) return 10;
    if (let_narrow_host(3.9)!=3) return 11;
    if (let_narrow_host(-3.9)!=-3) return 12;
    if (let_sat_host(1e300)!=INT64_MAX) return 13;
    if (let_sat_host(-1e300)!=INT64_MIN) return 14;
    if (let_sat_host(0.0/0.0)!=0) return 15;
    return 0;
}
]])
out:close()
local status=os.execute(('cc -std=c11 -O1 -w -lm %s.c -o %s && %s'):format(stem,stem,stem))
eq(status,0,'native Float arithmetic, comparisons and IEEE zero division')

print(('passed %d Float checks'):format(checks))
