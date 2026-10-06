/* residual.js: partial evaluation of ABC bytecode with respect to the program,
   block by block. The stacks are static data: every cell holds a symbolic value
   (a value the block found on entry, a constant, or the result of a residual
   operation). Stack moves, renamings and constants produce no code. Residual
   work is counted:
     - an operation on an unknown value (a fully constant one is folded),
     - ZX32/SX32 unless the value is already known normalized,
     - compare-and-branch, JZ/JNZ, JMP,
     - CALL/TCALL/RET, plus one move per argument cell,
     - at every block exit, one move per cell that does not already hold the
       value the next block expects there (a value computed in the block is
       computed straight into one of its homes, as a register allocator would).
   Usage: node residual.js            (all Let examples from ../lab/ui.js) */
require('../lab/core.js');
const S = globalThis.SimCore;
const fs = require('fs');

function residualize(code) {
  /* leaders: entry, branch targets, and every instruction after control flow */
  const leader = new Set([0]);
  code.forEach((o, i) => {
    if (o.target != null) leader.add(o.target);
    if (['CB', 'CBI', 'JZ', 'JNZ', 'JMP', 'CALL', 'TCALL', 'RET', 'HALT', 'ABORT'].includes(o.op)) leader.add(i + 1);
  });
  const cost = new Array(code.length).fill(0);
  const kinds = { compute: 0, normalize: 0, branch: 0, call: 0, exit: 0 };
  const perSite = code.map(() => ({ compute: 0, normalize: 0, branch: 0, call: 0, exit: 0 }));
  let id = 0;
  for (let start = 0; start < code.length; start++) {
    if (!leader.has(start)) continue;
    /* symbolic stacks: absolute positions, entry cells (negative positions) created on demand */
    const st = { A: { m: new Map(), top: 0 }, B: { m: new Map(), top: 0 }, C: { m: new Map(), top: 0 } };
    const home = (X, p) => ({ id: ++id, kind: 'home', X, p });
    const get = (X, p) => { const s = st[X]; if (!s.m.has(p)) s.m.set(p, home(X, p)); return s.m.get(p); };
    const push = (X, v) => { const s = st[X]; s.m.set(s.top, v); s.top++; };
    const pop = X => { const s = st[X]; s.top--; const v = get(X, s.top); s.m.delete(s.top); return v; };
    const top = (X, n = 0) => get(X, st[X].top - 1 - n);
    const put = (X, n, v) => st[X].m.set(st[X].top - 1 - n, v);
    const konst = c => ({ id: ++id, kind: 'const', c, norm32: c <= 0xffffffffn });
    const op = (norm32 = false) => ({ id: ++id, kind: 'op', norm32 });
    const add = (i, k, n = 1) => { cost[i] += n; perSite[i][k] += n; };
    /* materialize the stacks for the next block */
    const exitCost = i => {
      const where = new Map();
      for (const X of ['A', 'B', 'C']) for (const [p, v] of st[X].m) {
        if (p >= st[X].top) continue;
        if (v.kind === 'home' && v.X === X && v.p === p) continue;      /* already in place */
        if (!where.has(v.id)) where.set(v.id, { v, n: 0 });
        where.get(v.id).n++;
      }
      let n = 0;
      for (const { v, n: k } of where.values()) n += v.kind === 'op' ? k - 1 : k;
      if (n) add(i, 'exit', n);
    };
    const bin = (fn, x, y, i) => {
      if (x.kind === 'const' && y.kind === 'const') { try { return konst(S.BIN[fn].f(x.c, y.c)); } catch (e) { /* aborts stay residual */ } }
      add(i, 'compute');
      const norm = (fn === 'SHR' && x.norm32) || (['AND'].includes(fn) && (x.norm32 || y.norm32)) || (['OR', 'XOR'].includes(fn) && x.norm32 && y.norm32);
      return op(norm);
    };
    for (let i = start; i < code.length; i++) {
      if (i > start && leader.has(i)) { exitCost(i - 1); break; }
      const o = code[i], X = o.x;
      switch (o.op) {
        case 'PUSH': push(X, konst(o.v)); break;
        case 'DUP': push(X, top(X)); break;
        case 'DROP': pop(X); break;
        case 'COPY': push(X[1], top(X[0])); break;
        case 'MOVE': push(X[1], pop(X[0])); break;
        case 'CPUSH': push('C', pop(X)); break;
        case 'CPOP': pop('C'); break;
        case 'CGET': push(X, top('C', o.n)); break;
        case 'CSET': { const v = pop(X); put('C', o.n, v); break; }
        case 'BIN': { const y = top('B'), x = top('A'); const r = bin(o.fn, x, y, i); if (X === 'A') { put('A', 0, r); pop('B'); } else { put('B', 0, r); pop('A'); } break; }
        case 'BINI': { const x = top(X); put(X, 0, bin(o.fn, x, konst(o.v), i)); break; }
        case 'BINC': { const x = top(X); put(X, 0, bin(o.fn, x, top('C', o.n), i)); break; }
        case 'UN': {
          const x = top(X);
          if (x.kind === 'const') { put(X, 0, konst(S.UN[o.fn].f(x.c))); break; }
          if (o.fn === 'ZX32' || o.fn === 'SX32') {
            if (o.fn === 'ZX32' && x.norm32) break;                        /* already normalized: no code */
            add(i, 'normalize'); put(X, 0, op(o.fn === 'ZX32')); break;
          }
          add(i, 'compute'); put(X, 0, op()); break;
        }
        case 'ONE': { const x = top('A'); if (o.fn === 'POW' || o.fn === 'POWS') { pop('B'); } add(i, o.fn.startsWith('CHK') ? 'branch' : 'compute'); if (!o.fn.startsWith('CHK')) put('A', 0, op()); break; }
        case 'CB': pop('A'); pop('B'); add(i, 'branch'); exitCost(i); i = code.length; break;
        case 'CBI': case 'JZ': case 'JNZ': pop(X); add(i, 'branch'); exitCost(i); i = code.length; break;
        case 'JMP': add(i, 'branch'); exitCost(i); i = code.length; break;
        case 'CALL': {
          push('C', konst(0n));                                             /* return address */
          for (let k = 0; k < o.n; k++) push('C', pop('A'));
          add(i, 'call', 1 + o.n); exitCost(i); i = code.length; break;
        }
        case 'TCALL': {
          for (let k = 0; k < o.k; k++) pop('C');
          for (let k = 0; k < o.n; k++) push('C', pop('A'));
          add(i, 'call', 1 + o.n); exitCost(i); i = code.length; break;
        }
        case 'RET': for (let k = 0; k < o.k; k++) pop('C'); add(i, 'call'); exitCost(i); i = code.length; break;
        case 'HALT': case 'ABORT': i = code.length; break;
      }
      if (i === code.length - 1) exitCost(i);
    }
  }
  return { cost, perSite };
}

