#include "asdlc.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct asdl_arena_block {
    struct asdl_arena_block *next;
    size_t used;
    size_t capacity;
    unsigned char data[];
} asdl_arena_block;

struct asdl_arena {
    asdl_arena_block *blocks;
};

asdl_arena *asdl_arena_create(void) {
    return calloc(1, sizeof(asdl_arena));
}

static size_t aligned_size(size_t size) {
    size_t alignment = sizeof(void *);
    return (size + alignment - 1) & ~(alignment - 1);
}

void *asdl_arena_allocate(asdl_arena *arena, size_t size) {
    size = aligned_size(size ? size : 1);
    asdl_arena_block *block = arena->blocks;
    if (!block || size > block->capacity - block->used) {
        size_t capacity = 4096;
        if (capacity < size) capacity = size;
        if (capacity > SIZE_MAX - sizeof(*block)) return NULL;
        block = malloc(sizeof(*block) + capacity);
        if (!block) return NULL;
        block->next = arena->blocks;
        block->used = 0;
        block->capacity = capacity;
        arena->blocks = block;
    }
    void *result = block->data + block->used;
    block->used += size;
    memset(result, 0, size);
    return result;
}

const char *asdl_arena_copy(asdl_arena *arena, const char *text, size_t length) {
    char *copy = asdl_arena_allocate(arena, length + 1);
    if (!copy) return NULL;
    memcpy(copy, text, length);
    copy[length] = '\0';
    return copy;
}

void *asdl_grow_array(void *items, size_t *capacity, size_t count, size_t item_size) {
    if (count < *capacity) return items;
    size_t next = *capacity ? *capacity * 2 : 8;
    if (next <= count) next = count + 1;
    if (item_size && next > SIZE_MAX / item_size) return NULL;
    void *grown = realloc(items, next * item_size);
    if (!grown) return NULL;
    *capacity = next;
    return grown;
}

void asdl_schema_dispose(asdl_schema *schema) {
    if (!schema) return;
    for (size_t module_index = 0; module_index < schema->modules.count; module_index++) {
        asdl_module *module = &schema->modules.items[module_index];
        for (size_t type_index = 0; type_index < module->types.count; type_index++) {
            asdl_type *type = &module->types.items[type_index];
            free(type->fields.items);
            free(type->attributes.items);
            for (size_t constructor_index = 0; constructor_index < type->constructors.count; constructor_index++)
                free(type->constructors.items[constructor_index].fields.items);
            free(type->constructors.items);
        }
        free(module->types.items);
    }
    free(schema->modules.items);
    if (schema->arena) {
        asdl_arena_block *block = schema->arena->blocks;
        while (block) {
            asdl_arena_block *next = block->next;
            free(block);
            block = next;
        }
        free(schema->arena);
    }
    memset(schema, 0, sizeof(*schema));
}
