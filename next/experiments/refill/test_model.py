import unittest

from model import Cell, MASK, Oracle, POLICIES, Ring, fibonacci, mixed, replay


class RingTests(unittest.TestCase):
    def fixture(self, n, r, t, backed, policy):
        model = Ring(n, policy)
        values = list(range(10, 10 + backed + t))
        model.memory = values[:backed]
        model.r, model.t = r, t
        model.bank = [Cell(0xDEAD, refill=True) for _ in range(n)]
        for i, value in enumerate(values[backed:]):
            model.bank[(r + i) % n] = Cell(value)
        oracle = Oracle()
        oracle.a = values[:]
        return model, oracle

    def test_exhaustive_transitions(self):
        # Every rotation, occupancy and short backing prefix for N=1,2,3,4,8.
        # All inactive cells are poisoned before each independent event.
        cases = 0
        for n in (1, 2, 3, 4, 8):
            for r in range(n):
                for t in range(n + 1):
                    for backed in range(5):
                        depth = backed + t
                        events = [("push", 93), ("call", 94)]
                        if depth:
                            events += [("pop",), ("drop",), ("to_b",), ("addi", -17)]
                            for d in range(depth):
                                events += [("read", d), ("get", d), ("get_b", d), ("write", d, 71)]
                        for frame in range(1, min(depth, 5)):
                            for target in range(1, frame + 1):
                                for dest in ("A", "B"):
                                    events.append(("return", frame, target, dest))
                        for event in events:
                            for policy in POLICIES:
                                model, oracle = self.fixture(n, r, t, backed, policy)
                                self.assertEqual(model.step(event), oracle.step(event))
                                self.assertEqual(model.observe(), oracle.a)
                                self.assertEqual(model.b, oracle.b)
                                model.report()  # Refill-use partition must balance.
                                if policy == "demand" or (policy == "return-only" and event[0] != "return"):
                                    self.assertEqual(model.count["refill_loads"], 0)
                                if policy == "eager" and len(oracle.a) < depth:
                                    self.assertEqual(model.t, min(n, len(oracle.a)))
                                cases += 1
        self.assertGreater(cases, 10000)

    def test_refill_preserves_survivor_registers(self):
        for n in range(1, 10):
            for r in range(n):
                for t in range(n + 1):
                    model, oracle = self.fixture(n, r, t, 12, "eager")
                    survivors = {((r + i) % n): model.bank[(r + i) % n] for i in range(t)}
                    model.refill()
                    self.assertEqual(model.observe(), oracle.a)
                    self.assertEqual(model.count["refill_loads"], n - t)
                    for index, cell in survivors.items():
                        self.assertIs(model.bank[index], cell)

    def test_full_push_one_store_no_survivor_moves(self):
        for n in range(1, 10):
            for r in range(n):
                model, oracle = self.fixture(n, r, n, 3, "demand")
                old = model.bank[:]
                model.step(("push", 999))
                oracle.step(("push", 999))
                self.assertEqual(model.observe(), oracle.a)
                self.assertEqual(model.count["spill_stores"], 1)
                self.assertEqual(model.t, n)
                for index in range(n):
                    if index != r:
                        self.assertIs(model.bank[index], old[index])

    def test_atomic_return_refills_only_after_result_transport(self):
        for policy, loads in (("demand", 0), ("eager", 2), ("return-only", 2)):
            model = Ring(8, policy)
            for i in range(12):
                model.step(("push", i))
            model.step(("get", 0))
            model.step(("return", 2, 1, "A"))
            self.assertEqual(model.count["refill_loads"], loads)
            self.assertEqual(model.count["spill_stores"], 5)
            self.assertEqual(model.observe(), list(range(10)) + [11])

    def test_drop_does_not_load_and_demand_pop_never_refills(self):
        events = [("push", i) for i in range(32)] + [("drop",)] * 32
        _, results = replay(events)
        self.assertEqual(results["demand"]["total_loads"], 0)
        self.assertEqual(results["eager"]["refill_loads"], 24)
        self.assertEqual(results["eager"]["refill_unused_discarded"], 24)
        events = [("push", i) for i in range(32)] + [("pop",)] * 32
        _, results = replay(events)
        self.assertEqual(results["demand"]["demand_loads"], 24)
        self.assertEqual(results["demand"]["refill_loads"], 0)
        self.assertEqual(results["eager"]["refill_used"], 24)
        self.assertEqual(results["eager"]["total_loads"], 24)

    def test_oscillation_refills_are_immediately_respilled(self):
        events = [("push", i) for i in range(16)]
        events += [("pop",), ("push", 77)] * 100
        _, results = replay(events)
        self.assertEqual(results["demand"]["total_loads"], 0)
        self.assertEqual(results["demand"]["spill_stores"], 8)
        self.assertEqual(results["eager"]["refill_unused_spilled"], 100)
        self.assertEqual(results["eager"]["spill_stores"], 108)

    def test_refill_use_accounting_including_live_and_overwritten(self):
        model, _ = self.fixture(4, 0, 0, 4, "eager")
        model.refill()
        model.read(0)
        model.read(0)  # One refill residency used twice is counted once.
        model.write(1, 99)
        data = model.report()
        self.assertEqual(data["refill_used"], 1)
        self.assertEqual(data["refill_unused_overwritten"], 1)
        self.assertEqual(data["refill_unused_live"], 2)

    def test_b_and_wrapping(self):
        events = [("push", MASK), ("push", 2), ("to_b",), ("add",),
                  ("get_b", 0), ("from_b",)]
        oracle, _ = replay(events, 1)
        self.assertEqual(oracle.a, [1, 1])
        for policy in POLICIES:
            model = Ring(8, policy)
            model.step(("push", 1))
            model.step(("get_b", 0))
            with self.assertRaises(AssertionError):
                model.step(("call", 123))
            with self.assertRaises(AssertionError):
                model.step(("get_b", 0))

    def test_fibonacci_and_seeded_traces(self):
        for n in (1, 2, 3, 8, 9):
            oracle, _ = replay(list(fibonacci(10)), n)
            self.assertEqual(oracle.a, [55])
            for seed in (0, 1, 19, 20261019):
                oracle, _ = replay(list(mixed(seed, 1500)), n)
                self.assertEqual(oracle.a, [])
                self.assertIsNone(oracle.b)


if __name__ == "__main__":
    unittest.main(verbosity=2)
