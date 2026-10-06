#include "asdlc.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static int output_error(asdl_error *error, const char *message) {
    snprintf(error->message, sizeof(error->message), "%s", message);
    return 0;
}

static int is_enum_type(const asdl_type *type) {
    if (type->kind != ASDL_SUM || type->attributes.count != 0) return 0;
    for (size_t i = 0; i < type->constructors.count; i++)
        if (type->constructors.items[i].fields.count != 0) return 0;
    return 1;
}

static void emit_snake_range(FILE *output, const char *name, size_t length) {
    for (size_t i = 0; i < length; i++) {
        unsigned char c = (unsigned char)name[i];
        if (c == '.') {
            fputc('_', output);
            continue;
        }
        if (isupper(c) && i && name[i - 1] != '.' && name[i - 1] != '_' &&
                (islower((unsigned char)name[i - 1]) || isdigit((unsigned char)name[i - 1])))
            fputc('_', output);
        fputc(tolower(c), output);
    }
}

static void emit_snake(FILE *output, const char *name) {
    emit_snake_range(output, name, strlen(name));
}

static void emit_upper(FILE *output, const char *name) {
    for (size_t i = 0; name[i]; i++) {
        unsigned char c = (unsigned char)name[i];
        if (c == '.') c = '_';
        if (isupper(c) && i && name[i - 1] != '.' && name[i - 1] != '_' &&
                (islower((unsigned char)name[i - 1]) || isdigit((unsigned char)name[i - 1])))
            fputc('_', output);
        fputc(toupper(c), output);
    }
}

static int is_c_keyword(const char *name) {
    static const char *const keywords[] = {
        "auto", "break", "case", "char", "const", "continue", "default", "do",
        "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
        "int", "long", "register", "restrict", "return", "short", "signed", "sizeof",
        "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile",
        "while", "_Alignas", "_Alignof", "_Atomic", "_Bool", "_Complex", "_Generic",
        "_Imaginary", "_Noreturn", "_Static_assert", "_Thread_local"
    };
    for (size_t i = 0; i < sizeof(keywords) / sizeof(keywords[0]); i++) {
        size_t j = 0;
        while (name[j] && keywords[i][j] &&
               tolower((unsigned char)name[j]) == tolower((unsigned char)keywords[i][j])) j++;
        if (!name[j] && !keywords[i][j]) return 1;
    }
    return 0;
}

static void emit_member(FILE *output, const char *name) {
    emit_snake(output, name);
    if (is_c_keyword(name)) fputs("_value", output);
}

static void emit_named_type(FILE *output, const asdl_module *module, const char *name) {
    fputs("abc_asdl_", output);
    const char *dot = strchr(name, '.');
    if (dot) {
        emit_snake_range(output, name, (size_t)(dot - name));
        fputc('_', output);
        emit_snake(output, dot + 1);
    } else {
        emit_snake(output, module->name);
        fputc('_', output);
        emit_snake(output, name);
    }
}

static void emit_type(FILE *output, const asdl_module *module, const char *name) {
    if (strcmp(name, "number") == 0) fputs("uint64_t", output);
    else if (strcmp(name, "string") == 0) fputs("abc_asdl_string", output);
    else if (strcmp(name, "boolean") == 0) fputs("bool", output);
    else if (strcmp(name, "any") == 0) fputs("void *", output);
    else emit_named_type(output, module, name);
}

static void emit_tag_type(FILE *output, const asdl_module *module, const asdl_type *type) {
    emit_named_type(output, module, type->name);
    if (!is_enum_type(type)) fputs("_tag", output);
}

static void emit_tag(FILE *output, const asdl_module *module, const asdl_type *type,
                     const asdl_constructor *constructor) {
    fputs("ABC_ASDL_", output);
    emit_upper(output, module->name);
    fputc('_', output);
    emit_upper(output, type->name);
    fputc('_', output);
    emit_upper(output, constructor->name);
}

static void emit_field(FILE *output, const asdl_module *module, const asdl_field *field, unsigned indent) {
    fprintf(output, "%*s", (int)indent, "");
    if (field->quantifier == ASDL_SEQUENCE) {
        fputs("struct { size_t count; ", output);
        emit_type(output, module, field->type_name);
        fputs(" *items; } ", output);
    } else {
        emit_type(output, module, field->type_name);
        if (field->quantifier == ASDL_OPTIONAL) fputs(" *", output);
        else fputc(' ', output);
    }
    emit_member(output, field->name);
    fputs(";\n", output);
}

static void emit_enum(FILE *output, const asdl_module *module, const asdl_type *type) {
    fputs("typedef enum {\n", output);
    for (size_t i = 0; i < type->constructors.count; i++) {
        fputs("    ", output);
        emit_tag(output, module, type, &type->constructors.items[i]);
        if (i == 0) fputs(" = 0", output);
        fputs(i + 1 == type->constructors.count ? "\n" : ",\n", output);
    }
    fputs("} ", output);
    emit_named_type(output, module, type->name);
    fputs(";\n\n", output);
}

