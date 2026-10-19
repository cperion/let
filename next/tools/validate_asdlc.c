#include "asdlc/asdlc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int checks;

static void check(int condition, const char *message) {
    checks++;
    if (condition) return;
    fprintf(stderr, "asdlc validation: %s\n", message);
    exit(1);
}

static int parse_and_validate(const char *text, asdl_schema *schema, asdl_error *error) {
    asdl_source source = {"<test>", text, strlen(text)};
    return asdl_parse(source, schema, error) && asdl_validate(schema, error);
}

static void expect_invalid(const char *text, const char *message_fragment) {
    asdl_schema schema;
    asdl_error error;
    int valid = parse_and_validate(text, &schema, &error);
    check(!valid, "invalid schema was accepted");
    check(strstr(error.message, message_fragment) != NULL, "invalid schema produced the wrong diagnostic");
    asdl_schema_dispose(&schema);
}

static char *read_stream(FILE *stream) {
    check(fflush(stream) == 0, "cannot flush generated output");
    check(fseek(stream, 0, SEEK_END) == 0, "cannot seek generated output");
    long length = ftell(stream);
    check(length >= 0 && fseek(stream, 0, SEEK_SET) == 0, "cannot measure generated output");
    char *text = malloc((size_t)length + 1);
    check(text != NULL, "cannot allocate generated-output copy");
    check(fread(text, 1, (size_t)length, stream) == (size_t)length, "cannot read generated output");
    text[length] = '\0';
    return text;
}

int main(void) {
    const char valid_schema[] =
        "# products, sums, options, sequences and attributes\n"
        "module Tree {\n"
        "  Pos = (number line, number column)\n"
        "  Color = Red | Green | Blue\n"
        "  Node = Leaf(number value) | Branch(Node? left, Node? right)\n"
        "         attributes (Pos position)\n"
        "  Forest = (Node* roots, string name, boolean signed)\n"
        "}\n";
    asdl_schema schema;
    asdl_error error;
    check(parse_and_validate(valid_schema, &schema, &error), error.message);
    check(schema.modules.count == 1, "wrong module count");
    check(schema.modules.items[0].types.count == 4, "wrong type count");
    check(schema.modules.items[0].types.items[2].constructors.count == 2, "wrong constructor count");
    check(schema.modules.items[0].types.items[2].attributes.count == 1, "attributes were not parsed");

    FILE *header = tmpfile();
    FILE *source = tmpfile();
    check(header != NULL && source != NULL, "cannot create temporary streams");
    check(asdl_emit_c_header(header, &schema, "TEST_GENERATED_H", &error), error.message);
    check(asdl_emit_c_source(source, &schema, "test_generated.h", &error), error.message);
    char *header_text = read_stream(header);
    char *source_text = read_stream(source);
    check(strstr(header_text, "abc_asdl_tree_node_tag") != NULL, "payload sum tag was not generated");
    check(strstr(header_text, "abc_asdl_tree_node *left") != NULL, "optional recursive field was not generated");
    check(strstr(header_text, "signed_value") != NULL, "C keyword field was not sanitized");
    check(strstr(source_text, "return \"Branch\"") != NULL, "tag-name implementation was not generated");
    free(header_text);
    free(source_text);
    fclose(header);
    fclose(source);
    asdl_schema_dispose(&schema);

    expect_invalid("module M { A = (Missing value) }", "unknown field type");
    expect_invalid("module M { A = (number x, number x) }", "duplicate field");
    expect_invalid("module M { A = One B = One }", "duplicate constructor");
    expect_invalid("module M { A = (B value) B = (number value) }", "must be declared earlier");
    expect_invalid("module M { A = (number value }", "expected ')'");

    printf("validated C ASDL parser, semantics, diagnostics, and C11 emission (%d checks)\n", checks);
    return 0;
}
