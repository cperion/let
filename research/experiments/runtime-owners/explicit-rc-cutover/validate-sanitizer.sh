#!/bin/sh
# Focused C ownership/VM boundary instrumentation, not whole-project sanitization.
# Run from the repository root after make validate-source-owners.
set -eu
build=$(mktemp -d /tmp/let-explicit-rc-asan.XXXXXX)
trap 'rm -rf "$build"' EXIT HUP INT TERM
for file in tools/validate_source_owners.c src/owner.c src/lifetime.c src/vm.c \
            src/native_image.c src/native_emit.c src/threaded_emit.c \
            src/residualize.c src/memory_module.c; do
    "${CC_SANITIZE:-clang}" -Iinclude -Isrc -Ibuild -O1 -g -std=c11 -pthread \
        -Wall -Wextra -Wpedantic -Werror \
        -fsanitize=address,undefined -fno-sanitize=function -fno-omit-frame-pointer \
        -c "$file" -o "$build/$(basename "$file" .c).o"
done
"${SANITIZER_LINK_CC:-clang}" -pthread -fsanitize=address,undefined "$build"/*.o build/libabc.a \
    -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free,--wrap=abc_owner_replace,--wrap=abc_owner_drain,--wrap=mprotect \
    -lm -o "$build/validate"
ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 "$build/validate" \
    build/source-owners.abc build/source-owners-opt.abc \
    build/source-owners-b.abc build/source-owners-b-opt.abc
