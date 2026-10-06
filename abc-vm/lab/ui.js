(() => {
'use strict';
const S = window.SimCore;
const $ = id => document.getElementById(id);
const esc = x => String(x).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/* ------------------------------------------------------------ examples */
const W = 'SLet';
const EXAMPLES = [
  { id: 's13', group: W, kind: 'slet', title: 'Section 13: xorshift and skip',
    note: 'The spec\'s worked example. <b>next32 = xorshift(13, 17, 5)</b> is a static partial supply: the compiler makes a specialized word with the shift amounts folded in. <b>skip</b> calls itself in tail position, so that call becomes <b>CSET</b> plus a <b>JMP</b>: a loop. Every <b>u32</b> left shift and subtraction is followed by <b>ZX32</b>. Switch the values to Unsigned to read the results.',
    src: 'let xorshift(a, b, c, s: u32) : u32 = do\n  let s1 = s ~ (s << a)\n  let s2 = s1 ~ (s1 >> b)\n  return s2 ~ (s2 << c)\nend\n\nlet next32 = xorshift(13, 17, 5)\nlet seed(s: u32) : u32 = if s == 0 then 2463534242 else s\n\nlet skip(s, n: u32) : u32 = do\n  if n == 0 then return s end\n  return skip(next32(s), n - 1)\nend\n\nlet main() : u32 = skip(seed(0), 3)' },
  { id: 'area', group: W, kind: 'slet', title: 'Two subtrees meet',
    note: 'Parameters arrive on A and move to C. In the body, <b>w + m</b> is compiled into A and <b>h - m</b> into B, then one <b>MUL.A</b> folds them. Open the Tree view to see each node\'s destination stack.',
    src: 'let area(w, h, m: u32) : u32 = (w + m) * (h - m)\n\nlet main() : u32 = area(10, 7, 2)' },
  { id: 'deep', group: W, kind: 'slet', title: 'Heavier subtree first',
    note: 'A right-deep tree. Left to right it needs a combined A + B depth of 8 and spills out of the four-register bank. <b>compile(E, dst)</b> evaluates each node\'s heavier operand first (its Ershov number), so the body runs at depth 2 with no spills. The box on the right compares both orders.',
    src: 'let deep(x: u32) : u32 = 1 + (2 * (3 + (4 * (5 + (6 * (7 + x))))))\n\nlet main() : u32 = deep(8)' },
  { id: 'clamp', group: W, kind: 'slet', title: 'Routing > and >=',
    note: 'The ISA has no greater-than forms. Each <b>if</b> condition becomes one compare-and-branch on the negated test: <b>x &lt; lo</b> branches away with <b>BLE</b> on the swapped operands, and <b>x &gt; hi</b> with <b>BLE</b> on the original order. <b>i32</b> picks the signed forms.',
    src: 'let clamp(x, lo, hi: i32) : i32 =\n  if x < lo then lo else if x > hi then hi else x\n\nlet main() : i32 =\n  clamp(-5, 0, 10) + clamp(42, 0, 10) * 100 + clamp(7, 0, 10) * 10000' },
  { id: 'signed', group: W, kind: 'slet', title: 'Signed arithmetic',
    note: 'Types choose instructions. <b>i32</b> division and remainder use <b>DIVS</b> and <b>REMS</b> (truncating toward zero, the remainder takes the dividend\'s sign), and every wrapping <b>i32</b> operation is followed by <b>SX32</b>. The result is -31.',
    src: 'let half(x: i32) : i32 = x / 2\nlet rem(x: i32) : i32 = x % 2\n\nlet main() : i32 = half(-7) * 10 + rem(-7)' },
  { id: 'gcd', group: W, kind: 'slet', title: 'Euclid: a tail call is a loop',
    note: 'The recursive call is in tail position inside an expression conditional, so it compiles to <b>CSET</b> on both parameters and a <b>JMP</b>. The C stack never grows, however many steps Euclid takes.',
    src: 'let gcd(a, b: u32) : u32 = if b == 0 then a else gcd(b, a % b)\n\nlet main() : u32 = gcd(1071, 462)' },
  { id: 'collatz', group: W, kind: 'slet', title: 'Collatz: a loop with three exits',
    note: 'Two tail calls in one block, both turned into jumps to the same loop head. 27 takes 111 steps to reach 1; use Fast, or drag the scrubber to the end.',
    src: 'let steps(n, count: u32) : u32 = do\n  if n == 1 then return count end\n  if n % 2 == 0 then return steps(n / 2, count + 1) end\n  return steps(3 * n + 1, count + 1)\nend\n\nlet main() : u32 = steps(27, 0)' },
  { id: 'fib', group: W, kind: 'slet', title: 'Recursive fib(10)',
    note: 'Not a tail call, so real <b>CALL</b>s. The two calls are the operands of <b>+</b>: the first delivers to A, the second is compiled for B, so it is a <b>CALL.B</b> and its result lands on B with no extra move. <b>n &lt; 2</b> is one compare-and-branch against an immediate.',
    src: 'let fib(n: u32) : u32 = if n < 2 then n else fib(n - 1) + fib(n - 2)\n\nlet main() : u32 = fib(10)' },
  { id: 'logic', group: W, kind: 'slet', title: 'and, or, not',
    note: '<b>and</b> and <b>or</b> short-circuit with jumps; a comparison used as a condition becomes one compare-and-branch. bool values are cells holding 0 or 1, and <b>not</b> is <b>LNOT</b>.',
    src: 'let between(x, lo, hi: u32) : bool = lo <= x and x <= hi\n\nlet score(a, b, c: u32) : u32 = do\n  let one = if between(a, 1, 9) then 1 else 0\n  let two = if between(b, 1, 9) or b == 100 then 10 else 0\n  return one + two + (if not between(c, 1, 9) then 100 else 0)\nend\n\nlet main() : u32 = score(5, 100, 50)' },
  { id: 'ipow', group: W, kind: 'slet', title: 'Exponentiation by squaring (u64)',
    note: '3<sup>40</sup> in <b>u64</b>, with tail calls. 64-bit types wrap natively, so no normalization instructions appear at all.',
    src: 'let ipow(base, e, acc: u64) : u64 = do\n  if e == 0 then return acc end\n  if e % 2 == 1 then return ipow(base * base, e / 2, acc * base) end\n  return ipow(base * base, e / 2, acc)\nend\n\nlet main() : u64 = ipow(3, 40, 1)' },
  { id: 'ratio', group: W, kind: 'slet', title: 'Abort: run-time division by zero',
    note: 'The divisor is a run-time value, so <b>DIVU</b> checks it and aborts with reason 1. Change <b>b</b> to the literal <b>0</b> in the body (<b>a / 0</b>) and the compiler rejects the program instead: a known zero divisor never reaches run time.',
    src: 'let ratio(a, b: u32) : u32 = a / b\n\nlet main() : u32 = ratio(10, 0)' },
  { id: "s13roll", group: "SLet: results, records, methods", kind: 'slet', title: "Section 13: roll and d6",
    note: "The rest of the spec's worked example. <b>roll</b> returns two results, which simply means two cells on A. <b>d6 = roll(6)</b> is a static partial supply, and <b>let next, face = d6(s)</b> binds both results at once: two <b>CPUSH</b>es. <b>main</b> itself returns two values, so A ends with two cells.",
    src: "let xorshift(a, b, c, s: u32) : u32 = do\n  let s1 = s ~ (s << a)\n  let s2 = s1 ~ (s1 >> b)\n  return s2 ~ (s2 << c)\nend\n\nlet next32 = xorshift(13, 17, 5)\nlet seed(s: u32) : u32 = if s == 0 then 2463534242 else s\n\nlet step(s: u32) : (u32, u32) = do\n  let t = next32(s)\n  return t, t\nend\n\nlet roll(bound, s: u32) : (u32, u32) = do\n  let t = next32(s)\n  return t, t % bound + 1\nend\n\nlet d6 = roll(6)\nlet d20 = roll(20)\n\nlet roll_then_step(s: u32) : (u32, u32) = do\n  let next, face = d6(s)\n  return next32(next), face\nend\n\nlet main() : (u32, u32) = roll_then_step(seed(0))" },
  { id: "divmod", group: "SLet: results, records, methods", kind: 'slet', title: "divmod: multiple results",
    note: "Results form an ordered vector, not a tuple. <b>forward</b> passes both results through untouched; <b>(divmod(a, b))</b> and <b>divmod(9, 4) + 1</b> are scalar contexts, so the extra result is dropped with one <b>DROP.A</b>. A result vector maps directly onto A.",
    src: "let divmod(a, b: u32) : (u32, u32) = do\n  return a / b, a % b\nend\nlet forward(a, b: u32) : (u32, u32) = divmod(a, b)\nlet first(a, b: u32) : u32 = (divmod(a, b))\nlet main() : (u32, u32, u32) = do\n  let q, r = forward(17, 5)\n  return q * 10 + r, first(100, 7), divmod(9, 4) + 1\nend" },
  { id: "rng", group: "SLet: results, records, methods", kind: 'slet', title: "Section 8: rng.draw",
    note: "A record with a method. Records are scalarized: <b>r</b> is one cell on C. <b>r.draw()</b> compiles copy-in/copy-out: the receiver's cells go in as leading arguments, come back as trailing results, and the caller writes them back with <b>CSET</b>. Inside the method, bare <b>state</b> is the receiver's field.",
    src: "let xorshift(a, b, c, s: u32) : u32 = do\n  let s1 = s ~ (s << a)\n  let s2 = s1 ~ (s1 >> b)\n  return s2 ~ (s2 << c)\nend\nlet next32 = xorshift(13, 17, 5)\n\nlet rng = {\n  state: u32,\n  draw() : u32 = do\n    state = next32(state)\n    return state\n  end,\n}\n\nlet draw_twice(s: u32) : (u32, u32) = do\n  let r = rng { state = s }\n  let before = r.state\n  r.draw()\n  return before, r.draw()\nend\n\nlet main() : (u32, u32) = draw_twice(2463534242)" },
  { id: "points", group: "SLet: results, records, methods", kind: 'slet', title: "Records: points and aliases",
    note: "Fields are stored in canonical (name) order, so <b>point { y = -7, x = 3 }</b> evaluates y first but lays out x first, parking values on C for a moment. Passing and returning copies the record's cells. <b>let c = b</b> is a local alias: no code at all, and <b>c.x += 100</b> changes <b>b</b>, as the spec requires.",
    src: "let point = { x: i32, y: i32 }\n\nlet add(p, q: point) : point = point { x = p.x + q.x, y = p.y + q.y }\nlet manhattan(p: point) : i32 = (if p.x < 0 then -p.x else p.x) + (if p.y < 0 then -p.y else p.y)\n\nlet main() : (i32, point) = do\n  let a = point { y = -7, x = 3 }\n  let b = add(a, point { x = -10, y = 2 })\n  let c = b\n  c.x += 100\n  return manhattan(a), b\nend" },
  { id: "nested", group: "SLet: results, records, methods", kind: 'slet', title: "Nested records",
    note: "A record inside a record flattens into consecutive cells, so <b>r.max.x</b> is just one <b>CGET</b> at a computed depth and <b>r.max.x = 20</b> one <b>CSET</b>. <b>grow</b> builds a whole nested record and returns its four cells.",
    src: "let vec2 = { x: u32, y: u32 }\nlet rect = { min: vec2, max: vec2 }\n\nlet area(r: rect) : u32 = (r.max.x - r.min.x) * (r.max.y - r.min.y)\nlet grow(r: rect, by: u32) : rect = rect { min = vec2 { x = r.min.x - by, y = r.min.y - by }, max = vec2 { x = r.max.x + by, y = r.max.y + by } }\n\nlet main() : (u32, u32) = do\n  let r = rect { min = vec2 { x = 10, y = 20 }, max = vec2 { x = 14, y = 23 } }\n  let g = grow(r, 1)\n  r.max.x = 20\n  return area(r), area(g)\nend" },
  { id: "counter", group: "SLet: results, records, methods", kind: 'slet', title: "Counter: a method in a loop",
    note: "<b>bump</b> uses compound stores on the receiver's fields. <b>loop</b> passes the counter by value and calls itself in tail position, so the whole thing is a jump loop with the counter's two cells on C.",
    src: "let counter = {\n  value: u32,\n  steps: u32,\n  bump(by: u32) : u32 = do\n    value += by\n    steps += 1\n    return value\n  end,\n}\n\nlet count_to(limit: u32) : (u32, u32) = do\n  let c = counter { value = 0, steps = 0 }\n  let by = 7\n  return loop(c, limit, by)\nend\n\nlet loop(c: counter, limit, by: u32) : (u32, u32) = do\n  if c.value >= limit then return c.value, c.steps end\n  c.bump(by)\n  return loop(c, limit, by)\nend\n\nlet main() : (u32, u32) = count_to(50)" },
  { id: "fibpair", group: "SLet: expressions and loops", kind: 'slet', title: "Iterative fib in u64",
    note: "fib(90) without recursion depth: <b>go</b> carries the pair in its parameters and calls itself in tail position. 64-bit types wrap natively, so there is no normalization.",
    src: "let fib(n: u32) : u64 = go(n, 0, 1)\nlet go(n: u32, a, b: u64) : u64 = if n == 0 then a else go(n - 1, b, a + b)\nlet main() : u64 = fib(90)" },
  { id: 'bank', group: 'Hand-written assembly', kind: 'asm', title: 'Operand bank tour',
    note: 'Watch the registers. A fills the bank from <b>h0</b> up and B from <b>h3</b> down. When the bank is full the two tops are adjacent, so <b>MOVE.AB</b> is free: <b>h1</b> just changes owner. A push onto a full bank spills the pushing stack\'s deepest cell, and <b>COPY</b> always costs a real register copy.',
    src: '; watch the operand bank\nPUSH.A 10       ; A0 in h0\nPUSH.A 20       ; A0 in h1\nPUSH.B 30       ; B0 in h3\nPUSH.B 40       ; B0 in h2: the bank is full\nMOVE.AB         ; tops adjacent: h1 changes owner\nPUSH.A 50       ; full bank: A spills its deepest cell\nCOPY.BA         ; a real copy: one value, two stacks\nADD.A           ; one native add, B pops\nDROP.B\nHALT' },
  { id: 'sum', group: 'Hand-written assembly', kind: 'asm', title: 'Sum loop with operand forms',
    note: 'The counter <b>i</b> and limit <b>n</b> live on C; the running sum stays in <b>h0</b>. <b>ADDC.A 0</b> adds C0 to the sum in place and <b>ADDI.A 1</b> adds an immediate: neither touches B. <b>BLE</b> tests <b>n &lt;= i</b>, which is <b>i &gt;= n</b> with the operands routed.',
    src: '; sum = 0 + 1 + 2 + 3 + 4, with i and n on C\nPUSH.A 0        ; sum\nPUSH.A 5        ; n\nCPUSH.A\nPUSH.A 0        ; i\nCPUSH.A\nloop:\nCGET.A 1        ; n\nCGET.B 0        ; i\nBLE done        ; n <= i: finished\nADDC.A 0        ; sum += i\nCGET.A 0\nADDI.A 1\nCSET.A 0        ; i = i + 1\nJMP loop\ndone:\nHALT' },
  { id: 'fibasm', group: 'Hand-written assembly', kind: 'asm', title: 'Recursive fib(6) with frames',
    note: '<b>CALL.A fib 1</b> moves the argument into the callee\'s frame, so <b>n</b> is <b>C0</b> and there is no prologue. The second call is <b>CALL.B</b>: its result lands on B, ready for <b>ADD.A</b>. <b>RET 1 1</b> drops the one-cell frame and returns one result.',
    src: 'PUSH.A 6\nCALL.A fib 1\nHALT\nfib:                ; frame: C0 = n\nCGET.A 0\nBGEI.A 2 rec        ; n >= 2: recurse\nCGET.A 0\nRET 1 1             ; return n\nrec:\nCGET.A 0\nSUBI.A 1\nCALL.A fib 1        ; A: fib(n-1)\nCGET.A 0\nSUBI.A 2\nCALL.B fib 1        ; B: fib(n-2)\nADD.A\nRET 1 1' },
  { id: 'new-w', group: 'Start from scratch', kind: 'slet', title: 'New SLet program', blank: true,
    note: 'Define words with typed parameters and a <b>main</b>, then choose Run.',
    src: 'let triangle(n: u32) : u32 = n * (n + 1) / 2\n\nlet main() : u32 = triangle(10)' },
  { id: 'new-asm', group: 'Start from scratch', kind: 'asm', title: 'New assembly program', blank: true,
    note: 'Write instructions one per line, with labels and ; comments, then choose Run.', src: 'PUSH.A 6\nPUSH.B 7\nMUL.A\nHALT' },
];

/* ---------------------------------------------------------------- state */
let spec = EXAMPLES[0], P = null, idx = 0;
let view = 'src', bcView = 'asm', fmtMode = 's';
let editing = false, editText = '', editErr = null;
let playing = false, timer = null, speed = 300;
const edits = {};

function build(sp, src) {
  const out = { spec: sp, src, kind: sp.kind, warnings: [] };
  if (sp.kind === 'slet') {
    const c = S.wcompile(src);
    const a = S.assemble(c.asm);
    Object.assign(out, { asm: c.asm, map: c.map, insAsmLine: c.insAsmLine, roots: c.roots, code: a.code, labelAt: a.labelAt });
    out.need = Math.max(1, ...c.roots.map(r => r.e.need || 1));
    out.naiveNeed = Math.max(1, ...c.roots.map(r => S.naiveNeed(r.e)));
    try { out.expected = S.weval(src); } catch (e) { out.expectedAbort = e instanceof S.Abort ? e.code : null; }
    const naive = S.run(S.assemble(S.wcompile(src, { leftFirst: true }).asm).code, 20000);
    out.naiveStats = naive[naive.length - 1].stats;
  } else {
    const a = S.assemble(src);
    Object.assign(out, { code: a.code, labelAt: a.labelAt, warnings: a.warnings });
  }
  out.lay = S.layout(out.code);
  out.snaps = S.run(out.code, 20000);
  const hits = new Array(out.code.length).fill(0);
  out.hitsAt = [hits.slice()];
  for (let i = 1; i < out.snaps.length; i++) { const l = out.snaps[i].last; if (l >= 0) hits[l]++; out.hitsAt.push(hits.slice()); }
  out.labelOf = {};
  for (const [i, names] of Object.entries(out.labelAt || {})) out.labelOf[i] = names[0];
  return out;
}
function load(sp, keepEdit) {
  stop(); spec = sp;
  const src = edits[sp.id] != null ? edits[sp.id] : sp.src;
  try { P = build(sp, src); } catch (e) { delete edits[sp.id]; P = build(sp, sp.src); }
  idx = 0;
  if (!keepEdit) editing = !!sp.blank && edits[sp.id] == null;
  editText = P.src; editErr = null;
  if (P.kind !== 'slet' && view !== 'src') view = 'src';
  $('progSel').value = sp.id;
  render();
}

/* ------------------------------------------------------------- helpers */
const snap = () => P.snaps[idx];
const nextIns = () => { const s = snap(); return s.halted || s.reason ? null : P.code[s.pc]; };
function fv(v) {
  if (fmtMode === 'u') return S.u(v).toString();
  if (fmtMode === 'x') return '0x' + S.u(v).toString(16);
  return S.s(v).toString();
}
function cellText(c) {
  if (c.ret != null) return '↩ ' + (P.labelOf[c.ret] || '#' + c.ret);
  return fv(c.v);
}
function locOf(stack, n) { const s = snap(); const arr = s[stack]; return arr[n] ? arr[n].where : '?'; }
function ref(stack, n) {
  const w = locOf(stack, n);
  return `<span class="r ${stack.toLowerCase()}">${stack}${n}</span><span class="o" style="font-size:.45em">${w === 'mem' ? 'memory' : w}</span>`;
}

/* ---------------------------------------------------------------- render */
function render(anim) {
  renderProgram(); renderMachine(anim); renderCode(); renderTransport();
}

function hlExpr(l) {
  const [code, ...rest] = l.split('--');
  let h = esc(code).replace(/\b(let|do|end|if|then|else|return|and|or|not|true|false)\b/g, '<span class="tk-k">$1</span>')
    .replace(/\b(u32|i32|u64|i64|bool)\b/g, '<span class="tk-b">$1</span>')
    .replace(/\b(\d[\d_]*)\b/g, '<span class="tk-n">$1</span>');
  if (rest.length) h += `<span class="tk-c">--${esc(rest.join('--'))}</span>`;
  return h;
}
function hlAsm(l) {
  const ci = l.indexOf(';');
  const code = ci >= 0 ? l.slice(0, ci) : l, com = ci >= 0 ? l.slice(ci) : '';
  let h = esc(code)
    .replace(/^(\s*[A-Za-z_]\w*:)/, '<span class="tk-l">$1</span>')
    .replace(/\.(AB|BA|A|B)\b/g, (m, x) => `<span class="tk-${x[x.length - 1].toLowerCase()}">.${x}</span>`)
    .replace(/(\s)(-?\d+)(\s*)$/, '$1<span class="tk-n">$2</span>$3');
  return h + (com ? `<span class="tk-c">${esc(com)}</span>` : '');
}

function renderProgram() {
  $('kindTag').textContent = spec.kind === 'slet' ? 'SLet' : 'assembly';
  $('editBtn').textContent = editing ? 'Close editor' : 'Edit';
  [...$('viewSeg').children].forEach(b => {
    b.setAttribute('aria-pressed', String(b.dataset.v === view && !editing));
    b.disabled = editing || (b.dataset.v !== 'src' && P.kind !== 'slet');
  });
  const body = $('progBody');
  const note = `<div class="note">${spec.note}</div>`;
  if (editing) {
    body.innerHTML = `${note}<div class="editor">
      <textarea id="ed" spellcheck="false" aria-label="Program source">${esc(editText)}</textarea>
      ${editErr ? `<div class="err" role="alert">${esc(editErr.message)}</div>` : ''}
      <div class="row"><button class="btn primary" id="runBtn">Run</button><button class="btn" id="cancelBtn">Cancel</button>
      ${edits[spec.id] != null || editText !== spec.src ? '<button class="btn" id="revertBtn">Restore original</button>' : ''}</div>
      <div class="hint">${spec.kind === 'slet' ? 'SLet: words with typed parameters (u32, i32, u64, i64, bool), do ... end blocks, and a main. Comments start with --.' : 'One instruction per line, labels end with a colon, comments start with ;.'} Ctrl+Enter runs.</div></div>`;
    const ed = $('ed');
    ed.addEventListener('input', () => { editText = ed.value; });
    ed.addEventListener('keydown', e => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); applyEdit(); }
      if (e.key === 'Tab') { e.preventDefault(); ed.setRangeText('    ', ed.selectionStart, ed.selectionEnd, 'end'); editText = ed.value; }
    });
    $('runBtn').onclick = applyEdit;
    $('cancelBtn').onclick = () => { editing = false; editErr = null; editText = P.src; render(); };
    const rv = $('revertBtn');
    if (rv) rv.onclick = () => { delete edits[spec.id]; editText = spec.src; editErr = null; load(spec, true); editing = true; render(); };
    return;
  }
  const ins = nextIns(), s = snap();
  const cur = ins ? P.code.indexOf(ins) : s.last;
  const warns = P.warnings.length ? `<div class="warn">${P.warnings.map(w => `<p>${esc(w)}</p>`).join('')}</div>` : '';
  if (view === 'tree' && P.kind === 'slet') { body.innerHTML = note + treeHTML(cur) + warns; return; }
  if (view === 'asm' && P.kind === 'slet') {
    const on = cur >= 0 ? P.insAsmLine[cur] : -1;
    body.innerHTML = note + `<div class="src">${P.asm.split('\n').map((l, i) =>
      `<div class="l${i === on ? ' on' : ''}"><span class="n">${i + 1}</span><span>${hlAsm(l)}</span></div>`).join('')}</div>`;
    return;
  }
  const activeLine = cur >= 0 && P.code[cur] ? (P.kind === 'slet' ? P.map[cur].src : P.code[cur].line) : -1;
  const hl = P.kind === 'slet' ? hlExpr : hlAsm;
  body.innerHTML = note + `<div class="src">${P.src.split('\n').map((l, i) =>
    `<div class="l${i === activeLine ? ' on' : ''}"><span class="n">${i + 1}</span><span>${hl(l) || ' '}</span></div>`).join('')}</div>` + warns;
}

