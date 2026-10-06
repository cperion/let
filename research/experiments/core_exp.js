(function (G) {
'use strict';
/* ABC VM 2.0 simulator core.
   Three stacks of 64-bit cells (BigInt, stored unsigned). A and B share a
   four-register operand bank h0..h3: A fills it from h0 upward, B from h3
   downward, so A0 = h[a-1] and B0 = h[4-b]. C has its own bank c0..c3 with
   C0 = c[k-1]. Pushes and pops move no values; only a push onto a full bank
   spills. This mirrors gen.lua's builder exactly. */

const M64 = (1n << 64n) - 1n;
const u = x => BigInt.asUintN(64, x);
const s = x => BigInt.asIntN(64, x);
let NBANK = 4, CBANK = 4;
function setBanks(n, k) { NBANK = n; CBANK = k; }

class Abort extends Error { constructor(code, msg) { super(msg); this.code = code; } }
const REASONS = { 1: 'division by zero', 2: 'index out of range', 3: 'conversion out of range', 4: 'negative exponent', 5: 'unreachable' };

/* ------------------------------------------------------------------ ISA */
const BIN = {
  ADD: { f: (x, y) => u(x + y), sym: '+' },
  SUB: { f: (x, y) => u(x - y), sym: '-' },
  MUL: { f: (x, y) => u(x * y), sym: '*' },
  DIVU: { f: (x, y) => { if (!y) throw new Abort(1); return x / y; }, sym: '/u' },
  DIVS: { f: (x, y) => { if (!y) throw new Abort(1); return s(y) === -1n ? u(-x) : u(s(x) / s(y)); }, sym: '/' },
  REMU: { f: (x, y) => { if (!y) throw new Abort(1); return x % y; }, sym: '%u' },
  REMS: { f: (x, y) => { if (!y) throw new Abort(1); return s(y) === -1n ? 0n : u(s(x) % s(y)); }, sym: '%' },
  AND: { f: (x, y) => x & y, sym: '&' },
  OR: { f: (x, y) => x | y, sym: '|' },
  XOR: { f: (x, y) => x ^ y, sym: '^' },
  SHL: { f: (x, y) => (y >= 64n ? 0n : u(x << y)), sym: '<<' },
  SHR: { f: (x, y) => (y >= 64n ? 0n : x >> y), sym: '>>u' },
  SAR: { f: (x, y) => u(s(x) >> (y >= 64n ? 63n : y)), sym: '>>' },
  EQ: { f: (x, y) => (x === y ? 1n : 0n), sym: '==' },
  NE: { f: (x, y) => (x !== y ? 1n : 0n), sym: '!=' },
  LT: { f: (x, y) => (s(x) < s(y) ? 1n : 0n), sym: '<' },
  LE: { f: (x, y) => (s(x) <= s(y) ? 1n : 0n), sym: '<=' },
  LTU: { f: (x, y) => (x < y ? 1n : 0n), sym: '<u' },
  LEU: { f: (x, y) => (x <= y ? 1n : 0n), sym: '<=u' },
};
const UN = {
  NEG: { f: x => u(-x), sym: '-' },
  NOT: { f: x => x ^ M64, sym: '~' },
  LNOT: { f: x => x ^ 1n, sym: 'not ' },
  ZX32: { f: x => x & 0xffffffffn, sym: 'zx32 ' },
  SX32: { f: x => u(BigInt.asIntN(32, x)), sym: 'sx32 ' },
};
const AONLY_UN = { ZX8: x => x & 0xffn, ZX16: x => x & 0xffffn };
const CHK = {
  CHKU8: x => x > 0xffn, CHKU16: x => x > 0xffffn, CHKU32: x => x > 0xffffffffn,
  CHKI32: x => s(x) < -2147483648n || s(x) > 2147483647n, CHKNN: x => s(x) < 0n,
};
const CMPBR = {
  BEQ: (x, y) => x === y, BNE: (x, y) => x !== y, BLT: (x, y) => s(x) < s(y),
  BLE: (x, y) => s(x) <= s(y), BLTU: (x, y) => x < y, BLEU: (x, y) => x <= y,
};
function vpow(x, e) { let r = 1n; while (e) { if (e & 1n) r = u(r * x); x = u(x * x); e >>= 1n; } return r; }

/* encoded size of an instruction, as in opcodes.h */
function insLen(ins) {
  switch (ins.op) {
    case 'PUSH': return ins.width === 8 ? 2 : ins.width === 32 ? 5 : 9;
    case 'CGET': case 'CSET': return ins.n <= (ins.op === 'CGET' ? 1 : 0) ? 1 : 2;
    case 'JMP': case 'JZ': case 'JNZ': case 'CB': return 3;
    case 'CALL': case 'TCALL': return 5;
    case 'ABORT': return 2;
    default: return 1;
  }
}
function pushWidth(v) {
  const x = s(v);
  if (x >= -128n && x <= 127n) return 8;
  if (x >= -2147483648n && x <= 2147483647n) return 32;
  return 64;
}
function fmt(ins) {
  const x = ins.x ? '.' + ins.x : '';
  switch (ins.op) {
    case 'PUSH': return `PUSH${x} ${s(ins.v)}`;
    case 'BIN': case 'UN': return ins.fn + x;
    case 'ONE': return ins.fn;
    case 'CGET': case 'CSET': return `${ins.op}${x} ${ins.n}`;
    case 'CB': return `${ins.fn} ${ins.label}`;
    case 'JMP': case 'CALL': case 'TCALL': return `${ins.op} ${ins.label}`;
    case 'JZ': case 'JNZ': return `${ins.op}${x} ${ins.label}`;
    case 'ABORT': return `ABORT ${ins.n}`;
    default: return ins.op + x;
  }
}
/* spec opcode name, for the bytecode view */
function specName(ins) {
  const x = ins.x ? '_' + ins.x : '';
  switch (ins.op) {
    case 'PUSH': return `PUSH${ins.width}${x}`;
    case 'CGET': return ins.n === 0 ? `CGET0${x}` : ins.n === 1 ? `CGET1${x}` : `CGETN${x}`;
    case 'CSET': return ins.n === 0 ? `CSET0${x}` : `CSETN${x}`;
    case 'BIN': case 'UN': return ins.fn + x;
    case 'ONE': case 'CB': return ins.fn;
    default: return ins.op + x;
  }
}

/* ------------------------------------------------------------ assembler */
function assemble(text) {
  const lines = text.split('\n');
  const code = [], labels = {}, fix = [];
  const err = (i, m) => { const e = new Error(`Line ${i + 1}: ${m}`); e.line = i; throw e; };
  lines.forEach((raw, i) => {
    let line = raw.replace(/;.*$/, '').trim();
    let m;
    while ((m = /^([A-Za-z_]\w*):\s*(.*)$/.exec(line))) {
      if (labels[m[1]] != null) err(i, `the label "${m[1]}" is defined twice.`);
      labels[m[1]] = code.length; line = m[2].trim();
    }
    if (!line) return;
    const t = line.split(/[\s,]+/);
    const mm = /^([A-Za-z0-9]+)(?:\.([AB]{1,2}))?$/i.exec(t[0]);
    if (!mm) err(i, `"${t[0]}" is not an instruction.`);
    const name = mm[1].toUpperCase(), X = (mm[2] || '').toUpperCase();
    const want = n => { if (t.length !== n + 1) err(i, `${name} takes ${n === 0 ? 'no operands' : n === 1 ? 'one operand' : n + ' operands'}.`); };
    const needX = () => { if (X !== 'A' && X !== 'B') err(i, `${name} needs a stack: write ${name}.A or ${name}.B.`); };
    const noX = () => { if (X) err(i, `${name} does not take a stack suffix.`); };
    const num = (tok, what) => { if (!/^-?(0x[0-9a-f]+|\d+)$/i.test(tok || '')) err(i, `${what} must be a number.`); return tok.startsWith('-') ? -BigInt(tok.slice(1)) : BigInt(tok); };
    let ins;
    if (name === 'PUSH') { needX(); want(1); const v = u(num(t[1], 'PUSH')); ins = { op: 'PUSH', x: X, v, width: pushWidth(v) }; }
    else if (BIN[name]) { needX(); want(0); ins = { op: 'BIN', fn: name, x: X }; }
    else if (UN[name]) { needX(); want(0); ins = { op: 'UN', fn: name, x: X }; }
    else if (AONLY_UN[name] || CHK[name] || name === 'POW' || name === 'POWS') { noX(); want(0); ins = { op: 'ONE', fn: name }; }
    else if (['DUP', 'DROP', 'CPUSH'].includes(name)) { needX(); want(0); ins = { op: name, x: X }; }
    else if (name === 'COPY' || name === 'MOVE') {
      if (X !== 'AB' && X !== 'BA') err(i, `${name} needs a direction: ${name}.AB or ${name}.BA.`);
      want(0); ins = { op: name, x: X };
    }
    else if (name === 'CPOP') { noX(); want(0); ins = { op: 'CPOP' }; }
    else if (name === 'CTAKE') { needX(); want(0); ins = { op: 'CTAKE', x: X }; }
    else if (name === 'CGET' || name === 'CSET') {
      needX(); want(1); const n = Number(num(t[1], 'the depth'));
      if (n < 0 || n > 255) err(i, 'the depth must be between 0 and 255.');
      ins = { op: name, x: X, n };
    }
    else if (CMPBR[name]) { noX(); want(1); ins = { op: 'CB', fn: name, label: t[1] }; fix.push([ins, i]); }
    else if (name === 'JZ' || name === 'JNZ') { needX(); want(1); ins = { op: name, x: X, label: t[1] }; fix.push([ins, i]); }
    else if (['JMP', 'CALL', 'TCALL'].includes(name)) { noX(); want(1); ins = { op: name, label: t[1] }; fix.push([ins, i]); }
    else if (name === 'RET' || name === 'HALT') { noX(); want(0); ins = { op: name }; }
    else if (name === 'ABORT') { noX(); want(1); ins = { op: 'ABORT', n: Number(num(t[1], 'the reason')) & 255 }; }
    else err(i, `unknown instruction "${t[0]}". See the ISA reference.`);
    ins.line = i;
    code.push(ins);
  });
  for (const [ins, i] of fix) {
    if (labels[ins.label] == null) err(i, `there is no label called "${ins.label}".`);
    ins.target = labels[ins.label];
  }
  if (!code.length) err(0, 'the program is empty.');
  const last = code[code.length - 1].op;
  const warnings = [];
  if (!['HALT', 'JMP', 'RET', 'TCALL', 'ABORT'].includes(last)) {
    code.push({ op: 'HALT', line: lines.length - 1, implicit: true });
    warnings.push('The program did not end with HALT, so one was added.');
  }
  const labelAt = {};
  for (const [name, idx] of Object.entries(labels)) (labelAt[idx] = labelAt[idx] || []).push(name);
  return { code, labels, labelAt, warnings };
}
function layout(code) {
  const addr = []; let a = 0;
  for (const ins of code) { addr.push(a); a += insLen(ins); }
  return { addr, size: a };
}

/* -------------------------------------------------------------- machine */
function newMachine() {
  return { memA: [], memB: [], memC: [], h: new Array(NBANK).fill(null), c: new Array(CBANK).fill(null),
    a: 0, b: 0, k: 0, pc: 0, halted: false, reason: 0,
    stats: { steps: 0, regMoves: 0, freeMoves: 0, spills: 0, memReads: 0, memWrites: 0, maxA: 0, maxB: 0, maxC: 0 } };
}
const cnt = (m, X) => (X === 'A' ? m.a : X === 'B' ? m.b : m.k);
function regName(m, X, i) {
  if (X === 'A') return 'h' + (m.a - 1 - i);
  if (X === 'B') return 'h' + (NBANK - m.b + i);
  return 'c' + (m.k - 1 - i);
}
const mem = (m, X) => (X === 'A' ? m.memA : X === 'B' ? m.memB : m.memC);
function regGet(m, r) { return r[0] === 'h' ? m.h[+r[1]] : m.c[+r[1]]; }
function regSet(m, r, v) { if (r[0] === 'h') m.h[+r[1]] = v; else m.c[+r[1]] = v; }
function depth(m, X) { return cnt(m, X) + mem(m, X).length; }

/* where logical depth n of X lives */
function loc(m, X, n) {
  if (n < cnt(m, X)) return regName(m, X, n);
  return 'mem';
}
function read(m, X, n, L) {
  if (n >= depth(m, X)) throw new Error(`${X}${n} does not exist: the ${X === 'C' ? 'context' : X} stack holds ${depth(m, X)} value${depth(m, X) === 1 ? '' : 's'}.`);
  if (n < cnt(m, X)) return { cell: regGet(m, regName(m, X, n)), where: regName(m, X, n) };
  m.stats.memReads++;
  const M = mem(m, X);
  return { cell: M[M.length - 1 - (n - cnt(m, X))], where: `${X}[${n}] in memory` };
}
function writeAt(m, X, n, cell, L, how) {
  if (n < cnt(m, X)) { const r = regName(m, X, n); regSet(m, r, cell); L.push(`${r} = ${how}`); return r; }
  const M = mem(m, X); M[M.length - 1 - (n - cnt(m, X))] = cell; m.stats.memWrites++;
  L.push(`${X}[${n}] in memory = ${how}`);
  return 'mem';
}
function pop(m, X, L) {
  if (depth(m, X) === 0) throw new Error(`pop from an empty ${X === 'C' ? 'context' : X} stack.`);
  if (X === 'A' && m.a) { m.a--; return; }
  if (X === 'B' && m.b) { m.b--; return; }
  if (X === 'C' && m.k) { m.k--; return; }
  mem(m, X).pop();
}
function spillDeepest(m, X, L) {
  m.stats.spills++; m.stats.memWrites++;
  if (X === 'A') {
    m.memA.push(m.h[0]); L.push('spill h0 → A memory (A\'s deepest cached cell)');
    for (let i = 0; i < m.a - 1; i++) { m.h[i] = m.h[i + 1]; L.push(`h${i} = h${i + 1}`); m.stats.regMoves++; }
    m.h[m.a - 1] = null; m.a--;
  } else if (X === 'B') {
    m.memB.push(m.h[NBANK - 1]); L.push('spill → B memory');
    for (let i = NBANK - 1; i > NBANK - m.b; i--) { m.h[i] = m.h[i - 1]; L.push(`h${i} = h${i - 1}`); m.stats.regMoves++; }
    m.h[NBANK - m.b] = null; m.b--;
  } else {
    m.memC.push(m.c[0]); L.push('spill c0 → C memory (C\'s deepest cached cell)');
    for (let i = 0; i < m.k - 1; i++) { m.c[i] = m.c[i + 1]; L.push(`c${i} = c${i + 1}`); m.stats.regMoves++; }
    m.c[m.k - 1] = null; m.k--;
  }
}
/* push a cell; src = register name when the value is a copy of a register */
function push(m, X, cell, L, src, how) {
  let r, spilled = false;
  if (X === 'C') {
    if (m.k === CBANK) { spillDeepest(m, 'C', L); spilled = true; }
    r = 'c' + m.k; m.k++;
  } else {
    if (m.a + m.b === NBANK) { spillDeepest(m, cnt(m, X) > 0 ? X : (X === 'A' ? 'B' : 'A'), L); spilled = true; }
    if (X === 'A') { r = 'h' + m.a; m.a++; } else { r = 'h' + (NBANK - 1 - m.b); m.b++; }
  }
  /* after a spill the registers have shifted, so the value comes from a temporary */
  if (spilled && src && /^[hc]\d$/.test(src)) { L.push(`${r} = the value read from ${src} before the spill`); m.stats.regMoves++; src = null; how = null; }
  if (how === null) { /* already logged */ }
  else if (src && src === r) {
    L.push(`${r} changes owner: no native move`); m.stats.freeMoves++;
  } else {
    if (src && /^[hc]\d$/.test(src)) { L.push(`${r} = ${src}`); m.stats.regMoves++; }
    else L.push(`${r} = ${how}`);
  }
  regSet(m, r, cell);
  m.stats.maxA = Math.max(m.stats.maxA, depth(m, 'A'));
  m.stats.maxB = Math.max(m.stats.maxB, depth(m, 'B'));
  m.stats.maxC = Math.max(m.stats.maxC, depth(m, 'C'));
  return r;
}
const val = v => ({ v });
const other = X => (X === 'A' ? 'B' : 'A');

/* execute one instruction; returns { L: native log, msg } */
function step(m, code) {
  const ins = code[m.pc];
  const L = [];
  let next = m.pc + 1, msg = '';
  m.stats.steps++;
  const X = ins.x;
  switch (ins.op) {
    case 'PUSH': push(m, X, val(ins.v), L, null, `${s(ins.v)}`); msg = `Pushed ${s(ins.v)} onto ${X}.`; break;
    case 'DUP': { const r = read(m, X, 0, L); push(m, X, val(r.cell.v), L, r.where, r.where); msg = `Duplicated ${X}0.`; break; }
    case 'DROP': pop(m, X, L); L.push(`${X}0 retired: no native work`); msg = `Dropped ${X}0.`; break;
    case 'COPY': case 'MOVE': {
      const [F, T] = X.split('');
      const r = read(m, F, 0, L);
      if (ins.op === 'MOVE') pop(m, F, L);
      push(m, T, ins.op === 'MOVE' ? r.cell : val(r.cell.v), L, r.where, r.where);
      msg = ins.op === 'MOVE' ? `Moved ${F}0 to ${T}.` : `Copied ${F}0 to ${T}: one value, live on both stacks.`;
      break;
    }
    case 'CPUSH': { const r = read(m, X, 0, L); pop(m, X, L); push(m, 'C', r.cell, L, r.where, r.where); msg = `Moved ${X}0 onto C.`; break; }
    case 'CPOP': pop(m, 'C', L); L.push('C0 retired: no native work'); msg = 'Popped C.'; break;
    case 'CTAKE': { const r = read(m, 'C', 0, L); pop(m, 'C', L); push(m, X, r.cell, L, r.where, r.where); msg = `Moved C0 to ${X}.`; break; }
    case 'CGET': { const r = read(m, 'C', ins.n, L); push(m, X, val(r.cell.v), L, r.where, r.where); msg = `Copied C${ins.n} to ${X}.`; break; }
    case 'CSET': {
      const r = read(m, X, 0, L); pop(m, X, L);
      if (ins.n >= depth(m, 'C')) throw new Error(`C${ins.n} does not exist.`);
      writeAt(m, 'C', ins.n, r.cell, L, r.where);
      msg = `Wrote ${X}0 into C${ins.n}.`; break;
    }
    case 'BIN': {
      const xa = read(m, 'A', 0, L), yb = read(m, 'B', 0, L);
      const r = BIN[ins.fn].f(xa.cell.v, yb.cell.v);
      writeAt(m, X, 0, val(r), L, `${xa.where} ${BIN[ins.fn].sym} ${yb.where}`);
      pop(m, other(X), L);
      msg = `A0 ${BIN[ins.fn].sym} B0 = ${s(r)}; the result stays on ${X} and ${other(X)} pops.`;
      break;
    }
    case 'UN': {
      const r0 = read(m, X, 0, L); const r = UN[ins.fn].f(r0.cell.v);
      writeAt(m, X, 0, val(r), L, `${UN[ins.fn].sym}${r0.where}`);
      msg = `${ins.fn} of ${X}0 = ${s(r)}.`; break;
    }
    case 'ONE': {
      const fn = ins.fn;
      if (AONLY_UN[fn]) { const r0 = read(m, 'A', 0, L); const r = AONLY_UN[fn](r0.cell.v); writeAt(m, 'A', 0, val(r), L, `${fn.toLowerCase()} ${r0.where}`); msg = `${fn} of A0 = ${s(r)}.`; }
      else if (CHK[fn]) { const r0 = read(m, 'A', 0, L); if (CHK[fn](r0.cell.v)) throw new Abort(3); L.push('check passed: no native work beyond a compare'); msg = `${fn}: A0 fits.`; }
      else {
        const xa = read(m, 'A', 0, L), yb = read(m, 'B', 0, L);
        if (fn === 'POWS' && s(yb.cell.v) < 0n) throw new Abort(4);
        const r = vpow(xa.cell.v, yb.cell.v);
        writeAt(m, 'A', 0, val(r), L, `${xa.where} ^ ${yb.where}`); pop(m, 'B', L);
        msg = `A0 ^ B0 = ${s(r)}.`;
      }
      break;
    }
    case 'JMP': next = ins.target; L.push('jump'); msg = `Jumped to ${ins.label}.`; break;
    case 'JZ': case 'JNZ': {
      const r = read(m, X, 0, L); pop(m, X, L);
      const z = r.cell.v === 0n, taken = (ins.op === 'JZ') === z;
      if (taken) next = ins.target;
      L.push(`test ${r.where}, ${taken ? 'jump' : 'fall through'}`);
      msg = `${X}0 is ${s(r.cell.v)}, so the branch ${taken ? 'jumps to ' + ins.label : 'falls through'}.`; break;
    }
    case 'CB': {
      const xa = read(m, 'A', 0, L), yb = read(m, 'B', 0, L);
      pop(m, 'A', L); pop(m, 'B', L);
      const taken = CMPBR[ins.fn](xa.cell.v, yb.cell.v);
      if (taken) next = ins.target;
      L.push(`cmp ${xa.where}, ${yb.where}; ${taken ? 'jump' : 'fall through'}`);
      msg = `${ins.fn}: A0 = ${s(xa.cell.v)}, B0 = ${s(yb.cell.v)}, so the branch ${taken ? 'jumps to ' + ins.label : 'falls through'}.`; break;
    }
    case 'CALL': push(m, 'C', { v: BigInt(m.pc + 1), ret: m.pc + 1 }, L, null, 'return address'); next = ins.target; msg = `Called ${ins.label}; the return address is on C.`; break;
    case 'TCALL': next = ins.target; L.push('jump: no return address'); msg = `Tail call to ${ins.label}.`; break;
    case 'RET': {
      const r = read(m, 'C', 0, L); pop(m, 'C', L);
      if (r.cell.ret == null) throw new Error('RET found no return address on C0.');
      next = r.cell.ret; L.push(`jump through ${r.where}`); msg = 'Returned to the caller.'; break;
    }
    case 'ABORT': throw new Abort(ins.n);
    case 'HALT': {
      m.halted = true; next = m.pc; L.push('flush the banks and stop');
      const top = depth(m, 'A') ? (m.a ? m.h[m.a - 1] : m.memA[m.memA.length - 1]) : null;
      msg = top ? `Halted. A0 = ${s(top.v)}.` : 'Halted.'; break;
    }
  }
  m.pc = next;
  return { L, msg };
}

function snapshot(m, extra) {
  const logical = X => {
    const out = [];
    for (let n = 0; n < depth(m, X); n++) {
      const inReg = n < cnt(m, X);
      const M = mem(m, X);
      const cell = inReg ? regGet(m, regName(m, X, n)) : M[M.length - 1 - (n - cnt(m, X))];
      out.push({ v: cell.v, ret: cell.ret, where: inReg ? regName(m, X, n) : 'mem' });
    }
    return out;
  };
  const owners = [...Array(NBANK).keys()].map(i => (i < m.a ? 'A' : i >= NBANK - m.b ? 'B' : 'free'));
  return Object.assign({
    A: logical('A'), B: logical('B'), C: logical('C'),
    h: m.h.map((c, i) => (owners[i] === 'free' ? null : c && { v: c.v, ret: c.ret })), owners,
    c: m.c.map((c, i) => (i < m.k ? c && { v: c.v, ret: c.ret } : null)),
    a: m.a, b: m.b, k: m.k, pc: m.pc, halted: m.halted, reason: m.reason, stats: { ...m.stats },
  }, extra);
}

function run(code, limit = 5000) {
  const m = newMachine();
  const snaps = [snapshot(m, { msg: 'Ready. Step to execute the first instruction.', L: [], last: -1 })];
  while (!m.halted && !m.reason) {
    if (snaps.length > limit) { snaps[snaps.length - 1].msg += ` Stopped after ${limit} steps.`; snaps[snaps.length - 1].limited = true; break; }
    const idx = m.pc;
    if (idx < 0 || idx >= code.length) { m.reason = 255; snaps.push(snapshot(m, { msg: 'Stopped: execution ran past the end.', L: [], last: -1, error: true })); break; }
    let res, err = null;
    try { res = step(m, code); }
    catch (e) {
      if (e instanceof Abort) { m.reason = e.code; err = `Abort ${e.code}: ${REASONS[e.code] || 'program abort'}.`; }
      else { m.reason = 255; err = 'Stopped: ' + e.message; }
    }
    snaps.push(snapshot(m, res ? { msg: res.msg, L: res.L, last: idx } : { msg: err, L: [], last: idx, error: true }));
  }
  return snaps;
}

/* ------------------------------------------------- Let compiler */
/* A subset of SLet (spec sections 1-8, 10, 13):
     words with typed parameters and result contracts (one result or a list),
     do ... end blocks: let (several binders), if, return, field stores,
       compound stores and call statements,
     expression conditionals, and/or/not, static constants, static partial supply,
     record schemas with keyed construction, field reads and methods.
   Types: u32, i32, u64, i64, bool and record schemas.
   Code generation is compile(E, dst): left operand to A, right to B, heavier
   operand first (Ershov). Bindings live on C, one cell per scalar. Records are
   scalarized: a record value is its fields' cells in canonical (name) order, so
   no memory is needed. A method is compiled copy-in/copy-out: the receiver's
   cells go in as leading arguments and come back as trailing results, and the
   caller writes them back into its own C slots. Tail self-calls become jumps. */
const KW = new Set(['let', 'extern', 'do', 'defer', 'end', 'if', 'then', 'else', 'return', 'and', 'or', 'not', 'true', 'false']);
const SCALARS = new Set(['u32', 'i32', 'u64', 'i64', 'bool']);
const ASSIGN_OPS = ['+=', '-=', '*=', '/=', '%=', '^=', '&=', '|=', '~=', '<<=', '>>='];
function wlex(text) {
  const toks = [];
  const re = /(--\[(=*)\[[\s\S]*?\]\2\]|--[^\n]*)|(\s+)|(0x[0-9a-fA-F_]+|0b[01_]+|\d[\d_]*)|([A-Za-z_]\w*)|(<<=|>>=|<<|>>|<=|>=|==|!=|[-+*/%^~&|]=|[-+*/%^~&|<>()=,:;{}.])/y;
  let p = 0, line = 0;
  while (p < text.length) {
    re.lastIndex = p;
    const m = re.exec(text);
    if (!m) { const e = new Error(`Line ${line + 1}: unexpected "${text[p]}".`); e.line = line; throw e; }
    if (m[4]) {
      const raw = m[4];
      if (/__|_$|^_/.test(raw.replace(/^0[xb]/, ''))) { const e = new Error(`Line ${line + 1}: a digit separator must sit between two digits.`); e.line = line; throw e; }
      const v = BigInt(raw.replace(/_/g, ''));
      if (v > M64) { const e = new Error(`Line ${line + 1}: the literal does not fit in 64 bits.`); e.line = line; throw e; }
      toks.push({ t: 'num', v, line });
    } else if (m[5]) toks.push({ t: KW.has(m[5]) ? m[5] : 'id', v: m[5], line });
    else if (m[6]) toks.push({ t: m[6], v: m[6], line });
    line += (m[0].match(/\n/g) || []).length;
    p = re.lastIndex;
  }
  toks.push({ t: 'eof', v: 'end of file', line });
  return toks;
}

function wparse(text) {
  const toks = wlex(text);
  let p = 0, nid = 0;
  const peek = (k = 0) => toks[p + k], next = () => toks[p++];
  const err = (m, tk = peek()) => { const e = new Error(`Line ${tk.line + 1}: ${m}`); e.line = tk.line; throw e; };
  const expect = (t, what) => { const k = next(); if (k.t !== t) err(`expected ${what || '"' + t + '"'} but found "${k.v}".`, k); return k; };
  const node = (o, tk) => Object.assign(o, { id: ++nid, line: tk.line });
  function type() {
    const k = expect('id', 'a type');
    return { name: k.v, line: k.line };
  }
  function resultSpec() {                     /* -> list of type specs */
    if (peek().t === '(') {
      next();
      const out = [];
      if (peek().t === ')') { next(); return out; }
      for (;;) { out.push(type()); if (peek().t === ',') { next(); continue; } expect(')'); return out; }
    }
    return [type()];
  }
  function params() {
    expect('(');
    const out = [];
    if (peek().t === ')') { next(); return out; }
    for (;;) {
      const names = [expect('id', 'a parameter name')];
      while (peek().t === ',') { next(); names.push(expect('id', 'a parameter name')); }
      expect(':', '":" and a type');
      const t = type();
      names.forEach(n => out.push({ name: n.v, type: t }));
      if (peek().t === ',') { next(); continue; }
      expect(')');
      return out;
    }
  }
  function args() {
    expect('(');
    const out = [];
    if (peek().t !== ')') for (;;) { out.push(expr()); if (peek().t === ',') { next(); if (peek().t === ')') break; continue; } break; }
    expect(')');
    return out;
  }
  function primary() {
    const k = next();
    if (k.t === 'num') return node({ k: 'num', v: k.v }, k);
    if (k.t === 'true' || k.t === 'false') return node({ k: 'bool', v: k.t === 'true' ? 1n : 0n }, k);
    if (k.t === 'id') {
      if (peek().t === '(') return node({ k: 'call', name: k.v, args: args() }, k);
      if (peek().t === '{') {
        next();
        const inits = [];
        while (peek().t !== '}') {
          const f = expect('id', 'a field name'); expect('=', '"=" (a keyed supply)');
          inits.push({ name: f.v, e: expr(), line: f.line });
          if (peek().t === ',') next(); else break;
        }
        expect('}');
        return node({ k: 'make', schema: k.v, inits }, k);
      }
      return node({ k: 'var', name: k.v }, k);
    }
    if (k.t === '(') {
      const e = expr(); expect(')');
      return e.k === 'call' || e.k === 'mcall' ? node({ k: 'adjust', x: e }, k) : e;
    }
    err(`unexpected "${k.v}".`, k);
  }
  function postfix() {
    let e = primary();
    while (peek().t === '.') {
      const k = next();
      const f = expect('id', 'a field or method name');
      if (peek().t === '(') e = node({ k: 'mcall', recv: e, name: f.v, args: args() }, k);
      else e = node({ k: 'field', base: e, name: f.v }, k);
    }
    return e;
  }
  function power() {
    const b = postfix();
    if (peek().t === '^') { const k = next(); return node({ k: 'pow', l: b, r: unary() }, k); }
    return b;
  }
  function unary() {
    const k = peek();
    if (k.t === '-' || k.t === '~' || k.t === 'not') { next(); return node({ k: 'un', op: k.t, x: unary() }, k); }
    return power();
  }
  const LEVELS = [['|'], ['~'], ['&'], ['<<', '>>'], ['+', '-'], ['*', '/', '%']];
  function binary(i) {
    if (i === LEVELS.length) return unary();
    let l = binary(i + 1);
    while (LEVELS[i].includes(peek().t)) { const k = next(); l = node({ k: 'bin', o: k.t, l, r: binary(i + 1) }, k); }
    return l;
  }
  const CMPS = ['==', '!=', '<', '<=', '>', '>='];
  function comparison() {
    const l = binary(0);
    if (CMPS.includes(peek().t)) {
      const k = next();
      const n = node({ k: 'bin', o: k.t, l, r: binary(0) }, k);
      if (CMPS.includes(peek().t)) err('comparisons cannot be chained; add parentheses.');
      return n;
    }
    return l;
  }
  function andExpr() { let l = comparison(); while (peek().t === 'and') { const k = next(); l = node({ k: 'and', l, r: comparison() }, k); } return l; }
  function orExpr() { let l = andExpr(); while (peek().t === 'or') { const k = next(); l = node({ k: 'or', l, r: andExpr() }, k); } return l; }
  function expr() {
    if (peek().t === 'if') {
      const k = next(); const c = expr(); expect('then'); const t = expr(); expect('else', '"else" (an expression conditional needs one)'); const e = expr();
      return node({ k: 'if', c, t, e }, k);
    }
    return orExpr();
  }
  function exprList() { const out = [expr()]; while (peek().t === ',') { next(); out.push(expr()); } return out; }
  function stmts(stop) {
    const out = [];
    while (!stop.includes(peek().t)) {
      const k = peek();
      if (k.t === ';') { next(); continue; }
      if (k.t === 'let') {
        next();
        const binders = [];
        for (;;) {
          const name = expect('id', 'a name').v;
          let ann = null; if (peek().t === ':') { next(); ann = type(); }
          binders.push({ name, ann });
          if (peek().t === ',') { next(); continue; }
          break;
        }
        expect('=');
        out.push({ k: 'let', binders, es: exprList(), line: k.line });
      } else if (k.t === 'if') {
        next(); const c = expr(); expect('then');
        const t = stmts(['else', 'end']); let e = [];
        if (peek().t === 'else') { next(); e = stmts(['end']); }
        expect('end');
        out.push({ k: 'if', c, t, e, line: k.line });
      } else if (k.t === 'return') {
        next();
        const es = stop.includes(peek().t) || peek().t === ';' ? [] : exprList();
        out.push({ k: 'return', es, line: k.line });
      } else if (k.t === 'id') {
        const target = postfix();
        const op = peek().t;
        if (op === '=' || ASSIGN_OPS.includes(op)) {
          next();
          if (target.k !== 'var' && target.k !== 'field') err('only a field can be assigned; bindings are immutable.', k);
          out.push({ k: 'store', target, op: op === '=' ? null : op.slice(0, -1), e: expr(), line: k.line });
        } else if (target.k === 'call' || target.k === 'mcall') {
          out.push({ k: 'callstmt', e: target, line: k.line });
        } else err('a statement here must be a call, a field store, let, if or return.', k);
      } else err(`a block holds let, if, return, field stores and calls; found "${k.v}".`);
    }
    return out;
  }
  function body() {
    if (peek().t === 'do') { next(); const b = stmts(['end']); expect('end'); return { block: b }; }
    return { expr: expr() };
  }
  const items = [];
  while (peek().t !== 'eof') {
    if (peek().t === ';') { next(); continue; }
    const k = expect('let', '"let" (a top-level declaration)');
    const name = expect('id', 'a name');
    if (SCALARS.has(name.v)) err(`"${name.v}" is reserved: it is one of the language's own words.`, name);
    const it = { name: name.v, line: k.line };
    if (peek().t === '(') {
      it.k = 'word'; it.params = params();
      it.results = null; if (peek().t === ':') { next(); it.results = resultSpec(); }
      expect('=');
      Object.assign(it, body());
    } else {
      it.ann = null; if (peek().t === ':') { next(); it.ann = type(); }
      expect('=');
      if (peek().t === '{') {
        next();
        it.k = 'schema'; it.fields = []; it.methods = [];
        while (peek().t !== '}') {
          const mn = expect('id', 'a field or method name');
          if (peek().t === ':') { next(); it.fields.push({ name: mn.v, type: type(), line: mn.line }); }
          else if (peek().t === '(') {
            const m = { k: 'word', name: mn.v, line: mn.line, params: params(), results: null };
            if (peek().t === ':') { next(); m.results = resultSpec(); }
            expect('=');
            Object.assign(m, body());
            it.methods.push(m);
          } else err('a schema member is "name: type" or a method "name(params) : result = body".', mn);
          if (peek().t === ',') next(); else break;
        }
        expect('}');
      } else { it.k = 'value'; it.expr = expr(); }
    }
    items.push(it);
  }
  return items;
}

/* ---- types: a scalar name, 'lit' (an untyped literal), or { rec: schemaName } */
const SIGNED = { i32: true, i64: true };
const WIDTH = { u32: 32, i32: 32, u64: 64, i64: 64 };
const isRec = t => t && typeof t === 'object';
const tname = t => (isRec(t) ? t.rec : t === 'lit' ? 'an untyped literal' : t);
function norm(v, t) {
  if (t === 'u32') return v & 0xffffffffn;
  if (t === 'i32') return u(BigInt.asIntN(32, v));
  if (t === 'bool') return v ? 1n : 0n;
  return u(v);
}
function litType(v) { return v >= 0n && v <= 0xffffffffn ? 'u32' : 'u64'; }
function failAt(m, at) { const e = new Error(`Line ${(at && at.line != null ? at.line : 0) + 1}: ${m}`); e.line = at && at.line; throw e; }
function unify(a, b, at) {
  if (isRec(a) || isRec(b)) {
    if (isRec(a) && isRec(b) && a.rec === b.rec) return a;
    failAt(`cannot combine ${tname(a)} with ${tname(b)}.`, at);
  }
  if (a === 'lit') return b; if (b === 'lit') return a;
  if (a === b) return a;
  if (a === 'bool' || b === 'bool') failAt(`cannot combine bool with ${a === 'bool' ? b : a}.`, at);
  if (!!SIGNED[a] !== !!SIGNED[b]) failAt(`mixing ${a} and ${b} rejects: signed and unsigned values need an explicit conversion.`, at);
  return WIDTH[a] >= WIDTH[b] ? a : b;
}
const concrete = (t, v) => (t === 'lit' ? litType(v == null ? 0n : v) : t);
const WRAPS = new Set(['+', '-', '*', '<<']);
function opFor(o, t) {
  const sg = !!SIGNED[t];
  return { '+': 'ADD', '-': 'SUB', '*': 'MUL', '/': sg ? 'DIVS' : 'DIVU', '%': sg ? 'REMS' : 'REMU', '&': 'AND', '|': 'OR', '~': 'XOR',
    '<<': 'SHL', '>>': sg ? 'SAR' : 'SHR', '==': 'EQ', '!=': 'NE', '<': sg ? 'LT' : 'LTU', '<=': sg ? 'LE' : 'LEU',
    '>': sg ? 'LT' : 'LTU', '>=': sg ? 'LE' : 'LEU' }[o];
}
const isCmp = o => ['==', '!=', '<', '<=', '>', '>='].includes(o);
function wOperands(n) { return n.o === '>' || n.o === '>=' ? [n.r, n.l] : [n.l, n.r]; }
function applyBin(o, t, x, y, at) {
  const op = opFor(o, t);
  try { return norm(BIN[op].f(x, y), isCmp(o) ? 'bool' : t); }
  catch (e) { if (e instanceof Abort) failAt('a known zero divisor rejects at compile time.', at); throw e; }
}

/* ---- the program model shared by the compiler and the evaluator */
function wmodel(text) {
  const items = wparse(text);
  const words = {}, consts = {}, schemas = {};
  for (const it of items) {
    if (words[it.name] || consts[it.name] || schemas[it.name]) failAt(`"${it.name}" is already defined.`, it);
    if (it.k === 'word') words[it.name] = it;
    if (it.k === 'schema') schemas[it.name] = it;
  }
  const resolve = spec => {
    if (SCALARS.has(spec.name)) return spec.name;
    if (schemas[spec.name]) return { rec: spec.name };
    if (['u8', 'u16', 'f64', 'unit', 'string', 'type'].includes(spec.name)) failAt(`the simulator does not support the type ${spec.name} yet.`, spec);
    failAt(`"${spec.name}" is not a type.`, spec);
  };
  for (const sc of Object.values(schemas)) {
    const seen = new Set();
    for (const f of sc.fields) { if (seen.has(f.name)) failAt(`the field "${f.name}" appears twice.`, f); seen.add(f.name); f.t = resolve(f.type); }
    sc.order = sc.fields.slice().sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));   /* canonical layout */
  }
  /* cells of a type: one per scalar, records flattened in canonical field order */
  const cellsOf = t => (isRec(t) ? schemas[t.rec].order.reduce((n, f) => n + cellsOf(f.t), 0) : 1);
  const fieldOffset = (t, name, at) => {
    const sc = schemas[t.rec]; let off = 0;
    for (const f of sc.order) { if (f.name === name) return { off, t: f.t }; off += cellsOf(f.t); }
    failAt(`${t.rec} has no field "${name}".`, at);
  };
  const cycle = (name, path) => {
    for (const f of schemas[name].fields) if (isRec(f.t)) {
      if (path.includes(f.t.rec)) failAt(`a record cannot contain itself by value; this would need a reference.`, f);
      cycle(f.t.rec, path.concat(f.t.rec));
    }
  };
  Object.keys(schemas).forEach(n => cycle(n, [n]));
  const wordSig = w => {
    w.ps = w.params.map(p => ({ name: p.name, t: resolve(p.type) }));
    w.rs = w.results ? w.results.map(resolve) : null;
  };
  Object.values(words).forEach(wordSig);
  for (const sc of Object.values(schemas)) {
    sc.mwords = {};
    for (const m of sc.methods) {
      if (sc.fields.some(f => f.name === m.name)) failAt(`"${m.name}" is both a field and a method.`, m);
      const w = Object.assign({}, m, { name: `${sc.name}__${m.name}`, method: m.name, self: { rec: sc.name } });
      wordSig(w);
      if (!w.rs) failAt(`the simulator needs a result type on the method "${m.name}" (use () for none).`, m);
      sc.mwords[m.name] = w;
    }
  }
  return { items, words, consts, schemas, resolve, cellsOf, fieldOffset };
}

