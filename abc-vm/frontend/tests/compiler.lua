-- Source-profile and source-ingestion checks for the real ASDL-based compiler.
local source = debug.getinfo(1, "S").source:sub(2)
local here = source:match("^(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. here .. "../?/init.lua;" .. here .. "../../build/?.lua;" .. package.path

local Compiler = require("let.compiler")
local D = require("let.diag")
local checks = 0
local function check(ok, message) assert(ok, message); checks = checks + 1 end

local function compile(profile, text)
    return Compiler.source { profile = profile, source = text, name = "test." .. profile }
end

local slet = compile("slet", "let main(): u32 = 42")
check(slet.phase == "parsed" and slet.profile == Compiler.profiles.slet, "SLet profile is explicit")
check(slet.ast.declarations[1].kind == "WordDecl", "compiler preserves the ASDL AST")
check(slet.bindings.main == slet.ast.declarations[1], "module declarations are indexed")
check(slet.declarationOrder[1] == "main", "declaration order is deterministic")
check(not slet.profile.dynamic and not slet.profile.managed, "SLet has no dynamic or managed capability")

local let = compile("let", "let id(x: any): any = x\nreturn { functions = { id } }")
check(let.profile.dynamic and let.profile.managed, "Let enables dynamic and managed capability")
check(let.bindings.id ~= nil, "Let source uses the same parser and declaration index")

local ok, err = pcall(compile, "slet",
    "let id(x: any): any = x\nreturn { functions = { id } }")
check(not ok and D.is(err) and err.code == "slet-forbidden", "SLet rejects any")
check(err.span and err.span.file == "test.slet", "profile diagnostics retain source spans")
ok,err=pcall(Compiler.typed,{profile="slet",source="let f(x): u32 = 0\nreturn { functions = { f } }",name="missing.slet"})
check(not ok and D.is(err) and err.code=="parameter-type",
  "SLet rejects the same unannotated parameter that Let defaults to any")
local foreignSource=[[
extern let host_add(a: u32, b: u32): u32
let add(a: u32, b: u32): u32 = host_add(a, b)
return { functions = { add } }
]]
for _,profile in ipairs({"slet","let"}) do
  local foreign=Compiler.compile{profile=profile,source=foreignSource,name="foreign."..profile}
  check(#foreign.sourceUnit.foreigns==1 and foreign.assembly:match("%.extern host_add ii i"),
    profile.." source extern declarations lower to a verified foreign ABI")
  check(foreign.assembly:match("FCALL host_add"),profile.." source foreign calls lower to FCALL")
  local stageOk,stageError=pcall(Compiler.stage,foreign.functions,{profile=profile,entry="add",exports={"add"},mode="interpreted",foreigns=foreign.sourceUnit.foreigns})
  check(not stageOk and D.is(stageError) and stageError.code=="static-foreign",profile.." source foreign effects reject compile-time execution")
end

ok, err = pcall(compile, "slet",
    "let x = 1\nlet x = 2\nlet main(): u32 = x")
check(not ok and D.is(err) and err.code == "duplicate-name", "duplicate module names reject")

check(Compiler.profileForPath("game.let") == Compiler.profiles.let, ".let selects Let in the host")
check(Compiler.profileForPath("math.slet") == Compiler.profiles.slet, ".slet selects SLet in the host")
ok, err = pcall(Compiler.profileForPath, "source.txt")
check(not ok and D.is(err) and err.code == "source-profile", "unknown source extensions reject")

ok, err = pcall(Compiler.source, { source = "let main(): u32 = 0" })
check(not ok and D.is(err) and err.code == "source-profile", "source profile is mandatory")

local sourceProgram = [[
let base: u32 = 20
let add(x: u32, y: u32): u32 = x + y
let choose(x: u32): u32 = do if x == 0 then return 10 else return x + 1 end end
let select(x: u32): u32 = if x == 0 then 20 else x + 2
let safe(x: u32): bool = x == 0 or 10 / x > 1
let via(x: u32, y: u32): u32 = do
  let operation = add
  return operation(x, y)
end
let main(): u32 = do
  let x: u32 = base
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
for _, mode in ipairs({"interpreted", "eager", "lazy"}) do
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
let point = { x: u32, y: u32 }
let bump(r: ref(point)): u32 = do
  r.x += 1
  return r.x
end
let main(): u32 = do
  let p = point { y = 22, x = 20 }
  bump(ref(p))
  let alias = p
  let xs: array(u32, 2) = [alias.x, 21]
  xs[1] += 1
  let view = slice(xs)
  let text = "abc"
  return p.x + view[1] + u32(text[1])
end
return { functions = { main } }
]]
local aggregateModules = {}
for _, profile in ipairs({"slet", "let"}) do
  local aggregate = Compiler.compile { profile=profile, source=aggregateSource, name="aggregate."..profile }
  check(aggregate.assembly:match("ST32") and aggregate.assembly:match("LD32"),
    profile.." source aggregates lower through checked frame storage")
  for _, mode in ipairs({"interpreted", "eager", "lazy"}) do
    local result=Compiler.stage(aggregate.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==141,profile.." records, arrays, slices, strings, and stores execute in "..mode)
    aggregateModules[#aggregateModules+1]=result.module
  end
end
check(aggregateModules[1]==aggregateModules[2] and aggregateModules[2]==aggregateModules[3] and aggregateModules[4]==aggregateModules[5] and aggregateModules[5]==aggregateModules[6],
  "aggregate source optimized modules are policy-independent in each profile")
local recursiveTypeSource=[[
let node = { value: u32, next: link }
let link = oneof { none: unit, some: ref(node) }
extern let root(): ptr(node)
let value(): u32 = do
  let p = root()
  return p.value
end
return { functions = { value }, types = { node, link } }
]]
for _,profile in ipairs({"slet","let"}) do
  local recursive=Compiler.compile{profile=profile,source=recursiveTypeSource,name="recursive-type."..profile}
  check(recursive.sourceUnit.typeCells["type:node"]~=nil and recursive.assembly:match("FCALL root"),profile.." seals mutually recursive types through an indirection")
end
for _,source in ipairs({
  "let bad = { child: bad }\nreturn { types = { bad } }",
  "let a = { b: b }\nlet b = { a: a }\nreturn { types = { a, b } }",
}) do
  local cycleOk,cycleError=pcall(Compiler.compile,{profile="slet",source=source,name="type-cycle.slet"})
  check(not cycleOk and D.is(cycleError) and cycleError.code=="type-cycle","recursive types reject by-value layout cycles")
end

local pointerSource=[[
let main(): u32 = do
  let xs = [40, 1]
  let p = ptr(xs[0])
  p[1] += 1
  let empty: ptr(u32) = null(u32)
  if p == empty then return 0 end
  if p != ptr(xs[0]) then return 1 end
  return p[0] + p[1]
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local pointerProgram=Compiler.compile{profile=profile,source=pointerSource,name="pointer."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(pointerProgram.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." raw pointer construction, indexing, null, and stores execute in "..mode.." mode")
  end
end

local aggregateAnySource=[[
let pair = { x: u32, y: u32 }
let box(p: pair): any = p
let unbox(a: any): pair = a
let main(): u32 = do
  let a = box(pair { x = 40, y = 2 })
  if is(a, pair) then let p = unbox(a) return p.x + p.y end
  return 0
end
return { functions = { main } }
]]
local aggregateAny=Compiler.compile{profile="let",source=aggregateAnySource,name="aggregate-any.let"}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(aggregateAny.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"Let boxes, tests, and casts managed aggregates through any in "..mode.." mode")
end

local methodSource=[[
let counter = {
  value: u32,
  bump(by: u32): u32 = do value += by return value end,
}
let parent = { child: counter }
let by_value(c: counter): u32 = c.bump(2)
let by_ref(c: ref(counter)): u32 = c.bump(3)
let main(): u32 = do
  let c = counter { value = 40 }
  let copied = by_value(c)
  let borrowed = by_ref(ref(c))
  let nested = parent { child = counter { value = 41 } }
  return copied + borrowed + c.value + nested.child.bump(1)
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local methods=Compiler.compile{profile=profile,source=methodSource,name="methods."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(methods.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==170,profile.." methods retain interfaces on actual value, reference, and nested-field receivers in "..mode.." mode")
  end
end

local retainedMethodSource=[=[
let counter = {
  value: u32,
  bump(by: u32): u32 = do value += by return value end,
}
let bind(start: u32): (u32): u32 = do
  let receiver = counter { value = start }
  return receiver.bump
end
let main(): u32 = do
  let bump = bind(40)
  return bump(2)
end
return { functions = { main } }
]=]
local retainedMethod=Compiler.compile{profile="let",source=retainedMethodSource,name="retained-method.let"}
check(retainedMethod.assembly:match("MANAGED_COPY") and retainedMethod.assembly:match("_let_adapter_"),
  "retained method values capture their actual managed receiver")
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(retainedMethod.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"retained method values execute in "..mode.." mode")
end
ok,err=pcall(Compiler.typed,{profile="slet",source=retainedMethodSource,name="retained-method.slet"})
check(not ok and err.code=="slet-forbidden","SLet rejects retained method receivers")

local keyedSource=[[
let distance { x: u32, y: u32 }: u32 = x * x + y * y
let main(): u32 = do
  let with_x = distance { x = 3 }
  return with_x(4) + distance { y = 4, x = 3 }
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local keyed=Compiler.compile{profile=profile,source=keyedSource,name="keyed."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(keyed.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==50,profile.." keyed requirements canonicalize full and static partial supplies in "..mode.." mode")
  end
end
local keyedOk,keyedError=pcall(Compiler.compile,{profile="slet",name="keyed-runtime.slet",source=[[
let add { x: u32, y: u32 }: u32 = x + y
let bad(n: u32): (u32): u32 = add { x = n }
return { functions = { bad } }
]]})
check(not keyedOk and D.is(keyedError) and keyedError.code=="static-required","partial keyed supply rejects runtime evidence")
local partialRuntime=Compiler.compile{profile="let",name="partial-runtime.let",source=[[
let add(a, b: u32): u32 = a + b
let partial(n: u32): any = add(n)
return { functions = { partial } }
]]}
check(partialRuntime.assembly:match("WORD_DIRECT") and partialRuntime.assembly:match("DCALL"),
  "Let run-time ordered partial supply opens a word instead of claiming static evidence")

local deferSource=[[
let push(p: ptr(u32), digit: u32): unit = do
  p[0] = p[0] * 10 + digit
  return
end
let snapshot(p: ptr(u32)): unit = do
  let digit = [1]
  defer push(p, digit[0])
  digit[0] = 9
  return
end
let nested(p: ptr(u32)): unit = do
  defer push(p, 1)
  if true then
    defer push(p, 2)
    return
  end
  return
end
let main(): u32 = do
  let value = [0]
  let p = ptr(value[0])
  snapshot(p)
  nested(p)
  return value[0]
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local deferred=Compiler.compile{profile=profile,source=deferSource,name="defer."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(deferred.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==121,profile.." deferred calls snapshot arguments and leave nested blocks in LIFO order in "..mode.." mode")
  end
end

local nestedWordSource=[[
let main(): u32 = do
  let limit: u32 = 3
  let state = [0]
  let loop(n: u32): u32 = do
    state[0] += 2
    if n == limit then return state[0] end
    return loop(n + 1)
  end
  return loop(0)
end
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local nested=Compiler.compile{profile=profile,source=nestedWordSource,name="nested-word."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(nested.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==8,profile.." nested words retain lexical values and places through self recursion in "..mode.." mode")
  end
end

local aggregateAbiSource = [[
let pair = { x: u32, y: u16 }
let triple = array(u32, 3)
let choice = oneof { none: unit, some: pair }
let make_pair(): pair = pair { y = u16(5), x = 10 }
let bump(p: pair): pair = pair { x = p.x + 1, y = p.y }
let total(p: pair): u32 = p.x + u32(p.y)
let make_array(): triple = [5, 6, 7]
let array_total(xs: triple): u32 = xs[0] + xs[1] + xs[2]
let select(p: pair): choice = choice.some { x = p.x, y = p.y }
let unwrap(value: choice): u32 = value {
  none = || -> 0,
  some = |p| -> p.x + u32(p.y),
}
let main(): u32 = do
  let p = bump(make_pair())
  let xs = make_array()
  let selected = select(pair { x = 3, y = u16(5) })
  return total(p) + array_total(xs) + unwrap(selected)
end
return { functions = { main } }
]]
local aggregateAbiModules={}
for _,profile in ipairs({"slet","let"}) do
  local program=Compiler.compile{profile=profile,source=aggregateAbiSource,name="aggregate-abi."..profile}
  check(program.assembly:match("%.function make_pair 0 2") and program.assembly:match("%.function make_array 0 3"),
    profile.." source aggregate results flatten into deterministic ABC cells")
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(program.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." aggregate arguments, results, and sum payloads execute in "..mode)
    check(Compiler.optimize(result.module)==result.module,profile.." aggregate ABI optimization is a fixpoint in "..mode)
    aggregateAbiModules[#aggregateAbiModules+1]=result.module
  end
end
check(aggregateAbiModules[1]==aggregateAbiModules[2] and aggregateAbiModules[2]==aggregateAbiModules[3] and aggregateAbiModules[4]==aggregateAbiModules[5] and aggregateAbiModules[5]==aggregateAbiModules[6],
  "aggregate ABI residual modules are policy-independent in each profile")

local inferredBlockMatchSource=[=[
let option = oneof { none: unit, some: u32 }
let main(): u32 = do
  let value = option.some(40)
  let inferred = value {
    none = || -> do return 0 end,
    some = |payload| -> do return payload + 2 end,
  }
  return inferred
end
return { functions = { main } }
]=]
for _,profile in ipairs({"slet","let"}) do
  local program=Compiler.compile{profile=profile,source=inferredBlockMatchSource,name="inferred-block-match."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(program.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." infers block-bodied sum handler results in "..mode.." mode")
  end
end
ok,err=pcall(Compiler.typed,{profile="slet",name="mismatched-block-match.slet",source=[=[
let option = oneof { none: unit, some: u32 }
let main(): u32 = do
  let value = option.some(40)
  let inferred = value { none = || -> do return false end, some = |payload| -> do return payload end }
  return u32(inferred)
end
]=]})
check(not ok and err.code=="type-mismatch","inferred block handlers reject incompatible result paths")

local sumSource = [[
let option = oneof { none: unit, some: u32 }
let main(): u32 = do
  let present = option.some(40)
  let absent = option.none()
  let x = present { none = || -> 0, some = |value| -> value + 1 }
  let y = absent { some = |value| -> value, none = || -> 1 }
  return x + y
end
return { functions = { main } }
]]
local sumModules={}
for _,profile in ipairs({"slet","let"}) do
  local sumProgram=Compiler.compile{profile=profile,source=sumSource,name="sum."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(sumProgram.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." sum construction and matching execute in "..mode)
    sumModules[#sumModules+1]=result.module
  end
end
check(sumModules[1]==sumModules[2] and sumModules[2]==sumModules[3] and sumModules[4]==sumModules[5] and sumModules[5]==sumModules[6],
  "sum source optimized modules are policy-independent in each profile")
local blockMatchSource=[[
let option = oneof { none: unit, some: u32 }
let unwrap(value: option): u32 = value {
  none = || -> do
    let zero = 0
    return zero
  end,
  some = |payload| -> do
    let adjusted = payload + 2
    return adjusted
  end,
}
let main(): u32 = unwrap(option.some(40))
return { functions = { main } }
]]
for _,profile in ipairs({"slet","let"}) do
  local program=Compiler.compile{profile=profile,source=blockMatchSource,name="block-match."..profile}
  for _,mode in ipairs({"interpreted","eager","lazy"}) do
    local result=Compiler.stage(program.functions,{profile=profile,entry="main",exports={"main"},mode=mode})
    check(tonumber(result.cells[1])==42,profile.." block-bodied sum handlers execute in "..mode.." mode")
  end
end

local closureSource = [[
let capture = { base: u32, more: u32 }
let make(): (u32): u32 = do
  let environment = capture { more = 20, base = 20 }
  return |x: u32| -> environment.base + environment.more + x
end
let main(): u32 = do
  let add = make()
  return add(2)
end
return { functions = { main } }
]]
local closureProgram=Compiler.compile{profile="let",source=closureSource,name="closure.let"}
check(closureProgram.assembly:match("MANAGED_NEW") and closureProgram.assembly:match("_let_adapter_"),
  "capturing source lambdas lower through managed checked adapters")
local closureModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(closureProgram.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"escaping managed source capture executes in "..mode)
  closureModules[#closureModules+1]=result.module
end
check(closureModules[1]==closureModules[2] and closureModules[2]==closureModules[3],
  "managed source closure modules are policy-independent")

local indirectPartialSource=[=[
let add(a, b: u32): u32 = a + b
let bind(f: (u32, u32): u32, n: u32): (u32): u32 = f(n)
let make(base: u32): (u32, u32): u32 = |a: u32, b: u32| -> base + a + b
let main(): u32 = bind(add, 2)(40)
let managed(): u32 = bind(make(1), 2)(39)
return { functions = { main, managed } }
]=]
local indirectPartial=Compiler.compile{profile="let",name="indirect-partial.let",source=indirectPartialSource}
check(indirectPartial.assembly:match("MANAGED_COPY") and indirectPartial.assembly:match("CALLI"),
  "indirect partial application retains the callable and supplied arguments")
local indirectPartialModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(indirectPartial.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"indirect partial application executes in "..mode)
  local managed=Compiler.stage(indirectPartial.functions,{profile="let",entry="managed",exports={"managed"},mode=mode})
  check(tonumber(managed.cells[1])==42,"indirect partial application retains a managed callable in "..mode)
  indirectPartialModules[#indirectPartialModules+1]=result.module
end
check(indirectPartialModules[1]==indirectPartialModules[2] and indirectPartialModules[2]==indirectPartialModules[3],
  "indirect partial application modules are policy-independent")
ok,err=pcall(Compiler.typed,{profile="slet",name="indirect-partial.slet",source=indirectPartialSource})
check(not ok and err.code=="slet-forbidden","SLet rejects retained indirect partial application")

local openWordSource=[=[
let main(): u32 = do
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
  return u32(word.hp)
end
return { functions = { main } }
]=]
local openWords=Compiler.compile{profile="let",name="open-words.let",source=openWordSource}
check(openWords.assembly:match("WORD_NEW") and openWords.assembly:match("WORD_SET") and openWords.assembly:match("WORD_GET"),
  "Let bare supplies lower to profile-5 open-word operations")
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(openWords.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"open-word fields, aliases, keys, stores, and removal execute in "..mode)
end
ok,err=pcall(Compiler.typed,{profile="slet",name="open-words.slet",source=openWordSource})
check(not ok and err.code=="slet-forbidden","SLet rejects bare open-word supplies")
local runtimeSupply=Compiler.compile{profile="let",name="runtime-supply.let",source=[=[
let add(a, b: u32): u32 = a + b
let main(): u32 = do
  let supplied: u32 = 2
  let fields = { supplied = supplied }
  let partial = add(u32(fields.supplied))
  return u32(partial(40))
end
return { functions = { main } }
]=]}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(runtimeSupply.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"run-time positional supply opens and invokes a word in "..mode)
end
local noTerminal=Compiler.compile{profile="let",name="no-terminal.let",source="let main(): u32 = do open()() return 0 end\nreturn { functions = { main } }\n"}
ok,err=pcall(Compiler.stage,noTerminal.functions,{profile="let",entry="main",exports={"main"},mode="interpreted"})
check(not ok and err.code=="static-no-terminal","calling an open word without a terminal uses the specified no-terminal abort")
local frozenWords=Compiler.compile{profile="let",name="frozen-word.let",source=[=[
let main(): unit = do
  let word = freeze { value = 1 }
  word.value = 2
  return
end
return { functions = { main } }
]=]}
ok,err=pcall(Compiler.stage,frozenWords.functions,{profile="let",entry="main",exports={"main"},mode="interpreted"})
check(not ok and err.code=="static-frozen-store","stores through frozen words use the specified frozen-store abort")

local exactLambda=Compiler.compile{profile="slet",name="lambda.slet",source=[[
let noop(): unit = do return end
let main(): u32 = do
  noop()
  let add: (u32, u32): u32 = |x: u32, y: u32| -> x + y
  return add(20, 22)
end
return { functions = { main } }
]]}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(exactLambda.functions,{profile="slet",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"capture-free SLet lambda executes in "..mode)
end
ok,err=pcall(Compiler.typed,{profile="slet",name="capture.slet",source=[[
let main(): u32 = do
  let base = 40
  let add: (u32): u32 = |x: u32| -> base + x
  return add(2)
end
]]})
check(not ok and D.is(err) and err.code=="slet-forbidden","SLet rejects managed lambda captures")
ok,err=pcall(Compiler.typed,{profile="slet",name="borrow.slet",source=[[
let bad(): slice(u32) = do
  let xs = [1, 2]
  return slice(xs)
end
return { functions = { bad } }
]]})
check(not ok and D.is(err) and err.code=="borrow-return","source view lifetime checking rejects a local slice return")
ok,err=pcall(Compiler.typed,{profile="slet",name="borrow-ref.slet",source=[[
let item = { value: u32 }
let bad(): ref(item) = do
  let x = item { value = 42 }
  return ref(x)
end
return { functions = { bad } }
]]})
check(not ok and D.is(err) and err.code=="borrow-return","SLet rejects a returned reference to lexical storage")
for _,source in ipairs({
[[let box = { x: u32 }
let bad(c: bool): ref(u32) = do
  let x = box { x = 7 }
  return if c then ref(x.x) else ref(x.x)
end
return { functions = { bad } }]],
[[let box = { x: u32 }
let holder = { r: ref(u32) }
let bad(): holder = do
  let x = box { x = 7 }
  return holder { r = ref(x.x) }
end
return { functions = { bad } }]],
[[let box = { x: u32 }
let holders = array(ref(u32), 1)
let bad(): holders = do
  let x = box { x = 7 }
  return [ref(x.x)]
end
return { functions = { bad } }]],
}) do
  ok,err=pcall(Compiler.typed,{profile="slet",name="nested-borrow.slet",source=source})
  check(not ok and D.is(err) and err.code=="borrow-return","SLet rejects local borrows hidden by control or aggregates")
end
local escapingViews=Compiler.compile{profile="let",name="escaping-views.let",source=[[
let pair = { x: u32, y: u32 }
let make_ref(): ref(pair) = do
  let p = pair { x = 40, y = 2 }
  return ref(p)
end
let make_slice(): slice(u32) = do
  let xs = [10, 20, 12]
  return slice(xs)
end
let main(): u32 = do
  let r = make_ref()
  let xs = make_slice()
  return r.x + xs[2] - 10
end
return { functions = { main } }
]]}
check(escapingViews.assembly:match("MANAGED_NEW"),"escaping Let references and slices promote lexical backing storage")
local escapingViewModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(escapingViews.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"escaping Let references and slices execute in "..mode)
  escapingViewModules[#escapingViewModules+1]=result.module
end
check(escapingViewModules[1]==escapingViewModules[2] and escapingViewModules[2]==escapingViewModules[3],
  "escaping Let reference and slice modules are policy-independent")
check(Compiler.optimize(escapingViewModules[1])==escapingViewModules[1],
  "escaping Let reference and slice optimization reaches a fixpoint")
local retainedCaptures=Compiler.compile{profile="let",name="retained-captures.let",source=[[
let pair = { x: u32 }
let make_ref_reader(): (u32): u32 = do
  let p = pair { x = 40 }
  let r = ref(p)
  return |more: u32| -> r.x + more
end
let make_slice_reader(): (u32): u32 = do
  let xs = [10, 20, 12]
  let view = slice(xs)
  return |i: u32| -> view[i]
end
let main(): u32 = do
  let read = make_ref_reader()
  let pick = make_slice_reader()
  return read(2) + pick(2) - 12
end
return { functions = { main } }
]]}
check(retainedCaptures.assembly:match("MANAGED_COPY"),
  "managed callable environments copy captures with owner metadata")
local retainedCaptureModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(retainedCaptures.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"managed reference and slice captures retain their owners in "..mode)
  retainedCaptureModules[#retainedCaptureModules+1]=result.module
end
check(retainedCaptureModules[1]==retainedCaptureModules[2] and retainedCaptureModules[2]==retainedCaptureModules[3],
  "managed reference and slice capture modules are policy-independent")
check(Compiler.optimize(retainedCaptureModules[1])==retainedCaptureModules[1],
  "managed capture optimization reaches a fixpoint")
local retainedAggregate=Compiler.compile{profile="let",name="retained-aggregate.let",source=[[
let target = { value: u32 }
let holder = { r: ref(target), s: slice(u32) }
let make(): holder = do
  let p = target { value = 40 }
  let xs = [1, 2]
  return holder { r = ref(p), s = slice(xs) }
end
let main(): u32 = do
  let h = make()
  return h.r.value + h.s[1]
end
return { functions = { main } }
]]}
local retainedAggregateModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(retainedAggregate.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"managed aggregate reference and slice owners survive the call ABI in "..mode)
  retainedAggregateModules[#retainedAggregateModules+1]=result.module
end
check(retainedAggregateModules[1]==retainedAggregateModules[2] and retainedAggregateModules[2]==retainedAggregateModules[3],
  "managed aggregate owner modules are policy-independent")
check(Compiler.optimize(retainedAggregateModules[1])==retainedAggregateModules[1],
  "managed aggregate owner optimization reaches a fixpoint")

local anySource=[[
let dynamic_add(a, b): any = a + b
let main(): (u32, bool) = do
  let x = dynamic_add(any(u32(40)), any(u32(2)))
  return u32(x), is(x, u32)
end
return { functions = { main } }
]]
local anyTyped=Compiler.typed{profile="let",source=anySource,name="dynamic.let"}
check(anyTyped.functions[1].inputs[1].type==require("let.schema").any,
  "unannotated Let parameters default to any in production semantic IR")
local anyLowered=Compiler.compile{profile="let",source=anySource,name="dynamic.let"}
check(anyLowered.assembly:match("ANY_BOX") and anyLowered.assembly:match("DADD") and anyLowered.assembly:match("ANY_CAST") and anyLowered.assembly:match("ANY_IS"),
  "production Let source lowers boxing, generic arithmetic, casts, and type tests")
local anyModules={}
for _,mode in ipairs{"interpreted","eager","lazy"} do
  local result=Compiler.stage(anyLowered.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42 and tonumber(result.cells[2])==1,
    "generic any source execution agrees in "..mode.." mode")
  anyModules[#anyModules+1]=result.module
end
check(anyModules[1]==anyModules[2] and anyModules[2]==anyModules[3],
  "generic any staging produces policy-independent optimized modules")
local dynamicCallSource=[[
let add(a: u32, b: u32): u32 = a + b
let apply(callable, a, b): any = callable(a, b)
let main(): u32 = do
  let operation = any(add)
  let result = apply(operation, any(u32(40)), any(u32(2)))
  return u32(result)
end
return { functions = { main } }
]]
local dynamicCall=Compiler.compile{profile="let",source=dynamicCallSource,name="dynamic-call.let"}
check(dynamicCall.assembly:match("WORD_DIRECT add") and dynamicCall.assembly:match("DCALL 2 1"),
  "ordinary Let source lowers boxed words and dynamic calls")
local dynamicCallModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(dynamicCall.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==42,"source dynamic callable dispatch executes in "..mode)
  dynamicCallModules[#dynamicCallModules+1]=result.module
end
check(dynamicCallModules[1]==dynamicCallModules[2] and dynamicCallModules[2]==dynamicCallModules[3],
  "dynamic callable source modules are policy-independent")
local counterSource = [[
let loop(value: u32, steps: u32, limit: u32, by: u32): (u32, u32) = do
  if value >= limit then return value, steps end
  return loop(value + by, steps + 1, limit, by)
end
let main(): (u32, u32) = loop(0, 0, 50, 7)
return { functions = { main } }
]]
local counter = Compiler.compile { profile = "slet", source = counterSource, name = "counter.slet" }
local counterModules = {}
for _, mode in ipairs({"interpreted", "eager", "lazy"}) do
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
check(counterDis:close() and counterListing:match("BLTUI%s+50") and counterListing:match("ADDI_A%s+7") and not counterListing:match("CALL"),
  "source recursive loop specializes invariants into one call-free residual loop")
check(Compiler.optimize(counterModules[1])==counterModules[1],"source recursive specialization is a byte-identical fixpoint")
os.remove(counterPath)
local sharedLoop = Compiler.compile { profile = "slet", name = "shared-loop.slet", source = [[
let f(n: u32, acc: u32): u32 = do
  if n == 0 then return acc end
  let a = acc + 1
  return f(n - 1, a + a)
end
let main(): u32 = f(3, 0)
]] }
for _, mode in ipairs({"interpreted", "eager", "lazy"}) do
  local result = Compiler.stage(sharedLoop.functions, { profile = "slet", entry = "main", exports = {"main"}, mode = mode })
  check(tonumber(result.cells[1]) == 14, "nested recursive loop refreshes multi-use carried values in " .. mode .. " mode")
end
local dynamicLoop = Compiler.compile { profile = "let", name = "dynamic-loop.let", source = [[
let f(n: u32, acc: u32): u32 = do
  if n == 0 then return acc end
  let a = acc + 1
  return f(n - 1, a + a)
end
let main(): u32 = f(3, 0)
]] }
local dynamicResult=Compiler.stage(dynamicLoop.functions,{profile="let",entry="main",exports={"main"},mode="interpreted"})
local dynamicPath=prefix..".dynamic-loop.abc";local dynamicFile=assert(io.open(dynamicPath,"wb"));assert(dynamicFile:write(dynamicResult.module));assert(dynamicFile:close())
local dynamicDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",dynamicPath),"r"));local dynamicListing=dynamicDis:read("*a");local _,dynamicFunctions=dynamicListing:gsub("function %d+:","")
check(dynamicDis:close() and tonumber(dynamicResult.cells[1])==14 and dynamicFunctions==1 and not dynamicListing:match("CALL"),
  "dynamic-profile symbolic reachability emits only the call-free exported residual loop")
os.remove(dynamicPath)
local nonTail = Compiler.compile { profile = "let", name = "non-tail.let", source = [[
let f(n: u32, by: u32): u32 = do
  if n == 0 then return by end
  let rest = f(n - 1, by)
  return rest + by
end
let main(): u32 = f(3, 7)
]] }
local nonTailModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do local result=Compiler.stage(nonTail.functions,{profile="let",entry="main",exports={"main"},mode=mode});check(tonumber(result.cells[1])==28,"non-tail recursive SCC executes in "..mode.." mode");nonTailModules[#nonTailModules+1]=result.module end
check(nonTailModules[1]==nonTailModules[2] and nonTailModules[2]==nonTailModules[3],"non-tail SCC specialization is policy-independent")
local nonTailPath=prefix..".non-tail.abc";local nonTailFile=assert(io.open(nonTailPath,"wb"));assert(nonTailFile:write(nonTailModules[1]));assert(nonTailFile:close());local nonTailDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",nonTailPath),"r"));local nonTailListing=nonTailDis:read("*a")
check(nonTailDis:close() and nonTailListing:match("CALL_A") and nonTailListing:match("ADDI_A%s+7"),"non-tail SCC keeps calls while specializing its invariant argument")
check(Compiler.optimize(nonTailModules[1])==nonTailModules[1],"non-tail SCC specialization is a byte-identical fixpoint");os.remove(nonTailPath)
local publicRecursive=Compiler.compile {profile="let",name="public-recursive.let",source=[[
let f(n: u32, by: u32): u32 = do
  if n == 0 then return by end
  let rest = f(n - 1, by)
  return rest + by
end
let main(): u32 = f(3, 7)
return { functions = { f, main } }
]]}
local publicResult=Compiler.stage(publicRecursive.functions,{profile="let",entry="main",exports={"f","main"},mode="interpreted"});local publicPath=prefix..".public-recursive.abc";local publicFile=assert(io.open(publicPath,"wb"));assert(publicFile:write(publicResult.module));assert(publicFile:close())
local publicRun=assert(io.popen(string.format("%q run %q f 2 5 --interpreted",here.."../../build/abc",publicPath),"r"));check(publicRun:read("*a"):match("15") and publicRun:close(),"ABI-visible recursive entries begin with unknown facts");os.remove(publicPath)
local mutual = Compiler.compile { profile = "let", name = "mutual.let", source = [[
let even(n: u32, marker: u32): u32 = do
  if n == 0 then return marker end
  return odd(n - 1, marker)
end
let odd(n: u32, marker: u32): u32 = do
  if n == 0 then return marker + 1 end
  return even(n - 1, marker)
end
let main(): u32 = even(4, 9)
]] }
local mutualResult=Compiler.stage(mutual.functions,{profile="let",entry="main",exports={"main"},mode="lazy"});check(tonumber(mutualResult.cells[1])==9,"mutual recursive SCC executes through residual tail calls")
local mutualPath=prefix..".mutual.abc";local mutualFile=assert(io.open(mutualPath,"wb"));assert(mutualFile:write(mutualResult.module));assert(mutualFile:close());local mutualDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",mutualPath),"r"));local mutualListing=mutualDis:read("*a");local _,mutualFunctions=mutualListing:gsub("function %d+:","")
check(mutualDis:close() and mutualFunctions==3 and mutualListing:match("TCALL") and mutualListing:match("PUSH8_A%s+9") and mutualListing:match("PUSH8_A%s+10"),"mutual SCC fixed point retains carried n and specializes invariant marker")
check(Compiler.optimize(mutualResult.module)==mutualResult.module,"mutual SCC specialization is a byte-identical fixpoint");os.remove(mutualPath)
local ackermann=Compiler.compile {profile="let",name="ackermann.let",source=[[
let ack(m: u32, n: u32): u32 = do
  if m == 0 then return n + 1 end
  if n == 0 then return ack(m - 1, 1) end
  return ack(m - 1, ack(m, n - 1))
end
let main(): u32 = ack(2, 3)
]]}
local ackModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do local result=Compiler.stage(ackermann.functions,{profile="let",entry="main",exports={"main"},mode=mode});check(tonumber(result.cells[1])==9,"nested non-tail recursion preserves real returns in "..mode.." mode");ackModules[#ackModules+1]=result.module end
check(ackModules[1]==ackModules[2] and ackModules[2]==ackModules[3],"nested recursive SCC output is policy-independent")
local ackPath=prefix..".ackermann.abc";local ackFile=assert(io.open(ackPath,"wb"));assert(ackFile:write(ackModules[1]));assert(ackFile:close());local ackDis=assert(io.popen(string.format("%q dis %q",here.."../../build/abc",ackPath),"r"));local ackListing=ackDis:read("*a")
check(ackDis:close() and ackListing:match("CALL_A") and ackListing:match("RET") and ackListing:match("JMP"),"multiple self-tail edges do not conflate a nested call or return leaf")
check(Compiler.optimize(ackModules[1])==ackModules[1],"nested recursive SCC specialization is a byte-identical fixpoint");os.remove(ackPath)
for _, extension in ipairs({"slet", "let"}) do
  local path, module = prefix .. "." .. extension, prefix .. "." .. extension .. ".abc"
  local file = assert(io.open(path, "wb")); assert(file:write(counterSource)); assert(file:close())
  check(os.execute(string.format("%q compile %q -o %q", here .. "../../build/abc", path, module)) == 0,
    "abc compile uses the production ." .. extension .. " source frontend")
  local process = assert(io.popen(string.format("%q run %q main --lazy", here .. "../../build/abc", path), "r"))
  local output = process:read("*a")
  check(process:close() and output:match("56 8"), "abc run compiles ." .. extension .. " through verified IR")
  os.remove(path); os.remove(module)
end

local importDir = prefix .. "-imports"
assert(os.execute(string.format("mkdir -p %q", importDir)) == 0)
local function write(path, text) local file=assert(io.open(path,"wb"));assert(file:write(text));assert(file:close()) end
write(importDir .. "/math.slet", "let inc(x: u32): u32 = x + 1\nreturn { functions = { inc } }\n")
local importedSource = "use math\nlet main(): u32 = math.inc(41)\nreturn { functions = { main } }\n"
write(importDir .. "/main.slet", importedSource)
local imported = Compiler.compileFile(importDir .. "/main.slet")
local importedResult = Compiler.stage(imported.functions, {profile="slet",entry="main",exports={"main"},mode="lazy"})
check(tonumber(importedResult.cells[1]) == 42, "SLet file imports resolve exported SLet words")
write(importDir .. "/main.let", importedSource)
check(Compiler.compileFile(importDir .. "/main.let").phase == "lowered", "Let files may import SLet files")
write(importDir .. "/math.let", "let inc(x: u32): u32 = x + 2\nreturn { functions = { inc } }\n")
ok, err = pcall(Compiler.compileFile, importDir .. "/main.let")
check(not ok and D.is(err) and err.code == "import-ambiguous", "Let imports reject ambiguous .let/.slet modules")
os.remove(importDir .. "/math.slet")
ok, err = pcall(Compiler.compileFile, importDir .. "/main.slet")
check(not ok and D.is(err) and err.code == "slet-import", "SLet imports reject Let modules")
os.remove(importDir .. "/main.slet"); os.remove(importDir .. "/main.let"); os.remove(importDir .. "/math.let")
write(importDir .. "/strict.slet", [[
let pair = { x: u32, y: u32 }
let option = oneof { none: unit, some: u32 }
let pair_option = oneof { none: unit, some: pair }
let compute(): u32 = do
  let p = pair { y = 10, x = 10 }
  let xs = [p.x, p.y]
  let view = slice(xs)
  let tagged = option.some(view[0] + view[1])
  return tagged { none = || -> 0, some = |value| -> value + 1 }
end
let make_pair(): pair = pair { x = 20, y = 22 }
let pair_total(p: pair): u32 = p.x + p.y
let make_choice(): pair_option = pair_option.some { x = 19, y = 23 }
let choice_total(value: pair_option): u32 = value { none = || -> 0, some = |p| -> p.x + p.y }
return { functions = { compute, make_pair, pair_total, make_choice, choice_total } }
]])
write(importDir .. "/dynamic.let", [[
let capture = { base: u32 }
let make(): (u32): u32 = do
  let environment = capture { base = 20 }
  let retained = ref(environment)
  return |x: u32| -> retained.base + x
end
let make_pick(): (u32): u32 = do
  let xs = [10, 20, 12]
  let view = slice(xs)
  return |i: u32| -> view[i]
end
let make_slice(): slice(u32) = do
  let xs = [1, 2]
  return slice(xs)
end
let apply(callable, a, b): any = callable(a, b)
return { functions = { make, make_pick, make_slice, apply } }
]])
write(importDir .. "/app.let", [[
use strict
use dynamic
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do
  let f = dynamic.make()
  let pick = dynamic.make_pick()
  let escaped = dynamic.make_slice()
  let left = f(0)
  let retained = pick(2) + escaped[1]
  let right = u32(dynamic.apply(any(add), any(u32(10)), any(u32(11))))
  let p = strict.make_pair()
  let selected = strict.make_choice()
  return strict.compute() + left + retained + right + strict.pair_total(p) + strict.choice_total(selected)
end
return { functions = { main } }
]])
local importedFeatures=Compiler.compileFile(importDir.."/app.let")
local importedAgain=Compiler.compileFile(importDir.."/app.let")
check(importedFeatures.assembly==importedAgain.assembly,"cross-profile aggregate, closure, and any imports compile deterministically")
local importedFeatureModules={}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(importedFeatures.functions,{profile="let",entry="main",exports={"main"},mode=mode})
  check(tonumber(result.cells[1])==160,"cross-module source features, managed views, and aggregate ABI execute in "..mode)
  check(Compiler.optimize(result.module)==result.module,"cross-module optimized source reaches a fixpoint in "..mode)
  importedFeatureModules[#importedFeatureModules+1]=result.module
end
check(importedFeatureModules[1]==importedFeatureModules[2] and importedFeatureModules[2]==importedFeatureModules[3],
  "cross-module residual modules are policy-independent")
os.remove(importDir.."/strict.slet");os.remove(importDir.."/dynamic.let");os.remove(importDir.."/app.let");os.execute(string.format("rmdir %q", importDir))

local correctnessSource=[[
let wider(a: u8, b: u32): bool = a < b
let selected(): u32 = if true then 42 else missing
let main(): u32 = if wider(1, 300) then selected() else 0
return { functions = { main } }
]]
local correctness=Compiler.compile{profile="slet",name="correctness.slet",source=correctnessSource}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(correctness.functions,{profile="slet",entry="main",mode=mode})
  check(tonumber(result.cells[1])==42,"integer widening and selected-arm construction execute in "..mode)
end
for _,case in ipairs({
  {"let f(x: u32, x: u32): u32 = x", "duplicate-name"},
  {"let f(): u8 = 300", "numeric-range"},
  {"let f(a: u32, b: i32): u32 = a + b", "type-mismatch"},
  {"let f(): f64 = 1.5 % 1.0", "type-mismatch"},
  {"let f(): f64 = ~1.5", "type-mismatch"},
}) do
  ok,err=pcall(Compiler.typed,{profile="slet",name="negative.slet",source=case[1].."\nreturn { functions = { f } }"})
  check(not ok and D.is(err) and err.code==case[2],"invalid source rejects without an internal IR bug: "..case[2])
end

local vectorSource=[[
let pair(): (u32, u32) = do return 20, 22 end
let add(a: u32, b: u32): u32 = a + b
let main(): u32 = do
  let first = add(20)
  let a, b = pair()
  let kept = pair()
  let x, padding = 1
  let block: (u32): u32 = |n: u32| -> do return n + 1 end
  return first(a) + b + kept - 20 + x + (add(1))(2) + block(1)
end
return { functions = { main } }
]]
local vectors=Compiler.compile{profile="slet",name="vectors.slet",source=vectorSource}
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(vectors.functions,{profile="slet",entry="main",mode=mode})
  check(tonumber(result.cells[1])==68,"partial/direct-indirect calls, block lambdas, and result-vector binding execute in "..mode)
end

local interfaceDir=prefix.."-interfaces"
assert(os.execute(string.format("mkdir -p %q",interfaceDir))==0)
write(interfaceDir.."/types.slet",[[
let pair = { x: u32, y: u32, total(): u32 = x + y }
let make() = pair { x = 20, y = 22 }
return { types = { P = pair }, functions = { build = make }, results = { [make] = pair } }
]])
write(interfaceDir.."/main.slet",[[
use types
let main(): u32 = do
  let p: types.P = types.build()
  return p.total()
end
return { functions = { main } }
]])
local interfaces=Compiler.compileFile(interfaceDir.."/main.slet")
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(interfaces.functions,{profile="slet",entry="main",mode=mode})
  check(tonumber(result.cells[1])==42,"export aliases, exported schema methods/types, and results contracts execute in "..mode)
end
write(interfaceDir.."/main.let",[[
use types
let main(): u32 = do
  let p: types.P = types.build()
  let total = p.total
  return total()
end
return { functions = { main } }
]])
local retainedInterface=Compiler.compileFile(interfaceDir.."/main.let")
for _,mode in ipairs({"interpreted","eager","lazy"}) do
  local result=Compiler.stage(retainedInterface.functions,{profile="let",entry="main",mode=mode})
  check(tonumber(result.cells[1])==42,"imported schema interfaces support retained method values in "..mode)
end
os.remove(interfaceDir.."/types.slet");os.remove(interfaceDir.."/main.slet");os.remove(interfaceDir.."/main.let");os.execute(string.format("rmdir %q",interfaceDir))

print(("PASS: Let compiler source ingestion and semantic IR (%d checks)"):format(checks))
