/* Four-lane experiment, following four_lane_stack_register_vm_spec_v3.md.
   Compiler: the spec's baseline algorithm (section 25). New values go to the
   modulo-four winding cursor; a routed op consumes or keeps each source by
   last use (KEEP bits); a result replaces a consumed source in place, else goes
   to the winding cursor; a buried value is exposed with UNWIND (section 22).
   Calls are fused LINK+JMP (CALL), returns RESUME a token on S3 (sections 27-31).
   Calling convention (my choice; the spec leaves it open): arguments on lane
   tops S0..S(k-1), return token on top of S3, result on top of S0.
   Executor: tracks every lane's five cache states (U, R0, R1, R01, R10) with the
   spec's push / no-refill pop rules (sections 7-11), and records the
   (opcode, routing, cache state) combination of every executed instruction. */
require('./core_exp.js');
const S = globalThis.SimCore;
const { BIN, UN, CMPBR, norm, unify, concrete, litType, opFor, isCmp, WRAPS } = S;

function compile(text) {
  const items = S.wparse(text);
  const words = {};
  for (const it of items) {
    if (it.k !== 'word') throw new Error('only words are supported in this experiment');
    it.ps = it.params.map(p => ({ name: p.name, t: p.type.name }));
    it.rt = it.results ? it.results[0].name : null;
    if (it.params.length > 3) throw new Error('at most 3 parameters (S3 holds the return token)');
    if (it.block) throw new Error('expression bodies only in this experiment');
    words[it.name] = it;
  }
  const code = [], labels = {};
  let vid = 0, lid = 0;
  const newv = (tag) => ({ id: ++vid, tag });
  const emit = o => code.push(o);
  const label = p => `${p}_${++lid}`;
  const place = name => { labels[name] = code.length; };
  const uses = n => {
    const m = new Map();
    const walk = x => {
      if (!x) return;
      if (x.k === 'var') m.set(x.name, (m.get(x.name) || 0) + 1);
      for (const k of ['l', 'r', 'x', 'c', 't', 'e']) if (x[k]) walk(x[k]);
      if (x.args) x.args.forEach(walk);
    };
    walk(n);
    return m;
  };
  const plus = (a, b) => { const m = new Map(a); for (const [k, v] of b) m.set(k, (m.get(k) || 0) + v); return m; };
  const maxm = (a, b) => { const m = new Map(a); for (const [k, v] of b) m.set(k, Math.max(m.get(k) || 0, v)); return m; };

  function genWord(w) {
    /* symbolic lanes: bottom first; caller content is one placeholder per lane */
    let L = [[{ caller: true }], [{ caller: true }], [{ caller: true }], [{ caller: true }]];
    const env = {};
    w.ps.forEach((p, i) => { const v = newv('param'); v.frame = true; v.name = p.name; v.t = p.t; env[p.name] = v; L[i].push(v); });
    const token = newv('token'); L[3].push(token);
    let wind = w.ps.length % 4;
    const windLane = () => { const l = wind; wind = (wind + 1) & 3; return l; };
    const find = v => { for (let i = 0; i < 4; i++) { const j = L[i].lastIndexOf(v); if (j >= 0) return { lane: i, depth: L[i].length - 1 - j }; } throw new Error('lost value ' + v.id); };
    const unwind = (lane, n) => {
      emit({ op: 'UNWIND', L: lane, n });
      for (let j = 0; j < n; j++) { const v = L[lane].pop(); L[(lane + 1 + (j % 3)) % 4].push(v); }
    };
    const expose = v => { const f = find(v); if (f.depth > 0) unwind(f.lane, f.depth); };
    const exposeBoth = (a, b) => {
      for (let tries = 0; tries < 6; tries++) {
        const fa = find(a), fb = find(b);
        if (fa.depth === 0 && fb.depth === 0) return;
        if (fa.depth >= fb.depth) expose(a); else expose(b);
      }
      throw new Error('could not expose both operands');
    };
    const typeOf = x => {
      switch (x.k) {
        case 'num': return 'lit';
        case 'var': return env[x.name].t;
        case 'un': return typeOf(x.x);
        case 'bin': if (isCmp(x.o)) return 'bool'; if (x.o === '<<' || x.o === '>>') return typeOf(x.l); return unify(typeOf(x.l), typeOf(x.r), x);
        case 'call': return words[x.name].rt;
        case 'if': return unify(typeOf(x.t), typeOf(x.e), x);
      }
      throw new Error('unsupported ' + x.k);
    };
    const normalize = (v, t) => {
      const fn = t === 'u32' ? 'ZX32' : t === 'i32' ? 'SX32' : null;
      if (!fn) return;
      const f = find(v);
      emit({ op: 'UN', fn, L: f.lane, D: f.lane, k: 0 });
    };
    /* an operand: a fresh temporary (always consumed) or a parameter (consumed at its last use) */
    function operand(x, after, want) {
      if (x.k === 'var') {
        const p = env[x.name];
        if (!p || !L.some(l => l.includes(p))) throw new Error(`parameter ${x.name} is not available`);
        return { v: p, consume: (after.get(x.name) || 0) === 0 };
      }
      return { v: value(x, after, want), consume: true };
    }
    /* compute x into a new temporary on some lane top */
    function value(x, after, want) {
      switch (x.k) {
        case 'num': {
          const d = windLane(), v = newv('tmp'); v.frame = true;
          const t = want || litType(x.v);
          emit({ op: 'PUSH', D: d, v: norm(x.v, t) }); L[d].push(v); return v;
        }
        case 'var': {
          /* a parameter used as a whole value: copy it (keep) or take it (last use) */
          const o = operand(x, after, want);
          expose(o.v);
          const f = find(o.v), d = o.consume ? f.lane : windLane();
          const v = newv('tmp'); v.frame = true;
          emit({ op: 'UN', fn: 'MOV', L: f.lane, D: d, k: o.consume ? 0 : 1 });
          if (o.consume) L[f.lane].pop();
          L[d].push(v);
          return v;
        }
        case 'un': {
          if (x.x.k === 'num') {
            const lt = litType(x.x.v);
            const lit = norm(x.op === '-' ? S.u(-x.x.v) : x.x.v ^ ((1n << 64n) - 1n), lt);
            const d = windLane(), v = newv('tmp'); v.frame = true;
            emit({ op: 'PUSH', D: d, v: norm(lit, want || lt) }); L[d].push(v); return v;
          }
          const t = concrete(typeOf(x), 0n);
          const o = operand(x.x, after, t);
          expose(o.v);
          const f = find(o.v), d = o.consume ? f.lane : windLane(), v = newv('tmp'); v.frame = true;
          const fn = x.op === '-' ? 'NEG' : 'NOT';
          emit({ op: 'UN', fn, L: f.lane, D: d, k: o.consume ? 0 : 1 });
          if (o.consume) L[f.lane].pop();
          L[d].push(v);
          if (x.op === '-' || t === 'u32') normalize(v, t);
          return v;
        }
        case 'bin': {
          const shift = x.o === '<<' || x.o === '>>';
          const t = concrete(shift ? typeOf(x.l) : unify(typeOf(x.l), typeOf(x.r), x), 0n);
          if (isCmp(x.o)) throw new Error('comparisons are only supported as conditions here');
          let a, b;
          if (x.l.k === 'var' && x.r.k !== 'var') { b = operand(x.r, plus(after, uses(x.l)), shift ? 'u32' : t); a = operand(x.l, after, t); }
          else { a = operand(x.l, plus(after, uses(x.r)), t); b = operand(x.r, after, shift ? 'u32' : t); }
          if (a.v === b.v) {                       /* x op x: copy one side so the sources differ */
            a = { v: value({ k: 'var', name: x.l.name }, plus(after, new Map([[x.l.name, 1]])), t), consume: true };
          }
          exposeBoth(a.v, b.v);
          const fa = find(a.v), fb = find(b.v);
          const d = a.consume ? fa.lane : b.consume ? fb.lane : windLane();
          emit({ op: 'BIN', fn: opFor(x.o, t), L: fa.lane, R: fb.lane, D: d, kl: a.consume ? 0 : 1, kr: b.consume ? 0 : 1 });
          if (a.consume) L[fa.lane].pop();
          if (b.consume) L[fb.lane].pop();
          const v = newv('tmp'); v.frame = true; L[d].push(v);
          if (WRAPS.has(x.o) || (x.o === '/' && t === 'i32')) normalize(v, t);
          return v;
        }
        case 'call': {
          const f = words[x.name];
          const args = x.args.map((a, i) => {
            let rest = after; for (let j = i + 1; j < x.args.length; j++) rest = plus(rest, uses(x.args[j]));
            return value(a, rest, f.ps[i].t);
          });
          arrange(args.map((a, i) => [a, i]), false);
          emit({ op: 'CALL', target: f.name });
          args.forEach((a, i) => { const k = L[i].lastIndexOf(a); L[i].splice(k, 1); });
          const r = newv('tmp'); r.frame = true; L[0].push(r);
          return r;
        }
      }
      throw new Error('unsupported expression ' + x.k);
    }
    /* make each target value the top of its lane. Tail and return contexts also
       remove every other frame value (dead parameters, leftovers). */
    function arrange(targets, clean) {
      const tv = new Map(targets);
      const isJunk = v => clean && v.frame && !tv.has(v);
      for (let iter = 0; iter < 200; iter++) {
        let did = false;
        for (let i = 0; i < 4; i++) while (L[i].length && isJunk(L[i][L[i].length - 1])) { emit({ op: 'DROP', L: i }); L[i].pop(); did = true; }
        if (did) continue;
        /* buried junk: expose it so it can be dropped */
        if (clean) {
          let bj = null;
          for (let i = 0; i < 4 && !bj; i++) for (const v of L[i]) if (isJunk(v)) { bj = v; break; }
          if (bj) { expose(bj); continue; }
        }
        const pending = [...tv].filter(([v, lane]) => { const f = find(v); return !(f.lane === lane && f.depth === 0); });
        if (!pending.length) return;
        let moved = false;
        for (const [v, lane] of pending) {
          const f = find(v);
          if (f.depth > 0) { expose(v); moved = true; break; }
          const top = L[lane][L[lane].length - 1];
          if (top && tv.has(top) && top !== v) continue;          /* its lane is occupied by another target: later */
          emit({ op: 'UN', fn: 'MOV', L: f.lane, D: lane, k: 0 }); L[f.lane].pop(); L[lane].push(v);
          moved = true; break;
        }
        if (moved) continue;
        /* a cycle among targets: park one on a lane that is not a target lane, or on S3 */
        const used = new Set([...tv.values()]);
        const [v] = pending[0];
        const f = find(v);
        let park = [0, 1, 2, 3].find(i => !used.has(i) && i !== f.lane);
        if (park == null) park = f.lane === 3 ? 2 : 3;
        emit({ op: 'UN', fn: 'MOV', L: f.lane, D: park, k: 0 }); L[f.lane].pop(); L[park].push(v);
      }
      throw new Error('arrange did not converge');
    }
    function genFalse(c, target, after) {
      if (c.k !== 'bin' || !isCmp(c.o)) throw new Error('conditions must be comparisons here');
      const t = concrete(unify(typeOf(c.l), typeOf(c.r), c), 0n);
      const U = t === 'u32' || t === 'u64' ? 'U' : '';
      let a, b;
      if (c.l.k === 'var' && c.r.k !== 'var') { b = operand(c.r, plus(after, uses(c.l)), t); a = operand(c.l, after, t); }
      else { a = operand(c.l, plus(after, uses(c.r)), t); b = operand(c.r, after, t); }
      if (a.v === b.v) a = { v: value({ k: 'var', name: c.l.name }, plus(after, new Map([[c.l.name, 1]])), t), consume: true };
      exposeBoth(a.v, b.v);
      const fa = find(a.v), fb = find(b.v);
      /* branch when the test is false: (branch, swap) */
      const [br, swap] = { '==': ['BNE', false], '!=': ['BEQ', false], '<': ['BLE', true], '<=': ['BLT', true], '>': ['BLE', false], '>=': ['BLT', false] }[c.o];
      const fn = br === 'BEQ' || br === 'BNE' ? br : br + U;
      const [x, y, kx, ky] = swap ? [fb.lane, fa.lane, b.consume, a.consume] : [fa.lane, fb.lane, a.consume, b.consume];
      emit({ op: 'CB', fn, L: x, R: y, kl: kx ? 0 : 1, kr: ky ? 0 : 1, target });
      if (a.consume) L[fa.lane].splice(L[fa.lane].lastIndexOf(a.v), 1);
      if (b.consume) L[fb.lane].splice(L[fb.lane].lastIndexOf(b.v), 1);
    }
    function tail(x, after) {
      if (x.k === 'if') {
        const le = label('else');
        genFalse(x.c, le, maxm(plus(after, uses(x.t)), plus(after, uses(x.e))));
        const save = L.map(l => l.slice()), saveWind = wind;
        dropDead(plus(after, uses(x.t)));
        tail(x.t, after);
        L = save; wind = saveWind;
        place(le);
        dropDead(plus(after, uses(x.e)));
        tail(x.e, after);
        return;
      }
      if (x.k === 'call' && x.name === w.name) {
        const args = x.args.map((a, i) => {
          let rest = after; for (let j = i + 1; j < x.args.length; j++) rest = plus(rest, uses(x.args[j]));
          return value(a, rest, w.ps[i].t);
        });
        arrange([...args.map((a, i) => [a, i]), [token, 3]], true);
        emit({ op: 'JMP', target: w.name + '_body' });
        return;
      }
      const r = value(x, after, w.rt);
      arrange([[r, 0], [token, 3]], true);
      emit({ op: 'RESUME', L: 3 });
    }
    /* parameters dead on this path: drop them now if they are lane tops */
    function dropDead(live) {
      for (const p of Object.values(env)) {
        if ((live.get(p.name) || 0) > 0) continue;
        const i = L.findIndex(l => l[l.length - 1] === p);
        if (i >= 0) { emit({ op: 'DROP', L: i }); L[i].pop(); }
      }
    }
    place(w.name); place(w.name + '_body');
    tail(w.expr, new Map());
  }
  emit({ op: 'CALL', target: 'main' });
  emit({ op: 'HALT' });
  const todo = Object.keys(words);
  for (const n of todo) genWord(words[n]);
  for (const o of code) if (o.target) { if (labels[o.target] == null) throw new Error('no label ' + o.target); o.to = labels[o.target]; }
  return { code, labels };
}