function wcompile(text, opts = {}) {
  const M = wmodel(text);
  const { words, consts, schemas, cellsOf, fieldOffset } = M;
  const fail = failAt;
  /* ---- static evaluation (constants, folding, partial supply) */
  function staticVal(n, env) {
    switch (n.k) {
      case 'num': return { v: n.v, t: 'lit' };
      case 'bool': return { v: n.v, t: 'bool' };
      case 'var': return env(n.name) || null;
      case 'un': {
        const x = staticVal(n.x, env); if (!x) return null;
        if (n.op === 'not') { if (x.t !== 'bool') fail('not needs a bool.', n); return { v: x.v ^ 1n, t: 'bool' }; }
        if (x.t === 'bool') fail(`${n.op} needs an integer.`, n);
        if (x.t === 'lit') { const lt = litType(x.v); return { v: norm(n.op === '-' ? u(-x.v) : x.v ^ M64, lt), t: 'lit' }; }
        return { v: norm(n.op === '-' ? u(-x.v) : x.v ^ M64, x.t), t: x.t };
      }
      case 'bin': case 'pow': {
        const a = staticVal(n.l, env), b = staticVal(n.r, env); if (!a || !b) return null;
        if (n.k === 'pow') { const t = concrete(a.t, a.v); return { v: norm(vpow(norm(a.v, t), norm(b.v, 'u64')), t), t: a.t === 'lit' ? 'lit' : t }; }
        if (n.o === '<<' || n.o === '>>') { const t = concrete(a.t, a.v); return { v: applyBin(n.o, t, norm(a.v, t), norm(b.v, 'u64'), n), t: a.t === 'lit' ? 'lit' : t }; }
        const t = unify(a.t, b.t, n);
        if (t === 'lit' && !isCmp(n.o)) { const lt = litType(a.v > b.v ? a.v : b.v); return { v: applyBin(n.o, lt, norm(a.v, lt), norm(b.v, lt), n), t: 'lit' }; }
        const ct = concrete(t, t === 'lit' ? (a.v > b.v ? a.v : b.v) : 0n);
        const [A, B] = n.o === '>' || n.o === '>=' ? [b, a] : [a, b];
        return { v: applyBin(n.o, ct, norm(A.v, ct), norm(B.v, ct), n), t: isCmp(n.o) ? 'bool' : t };
      }
      case 'if': { const c = staticVal(n.c, env); if (!c) return null; return staticVal(c.v ? n.t : n.e, env); }
      case 'and': { const a = staticVal(n.l, env); if (!a) return null; return a.v ? staticVal(n.r, env) : { v: 0n, t: 'bool' }; }
      case 'or': { const a = staticVal(n.l, env); if (!a) return null; return a.v ? { v: 1n, t: 'bool' } : staticVal(n.r, env); }
      default: return null;
    }
  }
  const cenv = name => consts[name];
  for (const it of M.items) {
    if (it.k !== 'value') continue;
    const e = it.expr;
    if (e.k === 'call' && words[e.name] && e.args.length < words[e.name].ps.length) {
      const base = words[e.name], bound = {};
      e.args.forEach((a, i) => {
        const sv = staticVal(a, cenv);
        if (!sv || isRec(base.ps[i].t)) fail('a partial supply needs static scalar arguments.', a);
        bound[base.ps[i].name] = { v: norm(sv.v, base.ps[i].t), t: base.ps[i].t };
      });
      words[it.name] = Object.assign({}, base, { name: it.name, ps: base.ps.slice(e.args.length), bound, from: base.name, supplyLine: it.line });
      continue;
    }
    const sv = staticVal(e, cenv);
    if (!sv) fail('a top-level value must be static here: a constant, a schema, or a partial supply of a word.', e);
    const t = it.ann ? M.resolve(it.ann) : concrete(sv.t, sv.v);
    consts[it.name] = { v: norm(sv.v, t), t };
  }
  if (!words.main) fail('the program needs a word called main; the simulator calls it.', M.items[0]);
  if (words.main.ps.length) fail('main takes no parameters.', words.main);
  if (!words.main.rs) words.main.rs = null;

  /* ---- code generation */
  let out = [];
  let lid = 0;
  const label = p => `${p}_${++lid}`;
  const emit = (text, src, node) => out.push({ text, src, node });
  const place = (name, src) => out.push({ label: name, src });
  const needed = new Set(['main']), done = new Set();
  const allWords = Object.assign({}, words);
  for (const sc of Object.values(schemas)) Object.assign(allWords, Object.fromEntries(Object.values(sc.mwords).map(w => [w.name, w])));
  let roots = [];
  const inferring = new Set();
  /* a word without a result contract: compile it once into a scratch buffer to
     learn its result types. A word that needs itself to know its own result is
     recursive, and the spec requires a contract there. */
  function inferResults(f, at) {
    if (inferring.has(f)) failAt(`"${f.name}" is recursive, so it needs a result type (spec section 10).`, at);
    inferring.add(f);
    const saveOut = out, saveRoots = roots;
    out = []; roots = [];
    try { genWord(f); } finally { out = saveOut; roots = saveRoots; inferring.delete(f); }
  }

  function ershov(n) {
    switch (n.k) {
      case 'num': case 'bool': case 'var': case 'field': return (n.need = 1);
      case 'un': return (n.need = ershov(n.x));
      case 'adjust': return (n.need = ershov(n.x));
      case 'call': case 'mcall': { let m = 1; n.args.forEach((a, i) => { m = Math.max(m, i + ershov(a)); }); return (n.need = Math.max(m, n.args.length)); }
      case 'make': { let m = 1; n.inits.forEach((f, i) => { m = Math.max(m, i + ershov(f.e)); }); return (n.need = m); }
      case 'if': return (n.need = Math.max(ershov(n.c), ershov(n.t), ershov(n.e)));
      case 'and': case 'or': return (n.need = Math.max(ershov(n.l), ershov(n.r)));
      default: {
        const [a, b] = n.k === 'pow' ? [n.l, n.r] : wOperands(n);
        const ea = ershov(a), eb = ershov(b);
        n.aFirst = opts.leftFirst ? true : ea >= eb;
        return (n.need = ea === eb ? ea + 1 : Math.max(ea, eb));
      }
    }
  }

  function genWord(w) {
    /* frame: C cells of this activation, bottom first, each {b: binding, i: cell} */
    const frame = [];
    let bid = 0;
    const scopes = [[]];                    /* bindings visible, innermost scope last */
    const bind = (name, t) => { const b = { id: ++bid, name, t, n: cellsOf(t) }; scopes[scopes.length - 1].push(b); return b; };
    const findBinding = name => {
      for (let s = scopes.length - 1; s >= 0; s--) for (let j = scopes[s].length - 1; j >= 0; j--) {
        const e = scopes[s][j];
        if (e.name === name) return e.alias || e;
      }
      return null;
    };
    const depthOf = (b, i) => { for (let k = frame.length - 1; k >= 0; k--) if (frame[k].b === b && frame[k].i === i) return frame.length - 1 - k; fail('internal: cell lost', w); };
    /* values on A: cells c0..c(n-1) with the last on top; CPUSH them all */
    const cpushCells = (b, src) => { for (let i = b.n - 1; i >= 0; i--) { emit('CPUSH.A', src, null); frame.push({ b, i }); } };
    place(w.name, w.supplyLine != null ? w.supplyLine : w.line);
    const self = w.self ? bind('$self', w.self) : null;
    /* entry: arguments arrive on A in order: receiver cells first (methods), then each parameter */
    const pbs = [];
    if (self) pbs.push(self);
    w.ps.forEach(p => pbs.push(bind(p.name, p.t)));
    for (let k = pbs.length - 1; k >= 0; k--) cpushCells(pbs[k], w.line);
    const nParamCells = frame.length;
    place(`${w.name}_body`, w.line);

    /* a place: binding + cell range, for a variable, a field path, or a bare field in a method */
    function placeOf(x) {
      if (x.k === 'var') {
        const b = findBinding(x.name);
        if (b && b.name !== '$self') return { b, off: 0, t: b.t };
        if (self && !b) {
          const sc = schemas[self.t.rec];
          if (sc.fields.some(f => f.name === x.name)) { const fo = fieldOffset(self.t, x.name, x); return { b: self, off: fo.off, t: fo.t }; }
        }
        return null;
      }
      if (x.k === 'field') {
        const base = placeOf(x.base);
        if (!base) return null;
        if (!isRec(base.t)) fail(`${tname(base.t)} has no fields.`, x);
        const fo = fieldOffset(base.t, x.name, x);
        return { b: base.b, off: base.off + fo.off, t: fo.t };
      }
      return null;
    }
    const env = name => {
      if (findBinding(name)) return null;
      if (self && schemas[self.t.rec].fields.some(f => f.name === name)) return null;
      if (w.bound && w.bound[name]) return w.bound[name];
      return consts[name] || null;
    };
    const wordOf = (x) => {
      if (x.k === 'call') { const f = words[x.name]; if (!f) fail(schemas[x.name] ? `${x.name} is a schema: construct it with ${x.name} { field = value }.` : `there is no word called "${x.name}".`, x); return f; }
      const rt = typeOf(x.recv);
      if (!isRec(rt)) fail(`${tname(rt)} has no methods.`, x);
      const m = schemas[rt.rec].mwords[x.name];
      if (!m) fail(`${rt.rec} has no method "${x.name}".`, x);
      return m;
    };
    /* results of a call, as a list of types */
    const resultsOf = x => { const f = wordOf(x); if (!f.rs) inferResults(f, x); return f.rs; };
    function typeOf(x) {
      const sv = staticVal(x, env); if (sv) return sv.t;
      switch (x.k) {
        case 'var': case 'field': {
          const pl = placeOf(x);
          if (pl) return pl.t;
          if (x.k === 'field') { const bt = typeOf(x.base); if (!isRec(bt)) fail(`${tname(bt)} has no fields.`, x); return fieldOffset(bt, x.name, x).t; }
          fail(`"${x.name}" is not defined here.`, x);
        }
        case 'un': { const t = typeOf(x.x); if (x.op === 'not') { if (t !== 'bool') fail('not needs a bool.', x); return 'bool'; } if (t === 'bool' || isRec(t)) fail(`${x.op} needs an integer.`, x); return t; }
        case 'pow': return typeOf(x.l);
        case 'bin': {
          const a = typeOf(x.l), b = typeOf(x.r);
          if (isRec(a) || isRec(b)) fail(`${x.o} does not apply to records.`, x);
          if (x.o === '<<' || x.o === '>>') return a;
          const t = unify(a, b, x); if (isCmp(x.o)) return 'bool'; if (t === 'bool') fail(`${x.o} needs integers.`, x); return t;
        }
        case 'and': case 'or': return 'bool';
        case 'if': { const k = staticVal(x.c, env); return k ? typeOf(k.v ? x.t : x.e) : unify(typeOf(x.t), typeOf(x.e), x); }
        case 'call': case 'mcall': { const rs = resultsOf(x); if (!rs.length) fail(`"${x.name}" returns nothing, so it has no value.`, x); return rs[0]; }
        case 'adjust': return typeOf(x.x);
        case 'make': { if (!schemas[x.schema]) fail(`"${x.schema}" is not a schema.`, x); return { rec: x.schema }; }
      }
      return 'lit';
    }
    const normOp = (t, dst, src, node) => {
      if (t === 'u32') emit(`ZX32.${dst}`, src, node);
      else if (t === 'i32') emit(`SX32.${dst}`, src, node);
    };
    /* compile(E, dst) for one scalar value */
    function gen(x, dst, want) {
      genRaw(x, dst, want);
      if (!staticVal(x, env) && want && SCALARS.has(want) && want !== 'bool' && !['var', 'field', 'call', 'mcall', 'adjust'].includes(x.k)) {
        const own = typeOf(x);
        if (own === 'lit' && concrete(own, 0n) === 'u32' && want === 'i32') emit(`SX32.${dst}`, x.line, x.id);
      }
    }
    function genRaw(x, dst, want) {
      const sv = staticVal(x, env);
      x.dst = dst;
      if (sv) { const t = sv.t === 'lit' ? (want && SCALARS.has(want) ? want : litType(sv.v)) : sv.t; return emit(`PUSH.${dst} ${s(norm(sv.v, t))}`, x.line, x.id); }
      switch (x.k) {
        case 'var': case 'field': {
          const pl = placeOf(x);
          if (pl) { if (isRec(pl.t)) fail(`a whole ${pl.t.rec} is not a single value here.`, x); return emit(`CGET.${dst} ${depthOf(pl.b, pl.off)}`, x.line, x.id); }
          if (x.k === 'field') {
            /* a field of a computed record: put the record on C for a moment */
            const bt = typeOf(x.base);
            const fo = fieldOffset(bt, x.name, x);
            if (isRec(fo.t)) fail('a whole record is not a single value here.', x);
            const tmp = bind('$tmp', bt);
            genCells(x.base);
            cpushCells(tmp, x.line);
            emit(`CGET.${dst} ${depthOf(tmp, fo.off)}`, x.line, x.id);
            for (let i = 0; i < tmp.n; i++) { emit('CPOP', x.line, null); frame.pop(); }
            scopes[scopes.length - 1].pop();
            return;
          }
          fail(`"${x.name}" is not defined here.`, x);
        }
        case 'un': {
          const t = concrete(typeOf(x), 0n);
          gen(x.x, dst, t);
          if (x.op === 'not') return emit(`LNOT.${dst}`, x.line, x.id);
          emit(`${x.op === '-' ? 'NEG' : 'NOT'}.${dst}`, x.line, x.id);
          if (x.op === '-' || t === 'u32') normOp(t, dst, x.line, x.id);
          return;
        }
        case 'pow': {
          const t = concrete(typeOf(x.l), 0n);
          if (x.aFirst) { gen(x.l, 'A', t); gen(x.r, 'B', 'u64'); } else { gen(x.r, 'B', 'u64'); gen(x.l, 'A', t); }
          emit(SIGNED[t] ? 'POWS' : 'POW', x.line, x.id);
          normOp(t, 'A', x.line, x.id);
          if (dst === 'B') emit('MOVE.AB', x.line, x.id);
          return;
        }
        case 'bin': {
          const ta = typeOf(x.l), tb = typeOf(x.r);
          const shift = x.o === '<<' || x.o === '>>';
          const t = concrete(shift ? ta : unify(ta, tb, x), 0n);
          if (t === 'bool' && !['==', '!='].includes(x.o)) fail(`${x.o} needs integers.`, x);
          const [a, b] = wOperands(x);
          const wantA = shift ? t : t, wantB = shift ? 'u32' : t;
          if (x.aFirst) { gen(a, 'A', wantA); gen(b, 'B', wantB); } else { gen(b, 'B', wantB); gen(a, 'A', wantA); }
          emit(`${opFor(x.o, t)}.${dst}`, x.line, x.id);
          if (WRAPS.has(x.o) || (x.o === '/' && t === 'i32')) normOp(t, dst, x.line, x.id);
          return;
        }
        case 'if': {
          const k = staticVal(x.c, env);
          if (k) return gen(k.v ? x.t : x.e, dst, want);
          const le = label('else'), lend = label('endif');
          genFalse(x.c, le);
          gen(x.t, dst, want); emit(`JMP ${lend}`, x.line, x.id);
          place(le, x.line); gen(x.e, dst, want); place(lend, x.line);
          return;
        }
        case 'and': case 'or': {
          const lalt = label(x.k === 'and' ? 'false' : 'rhs'), lend = label('end');
          ershov(x.l); gen(x.l, 'A', 'bool'); emit(`JZ.A ${lalt}`, x.line, x.id);
          if (x.k === 'and') { gen(x.r, dst, 'bool'); emit(`JMP ${lend}`, x.line, x.id); place(lalt, x.line); emit(`PUSH.${dst} 0`, x.line, x.id); }
          else { emit(`PUSH.${dst} 1`, x.line, x.id); emit(`JMP ${lend}`, x.line, x.id); place(lalt, x.line); gen(x.r, dst, 'bool'); }
          place(lend, x.line);
          return;
        }
        case 'call': case 'mcall': case 'adjust': {
          const c = x.k === 'adjust' ? x.x : x;
          const rs = resultsOf(c);
          if (!rs.length) fail(`"${c.name}" returns nothing, so it has no value.`, c);
          if (isRec(rs[0])) fail(`"${c.name}" returns a record, which is not a single value here.`, c);
          genCall(c);
          const extra = rs.reduce((n, t) => n + cellsOf(t), 0) - 1;
          for (let i = 0; i < extra; i++) emit('DROP.A', x.line, x.id);   /* keep the first result */
          if (dst === 'B') emit('MOVE.AB', x.line, x.id);
          return;
        }
        case 'make': fail(`a whole ${x.schema} is not a single value here.`, x);
      }
      fail('this expression is not supported here.', x);
    }
    /* one value (a scalar or a whole record) as cells on A; returns its type */
    function genValue(x, want) {
      const t = typeOf(x);
      if (!isRec(t)) { gen(x, 'A', want); return t; }
      return genCells(x, 1)[0];
    }
    /* every value of x as cells on A, first value deepest; returns the list of types */
    function genCells(x, limit) {
      const t = typeOf(x);
      if (x.k === 'call' || x.k === 'mcall') {
        const rs = resultsOf(x);
        genCall(x);
        if (limit != null && rs.length > limit) {
          const extra = rs.slice(limit).reduce((n, tt) => n + cellsOf(tt), 0);
          for (let i = 0; i < extra; i++) emit('DROP.A', x.line, x.id);
          return rs.slice(0, limit);
        }
        return rs;
      }
      if (!isRec(t)) { gen(x, 'A', null); return [t]; }
      x.dst = 'A';
      switch (x.k) {
        case 'adjust': return genCells(x.x, 1);
        case 'var': case 'field': {
          const pl = placeOf(x);
          if (pl) { for (let i = 0; i < cellsOf(pl.t); i++) emit(`CGET.A ${depthOf(pl.b, pl.off + i)}`, x.line, x.id); return [pl.t]; }
          const bt = typeOf(x.base), fo = fieldOffset(bt, x.name, x);
          const tmp = bind('$tmp', bt);
          genCells(x.base); cpushCells(tmp, x.line);
          for (let i = 0; i < cellsOf(fo.t); i++) emit(`CGET.A ${depthOf(tmp, fo.off + i)}`, x.line, x.id);
          for (let i = 0; i < tmp.n; i++) { emit('CPOP', x.line, null); frame.pop(); }
          scopes[scopes.length - 1].pop();
          return [fo.t];
        }
        case 'make': {
          const sc = schemas[x.schema];
          const given = new Set();
          for (const f of x.inits) {
            if (!sc.fields.some(g => g.name === f.name)) fail(`${sc.name} has no field "${f.name}".`, f);
            if (given.has(f.name)) fail(`the field "${f.name}" is supplied twice.`, f);
            given.add(f.name);
          }
          for (const f of sc.fields) if (!given.has(f.name)) fail(`${sc.name} needs every field; "${f.name}" is missing (partial supply needs static values, which the simulator does not support).`, x);
          const written = x.inits.map(f => f.name).join(','), canon = sc.order.map(f => f.name).join(',');
          const want = name => sc.fields.find(g => g.name === name).t;
          if (written === canon) {
            for (const f of x.inits) { ershov(f.e); const ft = want(f.name); const got = genValue(f.e, isRec(ft) ? null : ft); unify(ft, got, f); }
          } else {
            /* initializers run in written order; park each on C, then read them in canonical order */
            const parked = {};
            for (const f of x.inits) {
              ershov(f.e); const ft = want(f.name);
              const got = genValue(f.e, isRec(ft) ? null : ft); unify(ft, got, f);
              const b = bind('$init', ft); cpushCells(b, f.line); parked[f.name] = b;
            }
            for (const f of sc.order) { const b = parked[f.name]; for (let i = 0; i < b.n; i++) emit(`CGET.A ${depthOf(b, i)}`, x.line, x.id); }
            for (const f of x.inits) { const b = parked[f.name]; for (let i = 0; i < b.n; i++) { emit('CPOP', x.line, null); frame.pop(); } scopes[scopes.length - 1].pop(); }
          }
          return [t];
        }
        case 'if': {
          const k = staticVal(x.c, env);
          if (k) return genCells(k.v ? x.t : x.e, limit);
          const le = label('else'), lend = label('endif');
          genFalse(x.c, le);
          genCells(x.t, 1); emit(`JMP ${lend}`, x.line, x.id);
          place(le, x.line); genCells(x.e, 1); place(lend, x.line);
          return [t];
        }
      }
      fail('this record expression is not supported here.', x);
    }
    /* a call: arguments on A, CALL, results on A. A method passes the receiver's
       cells first and writes the updated cells back into the receiver afterwards. */
    function genCall(x) {
      const f = wordOf(x);
      let recv = null;
      if (x.k === 'mcall') {
        recv = placeOf(x.recv);
        if (!recv) fail('a method needs a receiver that is a binding or a field of one.', x);
        for (let i = 0; i < cellsOf(recv.t); i++) emit(`CGET.A ${depthOf(recv.b, recv.off + i)}`, x.line, x.id);
      }
      const ps = f.ps;
      /* every argument but the last contributes one value; the last may expand */
      let k = 0;
      x.args.forEach((a, i) => {
        const last = i === x.args.length - 1;
        if (k >= ps.length) fail(`"${f.name}" takes ${ps.length} argument${ps.length === 1 ? '' : 's'}.`, a);
        if (last && (a.k === 'call' || a.k === 'mcall') && resultsOf(a).length > 1) {
          const rs = genCells(a);
          rs.forEach(rt => { if (k >= ps.length) fail(`too many values for "${f.name}".`, a); unify(ps[k].t, rt, a); k++; });
        } else {
          const got = genValue(a, isRec(ps[k].t) ? null : ps[k].t);
          unify(ps[k].t, got, a); k++;
        }
      });
      if (k !== ps.length) fail(`"${f.name}" takes ${ps.length} argument${ps.length === 1 ? '' : 's'}; partial supply at run time needs a lambda, which the simulator does not support.`, x);
      emit(`CALL ${f.name}`, x.line, x.id);
      needed.add(f.name);
      if (recv) {
        /* the method returned [results..., receiver cells]: write the receiver back */
        for (let i = cellsOf(recv.t) - 1; i >= 0; i--) emit(`CSET.A ${depthOf(recv.b, recv.off + i)}`, x.line, x.id);
      }
    }
    const popAll = (k, src) => { for (let i = 0; i < k; i++) emit('CPOP', src, null); };
    function genFalse(c, target) {
      if (c.k === 'bin' && isCmp(c.o) && !staticVal(c, env)) {
        const t = concrete(unify(typeOf(c.l), typeOf(c.r), c), 0n);
        const U = SIGNED[t] || t === 'bool' ? '' : 'U';
        const [br, swap] = { '==': ['BNE', false], '!=': ['BEQ', false], '<': ['BLE', true], '<=': ['BLT', true],
                             '>': ['BLE', false], '>=': ['BLT', false] }[c.o];
        const aNode = swap ? c.r : c.l, bNode = swap ? c.l : c.r;
        ershov(aNode); ershov(bNode);
        if (aNode.need >= bNode.need) { gen(aNode, 'A', t); gen(bNode, 'B', t); } else { gen(bNode, 'B', t); gen(aNode, 'A', t); }
        c.dst = 'branch';
        return emit(`${br === 'BEQ' || br === 'BNE' ? br : br + U} ${target}`, c.line, c.id);
      }
      ershov(c); gen(c, 'A', 'bool'); emit(`JZ.A ${target}`, c.line, c.id);
    }
    const tailOK = x => !w.self && x.k === 'call' && x.name === w.name && x.args.length === w.ps.length && !staticVal(x, env);
    /* return: results on A (a method adds its receiver cells), clear C, RET */
    function genReturn(es, src, at) {
      if (es.length === 1 && tailOK(es[0])) {
        const x = es[0];
        x.args.forEach((a, i) => { ershov(a); const got = genValue(a, isRec(w.ps[i].t) ? null : w.ps[i].t); unify(w.ps[i].t, got, a); });
        popAll(frame.length - nParamCells, src);
        for (let d = nParamCells - 1; d >= 0; d--) emit(`CSET.A ${d}`, src, x.id);
        emit(`JMP ${w.name}_body`, src, x.id);
        x.dst = 'A'; x.tail = true;
        return;
      }
      if (es.length === 1 && es[0].k === 'if' && !staticVal(es[0].c, env) && !w.self) {
        const x = es[0], le = label('else');
        const save = frame.length;
        genFalse(x.c, le);
        genReturn([x.t], src, at); frame.length = save;
        place(le, x.line); genReturn([x.e], src, at); frame.length = save;
        return;
      }
      const got = [];
      es.forEach((x, i) => {
        ershov(x);
        if (i === es.length - 1 && (x.k === 'call' || x.k === 'mcall')) got.push(...genCells(x));
        else { const want = w.rs && w.rs[got.length] && !isRec(w.rs[got.length]) ? w.rs[got.length] : null; got.push(genValue(x, want)); }
      });
      if (w.rs) {
        if (got.length !== w.rs.length) fail(`"${w.name}" returns ${w.rs.length} value${w.rs.length === 1 ? '' : 's'}, but this return gives ${got.length}.`, at);
        w.rs.forEach((t, i) => unify(t, got[i], at));
      } else w.rs = got.map(t => concrete(t, 0n));
      if (self) for (let i = 0; i < self.n; i++) emit(`CGET.A ${depthOf(self, i)}`, src, null);
      popAll(frame.length, src);
      emit('RET', src, null);
    }
    function genStore(st) {
      const pl = placeOf(st.target);
      if (!pl) fail('only a field can be assigned; bindings are immutable.', st);
      if (pl.b.name !== '$self' && pl.off === 0 && cellsOf(pl.b.t) === cellsOf(pl.t) && st.target.k === 'var') fail(`"${st.target.name}" is a binding, and bindings cannot be reassigned.`, st);
      ershov(st.e);
      if (st.op) {
        if (isRec(pl.t)) fail('a compound store needs a scalar field.', st);
        /* read the old value once, then the right-hand side, then store */
        const t = pl.t, fake = { k: 'bin', o: st.op, line: st.line, id: st.e.id };
        emit(`CGET.A ${depthOf(pl.b, pl.off)}`, st.line, null);
        if (st.op === '^') { gen(st.e, 'B', 'u64'); emit(SIGNED[t] ? 'POWS' : 'POW', st.line, null); normOp(t, 'A', st.line, null); }
        else {
          const rt = typeOf(st.e);
          if (!(st.op === '<<' || st.op === '>>')) unify(t, rt, st);
          gen(st.e, 'B', st.op === '<<' || st.op === '>>' ? 'u32' : t);
          emit(`${opFor(st.op, t)}.A`, st.line, null);
          if (WRAPS.has(st.op) || (st.op === '/' && t === 'i32')) normOp(t, 'A', st.line, null);
        }
        void fake;
        emit(`CSET.A ${depthOf(pl.b, pl.off)}`, st.line, null);
        return;
      }
      const got = genValue(st.e, isRec(pl.t) ? null : pl.t);
      unify(pl.t, got, st);
      for (let i = cellsOf(pl.t) - 1; i >= 0; i--) emit(`CSET.A ${depthOf(pl.b, pl.off + i)}`, st.line, null);
    }
    /* returns true when the statement list always returns */
    function genStmts(list) {
      scopes.push([]);
      const mark = frame.length;
      const leave = () => { scopes.pop(); };
      for (const st of list) {
        if (st.k === 'let') {
          for (const e of st.es) roots.push({ word: w.name, label: `let ${st.binders.map(b => b.name).join(', ')}`, e });
          /* every initializer but the last gives one value; the last may give several */
          const types = [];
          st.es.forEach((e, i) => {
            ershov(e);
            const pe = e.k === 'var' ? placeOf(e) : null;
            if (st.es.length === 1 && st.binders.length === 1 && pe && pe.b.name !== '$self' && pe.off === 0 && isRec(pe.t) && !st.binders[0].ann) {
              types.push('alias');                      /* a local alias keeps the same instance */
            } else if (i === st.es.length - 1 && (e.k === 'call' || e.k === 'mcall')) types.push(...genCells(e));
            else { const ann = st.binders[types.length] && st.binders[types.length].ann; const want = ann ? M.resolve(ann) : null; types.push(genValue(e, want && !isRec(want) ? want : null)); }
          });
          if (types[0] === 'alias') {
            /* a local alias keeps the same instance: no code, the name points at the same cells */
            scopes[scopes.length - 1].push({ name: st.binders[0].name, alias: placeOf(st.es[0]).b });
            continue;
          }
          if (types.length !== st.binders.length) fail(`${st.binders.length} name${st.binders.length === 1 ? '' : 's'} but ${types.length} value${types.length === 1 ? '' : 's'}; the simulator does not fill missing values with unit.`, st);
          const bs = st.binders.map((bd, i) => {
            let t = types[i];
            if (bd.ann) { const at = M.resolve(bd.ann); unify(at, t, st); t = at; }
            else t = isRec(t) ? t : concrete(t, 0n);
            return { bd, t };
          });
          /* cells on A: first value deepest; CPUSH from the top (the last value) down */
          const made = bs.map(x => ({ b: { id: ++bid, name: x.bd.name, t: x.t, n: cellsOf(x.t) } }));
          for (let k = made.length - 1; k >= 0; k--) cpushCells(made[k].b, st.line);
          made.forEach(m => scopes[scopes.length - 1].push(m.b));
        } else if (st.k === 'return') {
          st.es.forEach(e => roots.push({ word: w.name, label: 'return', e }));
          genReturn(st.es, st.line, st);
          frame.length = mark; leave(); return true;
        } else if (st.k === 'store') {
          roots.push({ word: w.name, label: 'store', e: st.e });
          genStore(st);
        } else if (st.k === 'callstmt') {
          roots.push({ word: w.name, label: 'call', e: st.e });
          ershov(st.e);
          const rs = resultsOf(st.e);
          genCall(st.e);
          const n = rs.reduce((a, t) => a + cellsOf(t), 0);
          for (let i = 0; i < n; i++) emit('DROP.A', st.line, null);
        } else {
          roots.push({ word: w.name, label: 'if', e: st.c });
          const sv = staticVal(st.c, env);
          if (sv) { if (genStmts(sv.v ? st.t : st.e)) { frame.length = mark; leave(); return true; } continue; }
          const le = label('else'), lend = label('endif');
          genFalse(st.c, le);
          const rt = genStmts(st.t);
          if (!rt) emit(`JMP ${lend}`, st.line, null);
          place(le, st.line);
          const re = genStmts(st.e);
          place(lend, st.line);
          if (rt && re) { frame.length = mark; leave(); return true; }
        }
      }
      popAll(frame.length - mark, list.length ? list[list.length - 1].line : w.line);
      frame.length = mark;
      leave();
      return false;
    }
    if (w.block) {
      if (!genStmts(w.block)) {
        if (w.rs && w.rs.length === 0) genReturn([], w.line, w);
        else fail(`every path through "${w.name}" must return.`, w);
      }
    } else {
      roots.push({ word: w.name, label: 'body', e: w.expr });
      genReturn([w.expr], w.line, w);
    }
  }
  emit('CALL main', words.main.line, null);
  emit('HALT', words.main.line, null);
  /* compile main first so an unannotated main gets its results inferred */
  while (needed.size > done.size) {
    for (const name of [...needed]) if (!done.has(name)) {
      done.add(name);
      genWord(allWords[name]);
    }
  }
  const asmLines = [], map = [], insAsmLine = [];
  for (const o of out) {
    if (o.label) { asmLines.push(o.label + ':'); continue; }
    insAsmLine.push(asmLines.length);
    asmLines.push('  ' + o.text);
    map.push({ src: o.src, node: o.node });
  }
  return { asm: asmLines.join('\n'), map, insAsmLine, roots, words, consts, schemas, model: M };
}

