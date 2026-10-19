CC = clang
AR ?= ar
LUA ?= luajit
MAKEFLAGS += -j8
CFLAGS ?= -O2 -g
# Native image construction is serialized; entry reads remain lock-free.
override CFLAGS += -pthread
WARN = -std=c11 -Wall -Wextra -Wpedantic -Werror
CPPFLAGS += -Iinclude -Isrc -Ibuild
SHARDS = 0 1 2 3 4 5 6 7
# Keep banked handlers ahead of the native compiler in static-library links.
RUNTIME_OBJ = build/module.o build/memory_module.o build/verify.o build/foreign.o build/vm.o build/semantics.o build/symbolic.o build/generated/symbolic_dispatch.o build/generated/symbolic_fold.o $(addprefix build/banked_,$(addsuffix .o,$(SHARDS))) build/residualize.o build/native_emit.o build/native_image.o build/threaded_emit.o build/generated/threaded.o
TOOL_OBJ = build/module.o build/memory_module.o build/verify.o build/semantics.o build/symbolic.o build/generated/symbolic_dispatch.o build/generated/symbolic_fold.o build/generated/residual_ir.o build/residual_ir.o build/residual_analysis.o build/residual_validate.o build/residual_dump.o build/residual_builder.o build/residual_c.o build/optimize.o
TOOL_PIC = build/pic/module.o build/pic/memory_module.o build/pic/verify.o build/pic/semantics.o build/pic/symbolic.o build/pic/symbolic_dispatch.o build/pic/symbolic_fold.o build/pic/generated_residual_ir.o build/pic/residual_ir.o build/pic/residual_validate.o build/pic/residual_analysis.o build/pic/residual_builder.o build/pic/residual_c.o build/pic/optimize.o
RUNTIME_PIC = build/pic/module.o build/pic/memory_module.o build/pic/verify.o build/pic/foreign.o build/pic/vm.o build/pic/semantics.o build/pic/symbolic.o build/pic/symbolic_dispatch.o build/pic/symbolic_fold.o $(addprefix build/pic/banked_,$(addsuffix .o,$(SHARDS))) build/pic/residualize.o build/pic/native_emit.o build/pic/native_image.o build/pic/threaded_emit.o build/pic/threaded.o
RUNTIME_OBJ += build/owner.o build/lifetime.o
RUNTIME_PIC += build/pic/owner.o build/pic/lifetime.o
ASDLC_SRC = tools/asdlc/main.c tools/asdlc/arena.c tools/asdlc/parser.c tools/asdlc/validate.c tools/asdlc/emit_c.c
.PHONY: all clean validate validate-optimizer-isa validate-frontend-symmetric validate-slet validate-owner-core validate-source-owners validate-c-entries validate-no-collector
all: build/abc build/abc-opt build/libabc-opt.so build/libabc.so build/libabc.a build/generated/stencils.h
build:
	mkdir -p build
build/opcodes.h: tools/gen_opcodes.lua tools/opcodes.lua gen/semantics.lua | build
	$(LUA) tools/gen_opcodes.lua $@
build/generated:
	mkdir -p $@
$(RUNTIME_OBJ) $(RUNTIME_PIC): src/execution_context.h
# Explicit generated/PIC rules also consume private module/function layouts.
$(RUNTIME_OBJ) $(RUNTIME_PIC) $(TOOL_OBJ) $(TOOL_PIC): src/internal.h
build/owner.o build/pic/owner.o: src/owner.h
$(RUNTIME_OBJ) $(RUNTIME_PIC) build/memory_module.o build/pic/memory_module.o: src/lifetime.h src/owner.h
build/abc-asdlc: $(ASDLC_SRC) tools/asdlc/asdlc.h | build
	$(CC) $(CFLAGS) $(WARN) -Itools $(ASDLC_SRC) -o $@
build/generated/residual_ir.h build/generated/residual_ir.c &: schema/residual.asdl build/abc-asdlc | build/generated
	build/abc-asdlc $< --header build/generated/residual_ir.h --source build/generated/residual_ir.c
build/generated/residual_ir.o: build/generated/residual_ir.c build/generated/residual_ir.h
	$(CC) $(CFLAGS) $(WARN) -Ibuild/generated -c $< -o $@
