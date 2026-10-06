require('./core.js'); const S = globalThis.SimCore;
let seed = 651815; const rnd = n => { seed ^= seed << 13; seed >>>= 0; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0; return seed % n; };
const OPS = ['+', '-', '*', '&', '|', '~', '/', '%', '<<', '>>'];
const CMPS = ['==', '!=', '<', '<=', '>', '>='];
function ex(d, vars) {
  const r = rnd(12);
  if (d > 3 || r < 3) return rnd(2) ? vars[rnd(vars.length)] : String([0, 1, 2, 3, 7, 31, 32, 100, 4294967295][rnd(9)]);
  if (r === 3) return `(-${ex(d + 1, vars)})`;
  if (r === 4) return `(~${ex(d + 1, vars)})`;
  if (r === 5) return `(if ${ex(d + 1, vars)} ${CMPS[rnd(6)]} ${ex(d + 1, vars)} then ${ex(d + 1, vars)} else ${ex(d + 1, vars)})`;
  if (r === 6) return `(${ex(d + 1, vars)} ^ ${rnd(5)})`;
  return `(${ex(d + 1, vars)} ${OPS[rnd(OPS.length)]} ${ex(d + 1, vars)})`;
}
let fails = 0, total = 0, aborts = 0, errs = 0;
for (let t = 0; t < 1500; t++) {
  const T = ['u32', 'i32', 'u64', 'i64'][rnd(4)];
  const body = ex(0, ['a', 'b', 'c']);
  const lit = () => (T[0] === 'i' && rnd(2) ? '-' : '') + [0, 1, 5, 17, 100, 65535, 4000000000][rnd(7)];
  const src = `let f(a, b, c: ${T}) : ${T} = ${body}\nlet main() : ${T} = f(${lit()}, ${lit()}, ${lit()})`;
  let want, got;
  try { want = S.weval(src).map(String).join(','); } catch (e) { want = e instanceof S.Abort ? 'abort' + e.code : 'err'; }
  if (want === 'err') { errs++; continue; }
  try { const c = S.wcompile(src); const sn = S.run(S.assemble(c.asm).code, 20000); const l = sn.at(-1); got = l.reason ? 'abort' + l.reason : l.A.slice().reverse().map(x => String(x.v)).join(','); }
  catch (e) { got = 'cerr ' + e.message; }
  total++; if (String(want).startsWith('abort')) aborts++;
  if (String(want) !== String(got)) { if (fails++ < 4) console.log('MISMATCH', want, got, '\n' + src); }
}
console.log('fuzz', total, 'programs,', aborts, 'aborts,', errs, 'rejected by the evaluator,', fails, 'mismatches');
