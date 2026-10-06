# ABC VM 2.0 active optimized tier: generated banked interpreters and copy-and-patch JIT.
# Needs clang with preserve_none/musttail and Lua/LuaJIT.
#   make        build      make run    tests + benchmarks
#   abc_bank / abc_mem          interpreter with the operand bank / nothing cached
#   abc_jit_bank / abc_jit_mem  JIT with the operand bank / nothing cached
ifeq ($(origin CC),default)
CC = clang-20
endif
CFLAGS ?= -O2 -std=c2x -w
LUA    ?= lua5.4
SFLAGS  = -O2 -std=c2x -w -fno-pic -fno-pie -fcf-protection=none \
          -fno-asynchronous-unwind-tables -ffunction-sections -fno-stack-protector
ALL = abc_bank abc_mem abc_jit_bank abc_jit_mem
all: $(ALL)

opcodes.h: gen.lua
	$(LUA) gen.lua opcodes $@
harness.o: harness.c opcodes.h
	$(CC) $(CFLAGS) -c $< -o $@

vm_bank.c: gen.lua opcodes.h ; $(LUA) gen.lua interp $@
vm_mem.c: gen.lua opcodes.h ; $(LUA) gen.lua interp0 $@
vm_%.o: vm_%.c ; $(CC) $(CFLAGS) -c $< -o $@
abc_bank: harness.o vm_bank.o ; $(CC) $(CFLAGS) -o $@ $^
abc_mem: harness.o vm_mem.o ; $(CC) $(CFLAGS) -o $@ $^

stencils_bank.c: gen.lua opcodes.h ; $(LUA) gen.lua jit $@
stencils_mem.c: gen.lua opcodes.h ; $(LUA) gen.lua jit0 $@
stencils_%.o: stencils_%.c ; $(CC) $(SFLAGS) -c $< -o $@
stencils_%.h: stencils_%.o ../../tools/extract_stencils.lua ; $(LUA) ../../tools/extract_stencils.lua $< stencils_$*_order.txt $@
jit_%.o: jit.c stencils_%.h opcodes.h
	$(CC) $(CFLAGS) -DSTENCILS='"stencils_$*.h"' -DMETA='"stencils_$*_meta.h"' -c $< -o $@
abc_jit_%: harness.o jit_%.o ; $(CC) $(CFLAGS) -o $@ $^

run: all
	@for b in $(ALL); do echo "== $$b"; ./$$b; done
clean:
	rm -f *.o vm_*.c stencils_* opcodes.h $(ALL)
.PHONY: all run clean
.SECONDARY:
