#ifndef ABC_RUNTIME_CALL_H
#define ABC_RUNTIME_CALL_H
#include "internal.h"
#include "generated/runtime_primitives.h"
abc_status abc_runtime_invoke(const abc_extern *,abc_foreign_address,const uint64_t *,uint64_t *);
#endif