BANKED_C = $(addprefix build/generated/banked_,$(addsuffix .c,$(SHARDS)))
build/generated/banked.h $(BANKED_C) &: gen/banked.lua gen/cache.lua gen/semantics.lua tools/opcodes.lua | build/generated
	$(LUA) gen/banked.lua build/generated
build/banked_%.o: build/generated/banked_%.c build/generated/banked.h src/vm_internal.h src/internal.h include/abc.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/generated/execution_forms.h: gen/execution_layout.lua gen/execution_forms.lua gen/semantics.lua | build/generated
	$(LUA) gen/execution_layout.lua $@
build/generated/threaded.c: gen/threaded.lua gen/execution_forms.lua gen/execution_compute.lua gen/semantics.lua | build/generated
	$(LUA) gen/threaded.lua $@
build/generated/threaded.o: build/generated/threaded.c src/threaded.h src/internal.h build/opcodes.h build/generated/execution_forms.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -Wno-unused-parameter -Wno-tautological-compare -c $< -o $@
build/pic/threaded.o: build/generated/threaded.c src/threaded.h src/internal.h build/opcodes.h build/generated/execution_forms.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -Wno-unused-parameter -Wno-tautological-compare -fPIC -c $< -o $@
build/generated/stencils.c build/generated/stencils.order build/generated/stencil_names.h &: gen/stencils.lua gen/execution_forms.lua gen/execution_compute.lua gen/semantics.lua | build/generated
	$(LUA) gen/stencils.lua build/generated
build/generated/symbolic_dispatch.c: gen/symbolic.lua gen/semantics.lua tools/opcodes.lua | build/generated
	$(LUA) gen/symbolic.lua build/generated
build/generated/symbolic_fold.c: gen/fold.lua gen/semantics.lua | build/generated
	$(LUA) gen/fold.lua $@
build/generated/symbolic_fold.o: build/generated/symbolic_fold.c src/symbolic.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/generated/symbolic_dispatch.o: build/generated/symbolic_dispatch.c src/symbolic.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/generated/foreign.c: gen/foreign.lua | build/generated
	$(LUA) gen/foreign.lua $@
build/foreign.o: build/generated/foreign.c src/vm_internal.h src/internal.h include/abc.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -Wno-cast-function-type-strict -Wno-unused-parameter -c $< -o $@
build/generated/cold.inc: gen/cold.lua gen/semantics.lua | build/generated
	$(LUA) gen/cold.lua $@
build/generated/stencils.o: build/generated/stencils.c build/opcodes.h
	$(CC) $(CPPFLAGS) -O2 -std=c2x -w -fno-builtin -fno-pic -fno-pie -fcf-protection=none -fno-asynchronous-unwind-tables -ffunction-sections -fno-stack-protector -c $< -o $@
build/generated/stencils.h: build/generated/stencils.o build/generated/stencils.order tools/extract_stencils.lua
	$(LUA) tools/extract_stencils.lua build/generated/stencils.o build/generated/stencils.order $@
build/residual_ir.o build/residual_validate.o build/residual_dump.o: build/%.o: src/%.c src/residual_ir.h build/generated/residual_ir.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/%.o: src/%.c src/internal.h src/handler_abi.h include/abc.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/vm.o: src/vm_internal.h src/execution_emit.h src/residualize.h build/generated/banked.h build/generated/cold.inc
build/symbolic.o: src/symbolic.h src/vm_internal.h
build/residual_analysis.o build/residual_c.o: build/generated/residual_ir.h
build/residual_analysis.o: src/residual_analysis.h src/symbolic.h src/vm_internal.h
build/residual_builder.o: src/residual_builder.c src/residual_builder.h src/residual_analysis.h src/residual_ir.h src/symbolic.h build/generated/residual_ir.h
build/optimize.o: src/optimize.c include/abc_tool.h src/symbolic.h src/vm_internal.h
build/residual_c.o: include/abc_tool.h
build/threaded_emit.o build/pic/threaded_emit.o: src/execution_emit.h src/threaded.h build/generated/execution_forms.h
build/native_image.o build/pic/native_image.o: src/execution_emit.h src/native_emit.h src/vm_internal.h build/generated/execution_forms.h
build/native_emit.o build/pic/native_emit.o: src/native_emit.h build/generated/stencils.h build/generated/execution_forms.h
build/residualize.o: src/residualize.c src/residualize.h src/execution_emit.h src/symbolic.h src/vm_internal.h build/generated/execution_forms.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -c $< -o $@
build/pic:
	mkdir -p $@
