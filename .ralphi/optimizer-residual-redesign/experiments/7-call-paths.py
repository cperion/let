#!/usr/bin/env python3
"""Round 7 probe: inlined-call multiplicity and the version budget.

Builds a call-diamond ladder with NO branches:

    f_depth(x) = x
    f_i(x)     = f_{i+1}(x) + f_{i+1}(a)   # a = x, or a = x+1 with --distinct

Full inlining creates 2^depth instances (copies) of every callee body and, in the
versioned model, 2^depth distinct continuation chains at the leaf's entry pc.
The probe measures the current ABC path-tree sink (code size, compile time,
function retention) as the number of call instances doubles -- the quantity the
per-pc key budget cannot bound.

Usage: 7-call-paths.py [--distinct|--same] DEPTH...
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "7-call-paths-out")
ROOT = HERE
while not os.path.exists(os.path.join(ROOT, "build", "abc")):
    parent = os.path.dirname(ROOT)
    if parent == ROOT:
        raise SystemExit("build/abc not found")
    ROOT = parent
ABC = os.path.join(ROOT, "build", "abc")


def source(depth, distinct):
    """f_0 .. f_depth; the leaf is f_depth, so there are 2^depth call instances."""
    lines = [".function f%d 1 1" % depth, "  CGET.A 0", "  RET.A 1 1"]
    for i in range(depth - 1, -1, -1):
        lines += [".function f%d 1 1" % i,
                  "  CGET.A 0",
                  "  CALL.A f%d 1" % (i + 1),
                  "  CPUSH.A",
                  "  CGET.A 0"]
        if distinct:
            lines += ["  PUSH.B 1", "  ADD.A"]
        lines += ["  CALL.A f%d 1" % (i + 1),
                  "  CGET.B 1",
                  "  ADD.A",
                  "  CPOP",
                  "  RET.A 1 1"]
    lines.append(".export f0")
    return "\n".join(lines) + "\n"


def run(argv):
    return subprocess.run(argv, capture_output=True, text=True)


def disassembly(path):
    d = run([ABC, "dis", path])
    if d.returncode:
        return None
    counts, cur = [], 0
    for line in d.stdout.splitlines():
        if line.startswith("function "):
            if cur:
                counts.append(cur)
            cur = 0
        elif line.startswith("  ") and line[2:3] in "0123456789abcdef":
            cur += 1
    if cur:
        counts.append(cur)
    return counts


def measure(depth, distinct):
    tag = "distinct" if distinct else "same"
    base = os.path.join(OUT, "ladder-%s-%02d" % (tag, depth))
    with open(base + ".abcasm", "w") as f:
        f.write(source(depth, distinct))
    r = run([ABC, "asm", base + ".abcasm", "-o", base + ".abc"])
    if r.returncode:
        return "depth=%2d %-8s asm failed: %s" % (depth, tag, r.stderr.strip())
    t0 = time.time()
    r = run([ABC, "opt", base + ".abc", "-o", base + ".opt.abc"])
    dt = (time.time() - t0) * 1000
    if r.returncode:
        return "depth=%2d %-8s opt failed: %s" % (depth, tag, r.stderr.strip())
    before, after = disassembly(base + ".abc"), disassembly(base + ".opt.abc")
    inb = sum(before or [])
    outb = sum(after or [])
    return ("depth=%2d %-8s instances=2^%d=%-6d in=%5dins out=%5dins "
            "funcs=%d sizes=%s opt=%6.1fms %s"
            % (depth, tag, depth, 2 ** depth, inb, outb, len(after or []),
               [os.path.getsize(base + "." + s) for s in ("abc", "opt.abc")],
               dt, "RETAINED" if before == after else "optimized"))


def main():
    os.makedirs(OUT, exist_ok=True)
    args = sys.argv[1:]
    distinct = "--same" not in args
    args = [a for a in args if not a.startswith("--")]
    for a in args or ["3", "5", "7", "9", "11"]:
        print(measure(int(a), distinct))


if __name__ == "__main__":
    main()