function treeHTML(cur) {
  const active = cur >= 0 && P.map[cur] ? P.map[cur].node : null;
  const SY = { '-': '−', '*': '×', '~': '~', not: 'not' };
  const node = (n, first) => {
    let label, kids = [], firstId = null;
    switch (n.k) {
      case 'num': label = String(n.v); break;
      case 'bool': label = n.v ? 'true' : 'false'; break;
      case 'var': label = n.name; break;
      case 'un': label = SY[n.op] || n.op; kids = [n.x]; break;
      case 'pow': label = '^'; kids = [n.l, n.r]; firstId = n.aFirst ? n.l.id : n.r.id; break;
      case 'bin': {
        label = SY[n.o] || n.o; kids = [n.l, n.r];
        const [a, b] = S.wOperands(n); firstId = n.aFirst ? a.id : b.id; break;
      }
      case 'if': label = 'if'; kids = [n.c, n.t, n.e]; break;
      case 'and': case 'or': label = n.k; kids = [n.l, n.r]; break;
      case 'call': label = n.name + (n.tail ? ' (jump)' : '()'); kids = n.args; break;
      case 'mcall': label = '.' + n.name + '()'; kids = [n.recv, ...n.args]; break;
      case 'field': label = '.' + n.name; kids = [n.base]; break;
      case 'make': label = n.schema + ' { }'; kids = n.inits.map(f => f.e); break;
      case 'adjust': label = '( )'; kids = [n.x]; break;
    }
    const d = n.dst === 'A' ? ' dA' : n.dst === 'B' ? ' dB' : '';
    const showNeed = ['bin', 'pow', 'un', 'call', 'mcall'].includes(n.k) && n.need;
    const title = n.dst === 'branch' ? 'compiled as a compare-and-branch' : n.dst ? `result goes to ${n.dst}` : 'folded at compile time';
    return `<li><span class="tn${d}${active === n.id ? ' on' : ''}" title="${esc(title)}${n.need ? '; Ershov number ' + n.need : ''}">${esc(label)}${showNeed ? `<span class="er">${n.need}</span>` : ''}${first ? '<span class="first">1st</span>' : ''}</span>${kids.length ? `<ul>${kids.map(k => node(k, k.id === firstId)).join('')}</ul>` : ''}</li>`;
  };
  const byWord = {};
  P.roots.forEach(r => (byWord[r.word] = byWord[r.word] || []).push(r));
  const seen = new Set();
  let h = `<div class="legend"><span><i style="background:var(--cold)"></i>result on A</span><span><i style="background:var(--indigo)"></i>result on B</span><span><i style="background:var(--clay-strong)"></i>Ershov number</span><span><i style="background:var(--mint-deep)"></i>evaluated first</span></div><div class="tree">`;
  for (const [word, roots] of Object.entries(byWord)) {
    h += `<div class="lbl" style="margin:10px 4px 0">word ${esc(word)}</div>`;
    for (const r of roots) {
      if (seen.has(r.e.id + ':' + word)) continue; seen.add(r.e.id + ':' + word);
      h += `<div class="stmt"><ul><li><span class="tn st">${esc(r.label)}</span><ul>${node(r.e, false)}</ul></li></ul></div>`;
    }
  }
  return h + '</div>';
}

