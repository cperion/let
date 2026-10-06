const FL = require('./fourlane.js');
const S = globalThis.SimCore;
const P = {
  fib: `let fib(n: u32) : u32 = if n < 2 then n else fib(n - 1) + fib(n - 2)
let main() : u32 = fib(15)`,
  gcd: `let gcd(a, b: u32) : u32 = if b == 0 then a else gcd(b, a % b)
let main() : u32 = gcd(1071, 462)`,
  collatz: `let steps(n, count: u32) : u32 = if n == 1 then count else if n % 2 == 0 then steps(n / 2, count + 1) else steps(3 * n + 1, count + 1)
let main() : u32 = steps(27, 0)`,
  fibiter: `let go(n: u32, a, b: u64) : u64 = if n == 0 then a else go(n - 1, b, a + b)
let main() : u64 = go(90, 0, 1)`,
  sum: `let sum(i, n, acc: u64) : u64 = if i >= n then acc else sum(i + 1, n, acc + i)
let main() : u64 = sum(0, 1000, 0)`,
  clamp: `let clamp(x, lo, hi: i32) : i32 = if x < lo then lo else if x > hi then hi else x
let main() : i32 = clamp(-5, 0, 10) + clamp(42, 0, 10) * 100 + clamp(7, 0, 10) * 10000`,
  deep: `let deep(x: u32) : u32 = 1 + (2 * (3 + (4 * (5 + (6 * (7 + x))))))
let main() : u32 = deep(8)`,
  area: `let area(w, h, m: u32) : u32 = (w + m) * (h - m)
let main() : u32 = area(10, 7, 2)`,
  ipow: `let ipow(base, e, acc: u64) : u64 = if e == 0 then acc else if e % 2 == 1 then ipow(base * base, e / 2, acc * base) else ipow(base * base, e / 2, acc)
let main() : u64 = ipow(3, 40, 1)`,
  xorshift: `let x1(s: u32) : u32 = s ~ (s << 13)
let x2(s: u32) : u32 = s ~ (s >> 17)
let x3(s: u32) : u32 = s ~ (s << 5)
let next32(s: u32) : u32 = x3(x2(x1(s)))
let skip(s, n: u32) : u32 = if n == 0 then s else skip(next32(s), n - 1)
let main() : u32 = skip(2463534242, 50)`,
  poly: `let poly(a, b, c: u64) : u64 = (a * b + c) * (a + b * c) - (a * c + b) * (b + c)
let main() : u64 = poly(3, 5, 7)`,
  mix: `let mix(a, b, c: u32) : u32 = ((a + b) * (b + c)) ~ ((c + a) * (a - b)) ~ ((a * b) + (b * c) + (c * a))
let loop(i, acc: u32) : u32 = if i == 0 then acc else loop(i - 1, mix(acc, i, acc + i))
let main() : u32 = loop(200, 1)`,
};
const allLocal = new Map(), allGlobal = new Map();
let tot = { fl: 0, abc: 0, unw: 0, unwMoves: 0, movs: 0, drops: 0, mem: 0, abcMem: 0 };
console.log('program    result ok   instructions four-lane / A/B/C   UNWINDs (moves)  MOVs  DROPs   memory ops four-lane / A/B/C');
for (const [name, src] of Object.entries(P)) {
  const want = S.weval(src).map(String).join(',');
  const c = FL.compile(src);
  const r = FL.run(c.code);
  const got = String(r.result);
  const abc = S.run(S.assemble(S.wcompile(src).asm).code, 5e6); const al = abc.at(-1);
  const abcGot = al.A.slice().reverse().map(x => String(x.v)).join(',');
  for (const [k, v] of r.local) allLocal.set(k, (allLocal.get(k) || 0) + v);
  for (const [k, v] of r.global) allGlobal.set(k, (allGlobal.get(k) || 0) + v);
  const st = r.stats, abcSteps = abc.length - 1, abcMem = al.stats.memReads + al.stats.memWrites;
  tot.fl += st.steps; tot.abc += abcSteps; tot.unw += st.unwinds; tot.unwMoves += st.unwindMoves; tot.movs += st.movs; tot.drops += st.drops; tot.mem += st.memReads + st.memWrites; tot.abcMem += abcMem;
  console.log(name.padEnd(10), (got === want && abcGot === want ? 'ok' : `MISMATCH fl=${got} abc=${abcGot} want=${want}`).padEnd(10),
    String(st.steps).padStart(8), '/', String(abcSteps).padEnd(8), String(st.unwinds).padStart(6), `(${st.unwindMoves})`.padEnd(8),
    String(st.movs).padStart(5), String(st.drops).padStart(6), '  ', String(st.memReads + st.memWrites).padStart(6), '/', abcMem);
}
console.log('TOTAL'.padEnd(21), String(tot.fl).padStart(8), '/', String(tot.abc).padEnd(8), String(tot.unw).padStart(6), `(${tot.unwMoves})`.padEnd(8), String(tot.movs).padStart(5), String(tot.drops).padStart(6), '  ', String(tot.mem).padStart(6), '/', tot.abcMem);
const cover = m => {
  const v = [...m.values()].sort((a, b) => b - a), total = v.reduce((a, b) => a + b, 0);
  const at = p => { let s = 0; for (let i = 0; i < v.length; i++) { s += v[i]; if (s >= p * total) return i + 1; } return v.length; };
  return `${m.size} distinct combinations; ${at(0.9)} cover 90% of executions, ${at(0.99)} cover 99%`;
};
console.log('\nreached, keyed by touched lanes only:', cover(allLocal));
console.log('reached, keyed by the global four-lane state:', cover(allGlobal));
/* static counts per the spec: opcode x routing x local cache states of the touched lanes */
let perBin = 0;
for (let r = 0; r < 256; r++) { const L = r & 3, R = (r >> 2) & 3, D = (r >> 4) & 3; perBin += 5 ** new Set([L, R, D]).size; }
let perCB = 0; for (let L = 0; L < 4; L++) for (let R = 0; R < 4; R++) perCB += 4 * 5 ** new Set([L, R]).size;
let perUn = 0; for (let L = 0; L < 4; L++) for (let D = 0; D < 4; D++) perUn += 2 * 5 ** new Set([L, D]).size;
const unwindN = 8, unwind = 4 * unwindN * 625;
const staticTotal = 19 * perBin + 6 * perCB + 6 * perUn + unwind + 4 * 5 * 6;
console.log(`\nstatic, per the spec: ${perBin} per binary opcode, ${perCB} per compare-and-branch, ${perUn} per unary; UNWIND with n up to ${unwindN}: ${unwind}`);
console.log(`total for the integer core: about ${staticTotal.toLocaleString()} (19 binary, 6 compare-branch, 6 unary incl. MOV, UNWIND, PUSH/DROP/LINK/RESUME)`);
console.log(`interpreter keyed by global state: ${(625 * (19 * 256 + 6 * 64 + 6 * 32)).toLocaleString()} handlers before UNWIND`);