/* ---- executor with the spec's per-lane cache states */
function run(code, limit = 5e6) {
  const lanes = [[], [], [], []];
  const st = ['U', 'U', 'U', 'U'];
  const stats = { steps: 0, unwinds: 0, unwindMoves: 0, movs: 0, drops: 0, memReads: 0, memWrites: 0 };
  const local = new Map(), global = new Map();
  const PUSH = { U: 'R0', R0: 'R10', R1: 'R01', R01: 'R10', R10: 'R01' };
  const POP = { U: 'U', R0: 'U', R1: 'U', R01: 'R1', R10: 'R0' };
  const push = (i, v) => { if (st[i] === 'R01' || st[i] === 'R10') stats.memWrites++; st[i] = PUSH[st[i]]; lanes[i].push(v); };
  const top = i => { if (st[i] === 'U') stats.memReads++; return lanes[i][lanes[i].length - 1]; };
  const pop = i => { st[i] = POP[st[i]]; return lanes[i].pop(); };
  const key = (o, touched) => {
    const r = `${o.op}:${o.fn || ''}:${o.L ?? ''}${o.R ?? ''}${o.D ?? ''}:${o.kl ?? ''}${o.kr ?? ''}${o.k ?? ''}${o.n ?? ''}`;
    const lk = r + '|' + touched.map(i => st[i]).join(',');
    const gk = r + '|' + st.join(',');
    local.set(lk, (local.get(lk) || 0) + 1); global.set(gk, (global.get(gk) || 0) + 1);
  };
  let pc = 0;
  while (stats.steps++ < limit) {
    const o = code[pc];
    switch (o.op) {
      case 'PUSH': key(o, [o.D]); push(o.D, o.v); pc++; break;
      case 'BIN': {
        key(o, [...new Set([o.L, o.R, o.D])]);
        const x = top(o.L), y = top(o.R);
        const r = BIN[o.fn].f(x, y);
        if (o.D === o.L && !o.kl) { lanes[o.L][lanes[o.L].length - 1] = r; if (!o.kr) pop(o.R); }
        else if (o.D === o.R && !o.kr) { lanes[o.R][lanes[o.R].length - 1] = r; if (!o.kl) pop(o.L); }
        else { if (!o.kl) pop(o.L); if (!o.kr) pop(o.R); push(o.D, r); }
        pc++; break;
      }
      case 'UN': {
        key(o, [...new Set([o.L, o.D])]);
        if (o.fn === 'MOV') stats.movs++;
        const x = top(o.L);
        const r = o.fn === 'MOV' ? x : UN[o.fn].f(x);
        if (o.D === o.L && !o.k) lanes[o.L][lanes[o.L].length - 1] = r;
        else { if (!o.k) pop(o.L); push(o.D, r); }
        pc++; break;
      }
      case 'DROP': key(o, [o.L]); stats.drops++; pop(o.L); pc++; break;
      case 'UNWIND': {
        key(o, [0, 1, 2, 3]); stats.unwinds++; stats.unwindMoves += o.n;
        for (let j = 0; j < o.n; j++) { top(o.L); const v = pop(o.L); push((o.L + 1 + (j % 3)) % 4, v); }
        pc++; break;
      }
      case 'CB': {
        key(o, [...new Set([o.L, o.R])]);
        const x = top(o.L), y = top(o.R);
        if (!o.kl) pop(o.L); if (!o.kr) pop(o.R);
        pc = CMPBR[o.fn](x, y) ? o.to : pc + 1; break;
      }
      case 'JMP': key(o, []); pc = o.to; break;
      case 'CALL': key(o, [3]); push(3, { ret: pc + 1 }); pc = o.to; break;
      case 'RESUME': { key(o, [3]); const t = top(3); pop(3); pc = t.ret; break; }
      case 'HALT': return { result: lanes[0][lanes[0].length - 1], stats, local, global, lanes };
      default: throw new Error('bad op ' + o.op);
    }
  }
  throw new Error('step limit');
}
module.exports = { compile, run };