build/pic/%.o: src/%.c src/internal.h src/vm_internal.h src/handler_abi.h src/symbolic.h include/abc.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/vm.o: src/residualize.h src/execution_emit.h build/generated/banked.h build/generated/cold.inc
build/pic/residualize.o: src/residualize.h src/execution_emit.h build/generated/execution_forms.h
build/pic/banked_%.o: build/generated/banked_%.c build/generated/banked.h src/vm_internal.h src/internal.h src/handler_abi.h include/abc.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/foreign.o: build/generated/foreign.c src/vm_internal.h src/internal.h include/abc.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -Wno-cast-function-type-strict -Wno-unused-parameter -c $< -o $@
build/libabc.so: $(RUNTIME_PIC)
	$(CC) -shared $(CFLAGS) -Wl,-z,defs $^ -lm -o $@
build/pic/symbolic_dispatch.o: build/generated/symbolic_dispatch.c src/symbolic.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/symbolic_fold.o: build/generated/symbolic_fold.c src/symbolic.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/generated_residual_ir.o: build/generated/residual_ir.c build/generated/residual_ir.h | build/pic
	$(CC) $(CFLAGS) $(WARN) -fPIC -Ibuild/generated -c $< -o $@
build/pic/residual_ir.o: src/residual_ir.c src/residual_ir.h build/generated/residual_ir.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/residual_validate.o: src/residual_validate.c src/residual_ir.h build/generated/residual_ir.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/residual_analysis.o: src/residual_analysis.c src/residual_analysis.h src/symbolic.h src/vm_internal.h build/generated/residual_ir.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/residual_c.o: src/residual_c.c src/residual_builder.h src/residual_ir.h build/generated/residual_ir.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/residual_builder.o: src/residual_builder.c src/residual_builder.h src/residual_analysis.h src/residual_ir.h src/symbolic.h build/generated/residual_ir.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/optimize.o: src/optimize.c include/abc_tool.h src/symbolic.h src/vm_internal.h build/opcodes.h | build/pic
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -fPIC -c $< -o $@
build/pic/residual_c.o: include/abc_tool.h
build/libabc-opt.so: $(TOOL_PIC)
	$(CC) -shared $(CFLAGS) $^ -lm -o $@
build/libabc.a: $(RUNTIME_OBJ) Makefile
	rm -f $@
	$(AR) rcs $@ $(RUNTIME_OBJ)
build/libabc-tool.a: $(TOOL_OBJ) Makefile
	rm -f $@
	$(AR) rcs $@ $(TOOL_OBJ)
build/abc-runtime: build/cli.o build/libabc.a
	$(CC) $(CFLAGS) $^ -o $@
build/abc-opt: tools/abc_opt.c build/libabc-tool.a include/abc_tool.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc-tool.a -lm -o $@
LUA_MODULES = int64 tool_util assembler opcodes
build/%.lua: tools/%.lua | build
	cp $< $@
build/abc: tools/abc build/abc-runtime build/abc-opt build/libabc.so $(addprefix build/,$(addsuffix .lua,$(LUA_MODULES)))
	cp tools/abc $@
	chmod +x $@
build/embed: examples/embed.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -o $@
build/validate-owner-core: tools/validate_owner_core.c build/owner.o src/owner.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/owner.o -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free -o $@
validate-owner-core: build/validate-owner-core
	build/validate-owner-core
build/validate-source-owners: tools/validate_source_owners.c build/libabc.a src/vm_internal.h src/execution_context.h src/lifetime.h src/owner.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -lm -Wl,--wrap=aligned_alloc,--wrap=malloc,--wrap=calloc,--wrap=realloc,--wrap=free,--wrap=abc_owner_replace,--wrap=abc_owner_drain,--wrap=mprotect -o $@
.PHONY: validate-source-owners
validate-source-owners: build/validate-source-owners build/libabc.so build/libabc-opt.so
	cd frontend && $(LUA) tests/source_owners.lua
	build/validate-source-owners build/source-owners.abc build/source-owners-opt.abc build/source-owners-b.abc build/source-owners-b-opt.abc