const SYM = { ADD: '+', SUB: '−', MUL: '×', DIVU: '÷u', DIVS: '÷', REMU: '%u', REMS: '%', AND: '&', OR: '|', XOR: '^', SHL: '<<', SHR: '>>u', SAR: '>>', EQ: '=', NE: '≠', LT: '<', LE: '≤', LTU: '<u', LEU: '≤u' };
function hero(ins) {
  const s = snap();
  const val = (st, n) => (s[st][n] ? cellText(s[st][n]) : '?');
  const dst = x => `<span class="o">→</span><span class="r ${x.toLowerCase()}">${x}</span>`;
  switch (ins.op) {
    case 'BIN': return [`${ref('A', 0)}<span class="o">${SYM[ins.fn]}</span>${ref('B', 0)}${dst(ins.x)}<span class="f">${esc(val('A', 0))} ${SYM[ins.fn]} ${esc(val('B', 0))}</span>`,
      `A0 ${SYM[ins.fn]} B0, result on ${ins.x}; ${ins.x === 'A' ? 'B' : 'A'} pops. One native operation, no data movement.`];
    case 'UN': return [`<span class="o">${ins.fn}</span>${ref(ins.x, 0)}`, `${ins.fn} of ${ins.x}0, in place.`];
    case 'ONE': return [`<span class="o">${ins.fn}</span>${ref('A', 0)}${ins.fn.startsWith('POW') ? ref('B', 0) : ''}`, ins.fn.startsWith('CHK') ? 'Abort (reason 3) if A0 does not fit; otherwise nothing changes.' : 'An A-only operation.'];
    case 'PUSH': return [`<span class="o">push</span><span class="r ${ins.x.toLowerCase()}">${esc(fv(ins.v))}</span>${dst(ins.x)}`, `Writes the next free register of ${ins.x} (PUSH${ins.width}, ${S.insLen(ins)} bytes).`];
    case 'DUP': return [`<span class="o">dup</span>${ref(ins.x, 0)}`, `A real copy: the value gains a second live position on ${ins.x}.`];
    case 'DROP': return [`<span class="o">drop</span>${ref(ins.x, 0)}`, 'No native work: the register just stops belonging to the stack.'];
    case 'COPY': return [`<span class="o">copy</span>${ref(ins.x[0], 0)}${dst(ins.x[1])}`, 'COPY creates liveness: always one real register copy.'];
    case 'MOVE': return [`<span class="o">move</span>${ref(ins.x[0], 0)}${dst(ins.x[1])}`, 'MOVE changes ownership: free when the bank is full, one register copy otherwise.'];
    case 'CPUSH': return [`<span class="o">cpush</span>${ref(ins.x, 0)}${dst('C')}`, `Moves ${ins.x}0 onto C.`];
    case 'CPOP': return [`<span class="o">cpop</span>${ref('C', 0)}`, 'No native work.'];
    case 'CGET': return [`<span class="o">cget</span>${ref('C', ins.n)}${dst(ins.x)}`, `Copies C${ins.n} to ${ins.x}${locOf('C', ins.n) === 'mem' ? ', reading it in place from memory' : ''}.`];
    case 'CSET': return [`${ref(ins.x, 0)}<span class="o">into</span><span class="r c">C${ins.n}</span>`, `Writes ${ins.x}0 into C${ins.n} and consumes it.`];
    case 'CB': return [`<span class="o">if</span>${ref('A', 0)}<span class="o">${ins.fn.slice(1).toLowerCase()}</span>${ref('B', 0)}<span class="f">jump to ${esc(ins.label)}</span>`, 'Compare-and-branch: consumes both tops.'];
    case 'JZ': case 'JNZ': return [`<span class="o">${ins.op === 'JZ' ? 'if zero' : 'if not zero'}</span>${ref(ins.x, 0)}<span class="f">${esc(ins.label)}</span>`, `Tests ${ins.x}0 and consumes it.`];
    case 'JMP': return [`<span class="o">jump</span><span class="f">${esc(ins.label)}</span>`, 'Unconditional jump.'];
    case 'CALL': return [`<span class="o">call</span><span class="f">${esc(ins.label)}, ${ins.n} argument${ins.n === 1 ? '' : 's'}</span><span class="o">→</span><span class="r ${ins.x.toLowerCase()}">${ins.x}</span>`,
      `Pushes the return address (recording ${ins.x} as the result stack), moves ${ins.n} argument cell${ins.n === 1 ? '' : 's'} from A into the new frame, and jumps.`];
    case 'TCALL': return [`<span class="o">tail call</span><span class="f">${esc(ins.label)}, drop ${ins.k}, take ${ins.n}</span>`, 'Replaces the frame and jumps, keeping the return address and the stack it records.'];
    case 'RET': return [`<span class="o">return</span><span class="f">drop ${ins.k}, ${ins.r} result${ins.r === 1 ? '' : 's'}</span>`, 'Drops the frame, pops the return address and jumps; moves the results to B if the call asked for that.'];
    case 'BINI': return [`${ref(ins.x, 0)}<span class="o">${SYM[ins.fn]}</span><span class="r ${ins.x.toLowerCase()}">${esc(fv(ins.v))}</span>`, `Operand form: ${ins.x}0 ${SYM[ins.fn]} an immediate, in place. The other stack is untouched.`];
    case 'BINC': return [`${ref(ins.x, 0)}<span class="o">${SYM[ins.fn]}</span>${ref('C', ins.n)}`, `Operand form: ${ins.x}0 ${SYM[ins.fn]} C${ins.n}, in place. C is only read.`];
    case 'CBI': return [`<span class="o">if</span>${ref(ins.x, 0)}<span class="o">${ins.fn.slice(1, -1).toLowerCase()}</span><span class="r ${ins.x.toLowerCase()}">${esc(fv(ins.v))}</span><span class="f">jump to ${esc(ins.label)}</span>`, 'Compare-and-branch against an immediate: consumes A0.'];
    case 'ABORT': return [`<span class="o">abort</span><span class="f">reason ${ins.n}</span>`, 'Stops with a reason code.'];
    case 'HALT': return [`<span class="o">halt</span>`, 'Flushes the banks to memory and stops.'];
  }
  return ['', ''];
}

