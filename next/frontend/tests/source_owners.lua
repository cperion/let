package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local A=require('assembler')
local O=require('let.optimize')
local ffi=require('let.abi')
local rt=ffi.load('../build/libabc.so')
-- Every allocating API declares Rc; every payload access explicitly borrows.
local source=[[
let Point = { x: U32, bump(n: U32): U32 = do x += n return x end }
let Box = { child: Rc(Point) }
let observed = Point { x = 0 }
let persisted(n: U32): U32 = observed.x
let leaf(n: U32): Rc(Point) = Rc(Point { x = n })
let parent(n: U32): Rc(Box) = Rc(Box { child = leaf(n) })
let read_only(p: Ref(Point)): U32 = p.x
let main(n: U32): U32 = do
 let root = parent(n) let p = root.borrow()
 let saved = p.child
 p.child = leaf(n+1)
 let a = saved.borrow() let next = p.child let b = next.borrow()
 return a.x*100+b.x
end
let fail(n: U32): U32 = do observed.x = n let result = main(n) return result/(n-n) end
let self_replace(n: U32): U32 = do
 let root = parent(n) let p = root.borrow() p.child = p.child
 let child = p.child let q = child.borrow() return q.x
end
let Empty = {}
let empty(): Rc(Empty) = Rc(Empty {})
let zero_width(n: U32): U32 = do let a = empty() let b = empty() return n end
let borrow(n: U32): U32 = do let root = parent(n) let p = root.borrow() let r = p.child return read_only(r.borrow()) end
let borrow_local(n: U32): U32 = do let p = Point { x = n } return read_only(Ref(p)) end
let Duo = { left: Point, right: Point }
let interior(n: U32): Rc(Duo) = Rc(Duo { left = Point { x = 1 }, right = Point { x = n } })
let projection(n: U32): U32 = do let root = interior(n) let p = root.borrow() return read_only(Ref(p.right)) end
let pair(n: U32): (Rc(Point), Rc(Point)) = do return leaf(n),leaf(n+1) end
let pair_result(n: U32): U32 = do let a,b = pair(n) let p = a.borrow() let q = b.borrow() return p.x*100+q.x end
let collection(n: U32): Rc(Array(Rc(Point),2)) = Rc([leaf(n),leaf(n+1)])
let array(n: U32): U32 = do
 let root = collection(n) let p = root.borrow() let saved = p[0]
 p[0] = leaf(n+2)
 let a = saved.borrow() let next = p[0] let b = next.borrow() let last = p[1] let c = last.borrow()
 return a.x*10000+b.x*100+c.x
end
let numbers(n: U32): Rc(Array(U32,2)) = Rc([n,n+1])
let slice(n: U32): U32 = do let root = numbers(n) let p = root.borrow() let values = Slice(p) return values[0]*100+values[1] end
let forwarded(n: U32): Rc(Box) = do if n == 0 then return parent(42) end return forwarded(n-1) end
let recursive(n: U32): U32 = do let root = forwarded(n) let p = root.borrow() let child = p.child let q = child.borrow() return q.x end
-- A recursive child cannot mutate its caller's private allocation merely
-- because both allocations originate at the same source site.
let private_recursive(n: U32): U32 = do
 let root = parent(n) let p = root.borrow() let saved = p.child.borrow()
 if n == 0 then p.child = leaf(1) return 0 end
 let rest = private_recursive(n-1)
 return saved.x+rest
end
let deep(n: U32): U32 = do
 let root = parent(n) let p = root.borrow() let child = p.child let q = child.borrow()
 if n == 0 then return q.x end
 let inner = deep(n-1) return inner+q.x
end
-- Borrowed callable environments remain frame-backed. Rc capture/result APIs
-- themselves stay gated; these closures borrow explicitly named live holdings.
let closure(n: U32): U32 = do
 let a = leaf(n+1) let b = leaf(n+2) let p = a.borrow() let q = b.borrow()
 let f = do() = p.x*100+q.x
 return f()
end
let direct_result(n: U32): U32 = borrow(n)
let add(p: Ref(Point), n: U32): U32 = p.x+n
let partial_apply(f: (Ref(Point),U32): U32, p: Ref(Point)): U32 = do let g = f(p) return g(5) end
let partial(n: U32): U32 = do let root = leaf(n) let p = root.borrow() return partial_apply(add,p) end
let keyed(n: U32): U32 = do let root = leaf(n) let p = root.borrow() return p.bump(3) end
let opened(n: U32): U32 = do let root = parent(n) let p = root.borrow() let box... = p let r = child let q = r.borrow() return q.x end
let loop(n: U32): U32 = do
 let walk(i: U32, total: U32): U32 = do
  if i == n then return total end
  let root = parent(i) let p = root.borrow() let child = p.child let q = child.borrow()
  return walk(i+1,total+q.x)
 end
 return walk(0,0)
end
let Node = { next: Link, value: U32 }
let Link = oneof { empty: Unit, node: Rc(Node) }
let chain(n: U32, value: U32): Rc(Node) = do
 if n == 0 then return Rc(Node { next = Link.empty(), value = value }) end
 let child = chain(n-1,value)
 return Rc(Node { next = Link.node(child), value = value })
end
let deep_graph(n: U32): U32 = do
 let root = chain(24,n) let p = root.borrow() let next = p.next
 return next { empty() = p.value, node(child) = do let q = child.borrow() return q.value end }
end
let Noise = { a: U64, b: U64, c: U64, d: U64 }
let One = { a: U64, b: Rc(Point), c: U64, d: U64 }
let Pair = { a: U64, b: Rc(Point), c: U64, d: Rc(Point) }
let Choice = oneof { empty: Unit, noise: Noise, one: One, pair: Pair }
let noise(): Choice = Choice.noise(Noise { a = 123, b = 456, c = 789, d = 321 })
let choose(n: U32): Choice = do
 if n == 0 then return Choice.empty() end
 return Choice.one(One { a = 123, b = leaf(n), c = 789, d = 321 })
end
let choice_value(v: Choice): U32 = v {
 empty() = 0,
 noise(_) = 0,
 one(p) = do let r = p.b let q = r.borrow() return q.x end,
 pair(p) = do let a = p.b let b = p.d let x = a.borrow() let y = b.borrow() return x.x+y.x end,
}
let TaggedBox = { sentinel: U64, value: Choice }
let tagged_box(n: U32): Rc(TaggedBox) = Rc(TaggedBox { sentinel = 17, value = Choice.pair(Pair { a = 123, b = leaf(n), c = 789, d = leaf(n+1) }) })
let variant(n: U32): U32 = choice_value(choose(n))
let variant_replace(n: U32): U32 = do
 let root = tagged_box(n) let p = root.borrow() let saved = p.value
 p.value = choose(n+19)
 return choice_value(saved)*100+choice_value(p.value)
end
let variant_nested(n: U32): U32 = do let root = tagged_box(n+2) let p = root.borrow() return choice_value(p.value) end
let variant_direct(n: U32): U32 = variant(n)
let invoke(f: (Ref(Point)): U32, p: Ref(Point)): U32 = f(p)
let variant_borrowed_call(n: U32): U32 = do let root = leaf(n+1) let p = root.borrow() return invoke(read_only,p) end
let SliceChoice = oneof { empty: Unit, values: Rc(Array(U32,2)) }
let slice_choice(n: U32): SliceChoice = SliceChoice.values(numbers(n))
let variant_slice(n: U32): U32 = do
 let v = slice_choice(n)
 return v { empty() = 0, values(root) = do let p = root.borrow() let a = Slice(p) return a[0]*100+a[1] end }
end
let variant_loop(n: U32): U32 = do
 let holder = TaggedBox { sentinel = 17, value = noise() }
 let walk(i: U32, total: U32): U32 = do
  if i == n then return total end
  holder.value = if i%2 == 0 then Choice.pair(Pair { a = 123, b = leaf(i), c = 789, d = leaf(i+1) }) else noise()
  return walk(i+1,total+choice_value(holder.value))
 end
 return walk(0,0)
end
let variant_deep(n: U32): U32 = do
 let v = choose(n+1)
 if n == 0 then return choice_value(v) end
 let inner = variant_deep(n-1) return inner+choice_value(v)
end
let variant_fail(n: U32): U32 = do
 let root = tagged_box(n) let p = root.borrow() let saved = p.value p.value = noise()
 return choice_value(saved)/(n-n)
end
let ScalarChoice = oneof { empty: Unit, value: U32 }
let variant_scalar(n: U32): U32 = do let root = leaf(n) let p = root.borrow() let v = ScalarChoice.value(p.x) return v { empty() = 0, value(x) = x } end
let variant_multi(n: U32): U32 = do
 let a,b = pair(n) let v = Choice.pair(Pair { a = 123, b = a, c = 789, d = b })
 return v { empty() = 0, noise(_) = 0, one(_) = 0, pair(p) = do let x = p.b let y = p.d let l = x.borrow() let r = y.borrow() return l.x*100+r.x end }
end
let RawFields = { a: U64, b: Ptr(U32), c: U64, d: U64 }
let RawChoice = oneof { empty: Unit, value: RawFields }
let raw_choice(p: Ptr(U32)): RawChoice = RawChoice.value(RawFields { a = 123, b = p, c = 789, d = 321 })
let variant_raw(n: U32): U32 = do
 let root = leaf(n) let p = root.borrow() let v = raw_choice(Ptr(p.x))
 return v { empty() = 0, value(q) = q.b[0]*2 }
end
]]
local exports={'main','fail','self_replace','zero_width','borrow','borrow_local','read_only','projection','pair_result','array','slice','recursive','private_recursive','deep','closure','direct_result','partial','keyed','opened','loop','deep_graph','persisted','variant','variant_replace','variant_nested','variant_direct','variant_borrowed_call','variant_slice','variant_loop','variant_deep','variant_fail','variant_scalar','variant_multi','variant_raw'}
local started=os.clock()
local artifact=C.compile{profile='slet',name='source-owners.slet',source=source,exports=exports,staticMode='interpreted',staticOptimize=false}
assert(artifact.materialized and artifact.program==artifact.materialized.source)
local frameBytes,largestFrame,holdingSlots=0,0,0
for _,fn in ipairs(artifact.materialized.functions) do
 local frame=fn.body[1]
 if frame and frame.kind=='Var' and frame.type:isRecord() then
  local fields=frame.type.fields
  if #fields>=2 and fields[1].name=='a_previous' and fields[2].name=='b_drop' then
   local bytes=artifact.layout:layout(frame.type).size
   frameBytes=frameBytes+bytes;largestFrame=math.max(largestFrame,bytes);holdingSlots=holdingSlots+#fields-2
  end
 end
