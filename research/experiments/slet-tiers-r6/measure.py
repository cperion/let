#!/usr/bin/env python3
"""Frozen-source, runtime-input SLet tier comparison; no runtime modifications."""
import argparse, hashlib, json, os, pathlib, platform, re, shutil, statistics, subprocess, tarfile, time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
MASK = (1 << 32) - 1
ENGINES = ['interpreter', 'eager', 'lazy', 'aot', 'c', 'lua-off', 'lua-jit']

def oracle(name, n):
    if name == 'fib':
        a, b = 0, 1
        for _ in range(n): a, b = b, a + b
        return a & MASK
    acc, x, a, b = 0, 0x12345678, 0x12345678, 0x9e3779b9
    if name == 'skip': x = 2463534242
    if name == 'divide': x = 0x76543210
    def step(s):
        s ^= (s << 13) & MASK
        s ^= s >> 17
        return (s ^ (s << 5)) & MASK
    for counter in range(n, 0, -1):
        if name == 'loop': acc = step(acc) ^ counter
        elif name == 'skip': x = step(x)
        elif name == 'sum2': a, b = step(a), step(b)
        elif name == 'branch':
            x = (x * 3 + 1) & MASK if x & 1 else x >> 1
            acc = (acc + (x & 255)) & MASK
        elif name == 'mul':
            x = (x * 33 + 17) & MASK
            acc = (acc + (x & 65535)) & MASK
        elif name == 'divide':
            q, r = divmod(x, 3)
            x, acc = (q + 0x9e3779b9) & MASK, (acc + r) & MASK
        elif name == 'mix':
            x = ((x ^ (x >> 7)) * 5 + 1) & MASK
            acc = (acc + (x & 1023)) & MASK
        else: raise ValueError(name)
    return x if name == 'skip' else a ^ b if name == 'sum2' else acc

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path, value): path.write_text(json.dumps(value, indent=2) + '\n')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True, type=pathlib.Path)
    ap.add_argument('--cc', default='/tmp/clang20')
    ap.add_argument('--lua', default='/tmp/lua-compat')
    ap.add_argument('--luajit', default=shutil.which('luajit'))
    ap.add_argument('--rounds', type=int, default=7)
    ap.add_argument('--samples', type=int, default=7)
    args = ap.parse_args()
    assert args.rounds >= 1 and args.samples >= 1
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    cpu = min(os.sched_getaffinity(0))
    commands = out / 'commands.jsonl'
    def run(command, pin=True, cwd=None):
        command = [str(x) for x in command]
        if pin: command = ['taskset', '-c', str(cpu)] + command
        started = time.perf_counter()
        p = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
        elapsed = time.perf_counter() - started
        with commands.open('a') as f:
            f.write(json.dumps(dict(command=command, cwd=str(cwd or ROOT), seconds=elapsed,
                                   status=p.returncode, stdout=p.stdout, stderr=p.stderr)) + '\n')
        if p.returncode:
            raise RuntimeError(f'{command}: exit {p.returncode}\n{p.stdout}\n{p.stderr}')
        return p.stdout, elapsed
    # Freeze the dirty working sources, not HEAD, and build in isolation from scratch.
    project = out / 'project'; project.mkdir()
    for name in ['src', 'include', 'gen', 'tools', 'frontend', 'schema', 'vendor']:
        shutil.copytree(ROOT / name, project / name)
    shutil.copy2(ROOT / 'Makefile', project / 'Makefile')
    source_hashes = {str(p.relative_to(project)): digest(p) for p in sorted(project.rglob('*')) if p.is_file()}
    save(out / 'source-sha256.json', source_hashes)
    with tarfile.open(out / 'source.tar.gz', 'w:gz') as tar:
        for name in ['Makefile', 'src', 'include', 'gen', 'tools', 'frontend', 'schema', 'vendor']:
            tar.add(project / name, arcname=name)
    harness = out / 'harness'; harness.mkdir()
    for name in ['vm.c', 'native.c', 'aot.c', 'lua.lua', 'measure.py']:
        shutil.copy2(HERE / name, harness / name)
    original = (ROOT / 'research/experiments/engines/run_bench.lua').read_text()
    specs = re.findall(r"\{name='(\w+)',n=(\d+),.*?src=\[\[(.*?)\]\]", original, re.S)
    assert len(specs) == 8
    workloads = {name: int(n) for name, n, _ in specs}
    host = dict(platform=platform.platform(), cpu=cpu, affinity=sorted(os.sched_getaffinity(0)),
                clang=run([args.cc, '--version'], False)[0], luajit=run([args.luajit, '-v'], False)[0],
                lscpu=run(['lscpu'], False)[0], git=run(['git', 'rev-parse', 'HEAD'], False, ROOT)[0].strip(),
                dirty=run(['git', 'status', '--short'], False, ROOT)[0],
                runtime_flags='-O2 -g; stencils use Makefile -O2 stencil flags',
                c_flags='-O3 -march=native; no LTO', rounds=args.rounds, samples=args.samples,
                timer='CLOCK_MONOTONIC_RAW (all engines)', start_load=os.getloadavg())
    save(out / 'host.json', host)
    warn = '-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof'
    text, _ = run(['make', '-j4', f'CC={args.cc}', f'LUA={args.lua}', 'CFLAGS=-O2 -g', f'WARN={warn}', 'all'], False, project)
    (out / 'build.log').write_text(text)
    flags = ['-O3', '-march=native', '-std=c11', '-Wall', '-Wextra', '-Wpedantic', '-Werror']
    run([args.cc, *flags, '-I'+str(project/'include'), '-I'+str(project/'src'), '-I'+str(project/'build'),
         harness/'vm.c', project/'build/libabc.a', '-lm', '-lpthread', '-o', out/'vm'])
    for suffix, extra in [('', []), ('-no-tco', ['-fno-optimize-sibling-calls'])]:
        run([args.cc, *flags, *extra, harness/'native.c', '-o', out/('native'+suffix)])
    abc = project / 'build/abc'
    pipeline = {}; binaries = {}; generated = out/'programs'; generated.mkdir()
    for name, n, source in specs:
        source = source.replace('let main(): u32', 'let main(n: u32): u32').replace('{N}', 'n')
        assert 'let main(n: u32)' in source and '{N}' not in source
        slet = generated/(name+'.slet'); slet.write_text(source+'\n')
        module = generated/(name+'.abc'); cfile = generated/(name+'.c')
        costs = dict(frontend=[], emit=[], c_compile=[])
        for _ in range(3):
            costs['frontend'].append(run([abc, 'compile', slet, '-o', module])[1])
            costs['emit'].append(run([abc, 'c', module, '-o', cfile])[1])
            costs['c_compile'].append(run([args.cc, *flags, '-Wno-unused-function', cfile, harness/'aot.c', '-o', generated/name])[1])
        (generated/(name+'.dis')).write_text(run([project/'build/abc-runtime', 'dis', module])[0])
        if name == 'fib':
            run([args.cc, *flags, '-Wno-unused-function', '-fno-optimize-sibling-calls', cfile, harness/'aot.c', '-o', generated/'fib-no-tco'])
        costs['module_bytes'] = module.stat().st_size
        costs['aot_executable_bytes'] = (generated/name).stat().st_size
        costs['aot_size'] = run(['size', generated/name])[0]
        pipeline[name] = costs
        binaries[name] = module
    save(out/'pipeline.json', pipeline)
    def engines(name): return ENGINES + (['aot-no-tco', 'c-no-tco'] if name == 'fib' else [])
    def execute(name, engine, n, count):
        if engine in ENGINES[:3]: command = [out/'vm', engine, binaries[name], n, count]
        elif engine.startswith('aot'): command = [generated/(name+('-no-tco' if engine.endswith('no-tco') else '')), n, count]
        elif engine in ('c', 'c-no-tco'): command = [out/('native-no-tco' if engine.endswith('no-tco') else 'native'), name, n, count]
        else: command = [args.luajit, *(['-joff'] if engine == 'lua-off' else []), harness/'lua.lua', name, n, count]
        text, _ = run(command)
        result = json.loads(text)
        if engine.startswith('lua'): assert result['jit'] == (engine == 'lua-jit')
        assert len(result['samples']) == count and all(x >= 0 for x in result['samples'])
        return result
    checks = []
    for name in workloads:
        for n in [0, 1, 2, 7, 31 if name != 'fib' else 10]:
            expected = oracle(name, n)
            for engine in engines(name):
                value = execute(name, engine, n, 1)
                assert value['result'] == expected, (name, engine, n, value, expected)
                checks.append(dict(workload=name, engine=engine, n=n, result=expected))
    save(out/'preflight.json', checks)
    print(f'Preflight: {len(checks)} processes correct. Computing independent full-size expectations.', flush=True)
    expected = {name: oracle(name, n) for name, n in workloads.items()}
    save(out/'expected.json', expected)
    records = []
    for round_index in range(args.rounds):
        names = list(workloads)
        names = names[round_index % len(names):] + names[:round_index % len(names)]
        for wi, name in enumerate(names):
            order = engines(name)
            shift = (round_index + list(workloads).index(name)) % len(order)
            order = order[shift:] + order[:shift]
            for position, engine in enumerate(order):
                record = execute(name, engine, workloads[name], args.samples)
                assert record['result'] == expected[name], (name, engine, record, expected[name])
                record.update(workload=name, engine=engine, round=round_index, position=position, n=workloads[name])
                records.append(record)
                with (out/'timings.jsonl').open('a') as f: f.write(json.dumps(record)+'\n')
        print(f'Round {round_index+1}/{args.rounds} complete; all results correct.', flush=True)
    source_check = {name: digest(ROOT/name) == sha for name, sha in source_hashes.items()}
    save(out/'source-unchanged.json', source_check)
    assert all(source_check.values()), 'Source tree changed during measurements'
    artifacts = [out/'vm', out/'native', out/'native-no-tco', project/'build/libabc.a', project/'build/abc-runtime', project/'build/abc-opt', project/'build/libabc-opt.so']
    artifacts += [p for p in generated.iterdir() if p.is_file()] + list(harness.iterdir())
    save(out/'artifact-sha256.json', {str(p.relative_to(out)): digest(p) for p in artifacts})
    host['end_load'] = os.getloadavg(); save(out/'host.json', host)
    summarize(out, records, workloads)