function renderMachine(anim) {
  const s = snap(), ins = nextIns();
  $('nextLbl').textContent = s.halted ? 'Finished' : s.reason ? 'Stopped' : 'Next instruction';
  if (ins) { const [e, m] = hero(ins); $('eq').innerHTML = e; $('mean').innerHTML = m; }
  else if (s.reason) {
    $('eq').innerHTML = `<span class="o">Abort</span><span class="r a">${s.reason}</span>`;
    $('mean').innerHTML = esc(S.REASONS[s.reason] || 'stopped');
  } else {
    const top = s.A[0];
    $('eq').innerHTML = `Halted${top ? `<span class="o">with</span><span class="r a">A0 = ${esc(cellText(top))}</span>` : ''}`;
    let m = 'Step back or reset to replay.';
    if (P.kind === 'slet') {
      if (P.expectedAbort) m = `The source program aborts with reason ${P.expectedAbort}.`;
      else if (P.expected) {
        const got = s.A.slice().reverse().map(c => c.v);
        const same = got.length === P.expected.length && got.every((v, i) => v === P.expected[i]);
        const show = P.expected.map(v => fv(v)).join(', ');
        m = same ? `main returns ${esc(show)} when the source is run directly, and A matches.` : `Running the source directly gives ${esc(show)}, but A holds ${esc(got.map(fv).join(', '))}.`;
      }
    }
    $('mean').innerHTML = m;
  }
  const last = $('last');
  last.className = 'last' + (s.error ? ' bad' : '');
  last.innerHTML = idx === 0 ? esc(s.msg) : `<b>Step ${idx}.</b> ${esc(s.msg)}`;
  const nat = $('native');
  nat.innerHTML = `<div class="lbl">Native work in that step</div>` + (s.L && s.L.length
    ? `<ol>${s.L.map(l => `<li class="${/no native move/.test(l) ? 'free' : /^spill/.test(l) ? 'spill' : ''}">${esc(l)}</li>`).join('')}</ol>`
    : '<div style="font-size:11px;color:var(--muted);margin-top:4px">none yet</div>');
  const touched = new Set();
  (anim && s.L ? s.L : []).forEach(l => { const m = /^([hc]\d)\b/.exec(l); if (m) touched.add(m[1]); });

  /* registers */
  $('abState').textContent = `a = ${s.a}, b = ${s.b}`;
  $('kState').textContent = `k = ${s.k}`;
  $('hregs').innerHTML = s.owners.map((o, i) => {
    let lab = 'free', top = false;
    if (o === 'A') { const d = s.a - 1 - i; lab = 'A' + d; top = d === 0; }
    if (o === 'B') { const d = i - (S.NBANK - s.b); lab = 'B' + d; top = d === 0; }
    const v = s.h[i];
    return `<div class="reg ${o}${top ? ' istop' : ''}${touched.has('h' + i) ? ' touched' : ''}" title="h${i}${v ? ' = ' + esc(cellText(v)) : ': free'}"><div class="rn">h${i}</div><div class="rv">${v ? esc(cellText(v)) : '·'}</div><div class="ro">${lab}</div></div>`;
  }).join('');
  $('cregs').innerHTML = [0, 1, 2, 3].map(i => {
    const own = i < s.k, d = s.k - 1 - i, v = s.c[i];
    return `<div class="reg ${own ? 'C' : 'free'}${own && d === 0 ? ' istop' : ''}${touched.has('c' + i) ? ' touched' : ''}" title="c${i}${own && v ? ' = ' + esc(cellText(v)) : ': free'}"><div class="rn">c${i}</div><div class="rv">${own && v ? esc(cellText(v)) : '·'}</div><div class="ro">${own ? 'C' + d : 'free'}</div></div>`;
  }).join('');

  /* stacks */
  const ops = operandRefs(ins);
  for (const X of ['A', 'B', 'C']) {
    const el = $('cells' + X), arr = s[X];
    if (!arr.length) { el.innerHTML = '<li class="empty">empty</li>'; continue; }
    el.innerHTML = arr.map((c, n) => {
      const reg = c.where !== 'mem';
      const cls = ['cell', reg ? 'reg-' + X : 'mem', ops.has(X + n) ? 'op' : ''].join(' ');
      return `<li class="${cls}" title="${X}${n} = ${esc(cellText(c))}, ${reg ? 'in register ' + c.where : 'in memory'}"><span class="dp">${X}${n}</span><span class="v">${esc(cellText(c))}</span><span class="w">${reg ? c.where : 'mem'}</span></li>`;
    }).join('');
  }
  const st = s.stats;
  const items = [[st.steps, 'Instructions'], [st.regMoves, 'Register copies'], [st.freeMoves, 'Free moves'], [st.spills, 'Spills'],
    [st.memReads, 'Memory reads'], [st.memWrites, 'Memory writes'], [`${st.maxA}/${st.maxB}/${st.maxC}`, 'Max depth A/B/C']];
  $('stats').innerHTML = items.map(([n, k]) => `<div class="stat"><b>${n}</b><span>${k}</span></div>`).join('');
}
function operandRefs(ins) {
  const r = new Set();
  if (!ins) return r;
  switch (ins.op) {
    case 'BIN': case 'CB': r.add('A0'); r.add('B0'); break;
    case 'ONE': r.add('A0'); if (ins.fn.startsWith('POW')) r.add('B0'); break;
    case 'UN': case 'DUP': case 'DROP': case 'CPUSH': case 'JZ': case 'JNZ': case 'BINI': case 'CBI': r.add(ins.x + '0'); break;
    case 'BINC': r.add(ins.x + '0'); r.add('C' + ins.n); break;
    case 'COPY': case 'MOVE': r.add(ins.x[0] + '0'); break;
    case 'CGET': r.add('C' + ins.n); break;
    case 'CSET': r.add(ins.x + '0'); r.add('C' + ins.n); break;
    case 'CPOP': case 'RET': r.add('C0'); break;
  }
  return r;
}