/* reference evaluator: runs the source directly. Records are live objects with
   value semantics on calls, returns and stores; a local alias shares the
   object; a method mutates its receiver in place. Returns main's results as a
   flat list of cells (records in canonical field order), first result first. */
function weval(text) {
  const C = wcompile(text);
  const { words, consts, schemas } = C;
  const copy = v => (v && v.rec ? { rec: v.rec, f: Object.fromEntries(Object.entries(v.f).map(([k, x]) => [k, copy(x)])) } : v);
  const conv = (v, t) => (isRec(t) ? copy(v) : { v: norm(v.v, t), t });
  const flat = v => (v && v.rec ? schemas[v.rec].order.flatMap(f => flat(v.f[f.name])) : [v.v]);
  function call(w, args, selfObj) {
    const frames = [{}];
    w.ps.forEach((p, i) => { frames[0][p.name] = { val: conv(args[i], p.t) }; });
    const find = name => { for (let i = frames.length - 1; i >= 0; i--) if (name in frames[i]) return frames[i][name]; return null; };
    const isField = name => selfObj && Object.prototype.hasOwnProperty.call(selfObj.f, name);
    const get = name => {
      const b = find(name); if (b) return b.val;
      if (isField(name)) return selfObj.f[name];
      if (w.bound && w.bound[name]) return w.bound[name];
      return consts[name];
    };
    const typeOfVal = v => (v.rec ? { rec: v.rec } : v.t);
    const fieldType = (rec, name) => schemas[rec].fields.find(f => f.name === name).t;
    const wordFor = x => (x.k === 'call' ? words[x.name] : schemas[stype(x.recv).rec].mwords[x.name]);
    const stype = x => {
      switch (x.k) {
        case 'num': return 'lit';
        case 'bool': case 'and': case 'or': return 'bool';
        case 'var': return typeOfVal(get(x.name));
        case 'field': return fieldType(stype(x.base).rec, x.name);
        case 'make': return { rec: x.schema };
        case 'un': return x.op === 'not' ? 'bool' : stype(x.x);
        case 'pow': return stype(x.l);
        case 'adjust': return stype(x.x);
        case 'bin': return isCmp(x.o) ? 'bool' : x.o === '<<' || x.o === '>>' ? stype(x.l) : unify(stype(x.l), stype(x.r), x);
        case 'if': return known(x.c) ? stype(ev(x.c).v ? x.t : x.e) : unify(stype(x.t), stype(x.e), x);
        case 'call': case 'mcall': return wordFor(x).rs[0];
      }
    };
    const known = x => {
      switch (x.k) {
        case 'num': case 'bool': return true;
        case 'var': return !find(x.name) && !isField(x.name) && !!(consts[x.name] || (w.bound && w.bound[x.name]));
        case 'call': case 'mcall': case 'make': case 'field': case 'adjust': return false;
        case 'un': return known(x.x);
        case 'if': return known(x.c) && (ev(x.c).v ? known(x.t) : known(x.e));
        default: return known(x.l) && known(x.r);
      }
    };
    /* a place: { get, set } for a binding's record, a field path, or a bare field */
    const placeRef = x => {
      if (x.k === 'var') {
        const b = find(x.name);
        if (b) return { get: () => b.val, set: v => { b.val = v; } };
        if (isField(x.name)) return { get: () => selfObj.f[x.name], set: v => { selfObj.f[x.name] = v; } };
        return null;
      }
      if (x.k === 'field') {
        const base = placeRef(x.base);
        if (!base) return null;
        return { get: () => base.get().f[x.name], set: v => { base.get().f[x.name] = v; } };
      }
      return null;
    };
    const ev = x => {
      switch (x.k) {
        case 'num': return { v: x.v, t: 'lit' };
        case 'bool': return { v: x.v, t: 'bool' };
        case 'var': return get(x.name);
        case 'field': { const r = ev(x.base); return r.f[x.name]; }
        case 'adjust': return evAll(x.x)[0];
        case 'make': {
          const sc = schemas[x.schema], f = {};
          for (const it of x.inits) f[it.name] = conv(ev(it.e), sc.fields.find(g => g.name === it.name).t);
          return { rec: x.schema, f };
        }
        case 'un': {
          const a = ev(x.x);
          if (x.op === 'not') return { v: a.v ^ 1n, t: 'bool' };
          if (a.t === 'lit') { const lt = litType(a.v); return { v: norm(x.op === '-' ? u(-a.v) : a.v ^ M64, lt), t: 'lit' }; }
          return { v: norm(x.op === '-' ? u(-a.v) : a.v ^ M64, a.t), t: a.t };
        }
        case 'pow': { const a = ev(x.l), b = ev(x.r); const t = concrete(a.t, a.v); if (SIGNED[t] && s(norm(b.v, 'u64')) < 0n) throw new Abort(4); return { v: norm(vpow(norm(a.v, t), norm(b.v, 'u64')), t), t: a.t === 'lit' ? 'lit' : t }; }
        case 'bin': {
          const a = ev(x.l), b = ev(x.r);
          if (x.o === '<<' || x.o === '>>') { const t = concrete(a.t, a.v); return { v: norm(BIN[opFor(x.o, t)].f(norm(a.v, t), norm(b.v, 'u64')), t), t: a.t === 'lit' ? 'lit' : t }; }
          let t = unify(a.t, b.t, x);
          const lit = t === 'lit';
          if (lit) t = litType(a.v > b.v ? a.v : b.v);
          const [A, B] = x.o === '>' || x.o === '>=' ? [b, a] : [a, b];
          const r = BIN[opFor(x.o, t)].f(norm(A.v, t), norm(B.v, t));
          return isCmp(x.o) ? { v: r, t: 'bool' } : { v: norm(r, t), t: lit ? 'lit' : t };
        }
        case 'and': return ev(x.l).v ? ev(x.r) : { v: 0n, t: 'bool' };
        case 'or': return ev(x.l).v ? { v: 1n, t: 'bool' } : ev(x.r);
        case 'if': {
          const r = ev(x.c).v ? ev(x.t) : ev(x.e);
          if (known(x.c) || r.rec) return r;
          const t = unify(stype(x.t), stype(x.e), x);
          return t !== 'lit' && r.t === 'lit' ? { v: norm(r.v, t), t } : r;
        }
        case 'call': case 'mcall': return evAll(x)[0];
      }
    };
    function evAll(x) {
      if (x.k !== 'call' && x.k !== 'mcall') return [ev(x)];
      const f = wordFor(x);
      const argv = [];
      x.args.forEach((a, i) => {
        if (i === x.args.length - 1 && (a.k === 'call' || a.k === 'mcall')) argv.push(...evAll(a));
        else argv.push(ev(a));
      });
      if (x.k === 'mcall') return call(f, argv, placeRef(x.recv).get());
      return call(f, argv, null);
    }
    function exec(list) {
      frames.push({});
      try {
        for (const st of list) {
          if (st.k === 'let') {
            const pe = st.es.length === 1 && st.binders.length === 1 && st.es[0].k === 'var' && find(st.es[0].name);
            if (pe && pe.val.rec && !st.binders[0].ann) { frames[frames.length - 1][st.binders[0].name] = pe; continue; }
            const vals = [];
            st.es.forEach((e, i) => { if (i === st.es.length - 1) vals.push(...evAll(e)); else vals.push(ev(e)); });
            st.binders.forEach((bd, i) => {
              const v = vals[i];
              const t = bd.ann ? C.model.resolve(bd.ann) : (v.rec ? { rec: v.rec } : concrete(v.t, v.v));
              frames[frames.length - 1][bd.name] = { val: conv(v, t) };
            });
          } else if (st.k === 'return') {
            const vals = [];
            st.es.forEach((e, i) => { if (i === st.es.length - 1) vals.push(...evAll(e)); else vals.push(ev(e)); });
            return { ret: vals };
          } else if (st.k === 'store') {
            const pr = placeRef(st.target);
            if (!st.op) {
              const old = pr.get();
              pr.set(old && old.rec ? copy(ev(st.e)) : { v: norm(ev(st.e).v, old.t), t: old.t });
            } else {
              const old = pr.get(), t = old.t;
              const rhs = ev(st.e);
              let r;
              if (st.op === '^') { if (SIGNED[t] && s(norm(rhs.v, 'u64')) < 0n) throw new Abort(4); r = vpow(old.v, norm(rhs.v, 'u64')); }
              else r = BIN[opFor(st.op, t)].f(old.v, st.op === '<<' || st.op === '>>' ? norm(rhs.v, 'u64') : norm(rhs.v, t));
              pr.set({ v: norm(r, t), t });
            }
          } else if (st.k === 'callstmt') evAll(st.e);
          else { const r = exec(ev(st.c).v ? st.t : st.e); if (r) return r; }
        }
        return null;
      } finally { frames.pop(); }
    }
    let rs = w.block ? exec(w.block) : { ret: evAll(w.expr) };
    rs = rs ? rs.ret : [];
    return rs.map((v, i) => (w.rs && w.rs[i] ? conv(v, w.rs[i]) : v.rec ? copy(v) : { v: norm(v.v, concrete(v.t, v.v)), t: concrete(v.t, v.v) }));
  }
  return call(words.main, [], null).flatMap(flat);
}