def summarize(out, records, workloads):
    med = statistics.median
    rows = {}; lines = ['Median of process medians, milliseconds per complete invocation.',
                       'workload        interpreter    eager     lazy      aot        C    Lua-off   Lua-JIT']
    for name in workloads:
        rows[name] = {}
        for engine in ENGINES + (['aot-no-tco', 'c-no-tco'] if name == 'fib' else []):
            rr = [r for r in records if r['workload'] == name and r['engine'] == engine]
            vv = [med(r['samples']) for r in rr]
            rows[name][engine] = dict(seconds=med(vv), round_medians=vv, minimum=min(vv), maximum=max(vv),
                                      first=med([r['first'] for r in rr]))
            if engine in ENGINES[:3]:
                rows[name][engine].update(read=med([r['read'] for r in rr]), prepare=med([r['prepare'] for r in rr]),
                                          native_bytes=sorted(set(r['native_bytes'] for r in rr)))
        lines.append(f'{name:12s} '+ ' '.join(f'{rows[name][e]["seconds"]*1e3:9.3f}' for e in ENGINES))
    lines += ['', 'Paired round ratios: median [min,max]; ranges are NOT confidence intervals.']
    ratios = {}
    for name in workloads:
        ratios[name] = {}
        for a,b in [('interpreter','eager'), ('eager','c'), ('aot','c'), ('eager','lua-jit'), ('lazy','eager')]:
            aa = rows[name][a]['round_medians']; bb = rows[name][b]['round_medians']
            vv = [x/y for x,y in zip(aa,bb)]
            ratios[name][a+'/'+b] = dict(median=med(vv), minimum=min(vv), maximum=max(vv))
        lines.append(name + ': ' + '; '.join(f'{k}={v["median"]:.3f} [{v["minimum"]:.3f},{v["maximum"]:.3f}]' for k,v in ratios[name].items()))
    lines += ['', 'Fibonacci no sibling-call optimization (ms/invocation): ' + ', '.join(f'{e}={rows["fib"][e]["seconds"]*1e3:.3f}' for e in ['eager','lazy','aot-no-tco','c-no-tco']), '', 'Fixed costs (us): read/verify, prepare, first call; first call INCLUDES useful work.']
    for name in workloads:
        lines.append(name + ': ' + '; '.join(f'{e}={rows[name][e]["read"]*1e6:.1f}/{rows[name][e]["prepare"]*1e6:.1f}/{rows[name][e]["first"]*1e6:.1f}, bytes={rows[name][e]["native_bytes"]}' for e in ENGINES[:3]))
    save(out/'summary.json', dict(tiers=rows, paired_ratios=ratios))
    text='\n'.join(lines)+'\n'; (out/'summary.txt').write_text(text); print(text)

if __name__ == '__main__': main()
