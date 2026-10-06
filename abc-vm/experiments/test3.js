require('./core.js'); const S = globalThis.SimCore;
const P = {};
P.s13full = `let xorshift(a, b, c, s: u32) : u32 = do
  let s1 = s ~ (s << a)
  let s2 = s1 ~ (s1 >> b)
  return s2 ~ (s2 << c)
end

let next32 = xorshift(13, 17, 5)
let seed(s: u32) : u32 = if s == 0 then 2463534242 else s

let step(s: u32) : (u32, u32) = do
  let t = next32(s)
  return t, t
end

let roll(bound, s: u32) : (u32, u32) = do
  let t = next32(s)
  return t, t % bound + 1
end

let d6 = roll(6)
let d20 = roll(20)

let roll_then_step(s: u32) : (u32, u32) = do
  let next, face = d6(s)
  return next32(next), face
end

let main() : (u32, u32) = roll_then_step(seed(0))`;
P.divmod = `let divmod(a, b: u32) : (u32, u32) = do
  return a / b, a % b
end
let forward(a, b: u32) : (u32, u32) = divmod(a, b)
let first(a, b: u32) : u32 = (divmod(a, b))
let main() : (u32, u32, u32) = do
  let q, r = forward(17, 5)
  return q * 10 + r, first(100, 7), divmod(9, 4) + 1
end`;
P.rng = `let xorshift(a, b, c, s: u32) : u32 = do
  let s1 = s ~ (s << a)
  let s2 = s1 ~ (s1 >> b)
  return s2 ~ (s2 << c)
end
let next32 = xorshift(13, 17, 5)

let rng = {
  state: u32,
  draw() : u32 = do
    state = next32(state)
    return state
  end,
}

let draw_twice(s: u32) : (u32, u32) = do
  let r = rng { state = s }
  let before = r.state
  r.draw()
  return before, r.draw()
end

let main() : (u32, u32) = draw_twice(2463534242)`;
P.points = `let point = { x: i32, y: i32 }

let add(p, q: point) : point = point { x = p.x + q.x, y = p.y + q.y }
let manhattan(p: point) : i32 = (if p.x < 0 then -p.x else p.x) + (if p.y < 0 then -p.y else p.y)

let main() : (i32, point) = do
  let a = point { y = -7, x = 3 }
  let b = add(a, point { x = -10, y = 2 })
  let c = b
  c.x += 100
  return manhattan(a), b
end`;
P.counter = `let counter = {
  value: u32,
  steps: u32,
  bump(by: u32) : u32 = do
    value += by
    steps += 1
    return value
  end,
}

let count_to(limit: u32) : (u32, u32) = do
  let c = counter { value = 0, steps = 0 }
  let by = 7
  return loop(c, limit, by)
end

let loop(c: counter, limit, by: u32) : (u32, u32) = do
  if c.value >= limit then return c.value, c.steps end
  c.bump(by)
  return loop(c, limit, by)
end

let main() : (u32, u32) = count_to(50)`;
P.nested = `let vec2 = { x: u32, y: u32 }
let rect = { min: vec2, max: vec2 }

let area(r: rect) : u32 = (r.max.x - r.min.x) * (r.max.y - r.min.y)
let grow(r: rect, by: u32) : rect = rect { min = vec2 { x = r.min.x - by, y = r.min.y - by }, max = vec2 { x = r.max.x + by, y = r.max.y + by } }

let main() : (u32, u32) = do
  let r = rect { min = vec2 { x = 10, y = 20 }, max = vec2 { x = 14, y = 23 } }
  let g = grow(r, 1)
  r.max.x = 20
  return area(r), area(g)
end`;
P.fibpair = `let fib(n: u32) : u64 = go(n, 0, 1)
let go(n: u32, a, b: u64) : u64 = if n == 0 then a else go(n - 1, b, a + b)
let main() : u64 = fib(90)`;
P.clamp = `let clamp(x, lo, hi: i32) : i32 =\n  if x < lo then lo else if x > hi then hi else x\nlet main() : i32 =\n  clamp(-5, 0, 10) + clamp(42, 0, 10) * 100 + clamp(7, 0, 10) * 10000`;
P.collatz = `let steps(n, count: u32) : u32 = do\n  if n == 1 then return count end\n  if n % 2 == 0 then return steps(n / 2, count + 1) end\n  return steps(3 * n + 1, count + 1)\nend\nlet main() : u32 = steps(27, 0)`;
P.logic = `let between(x, lo, hi: u32) : bool = lo <= x and x <= hi\nlet score(a, b, c: u32) : u32 = do\n  let one = if between(a, 1, 9) then 1 else 0\n  let two = if between(b, 1, 9) or b == 100 then 10 else 0\n  return one + two + (if not between(c, 1, 9) then 100 else 0)\nend\nlet main() : u32 = score(5, 100, 50)`;
P.ratio = `let ratio(a, b: u32) : u32 = a / b\nlet main() : u32 = ratio(10, 0)`;
let bad = 0;
for (const [k, src] of Object.entries(P)) {
  let want;
  try { want = S.weval(src).map(String).join(','); } catch (e) { want = e instanceof S.Abort ? 'abort ' + e.code : 'ERR ' + e.message; }
  let got;
  try { const c = S.wcompile(src); const sn = S.run(S.assemble(c.asm).code, 50000); const l = sn.at(-1); got = l.reason ? 'abort ' + l.reason : l.A.slice().reverse().map(x => String(x.v)).join(','); }
  catch (e) { got = 'CERR ' + e.message; }
  const ok = want === got; if (!ok) bad++;
  console.log(k.padEnd(9), ok ? 'ok      ' : 'MISMATCH', 'want', want.slice(0, 60).padEnd(40), ok ? '' : 'got ' + got.slice(0, 80));
}
console.log(bad ? bad + ' failing' : 'all match');
