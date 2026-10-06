#include "asdlc.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static int fail(asdl_error *error, unsigned line, unsigned column, const char *format, ...) {
    error->line = line;
    error->column = column;
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(error->message, sizeof(error->message), format, arguments);
    va_end(arguments);
    return 0;
}

static int is_builtin(const char *name) {
    return strcmp(name, "number") == 0 || strcmp(name, "string") == 0 ||
           strcmp(name, "boolean") == 0 || strcmp(name, "any") == 0;
}

static int is_enum_type(const asdl_type *type) {
    if (type->kind != ASDL_SUM || type->attributes.count != 0) return 0;
    for (size_t i = 0; i < type->constructors.count; i++)
        if (type->constructors.items[i].fields.count != 0) return 0;
    return 1;
}


static const asdl_type *find_local_type(const asdl_module *module, const char *name, size_t *index) {
    for (size_t i = 0; i < module->types.count; i++) {
        if (strcmp(module->types.items[i].name, name) != 0) continue;
        if (index) *index = i;
        return &module->types.items[i];
    }
    return NULL;
}

static const asdl_type *resolve_type(const asdl_schema *schema, const asdl_module *current,
                                     const char *name, const asdl_module **owner, size_t *index) {
    const char *dot = strchr(name, '.');
    if (!dot) {
        if (owner) *owner = current;
        return find_local_type(current, name, index);
    }
    size_t module_length = (size_t)(dot - name);
    for (size_t i = 0; i < schema->modules.count; i++) {
        const asdl_module *module = &schema->modules.items[i];
        if (strlen(module->name) != module_length || memcmp(module->name, name, module_length) != 0) continue;
        if (owner) *owner = module;
        return find_local_type(module, dot + 1, index);
    }
    return NULL;
}

static int validate_field_names(const asdl_fields *fields, asdl_error *error) {
    for (size_t i = 0; i < fields->count; i++)
        for (size_t j = 0; j < i; j++)
            if (strcmp(fields->items[i].name, fields->items[j].name) == 0)
                return fail(error, fields->items[i].line, fields->items[i].column,
                            "duplicate field '%s'", fields->items[i].name);
    return 1;
}

static int validate_fields(const asdl_schema *schema, const asdl_module *module, size_t type_index,
                           const asdl_fields *fields, asdl_error *error) {
    if (!validate_field_names(fields, error)) return 0;
    for (size_t i = 0; i < fields->count; i++) {
        const asdl_field *field = &fields->items[i];
        if (is_builtin(field->type_name)) continue;
        const asdl_module *owner = NULL;
        size_t dependency_index = 0;
        const asdl_type *dependency = resolve_type(schema, module, field->type_name, &owner, &dependency_index);
        if (!dependency)
            return fail(error, field->line, field->column, "unknown field type '%s'", field->type_name);
        if (field->quantifier != ASDL_ONE || is_enum_type(dependency)) continue;
        if (owner == module && dependency_index >= type_index)
            return fail(error, field->line, field->column,
                        "by-value type '%s' must be declared earlier; use '?' or '*' for recursive references",
                        field->type_name);
        if (owner != module) {
            size_t owner_index = 0, module_index = 0;
            while (&schema->modules.items[owner_index] != owner) owner_index++;
            while (&schema->modules.items[module_index] != module) module_index++;
            if (owner_index >= module_index)
                return fail(error, field->line, field->column,
                            "by-value type '%s' belongs to a module declared later", field->type_name);
        }
    }
    return 1;
}

int asdl_validate(const asdl_schema *schema, asdl_error *error) {
    if (!schema || !error) return 0;
    memset(error, 0, sizeof(*error));
    for (size_t module_index = 0; module_index < schema->modules.count; module_index++) {
        const asdl_module *module = &schema->modules.items[module_index];
        for (size_t previous = 0; previous < module_index; previous++)
            if (strcmp(module->name, schema->modules.items[previous].name) == 0)
                return fail(error, module->line, module->column, "duplicate module '%s'", module->name);

        for (size_t type_index = 0; type_index < module->types.count; type_index++) {
            const asdl_type *type = &module->types.items[type_index];
            for (size_t previous = 0; previous < type_index; previous++)
                if (strcmp(type->name, module->types.items[previous].name) == 0)
                    return fail(error, type->line, type->column, "duplicate type '%s.%s'", module->name, type->name);

            if (type->kind == ASDL_PRODUCT) {
                if (!validate_fields(schema, module, type_index, &type->fields, error)) return 0;
                continue;
            }
            if (type->constructors.count == 0)
                return fail(error, type->line, type->column, "sum '%s.%s' has no constructors", module->name, type->name);
            if (!validate_fields(schema, module, type_index, &type->attributes, error)) return 0;
            for (size_t constructor_index = 0; constructor_index < type->constructors.count; constructor_index++) {
                const asdl_constructor *constructor = &type->constructors.items[constructor_index];
                if (strcmp(constructor->name, type->name) == 0)
                    return fail(error, constructor->line, constructor->column,
                                "constructor '%s' conflicts with a type name", constructor->name);
                for (size_t other_type = 0; other_type < module->types.count; other_type++)
                    if (strcmp(constructor->name, module->types.items[other_type].name) == 0)
                        return fail(error, constructor->line, constructor->column,
                                    "constructor '%s' conflicts with a type name", constructor->name);
                for (size_t prior_type = 0; prior_type <= type_index; prior_type++) {
                    const asdl_type *candidate = &module->types.items[prior_type];
                    if (candidate->kind != ASDL_SUM) continue;
                    size_t limit = prior_type == type_index ? constructor_index : candidate->constructors.count;
                    for (size_t prior = 0; prior < limit; prior++)
                        if (strcmp(constructor->name, candidate->constructors.items[prior].name) == 0)
                            return fail(error, constructor->line, constructor->column,
                                        "duplicate constructor '%s' in module '%s'", constructor->name, module->name);
                }
                if (!validate_fields(schema, module, type_index, &constructor->fields, error)) return 0;
            }
        }
    }
    return 1;
}
