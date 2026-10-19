-- Source-profile and source-ingestion checks for the real ASDL-based compiler.
-- Both frontends are checked; only SLet executes on the typed-only runtime.
-- Profile-5 execution cases are preserved in
-- research/archive/dynamic-layer-before-typed-teardown/mixed-frontend-tests/compiler.lua.
local source = debug.getinfo(1, "S").source:sub(2)
local here = source:match("^(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. here .. "../?/init.lua;" .. here .. "../../build/?.lua;" .. package.path

local Compiler = require("let.compiler")
local D = require("let.diag")
local checks = 0
local runtimeModes = {slet = {"interpreted", "eager", "lazy"}, let = {}}
local function check(ok, message) assert(ok, message); checks = checks + 1 end

-- Let is checked through real semantic IR, not an invented assembly artifact.
local function checkedLet(options)
  local unit=Compiler.typed(options)
  check(unit.phase=='typed-ir' and #unit.functions>0,'Let source constructs semantic IR: '..options.name)
  local accepted,error=pcall(Compiler.compile,options)
  check(not accepted and D.is(error) and error.code=='dynamic-lowering',
    'Let executable lowering is explicitly unavailable: '..options.name)
  return unit
end
local function checkedSource(options)
  if options.profile=='let' then return checkedLet(options) end
  return Compiler.compile(options)
end
local function hasIR(unit,kind,operation)
  local found=false
  for _,fn in ipairs(unit.functions) do require('let.walk').walk(fn,{enter=function(node)
    if node.kind==kind and (not operation or node.operation and node.operation.kind==operation) then found=true end
  end}) end
  return found
end
local function checkedLetFile(path)
  local graph=Compiler.typedFile(path)
  check(graph.phase=='typed-ir' and #graph.functions>0,'Let imports construct verified IR')
  local accepted,error=pcall(Compiler.compileFile,path)
  check(not accepted and D.is(error) and error.code=='dynamic-lowering','Let file lowering rejects unavailable runtime')
  return graph
end

local function compile(profile, text)
    return Compiler.source { profile = profile, source = text, name = "test." .. profile }
end

local slet = compile("slet", "let main(): U32 = 42")
check(slet.phase == "parsed" and slet.profile == Compiler.profiles.slet, "SLet profile is explicit")
check(slet.ast.declarations[1].kind == "WordDecl", "compiler preserves the ASDL AST")
check(slet.bindings.main == slet.ast.declarations[1], "module declarations are indexed")
check(slet.declarationOrder[1] == "main", "declaration order is deterministic")
check(not slet.profile.dynamic and not slet.profile.managed, "SLet has no dynamic or managed capability")

local let = compile("let", "let id(x: Any): Any = x\nreturn { functions = { id } }")
check(let.profile.dynamic and let.profile.managed, "Let enables dynamic and managed capability")
check(let.bindings.id ~= nil, "Let source uses the same parser and declaration index")

local ok, err = pcall(compile, "slet",
    "let id(x: Any): Any = x\nreturn { functions = { id } }")
check(not ok and D.is(err) and err.code == "slet-forbidden", "SLet rejects any")
check(err.span and err.span.file == "test.slet", "profile diagnostics retain source spans")
ok,err=pcall(Compiler.typed,{profile="slet",source="let f(x): U32 = 0\nreturn { functions = { f } }",name="missing.slet"})
check(not ok and D.is(err) and err.code=="parameter-type",
  "SLet rejects the same unannotated parameter that Let defaults to any")
local foreignSource=[[
extern let host_add(a: U32, b: U32): U32
let add(a: U32, b: U32): U32 = host_add(a, b)
return { functions = { add } }
]]
for _,profile in ipairs({"slet","let"}) do
  local foreign=checkedSource{profile=profile,source=foreignSource,name="foreign."..profile}
  if profile=='slet' then
  check(#foreign.sourceUnit.foreigns==1 and foreign.assembly:match("%.extern host_add ii i"),
    profile.." source extern declarations lower to a verified foreign ABI")
  check(foreign.assembly:match("FCALL%.A host_add"),profile.." source foreign calls lower to FCALL")
  local stageOk,stageError=pcall(Compiler.stage,foreign.functions,{profile=profile,entry="add",exports={"add"},mode="interpreted",foreigns=foreign.sourceUnit.foreigns})
  check(not stageOk and D.is(stageError) and stageError.code=="static-foreign",profile.." source foreign effects reject compile-time execution")
  else
    check(#foreign.foreigns==1,'Let retains foreign signature IR without code generation')
    local stageOK,stageError=pcall(Compiler.stage,foreign.functions,{profile='let',entry='add',mode='interpreted',foreigns=foreign.foreigns})
    check(not stageOK and D.is(stageError) and stageError.code=='dynamic-lowering','staging cannot bypass the Let lowering boundary')
  end
end

ok, err = pcall(compile, "slet",
    "let x = 1\nlet x = 2\nlet main(): U32 = x")
check(not ok and D.is(err) and err.code == "duplicate-name", "duplicate module names reject")

check(Compiler.profileForPath("game.let") == Compiler.profiles.let, ".let selects Let in the host")
check(Compiler.profileForPath("math.slet") == Compiler.profiles.slet, ".slet selects SLet in the host")
ok, err = pcall(Compiler.profileForPath, "source.txt")
check(not ok and D.is(err) and err.code == "source-profile", "unknown source extensions reject")

ok, err = pcall(Compiler.source, { source = "let main(): U32 = 0" })
check(not ok and D.is(err) and err.code == "source-profile", "source profile is mandatory")

local sourceProgram = [[
let base: U32 = 20
let add(x: U32, y: U32): U32 = x + y
let choose(x: U32): U32 = do if x == 0 then return 10 else return x + 1 end end
let select(x: U32): U32 = if x == 0 then 20 else x + 2
let safe(x: U32): Bool = x == 0 or 10 / x > 1
let via(x: U32, y: U32): U32 = do
  let operation = add
  return operation(x, y)
end
let main(): U32 = do
  let x: U32 = base
  let y = 22
  return add(x, y)
end
return { functions = { main, choose, select, via } }
]]
local typed = Compiler.typed { profile = "slet", source = sourceProgram, name = "source-ir.slet" }
check(typed.phase == "typed-ir" and #typed.functions == 6, "source declarations build verified ASDL IR")
check(typed.functions[1].id == "add" and typed.functions[6].id == "main", "semantic construction preserves declaration order")
local lowered = Compiler.compile { profile = "slet", source = sourceProgram, name = "source-ir.slet" }
check(lowered.phase == "lowered" and lowered.assembly:match("%.export main"), "source compilation reaches checked ABC lowering")
local modules = {}
for _, mode in ipairs({"interpreted", "eager", "lazy", "threaded"}) do
  local result = Compiler.stage(lowered.functions, { profile = "slet", entry = "main", exports = {"main"}, mode = mode })
  check(tonumber(result.cells[1]) == 42, "source-built IR executes in " .. mode .. " mode")
  for _, case in ipairs({{"choose", 0, 10}, {"choose", 5, 6}, {"select", 0, 20}, {"select", 5, 7}, {"safe", 0, 1}, {"safe", 10, 0}, {"via", 20, 42}}) do
    local arguments = case[1] == "via" and {case[2], 22} or {case[2]}
    local branch = Compiler.stage(lowered.functions, { profile = "slet", entry = case[1], exports = {case[1]}, mode = mode, arguments = arguments })
    check(tonumber(branch.cells[1]) == case[3], "source-built structured control agrees in " .. mode .. " mode")
  end
  modules[#modules + 1] = result.module
end
check(modules[1] == modules[2] and modules[2] == modules[3], "source-built residual modules are policy-independent")

local aggregateSource = [[
let Point = { x: U32, y: U32 }
let bump(r: Ref(Point)): U32 = do
  r.x += 1
  return r.x
end
let main(): U32 = do
  let p = Point { y = 22, x = 20 }
  bump(Ref(p))
  let alias = p
  let xs: Array(U32, 2) = [alias.x, 21]
  xs[1] += 1
  let view = Slice(xs)
  let text = "abc"
  return p.x + view[1] + U32(text[1])
end
return { functions = { main } }
]]
local aggregateModules = {}
for _, profile in ipairs({"slet", "let"}) do
  local aggregate = checkedSource { profile=profile, source=aggregateSource, name="aggregate."..profile }
  if profile=='slet' then
    check(aggregate.assembly:match("ST32") and aggregate.assembly:match("LD32"),
      'SLet source aggregates lower through checked frame storage')
  else check(hasIR(aggregate,'Store') and hasIR(aggregate,'Read'),'Let aggregate storage remains in IR') end
  for _, mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(aggregate.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==141,profile.." records, arrays, slices, strings, and stores execute in "..mode)
    aggregateModules[#aggregateModules+1]=result.module
  end
end
check(#aggregateModules==3 and aggregateModules[1]==aggregateModules[2] and aggregateModules[2]==aggregateModules[3],
  "SLet aggregate source optimized modules are policy-independent")
local recursiveTypeSource=[[
let Node = { value: U32, next: Link }
let Link = oneof { none: Unit, some: Ref(Node) }
extern let root(): Ptr(Node)
let value(): U32 = do
  let p = root()
  return p.value
end
return { functions = { value }, types = { Node, Link } }
]]
for _,profile in ipairs({"slet","let"}) do
  local recursive=checkedSource{profile=profile,source=recursiveTypeSource,name="recursive-type."..profile}
  local unit=profile=='slet' and recursive.sourceUnit or recursive
  check(unit.typeCells['type:Node']~=nil,profile..' seals mutually recursive types through an indirection')
  if profile=='slet' then check(recursive.assembly:match('FCALL%.A root'),'SLet recursive-type foreign call emits selected ABI') end
end
for _,source in ipairs({
  "let Bad = { child: Bad }\nreturn { types = { Bad } }",
  "let A = { b: B }\nlet B = { a: A }\nreturn { types = { A, B } }",
}) do
  local cycleOk,cycleError=pcall(Compiler.compile,{profile="slet",source=source,name="type-cycle.slet"})
  check(not cycleOk and D.is(cycleError) and cycleError.code=="type-cycle","recursive types reject by-value layout cycles")
end

local pointerSource=[[
let main(): U32 = do
  let xs = [40, 1]
  let p = Ptr(xs[0])
  p[1] += 1
  let empty: Ptr(U32) = null(U32)
  if p == empty then return 0 end
  if p != Ptr(xs[0]) then return 1 end
  return p[0] + p[1]
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local pointerProgram=checkedSource{profile=profile,source=pointerSource,name="pointer."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(pointerProgram.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." raw pointer construction, indexing, null, and stores execute in "..mode.." mode")
  end
end

local aggregateAnySource=[[
let Pair = { x: U32, y: U32 }
let box(p: Pair): Any = p
let unbox(a: Any): Pair = a
let main(): U32 = do
  let a = box(Pair { x = 40, y = 2 })
  if is(a, Pair) then let p = unbox(a) return p.x + p.y end
  return 0
end
return { functions = { main } }
]]
local aggregateOK,aggregateError=pcall(Compiler.typed,{profile="let",source=aggregateAnySource,name="aggregate-any.let"})
check(not aggregateOK and D.is(aggregateError) and aggregateError.code=='borrow-escape',
  'The current erased aggregate conversion cannot preserve its borrowed local implicitly')

local methodSource=[[
let Counter = {
  value: U32,
  bump(by: U32): U32 = do value += by return value end,
}
let Parent = { child: Counter }
let by_value(c: Counter): U32 = c.bump(2)
let by_ref(c: Ref(Counter)): U32 = c.bump(3)
let main(): U32 = do
  let c = Counter { value = 40 }
  let copied = by_value(c)
  let borrowed = by_ref(Ref(c))
  let nested = Parent { child = Counter { value = 41 } }
  return copied + borrowed + c.value + nested.child.bump(1)
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local methods=checkedSource{profile=profile,source=methodSource,name="methods."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(methods.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==170,profile.." methods retain interfaces on actual value, reference, and nested-field receivers in "..mode.." mode")
  end
end

local retainedMethodSource=[=[
let Counter = {
  value: U32,
  bump(by: U32): U32 = do value += by return value end,
}
let bind(start: U32): (U32): U32 = do
  let receiver = Counter { value = start }
  return receiver.bump
end
let main(): U32 = do
  let bump = bind(40)
  return bump(2)
end
return { functions = { main } }
]=]
ok,err=pcall(Compiler.compile,{profile="let",source=retainedMethodSource,name="retained-method.let"})
check(not ok and D.is(err) and err.code=='borrow-escape','A returned receiver borrow cannot acquire implicit ownership: '..tostring(err))
ok,err=pcall(Compiler.compile,{profile='slet',source=retainedMethodSource,name='retained-method.slet'})
check(not ok and D.is(err) and err.code=='borrow-escape','The same receiver lifetime rule applies in both source profiles')

local keyedSource=[[
let distance { x: U32, y: U32 }: U32 = x * x + y * y
let main(): U32 = do
  let with_x = distance { x = 3 }
  return with_x(4) + distance { y = 4, x = 3 }
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local keyed=checkedSource{profile=profile,source=keyedSource,name="keyed."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(keyed.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==50,profile.." keyed requirements canonicalize full and static partial supplies in "..mode.." mode")
  end
end
local keyedOk,keyedError=pcall(Compiler.compile,{profile="slet",name="keyed-runtime.slet",source=[[
let add { x: U32, y: U32 }: U32 = x + y
let bad(n: U32): (U32): U32 = add { x = n }
return { functions = { bad } }
]]})
check(not keyedOk and D.is(keyedError) and keyedError.code=='borrow-escape','Returning a borrowed partial-call environment does not acquire ownership')
local partialOK,partialError=pcall(Compiler.typed,{profile="let",name="partial-runtime.let",source=[[
let add(a, b: U32): U32 = a + b
let partial(n: U32): Any = add(n)
return { functions = { partial } }
]]})
check(not partialOK and D.is(partialError) and partialError.code=='Rc-interface',
  'Runtime erased partial-call environments require their explicit ownership API: '..tostring(partialError))

local deferSource=[[
let push(p: Ptr(U32), digit: U32): Unit = do
  p[0] = p[0] * 10 + digit
  return
end
let snapshot(p: Ptr(U32)): Unit = do
  let digit = [1]
  defer push(p, digit[0])
  digit[0] = 9
  return
end
let nested(p: Ptr(U32)): Unit = do
  defer push(p, 1)
  if true then
    defer push(p, 2)
    return
  end
  return
end
let main(): U32 = do
  let value = [0]
  let p = Ptr(value[0])
  snapshot(p)
  nested(p)
  return value[0]
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local deferred=checkedSource{profile=profile,source=deferSource,name="defer."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(deferred.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==121,profile.." deferred calls snapshot arguments and leave nested blocks in LIFO order in "..mode.." mode")
  end
end

local nestedWordSource=[[
let main(): U32 = do
  let limit: U32 = 3
  let state = [0]
  let loop(n: U32): U32 = do
    state[0] += 2
    if n == limit then return state[0] end
    return loop(n + 1)
  end
  return loop(0)
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local nested=checkedSource{profile=profile,source=nestedWordSource,name="nested-word."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(nested.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==8,profile.." nested words retain lexical values and places through self recursion in "..mode.." mode")
  end
end

local aggregateAbiSource = [[
let Pair = { x: U32, y: U16 }
let Triple = Array(U32, 3)
let Choice = oneof { none: Unit, some: Pair }
let make_pair(): Pair = Pair { y = U16(5), x = 10 }
let bump(p: Pair): Pair = Pair { x = p.x + 1, y = p.y }
let total(p: Pair): U32 = p.x + U32(p.y)
let make_array(): Triple = [5, 6, 7]
let array_total(xs: Triple): U32 = xs[0] + xs[1] + xs[2]
let select(p: Pair): Choice = Choice.some { x = p.x, y = p.y }
let unwrap(value: Choice): U32 = value {
  none = do() = 0,
  some = do(p) = p.x + U32(p.y),
}
let main(): U32 = do
  let p = bump(make_pair())
  let xs = make_array()
  let selected = select(Pair { x = 3, y = U16(5) })
  return total(p) + array_total(xs) + unwrap(selected)
end
return { functions = { main } }
]]
local aggregateAbiModules={}
for _,profile in ipairs({"slet","let"}) do
  local program=checkedSource{profile=profile,source=aggregateAbiSource,name="aggregate-abi."..profile}
  if profile=='slet' then
    check(program.assembly:match('%.function make_pair 0 2') and program.assembly:match('%.function make_array 0 3'),
      'SLet aggregate results flatten into deterministic ABC cells')
  end
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(program.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." aggregate arguments, results, and sum payloads execute in "..mode)
    check(Compiler.optimize(result.module)==result.module,profile.." aggregate ABI optimization is a fixpoint in "..mode)
    aggregateAbiModules[#aggregateAbiModules+1]=result.module
  end
end
check(#aggregateAbiModules==3 and aggregateAbiModules[1]==aggregateAbiModules[2] and aggregateAbiModules[2]==aggregateAbiModules[3],
  "SLet aggregate ABI residual modules are policy-independent")

local inferredBlockMatchSource=[=[
let Option = oneof { none: Unit, some: U32 }
let main(): U32 = do
  let value = Option.some(40)
  let inferred = value {
    none = do return 0 end,
    some = do(payload) return payload + 2 end,
  }
  return inferred
end
return { functions = { main } }
]=]
for _,profile in ipairs({"slet","let"}) do
  local program=checkedSource{profile=profile,source=inferredBlockMatchSource,name="inferred-block-match."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(program.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." infers block-bodied sum handler results in "..mode.." mode")
  end
end
ok,err=pcall(Compiler.typed,{profile="slet",name="mismatched-block-match.slet",source=[=[
let Option = oneof { none: Unit, some: U32 }
let main(): U32 = do
  let value = Option.some(40)
  let inferred = value { none = do return false end, some = do(payload) return payload end }
  return U32(inferred)
end
]=]})
check(not ok and err.code=="type-mismatch","inferred block handlers reject incompatible result paths")

local sumSource = [[
let Option = oneof { none: Unit, some: U32 }
let main(): U32 = do
  let present = Option.some(40)
  let absent = Option.none()
  let x = present { none = do() = 0, some = do(value) = value + 1 }
  let y = absent { some = do(value) = value, none = do() = 1 }
  return x + y
end
return { functions = { main } }
]]
local sumModules={}
for _,profile in ipairs({"slet","let"}) do
  local sumProgram=checkedSource{profile=profile,source=sumSource,name="sum."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(sumProgram.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." sum construction and matching execute in "..mode)
    sumModules[#sumModules+1]=result.module
  end
end
check(#sumModules==3 and sumModules[1]==sumModules[2] and sumModules[2]==sumModules[3],
  "SLet sum source optimized modules are policy-independent")
local blockMatchSource=[[
let Option = oneof { none: Unit, some: U32 }
let unwrap(value: Option): U32 = value {
  none = do
    let zero = 0
    return zero
  end,
  some = do(payload)
    let adjusted = payload + 2
    return adjusted
  end,
}
let main(): U32 = unwrap(Option.some(40))
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local program=checkedSource{profile=profile,source=blockMatchSource,name="block-match."..profile}
  for _,mode in ipairs(runtimeModes[profile]) do
    local result=Compiler.stage(program.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." block-bodied sum handlers execute in "..mode.." mode")
  end
end

local closureSource = [[
let Capture = { base: U32, more: U32 }
let make(): (U32): U32 = do
  let environment = Capture { more = 20, base = 20 }
  return do(x: U32) = environment.base + environment.more + x
end
let main(): U32 = do
  let add = make()
  return add(2)
end
return { functions = { main } }
]]
ok,err=pcall(Compiler.compile,{profile="let",source=closureSource,name="closure.let"})
check(not ok and D.is(err) and err.code=='borrow-escape','A returned borrowed record capture cannot acquire ownership')
ok,err=pcall(Compiler.compile,{profile='slet',source=closureSource,exports={'main'}})
check(not ok and D.is(err) and err.code=='borrow-escape','The same record capture lifetime rule applies in SLet')

local indirectPartialSource=[=[
let add(a, b: U32): U32 = a + b
let bind(f: (U32, U32): U32, n: U32): (U32): U32 = f(n)
let make(base: U32): (U32, U32): U32 = (do(a: U32, b: U32) = base + a + b)
let main(): U32 = bind(add, 2)(40)
let managed(): U32 = bind(make(1), 2)(39)
return { functions = { main, managed } }
]=]
ok,err=pcall(Compiler.compile,{profile="let",name="indirect-partial.let",source=indirectPartialSource})
check(not ok and D.is(err) and err.code=='borrow-escape','A returned borrowed partial environment cannot acquire ownership')
ok,err=pcall(Compiler.compile,{profile='slet',source=indirectPartialSource,exports={'main','managed'}})
check(not ok and D.is(err) and err.code=='borrow-escape','The same partial environment lifetime rule applies in SLet')

local openWordSource=[=[
let main(): U32 = do
  let word = { hp = 40, name = "golem" }
  let alias = word
  alias.hp += 2
  word["bonus"] = 1
  if not has(word, "hp") then return 0 end
  if count(word) != 3 then return 1 end
  if key(word, 0) != "hp" then return 2 end
  let changed = word { hp = 10, extra = 3 }
  if changed.hp != 10 or word.hp != 42 or count(changed) != 4 then return 6 end
  remove(word, "name")
  if has(alias, "name") then return 3 end
  if word["bonus"] != 1 then return 4 end
  return U32(word.hp)
end
return { functions = { main } }
]=]
local openWords=checkedLet{profile="let",name="open-words.let",source=openWordSource}
check(hasIR(openWords,'Dynamic','WordNew') and hasIR(openWords,'Dynamic','WordSet') and hasIR(openWords,'Dynamic','WordGet'),
  'Let bare supplies construct explicit open-word IR operations')
ok,err=pcall(Compiler.typed,{profile="slet",name="open-words.slet",source=openWordSource})
check(not ok and err.code=="slet-forbidden","SLet rejects bare open-word supplies")
local openMethodSource=[=[
let increment(x): Any = x + 1
let main(): U32 = do
  let enemy = { hp = 10, plain = increment }
  let enemy.hit(damage): Bool = do
    hp -= damage
    return hp <= 0
  end
  if enemy.plain(2) != 3 then return 3 end
  let hit = enemy.hit
  if hit(3) then return 0 end
  let copy = enemy { hp = 5 }
  if copy.hit(5) != true then return 1 end
  if U32(enemy.hp) != 7 or U32(copy.hp) != 0 then return 2 end
  return U32(enemy.hp) * 6
end
return { functions = { main } }
]=]
local openMethods=checkedLet{profile="let",name="open-methods.let",source=openMethodSource}
check(hasIR(openMethods,'Dynamic','WordMethod'),'open-word methods preserve receiver-binding IR')
ok,err=pcall(Compiler.typed,{profile="slet",name="open-methods.slet",source=openMethodSource})
check(not ok and err.code=="slet-forbidden","SLet rejects open-word methods")

local runtimeSupplyOK,runtimeSupplyError=pcall(Compiler.typed,{profile="let",name="runtime-supply.let",source=[=[
let add(a, b: U32): U32 = a + b
let main(): U32 = do
  let supplied: U32 = 2
  let fields = { supplied = supplied }
  let partial = add(U32(fields.supplied))
  return U32(partial(40))
end
return { functions = { main } }
]=]})
check(not runtimeSupplyOK and D.is(runtimeSupplyError) and runtimeSupplyError.code=='Rc-interface','Erased runtime partial environments remain gated')
local keyedRuntimeSupply=checkedLet{profile="let",name="keyed-runtime-supply.let",source=[=[
let add { a: U32, b: U32 }: U32 = a + b
let digits { a: U32, b: U32, c: U32 }: U32 = a * 100 + b * 10 + c
let main(supplied: U32): U32 = do
  let partial = add { b = supplied }
  let full = add { a = supplied, b = 22 }
  return partial(20) + full
end
let bookkeeping(supplied: U32): U32 = do
  let partial = digits { b = supplied }
  return partial(1, 3)
end
return { functions = { main, bookkeeping } }
]=]}
check(not hasIR(keyedRuntimeSupply,'Dynamic','WordBind'),'Known keyed supplies elaborate through ordinary source calls, not mutable open words')
local noTerminal=checkedLet{profile="let",name="no-terminal.let",source="let main(): U32 = do open()() return 0 end\nreturn { functions = { main } }\n"}
local frozenWords=checkedLet{profile="let",name="frozen-word.let",source=[=[
let main(): Unit = do
  let word = freeze { value = 1 }
  word.value = 2
  return
end
return { functions = { main } }
]=]}

local exactLambda=Compiler.compile{profile="slet",name="lambda.slet",source=[[
let noop(): Unit = do return end
let main(): U32 = do
  noop()
  let add: (U32, U32): U32 = do(x: U32, y: U32) = x + y
  return add(20, 22)
end
return { functions = { main } }
]]}
for _,mode in ipairs({"interpreted","eager","lazy","threaded"}) do
  local result=Compiler.stage(exactLambda.functions,{profile="slet",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"capture-free SLet lambda executes in "..mode)
end
ok,err=pcall(Compiler.typed,{profile="slet",name="capture.slet",source=[[
let main(): U32 = do
  let base = 40
  let add: (U32): U32 = do(x: U32) = base + x
  return add(2)
end
]]})
check(ok,"Direct local lambda captures need no owned callable representation: "..tostring(err))
if ok then
  local result=Compiler.stage(err.functions,{profile="slet",entry="main",exports={"main"},mode="interpreted"})
  check(tonumber(result.cells[1])==42,"Direct captured lambda preserves its scalar capture")
end
ok,err=pcall(Compiler.compile,{profile="slet",name="borrow.slet",source=[[
let bad(): Slice(U32) = do
  let xs = [1, 2]
  return Slice(xs)
end
return { functions = { bad } }
]]})
check(not ok and D.is(err) and err.code=='borrow-escape','A local slice cannot acquire implicit ownership')
ok,err=pcall(Compiler.compile,{profile="slet",name="borrow-ref.slet",source=[[
let Item = { value: U32 }
let bad(): Ref(Item) = do
  let x = Item { value = 42 }
  return Ref(x)
end
return { functions = { bad } }
]]})
check(not ok and D.is(err) and err.code=='borrow-escape','A local reference cannot acquire implicit ownership')
for _,source in ipairs({
[[let Box = { x: U32 }
let bad(c: Bool): Ref(U32) = do
  let x = Box { x = 7 }
  return if c then Ref(x.x) else Ref(x.x)
end
return { functions = { bad } }]],
[[let Box = { x: U32 }
let Holder = { r: Ref(U32) }
let bad(): Holder = do
  let x = Box { x = 7 }
  return Holder { r = Ref(x.x) }
end
return { functions = { bad } }]],
[[let Box = { x: U32 }
let Holders = Array(Ref(U32), 1)
let bad(): Holders = do
  let x = Box { x = 7 }
  return [Ref(x.x)]
end
return { functions = { bad } }]],
}) do
  ok,err=pcall(Compiler.compile,{profile="slet",name="nested-borrow.slet",source=source})
  check(not ok and D.is(err) and err.code=='borrow-escape','Aggregate transport cannot extend a borrowed lifetime')
end
ok,err=pcall(Compiler.compile,{profile="let",name="escaping-views.let",source=[[
let Pair = { x: U32, y: U32 }
let make_ref(): Ref(Pair) = do
  let p = Pair { x = 40, y = 2 }
  return Ref(p)
end
let make_slice(): Slice(U32) = do
  let xs = [10, 20, 12]
  return Slice(xs)
end
let main(): U32 = do
  let r = make_ref()
  let xs = make_slice()
  return r.x + xs[2] - 10
end
return { functions = { main } }
]]})
check(not ok and D.is(err) and err.code=='borrow-escape','Both profiles reject escaping local references/slices')
ok,err=pcall(Compiler.compile,{profile="let",name="retained-captures.let",source=[[
let Pair = { x: U32 }
let make_ref_reader(): (U32): U32 = do
  let p = Pair { x = 40 }
  let r = Ref(p)
  return do(more: U32) = r.x + more
end
let make_slice_reader(): (U32): U32 = do
  let xs = [10, 20, 12]
  let view = Slice(xs)
  return do(i: U32) = view[i]
end
let main(): U32 = do
  let read = make_ref_reader()
  let pick = make_slice_reader()
  return read(2) + pick(2) - 12
end
return { functions = { main } }
]]})
check(not ok and D.is(err) and err.code=='borrow-escape','Both profiles reject escaping borrowed captures')
ok,err=pcall(Compiler.compile,{profile="let",name="retained-aggregate.let",source=[[
let Target = { value: U32 }
let Holder = { r: Ref(Target), s: Slice(U32) }
let make(): Holder = do
  let p = Target { value = 40 }
  let xs = [1, 2]
  return Holder { r = Ref(p), s = Slice(xs) }
end
let main(): U32 = do
  let h = make()
  return h.r.value + h.s[1]
end
return { functions = { main } }
]]})
check(not ok and D.is(err) and err.code=='borrow-escape','Both profiles reject escaping borrowed aggregate fields')

local anySource=[[
let dynamic_add(a, b): Any = a + b
let main(): (U32, Bool) = do
  let x = dynamic_add(Any(U32(40)), Any(U32(2)))
  return U32(x), is(x, U32)
end
return { functions = { main } }
]]
local anyTyped=Compiler.typed{profile="let",source=anySource,name="dynamic.let"}
check(anyTyped.functions[1].inputs[1].type==require("let.schema").Any,
  "unannotated Let parameters default to any in production semantic IR")
local anyLowered=checkedLet{profile="let",source=anySource,name="dynamic.let"}
check(hasIR(anyLowered,'Convert') and hasIR(anyLowered,'Bin') and hasIR(anyLowered,'Is'),
  'Let semantic IR retains conversions, arithmetic and type tests')
local dynamicCallSource=[[
let add(a: U32, b: U32): U32 = a + b
let apply(callable, a, b): Any = callable(a, b)
let main(): U32 = do
  let operation = Any(add)
  let result = apply(operation, Any(U32(40)), Any(U32(2)))
  return U32(result)
end
return { functions = { main } }
]]
local dynamicCall=checkedLet{profile="let",source=dynamicCallSource,name="dynamic-call.let"}
check(hasIR(dynamicCall,'View') and hasIR(dynamicCall,'Indirect'),
  'Let semantic IR retains boxed callables and dynamic calls')
local counterSource = [[
let loop(value: U32, steps: U32, limit: U32, by: U32): (U32, U32) = do
  if value >= limit then return value, steps end
  return loop(value + by, steps + 1, limit, by)
end
let main(): (U32, U32) = loop(0, 0, 50, 7)
return { functions = { main } }
]]
local counter = Compiler.compile { profile = "slet", source = counterSource, name = "counter.slet" }
local counterModules = {}
for _, mode in ipairs({"interpreted", "eager", "lazy", "threaded"}) do
  local result = Compiler.stage(counter.functions, { profile = "slet", entry = "main", exports = {"main"}, mode = mode })
  check(tonumber(result.cells[1]) == 56 and tonumber(result.cells[2]) == 8,
    "source-built recursive control executes in " .. mode .. " mode")
  counterModules[#counterModules + 1] = result.module
end
check(counterModules[1] == counterModules[2] and counterModules[2] == counterModules[3],
  "source-built recursive residual modules are policy-independent")
local prefix = os.tmpname()
local counterPath=prefix..".specialized.abc";local counterFile=assert(io.open(counterPath,"wb"));assert(counterFile:write(counterModules[1]));assert(counterFile:close())
local counterDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",counterPath),"r"));local counterListing=counterDis:read("*a")
check(counterDis:close() and counterListing:match("BLTUI_A%s+50") and counterListing:match("ADDI_A%s+7") and not counterListing:match("CALL"),
  "source recursive loop specializes invariants into one call-free residual loop")
check(Compiler.optimize(counterModules[1])==counterModules[1],"source recursive specialization is a byte-identical fixpoint")
os.remove(counterPath)
local sharedLoop = Compiler.compile { profile = "slet", name = "shared-loop.slet", source = [[
let f(n: U32, acc: U32): U32 = do
  if n == 0 then return acc end
  let a = acc + 1
  return f(n - 1, a + a)
end
let main(): U32 = f(3, 0)
]] }
for _, mode in ipairs({"interpreted", "eager", "lazy", "threaded"}) do
  local result = Compiler.stage(sharedLoop.functions, { profile = "slet", entry = "main", exports = {"main"}, mode = mode })
  check(tonumber(result.cells[1]) == 14, "nested recursive loop refreshes multi-use carried values in " .. mode .. " mode")
end
local nonTail = Compiler.compile { profile = "slet", name = "non-tail.slet", source = [[
let f(n: U32, by: U32): U32 = do
  if n == 0 then return by end
  let rest = f(n - 1, by)
  return rest + by
end
let main(): U32 = f(3, 7)
]] }
local nonTailModules={}
for _,mode in ipairs({"interpreted","eager","lazy","threaded"}) do local result=Compiler.stage(nonTail.functions,{profile="slet",entry="main",exports={"main"},mode=mode});check(tonumber(result.cells[1])==28,"non-tail recursive SCC executes in "..mode.." mode");nonTailModules[#nonTailModules+1]=result.module end
check(nonTailModules[1]==nonTailModules[2] and nonTailModules[2]==nonTailModules[3],"non-tail SCC specialization is policy-independent")
local nonTailPath=prefix..".non-tail.abc";local nonTailFile=assert(io.open(nonTailPath,"wb"));assert(nonTailFile:write(nonTailModules[1]));assert(nonTailFile:close());local nonTailDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",nonTailPath),"r"));local nonTailListing=nonTailDis:read("*a")
check(nonTailDis:close() and nonTailListing:match("CALL_A") and nonTailListing:match("ADDI_A%s+7"),"non-tail SCC keeps calls while specializing its invariant argument")
check(Compiler.optimize(nonTailModules[1])==nonTailModules[1],"non-tail SCC specialization is a byte-identical fixpoint");os.remove(nonTailPath)
local publicRecursive=Compiler.compile {profile="slet",name="public-recursive.slet",source=[[
let f(n: U32, by: U32): U32 = do
  if n == 0 then return by end
  let rest = f(n - 1, by)
  return rest + by
end
let main(): U32 = f(3, 7)
return { functions = { f, main } }
]]}
local publicResult=Compiler.stage(publicRecursive.functions,{profile="slet",entry="main",exports={"f","main"},mode="interpreted"});local publicPath=prefix..".public-recursive.abc";local publicFile=assert(io.open(publicPath,"wb"));assert(publicFile:write(publicResult.module));assert(publicFile:close())
local publicRun=assert(io.popen(string.format("%q run %q f 2 5 --interpreted",here.."../../build/abc",publicPath),"r"));check(publicRun:read("*a"):match("15") and publicRun:close(),"ABI-visible recursive entries begin with unknown facts");os.remove(publicPath)
local mutual = Compiler.compile { profile = "slet", name = "mutual.slet", source = [[
let even(n: U32, marker: U32): U32 = do
  if n == 0 then return marker end
  return odd(n - 1, marker)
end
let odd(n: U32, marker: U32): U32 = do
  if n == 0 then return marker + 1 end
  return even(n - 1, marker)
end
let main(): U32 = even(4, 9)
]] }
local mutualResult=Compiler.stage(mutual.functions,{profile="slet",entry="main",exports={"main"},mode="lazy"});check(tonumber(mutualResult.cells[1])==9,"mutual recursive SCC executes through residual tail calls")
local mutualPath=prefix..".mutual.abc";local mutualFile=assert(io.open(mutualPath,"wb"));assert(mutualFile:write(mutualResult.module));assert(mutualFile:close());local mutualDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",mutualPath),"r"));local mutualListing=mutualDis:read("*a");local _,mutualFunctions=mutualListing:gsub("function %d+:","")
check(mutualDis:close() and mutualFunctions==3 and mutualListing:match("TCALL") and mutualListing:match("PUSH8_A%s+9") and mutualListing:match("PUSH8_A%s+10"),"mutual SCC fixed point retains carried n and specializes invariant marker")
check(Compiler.optimize(mutualResult.module)==mutualResult.module,"mutual SCC specialization is a byte-identical fixpoint");os.remove(mutualPath)
local ackermann=Compiler.compile {profile="slet",name="ackermann.slet",source=[[
let ack(m: U32, n: U32): U32 = do
  if m == 0 then return n + 1 end
  if n == 0 then return ack(m - 1, 1) end
  return ack(m - 1, ack(m, n - 1))
end
let main(): U32 = ack(2, 3)
]]}
local ackModules={}
for _,mode in ipairs({"interpreted","eager","lazy","threaded"}) do local result=Compiler.stage(ackermann.functions,{profile="slet",entry="main",exports={"main"},mode=mode});check(tonumber(result.cells[1])==9,"nested non-tail recursion preserves real returns in "..mode.." mode");ackModules[#ackModules+1]=result.module end
check(ackModules[1]==ackModules[2] and ackModules[2]==ackModules[3],"nested recursive SCC output is policy-independent")
local ackPath=prefix..".ackermann.abc";local ackFile=assert(io.open(ackPath,"wb"));assert(ackFile:write(ackModules[1]));assert(ackFile:close());local ackDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",ackPath),"r"));local ackListing=ackDis:read("*a")
check(ackDis:close() and ackListing:match("CALL_A") and ackListing:match("RET") and ackListing:match("JMP"),"multiple self-tail edges do not conflate a nested call or return leaf")
check(Compiler.optimize(ackModules[1])==ackModules[1],"nested recursive SCC specialization is a byte-identical fixpoint");os.remove(ackPath)
for _, extension in ipairs({"slet"}) do
  local path, module = prefix .. "." .. extension, prefix .. "." .. extension .. ".abc"
  local file = assert(io.open(path, "wb")); assert(file:write(counterSource)); assert(file:close())
  check(os.execute(string.format("%q compile %q -o %q", here .. "../../build/abc", path, module)) == 0,
    "abc compile uses the production ." .. extension .. " source frontend")
  local process = assert(io.popen(string.format("%q run %q main --lazy", here .. "../../build/abc", path), "r"))
  local output = process:read("*a")
  check(process:close() and output:match("56 8"), "abc run compiles ." .. extension .. " through verified IR")
  os.remove(path); os.remove(module)
end

-- The CLI must reject Let lowering without overwriting an existing output.
do
  local path,module,diagnostic=prefix..'.let',prefix..'.let.abc',prefix..'.let.error'
  local file=assert(io.open(path,'wb'));assert(file:write(counterSource));assert(file:close())
  file=assert(io.open(module,'wb'));assert(file:write('preserved output'));assert(file:close())
  local status=os.execute(string.format('%q compile %q -o %q 2>%q',here..'../../build/abc',path,module,diagnostic))
  check(status~=0,'CLI rejects unavailable Let ABC lowering')
  file=assert(io.open(diagnostic,'rb'));local message=file:read('*a');file:close()
  check(message:find('dynamic-lowering',1,true),'CLI reports the explicit lowering boundary')
  file=assert(io.open(module,'rb'));local retained=file:read('*a');file:close()
  check(retained=='preserved output','failed Let compilation preserves existing output')
  os.remove(path);os.remove(module);os.remove(diagnostic)
end

local importDir = prefix .. "-imports"
assert(os.execute(string.format("mkdir -p %q", importDir)) == 0)
local function write(path, text) local file=assert(io.open(path,"wb"));assert(file:write(text));assert(file:close()) end
write(importDir .. "/math.slet", "let inc(x: U32): U32 = x + 1\nreturn { functions = { inc } }\n")
local importedSource = "use math\nlet main(): U32 = math.inc(41)\nreturn { functions = { main } }\n"
write(importDir .. "/main.slet", importedSource)
local imported = Compiler.compileFile(importDir .. "/main.slet")
local importedResult = Compiler.stage(imported.functions, {profile="slet",entry="main",exports={"main"},mode="lazy"})
check(tonumber(importedResult.cells[1]) == 42, "SLet file imports resolve exported SLet words")
write(importDir .. "/main.let", importedSource)
check(checkedLetFile(importDir .. "/main.let").phase == "typed-ir", "Let files may import SLet IR")
write(importDir .. "/math.let", "let inc(x: U32): U32 = x + 2\nreturn { functions = { inc } }\n")
ok, err = pcall(Compiler.compileFile, importDir .. "/main.let")
check(not ok and D.is(err) and err.code == "import-ambiguous", "Let imports reject ambiguous .let/.slet modules")
os.remove(importDir .. "/math.slet")
ok, err = pcall(Compiler.compileFile, importDir .. "/main.slet")
check(not ok and D.is(err) and err.code == "slet-import", "SLet imports reject Let modules")
os.remove(importDir .. "/main.slet"); os.remove(importDir .. "/main.let"); os.remove(importDir .. "/math.let")
write(importDir .. "/strict.slet", [[
let Pair = { x: U32, y: U32 }
let Option = oneof { none: Unit, some: U32 }
let PairOption = oneof { none: Unit, some: Pair }
let compute(): U32 = do
  let p = Pair { y = 10, x = 10 }
  let xs = [p.x, p.y]
  let view = Slice(xs)
  let tagged = Option.some(view[0] + view[1])
  return tagged { none = do() = 0, some = do(value) = value + 1 }
end
let make_pair(): Pair = Pair { x = 20, y = 22 }
let pair_total(p: Pair): U32 = p.x + p.y
let make_choice(): PairOption = PairOption.some { x = 19, y = 23 }
let choice_total(value: PairOption): U32 = value { none = do() = 0, some = do(p) = p.x + p.y }
return { functions = { compute, make_pair, pair_total, make_choice, choice_total } }
]])
-- Keep the typed half of the former mixed-profile import execution test.
write(importDir .. "/typed-app.slet", [[
use strict
let main(): U32 = do
  let p = strict.make_pair()
  let selected = strict.make_choice()
  return strict.compute() + strict.pair_total(p) + strict.choice_total(selected)
end
return { functions = { main } }
]])
local typedImports=Compiler.compileFile(importDir.."/typed-app.slet")
local typedImportModules={}
for _,mode in ipairs(runtimeModes.slet) do
  local result=Compiler.stage(typedImports.functions,{profile="slet",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==105,"cross-module typed aggregates and sum ABI execute in "..mode)
  check(Compiler.optimize(result.module)==result.module,"cross-module typed optimization reaches a fixpoint in "..mode)
  typedImportModules[#typedImportModules+1]=result.module
end
check(#typedImportModules==3 and typedImportModules[1]==typedImportModules[2] and typedImportModules[2]==typedImportModules[3],
  "cross-module typed residual modules are policy-independent")
os.remove(importDir.."/typed-app.slet")
write(importDir .. "/dynamic.let", [[
let Capture = { base: U32 }
-- These controls return code/literal-module access, not frame-owned environments.
let make(): (U32): U32 = do return do(x: U32) = 20 + x end
let make_pick(): (U32): U32 = do return do(i: U32) = i + 10 end
let make_slice(): Slice(U8) = "ab"
let apply(callable, a, b): Any = callable(a, b)
return { functions = { make, make_pick, make_slice, apply } }
]])
write(importDir .. "/app.let", [[
use strict
use dynamic
let add(a: U32, b: U32): U32 = a + b
let main(): U32 = do
  let f = dynamic.make()
  let pick = dynamic.make_pick()
  let escaped = dynamic.make_slice()
  let left = f(0)
  let retained = pick(2) + escaped[1]
  let right = U32(dynamic.apply(Any(add), Any(U32(10)), Any(U32(11))))
  let p = strict.make_pair()
  let selected = strict.make_choice()
  return strict.compute() + left + retained + right + strict.pair_total(p) + strict.choice_total(selected)
end
return { functions = { main } }
]])
local importedFeatures=checkedLetFile(importDir.."/app.let")
local importedAgain=checkedLetFile(importDir.."/app.let")
check(#importedFeatures.functions==#importedAgain.functions,'cross-profile IR import graph is stable')
for index,fn in ipairs(importedFeatures.functions) do check(fn.id==importedAgain.functions[index].id,'imported IR identities are deterministic') end
os.remove(importDir.."/strict.slet");os.remove(importDir.."/dynamic.let");os.remove(importDir.."/app.let");os.execute(string.format("rmdir %q", importDir))

local correctnessSource=[[
let wider(a: U8, b: U32): Bool = a < b
let selected(): U32 = if true then 42 else missing
let main(): U32 = if wider(1, 300) then selected() else 0
return { functions = { main } }
]]
local correctness=Compiler.compile{profile="slet",name="correctness.slet",source=correctnessSource}
for _,mode in ipairs({"interpreted","eager","lazy","threaded"}) do
  local result=Compiler.stage(correctness.functions,{profile="slet",entry="main",mode=mode})
  check(tonumber(result.cells[1])==42,"integer widening and selected-arm construction execute in "..mode)
end
-- Preserve typed conversion execution independently of the archived any-call path.
local typedConversions=Compiler.compile{profile="slet",name="numeric-conversions.slet",source=[=[
let static_value(): U32 = U32(F64(I64(41)))
let main(): U32 = do
  if static_value() != 41 or I32(-1.9) != I32(-1) then return 0 end
  return U32(42.9)
end
return { functions = { main } }
]=]}
local typedConversionModules={}
for _,mode in ipairs(runtimeModes.slet) do
  local result=Compiler.stage(typedConversions.functions,{profile="slet",entry="main",mode=mode})
  check(tonumber(result.cells[1])==42,"typed integer/f64 conversions execute in "..mode)
  typedConversionModules[#typedConversionModules+1]=result.module
end
check(#typedConversionModules==3 and typedConversionModules[1]==typedConversionModules[2] and typedConversionModules[2]==typedConversionModules[3],
  "typed numeric conversion modules are policy-independent")
local numericConversionSource=[=[
let accept(x: U32): U32 = x
let apply(callable, value): Any = callable(value)
let static_value(): U32 = U32(F64(I64(41)))
let main(): U32 = do
  if static_value() != 41 or I32(Any(-1.9)) != I32(-1) then return 0 end
  return U32(apply(Any(accept), Any(42.9)))
end
return { functions = { main } }
]=]
local numericConversions=checkedLet{profile="let",name="numeric-conversions.let",source=numericConversionSource}
local numericRange=checkedLet{profile="let",name="numeric-range.let",source="let main(): U8 = U8(Any(256.0))\nreturn { functions = { main } }\n"}
for _,case in ipairs({
  {"let f(x: U32, x: U32): U32 = x", "duplicate-name"},
  {"let f(): U8 = 300", "numeric-range"},
  {"let f(a: U32, b: I32): U32 = a + b", "type-mismatch"},
  {"let f(): F64 = 1.5 % 1.0", "type-mismatch"},
  {"let f(): F64 = ~1.5", "type-mismatch"},
}) do
  ok,err=pcall(Compiler.typed,{profile="slet",name="negative.slet",source=case[1].."\nreturn { functions = { f } }"})
  check(not ok and D.is(err) and err.code==case[2],"invalid source rejects without an internal IR bug: "..case[2])
end

local vectorSource=[[
let pair(): (U32, U32) = do return 20, 22 end
let add(a: U32, b: U32): U32 = a + b
let main(): U32 = do
  let first = add(20)
  let a, b = pair()
  let kept = pair()
  let x, padding = 1
  let block: (U32): U32 = do(n: U32) return n + 1 end
  return first(a) + b + kept - 20 + x + (add(1))(2) + block(1)
end
return { functions = { main } }
]]
local vectors=Compiler.compile{profile="slet",name="vectors.slet",source=vectorSource}
for _,mode in ipairs({"interpreted","eager","lazy","threaded"}) do
  local result=Compiler.stage(vectors.functions,{profile="slet",entry="main",mode=mode})
  check(tonumber(result.cells[1])==68,"partial/direct-indirect calls, block lambdas, and result-vector binding execute in "..mode)
end

local interfaceDir=prefix.."-interfaces"
assert(os.execute(string.format("mkdir -p %q",interfaceDir))==0)
write(interfaceDir.."/types.slet",[[
let Pair = { x: U32, y: U32, total(): U32 = x + y }
let make() = Pair { x = 20, y = 22 }
return { types = { P = Pair }, functions = { build = make }, results = { [make] = Pair } }
]])
write(interfaceDir.."/main.slet",[[
use types
let main(): U32 = do
  let p: types.P = types.build()
  return p.total()
end
return { functions = { main } }
]])
local interfaces=Compiler.compileFile(interfaceDir.."/main.slet")
for _,mode in ipairs({"interpreted","eager","lazy","threaded"}) do
  local result=Compiler.stage(interfaces.functions,{profile="slet",entry="main",mode=mode})
  check(tonumber(result.cells[1])==42,"export aliases, exported schema methods/types, and results contracts execute in "..mode)
end
write(interfaceDir.."/main.let",[[
use types
let main(): U32 = do
  let p: types.P = types.build()
  let total = p.total
  return total()
end
return { functions = { main } }
]])
local retainedInterface=checkedLetFile(interfaceDir.."/main.let")
os.remove(interfaceDir.."/types.slet");os.remove(interfaceDir.."/main.slet");os.remove(interfaceDir.."/main.let");os.execute(string.format("rmdir %q",interfaceDir))

print(("PASS: Let compiler source ingestion and semantic IR (%d checks)"):format(checks))
