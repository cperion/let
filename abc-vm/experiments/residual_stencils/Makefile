ifeq ($(origin CC),default)
CC = clang
endif
LUA ?= luajit
SFLAGS = -O2 -std=c2x -w -fno-pic -fno-pie -fcf-protection=none \
         -fno-asynchronous-unwind-tables -ffunction-sections -fno-stack-protector
.PHONY: all check clean
all: run
rs.c rs_order.txt rs_names.h &: gen.lua
	$(LUA) gen.lua
rs.o: rs.c
	$(CC) $(SFLAGS) -c $< -o $@
rs.h: rs.o rs_order.txt ../../vm/extract.lua
	$(LUA) ../../vm/extract.lua rs.o rs_order.txt $@
run: run.c rs.h rs_names.h
	$(CC) -O2 -std=c2x -w run.c -o $@
check: run
	./run
	./run stackcache
clean:
	rm -f rs.c rs_order.txt rs_names.h rs.o rs.h run