/* the combined depth a plain left-to-right order would need, for comparison */
function naiveNeed(n) {
  switch (n.k) {
    case 'num': case 'bool': case 'var': case 'field': return 1;
    case 'un': case 'adjust': return naiveNeed(n.x);
    case 'call': case 'mcall': { let m = 1; n.args.forEach((a, i) => { m = Math.max(m, i + naiveNeed(a)); }); return Math.max(m, n.args.length); }
    case 'make': { let m = 1; n.inits.forEach((f, i) => { m = Math.max(m, i + naiveNeed(f.e)); }); return m; }
    case 'if': return Math.max(naiveNeed(n.c), naiveNeed(n.t), naiveNeed(n.e));
    case 'and': case 'or': return Math.max(naiveNeed(n.l), naiveNeed(n.r));
    default: { const [a, b] = n.k === 'pow' ? [n.l, n.r] : wOperands(n); return Math.max(naiveNeed(a), 1 + naiveNeed(b)); }
  }
}

G.SimCore = { wparse, norm, unify, concrete, litType, opFor, isCmp, WRAPS, setBanks, u, s, NBANK, CBANK, REASONS, BIN, UN, CHK, CMPBR, assemble, layout, insLen, fmt, specName, run,
  wcompile, weval, naiveNeed, wOperands, Abort };
})(typeof window !== 'undefined' ? window : globalThis);
