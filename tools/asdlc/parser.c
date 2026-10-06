#include "asdlc.h"

#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    TOKEN_EOF,
    TOKEN_IDENTIFIER,
    TOKEN_LEFT_PAREN,
    TOKEN_RIGHT_PAREN,
    TOKEN_LEFT_BRACE,
    TOKEN_RIGHT_BRACE,
    TOKEN_EQUALS,
    TOKEN_PIPE,
    TOKEN_COMMA,
    TOKEN_QUESTION,
    TOKEN_STAR,
    TOKEN_DOT
} token_kind;

typedef struct {
    token_kind kind;
    const char *start;
    size_t length;
    unsigned line;
    unsigned column;
} token;

typedef struct {
    asdl_source source;
    size_t offset;
    unsigned line;
    unsigned column;
    token current;
    asdl_schema *schema;
    asdl_error *error;
    int failed;
} parser;

static void report(parser *p, unsigned line, unsigned column, const char *format, ...) {
    if (p->failed) return;
    p->failed = 1;
    p->error->path = p->source.path;
    p->error->line = line;
    p->error->column = column;
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(p->error->message, sizeof(p->error->message), format, arguments);
    va_end(arguments);
}

static int is_identifier_start(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
}

static int is_identifier_continue(char c) {
    return is_identifier_start(c) || (c >= '0' && c <= '9');
}

static void advance_character(parser *p) {
    char c = p->source.text[p->offset++];
    if (c == '\n') {
        p->line++;
        p->column = 1;
    } else {
        p->column++;
    }
}

static void skip_space_and_comments(parser *p) {
    for (;;) {
        while (p->offset < p->source.length) {
            char c = p->source.text[p->offset];
            if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
            advance_character(p);
        }
        if (p->offset >= p->source.length || p->source.text[p->offset] != '#') return;
        while (p->offset < p->source.length && p->source.text[p->offset] != '\n')
            advance_character(p);
    }
}

static void next_token(parser *p) {
    skip_space_and_comments(p);
    token next = {.line = p->line, .column = p->column};
    if (p->offset >= p->source.length) {
        next.kind = TOKEN_EOF;
        p->current = next;
        return;
    }

    next.start = p->source.text + p->offset;
    char c = p->source.text[p->offset];
    if (is_identifier_start(c)) {
        advance_character(p);
        while (p->offset < p->source.length && is_identifier_continue(p->source.text[p->offset]))
            advance_character(p);
        next.kind = TOKEN_IDENTIFIER;
        next.length = (size_t)(p->source.text + p->offset - next.start);
        p->current = next;
        return;
    }

    advance_character(p);
    next.length = 1;
    switch (c) {
    case '(': next.kind = TOKEN_LEFT_PAREN; break;
    case ')': next.kind = TOKEN_RIGHT_PAREN; break;
    case '{': next.kind = TOKEN_LEFT_BRACE; break;
    case '}': next.kind = TOKEN_RIGHT_BRACE; break;
    case '=': next.kind = TOKEN_EQUALS; break;
    case '|': next.kind = TOKEN_PIPE; break;
    case ',': next.kind = TOKEN_COMMA; break;
    case '?': next.kind = TOKEN_QUESTION; break;
    case '*': next.kind = TOKEN_STAR; break;
    case '.': next.kind = TOKEN_DOT; break;
    default:
        report(p, next.line, next.column, "unexpected character '%c'", c);
        next.kind = TOKEN_EOF;
        break;
    }
    p->current = next;
}

static int token_is(const parser *p, token_kind kind) {
    return p->current.kind == kind;
}

static int token_spells(const parser *p, const char *text) {
    size_t length = strlen(text);
    return p->current.kind == TOKEN_IDENTIFIER && p->current.length == length &&
           memcmp(p->current.start, text, length) == 0;
}

static int accept(parser *p, token_kind kind) {
    if (!token_is(p, kind)) return 0;
    next_token(p);
    return 1;
}

static int expect(parser *p, token_kind kind, const char *description) {
    if (accept(p, kind)) return 1;
    report(p, p->current.line, p->current.column, "expected %s", description);
    return 0;
}

static const char *take_identifier(parser *p, const char *description) {
    if (!token_is(p, TOKEN_IDENTIFIER)) {
        report(p, p->current.line, p->current.column, "expected %s", description);
        return NULL;
    }
    const char *result = asdl_arena_copy(p->schema->arena, p->current.start, p->current.length);
    if (!result) report(p, p->current.line, p->current.column, "out of memory");
    next_token(p);
    return result;
}

static const char *parse_qualified_name(parser *p) {
    const char *first = take_identifier(p, "a type name");
    if (!first || !accept(p, TOKEN_DOT)) return first;
    const char *second = take_identifier(p, "a name after '.'");
    if (!second) return NULL;
    size_t first_length = strlen(first), second_length = strlen(second);
    char *result = asdl_arena_allocate(p->schema->arena, first_length + second_length + 2);
    if (!result) {
        report(p, p->current.line, p->current.column, "out of memory");
        return NULL;
    }
    memcpy(result, first, first_length);
    result[first_length] = '.';
    memcpy(result + first_length + 1, second, second_length + 1);
    if (accept(p, TOKEN_DOT))
        report(p, p->current.line, p->current.column, "type names may contain at most one '.'");
    return result;
}

static int append_field(parser *p, asdl_fields *fields, asdl_field field) {
    void *items = asdl_grow_array(fields->items, &fields->capacity, fields->count, sizeof(field));
    if (!items) {
        report(p, field.line, field.column, "out of memory");
        return 0;
    }
    fields->items = items;
    fields->items[fields->count++] = field;
    return 1;
}