function renderCode() {
  const s = snap();
  $('sizeTag').textContent = `${P.code.length} instructions, ${P.lay.size} bytes`;
  [...$('bcSeg').children].forEach(b => b.setAttribute('aria-pressed', String(b.dataset.v === bcView)));
  const hits = P.hitsAt[idx], cur = s.halted || s.reason ? -1 : s.pc;
  let h = '';
  P.code.forEach((ins, i) => {
    if (P.labelAt && P.labelAt[i]) h += P.labelAt[i].map(l => `<li class="lab" aria-hidden="true">${esc(l)}:</li>`).join('');
    const txt = bcView === 'asm' ? esc(S.fmt(ins)) : `${esc(S.specName(ins))}<small>${S.insLen(ins)} byte${S.insLen(ins) > 1 ? 's' : ''}</small>`;
    h += `<li class="row${i === cur ? ' cur' : ''}"><span class="a">${P.lay.addr[i].toString(16).padStart(2, '0')}</span><span class="t">${txt}</span><span class="hits" title="times executed so far">${hits[i] ? '×' + hits[i] : ''}</span></li>`;
  });
  $('bc').innerHTML = h;
  const c = $('bc').querySelector('.row.cur');
  if (c) { const pb = c.closest('.pbody'); if (pb && pb.scrollHeight > pb.clientHeight + 1) { const er = c.getBoundingClientRect(), cr = pb.getBoundingClientRect(); if (er.top < cr.top) pb.scrollTop -= cr.top - er.top + 8; else if (er.bottom > cr.bottom) pb.scrollTop += er.bottom - cr.bottom + 8; } }
  const fin = P.snaps[P.snaps.length - 1].stats;
  if (P.kind === 'slet') {
    const n = P.naiveStats;
    $('info').innerHTML = `<div class="box"><h4>compile(E, dst) and evaluation order</h4>
      <div class="kv"><span>Result of main, from the source</span><b>${P.expectedAbort ? 'abort ' + P.expectedAbort : P.expected ? esc(P.expected.map(fv).join(', ')) : '?'}</b></div>
      <div class="kv"><span>Combined A + B depth, heavier operand first</span><b>${P.need}</b></div>
      <div class="kv"><span>Combined depth, plain left to right</span><b>${P.naiveNeed}</b></div>
      <div class="kv"><span>Spills: chosen order / left to right</span><b>${fin.spills} / ${n.spills}</b></div>
      <div class="kv"><span>Register copies: chosen / left to right</span><b>${fin.regMoves} / ${n.regMoves}</b></div>
      <div style="margin-top:6px">The bank holds four values, so a combined depth above 4 spills to memory.</div></div>`;
  } else {
    $('info').innerHTML = `<div class="box"><h4>Run summary</h4>
      <div class="kv"><span>Instructions executed</span><b>${fin.steps}</b></div>
      <div class="kv"><span>Free moves (ownership only)</span><b>${fin.freeMoves}</b></div>
      <div class="kv"><span>Register copies</span><b>${fin.regMoves}</b></div>
      <div class="kv"><span>Spills to memory</span><b>${fin.spills}</b></div></div>`;
  }
}

