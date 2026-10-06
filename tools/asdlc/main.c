#define _POSIX_C_SOURCE 200809L
#include "asdlc.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    const char *input_path;
    const char *header_path;
    const char *source_path;
    int check_only;
} options;

static void usage(FILE *output) {
    fputs("usage: abc-asdlc --check SCHEMA\n", output);
    fputs("       abc-asdlc SCHEMA --header OUTPUT.h --source OUTPUT.c\n", output);
}

static int parse_options(int argc, char **argv, options *result) {
    memset(result, 0, sizeof(*result));
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--check") == 0) result->check_only = 1;
        else if (strcmp(argv[i], "--header") == 0 && i + 1 < argc) result->header_path = argv[++i];
        else if (strcmp(argv[i], "--source") == 0 && i + 1 < argc) result->source_path = argv[++i];
        else if (argv[i][0] == '-' || result->input_path) return 0;
        else result->input_path = argv[i];
    }
    if (!result->input_path) return 0;
    if (result->check_only) return !result->header_path && !result->source_path;
    return result->header_path && result->source_path;
}

static int read_file(const char *path, char **text, size_t *length) {
    FILE *input = fopen(path, "rb");
    if (!input) return 0;
    if (fseek(input, 0, SEEK_END) != 0) { fclose(input); return 0; }
    long end = ftell(input);
    if (end < 0 || fseek(input, 0, SEEK_SET) != 0) { fclose(input); return 0; }
    char *bytes = malloc((size_t)end + 1);
    if (!bytes) { fclose(input); return 0; }
    size_t count = fread(bytes, 1, (size_t)end, input);
    int ok = count == (size_t)end && fclose(input) == 0;
    if (!ok) { free(bytes); return 0; }
    bytes[count] = '\0';
    *text = bytes;
    *length = count;
    return 1;
}

static char *temporary_path(const char *path) {
    size_t length = strlen(path);
    char *result = malloc(length + 5);
    if (!result) return NULL;
    memcpy(result, path, length);
    memcpy(result + length, ".tmp", 5);
    return result;
}

static const char *base_name(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static void make_guard(const char *header_path, char *guard, size_t capacity) {
    const char *base = base_name(header_path);
    size_t at = 0;
    const char prefix[] = "ABC_GENERATED_";
    for (size_t i = 0; prefix[i] && at + 1 < capacity; i++) guard[at++] = prefix[i];
    for (size_t i = 0; base[i] && at + 1 < capacity; i++) {
        unsigned char c = (unsigned char)base[i];
        guard[at++] = isalnum(c) ? (char)toupper(c) : '_';
    }
    guard[at] = '\0';
}

static void print_error(const asdl_error *error, const char *fallback_path) {
    const char *path = error->path ? error->path : fallback_path;
    if (error->line) fprintf(stderr, "%s:%u:%u: error: %s\n", path, error->line, error->column, error->message);
    else fprintf(stderr, "%s: error: %s\n", path, error->message);
}

static int generate(const options *configuration, const asdl_schema *schema, asdl_error *error) {
    char *header_temporary = temporary_path(configuration->header_path);
    char *source_temporary = temporary_path(configuration->source_path);
    if (!header_temporary || !source_temporary) {
        free(header_temporary); free(source_temporary);
        snprintf(error->message, sizeof(error->message), "out of memory");
        return 0;
    }

    FILE *header = fopen(header_temporary, "wb");
    FILE *source = fopen(source_temporary, "wb");
    if (!header || !source) {
        snprintf(error->message, sizeof(error->message), "cannot create output: %s", strerror(errno));
        if (header) fclose(header);
        if (source) fclose(source);
        remove(header_temporary); remove(source_temporary);
        free(header_temporary); free(source_temporary);
        return 0;
    }

    char guard[256];
    make_guard(configuration->header_path, guard, sizeof(guard));
    int ok = asdl_emit_c_header(header, schema, guard, error) &&
             asdl_emit_c_source(source, schema, base_name(configuration->header_path), error);
    if (fclose(header) != 0 || fclose(source) != 0) {
        if (ok) snprintf(error->message, sizeof(error->message), "cannot close generated output: %s", strerror(errno));
        ok = 0;
    }
    if (ok && rename(header_temporary, configuration->header_path) != 0) {
        snprintf(error->message, sizeof(error->message), "cannot publish %s: %s", configuration->header_path, strerror(errno));
        ok = 0;
    }
    if (ok && rename(source_temporary, configuration->source_path) != 0) {
        snprintf(error->message, sizeof(error->message), "cannot publish %s: %s", configuration->source_path, strerror(errno));
        ok = 0;
    }
    if (!ok) { remove(header_temporary); remove(source_temporary); }
    free(header_temporary); free(source_temporary);
    return ok;
}

int main(int argc, char **argv) {
    options configuration;
    if (!parse_options(argc, argv, &configuration)) { usage(stderr); return 2; }

    char *text = NULL;
    size_t length = 0;
    if (!read_file(configuration.input_path, &text, &length)) {
        fprintf(stderr, "%s: error: cannot read schema: %s\n", configuration.input_path, strerror(errno));
        return 1;
    }

    asdl_schema schema;
    asdl_error error;
    asdl_source source = {configuration.input_path, text, length};
    int ok = asdl_parse(source, &schema, &error);
    if (ok) {
        error.path = configuration.input_path;
        ok = asdl_validate(&schema, &error);
    }
    if (ok && !configuration.check_only) ok = generate(&configuration, &schema, &error);
    if (!ok) print_error(&error, configuration.input_path);
    asdl_schema_dispose(&schema);
    free(text);
    return ok ? 0 : 1;
}
