#ifndef ABC_TYPE_OPS_H
#define ABC_TYPE_OPS_H
#include <stddef.h>
#include <stdint.h>

typedef enum { ABC_OWNER_LOCAL, ABC_OWNER_SHARED, ABC_OWNER_IMMORTAL } abc_owner_kind;
typedef uint32_t abc_type_op_id;
typedef struct abc_type_ops {
    size_t payload_size, payload_align;
    abc_owner_kind owner_kind;
    abc_type_op_id copy_holding, release_holdings;
} abc_type_ops;

/* Private runtime operation identities, not bytecode or native function pointers.
 * Initial admission: pointer-free storage and one initialized owner holding.
 * Source-specific aggregate/variant operation generation is not admitted yet. */
#include "generated/type_ops.h"
#endif