function renderTransport() {
  const max = P.snaps.length - 1, s = snap();
  $('scrub').max = max; $('scrub').value = idx;
  $('stepOut').textContent = `Step ${idx} of ${max}`;
  $('backBtn').disabled = idx === 0;
  $('stepBtn').disabled = idx >= max;
  $('stepBtn').textContent = idx >= max ? (s.reason ? 'Stopped' : 'Done') : 'Step';
  $('playBtn').innerHTML = playing ? '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4 3h3v10H4zM9 3h3v10H9z"/></svg>' : '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M5 3l8 5-8 5z"/></svg>';
  $('playBtn').setAttribute('aria-label', playing ? 'Pause' : 'Play');
}

/* ------------------------------------------------------------- controls */
function go(i, anim) {
  const n = Math.max(0, Math.min(P.snaps.length - 1, i));
  if (n === idx) return;
  const fwd = n === idx + 1;
  idx = n; render(anim && fwd);
}
function step() { go(idx + 1, true); }
function back() { stop(); go(idx - 1, false); }
function play() {
  if (playing) return stop();
  if (idx >= P.snaps.length - 1) { idx = 0; render(); }
  playing = true; renderTransport();
  const tick = () => { if (!playing) return; if (idx >= P.snaps.length - 1) return stop(); go(idx + 1, speed > 150); timer = setTimeout(tick, speed); };
  timer = setTimeout(tick, 60);
}
function stop() { playing = false; clearTimeout(timer); if (P) renderTransport(); }
function applyEdit() {
  try { const b = build(spec, editText); edits[spec.id] = editText; P = b; idx = 0; editing = false; editErr = null; render(); }
  catch (e) { editErr = { message: e.message, line: e.line }; renderProgram(); }
}

