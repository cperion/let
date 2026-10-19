-- Exact ABI cells, not host numeric approximations or scalar-only staging wrappers.
package.path='./?.lua;./?/init.lua;../tools/?.lua;../build/?.lua;'..package.path
local C,S=require('let.compiler'),require('let.schema')
require('let.ir')
local Stage,ffi,Int=require('let.stage'),require('let.abi'),require('int64')
local I,L=S.Ir,S.ASDL.List
local checks,executions,fixturesRun=0,0,0
local function check(ok,why) checks=checks+1;assert(ok,why) end
local function u(n,ty) return I.Const(ty or S.U32,I.UInt(n)) end
local function ref(id,ty) return I.Ref(I.Value(id),ty) end
local function fn(name,inputs,results,params,body)
 return I.Fn(name,I.Entry,0,L(inputs),L(results),L(params),L(body))
end
local function run(functions,arguments,expected,storage)
 fixturesRun=fixturesRun+1
 local artifact=C.lower(functions,{profile='slet',exports={'main'}})
 if not storage then
  check(not artifact.assembly:find('CALLOC',1,true) and not artifact.assembly:find('FADDR',1,true),'value-only tagged function allocated storage')
 else check(artifact.assembly:find('CALLOC',1,true),'actual storage must remain explicit') end
 for _,optimized in ipairs{false,true} do
  for _,mode in ipairs{'interpreted','threaded','eager','lazy'} do
   local session=Stage.open{mode=mode,optimize=optimized}
   local ok,program=pcall(session.prepare,session,artifact,functions)
   assert(ok,'fixture '..fixturesRun..' '..mode..' optimized='..tostring(optimized)..': '..tostring(program)..'\n'..artifact.assembly)
   local args=ffi.new('uint64_t[?]',math.max(1,#arguments))
   for index,value in ipairs(arguments) do args[index-1]=Int.parse(value) end
   local output=ffi.new('uint64_t[?]',math.max(1,#expected))
   local count,err=ffi.new('size_t[1]'),ffi.new('abc_error[1]')
   local status=session.C.abc_vm_call(session.vm,program.handle,'main',args,#arguments,output,#expected,count,err)
   check(status==0,mode..' optimize='..tostring(optimized)..': '..ffi.string(err[0].message))
   check(tonumber(count[0])==#expected,'result cell count')
   for index,value in ipairs(expected) do check(output[index-1]==Int.parse(value),mode..' cell '..index..': '..tostring(output[index-1])..' wanted '..value) end
   executions=executions+1;session:close()
  end
 end
end
local fixtures={
 {S.Unit,nil,{'0'}},
 {S.U8,u(171,S.U8),{'0xab00000000'}},
 {S.U16,u(43981,S.U16),{'0xabcd00000000'}},
 {S.U32,u(2309737967),{'0x89abcdef00000000'}},
 {S.I32,I.Un(I.Neg,u(1,S.I32),S.I32),{'0xffffffff00000000'}},
 {S.U64,I.Const(S.U64,I.UInt64(19088743,2309737967)),{'0','0x0123456789abcdef'}},
}
local record=S.Record{a=S.U8,b=S.U16,c=S.U32}
fixtures[#fixtures+1]={record,I.Make(record,L{u(18,S.U8),u(13398,S.U16),u(2309737967)}),{'0x3456001200000000','0x89abcdef'}}
local array=S.Array(S.U8,5)
fixtures[#fixtures+1]={array,I.Make(array,L{u(1,S.U8),u(2,S.U8),u(3,S.U8),u(4,S.U8),u(5,S.U8)}),{'0x0403020100000000','5'}}
for _,case in ipairs(fixtures) do
 local ty=S.Sum{value=case[1]}
 run({fn('main',{}, {ty},{},{I.ConstructVariant(I.Value(1),ty,'value',case[2]),I.Return(L{ref(1,ty)})})},{},case[3])
 -- Exact forwarding includes deliberately noncanonical incoming padding.
 local args={};for index,value in ipairs(case[3]) do args[index]=value end
 args[1]='0xfedcba9876543210'
 run({fn('main',{S.inValue(ty)},{ty},{I.ValueParam(0,I.Value(1),ty)},{I.Return(L{ref(1,ty)})})},args,args)
end
local inner=S.Sum{value=record};local outer=S.Sum{nested=inner}
run({fn('main',{}, {outer},{},{
 I.ConstructVariant(I.Value(1),inner,'value',I.Make(record,L{u(18,S.U8),u(13398,S.U16),u(2309737967)})),
 I.ConstructVariant(I.Value(2),outer,'nested',ref(1,inner)),I.Return(L{ref(2,outer)})
})},{},{'0','0x89abcdef34560012'})
run({fn('main',{S.inValue(outer)},{inner},{I.ValueParam(0,I.Value(1),outer)},{
 I.VariantPayload(I.Value(2),I.Value(1),outer,'nested'),I.Return(L{ref(2,inner)})
})},{'0','0x89abcdef34560012'},{'0x3456001200000000','0x89abcdef'})
-- Taking an address forces actual storage. The logical size is 12 bytes, not 16.
run({fn('main',{S.inValue(inner)},{inner},{I.ValueParam(0,I.Value(1),inner)},{
 I.Var(I.Storage(1),inner,ref(1,inner)),I.Var(I.Storage(2),S.Ref(inner),I.Addr(I.Local(I.Storage(1)),S.Ref(inner))),
 I.Read(I.Value(3),inner,I.Deref(I.Local(I.Storage(2)),inner)),I.Return(L{ref(3,inner)})
})},{'0x3456001200000000','0xfeedface89abcdef'},{'0x3456001200000000','0x89abcdef'},true)
-- Runtime constructor inputs, distinct alternatives, mutable cell storage, and
-- ordinary direct/indirect transport retain one authoritative packed ABI.
local choice=S.Sum{empty=S.Unit,small=S.U32,wide=S.U64}
-- The wide alternative gives every payload 8-byte alignment.
for _,case in ipairs{{'small',S.U32,'0x89abcdef',{'1','0x89abcdef'}},
 {'wide',S.U64,'0x0123456789abcdef',{'2','0x0123456789abcdef'}}} do
 run({fn('main',{S.inValue(case[2])},{choice},{I.ValueParam(0,I.Value(1),case[2])},{
  I.ConstructVariant(I.Value(2),choice,case[1],ref(1,case[2])),I.Return(L{ref(2,choice)})
 })},{case[3]},case[4])
end
run({fn('main',{S.inValue(choice)},{choice},{I.ValueParam(0,I.Value(1),choice)},{
 I.Var(I.Storage(1),choice,ref(1,choice)),I.ConstructVariant(I.Value(2),choice,'empty',nil),
 I.Store(I.Local(I.Storage(1)),ref(2,choice)),I.Read(I.Value(3),choice,I.Local(I.Storage(1))),I.Return(L{ref(3,choice)})
})},{'2','0xffffffffffffffff'},{'0','0'})
local identity=fn('identity',{S.inValue(inner)},{inner},{I.ValueParam(0,I.Value(1),inner)},{I.Return(L{ref(1,inner)})})
run({identity,fn('main',{S.inValue(inner)},{inner},{I.ValueParam(0,I.Value(1),inner)},{
 I.Call(L{I.Value(2)},'identity',L{I.ValueArg(ref(1,inner))}),I.Return(L{ref(2,inner)})
})},{'0x3456001200000000','0xfeedface89abcdef'},{'0x3456001200000000','0xfeedface89abcdef'})
local view=S.View(S.Sig({S.inValue(inner)},{inner}))
run({identity,fn('main',{S.inValue(inner)},{inner},{I.ValueParam(0,I.Value(1),inner)},{
 I.View(I.Value(2),view,'identity',L{},nil),
 I.Indirect(L{I.Value(3)},ref(2,view),L{I.ValueArg(ref(1,inner))}),I.Return(L{ref(3,inner)})
})},{'0x3456001200000000','0xfeedface89abcdef'},{'0x3456001200000000','0xfeedface89abcdef'})
local truth=S.Sum{value=S.Bool}
run({fn('main',{S.inValue(S.Bool)},{truth},{I.ValueParam(0,I.Value(1),S.Bool)},{
 I.ConstructVariant(I.Value(2),truth,'value',ref(1,S.Bool)),I.Return(L{ref(2,truth)})
})},{'1'},{'0x100000000'})
print(('packed tagged integer/storage subset: %d checks, %d VM executions'):format(checks,executions))
-- Explicit raw-kind transitions: exact construction, runtime transport and extraction.
local floating=S.Sum{value=S.F64}
for _,bits in ipairs{{0,0,'0'},{2147483648,0,'0x8000000000000000'},
 {0,1,'1'},{1048575,4294967295,'0x000fffffffffffff'},
 {1073217536,0,'0x3ff8000000000000'},
 {2146435072,0,'0x7ff0000000000000'},{4293918720,0,'0xfff0000000000000'},
 {2146959360,305419896,'0x7ff8000012345678'},
 {2146435072,1,'0x7ff0000000000001'},{4293993285,1737075661,'0xfff123456789abcd'}} do
 run({fn('main',{}, {floating},{},{I.ConstructVariant(I.Value(1),floating,'value',I.Const(S.F64,I.FloatBits(bits[1],bits[2]))),I.Return(L{ref(1,floating)})})},{},{'0',bits[3]})
 run({fn('main',{S.inValue(S.F64)}, {floating},{I.ValueParam(0,I.Value(1),S.F64)},{
  I.ConstructVariant(I.Value(2),floating,'value',ref(1,S.F64)),I.Return(L{ref(2,floating)})
 })},{bits[3]},{'0',bits[3]})
 run({fn('main',{S.inValue(floating)}, {S.F64},{I.ValueParam(0,I.Value(1),floating)},{
  I.VariantPayload(I.Value(2),I.Value(1),floating,'value'),I.Return(L{ref(2,S.F64)})
 })},{'0',bits[3]},{bits[3]})
end
-- Decoded values participate in real floating arithmetic, not merely byte copying.
run({fn('main',{S.inValue(floating)}, {S.F64},{I.ValueParam(0,I.Value(1),floating)},{
 I.VariantPayload(I.Value(2),I.Value(1),floating,'value'),
 I.Return(L{I.Bin(I.Add,ref(2,S.F64),I.Const(S.F64,I.FloatBits(1073741824,0)),S.F64)})
})},{'0','0x3ff8000000000000'},{'0x400c000000000000'})
-- Mixed aggregates and nested sums decode/encode floats through the same leaves.
local mixed=S.Record{a=S.U8,b=S.F64,c=S.U16}
local mixedSum=S.Sum{value=mixed};local nestedFloat=S.Sum{nested=mixedSum}
run({fn('main',{S.inValue(S.F64)}, {nestedFloat},{I.ValueParam(0,I.Value(1),S.F64)},{
 I.ConstructVariant(I.Value(2),mixedSum,'value',I.Make(mixed,L{u(171,S.U8),ref(1,S.F64),u(43981,S.U16)})),
 I.ConstructVariant(I.Value(3),nestedFloat,'nested',ref(2,mixedSum)),I.Return(L{ref(3,nestedFloat)})
})},{'0x7ff8000012345678'},{'0','0','171','0x7ff8000012345678','43981'})
run({fn('main',{S.inValue(nestedFloat)}, {mixed},{I.ValueParam(0,I.Value(1),nestedFloat)},{
 I.VariantPayload(I.Value(2),I.Value(1),nestedFloat,'nested'),
 I.VariantPayload(I.Value(3),I.Value(2),mixedSum,'value'),I.Return(L{ref(3,mixed)})
})},{'0','0','171','0x7ff8000012345678','43981'},{'171','0x7ff8000012345678','43981'})
local floatArray=S.Array(S.F64,2);local arraySum=S.Sum{value=floatArray}
run({fn('main',{S.inValue(S.F64),S.inValue(S.F64)}, {arraySum},{I.ValueParam(0,I.Value(1),S.F64),I.ValueParam(1,I.Value(2),S.F64)},{
 I.ConstructVariant(I.Value(3),arraySum,'value',I.Make(floatArray,L{ref(1,S.F64),ref(2,S.F64)})),I.Return(L{ref(3,arraySum)})
})},{'0x8000000000000000','0x7ff0000000000001'},{'0','0x8000000000000000','0x7ff0000000000001'})
run({fn('main',{S.inValue(arraySum)}, {floatArray},{I.ValueParam(0,I.Value(1),arraySum)},{
 I.VariantPayload(I.Value(2),I.Value(1),arraySum,'value'),I.Return(L{ref(2,floatArray)})
})},{'0','0x8000000000000000','0x7ff0000000000001'},{'0x8000000000000000','0x7ff0000000000001'})
local transport=fn('transport',{S.inValue(floating)},{floating},{I.ValueParam(0,I.Value(1),floating)},{I.Return(L{ref(1,floating)})})
local floatView=S.View(S.Sig({S.inValue(floating)},{floating}))
run({transport,fn('main',{S.inValue(S.F64)},{S.F64},{I.ValueParam(0,I.Value(1),S.F64)},{
 I.ConstructVariant(I.Value(2),floating,'value',ref(1,S.F64)),
 I.Call(L{I.Value(3)},'transport',L{I.ValueArg(ref(2,floating))}),
 I.View(I.Value(4),floatView,'transport',L{},nil),
 I.Indirect(L{I.Value(5)},ref(4,floatView),L{I.ValueArg(ref(3,floating))}),
 I.VariantPayload(I.Value(6),I.Value(5),floating,'value'),I.Return(L{ref(6,S.F64)})
})},{'0x7ff0000000000001'},{'0x7ff0000000000001'})
run({fn('main',{S.inValue(S.F64)},{S.F64},{I.ValueParam(0,I.Value(1),S.F64)},{
 I.ConstructVariant(I.Value(2),floating,'value',ref(1,S.F64)),I.Var(I.Storage(1),floating,ref(2,floating)),
 I.Var(I.Storage(2),S.Ref(floating),I.Addr(I.Local(I.Storage(1)),S.Ref(floating))),
 I.Read(I.Value(3),floating,I.Deref(I.Local(I.Storage(2)),floating)),
 I.VariantPayload(I.Value(4),I.Value(3),floating,'value'),I.Return(L{ref(4,S.F64)})
})},{'0x8000000000000000'},{'0x8000000000000000'},true)
print(('packed tagged: %d checks, %d VM executions'):format(checks,executions))
