#!/usr/bin/env python3
"""Private x86-64 benchmark interpreter. No VM module/ABI compatibility."""
from pathlib import Path
import argparse

REG = [f"%r{i}" for i in range(8, 16)]
OPS = ["PUSH", "DROP", "TO_B", "FROM_B", "ADD", "ADDI", "NIP", "SET1",
       "JNZ", "BGE2", "CALL", "CALL_B", "RET", "HALT"] + [f"GET{i}" for i in range(32)]
POLICIES = ("demand", "eager", "return_only")


def generate(directory, policies=POLICIES):
    assert sorted(policies) == sorted(POLICIES)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "ops.h").write_text("enum Opcode {\n" + ",\n".join(
        f"    OP_{op} = {i}" for i, op in enumerate(OPS)) + ",\n    OP_COUNT\n};\n")
    out = [".text"]
    emit = out.append
    # Snapshot hook only exists in the separate -DCHECKED assembly build.
    emit(".macro CHECK_STATE R,T\n#ifdef CHECKED\n subq $112,%rsp")
    for i, reg in enumerate(REG):
        emit(f" movq {reg},{i * 8}(%rsp)")
    for reg, offset in (("%rbx", 64), ("%rbp", 72), ("%rsi", 80)):
        emit(f" movq {reg},{offset}(%rsp)")
    emit(" movq $\\R,88(%rsp)\n movq $\\T,96(%rsp)\n movq %rsp,%rdi\n call check_snapshot")
    for i, reg in enumerate(REG):
        emit(f" movq {i * 8}(%rsp),{reg}")
    for reg, offset in (("%rbx", 64), ("%rbp", 72), ("%rsi", 80)):
        emit(f" movq {offset}(%rsp),{reg}")
    emit(" addq $112,%rsp\n#endif\n.endm")

    for policy in policies:
        prefix = ".L" + policy

        def dispatch(r, t):
            emit(f" CHECK_STATE {r},{t}")
            emit(f" movq (%rsi),%rax\n addq $16,%rsi\n jmp *{prefix}_table_{r}_{t}(,%rax,8)")

        def read(r, t, d):
            return REG[(r + t - 1 - d) % 8] if d < t else f"{-8 * (1 + d - t)}(%rbp)"

        def push(r, t, source):
            if t == 8:
                emit(f" movq {REG[r]},(%rbp)\n addq $8,%rbp\n movq {source},{REG[r]}")
                return (r + 1) % 8, 8
            emit(f" movq {source},{REG[(r + t) % 8]}")
            return r, t + 1

        def discard(r, t, count=1):
            if count > t:
                emit(f" subq ${8 * (count - t)},%rbp")
            return r, max(0, t - count)

        def finish(r, t, reduced=False, returning=False):
            if t < 8 and ((policy == "eager" and reduced)
                          or (policy == "return_only" and returning)):
                emit(f" jmp {prefix}_refill_{r}_{t}")
            else:
                dispatch(r, t)

        emit(f".p2align 4\n.globl vm_{policy}\n.type vm_{policy},@function\nvm_{policy}:")
        emit(" pushq %rbp\n pushq %rbx\n pushq %r12\n pushq %r13\n pushq %r14\n pushq %r15\n subq $24,%rsp")
        # Start: ip, memory, backed, R, T, physical bank[8], B. No per-op context loads.
        emit(" movq %rdi,%rax\n movq 0(%rax),%rsi\n movq 8(%rax),%rbp\n movq %rbp,0(%rsp)\n movq 16(%rax),%rcx\n leaq (%rbp,%rcx,8),%rbp")
        for i, reg in enumerate(REG):
            emit(f" movq {40 + i * 8}(%rax),{reg}")
        emit(" movq 104(%rax),%rbx\n movq 24(%rax),%rdx\n imulq $9,%rdx,%rdx\n addq 32(%rax),%rdx")
        emit(f" jmp *{prefix}_entries(,%rdx,8)")

        for r in range(8):
            for t in range(9):
                emit(f"{prefix}_entry_{r}_{t}:")
                dispatch(r, t)
                for op in OPS:
                    label = f"{prefix}_{op}_{r}_{t}"
                    emit(f".p2align 4\n{label}:")
                    if op == "PUSH" or op.startswith("GET"):
                        source = "-8(%rsi)" if op == "PUSH" else read(r, t, int(op[3:]))
                        emit(f" movq {source},%rax")
                        finish(*push(r, t, "%rax"))
                    elif op == "DROP":
                        finish(*discard(r, t), reduced=True)
                    elif op == "TO_B":
                        emit(f" movq {read(r,t,0)},%rbx")
                        finish(*discard(r, t), reduced=True)
                    elif op == "FROM_B":
                        finish(*push(r, t, "%rbx"))
                    elif op == "ADD":
                        emit(f" addq %rbx,{read(r,t,0)}")
                        finish(r, t)
                    elif op == "ADDI":
                        emit(f" movq -8(%rsi),%rax\n addq %rax,{read(r,t,0)}")
                        finish(r, t)
                    elif op == "NIP":
                        emit(f" movq {read(r,t,0)},%rdx")
                        finish(*push(*discard(r, t, 2), "%rdx"), reduced=True)
                    elif op == "SET1":
                        emit(f" movq {read(r,t,0)},%rdx")
                        rr, tt = discard(r, t)
                        emit(f" movq %rdx,{read(rr,tt,1)}")
                        finish(rr, tt, reduced=True)
                    elif op in ("JNZ", "BGE2"):
                        emit(f" movq {read(r,t,0)},%rdx")
                        rr, tt = discard(r, t)
                        if op == "JNZ":
                            emit(f" testq %rdx,%rdx\n jz {label}_fall")
                        else:
                            emit(f" cmpq $2,%rdx\n jb {label}_fall")
                        emit(" movq -8(%rsi),%rsi")
                        finish(rr, tt, reduced=True)
                        emit(f"{label}_fall:")
                        finish(rr, tt, reduced=True)
                    elif op in ("CALL", "CALL_B"):
                        emit(" movq -8(%rsi),%rdx\n movq %rsi,%rcx")
                        if op == "CALL_B":
                            emit(" orq $1,%rcx")
                        rr, tt = push(r, t, "%rcx")
                        emit(" movq %rdx,%rsi")
                        finish(rr, tt)
                    elif op == "RET":
                        # One result above one argument + tagged continuation.
                        emit(f" movq {read(r,t,0)},%rdx\n movq {read(r,t,1)},%rcx")
                        rr, tt = discard(r, t, 3)
                        emit(f" testq $1,%rcx\n jnz {label}_b\n movq %rcx,%rsi")
                        finish(*push(rr, tt, "%rdx"), reduced=True, returning=True)
                        emit(f"{label}_b:\n andq $-2,%rcx\n movq %rcx,%rsi\n movq %rdx,%rbx")
                        finish(rr, tt, reduced=True, returning=True)
                    elif op == "HALT":
                        emit(f" movq {read(r,t,0)},%rax\n jmp {prefix}_exit")
                    else:
                        raise AssertionError(op)
        if policy != "demand":
            # One shared refill tail per state, reached only after the completed
            # operation. Saturated path first, partial fills only near stack base.
            for r in range(8):
                for t in range(8):
                    label = f"{prefix}_refill_{r}_{t}"
                    maximum = 8 - t
                    emit(f"{label}:\n movq %rbp,%rax\n subq 0(%rsp),%rax")
                    for k in range(maximum, 0, -1):
                        emit(f" cmpq ${k * 8},%rax\n jae {label}_{k}")
                    dispatch(r, t)
                    for k in range(1, maximum + 1):
                        emit(f"{label}_{k}:")
                        for i in range(1, k + 1):
                            emit(f" movq {-8 * i}(%rbp),{REG[(r - i) % 8]}")
                        emit(f" subq ${8 * k},%rbp")
                        dispatch((r - k) % 8, t + k)
        emit(f"{prefix}_exit:\n addq $24,%rsp\n popq %r15\n popq %r14\n popq %r13\n popq %r12\n popq %rbx\n popq %rbp\n ret\n.size vm_{policy},.-vm_{policy}")
        emit(".section .rodata\n.p2align 3")
        emit(f"{prefix}_entries:")
        for r in range(8):
            for t in range(9):
                emit(f" .quad {prefix}_entry_{r}_{t}")
        for r in range(8):
            for t in range(9):
                emit(f"{prefix}_table_{r}_{t}:")
                for op in OPS:
                    emit(f" .quad {prefix}_{op}_{r}_{t}")
        emit(".text")
    emit('.section .note.GNU-stack,"",@progbits')
    (directory / "vm.S").write_text("\n".join(out) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--order", default=",".join(POLICIES), help="text/table placement order, not execution order")
    args = parser.parse_args()
    generate(args.output, tuple(args.order.split(",")))
