require('./core.js');
const S = globalThis.SimCore;
// random differential: bank machine vs plain logical stacks
let seed = 2463534242; const rnd = n => { seed ^= seed << 13; seed >>>= 0; seed ^= seed >>> 17; seed ^= seed << 5; seed >>>= 0; return seed % n; };
const ops = ['PUSH','DUP','DROP','COPY','MOVE','CPUSH','CPOP','CGET','CSET','BIN','UN','ONE'];
const binfn = Object.keys(S.BIN), unfn = Object.keys(S.UN), onefn = ['ZX8','ZX16','POW','POWS',...Object.keys(S.CHK)];
function refRun(code) {
  const A = [], B = [], C = []; // top = end
  const T = X => X === 'A' ? A : X === 'B' ? B : C;
  for (const ins of code) {
    const X = ins.x;
    try {
      switch (ins.op) {
        case 'PUSH': T(X).push(ins.v); break;
        case 'DUP': T(X).push(T(X).at(-1)); break;
        case 'DROP': T(X).pop(); break;
        case 'COPY': T(X[1]).push(T(X[0]).at(-1)); break;
        case 'MOVE': T(X[1]).push(T(X[0]).pop()); break;
        case 'CPUSH': C.push(T(X).pop()); break;
        case 'CPOP': C.pop(); break;
        case 'CGET': T(X).push(C[C.length - 1 - ins.n]); break;
        case 'CSET': { const v = T(X).pop(); C[C.length - 1 - ins.n] = v; break; }
        case 'BIN': { const r = S.BIN[ins.fn].f(A.at(-1), B.at(-1)); if (X === 'A') { A[A.length-1] = r; B.pop(); } else { B[B.length-1] = r; A.pop(); } break; }
        case 'UN': T(X)[T(X).length-1] = S.UN[ins.fn].f(T(X).at(-1)); break;
        case 'ONE': {
          const f = ins.fn, x = A.at(-1);
          if (f === 'ZX8') A[A.length-1] = x & 0xffn; else if (f === 'ZX16') A[A.length-1] = x & 0xffffn;
          else if (S.CHK[f]) { if (S.CHK[f](x)) return { reason: 3 }; }
          else { const y = B.at(-1); if (f === 'POWS' && S.s(y) < 0n) return { reason: 4 }; let r = 1n, b = x, e = y; while (e) { if (e & 1n) r = S.u(r*b); b = S.u(b*b); e >>= 1n; } A[A.length-1] = r; B.pop(); }
          break;
        }
        case 'HALT': return { A, B, C, reason: 0 };
      }
    } catch (e) { if (e instanceof S.Abort) return { reason: e.code }; throw e; }
  }
}
const rv = () => [0n, 1n, 2n, 5n, 63n, 64n, 100n, S.u(-1n), S.u(-5n), 0xffffffffn, 1n << 63n][rnd(11)];
let fails = 0, aborts = 0;
for (let t = 0; t < 3000; t++) {
  const code = []; let da = 0, db = 0, dc = 0; const len = 1 + rnd(120), target = 1 + rnd(8);
  for (let i = 0; i < len; i++) {
    let op = ops[rnd(ops.length)];
    if ((da < target || db < target) && rnd(3) === 0) op = 'PUSH';
    const X = rnd(2) ? 'A' : 'B', XX = rnd(2) ? 'AB' : 'BA';
    const d = X === 'A' ? da : db;
    let ins = null;
    switch (op) {
      case 'PUSH': ins = { op, x: X, v: rv() }; X === 'A' ? da++ : db++; break;
      case 'DUP': if (d) { ins = { op, x: X }; X === 'A' ? da++ : db++; } break;
      case 'DROP': if (d) { ins = { op, x: X }; X === 'A' ? da-- : db--; } break;
      case 'COPY': case 'MOVE': { const f = XX[0] === 'A' ? da : db; if (f) { ins = { op, x: XX }; if (XX[1] === 'A') da++; else db++; if (op === 'MOVE') { if (XX[0] === 'A') da--; else db--; } } break; }
      case 'CPUSH': if (d) { ins = { op, x: X }; X === 'A' ? da-- : db--; dc++; } break;
      case 'CPOP': if (dc) { ins = { op }; dc--; } break;
      case 'CGET': if (dc) { ins = { op, x: X, n: rnd(dc) }; X === 'A' ? da++ : db++; } break;
      case 'CSET': if (dc && d) { ins = { op, x: X, n: rnd(dc) }; X === 'A' ? da-- : db--; } break;
      case 'BIN': if (da && db) { ins = { op, x: X, fn: binfn[rnd(binfn.length)] }; X === 'A' ? db-- : da--; } break;
      case 'UN': if (d) ins = { op, x: X, fn: unfn[rnd(unfn.length)] }; break;
      case 'ONE': { const f = onefn[rnd(onefn.length)]; if (da && ((f !== 'POW' && f !== 'POWS') || db)) { ins = { op, fn: f }; if (f === 'POW' || f === 'POWS') db--; } break; }
    }
    if (ins) code.push(ins);
  }
  code.push({ op: 'HALT' });
  const ref = refRun(code); const sn = S.run(code); const last = sn.at(-1);
  let bad = ref.reason !== last.reason;
  if (!bad && !ref.reason) for (const X of ['A','B','C']) { const want = ref[X].slice().reverse(); const got = last[X].map(c => c.v); if (want.length !== got.length || want.some((v,i)=>v!==got[i])) bad = true; }
  if (ref.reason) aborts++;
  if (bad && fails++ < 3) console.log('MISMATCH', t, ref.reason, last.reason, last.msg);
}
console.log('random', 3000, 'aborts', aborts, 'fails', fails);
// asm examples
const skip = `PUSH.A 2463534242
PUSH.A 3
CALL skip
HALT
next32:
DUP.A
PUSH.B 13
SHL.A
ZX32.A
MOVE.AB
XOR.A
DUP.A
PUSH.B 17
SHR.A
MOVE.AB
XOR.A
DUP.A
PUSH.B 5
SHL.A
ZX32.A
MOVE.AB
XOR.A
RET
skip:
CPUSH.A
CPUSH.A
loop:
CGET.A 1
PUSH.B 0
BEQ done
CGET.A 0
CALL next32
CGET.A 1
PUSH.B 1
SUB.A
ZX32.A
CSET.A 1
CSET.A 0
JMP loop
done:
CGET.A 0
CPOP
CPOP
RET`;
{ const a = S.assemble(skip); const sn = S.run(a.code); let st = 2463534242; for (let i=0;i<3;i++){ st = (st ^ (st << 13)) >>> 0; st = (st ^ (st >>> 17)) >>> 0; st = (st ^ (st << 5)) >>> 0; }
  console.log('skip want', st, 'got', String(sn.at(-1).A[0].v), 'steps', sn.length-1, 'freeMoves', sn.at(-1).stats.freeMoves, 'regMoves', sn.at(-1).stats.regMoves, 'spills', sn.at(-1).stats.spills); }
