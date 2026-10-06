#ifndef ABC_ASDLC_H
#define ABC_ASDLC_H

#include <stddef.h>
#include <stdio.h>

typedef struct asdl_arena asdl_arena;

typedef struct {
    const char *path;
    const char *text;
    size_t length;
} asdl_source;

typedef struct {
    const char *path;
    unsigned line;
    unsigned column;
    char message[256];
} asdl_error;

typedef enum {
    ASDL_ONE,
    ASDL_OPTIONAL,
    ASDL_SEQUENCE
} asdl_quantifier;

typedef struct {
    const char *type_name;
    const char *name;
    asdl_quantifier quantifier;
    unsigned line;
    unsigned column;
} asdl_field;

typedef struct {
    asdl_field *items;
    size_t count;
    size_t capacity;
} asdl_fields;

typedef struct {
    const char *name;
    asdl_fields fields;
    unsigned line;
    unsigned column;
} asdl_constructor;

typedef struct {
    asdl_constructor *items;
    size_t count;
    size_t capacity;
} asdl_constructors;

typedef enum {
    ASDL_PRODUCT,
    ASDL_SUM
} asdl_type_kind;

typedef struct {
    const char *name;
    asdl_type_kind kind;
    asdl_fields fields;
    asdl_constructors constructors;
    asdl_fields attributes;
    unsigned line;
    unsigned column;
} asdl_type;

typedef struct {
    asdl_type *items;
    size_t count;
    size_t capacity;
} asdl_types;

typedef struct {
    const char *name;
    asdl_types types;
    unsigned line;
    unsigned column;
} asdl_module;

typedef struct {
    asdl_module *items;
    size_t count;
    size_t capacity;
} asdl_modules;

typedef struct {
    asdl_arena *arena;
    asdl_modules modules;
} asdl_schema;

int asdl_parse(asdl_source source, asdl_schema *schema, asdl_error *error);
int asdl_validate(const asdl_schema *schema, asdl_error *error);
void asdl_schema_dispose(asdl_schema *schema);

int asdl_emit_c_header(FILE *output, const asdl_schema *schema, const char *guard, asdl_error *error);
int asdl_emit_c_source(FILE *output, const asdl_schema *schema, const char *header_name, asdl_error *error);

void *asdl_grow_array(void *items, size_t *capacity, size_t count, size_t item_size);
asdl_arena *asdl_arena_create(void);
void *asdl_arena_allocate(asdl_arena *arena, size_t size);
const char *asdl_arena_copy(asdl_arena *arena, const char *text, size_t length);

#endif
