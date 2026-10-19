#!/usr/bin/env python3
"""Traffic model only: no VM bytecode, native register mapping, or timing claim."""
import argparse
from collections import Counter
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import random

MASK = (1 << 64) - 1
POLICIES = ("demand", "eager", "return-only")


@dataclass
class Cell:
    value: int
    refill: bool = False
    used: bool = False


class Ring:
    def __init__(self, n, policy):
        assert n > 0 and policy in POLICIES
        self.n, self.policy = n, policy
        self.r, self.t = 0, 0
        self.bank = [None] * n  # Inactive cells may retain poisoned/stale objects.
        self.memory = []
        self.b = None
        self.count = Counter()
        self.states = Counter()
        self.transitions = Counter()

    def depth(self):
        return len(self.memory) + self.t

    def index(self, depth):
        assert 0 <= depth < self.depth()
        return (self.r + self.t - 1 - depth) % self.n

    def observe(self):
        # Verification never calls read(): observing the model adds no traffic.
        return self.memory + [self.bank[(self.r + i) % self.n].value
                              for i in range(self.t)]

    def retire(self, cell, reason):
        if cell.refill and not cell.used:
            self.count["refill_unused_" + reason] += 1

    def read(self, depth=0):
        assert 0 <= depth < self.depth()
        if depth >= self.t:
            self.count["demand_loads"] += 1
            return self.memory[-1 - (depth - self.t)]
        cell = self.bank[self.index(depth)]
        if cell.refill and not cell.used:
            self.count["refill_used"] += 1
            cell.used = True
        return cell.value

    def write(self, depth, value):
        assert 0 <= depth < self.depth()
        if depth >= self.t:
            self.memory[-1 - (depth - self.t)] = value
            self.count["explicit_stores"] += 1
        else:
            index = self.index(depth)
            self.retire(self.bank[index], "overwritten")
            self.bank[index] = Cell(value)

    def push(self, value):
        if self.t == self.n:
            cell = self.bank[self.r]
            self.memory.append(cell.value)
            self.count["spill_stores"] += 1
            self.retire(cell, "spilled")
            self.bank[self.r] = Cell(value)
            self.r = (self.r + 1) % self.n
        else:
            self.bank[(self.r + self.t) % self.n] = Cell(value)
            self.t += 1

    def discard(self):
        assert self.depth() > 0
        if self.t:
            self.retire(self.bank[self.index(0)], "discarded")
            self.t -= 1
        else:
            self.memory.pop()  # No load is needed to discard dead bits.

    def pop(self):
        value = self.read()
        self.discard()
        return value

    def refill(self):
        # Prepend backing cells. Existing cached cells retain physical registers.
        while self.t < self.n and self.memory:
            self.r = (self.r - 1) % self.n
            self.bank[self.r] = Cell(self.memory.pop(), refill=True)
            self.t += 1
            self.count["refill_loads"] += 1

    def step(self, event):
        op, *args = event
        before = self.depth()
        entry = self.r, self.t
        self.states[entry] += 1
        result = None
        if op in ("push", "call"):
            if op == "call":
                assert self.b is None  # Local trace convention, not a V3 ABI.
            self.push(args[0])
        elif op == "read":
            result = self.read(args[0])
        elif op == "get":
            value = self.read(args[0])  # Capture before a possible full push.
            self.push(value)
        elif op == "write":
            self.write(args[0], args[1])  # Trace primitive, not encoded SET.
        elif op == "pop":
            result = self.pop()
        elif op == "drop":
            self.discard()
        elif op == "to_b":
            assert self.b is None
            self.b = self.pop()
        elif op == "get_b":
            assert self.b is None
            self.b = self.read(args[0])
        elif op == "from_b":
            assert self.b is not None
            self.push(self.b)
            self.b = None
        elif op == "add":
            assert self.b is not None
            self.write(0, (self.read() + self.b) & MASK)
            self.b = None
        elif op == "addi":
            self.write(0, (self.read() + args[0]) & MASK)
        elif op == "return":
            frame_cells, continuation_depth, destination = args
            assert self.b is None and 1 <= continuation_depth <= frame_cells
            assert self.depth() >= frame_cells + 1 and destination in ("A", "B")
            # One explicit return-target read plus capture of the single result.
            result = self.read(continuation_depth)
            value = self.pop()
            for _ in range(frame_cells):
                self.discard()
            if destination == "A":
                self.push(value)
            else:
                self.b = value
        else:
            raise AssertionError(op)
        # Only final logical depth matters; never refill between instruction parts.
        if ((self.policy == "eager" and self.depth() < before)
                or (self.policy == "return-only" and op == "return")):
            self.refill()
        self.count["steps"] += 1
        self.transitions[(op, *entry, self.r, self.t)] += 1
        return result

    def report(self):
        keys = ("steps", "demand_loads", "refill_loads", "spill_stores",
                "explicit_stores", "refill_used", "refill_unused_spilled",
                "refill_unused_discarded", "refill_unused_overwritten")
        data = {key: self.count[key] for key in keys}
        data["refill_unused_live"] = sum(
            cell.refill and not cell.used for cell in
            (self.bank[(self.r + i) % self.n] for i in range(self.t)))
        assert data["refill_loads"] == data["refill_used"] + sum(
            value for key, value in data.items() if key.startswith("refill_unused_"))
        data["total_loads"] = data["demand_loads"] + data["refill_loads"]
        data["total_stores"] = data["spill_stores"] + data["explicit_stores"]
        data["visited_states"] = len(self.states)
        data["distinct_transitions"] = len(self.transitions)
        data["occupancy_entries"] = [sum(count for (_, t), count in self.states.items()
                                         if t == depth) for depth in range(self.n + 1)]
        data["state_entries"] = [[*state, count] for state, count in sorted(self.states.items())]
        data["transitions"] = [[*state, count] for state, count in sorted(self.transitions.items())]
        return data