build/validate-c-entries: tools/validate_c_entries.c build/libabc.a build/libabc-tool.a src/vm_internal.h src/residual_builder.h src/residualize.h include/abc_tool.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a build/libabc-tool.a -lm -o $@
validate-c-entries: build/validate-c-entries build/libabc.so build/libabc-opt.so build/abc-runtime
	$(LUA) tools/validate_c_entries.lua build/c-entry-tests
	build/validate-c-entries build/c-entry-tests/entries.abc build/c-entry-tests/optimized.abc build/c-entry-tests/ordinary.abc build/c-entry-tests/empty.abc
build/validate-lifetime: tools/validate_lifetime.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -lm -o $@
build/validate-capacity-frontiers: tools/validate_capacity_frontiers.c build/libabc.a src/internal.h include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -lm -o $@
build/validate-backedges: tools/validate_backedges.c build/libabc.a src/residualize.h src/vm_internal.h include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -lm -o $@
build/generated/validate_execution_forms.c: tools/validate_execution_forms.lua gen/execution_forms.lua gen/semantics.lua | build/generated
	$(LUA) tools/validate_execution_forms.lua $@
build/validate-execution-forms: build/generated/validate_execution_forms.c build/generated/execution_forms.h
	$(CC) $(CFLAGS) $(WARN) -Ibuild/generated $< -o $@
build/validate-staging-abi: tools/validate_staging_abi.c include/abc.h | build
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< -o $@
build/validate-api: tools/validate_api.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -Wno-cast-function-type-strict $< build/libabc.a -o $@
build/validate-cache: tools/validate_cache.c build/libabc.a include/abc.h src/vm_internal.h src/handler_abi.h build/generated/banked.h build/opcodes.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -o $@
build/validate-symbolic: tools/validate_symbolic.c build/libabc.a src/symbolic.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -o $@
build/generated/test_stencils.o: build/generated/stencils.o
	objcopy --localize-symbol=calloc $< $@
build/validate-execution-emit: tools/validate_execution_emit.c build/libabc.a src/execution_emit.h src/threaded.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -lm -o $@
build/validate-native-emit: tools/validate_native_emit.c build/native_emit.o src/native_emit.h build/generated/stencils.h build/generated/execution_forms.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) tools/validate_native_emit.c build/native_emit.o -o $@
build/validate-stencil-operands: tools/validate_stencil_operands.c build/generated/test_stencils.o
	$(CC) $(CFLAGS) $(WARN) -fno-pie -no-pie -Wl,--gc-sections -Wl,--defsym=HOLE_IMM=65539 $^ -o $@
build/validate-call-graph: tools/validate_call_graph.c build/libabc-tool.a src/residual_analysis.h
	$(CC) $(CFLAGS) $(WARN) $(CPPFLAGS) $< build/libabc-tool.a -lm -o $@
build/validate-isa: tools/validate_isa.c build/opcodes.h
	$(CC) $(CFLAGS) $(WARN) $(CPPFLAGS) $< -o $@
build/validate-banked-isa: tools/validate_banked_isa.c build/libabc.a src/vm_internal.h build/opcodes.h
	$(CC) $(CFLAGS) $(WARN) $(CPPFLAGS) $< build/libabc.a -lm -lpthread -o $@
build/validate-capture: tools/validate_capture.c build/libabc.a src/symbolic.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc.a -o $@
build/validate-asdlc: tools/validate_asdlc.c $(filter-out tools/asdlc/main.c,$(ASDLC_SRC)) tools/asdlc/asdlc.h | build
	$(CC) $(CFLAGS) $(WARN) -Itools tools/validate_asdlc.c $(filter-out tools/asdlc/main.c,$(ASDLC_SRC)) -o $@
build/validate-residual-ir: tools/validate_residual_ir.c build/libabc-tool.a src/residual_ir.h src/residual_builder.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) $< build/libabc-tool.a -lm -o $@
build/validate-optimizer-foreign: tools/validate_optimizer_foreign.c build/libabc.a include/abc.h
	$(CC) $(CPPFLAGS) $(CFLAGS) $(WARN) -Wno-cast-function-type-strict $< build/libabc.a -lm -lpthread -o $@
validate-optimizer-isa: build/abc-runtime build/libabc-opt.so build/validate-optimizer-foreign
	$(LUA) tools/validate_optimizer_isa.lua build/abc-runtime build/optimizer-isa build/validate-optimizer-foreign
