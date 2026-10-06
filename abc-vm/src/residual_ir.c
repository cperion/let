#include "residual_ir.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct abc_residual_chunk {
    struct abc_residual_chunk *next;
    size_t used;
    size_t capacity;
    max_align_t data[];
} abc_residual_chunk;

struct abc_residual_arena {
    abc_residual_chunk *chunks;
    uint64_t next_id;
};

static int multiply_size(size_t left, size_t right, size_t *result) {
    if (right && left > SIZE_MAX / right) return 0;
    *result = left * right;
    return 1;
}

static size_t align_size(size_t size) {
    const size_t alignment = _Alignof(max_align_t);
    if (size > SIZE_MAX - alignment + 1) return 0;
    return (size + alignment - 1) / alignment * alignment;
}

abc_residual_arena *abc_residual_arena_create(void) {
    abc_residual_arena *arena = calloc(1, sizeof(*arena));
    if (arena) arena->next_id = 1;
    return arena;
}

void abc_residual_arena_free(abc_residual_arena *arena) {
    if (!arena) return;
    abc_residual_chunk *chunk = arena->chunks;
    while (chunk) {
        abc_residual_chunk *next = chunk->next;
        free(chunk);
        chunk = next;
    }
    free(arena);
}

void *abc_residual_allocate(abc_residual_arena *arena, size_t count, size_t element_size) {
    if (!arena) return NULL;
    size_t bytes;
    if (!multiply_size(count, element_size, &bytes)) return NULL;
    if (!bytes) return NULL;
    bytes = align_size(bytes);
    if (!bytes) return NULL;

    abc_residual_chunk *chunk = arena->chunks;
    if (!chunk || bytes > chunk->capacity - chunk->used) {
        size_t capacity = 16384;
        if (capacity < bytes) capacity = bytes;
        if (capacity > SIZE_MAX - sizeof(*chunk)) return NULL;
        chunk = malloc(sizeof(*chunk) + capacity);
        if (!chunk) return NULL;
        chunk->next = arena->chunks;
        chunk->used = 0;
        chunk->capacity = capacity;
        arena->chunks = chunk;
    }

    unsigned char *bytes_start = (unsigned char *)chunk->data;
    void *result = bytes_start + chunk->used;
    chunk->used += bytes;
    memset(result, 0, bytes);
    return result;
}

void *abc_residual_copy(abc_residual_arena *arena, const void *items, size_t count, size_t element_size) {
    if (!count) return NULL;
    void *copy = abc_residual_allocate(arena, count, element_size);
    if (!copy) return NULL;
    memcpy(copy, items, count * element_size);
    return copy;
}

abc_asdl_string abc_residual_string(abc_residual_arena *arena, const char *text) {
    abc_asdl_string result = {0};
    if (!text) return result;
    result.length = strlen(text);
    char *copy = abc_residual_allocate(arena, result.length + 1, 1);
    if (!copy) { result.length = 0; return result; }
    memcpy(copy, text, result.length + 1);
    result.data = copy;
    return result;
}

abc_residual_id abc_residual_new_id(abc_residual_arena *arena) {
    abc_residual_id result = {0};
    if (!arena || !arena->next_id) return result;
    result.value = arena->next_id++;
    return result;
}

abc_residual_origin abc_residual_make_origin(abc_residual_arena *arena, uint64_t offset,
                                                 const abc_residual_origin *caller) {
    abc_residual_origin result = {.offset = offset};
    size_t count = 0;
    for (const abc_residual_origin *at = caller; at; at = at->caller) {
        if (count == SIZE_MAX) return result;
        count++;
    }
    if (!count) return result;
    abc_residual_origin *chain = abc_residual_allocate(arena, count, sizeof(*chain));
    if (!chain) return result;
    const abc_residual_origin *source = caller;
    for (size_t i = 0; i < count; i++, source = source->caller) {
        chain[i].offset = source->offset;
        chain[i].caller = i + 1 < count ? &chain[i + 1] : NULL;
    }
    result.caller = chain;
    return result;
}