function populate() {
  const groups = {};
  EXAMPLES.forEach(e => (groups[e.group] = groups[e.group] || []).push(e));
  $('progSel').innerHTML = Object.entries(groups).map(([g, l]) => `<optgroup label="${esc(g)}">${l.map(e => `<option value="${e.id}">${esc(e.title)}</option>`).join('')}</optgroup>`).join('');
}
function segWire(id, fn) {
  $(id).addEventListener('click', e => {
    const b = e.target.closest('button'); if (!b || b.disabled) return;
    [...$(id).children].forEach(x => x.setAttribute('aria-pressed', String(x === b)));
    fn(b);
  });
}
function wire() {
  $('progSel').addEventListener('change', e => load(EXAMPLES.find(x => x.id === e.target.value)));
  segWire('viewSeg', b => { view = b.dataset.v; renderProgram(); });
  segWire('bcSeg', b => { bcView = b.dataset.v; renderCode(); });
  segWire('speedSeg', b => { speed = Number(b.dataset.s); });
  segWire('fmtSeg', b => { fmtMode = b.dataset.f; render(); });
  $('editBtn').onclick = () => { editing = !editing; editErr = null; editText = P.src; stop(); render(); };
  $('stepBtn').onclick = () => { stop(); step(); };
  $('backBtn').onclick = back;
  $('playBtn').onclick = play;
  $('resetBtn').onclick = () => { stop(); idx = 0; render(); };
  $('scrub').addEventListener('input', e => { stop(); go(Number(e.target.value), false); });
  $('helpBtn').onclick = () => $('help').showModal();
  $('helpClose').onclick = () => $('help').close();
  $('help').addEventListener('click', e => { if (e.target === $('help')) $('help').close(); });
  document.addEventListener('keydown', e => {
    const t = e.target;
    if ((t && t.closest && t.closest('textarea, input, select')) || $('help').open || e.ctrlKey || e.metaKey || e.altKey) return;
    if (e.key === 'ArrowRight') { e.preventDefault(); stop(); step(); }
    else if (e.key === 'ArrowLeft') { e.preventDefault(); back(); }
    else if (e.key === ' ') { e.preventDefault(); play(); }
    else if (e.key === 'r' || e.key === 'R') { stop(); idx = 0; render(); }
    else if (e.key === 'Home') { stop(); go(0, false); }
    else if (e.key === 'End') { stop(); go(P.snaps.length - 1, false); }
  });
}
populate(); wire(); load(EXAMPLES[0]);
})();