class Oracle:
    """Uncached logical stack; list operations independently specify each event."""
    def __init__(self):
        self.a, self.b = [], None

    def step(self, event):
        op, *args = event
        if op in ("push", "call"):
            if op == "call":
                assert self.b is None
            self.a.append(args[0])
        elif op == "read":
            return self.a[-1 - args[0]]
        elif op == "get":
            self.a.append(self.a[-1 - args[0]])
        elif op == "write":
            self.a[-1 - args[0]] = args[1]
        elif op == "pop":
            return self.a.pop()
        elif op == "drop":
            del self.a[-1]
        elif op == "to_b":
            assert self.b is None
            self.b = self.a.pop()
        elif op == "get_b":
            assert self.b is None
            self.b = self.a[-1 - args[0]]
        elif op == "from_b":
            assert self.b is not None
            self.a.append(self.b)
            self.b = None
        elif op == "add":
            assert self.b is not None
            self.a[-1] = (self.a[-1] + self.b) & MASK
            self.b = None
        elif op == "addi":
            self.a[-1] = (self.a[-1] + args[0]) & MASK
        elif op == "return":
            frame_cells, continuation_depth, destination = args
            assert self.b is None and 1 <= continuation_depth <= frame_cells
            assert len(self.a) >= frame_cells + 1 and destination in ("A", "B")
            target, value = self.a[-1 - continuation_depth], self.a[-1]
            del self.a[-frame_cells - 1:]
            if destination == "A":
                self.a.append(value)
            else:
                self.b = value
            return target
        else:
            raise AssertionError(op)
        return None


def replay(events, n=8):
    models = [Ring(n, policy) for policy in POLICIES]
    oracle = Oracle()
    for step, event in enumerate(events):
        expected = oracle.step(event)
        for model in models:
            actual = model.step(event)
            assert actual == expected, (step, event, model.policy, actual, expected)
            assert model.observe() == oracle.a, (step, event, model.policy)
            assert model.b == oracle.b, (step, event, model.policy, "B")
            assert 0 <= model.r < n and 0 <= model.t <= n
    return oracle, {model.policy: model.report() for model in models}


def fibonacci(n=16):
    # Trace convention: n then one opaque target cell, no locals, one result.
    # Branch paths are generated here; this is not a bytecode or host-stack VM.
    serial = 0

    def activation(value, destination):
        nonlocal serial
        serial += 1
        yield ("call", 0xCA110000 + serial)
        yield ("get", 1)
        yield ("pop",)  # BGEI-like consuming test, branch resolved by generator.
        if value < 2:
            yield ("get", 1)
        else:
            yield ("get", 1)
            yield ("addi", -1)
            yield from activation(value - 1, "A")
            yield ("get", 2)
            yield ("addi", -2)
            yield from activation(value - 2, "B")
            yield ("add",)
        yield ("return", 2, 1, destination)

    yield ("push", n)
    yield from activation(n, "A")


