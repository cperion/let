#ifndef ABC_TYPE_OPS_H
#define ABC_TYPE_OPS_H
#include <stddef.h>
#include <stdint.h>
typedef enum { ABC_OWNER_LOCAL, ABC_OWNER_SHARED, ABC_OWNER_IMMORTAL } abc_owner_kind;
typedef uint32_t abc_type_op_id;
struct abc_image;
typedef struct abc_type_ops {
    size_t payload_size,payload_align;
    abc_owner_kind owner_kind;
    abc_type_op_id copy_holding,release_holdings;
    struct abc_image *image;
    struct abc_type_ops *next;
} abc_type_ops;
/* Operation ids are module function identities, resolved by image. No fixed
 * layout tags, serialized native pointers, or field-plan interpretation. */
#endif
