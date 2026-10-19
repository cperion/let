#!/usr/bin/env python3
"""Build, validate, inspect and measure; refuse to overwrite experiment evidence."""
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import io
import json
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--order", default="demand,eager,return_only")
    args = parser.parse_args()
    if platform.machine() != "x86_64":
        raise SystemExit("This experiment requires x86-64 Linux.")
    args.output.mkdir(parents=True, exist_ok=False)
    root = Path(__file__).resolve().parent
    build = root / "build"
    source = args.output / "source"
    source.mkdir()
    for name in ("generate.py", "driver.c", "run.py"):
        shutil.copy2(root / name, source / name)
    log = []

    def run(command):
        log.append("$ " + " ".join(map(str, command)))
        process = subprocess.run(list(map(str, command)), text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT)
        log.append(process.stdout)
        (args.output / "build.log").write_text("\n".join(log))
        if process.returncode:
            raise RuntimeError(f"command failed ({process.returncode}); see {args.output / 'build.log'}")
        return process.stdout

    run([sys.executable, root / "generate.py", build, "--order", args.order])
    common = [args.cc, "-O2", "-g", "-std=c11", "-Wall", "-Wextra", "-Werror",
              "-fcf-protection=none", "-fno-pie", "-no-pie", "-I" + str(build)]
    run(common + ["-DCHECKED", root / "driver.c", build / "vm.S", "-o", build / "checked"])
    checked = run([build / "checked"])
    (args.output / "checked.log").write_text(checked)
    run([args.cc, "-g", "-fno-pie", "-fcf-protection=none", "-c", build / "vm.S", "-o", build / "vm.o"])
    run(common + [root / "driver.c", build / "vm.o", "-o", build / "bench"])
    disassembly = subprocess.check_output(["objdump", "-d", "--no-show-raw-insn", build / "vm.o"], text=True)
    (build / "vm.dis").write_text(disassembly)
    assert not re.search(r"\bcallq?\s", disassembly), "timed interpreter contains a host call"
    assert len(re.findall(r"\bretq?\s*(?:\n|$)", disassembly)) == 3
    sizes, addresses = {}, {}
    for line in subprocess.check_output(["nm", "-S", build / "vm.o"], text=True).splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[3].startswith("vm_"):
            sizes[fields[3]] = int(fields[1], 16)
            addresses[fields[3]] = int(fields[0], 16)
    assert len(sizes) == 3
    inspection = {"interpreter_host_calls": 0, "host_returns": 3, "text_bytes": sizes,
                  "object_text_offsets": addresses,
                  "bank_registers": [f"r{i}" for i in range(8, 16)], "B": "rbx", "ip": "rsi", "asp": "rbp",
                  "disassembly_sha256": hashlib.sha256(disassembly.encode()).hexdigest()}
    (args.output / "inspection.json").write_text(json.dumps(inspection, indent=2) + "\n")
    # Exclude checking, counters, builds and assembly inspection from timed samples.
    samples = subprocess.check_output([build / "bench"], text=True)
    (args.output / "samples.csv").write_text(samples)
    rows = list(csv.DictReader(io.StringIO("\n".join(line for line in samples.splitlines()
                                                         if not line.startswith("#")))))
    assert len(rows) == 4 * 3 * 18
    summary = {}
    for workload in dict.fromkeys(row["workload"] for row in rows):
        group = [row for row in rows if row["workload"] == workload]
        data = {}
        baseline = {int(row["sample"]): float(row["ns_per_run"]) for row in group if row["policy"] == "demand"}
        for policy in ("demand", "eager", "return-only"):
            selected = [row for row in group if row["policy"] == policy]
            values = [float(row["ns_per_run"]) for row in selected]
            q1, _, q3 = statistics.quantiles(values, n=4, method="inclusive")
            ratios = [float(row["ns_per_run"]) / baseline[int(row["sample"])] for row in selected]
            data[policy] = {"median_ns": statistics.median(values), "q1_ns": q1, "q3_ns": q3,
                            "min_ns": min(values), "max_ns": max(values),
                            "median_paired_ratio_to_demand": statistics.median(ratios),
                            "iterations_per_sample": int(selected[0]["iterations"]),
                            "instructions_per_run": int(selected[0]["instructions_per_run"])}
        summary[workload] = data
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    metadata = {"timestamp_utc": datetime.now(timezone.utc).isoformat(), "platform": platform.platform(),
                "python": sys.version, "compiler": subprocess.check_output([args.cc, "--version"], text=True),
                "cpu": subprocess.check_output(["lscpu"], text=True), "timing_header": samples.splitlines()[0],
                "perf_available": shutil.which("perf") is not None, "hardware_counters_collected": False,
                "flags": common[1:], "policy_placement_order": args.order,
                "sha256": {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
                           for name in ("generate.py", "driver.c", "run.py", "build/vm.S", "build/vm.o", "build/bench", "build/checked")}}
    (args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(checked, end="")
    print("policy text bytes:", sizes)
    print("workload             demand_us   eager_us  return_us  eager/demand return/demand")
    for workload, data in summary.items():
        print(f"{workload:20s} {data['demand']['median_ns']/1000:9.3f} {data['eager']['median_ns']/1000:9.3f} "
              f"{data['return-only']['median_ns']/1000:9.3f} "
              f"{data['eager']['median_paired_ratio_to_demand']:12.3f} "
              f"{data['return-only']['median_paired_ratio_to_demand']:13.3f}")
    print("Elapsed times only; no cache-miss/branch-miss attribution or V2 comparison.")


if __name__ == "__main__":
    main()