static int parse_fields(parser *p, asdl_fields *fields) {
    if (!expect(p, TOKEN_LEFT_PAREN, "'('") || accept(p, TOKEN_RIGHT_PAREN)) return !p->failed;
    for (;;) {
        asdl_field field = {.line = p->current.line, .column = p->current.column};
        field.type_name = parse_qualified_name(p);
        if (accept(p, TOKEN_QUESTION)) field.quantifier = ASDL_OPTIONAL;
        else if (accept(p, TOKEN_STAR)) field.quantifier = ASDL_SEQUENCE;
        else field.quantifier = ASDL_ONE;
        field.name = take_identifier(p, "a field name");
        if (p->failed || !append_field(p, fields, field)) return 0;
        if (!accept(p, TOKEN_COMMA)) break;
    }
    return expect(p, TOKEN_RIGHT_PAREN, "')'");
}

static int append_constructor(parser *p, asdl_constructors *constructors, asdl_constructor constructor) {
    void *items = asdl_grow_array(constructors->items, &constructors->capacity, constructors->count, sizeof(constructor));
    if (!items) {
        report(p, constructor.line, constructor.column, "out of memory");
        return 0;
    }
    constructors->items = items;
    constructors->items[constructors->count++] = constructor;
    return 1;
}

static int parse_constructor(parser *p, asdl_constructors *constructors) {
    asdl_constructor constructor = {.line = p->current.line, .column = p->current.column};
    constructor.name = take_identifier(p, "a constructor name");
    if (token_is(p, TOKEN_LEFT_PAREN) && !parse_fields(p, &constructor.fields)) {
        free(constructor.fields.items);
        return 0;
    }
    return !p->failed && append_constructor(p, constructors, constructor);
}

static int append_type(parser *p, asdl_types *types, asdl_type type) {
    void *items = asdl_grow_array(types->items, &types->capacity, types->count, sizeof(type));
    if (!items) {
        report(p, type.line, type.column, "out of memory");
        return 0;
    }
    types->items = items;
    types->items[types->count++] = type;
    return 1;
}

static int parse_type(parser *p, asdl_types *types) {
    asdl_type type = {.line = p->current.line, .column = p->current.column};
    type.name = take_identifier(p, "a type name");
    if (!expect(p, TOKEN_EQUALS, "'='") || p->failed) return 0;
    if (token_is(p, TOKEN_LEFT_PAREN)) {
        type.kind = ASDL_PRODUCT;
        if (!parse_fields(p, &type.fields)) goto failed;
    } else {
        type.kind = ASDL_SUM;
        do {
            if (!parse_constructor(p, &type.constructors)) goto failed;
        } while (accept(p, TOKEN_PIPE));
        if (token_spells(p, "attributes")) {
            next_token(p);
            if (!parse_fields(p, &type.attributes)) goto failed;
        }
    }
    return append_type(p, types, type);

failed:
    free(type.fields.items);
    free(type.attributes.items);
    for (size_t i = 0; i < type.constructors.count; i++) free(type.constructors.items[i].fields.items);
    free(type.constructors.items);
    return 0;
}

static int append_module(parser *p, asdl_modules *modules, asdl_module module) {
    void *items = asdl_grow_array(modules->items, &modules->capacity, modules->count, sizeof(module));
    if (!items) {
        report(p, module.line, module.column, "out of memory");
        return 0;
    }
    modules->items = items;
    modules->items[modules->count++] = module;
    return 1;
}

static int parse_module(parser *p) {
    asdl_module module = {.line = p->current.line, .column = p->current.column};
    if (!token_spells(p, "module")) {
        report(p, p->current.line, p->current.column, "expected 'module'");
        return 0;
    }
    next_token(p);
    module.name = take_identifier(p, "a module name");
    if (!expect(p, TOKEN_LEFT_BRACE, "'{'") || p->failed) return 0;
    while (!token_is(p, TOKEN_RIGHT_BRACE) && !token_is(p, TOKEN_EOF))
        if (!parse_type(p, &module.types)) goto failed;
    if (!expect(p, TOKEN_RIGHT_BRACE, "'}'") || !append_module(p, &p->schema->modules, module))
        goto failed;
    return 1;

failed:
    for (size_t i = 0; i < module.types.count; i++) {
        asdl_type *type = &module.types.items[i];
        free(type->fields.items);
        free(type->attributes.items);
        for (size_t j = 0; j < type->constructors.count; j++) free(type->constructors.items[j].fields.items);
        free(type->constructors.items);
    }
    free(module.types.items);
    return 0;
}

int asdl_parse(asdl_source source, asdl_schema *schema, asdl_error *error) {
    if (!schema || !error || !source.text) return 0;
    memset(schema, 0, sizeof(*schema));
    memset(error, 0, sizeof(*error));
    schema->arena = asdl_arena_create();
    if (!schema->arena) {
        snprintf(error->message, sizeof(error->message), "out of memory");
        error->path = source.path;
        return 0;
    }

    parser p = {
        .source = source, .line = 1, .column = 1, .schema = schema, .error = error
    };
    next_token(&p);
    while (!p.failed && !token_is(&p, TOKEN_EOF))
        if (!parse_module(&p)) break;
    if (!p.failed && schema->modules.count == 0) report(&p, 1, 1, "schema contains no modules");
    if (p.failed) {
        asdl_schema_dispose(schema);
        return 0;
    }
    return 1;
}
