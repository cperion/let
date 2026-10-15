#ifndef ABC_LIFETIME_H
#define ABC_LIFETIME_H
#include "internal.h"
#include "owner.h"

/* One record embedded in each owning ABC activation. The rest of the concrete
 * frame is compiler-owned storage, not a mirrored list of holdings. */
typedef void (*abc_cleanup_fn)(abc_owner_context *,void *);
typedef struct abc_cleanup_frame {
    struct abc_cleanup_frame *previous;
    abc_cleanup_fn drop;
} abc_cleanup_frame;

/* Load-time declarations, not a per-operation execution dispatcher. */
static inline int abc_source_contract(const abc_extern *e) {
    const char *kinds=NULL;
    if(!strcmp(e->name,"__let_rt_source_alloc"))kinds="aiia";
    else if(!strcmp(e->name,"__let_rt_source_hold")||!strcmp(e->name,"__let_rt_source_clear")||
            !strcmp(e->name,"__let_rt_source_enter")||!strcmp(e->name,"__let_rt_source_drop"))kinds="aa";
    else if(!strcmp(e->name,"__let_rt_source_leave"))kinds="a";
    if(!kinds||e->results||e->arguments!=strlen(kinds))return 0;
    for(unsigned i=0;i<e->arguments;i++)if(e->argument_kinds[i]!=(kinds[i]=='a'?ABC_KIND_ADDR:ABC_KIND_INT))return 0;
    return 1;
}
abc_foreign_bridge_fn abc_source_binding(const abc_extern *);
struct abc_exec_context;
void abc_source_unwind(struct abc_exec_context *);
abc_status abc_source_lifecycle_check(const abc_module *,abc_error *);
#endif
