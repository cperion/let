#define _POSIX_C_SOURCE 200809L
#include "vm_internal.h"
#include "residualize.h"
#include "execution_emit.h"
#include <time.h>

static double cpu(void){struct timespec t;if(clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&t))abort();return (double)t.tv_sec+(double)t.tv_nsec/1e9;}
static int compare(const void *a,const void *b){double x=*(const double *)a,y=*(const double *)b;return (x>y)-(x<y);}
int main(int argc,char **argv){
 if(argc!=2)return 2;
 abc_module *module=NULL;abc_error error;
 if(abc_module_read(argv[1],&module,&error)!=ABC_OK){fprintf(stderr,"%s\n",error.message);return 1;}
 const char *names[]={"plain","normal","nested","held_child","copy_pair"};
 for(unsigned mode=0;mode<4;mode++){
  abc_vm *vm=NULL;abc_limits limits={.mode=(abc_execution_mode)mode};
  if(abc_vm_create(&limits,&vm,&error)!=ABC_OK||abc_vm_load(vm,module,&error)!=ABC_OK)return 1;
  abc_owner_context *o=&vm->worker.owners;
  for(unsigned entry=0;entry<sizeof names/sizeof names[0];entry++){
   const size_t iterations=20000;double samples[9];size_t alloc=0,retains=0,releases=0,services=0;
   for(unsigned trial=0;trial<10;trial++){
    size_t a=o->allocations,r=o->retains,d=o->releases,s=vm->worker.service_exits;
    size_t count=trial?iterations:2000;double start=cpu();
    for(size_t i=0;i<count;i++){
     uint64_t result=0;size_t n=0;
     if(abc_vm_call(vm,module,names[entry],NULL,0,&result,1,&n,&error)!=ABC_OK||n!=1||result!=42){fprintf(stderr,"%s: %s\n",names[entry],error.message);return 1;}
    }
    double elapsed=cpu()-start;
    if(trial)samples[trial-1]=elapsed*1e9/(double)count;
    alloc=(o->allocations-a)/count;retains=(o->retains-r)/count;releases=(o->releases-d)/count;services=(vm->worker.service_exits-s)/count;
    if(o->allocations!=o->frees)return 1;
   }
   qsort(samples,9,sizeof *samples,compare);
   printf("mode=%u case=%s median_ns=%.2f allocations=%zu retains=%zu releases=%zu services=%zu live=%zu\n",mode,names[entry],samples[4],alloc,retains,releases,services,o->allocations-o->frees);
  }
  if(vm->images->execution){abc_exec_emitter *e=vm->images->execution->emitter;abc_exec_storage s=e->ops->storage(e);
   printf("mode=%u image_body_bytes=%zu allocation_bytes=%zu regions=%zu cleanup_cells_per_bank=%zu\n",mode,s.body_bytes,s.allocation_bytes,s.regions,vm->worker.cleanup.capacity);
  }else printf("mode=%u cleanup_cells_per_bank=%zu\n",mode,vm->worker.cleanup.capacity);
  abc_vm_free(vm);
 }
 abc_module_free(module);return 0;
}