def expressions():
    # Right-deep trees: left values accumulate, then combine through scalar B.
    for depth in (4, 8, 16, 32, 64):
        for _ in range(32):
            for value in range(1, depth + 1):
                yield ("push", value)
            for _ in range(depth - 1):
                yield ("to_b",)
                yield ("add",)
            yield ("pop",)


def locals_trace():
    for _ in range(128):
        for value in range(24):
            yield ("push", value)
        # Remove operand temporaries, then repeatedly read 12 surviving locals.
        for _ in range(12):
            yield ("drop",)
        for _ in range(8):
            for depth in range(12):
                yield ("read", depth)
        for _ in range(12):
            yield ("drop",)


def oscillation():
    # Refill can pull back a cell that the next push immediately spills again.
    for value in range(32):
        yield ("push", value)
    for value in range(4096):
        yield ("pop",)
        yield ("push", value)
    for _ in range(32):
        yield ("drop",)


def streams():
    for consume in ("pop", "drop"):
        for _ in range(64):
            for value in range(128):
                yield ("push", value)
            for _ in range(128):
                yield (consume,)


def mixed(seed=20261019, steps=30000):
    rng, oracle = random.Random(seed), Oracle()
    for i in range(steps):
        depth = len(oracle.a)
        if oracle.b is not None:
            event = ("add",) if depth and rng.randrange(2) else ("from_b",)
        elif not depth:
            event = ("push", rng.getrandbits(64))
        else:
            choices = ["read", "get", "write", "pop", "drop", "to_b", "get_b", "addi"]
            if depth < 96:
                choices += ["push"] * 3
            else:
                choices = ["read", "write", "pop", "drop"]
            op = rng.choice(choices)
            if op in ("read", "get", "get_b"):
                event = (op, rng.randrange(depth))
            elif op == "write":
                event = (op, rng.randrange(depth), rng.getrandbits(64))
            elif op == "push":
                event = (op, rng.getrandbits(64))
            elif op == "addi":
                event = (op, rng.randrange(-128, 128))
            else:
                event = (op,)
        oracle.step(event)
        yield event
    if oracle.b is not None:
        yield ("from_b",)
        oracle.step(("from_b",))
    for _ in oracle.a:
        yield ("drop",)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="new output directory; never overwrite evidence")
    parser.add_argument("--registers", type=int, default=8)
    args = parser.parse_args()
    assert args.registers > 0
    args.output.mkdir(parents=True, exist_ok=False)
    workloads = {"fib16": fibonacci(), "expressions": expressions(), "locals": locals_trace(),
                 "oscillation": oscillation(), "pop-drop-streams": streams(), "mixed": mixed()}
    results = {"model_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
               "registers": args.registers, "mixed_seed": 20261019, "workloads": {}}
    table = ["workload,policy,steps,demand_loads,refill_loads,total_loads,spill_stores,explicit_stores,refill_used,refill_unused,states,transitions"]
    for name, generator in workloads.items():
        events = list(generator)
        oracle, policies = replay(events, args.registers)
        assert oracle.b is None
        assert oracle.a == ([987] if name == "fib16" else []), (name, oracle.a)
        results["workloads"][name] = {
            "trace_sha256": hashlib.sha256(json.dumps(events).encode()).hexdigest(),
            "final_stack": oracle.a, "policies": policies}
        for policy, data in policies.items():
            unused = sum(v for k, v in data.items() if k.startswith("refill_unused_"))
            table.append(",".join(map(str, [name, policy, data["steps"], data["demand_loads"],
                data["refill_loads"], data["total_loads"], data["spill_stores"], data["explicit_stores"],
                data["refill_used"], unused, data["visited_states"], data["distinct_transitions"]])))
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    (args.output / "summary.csv").write_text("\n".join(table) + "\n")
    print("\n".join(table))
    print("All traces matched the uncached oracle after every operation; counts only, no timings.")


if __name__ == "__main__":
    main()
