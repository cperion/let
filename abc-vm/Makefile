CC = clang
AR ?= ar
LUA ?= luajit
MAKEFLAGS += -j8
CFLAGS ?= -O2 -g
WARN = -std=c11 -Wall -Wextra -Wpedantic -Werror
CPPFLAGS += -Iinclude -Isrc -Ibuild
GC_BASE := $(CURDIR)/vendor/whippet/
GC_COLLECTOR := stack_conservative_mmc
GC_CC := $(CC)
GC_AR := $(AR)
GC_OBJDIR := build/whippet/
GC_EMBEDDER_H := $(CURDIR)/src/whippet_embedder.h
GC_EMBEDDER_CPPFLAGS := -I$(CURDIR)/src -I$(CURDIR)/build
include vendor/whippet/embed.mk
GC_LTO_CFLAGS :=
GC_LTO_LDFLAGS :=
SHARDS = 0 1 2 3 4 5 6 7
LIBOBJ = build/module.o build/memory_module.o build/dynamic.o build/foreign.o build/vm.o build/semantics.o build/symbolic.o build/generated/symbolic_dispatch.o build/optimize.o build/residualize.o $(addprefix build/banked_,$(addsuffix .o,$(SHARDS))) $(GC_OBJS)
OPTPIC = build/pic/module.o build/pic/memory_module.o build/pic/semantics.o build/pic/symbolic.o build/pic/symbolic_dispatch.o build/pic/optimize.o
.PHONY: all clean validate
all: build/abc build/abc-opt build/libabc-opt.so build/libabc.a build/generated/stencils.h
build:
	mkdir -p build
build/opcodes.h: tools/gen_opcodes.lua tools/opcodes.lua | build
	$(LUA) tools/gen_opcodes.lua $@
build/generated:
	mkdir -p $@
BANKED_C = $(addprefix build/generated/banked_,$(addsuffix .c,$(SHARDS)))
build/generated/banked.h $(BANKED_C) &: gen/banked.lua gen/cache.lua gen/semantics.lua gen/banked_manifest.lua tools/opcodes.lua | build/generated
	$(LUA) gen/banked.lua build/generated
build/banked_%.o: build/generated/banked_%.c build/generated/banked.h src/vm_internal.h src/internal.h include/abc.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/generated/stencils.c build/generated/stencils.order build/generated/stencil_names.h build/generated/stencil_layout.h &: gen/stencils.lua gen/semantics.lua | build/generated
	$(LUA) gen/stencils.lua build/generated
build/generated/symbolic_dispatch.c: gen/symbolic.lua gen/semantics.lua tools/opcodes.lua | build/generated
	$(LUA) gen/symbolic.lua build/generated
build/generated/symbolic_dispatch.o: build/generated/symbolic_dispatch.c src/symbolic.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/generated/foreign.c: gen/foreign.lua | build/generated
	$(LUA) gen/foreign.lua $@
build/foreign.o: build/generated/foreign.c src/vm_internal.h src/internal.h include/abc.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -Wno-cast-function-type-strict -Wno-unused-parameter -c $< -o $@
build/generated/cold.inc: gen/cold.lua gen/semantics.lua | build/generated
	$(LUA) gen/cold.lua $@
build/generated/stencils.o: build/generated/stencils.c
	$(CC) -O2 -std=c2x -w -fno-builtin -fno-pic -fno-pie -fcf-protection=none -fno-asynchronous-unwind-tables -ffunction-sections -fno-stack-protector -c $< -o $@
build/generated/stencils.h: build/generated/stencils.o build/generated/stencils.order vm/extract.lua
	$(LUA) vm/extract.lua build/generated/stencils.o build/generated/stencils.order $@
build/%.o: src/%.c src/internal.h src/handler_abi.h include/abc.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/vm.o: src/vm_internal.h src/dynamic.h build/generated/banked.h build/generated/cold.inc
build/dynamic.o: src/dynamic.c src/dynamic.h src/whippet_types.h src/vm_internal.h build/opcodes.h
	$(CC) $(CPPFLAGS) -isystem $(GC_BASE)api $(GC_CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/symbolic.o build/optimize.o: src/symbolic.h src/vm_internal.h
build/residualize.o: src/residualize.h src/symbolic.h src/vm_internal.h build/generated/stencils.h build/generated/stencil_layout.h
build/pic:
	mkdir -p $@
build/pic/%.o: src/%.c src/internal.h src/vm_internal.h src/symbolic.h include/abc.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/symbolic_dispatch.o: build/generated/symbolic_dispatch.c src/symbolic.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/libabc-opt.so: $(OPTPIC)
	$(CC) -shared $(CFLAGS) $^ -lm -o $@
build/libabc.a: $(LIBOBJ)
	$(AR) rcs $@ $^
build/abc-runtime: build/cli.o build/libabc.a
	$(CC) $(CFLAGS) $^ $(GC_LIBS) -o $@
build/abc-opt: tools/abc_opt.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a $(GC_LIBS) -o $@
LUA_MODULES = int64 tool_util assembler slet_frontend opcodes
build/%.lua: tools/%.lua | build
	cp $< $@
build/abc: tools/abc build/abc-runtime build/abc-opt $(addprefix build/,$(addsuffix .lua,$(LUA_MODULES)))
	cp tools/abc $@
	chmod +x $@
build/embed: examples/embed.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a $(GC_LIBS) -o $@
build/validate-api: tools/validate_api.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -Wno-cast-function-type-strict $< build/libabc.a $(GC_LIBS) -o $@
build/validate-cache: tools/validate_cache.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a $(GC_LIBS) -o $@
build/validate-symbolic: tools/validate_symbolic.c build/libabc.a src/symbolic.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a $(GC_LIBS) -o $@
validate: all build/validate-api build/validate-cache build/validate-symbolic
	build/validate-symbolic
	$(LUA) tools/validate.lua
	$(LUA) tools/validate_slet_frontend.lua
	cd frontend && $(LUA) tools/embed.lua --check
	cd frontend && $(LUA) tests/schemas.lua
	cd frontend && $(LUA) tests/walk.lua
	cd frontend && $(LUA) tests/parse.lua
	cd frontend && $(LUA) tests/compiler.lua
	cd frontend && $(LUA) tests/lowering.lua
	cd frontend && $(LUA) tests/optimize.lua
	cd frontend && $(LUA) tests/staging.lua
	$(LUA) tools/validate_dynamic.lua
	$(LUA) tools/validate_cache.lua build/validate-cache.abcasm build/validate-cache.oracle
	build/abc asm build/validate-cache.abcasm -o build/validate-cache.abc
	build/validate-cache build/validate-cache.abc build/validate-cache.oracle
	build/abc asm examples/callables.abcasm -o build/validate-callables.abc
	build/abc asm examples/virtual.abcasm -o build/validate-virtual.abc
	build/abc asm examples/foreign.abcasm -o build/validate-foreign.abc
	build/abc asm examples/dynamic_gc.abcasm -o build/validate-dynamic-gc.abc
	build/validate-api build/validate-callables.abc build/validate-virtual.abc build/validate-foreign.abc build/validate-dynamic-gc.abc
clean:
	rm -rf build

