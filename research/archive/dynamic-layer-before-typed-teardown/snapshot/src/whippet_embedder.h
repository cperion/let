#ifndef ABC_WHIPPET_EMBEDDER_H
#define ABC_WHIPPET_EMBEDDER_H
#include <stdatomic.h>
#include "whippet_types.h"
#include "gc-atomics.h"
#include "gc-config.h"
#include "gc-embedder-api.h"
#define GC_EMBEDDER_EPHEMERON_HEADER _Atomic uintptr_t tag;
#define GC_EMBEDDER_FINALIZER_HEADER _Atomic uintptr_t tag;
static inline size_t gc_finalizer_priority_count(void) { return 1; }
size_t abc_whippet_trace_object(struct gc_ref, void (*)(struct gc_edge,struct gc_heap *,void *), struct gc_heap *, void *);
void abc_whippet_trace_roots(struct abc_whippet_roots *, void (*)(struct gc_edge,struct gc_heap *,void *), struct gc_heap *, void *);
void abc_whippet_trace_pinned_roots(struct abc_whippet_roots *, void (*)(struct gc_ref,struct gc_heap *,void *), void (*)(uintptr_t,uintptr_t,int,struct gc_heap *,void *), struct gc_heap *, void *);
static inline size_t gc_trace_object(struct gc_ref ref,void (*trace)(struct gc_edge,struct gc_heap *,void *),struct gc_heap *heap,void *data){return abc_whippet_trace_object(ref,trace,heap,data);}
static inline void gc_trace_mutator_roots(struct gc_mutator_roots *roots,void (*trace)(struct gc_edge,struct gc_heap *,void *),struct gc_heap *heap,void *data){abc_whippet_trace_roots((struct abc_whippet_roots *)roots,trace,heap,data);}
static inline void gc_trace_heap_roots(struct gc_heap_roots *roots,void (*trace)(struct gc_edge,struct gc_heap *,void *),struct gc_heap *heap,void *data){abc_whippet_trace_roots((struct abc_whippet_roots *)roots,trace,heap,data);}
static inline void gc_trace_mutator_pinned_roots(struct gc_mutator_roots *roots,void (*pinned)(struct gc_ref,struct gc_heap *,void *),void (*ambiguous)(uintptr_t,uintptr_t,int,struct gc_heap *,void *),struct gc_heap *heap,void *data){abc_whippet_trace_pinned_roots((struct abc_whippet_roots *)roots,pinned,ambiguous,heap,data);}
static inline void gc_trace_heap_pinned_roots(struct gc_heap_roots *roots,void (*pinned)(struct gc_ref,struct gc_heap *,void *),void (*ambiguous)(uintptr_t,uintptr_t,int,struct gc_heap *,void *),struct gc_heap *heap,void *data){abc_whippet_trace_pinned_roots((struct abc_whippet_roots *)roots,pinned,ambiguous,heap,data);}
static inline int gc_is_valid_conservative_ref_displacement(uintptr_t displacement){(void)displacement;return 1;}
static inline int gc_extern_space_visit(struct gc_extern_space *space,struct gc_ref ref){(void)space;(void)ref;GC_CRASH();}
static inline void gc_extern_space_start_gc(struct gc_extern_space *space,int minor){(void)space;(void)minor;}
static inline void gc_extern_space_finish_gc(struct gc_extern_space *space,int minor){(void)space;(void)minor;}
static inline uintptr_t *abc_tag_word(struct gc_ref ref){return &((abc_object *)gc_ref_heap_object(ref))->tag;}
static inline uintptr_t gc_object_forwarded_nonatomic(struct gc_ref ref){uintptr_t tag=*abc_tag_word(ref);return tag&1u?0:tag;}
static inline void gc_object_forward_nonatomic(struct gc_ref ref,struct gc_ref to){*abc_tag_word(ref)=gc_ref_value(to);}
static inline struct gc_atomic_forward gc_atomic_forward_begin(struct gc_ref ref){uintptr_t tag=gc_atomic_load(abc_tag_word(ref));enum gc_forwarding_state state=tag==0?GC_FORWARDING_STATE_BUSY:tag&1u?GC_FORWARDING_STATE_NOT_FORWARDED:GC_FORWARDING_STATE_FORWARDED;return (struct gc_atomic_forward){ref,tag,state};}
static inline int gc_atomic_forward_retry_busy(struct gc_atomic_forward *f){uintptr_t tag=gc_atomic_load(abc_tag_word(f->ref));if(tag==0)return 0;f->data=tag;f->state=tag&1u?GC_FORWARDING_STATE_NOT_FORWARDED:GC_FORWARDING_STATE_FORWARDED;return 1;}
static inline void gc_atomic_forward_acquire(struct gc_atomic_forward *f){uintptr_t expected=f->data;if(gc_atomic_cmpxchg_strong(abc_tag_word(f->ref),&expected,0))f->state=GC_FORWARDING_STATE_ACQUIRED;else{f->data=expected;f->state=expected==0?GC_FORWARDING_STATE_BUSY:GC_FORWARDING_STATE_FORWARDED;}}
static inline void gc_atomic_forward_abort(struct gc_atomic_forward *f){gc_atomic_store(abc_tag_word(f->ref),f->data);f->state=GC_FORWARDING_STATE_NOT_FORWARDED;}
static inline size_t gc_atomic_forward_object_size(struct gc_atomic_forward *f){return ((abc_object *)gc_ref_heap_object(f->ref))->bytes;}
static inline void gc_atomic_forward_commit(struct gc_atomic_forward *f,struct gc_ref to){abc_object *dst=gc_ref_heap_object(to);dst->tag=f->data;gc_atomic_store(abc_tag_word(f->ref),gc_ref_value(to));f->state=GC_FORWARDING_STATE_FORWARDED;}
static inline uintptr_t gc_atomic_forward_address(struct gc_atomic_forward *f){return f->data;}
#endif