end
print(('Rc analysis: %d bindings / %d iterations; cleanup frames: %d declared bytes, %d largest, %d typed slots'):format(artifact.program.accessStats.contexts,artifact.program.accessStats.iterations,frameBytes,largestFrame,holdingSlots))
assert(artifact.assembly:find('.centry',1,true) and artifact.assembly:find('.codeaddr',1,true))
assert(artifact.assembly:find('ADDR2BITS.A',1,true) and artifact.assembly:find('BITS2ADDR.A',1,true),'packed pointer leaves retain explicit kind transitions')
local localBody=assert(artifact.assembly:match('%.function borrow_local[^\n]*\n(.-)\n%.function'))
assert(localBody:find('CALL.A read_only',1,true) and not localBody:find('TCALL.A read_only',1,true),'borrowed local survives its call frame')
local function write(path,data) local f=assert(io.open(path,'wb'));assert(f:write(data));assert(f:close()) end
write('../build/source-owners.abcasm',artifact.assembly)
print(('Rc frontend: %.3fs CPU, %.1f MiB Lua heap, %d assembly bytes'):format(os.clock()-started,collectgarbage('count')/1024,#artifact.assembly));io.stdout:flush()
local raw=A.assemble(artifact.assembly)
print(('Rc raw image: %d bytes; optimizing'):format(#raw));io.stdout:flush()
local optimized=O.optimize(raw)
write('../build/source-owners.abc',raw);write('../build/source-owners-opt.abc',optimized)
local entries={};for name in artifact.assembly:gmatch('%.centry%s+%d+%s+([%w_]+)') do entries[name]=true end
local mirrored,inside={},false
for line in artifact.assembly:gmatch('[^\n]+') do
 local name=line:match('^%.function%s+([%w_]+)');if name then inside=entries[name] or false end
 if inside then line=line:gsub('%.([AB])',function(bank) return bank=='A' and '.B' or '.A' end) end
 mirrored[#mirrored+1]=line
end
local mirror=A.assemble(table.concat(mirrored,'\n')..'\n');local mirrorOptimized=O.optimize(mirror)
assert(mirror~=raw,'lifecycle bank mirror changes bytes')
write('../build/source-owners-b.abc',mirror);write('../build/source-owners-b-opt.abc',mirrorOptimized)
local err=ffi.new('abc_error[1]');local checks,executions=0,0
local function check(ok,message) checks=checks+1;assert(ok,message) end
local function status(s) check(s==0,tonumber(s)..': '..ffi.string(err[0].message)..' at '..tonumber(err[0].offset)) end
local prefix='.profile foreign\n.datazero 8\n.centry 0 cleanup\n'
local ending='.function main 0 1 - i\n PUSH.A 42\n RET.A 0 1\n.export main\n'
for _,declaration in ipairs{
 '__let_rt_source_alloc aiii -','__let_rt_source_hold aa i','__let_rt_source_clear a -',
 '__let_rt_source_enter ai -','__let_rt_source_leave aa -','__let_rt_source_drop ia -','__let_rt_v3_owner_new aiia -',
} do
 local bytes=A.assemble(prefix..'.extern '..declaration..'\n.function cleanup 2 0 aa -\n RET.A 2 0\n'..ending)
 local out=ffi.new('abc_module *[1]');check(rt.abc_module_load(bytes,#bytes,out,err)~=0 and out[0]==nil,'Malformed or retired lifetime contract must not load')
end
for _,body in ipairs{' PUSH.A 1\n PUSH.B 0\n DIVU.A\n DROP.A\n',' CALLOC 8\n CFREE 8\n',' CGET.A 0\n FCALL.A __let_rt_source_leave\n'} do
 local bytes=A.assemble(prefix..'.extern __let_rt_source_leave a -\n.function cleanup 2 0 aa -\n'..body..' RET.A 2 0\n'..ending)
 local out=ffi.new('abc_module *[1]');status(rt.abc_module_load(bytes,#bytes,out,err))
 for _,mode in ipairs{0,3,1,2} do
  local vm=ffi.new('abc_vm *[1]');status(rt.abc_vm_create(ffi.new('abc_limits',{mode=mode}),vm,err))
  check(rt.abc_vm_load(vm[0],out[0],err)~=0,'Unsafe lifecycle rejected before publication');rt.abc_vm_free(vm[0])
 end
 rt.abc_module_free(out[0])
end
local cases={{'main',2,203},{'self_replace',42,42},{'zero_width',42,42},{'borrow',2,2},{'borrow_local',91,91},{'projection',42,42},{'pair_result',2,203},{'array',2,20403},{'slice',2,203},{'recursive',12,42},{'private_recursive',5,15},{'deep',5,15},{'closure',2,304},{'direct_result',42,42},{'partial',2,7},{'keyed',2,5},{'opened',42,42},{'loop',10,45},{'deep_graph',42,42},{'variant',0,0},{'variant',2,2},{'variant_replace',2,521},{'variant_nested',2,9},{'variant_direct',2,2},{'variant_borrowed_call',2,3},{'variant_slice',2,203},{'variant_loop',4,6},{'variant_deep',5,21},{'variant_fail',2,false},{'variant_scalar',2,2},{'variant_multi',2,203},{'variant_raw',2,4},{'fail',2,false},{'persisted',0,2},{'main',3,304}}
for _,bytes in ipairs{raw,optimized,mirror,mirrorOptimized} do
 local m=ffi.new('abc_module *[1]');status(rt.abc_module_load(bytes,#bytes,m,err))
 for _,mode in ipairs{0,3,1,2} do
  local vm=ffi.new('abc_vm *[1]');status(rt.abc_vm_create(ffi.new('abc_limits',{stack_cells=65536,mode=mode}),vm,err));status(rt.abc_vm_load(vm[0],m[0],err))
  for _,test in ipairs(cases) do
   local input=ffi.new('uint64_t[1]',test[2]);local out=ffi.new('uint64_t[1]',999);local n=ffi.new('size_t[1]',99)
   local result=rt.abc_vm_call(vm[0],m[0],test[1],input,1,out,1,n,err);executions=executions+1
   if test[3] then status(result);check(tonumber(out[0])==test[3],test[1]..': '..tostring(out[0]));check(tonumber(n[0])==1,'one result')
   else check(result~=0 and err[0].reason==1,'original division trap');check(tonumber(out[0])==999 and tonumber(n[0])==0,'failed result storage unchanged') end
  end
  rt.abc_vm_free(vm[0])
 end
 rt.abc_module_free(m[0])
end
print(('explicit Rc execution: %d checks, %d VM executions; raw/optimized, four modes, both lifecycle banks'):format(checks,executions))