if (require.main === module) {
  const src = fs.readFileSync(__dirname + '/../lab/ui.js', 'utf8');
  const ex = []; const re = /kind: 'slet', title: ("[^"]*"|'[^']*'),[\s\S]*?src: ("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/g; let m;
  while ((m = re.exec(src))) ex.push([eval(m[1]), eval(m[2])]);
  let tAbc = 0, tRes = 0; const tk = { compute: 0, normalize: 0, branch: 0, call: 0, exit: 0 }; const rows = [];
  for (const [title, code] of ex) {
    const asm = S.assemble(S.wcompile(code).asm).code;
    const sn = S.run(asm, 500000);
    const { cost, perSite } = residualize(asm);
    let abc = 0, res = 0;
    for (const x of sn) if (x.last >= 0) { abc++; res += cost[x.last]; for (const k in tk) tk[k] += perSite[x.last][k]; }
    tAbc += abc; tRes += res;
    rows.push([title, abc, res]);
  }
  rows.sort((a, b) => b[1] - a[1]);
  console.log('program'.padEnd(36), 'bytecode', ' residual', '  ratio');
  rows.slice(0, 10).forEach(([t, a, r]) => console.log(t.padEnd(36), String(a).padStart(8), String(r).padStart(9), (r / a).toFixed(2).padStart(7)));
  console.log('ALL 19'.padEnd(36), String(tAbc).padStart(8), String(tRes).padStart(9), (tRes / tAbc).toFixed(2).padStart(7));
  console.log('residual work by kind:', JSON.stringify(tk));
}
module.exports = { residualize };
