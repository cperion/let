package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C=require('let.compiler')
local A=require('assembler')
local O=require('let.optimize')
local ffi=require('let.abi')
local rt=ffi.load('../build/libabc.so')
local source=[[
let Point = { x: U32 }
let Box = { child: Ref(Point) }
let observed = Point { x = 0 }
let persisted(n: U32): U32 = observed.x
let self_replace(n: U32): U32 = do let p = parent(n) p.child = p.child return p.child.x end
let Empty = {}
let empty(): Ref(Empty) = do let e = Empty {} return Ref(e) end
let zero_width(n: U32): U32 = do let a = empty() let b = empty() return n end
let leaf(v: U32): Ref(Point) = do
 let point = Point { x = v }
 return Ref(point)
end
let parent(v: U32): Ref(Box) = do
 let p = Box { child = leaf(v) }
 return Ref(p)
end
let read_only(p: Ref(Point)): U32 = p.x
let borrow(n: U32): U32 = do let p = parent(n) return read_only(p.child) end
let borrow_local(n: U32): U32 = do let p = Point { x = n } return read_only(Ref(p)) end
let Duo = { left: Point, right: Point }
let interior(n: U32): Ref(Point) = do
 let pair = Duo { left = Point { x = 1 }, right = Point { x = n } }
 return Ref(pair.right)
end
let projection(n: U32): U32 = do let p = interior(n) return p.x end
let pair(v: U32): (Ref(Point), Ref(Point)) = do
 let a = Point { x = v }
 let b = Point { x = v+1 }
 return Ref(a), Ref(b)
end
let pair_result(n: U32): U32 = do
 let a,b = pair(n)
 return a.x*100+b.x
end
let Collection = { points: Array(Ref(Point),2) }
let collection(v: U32): Ref(Collection) = do
 let c = Collection { points = [leaf(v),leaf(v+1)] }
 return Ref(c)
end
let array(n: U32): U32 = do
 let c = collection(n)
 let saved = c.points[0]
 c.points[0] = leaf(n+2)
 return saved.x*10000+c.points[0].x*100+c.points[1].x
end
let numbers(v: U32): Slice(U32) = do
 let values = [v,v+1]
 return Slice(values)
end
let slice(n: U32): U32 = do
 let values = numbers(n)
 return values[0]*100+values[1]
end
let main(n: U32): U32 = do
 let p = parent(n)
 let saved = p.child
 p.child = leaf(n+1)
 return saved.x*100+p.child.x
end
let fail(n: U32): U32 = do
 observed.x = n
 let p = parent(n)
 let saved = p.child
 p.child = leaf(n+1)
 return saved.x/(n-n)
end
let forwarded(n: U32): Ref(Box) = do
 if n == 0 then return parent(42) else return forwarded(n-1) end
end
let recursive(n: U32): U32 = do
 let p = forwarded(n)
 return p.child.x
end
let deep(n: U32): U32 = do
 let p = parent(n)
 if n == 0 then return p.child.x end
 let inner = deep(n-1)
 return inner+p.child.x
end
let opened_make(n: U32): (): U32 = do let p = Point { x = n } let p... return do(): U32 = x end
let opened(n: U32): U32 = do let f = opened_make(n) return f() end
let maker(n: U32): (): U32 = do
 let point = Point { x = n }
 return do(): U32 point.x += 1 return point.x end
end
let view_factory(n: U32): (): Ref(Point) = do
 return do(): Ref(Point) = leaf(n)
end
let indirect_result(n: U32): U32 = do
 let f = view_factory(n)
 let p = f()
 return p.x
end
let add(a,b: U32): U32 = a+b
let bind(f: (U32,U32): U32, n: U32): (U32): U32 = f(n)
let add_base(base: U32): (U32,U32): U32 = do(a: U32,b: U32) = base+a+b
let partial(n: U32): U32 = bind(add_base(n),2)(3)
let keyed_add { x: U32, y: U32 }: U32 = x+y
let keyed_bind(n: U32): (U32): U32 = keyed_add { x = n }
let keyed(n: U32): U32 = do let f = keyed_bind(n) return f(3) end
let closure(n: U32): U32 = do
 let f = maker(n)
 return f()*100+f()
end
let loop(n: U32): U32 = do
 let walk(i: U32, total: U32): U32 = do
  if i == n then return total end
  let p = parent(i)
  return walk(i+1,total+p.child.x)
 end
 return walk(0,0)
end
]]
-- A real source-owned chain of 25 environments, at distinct source call sites.
-- This is separate from the C-constructed 100001-node small-stack lifecycle test.
source=source..[[
let graph_base(n: U32): (): U32 = do() = n
let graph_link(previous: (): U32): (): U32 = do() = previous()
let deep_graph(n: U32): U32 = do
 let g0 = graph_base(n)
]]
for depth=1,24 do source=source..(' let g%d = graph_link(g%d)\n'):format(depth,depth-1) end
source=source..' return g24()\nend\n'
source=source..[[
let PairRefs = { first: Ref(Point), last: Ref(Point) }
let Noise = { a: U64, b: U64, c: U64, d: U64 }
let Choice = oneof { empty: Unit, noise: Noise, one: Ref(Point), pair: PairRefs }
let noise(): Choice = Choice.noise(Noise { a=U64(123), b=U64(456), c=U64(789), d=U64(321) })
let choose(n: U32): Choice = if n == 0 then Choice.empty() else Choice.one(leaf(n))
let choice_value(v: Choice): U32 = v {
 empty() = 0, noise(bits) = 0, one(p) = p.x, pair(p) = p.first.x+p.last.x,
}
let TaggedBox = { sentinel: U32, value: Choice }
let tagged_box(n: U32): Ref(TaggedBox) = do
 let p = TaggedBox { sentinel=17, value=Choice.pair(PairRefs { first=leaf(n), last=leaf(n+1) }) }
 return Ref(p)
end
let variant(n: U32): U32 = choice_value(choose(n))
let choices(n: U32): (Choice,Choice) = do return choose(n),choose(n+1) end
let variant_multi(n: U32): U32 = do let a,b=choices(n) return choice_value(a)*100+choice_value(b) end
let RawChoice = oneof { empty: Unit, pointer: Ptr(U32) }
let raw_choice(p: Ptr(U32)): RawChoice = RawChoice.pointer(p)
let variant_raw(n: U32): U32 = do
 let keep=leaf(n)
 let x=Point { x=n }
 let v=raw_choice(Ptr(x.x))
 return v { empty()=0, pointer(p)=p[0] }+keep.x
end
let variant_replace(n: U32): U32 = do
 let p = tagged_box(n)
 let saved = p.value
 p.value = noise()
 let old = choice_value(saved)
 p.value = Choice.one(leaf(n+2))
 p.value = p.value
 return old*100+choice_value(p.value)+p.sentinel
end
let Nested = oneof { empty: Unit, values: Array(Choice,2) }
let nested_make(n: U32): Nested = Nested.values([choose(n),Choice.pair(PairRefs { first=leaf(n+1), last=leaf(n+2) })])
let variant_nested(n: U32): U32 = do
 let v = nested_make(n)
 return v { empty()=0, values(a)=choice_value(a[0])+choice_value(a[1]) }
end
let variant_factory(n: U32): (): Choice = do() = choose(n)
let variant_indirect(n: U32): U32 = do let f=variant_factory(n) return choice_value(f()) end
let ActionChoice = oneof { empty: Unit, run: (): U32 }
let action_make(n: U32): ActionChoice = ActionChoice.run(maker(n))
let variant_callable(n: U32): U32 = do let v=action_make(n) return v { empty()=0, run(f)=f() } end
let SliceChoice = oneof { empty: Unit, values: Slice(U32) }
let slice_choice(n: U32): SliceChoice = SliceChoice.values(numbers(n))
let variant_slice(n: U32): U32 = do let v=slice_choice(n) return v { empty()=0, values(a)=a[0]*100+a[1] } end
let variant_loop(n: U32): U32 = do
 let holder = TaggedBox { sentinel=17, value=noise() }
 let walk(i: U32, total: U32): U32 = do
  if i == n then return total end
  holder.value = if i%2 == 0 then Choice.pair(PairRefs { first=leaf(i), last=leaf(i+1) }) else noise()
  return walk(i+1,total+choice_value(holder.value))
 end
 return walk(0,0)
end
let variant_deep(n: U32): U32 = do
 let v = choose(n+1)
 if n == 0 then return choice_value(v) end
 let inner = variant_deep(n-1)
 return inner+choice_value(v)
end
let variant_fail(n: U32): U32 = do
 let p = tagged_box(n)
 let saved = p.value
 p.value = noise()
 return choice_value(saved)/(n-n)
end
-- Pointer-free tag operations must also work inside an owning activation.
let ScalarChoice = oneof { empty: Unit, value: U32 }
let variant_scalar(n: U32): U32 = do
 let p = leaf(n)
 let v = ScalarChoice.value(p.x)
 return v { empty()=0, value(x)=x }
end
]]
local exports={'variant_multi','variant_raw','variant_deep','variant','variant_replace','variant_nested','variant_indirect','variant_callable','variant_slice','variant_loop','variant_fail','variant_scalar','main','fail','recursive','deep','closure','loop','pair_result','array','slice','borrow','borrow_local','read_only','projection','indirect_result','partial','keyed','deep_graph','self_replace','zero_width','persisted','opened'}
local artifact=C.compile{profile='slet',name='source-owners.slet',source=source,exports=exports,staticMode='interpreted',staticOptimize=false}
assert(artifact.materialized and artifact.program==artifact.materialized.source)
assert(artifact.assembly:find('.centry',1,true) and artifact.assembly:find('.codeaddr',1,true))
assert(artifact.assembly:find('ADDR2BITS.A',1,true) and artifact.assembly:find('BITS2ADDR.A',1,true),'packed pointer leaves use explicit kind transitions')
local packedBody=assert(artifact.assembly:match('%.function raw_choice__constructor_%d+[^\n]*\n(.-)\n%.function'))
assert(packedBody:find('ADDR2BITS.A',1,true) and not packedBody:find('CALLOC',1,true) and not packedBody:find('FADDR',1,true),'value-only pointer packing must not manufacture storage')
local localBody=assert(artifact.assembly:match('%.function borrow_local[^\n]*\n(.-)\n%.function'))
assert(localBody:find('CALL.A read_only',1,true) and not localBody:find('TCALL.A read_only',1,true),'borrowed local survives its ordinary call frame')
local function write(path,data) local f=assert(io.open(path,'wb'));assert(f:write(data));assert(f:close()) end
write('../build/source-owners.abcasm',artifact.assembly)
local raw=A.assemble(artifact.assembly)
write('../build/source-owners.abc',raw)
local optimized=O.optimize(raw);write('../build/source-owners-opt.abc',optimized)
local entries={};for name in artifact.assembly:gmatch('%.centry%s+%d+%s+([%w_]+)') do entries[name]=true end
-- Mirror only lifecycle bodies. Ordinary source calls/results remain unchanged;
-- the generated C wrapper must bind either selected operand stack correctly.
local mirrored,inside={},false
for line in artifact.assembly:gmatch('[^\n]+') do
 local name=line:match('^%.function%s+([%w_]+)');if name then inside=entries[name] or false end
 if inside then line=line:gsub('%.([AB])',function(bank) return bank=='A' and '.B' or '.A' end) end
 mirrored[#mirrored+1]=line
end
local mirror=A.assemble(table.concat(mirrored,'\n')..'\n')
assert(mirror~=raw,'lifecycle bank mirror must change bytes')
write('../build/source-owners-b.abc',mirror)
local mirrorOptimized=O.optimize(mirror);write('../build/source-owners-b-opt.abc',mirrorOptimized)
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
 local out=ffi.new('abc_module *[1]')
 check(rt.abc_module_load(bytes,#bytes,out,err)~=0 and out[0]==nil,'Malformed or retired lifetime contract must not load')
end
for _,body in ipairs{
 ' PUSH.A 1\n PUSH.B 0\n DIVU.A\n DROP.A\n',
 ' CALLOC 8\n CFREE 8\n',
 ' CGET.A 0\n FCALL.A __let_rt_source_leave\n',
} do
 local bytes=A.assemble(prefix..'.extern __let_rt_source_leave a -\n.function cleanup 2 0 aa -\n'..body..' RET.A 2 0\n'..ending)
 local out=ffi.new('abc_module *[1]');status(rt.abc_module_load(bytes,#bytes,out,err))
 for _,mode in ipairs{0,3,1,2} do
  local vm=ffi.new('abc_vm *[1]');status(rt.abc_vm_create(ffi.new('abc_limits',{mode=mode}),vm,err))
  check(rt.abc_vm_load(vm[0],out[0],err)~=0,'Unsafe lifecycle must fail before image publication');rt.abc_vm_free(vm[0])
 end
 rt.abc_module_free(out[0])
end
for _,image in ipairs{raw,optimized,mirror,mirrorOptimized} do
 local m=ffi.new('abc_module *[1]');status(rt.abc_module_load(image,#image,m,err))
 for _,mode in ipairs{0,3,1,2} do
  local limits=ffi.new('abc_limits',{stack_cells=65536,mode=mode});local vm=ffi.new('abc_vm *[1]');status(rt.abc_vm_create(limits,vm,err));status(rt.abc_vm_load(vm[0],m[0],err))
  for _,test in ipairs{{'variant_multi',2,203},{'variant_raw',2,4},{'variant_deep',5,21},{'variant',0,0},{'variant',2,2},{'variant_replace',2,521},{'variant_nested',2,9},{'variant_indirect',2,2},{'variant_callable',2,3},{'variant_slice',2,203},{'variant_loop',4,6},{'variant_fail',2,false},{'variant_scalar',2,2},{'main',2,203},{'self_replace',42,42},{'opened',42,42},{'zero_width',42,42},{'borrow',2,2},{'borrow_local',91,91},{'projection',42,42},{'indirect_result',42,42},{'partial',2,7},{'keyed',2,5},{'deep_graph',42,42},{'pair_result',2,203},{'array',2,20403},{'slice',2,203},{'recursive',12,42},{'deep',5,15},{'closure',2,304},{'loop',10,45},{'fail',2,false},{'persisted',0,2},{'main',3,304},{'closure',40,4142}} do
   local input=ffi.new('uint64_t[1]',test[2]);local out=ffi.new('uint64_t[1]',999);local n=ffi.new('size_t[1]',99)
   local result=rt.abc_vm_call(vm[0],m[0],test[1],input,1,out,1,n,err);executions=executions+1
   if test[3] then status(result);check(tonumber(out[0])==test[3],test[1]..': '..tostring(out[0]));check(tonumber(n[0])==1,'one result')
   else check(result~=0 and err[0].reason==1,'original division trap');check(tonumber(out[0])==999 and tonumber(n[0])==0,'unchanged result storage and zero failed result count') end
  end
  rt.abc_vm_free(vm[0])
 end
 rt.abc_module_free(m[0])
end
-- A module with no counted requirement must still materialize a retained-capable
-- variant privately. Its local reference has a null owner, not a heap promotion.
local bounded=C.compile{profile='slet',name='bounded-variant.slet',exports={'main'},source=[[
let Point = { x: U32 }
let Choice = oneof { empty: Unit, value: Ref(Point) }
let main(n: U32): U32 = do
 let p=Point { x=n }
 let v=Choice.value(Ref(p))
 return v { empty()=0, value(p)=p.x }
end
]]}
check(bounded.materialized~=nil,'bounded variant uses the physical graph')
check(not bounded.assembly:find('FCALL.A __let_rt_source_alloc',1,true),'bounded variant introduces no heap allocation')
for _,proof in pairs(bounded.program.ownership) do check(#proof.summary.counted==0,'bounded variant does not promote roots') end
local boundedRaw=A.assemble(bounded.assembly)
for _,image in ipairs{boundedRaw,O.optimize(boundedRaw)} do
 local m=ffi.new('abc_module *[1]');status(rt.abc_module_load(image,#image,m,err))
 for _,mode in ipairs{0,3,1,2} do
  local vm=ffi.new('abc_vm *[1]');status(rt.abc_vm_create(ffi.new('abc_limits',{mode=mode}),vm,err));status(rt.abc_vm_load(vm[0],m[0],err))
  local input=ffi.new('uint64_t[1]',42);local out=ffi.new('uint64_t[1]');local count=ffi.new('size_t[1]')
  status(rt.abc_vm_call(vm[0],m[0],'main',input,1,out,1,count,err));executions=executions+1
  check(out[0]==42 and count[0]==1,'bounded variant result');rt.abc_vm_free(vm[0])
 end
 rt.abc_module_free(m[0])
end
local D=require('let.diag')
local ok,problem=pcall(C.typed,{profile='slet',source=[[
let Point = { x: U32 }
let Choice = oneof { empty: Unit, one: Ref(Point) }
let Box = { child: Point, value: Choice }
let bad(): Ref(Box) = do
 let p=Box { child=Point { x=42 }, value=Choice.empty() }
 p.value=Choice.one(Ref(p.child))
 return Ref(p)
end
let main(): U32 = 0
]]})
check(not ok and D.is(problem) and problem.code=='Ref-cycle','tagged owning cycle remains rejected')
-- Public transport and foreign retention are not admitted by the private layout.
for _,test in ipairs{{'let public(n: U32): Choice = Choice.one(leaf(n))','ownership-materialization'},
 {'extern let consume(value: Choice): U32\nlet public(n: U32): U32 = consume(Choice.one(leaf(n)))','borrow-proof'},
 {'let Raw = oneof { pointer: Ptr(U32) }\nlet public(p: Ptr(U32)): Raw = do let keep=leaf(1) return Raw.pointer(p) end','ownership-materialization'},
 {'let Scalar = oneof { value: U32 }\nlet Wrapper = { value: Scalar }\nlet public(n: U32): Wrapper = do let keep=leaf(n) return Wrapper { value=Scalar.value(n) } end','ownership-materialization'}} do
 local success,error=pcall(C.compile,{profile='slet',exports={'public'},source=[[
let Point = { x: U32 }
let Choice = oneof { empty: Unit, one: Ref(Point) }
let leaf(n: U32): Ref(Point) = do let p=Point { x=n } return Ref(p) end
]]..test[1]..'\nlet main(): U32 = 0\n'})
 check(not success and D.is(error) and error.code==test[2],'owning ABI gate remains explicit: '..tostring(error))
end
print(('source owning execution: %d checks, %d four-mode original/optimized calls'):format(checks,executions))