validate-frontend-symmetric: build/abc-runtime build/abc-opt build/libabc-opt.so build/libabc.so
	cd frontend && $(LUA) tests/symmetric.lua "$(CC)"
validate-slet: validate-frontend-symmetric build/abc build/validate-staging-abi build/validate-lifetime
	build/abc asm tools/validate_lifetime.abcasm -o build/validate-lifetime.abc
	build/validate-lifetime build/validate-lifetime.abc
	cd frontend && $(LUA) tools/embed.lua --check
	cd frontend && $(LUA) tests/schemas.lua
	cd frontend && $(LUA) tests/type_names.lua
	cd frontend && $(LUA) tests/walk.lua
	cd frontend && $(LUA) tests/parse.lua
	cd frontend && $(LUA) tests/syntax_batch.lua
	cd frontend && $(LUA) tests/endall.lua
	cd frontend && $(LUA) tests/word_bindings.lua
	cd frontend && $(LUA) tests/application_chains.lua
	cd frontend && $(LUA) tests/vocabulary.lua
	cd frontend && $(LUA) tests/receiver_scopes.lua
	cd frontend && $(LUA) tests/anonymous_context.lua
	cd frontend && $(LUA) tests/compiler.lua
	cd frontend && $(LUA) tests/lambdas.lua
	cd frontend && $(LUA) tests/lowering.lua
	cd frontend && $(LUA) tests/optimize.lua
	cd frontend && $(LUA) tests/staging.lua
	cd frontend && $(LUA) tests/source_demands.lua
	cd frontend && $(LUA) tests/aggregate_staging.lua
	cd frontend && $(LUA) tests/packed_tagged.lua
	cd frontend && $(LUA) tests/spread.lua --unoptimized
	cd frontend && $(LUA) tests/rest_templates.lua
	cd frontend && $(LUA) tests/access_proofs.lua
	cd frontend && $(LUA) tests/program.lua
	cd frontend && $(LUA) tests/ownership.lua
	cd frontend && LUA="$(LUA)" $(LUA) tests/staging_sessions.lua
	$(LUA) tools/validate_slet_frontend.lua
	CC="$(CC)" $(LUA) tools/validate_c_aot.lua
validate-no-collector:
	$(LUA) tools/validate_no_collector.lua

validate: validate-no-collector validate-c-entries validate-owner-core validate-source-owners validate-slet validate-optimizer-isa all build/validate-api build/validate-cache build/validate-symbolic build/validate-capture build/validate-asdlc build/validate-residual-ir build/validate-isa build/validate-banked-isa build/validate-stencil-operands build/validate-call-graph build/validate-backedges build/validate-execution-forms build/validate-native-emit build/validate-execution-emit build/validate-capacity-frontiers
	build/abc asm tools/validate_capacity_frontiers.abcasm -o build/validate-capacity-frontiers.abc
	build/validate-capacity-frontiers build/validate-capacity-frontiers.abc
	build/validate-execution-emit
	build/validate-native-emit
	build/validate-execution-forms
	build/abc asm tools/validate_backedges.abcasm -o build/validate-backedges.abc
	build/validate-backedges build/validate-backedges.abc
	build/abc asm tools/validate_call_graph.abcasm -o build/validate-call-graph.abc
	build/validate-call-graph build/validate-call-graph.abc
	build/validate-stencil-operands
	build/validate-isa
	build/validate-banked-isa
	$(LUA) tools/validate_symmetric_interpreter.lua build/abc-runtime
	$(LUA) tools/validate_native_returns.lua build/abc-runtime
	build/abc-asdlc --check schema/residual.asdl
	build/validate-asdlc
	build/validate-residual-ir
	build/validate-symbolic
	build/validate-capture
	$(LUA) tools/validate_continuations.lua
	build/abc asm examples/callables.abcasm -o build/validate-callables.abc
	build/abc asm examples/virtual.abcasm -o build/validate-virtual.abc
	build/abc asm examples/foreign.abcasm -o build/validate-foreign.abc
	build/validate-api build/validate-callables.abc build/validate-virtual.abc build/validate-foreign.abc
	$(LUA) tools/validate.lua
	$(LUA) tools/validate_cache.lua build/validate-cache.abcasm build/validate-cache.oracle
	build/abc asm build/validate-cache.abcasm -o build/validate-cache.abc
	build/validate-cache build/validate-cache.abc build/validate-cache.oracle
clean:
	rm -rf build
