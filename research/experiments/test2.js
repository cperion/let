require('./core.js'); const S = globalThis.SimCore;
const progs = {
s13: `let xorshift(a, b, c, s: u32) : u32 = do
  let s1 = s ~ (s << a)
  let s2 = s1 ~ (s1 >> b)
  return s2 ~ (s2 << c)
end

let next32 = xorshift(13, 17, 5)
let seed(s: u32) = if s == 0 then 2463534242 else s

let skip(s, n: u32) : u32 = do
  if n == 0 then return s end
  return skip(next32(s), n - 1)
end

let main() : u32 = skip(seed(0), 3)`,
area: `let area(w, h, m: u32) : u32 = (w + m) * (h - m)
let main() : u32 = area(10, 7, 2)`,
deep: `let deep(x: u32) : u32 = 1 + (2 * (3 + (4 * (5 + (6 * (7 + x))))))
let main() : u32 = deep(8)`,
clamp: `let clamp(x, lo, hi: i32) : i32 = if x < lo then lo else if x > hi then hi else x
let main() : i32 = clamp(-5, 0, 10) + clamp(42, 0, 10) * 100 + clamp(7, 0, 10) * 10000`,
signed: `let half(x: i32) : i32 = x / 2
let rem(x: i32) : i32 = x % 2
let main() : i32 = half(-7) * 10 + rem(-7)`,
fib: `let fib(n: u32) : u32 = if n < 2 then n else fib(n - 1) + fib(n - 2)
let main() : u32 = fib(10)`,
gcd: `let gcd(a, b: u32) : u32 = if b == 0 then a else gcd(b, a % b)
let main() : u32 = gcd(1071, 462)`,
collatz: `let steps(n, count: u32) : u32 = do
  if n == 1 then return count end
  if n % 2 == 0 then return steps(n / 2, count + 1) end
  return steps(3 * n + 1, count + 1)
end
let main() : u32 = steps(27, 0)`,
ratio: `let ratio(a, b: u32) : u32 = a / b
let main() : u32 = ratio(10, 0)`,
cube: `let cube(x: u32) : u32 = x ^ 3
let main() : u32 = cube(2000)`,
logic: `let between(x, lo, hi: u32) : bool = lo <= x and x <= hi
let count(a, b, c: u32) : u32 = do
  let one = if between(a, 1, 9) then 1 else 0
  let two = if between(b, 1, 9) or b == 100 then 10 else 0
  return one + two + (if not between(c, 1, 9) then 100 else 0)
end
let main() : u32 = count(5, 100, 50)`,
power2: `let ipow(base, e, acc: u64) : u64 = do
  if e == 0 then return acc end
  if e % 2 == 1 then return ipow(base * base, e / 2, acc * base) end
  return ipow(base * base, e / 2, acc)
end
let main() : u64 = ipow(3, 40, 1)`,
};
for (const [k, src] of Object.entries(progs)) {
  let want; try { want = S.weval(src).map(String).join(','); } catch (e) { want = e instanceof S.Abort ? 'abort ' + e.code : 'ERR ' + e.message; }
  const c = S.wcompile(src); const a = S.assemble(c.asm); const sn = S.run(a.code, 20000); const last = sn.at(-1);
  const got = last.reason ? 'abort ' + last.reason : last.A.slice().reverse().map(x=>String(x.v)).join(',');
  const nl = S.run(S.assemble(S.wcompile(src, { leftFirst: true }).asm).code, 20000).at(-1);
  console.log(k.padEnd(8), 'want', String(want).padEnd(22), 'got', String(got).padEnd(22), (String(want) === String(got) ? 'ok' : 'MISMATCH'), 'steps', sn.length - 1, 'spills', last.stats.spills, '/', nl.stats.spills, 'ins', a.code.length);
}
console.log(S.wcompile(progs.s13).asm);
// errors
for (const bad of ['let main() : u32 = 1 / 0', 'let f(x: u32) : u32 = x\nlet main() : u32 = f(1, 2)', 'let main() : u32 = do\n let a: i32 = 1\n let b: u32 = 2\n return a + b\nend', 'let f(x: u32) : u32 = x', 'let main() : u32 = 1 < 2 < 3']) {
  try { S.wcompile(bad); console.log('no error?', bad); } catch (e) { console.log('ok err:', e.message); }
}
