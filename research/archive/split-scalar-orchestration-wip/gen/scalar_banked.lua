-- Cache wiring for scalar EXT. Language operations come from scalar_ops.h,
-- generated from the same recipes executed by the symbolic VM.
local M={}
function M.emit(emit,builder,s)
  local function publish()
    for i=0,s.a-1 do emit(('asp[%d]=h%d;'):format(i,i)) end
    for i=0,s.b-1 do emit(('bsp[%d]=h%d;'):format(i,3-i)) end
    for i=0,s.c-1 do emit(('csp[%d]=c%d;'):format(i,i)) end
  end
  local function finish(pops,values)
    local b=builder(s)
    for _=1,pops do b:pop('A',true) end
    for _,v in ipairs(values) do b:push('A',v) end
    b:forget_unused();emit(b:finish())
  end
  local function box(pops,tag,bits)
    emit(('uint64_t boxed;if(%s==ABC_ANY_F64)boxed=encode_float(%s);else if(abc_repr_fits(%s,%s))boxed=immediate(%s,%s);else{'):format(tag,bits,tag,bits,tag,bits))
    publish()
    emit(('boxed=vm_scalar_allocate(asp+%d,bsp+%d,csp+%d,%s,%s);if(!boxed)return abc_fail(e,ABC_NOMEM,pc,"scalar allocation failed");}'):format(s.a,s.b,s.c,tag,bits))
    finish(pops,{'boxed'})
  end
  local peek=builder(s)
  local x=peek:peek('A',0)
  -- A pending request is a collection effect, not a reason to empty the cache
  -- on every scalar instruction. Nonmoving collection leaves bank registers valid.
  emit('if(v->dynamic&&atomic_load(&v->dynamic->collection_requested)){')
  publish()
  emit(('v->ca=v->cb=v->cc=0;v->na=(size_t)(asp-v->a)+%d;v->nb=(size_t)(bsp-v->b)+%d;v->nc=(size_t)(csp-v->c)+%d;abc_dynamic_collect(v);v->na=v->nb=v->nc=0;}'):format(s.a,s.b,s.c))
  emit('if(p[1]==EXT_ANY_BOX||p[1]==EXT_ANY_CAST||p[1]==EXT_ANY_IS){unsigned di=abc_u32(p+2);const abc_descriptor *d=&r->m->descriptors[di];abc_any_layout l=abc_any_descriptor_layout(d);')
  emit('if(p[1]==EXT_ANY_BOX){')
  emit('if(d->tag==ABC_DESC_PRIMITIVE&&d->payload[0]==ABC_PRIM_UNIT){uint64_t boxed=immediate(ABC_ANY_UNIT,0);')
  finish(0,{'boxed'});emit('}')
  emit(('if(d->tag==ABC_DESC_PRIMITIVE&&d->payload[0]>=ABC_PRIM_BOOL&&d->payload[0]<=ABC_PRIM_F64){uint64_t bits=%s;'):format(x))
  box(1,'l.tag','bits');emit('}')
  emit(('if(l.form==ABC_ANY_LAYOUT_IDENTITY){uint64_t value=%s;if(l.tag==ABC_ANY_WORD&&abc_repr_tag(v->dynamic,value,gc_heap_contains)!=ABC_ANY_WORD)ABORT(6);'):format(x))
  finish(1,{'value'});emit('}')
  emit('}else{')
  emit(('uint64_t value=%s;unsigned tag=abc_repr_tag(v->dynamic,value,gc_heap_contains);int matches=l.tag==255||tag==l.tag;abc_object *object=NULL;'):format(x))
  emit('if(!l.form)ABORT(6);if(l.form==ABC_ANY_LAYOUT_OBJECT){object=abc_repr_object(v->dynamic,value,gc_heap_contains);matches=object&&object->kind==l.object_kind&&(!l.exact_descriptor||object->descriptor==di);}')
  emit('if(p[1]==EXT_ANY_IS){');finish(1,{'matches'});emit('}')
  emit('if(l.form==ABC_ANY_LAYOUT_IDENTITY){if(!matches)ABORT(6);');finish(1,{'value'});emit('}')
  emit('if(l.form==ABC_ANY_LAYOUT_OBJECT){if(!matches)ABORT(6);const uint8_t *address=(const uint8_t *)object;uint64_t first=l.address?(uint64_t)(uintptr_t)(address+l.offset[0]):abc_u64(address+l.offset[0]);if(l.cells==2){uint64_t second=l.width[1]==4?abc_u32(address+l.offset[1]):abc_u64(address+l.offset[1]);')
  finish(1,{'first','second'});emit('}else{');finish(1,{'first'});emit('}}')
  emit('if(!abc_repr_scalar(tag))ABORT(6);uint64_t bits=abc_repr_bits(value,tag);if(tag!=l.tag){if(!(abc_numeric_integer(tag)||tag==ABC_ANY_F64)||!(abc_numeric_integer(l.tag)||l.tag==ABC_ANY_F64))ABORT(6);unsigned reason=abc_scalar_convert(tag,l.tag,bits,&bits);if(reason)ABORT(reason);}if(l.cells){')
  finish(1,{'bits'});emit('}else{');finish(1,{});emit('}}}')
  emit('if((p[1]>=EXT_DADD&&p[1]<=EXT_DXOR)||(p[1]>=EXT_DEQ&&p[1]<=EXT_DLE)){')
  emit(('uint64_t x=%s,y=%s,result;unsigned a=abc_repr_tag(v->dynamic,x,gc_heap_contains),b=abc_repr_tag(v->dynamic,y,gc_heap_contains);'):format(peek:peek('A',1),x))
  emit('if(p[1]==EXT_DEQ||p[1]==EXT_DNE){unsigned kind=abc_scalar_equality_kind(a,b);if(kind==UINT_MAX)result=0;else if(kind==ABC_ANY_STRING)result=abc_repr_string_equal(x,y);else if(kind<=ABC_ANY_F64||kind==ABC_ANY_PTR||kind>=14){uint64_t left=abc_repr_bits(x,a),right=abc_repr_bits(y,b);result=kind==ABC_ANY_F64?vm_feq(left,right):kind>=14?abc_scalar_mixed_equal(left,right):left==right;}else result=x==y;if(p[1]==EXT_DNE)result=!result;')
  finish(2,{'result'});emit('}')
  emit('unsigned tag=abc_numeric_result(p[1],a,b);if(tag==UINT_MAX)ABORT(6);unsigned reason=abc_scalar_binary_bits(p[1],tag,abc_repr_bits(x,a),abc_repr_bits(y,b),&result);if(reason)ABORT(reason);if(p[1]==EXT_DLT||p[1]==EXT_DLE){')
  finish(2,{'result'});emit('}');box(2,'tag','result');emit('}')
  emit(('if(p[1]>=EXT_DADDL&&p[1]<=EXT_DXORL){uint64_t value=%s,bits=0,result;unsigned a=abc_repr_tag(v->dynamic,value,gc_heap_contains);const abc_dynamic_constant *literal=&r->m->dynamic_constants[abc_u32(p+2)];unsigned b=abc_primitive_tag(literal->kind);memcpy(&bits,literal->payload,literal->length);if(!abc_scalar_literal(a,&b,&bits,literal->flags&1))ABORT(6);unsigned op=EXT_DADD+(p[1]-EXT_DADDL),tag=abc_numeric_result(op,a,b);if(tag==UINT_MAX)ABORT(6);uint64_t raw=abc_repr_bits(value,a);unsigned reason=abc_scalar_binary_bits(op,tag,p[6]?bits:raw,p[6]?raw:bits,&result);if(reason)ABORT(reason);'):format(x))
  box(1,'tag','result');emit('}')
  emit(('if(p[1]==EXT_DNEG||p[1]==EXT_DNOT||p[1]==EXT_DLNOT||p[1]==EXT_DREQUIRE_BOOL){uint64_t value=%s,result;unsigned tag=abc_repr_tag(v->dynamic,value,gc_heap_contains);if(!abc_repr_scalar(tag))ABORT(6);unsigned reason=abc_scalar_unary_bits(p[1],tag,abc_repr_bits(value,tag),&result);if(reason)ABORT(reason);if(p[1]==EXT_DLNOT||p[1]==EXT_DREQUIRE_BOOL){'):format(x))
  finish(1,{'result'});emit('}');box(1,'tag','result');emit('}')
end
return M
