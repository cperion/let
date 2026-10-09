ifeq ($(origin CC),default)
CC = clang
endif
TOP = ../../..
LUA ?= luajit
CFLAGS ?= -O3 -march=native
WARN = -std=c11 -Wall -Wextra -Wpedantic -Werror

all: runlet native native-recursive dynamic-native

$(TOP)/build/libabc.a:
	$(MAKE) -C $(TOP) -j8 all

runlet: runlet.c $(TOP)/build/libabc.a
	$(CC) $(CFLAGS) $(WARN) -I$(TOP)/include -I$(TOP)/src -I$(TOP)/build $< $(TOP)/build/libabc.a -lm -lpthread -o $@

native: native.c
	$(CC) $(CFLAGS) $(WARN) $< -o $@

native-recursive: native.c
	$(CC) $(CFLAGS) -fno-optimize-sibling-calls $(WARN) $< -o $@

dynamic-native: dynamic_native.c
	$(CC) $(CFLAGS) $(WARN) $< -o $@

check: all
	$(LUA) run_bench.lua
	$(LUA) run_dynamic.lua

check-dynamic: runlet dynamic-native
	$(LUA) run_dynamic.lua

clean:
	rm -f runlet native native-recursive dynamic-native *.abc .*.abc .bench-*.slet .*-aot .*-aot.c

.PHONY: all check check-dynamic clean
