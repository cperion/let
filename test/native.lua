package.path='./?.lua;./?/init.lua;' .. package.path
local V=require('let'); local A,B,C,L=V.AST,V.Belt,V.C,V.List
local checks=0
local function check(value,message) assert(value,message); checks=checks+1 end
local function eq(actual,expected,message)
    assert(actual==expected,('%s:\nexpected %q\ngot      %q'):format(message or 'output',expected,actual)); checks=checks+1
end

local directory='test/out'
local read_parameter=B.Parameter(B.Text,A.Read)
local int_parameter=B.Parameter(B.Int,A.Read)
local hosts={
    print_int={symbol='print_int',phase='runtime',purity='ordered',signature=B.Signature(L{int_parameter},L{B.Unit})},
    print_bool={symbol='print_bool',phase='runtime',purity='ordered',signature=B.Signature(L{B.Parameter(B.Bool,A.Read)},L{B.Unit})},
    runtime_int={symbol='runtime_int',phase='runtime',purity='pure',signature=B.Signature(L{int_parameter},L{B.Int})},
    open={symbol='open',phase='runtime',purity='ordered',signature=B.Signature(L{int_parameter},L{B.Named('Box')})},
    open_buffer={symbol='open_buffer',phase='runtime',purity='ordered',signature=B.Signature(L{int_parameter},L{B.Named('Buffer')})},
    write_byte={symbol='write_byte',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(B.Named('Buffer'),A.Mut),int_parameter,int_parameter},L{B.Unit})},
    consume_buffer={symbol='consume_buffer',phase='runtime',purity='ordered',
        signature=B.Signature(L{B.Parameter(B.Named('Buffer'),A.Own)},L{B.Unit})},
    mark={symbol='mark',phase='runtime',purity='ordered',signature=B.Signature(L{read_parameter},L{B.Text})},
}
local host_code=[[
#include <stdio.h>
#include <stdlib.h>
int64_t runtime_int(int64_t value){ return value; }
int64_t open(int64_t value){ printf("open:%lld\n",(long long)value); return value; }
void close(int64_t value){ printf("close:%lld\n",(long long)value); }
int64_t open_buffer(int64_t n){ printf("open:%lld\n",(long long)n); return 7; }
void write_byte(int64_t* buffer,int64_t index,int64_t value){ printf("write:%lld:%lld\n",(long long)index,(long long)value); }
void consume_buffer(int64_t buffer){ printf("consume:%lld\n",(long long)buffer); }
void close_buffer(int64_t buffer){ printf("close_buffer:%lld\n",(long long)buffer); }
void print_bool(bool value){ printf("%d\n",value?1:0); }
void print_int(int64_t value){ printf("%lld\n",(long long)value); }
]]
-- A host that takes or returns `Text` is compiled in this unit, so its implementation needs
-- the struct. The generated C declares it only when the program uses Text, so this follows.
local text_host_code=[[
struct let_text mark(struct let_text text){ fwrite(text.data,1,(size_t)text.size,stdout); fputc('\n',stdout); return text; }
]]
local trap_code=[[
void let_trap(char* reason){ fputs("trap: ",stderr); fputs(reason,stderr); fputc('\n',stderr); abort(); }
]]


-- Emits, compiles, links the host implementations, and runs the module initializer.
local modules={
    ['math.let']='let add = let x : Int let y : Int do : Int return x + y end\n'..
                 'let negate = let x : Int do : Int return -x end',
    ['codec.let']='let scale : Int\nlet factor = scale * 2;\n{ let encode = factor }',
}
local function native(name,source,extra_c,extra_options)
    local build_options={hosts=hosts,resources={Box={destroy='close'},Buffer={destroy='close_buffer'}},
        resolve=function(path) local text=modules[path]; if text then return {text=text,file=path} end end}
    for key,value in pairs(extra_options or {}) do build_options[key]=value end
    local program=V.parse(source,name..'.let'):build(build_options)
    local unit=program:emit(build_options)
    local declarations=L()
    for _,declaration in ipairs(unit.declarations) do declarations:insert(declaration) end
    local has_text=false
    for _,declaration in ipairs(unit.declarations) do
        if C.Struct:isclassof(declaration) and declaration.name=='let_text' then has_text=true end
    end
    declarations:insert(C.Raw(host_code .. '\n' .. (has_text and text_host_code or '') .. '\n' .. trap_code .. '\n' .. (extra_c or '')))
    local includes=L(); for _,include in ipairs(unit.includes) do if include~='stdint.h' then includes:insert(include) end end
    includes:insert('inttypes.h')
    local text=V.print(C.Unit(includes,declarations))
    os.execute('mkdir -p '..directory)
    local path=('%s/%s.c'):format(directory,name)
    local file=assert(io.open(path,'w')); file:write(text); file:close()
    local executable=('%s/%s'):format(directory,name)
    -- Lua 5.2+ returns (true,"exit",0) instead of 0, so normalize the status.
    local executed,_,code=os.execute(('cc -std=c11 -O1 -w -o %s %s > %s/%s.log 2>&1'):format(executable,path,directory,name))
    local status=(type(executed)=='number') and executed or (executed and 0 or (code or 1))
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
    do : Int
        return x * y
    end
let double = multiply 2
let pending = multiply 6 7
let a = double(21)
let b = pending()
let c = multiply(6, 7)
let show = do : Unit print_int(a); print_int(b); print_int(c) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'42\n42\n42\n','§17.1 native currying and invocation')

-- §10.2 Private mutable prelude state survives native invocation and stays per-instance.
output=native('counters',[[
let counter =
    let start : Int
    let value mut = start
    do : Int
        value = value + 1;
        print_int(value)
        return value
    end
let errors = counter 0
let first = errors()
let second = errors()
let requests = counter 100
let third = requests()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'1\n2\n101\n','§10.2 native interior mutable state')

-- A value the compiler cannot know keeps the real call path: entry function, argument
-- packet and arithmetic helper all survive, and the result is still correct.
output=native('runtime_call',[[
let multiply = let x : Int let y : Int do : Int return x * y end
let seed = runtime_int(6)
let product = multiply(seed, 7)
let show = do : Unit print_int(product) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'42\n','runtime arguments still take the emitted call path')

-- §7.4 `break` and `continue` compile to ordinary edges: the loop, the iteration cleanup, the
-- effect thread and the loop-carried state all survive into C, and the program runs.
output=native('loop_break',[[
let compute = do : Unit
    let x mut = 0
    let total mut = 0
    while x < 10 do
        x = x + 1
        if x == 3 do continue end
        if x == 6 do break end
        total = total + x
    end
    print_int(total)
end
let shown = compute()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'12\n','§7.4 native break and continue')

-- Runtime interior state must thread through invocations rather than fold.
output=native('runtime_state',[[
let counter =
    let start : Int
    let value mut = start
    do : Int
        value = value + 1;
        print_int(value);
        return value
    end
let errors = counter runtime_int(0)
let first = errors()
let second = errors()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'1\n2\n','runtime interior state persists across invocations')

-- §8 and §17.3 Aggregates, projection, indexing and a projected word member reach C.
output=native('aggregates',[[
let arithmetic = {
    let add = let x : Int let y : Int do : Int return x + y end
    let negate = let x : Int do : Int return -x end
}
let point = { let x = 10 let y = 20 }
let rgb = { 255, 128, 32 }
let show = do : Unit
    print_int(arithmetic.add(40, 2));
    print_int(point.x + point.y);
    print_int(rgb[1]);
    return {}
end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'42\n30\n128\n','§8/§17.3 aggregates, projection and projected word invocation')

-- §8.5 Owned members are destroyed in reverse initialization order in the emitted C.
output=native('aggregate_ownership',[[
let show = do : Unit
    let pair = { let first = open(1) let second = open(2) };
    let nested = { let inner = { open(3), open(4) } };
    return {}
end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'open:1\nopen:2\nopen:3\nopen:4\nclose:4\nclose:3\nclose:2\nclose:1\n',
    '§8.5 native reverse member destruction')

-- Loop widening must not mistake a varying value for a constant. Because this witness is
-- executed, an unsound fold would print a wrong number rather than merely look odd.
output=native('loop_widening',[[
let run = do : Int
    let i mut = 0;
    let acc mut = 0;
    while i < runtime_int(5) do
        i = i + 1;
        acc = acc + i
    end
    return acc
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'15\n','a widened loop computes at runtime instead of folding')

-- A loop-invariant value stays known inside the loop, so work on it is folded away.
output=native('loop_invariant',[[
let run = do : Int
    let bias = 7;
    let total mut = 0;
    let i mut = 0;
    while i < 3 do
        total = total + bias * 2;
        i = i + 1
    end
    return total
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'42\n','a loop-invariant folds while the loop still runs')

-- A stateful word carried across a loop backedge: the record travels as a loop packet and
-- its interior state must survive every iteration.
output=native('loop_stateful',[[
let run = do : Int
    let counter = let start : Int let value mut = start do : Int value = value + 1; return value end
    let c = counter runtime_int(0)
    let total mut = 0
    let i mut = 0
    while i < runtime_int(4) do
        total = total + c();
        i = i + 1
    end
    return total
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'10\n','a stateful word invoked in a loop carries its state across the backedge')

-- §15.2 File chains and imports reach native code: an imported namespace is an ordinary
-- aggregate whose word members are projected and invoked, and a configurable file is
-- specialized at its import site.
output=native('modules',[[
let math = import "math.let"
let codec = import "codec.let" 21
let total = math.add(40, 2) + math.negate(7) + codec.encode
let show = do : Unit print_int(total) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'77\n','§15.2 imported namespaces, word members and a configured file')

-- §15.1 Module unload destroys owned top-level state in reverse successful-construction
-- order. The initializer returns the namespace and the state that owns it; the host holds
-- both and calls unload.
output=native('unload',[[
let first = open(1)
let second = open(2)
let run = do : Int
    let local_pair = { open(3), open(4) };
    return 0
end
let r = run()
]],[[int main(void){ struct let_ret_1 m = let_module_init(); let_module_unload(m.r1); return 0; }]])
eq(output,'open:1\nopen:2\nopen:3\nopen:4\nclose:4\nclose:3\nclose:2\nclose:1\n',
    '§15.1 unload destroys module state in reverse construction order')

-- §15.1 A do terminal is the initialization body: its return is the namespace, while the
-- module's preludes remain the state the host destroys at unload.
output=native('unload_do',[[
let first = open(1)
let second = open(2)
do : { let answer : Int }
    let invisible = open(3);
    return { let answer = 42 }
end
]],[[int main(void){ struct let_ret_1 m = let_module_init(); print_int(m.r0.f0); let_module_unload(m.r1); return 0; }]])
eq(output,'open:1\nopen:2\nopen:3\nclose:3\n42\nclose:2\nclose:1\n',
    '§15.1 a do terminal returns its namespace and unloads its prelude state')

output=native('unload_do_view',[[
let first = open(1)
let second = open(2)
do : { let shown : Box }
    return { let shown = move first }
end
]],[[int main(void){ struct let_ret_1 m = let_module_init(); let_module_unload(m.r1); return 0; }]])
eq(output,'open:1\nopen:2\nclose:2\nclose:1\n','§15.1 a do terminal that moves a prelude still owns it once')

-- A written terminal is a view over the preludes, so a moved owned prelude is still
-- destroyed once, at its original construction position.
output=native('unload_view',[[
let first = open(1)
let hidden = open(2);
{ let shown = move first }
]],[[int main(void){ struct let_ret_1 m = let_module_init(); let_module_unload(m.r1); return 0; }]])
eq(output,'open:1\nopen:2\nclose:2\nclose:1\n','§15.1 a written terminal does not duplicate ownership')

-- §6.3 A user word with an `own` stage takes the argument from the call site and destroys it
-- once -- not from a host, and not before the callee runs.
output=native('own_stage',[[
let drop =
    let buffer own : Buffer
    do : Int return 0 end
let run = do : Int
    let b = open_buffer(8);
    return drop(move b)
end
let answer = run()
]],[[int main(void){ let_module_init(); return 0; }]])
eq(output,'open:8\nclose_buffer:7\n','§6.3 a user word owns and destroys its own-stage argument once')

-- §11.1 a word-typed stage: its arrow signature is the word the argument supplies, so the
-- word chosen at the call site is the one that runs.
output=native('executable',[[
let success = let value : Int do : Int return value end
let failure = let code : Int do : Int return -code end
let checked_divide =
    let ok : Int -> do Int
    let bad : Int -> do Int
    let numerator : Int
    let denominator : Int
    do : Int
        if denominator == 0 do
            return bad(1)
        else
            return ok(numerator / denominator)
        end
    end
let divide = checked_divide success failure
let run = do : Int
    print_int(divide(84, 2));
    print_int(divide(1, 0));
    return 0
end
let shown = run()
]],[[int main(void){ let_module_init(); return 0; }]])
eq(output,'42\n-1\n','§11.1 a word-typed stage runs the word its argument supplied')

-- §11.5 Tagged unions: `T = A or B` is a type word with derived injections `T.left`/`T.right`;
-- the value carries a tag, projection reads the active alternative, and `switch` eliminates it.
output=native('sums',[[
let run = do : Unit
    let Opt = Int or Int
    let a : Opt = Opt.left 65;
    let b : Opt = Opt.right 66;
    switch a.tag do
    case 0 print_int(a.left)
    case 1 print_int(0)
    else print_int(0)
    end
    switch b.tag do
    case 0 print_int(0)
    case 1 print_int(b.right)
    else print_int(0)
    end
end
let shown = run()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'65\n66\n','§11.5 tagged unions: injection, tag, projection and switch')

-- §4.2 Self recursion that is not a tail call: the recursive call returns whatever the
-- word returns, so its result type comes from the word itself.
output=native('recursion',[[
let factorial = let n : Int do : Int
    if n == 0 do return 1 end
    return n * factorial(n - 1)
end
let fib = let n : Int do : Int
    if n < 2 do return n end
    return fib(n - 1) + fib(n - 2)
end
let show = do : Unit print_int(factorial(5)); print_int(fib(10)) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'120\n55\n','§4.2 non-tail self recursion, including two recursive calls')

-- §4.2 and §7: a self reference is resolvable inside any nested control block, and the result
-- type a word's returns state is used even when construction reaches the self call first.
output=native('recursion_branch',[[
let digits = let n : Int
do : Unit
    if n >= 10 do digits(n / 10) end
    print_int(n % 10)
end
let show = do : Unit digits(123) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'1\n2\n3\n','§4.2 a recursive call inside a control block')

-- §15.1: a module whose do terminal splits the CFG still builds its state record from the
-- current prelude bindings, not from handles captured before the terminal ran.
output=native('prelude_terminal',[[
let counter =
    let start : Int
    let value mut = start
    do : Int
        value = value + 1
        return value
    end
let errors = counter 0
do : Unit
    if 1 < 2 do print_int(errors()) end
    print_int(errors())
    return
end
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'1\n2\n','§15.1 a module do terminal with control flow and a prelude')

-- §17.4 A mutable stage lends the caller's place: the host receives a pointer and its write
-- is visible in the caller afterwards.
output=native('mut_place',[[
let bump = let counter mut : Int let by : Int do : Int counter = counter + by; return counter end
let run = do : Int
    let n mut = 40;
    let r = bump(mut n, 2);
    return r + n
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'84\n','§17.4 a mutable stage writes the caller place through a pointer')

-- §17.4's ownership example: lending a place, then moving the resource out of it.
events={}
output=native('ownership_lend',[[
let example = do : Unit
    let buffer mut = open_buffer(1024);
    write_byte(mut buffer, 0, 42);
    consume_buffer(move buffer)
end
let r = example()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'open:1024\nwrite:0:42\nconsume:7\n','§17.4 borrow then move, in that order')

-- §10.1 A non-escaping word captures an owned binding as a borrow, so the two share state.
output=native('capture',[[
let counter = let start : Int let v mut = start do : Int v = v + 1; return v end
let c = counter 0
let f = do : Int let r = c(); return r end
let a = f()
let b = f()
let d = c()
let show = do : Unit print_int(a); print_int(b); print_int(d) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'1\n2\n3\n','§10.1 a captured word shares its owner state: 1, 2, then 3')

-- §9.3 A projected member is a place too: the callee receives a pointer to the owner's
-- field, and the owner sees the write.
output=native('projected_borrow',[[
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let run = do : Int
    let a mut = { let x = 1 let y = 2 };
    let r = bump(mut a.x, 40);
    return a.x + r
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'82\n','§9.3 a mutable borrow of a projected member')

-- §8.4 A runtime index selects among the members, and §9.4 indexed assignment writes the
-- selected member. The out-of-range case traps, so it is not silently ignored.
output=native('dynamic_index',[[
let run = do : Int
    let a mut = { 1, 2, 3 };
    let i mut = 0;
    let total mut = 0;
    while i < 3 do
        a[i] = a[i] * 10;
        total = total + a[i];
        i = i + 1
    end
    return total
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'60\n','§8.4/§9.4 a runtime index and indexed assignment')

-- §9.4 A nested assignment rebuilds each level of the path, so the write lands in the
-- member it names and every sibling survives it.
output=native('nested_assignment',[[
let run = do : Int
    let a mut = { let b mut = { let c mut = 1 let d = 2 } };
    a.b.c = 40;
    return a.b.c + a.b.d
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'42\n','§9.4 native assignment to a nested member')

-- §9.4 A run-time index in the middle of an assignment path: the suffix after the index is
-- resolved against the selected member, and each level is rebuilt on the way back up.
output=native('midpath_index',[[
let run = do : Int
    let values mut = { { 1, 2 }, { 3, 4 } };
    let i mut = 0;
    while i < 2 do
        values[i][1] = values[i][0] * 10;
        i = i + 1
    end
    return values[0][1] + values[1][1]
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'40\n','§9.4 native assignment through a mid-path run-time index')

-- §9.2 A plain stage receives a read-only borrow for the invocation, so a non-Copy
-- argument is still the caller's afterwards and is released once, by the caller. If the
-- callee owned it, the release would appear before the consume, or twice.
output=native('borrowed_argument',[[
let look = let b : Buffer do : Int return 0 end
let run = do : Int
    let b = open_buffer(1);
    let n = look(b);
    consume_buffer(move b);
    return n
end
let answer = run()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'open:1\nconsume:7\n','§9.2 native plain stage borrows and the caller releases')

-- §9.2 A move on one branch only makes the aggregate partially initialized on that path, so
-- the flag is a run-time fact and the destruction of that subplace is guarded. An unguarded
-- or inverted guard shows up here as a second release or a missing one.
output=native('conditional_move',[[
let run = do : Int
    let pair = { let first = open(1) let second = open(2) };
    let k = 1;
    if k == 1 do
        let gone = move pair.first;
    end
    return 0
end
let ran = run()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'open:1\nopen:2\nclose:1\nclose:2\n','§9.2 native guarded release after a conditional move')

output=native('conditional_move_kept',[[
let run = do : Int
    let pair = { let first = open(1) let second = open(2) };
    let k = 2;
    if k == 1 do
        let gone = move pair.first;
    end
    return 0
end
let ran = run()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'open:1\nopen:2\nclose:2\nclose:1\n','§9.2 native release of a subplace that was not moved')

-- §9.2 Moving one subplace out of an aggregate hands that resource to the new binding: one
-- release per buffer, by whichever binding owns it, and the other members are untouched.
output=native('partial_move',[[
let run = do : Int
    let pair = { let first = open(1) let second = open(2) };
    let moved = move pair.first;
    return 0
end
let ran = run()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'open:1\nopen:2\nclose:1\nclose:2\n','§9.2 native partial move releases each resource once')

-- §9.3 A runtime index inside a borrowed path selects a place, so the callee writes the
-- member the index names.
output=native('dynamic_borrow',[[
let bump = let p mut : Int let by : Int do : Int p = p + by; return p end
let run = do : Int
    let a mut = { 1, 2, 3 };
    let i mut = 0;
    while i < 3 do
        bump(mut a[i], 1);
        i = i + 1
    end
    return a[0] + a[1] + a[2]
end
let answer = run()
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'9\n','§9.3 a mutable borrow through a runtime index')

-- §6.2 Prelude effects reached between stages precede the following argument.
output=native('preludes',[[
let staged =
    let first : Text
    let prelude = mark("prelude")
    let second : Text
    do : Unit
        return {}
    end
let result = staged(mark("first"), mark("second"))
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'first\nprelude\nsecond\n','§6.2 native prelude ordering')

-- §6.5 Proper tail invocation: 200000 transfers must not grow the native stack.
output=native('tail',[[
let countdown =
    let n : Int
    do : Int
        if n == 0 do
            return 0
        end
        return countdown(n - 1)
    end
let answer = countdown(200000)
let show = do : Unit print_int(answer) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'0\n','§6.5 native bounded tail transfer')

-- §13.2 Int arithmetic wraps at 64 bits and traps on a zero divisor.
output=native('arithmetic',[[
let big = 9223372036854775807 + 1
let quotient = -7 / 2
let remainder = -7 % 2
let show = do : Unit
    print_int(big); print_int(quotient); print_int(remainder)
end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'-9223372036854775808\n-3\n-1\n','§13.2 native wrapping, truncation, dividend sign')

-- §13.3 Text equality compares the UTF-8 byte sequence.
output=native('text',[[
let same = "caf\u{e9}" == "caf\u{e9}"
let different = "a" != "b"
let show = do : Unit
    print_bool(same); print_bool(different)
end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
eq(output,'1\n1\n','§13.3 native Text equality')

-- §14.2 A violated contract leaves through the embedding host's trap hook.
output=native('trap',[[
let quotient = 1 / 0
let show = do : Unit print_int(quotient) end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }')
check(output:find('trap: division by zero',1,true)~=nil,'§14.2 native division trap')

-- §15.3 A host may state the C prototype it calls, and the C vocabulary lives under `c`: its
-- members take a borrowed `CString` (a `const char*`), and `c.string`/`c.text` are the
-- explicit crossings between that and Let's `Text`. No shim, and no implicit string conflation.
local c_members={}
for name,host in pairs(V.libc.members) do c_members[name]=host end
c_members.greeting={symbol='ffi_greeting',phase='runtime',purity='pure',
    signature=B.Signature(L{},L{B.CString})}
output=native('libc',[[
let n = c.strlen(c.string("hello"))
let g = c.greeting()
let gn = c.strlen(g)
let wrote = c.puts(c.string("from-libc"))
let r = n + gn
let shown = print_int(r)
]],'const char* ffi_greeting(void){ return "hello-from-c"; }\n'..
    'int main(void){ let_module_init(); return 0; }',
    {dictionary={c={members=c_members}},
        resources={Box={destroy='close'},Buffer={destroy='close_buffer'},
            CAlloc=V.libc.resources.CAlloc}})
eq(output,'from-libc\n17\n','§15.3 native libc: `c.strlen`, `c.puts` and `c.string` over a borrowed C string')

-- §12.4 C memory is an owned pointer resource: `c.malloc` returns it and Let destroys it with
-- `free`; `c.memcpy`/`c.memcmp` borrow it. Let never dereferences it, and there is no `c.free`.
local c_memory={dictionary={c={members=V.libc.members}},
    resources={Box={destroy='close'},Buffer={destroy='close_buffer'},CAlloc=V.libc.resources.CAlloc}}
output=native('cmemory',[[
let buffer = c.malloc(6)
let copied = c.memcpy(buffer, c.string("hello"), 6)
let same = c.memcmp(buffer, c.string("hello"), 6)
let shown = c.putchar(48 + same)
]],'int main(void){ let_module_init(); return 0; }',c_memory)
eq(output,'0','§12.4 native C memory: an owned pointer resource, malloc/memcpy/memcmp')

-- A pointer resource is released exactly once, at the exit of the scope that owns it, rather
-- than freed by hand; the destructor's C parameter is the pointer, not a handle.
local tracked_members={}
for name,host in pairs(V.libc.members) do tracked_members[name]=host end
tracked_members.alloc={symbol='ffi_alloc',phase='runtime',purity='ordered',
    signature=B.Signature(L{int_parameter},L{B.Named('Tracked')}), c={params={'size_t'},result='void *'}}
tracked_members.released={symbol='ffi_released',phase='runtime',purity='pure',
    signature=B.Signature(L{},L{B.Int}), c={result='int'}}
output=native('cownership',[[
let allocate = do : Int
    let a = c.alloc(8)
    let b = c.alloc(16)
    return 0
end
let ran = allocate()
let released = c.released()
let shown = c.putchar(48 + released)
]],[[
static int tracked_released=0;
void* ffi_alloc(size_t n){ return malloc(n); }
void ffi_release(void* p){ ++tracked_released; free(p); }
int ffi_released(void){ return tracked_released; }
int main(void){ let_module_init(); return 0; }
]],{dictionary={c={members=tracked_members}},
    resources={Box={destroy='close'},Buffer={destroy='close_buffer'},
        Tracked={destroy='ffi_release',representation='pointer'},
        CAlloc=V.libc.resources.CAlloc}})
eq(output,'2','§12.4 a pointer resource is released once at its scope exit')

-- §12.4 A source `extern` declares a foreign word with no options file at all: the C symbol,
-- the stages with their capabilities, and the result, all in Let.
output=native('extern',[[
extern pure ffi_len (text : CString) : Int

let length = ffi_len(c.string("hello"))
let shown = print_int(length)
]],[[
#include <string.h>
int64_t ffi_len(const char* text){ return (int64_t)strlen(text); }
int main(void){ let_module_init(); return 0; }
]],{dictionary={c={members=V.libc.members}},
    resources={Box={destroy='close'},Buffer={destroy='close_buffer'},
        CAlloc=V.libc.resources.CAlloc}})
eq(output,'5\n','§12.4 a source `extern` declares a foreign word without an options file')

-- §12.4 A type may name its exact C spelling, so a C `int` is declared and converted at the
-- boundary rather than silently widened to the default `int64_t`.
output=native('cwidth',[[
extern pure ffi_at (text : CString, index : Int "int") : Int "int"

let ch = ffi_at(c.string("A"), 0)
let shown = c.putchar(ch)
]],[[
int ffi_at(const char* text, int index){ return text[index]; }
int main(void){ let_module_init(); return 0; }
]],{dictionary={c={members=V.libc.members}},
    resources={Box={destroy='close'},Buffer={destroy='close_buffer'},
        CAlloc=V.libc.resources.CAlloc}})
eq(output,'A','§12.4 a foreign type names its C spelling: `Int "int"`')

-- §12.4 A Text's byte length reaches a C call that takes a pointer and a count, and a borrowed
-- pointer can be tested for null; neither assumes a terminator.
output=native('cbytes',[[
let text = "hi\n"
let written = c.write(1, c.string(text), c.byte_length(text))
let missing = c.null(c.getenv(c.string("LET_NO_SUCH_VARIABLE_XYZ")))
let show = do : Unit if missing do c.putchar(49) else c.putchar(48) end end
let shown = show()
]],'int main(void){ let_module_init(); return 0; }',
    {dictionary={c={members=V.libc.members}},
        resources={Box={destroy='close'},Buffer={destroy='close_buffer'},
            CAlloc=V.libc.resources.CAlloc}})
eq(output,'hi\n1','§12.4 `c.byte_length`, `c.write` and `c.null` over a borrowed view')

-- §12.4 `c.text_of` builds a Text view over a pointer and a length, so a buffer C filled can
-- be read as a Text without a terminator.
output=native('ctextof',[[
let buffer = c.malloc(4)
let copied = c.memcpy(buffer, c.string("abc"), 4)
let text = c.text_of(buffer, 3)
let wrote = c.write(1, c.string(text), c.byte_length(text))
let same = c.strcmp(c.string(text), c.string("abc"))
let shown = c.putchar(48 + same)
]],'int main(void){ let_module_init(); return 0; }',
    {dictionary={c={members=V.libc.members}},
        resources={Box={destroy='close'},Buffer={destroy='close_buffer'},
            CAlloc=V.libc.resources.CAlloc}})
eq(output,'abc0','§12.4 `c.text_of` builds a Text view over a pointer and a length')

-- §12.4 A namespaced `extern` adds a member to a namespace instead of a top-level name.
output=native('nsextern',[[
extern c.ffi_len (text : CString) : Int "size_t"

let n = c.ffi_len(c.string("hello"))
let shown = print_int(n)
]],[[
#include <string.h>
size_t ffi_len(const char* text){ return strlen(text); }
int main(void){ let_module_init(); return 0; }
]],{dictionary={c={members=V.libc.members}},
    resources={Box={destroy='close'},Buffer={destroy='close_buffer'},
        CAlloc=V.libc.resources.CAlloc}})
eq(output,'5\n','§12.4 a namespaced `extern` adds a member to the `c` namespace')

print(('passed %d native compilation checks (source in %s)'):format(checks,path))