static void emit_struct(FILE *output, const asdl_module *module, const asdl_type *type) {
    fputs("struct ", output);
    emit_named_type(output, module, type->name);
    fputs(" {\n", output);
    if (type->kind == ASDL_PRODUCT) {
        for (size_t i = 0; i < type->fields.count; i++) emit_field(output, module, &type->fields.items[i], 4);
    } else {
        fputs("    ", output);
        emit_tag_type(output, module, type);
        fputs(" tag;\n", output);
        int emitted_union = 0;
        for (size_t i = 0; i < type->constructors.count; i++)
            emitted_union |= type->constructors.items[i].fields.count != 0;
        if (emitted_union) {
            fputs("    union {\n", output);
            for (size_t i = 0; i < type->constructors.count; i++) {
                const asdl_constructor *constructor = &type->constructors.items[i];
                if (!constructor->fields.count) continue;
                fputs("        struct {\n", output);
                for (size_t j = 0; j < constructor->fields.count; j++)
                    emit_field(output, module, &constructor->fields.items[j], 12);
                fputs("        } ", output);
                emit_member(output, constructor->name);
                fputs(";\n", output);
            }
            fputs("    } value;\n", output);
        }
        for (size_t i = 0; i < type->attributes.count; i++) emit_field(output, module, &type->attributes.items[i], 4);
    }
    fputs("};\n\n", output);
}

static void emit_payload_tag(FILE *output, const asdl_module *module, const asdl_type *type) {
    fputs("typedef enum {\n", output);
    for (size_t i = 0; i < type->constructors.count; i++) {
        fputs("    ", output);
        emit_tag(output, module, type, &type->constructors.items[i]);
        if (i == 0) fputs(" = 0", output);
        fputs(i + 1 == type->constructors.count ? "\n" : ",\n", output);
    }
    fputs("} ", output);
    emit_tag_type(output, module, type);
    fputs(";\n\n", output);
}

static void emit_name_prototype(FILE *output, const asdl_module *module, const asdl_type *type) {
    fputs("const char *", output);
    emit_named_type(output, module, type->name);
    fputs("_tag_name(", output);
    emit_tag_type(output, module, type);
    fputs(" tag);\n", output);
}

int asdl_emit_c_header(FILE *output, const asdl_schema *schema, const char *guard, asdl_error *error) {
    fprintf(output, "/* Generated by abc-asdlc. Do not edit. */\n#ifndef %s\n#define %s\n\n", guard, guard);
    fputs("#include <stdbool.h>\n#include <stddef.h>\n#include <stdint.h>\n\n", output);
    fputs("typedef struct { size_t length; const char *data; } abc_asdl_string;\n\n", output);

    for (size_t m = 0; m < schema->modules.count; m++)
        for (size_t t = 0; t < schema->modules.items[m].types.count; t++) {
            const asdl_type *type = &schema->modules.items[m].types.items[t];
            if (is_enum_type(type)) continue;
            fputs("typedef struct ", output);
            emit_named_type(output, &schema->modules.items[m], type->name);
            fputc(' ', output);
            emit_named_type(output, &schema->modules.items[m], type->name);
            fputs(";\n", output);
        }
    fputc('\n', output);

    for (size_t m = 0; m < schema->modules.count; m++)
        for (size_t t = 0; t < schema->modules.items[m].types.count; t++) {
            const asdl_type *type = &schema->modules.items[m].types.items[t];
            if (is_enum_type(type)) emit_enum(output, &schema->modules.items[m], type);
        }
    for (size_t m = 0; m < schema->modules.count; m++)
        for (size_t t = 0; t < schema->modules.items[m].types.count; t++) {
            const asdl_type *type = &schema->modules.items[m].types.items[t];
            if (!is_enum_type(type) && type->kind == ASDL_SUM)
                emit_payload_tag(output, &schema->modules.items[m], type);
        }
    for (size_t m = 0; m < schema->modules.count; m++)
        for (size_t t = 0; t < schema->modules.items[m].types.count; t++) {
            const asdl_type *type = &schema->modules.items[m].types.items[t];
            if (!is_enum_type(type)) emit_struct(output, &schema->modules.items[m], type);
        }

    fputs("/* Checked tag names are useful to validators and textual dumps. */\n", output);
    for (size_t m = 0; m < schema->modules.count; m++)
        for (size_t t = 0; t < schema->modules.items[m].types.count; t++)
            if (schema->modules.items[m].types.items[t].kind == ASDL_SUM)
                emit_name_prototype(output, &schema->modules.items[m], &schema->modules.items[m].types.items[t]);
    fprintf(output, "\n#endif /* %s */\n", guard);
    return ferror(output) ? output_error(error, "cannot write generated C header") : 1;
}

static void emit_name_function(FILE *output, const asdl_module *module, const asdl_type *type) {
    fputs("const char *", output);
    emit_named_type(output, module, type->name);
    fputs("_tag_name(", output);
    emit_tag_type(output, module, type);
    fputs(" tag) {\n    switch (tag) {\n", output);
    for (size_t i = 0; i < type->constructors.count; i++) {
        fputs("    case ", output);
        emit_tag(output, module, type, &type->constructors.items[i]);
        fprintf(output, ": return \"%s\";\n", type->constructors.items[i].name);
    }
    fputs("    default: return NULL;\n    }\n}\n\n", output);
}

int asdl_emit_c_source(FILE *output, const asdl_schema *schema, const char *header_name, asdl_error *error) {
    fprintf(output, "/* Generated by abc-asdlc. Do not edit. */\n#include \"%s\"\n\n", header_name);
    for (size_t m = 0; m < schema->modules.count; m++)
        for (size_t t = 0; t < schema->modules.items[m].types.count; t++)
            if (schema->modules.items[m].types.items[t].kind == ASDL_SUM)
                emit_name_function(output, &schema->modules.items[m], &schema->modules.items[m].types.items[t]);
    return ferror(output) ? output_error(error, "cannot write generated C source") : 1;
}
