# Receiver scopes and binding-resolved captures

## Status

Implemented and qualified within the frontend's admitted typed interfaces. This is
not whole-Q11 completion, owned/escaping closure support, or dynamic `.let` execution.
Packed tagged-value work remains paused and separate. Nothing in this batch was pushed.

The authoritative rule is: **resolve the selected binding first; capture that binding,
not names that happen to occur in syntax.**

## Receiver contract

- Actual members win. Bad selected signatures/noncallable fields never fall back.
- A lexical receiver supplied to `ref(T)` borrows an addressable `T` place using the
  existing reference/place model; compatible references pass unchanged. `T` receives
  an ordinary value copy. Other argument positions still require explicit references.
- Record/ref-record vocabulary opening retains an innermost lexical receiver as well
  as ordinary field snapshots. Local callables stay ordinary; namespace qualification
  and `(function_value)(args)` bypass insertion. There is no signature-based retry.
- A reference context retains its actual referent. A by-value parameter context still
  concerns that parameter's copy. Opening does not authorize borrowed closures to escape.
- Module/sum expansion remains definition-only. Dynamic receivers keep member routing.

## Implementation

`frontend/let/semantic.lua` separates noncapturing visibility/interface queries from
selected binding lookup. Definition-site lexical environments are pinned when a word
is formed. Selected outer runtime bindings travel through intervening lexical frames;
compile-time definitions retain identity without a runtime namespace or environment.
The implicit receiver is another such binding. Direct and callable-held uses of the
same holding share capture transport.

`frontend/let/source_state.lua` retains ordered capture streams and finite word
completion dependencies. Recursive references can observe capture requirements that
are discovered later in the enclosing body. After all participating bodies finish,
completion closes the component before publishing its consumers, in stable dependency
order. Hidden parameter prefixes, direct/deferred call arguments and view/adapter
layouts finish consistently. Callable identities are reserved before layout completion.

`frontend/let/demand.lua` treats unfinished transport as unavailable knowledge; a
required query reports `static-cycle` rather than executing incomplete IR. Semantic
publication also rejects unfinished transport. No IR schema, ABC ABI, continuation,
runtime allocator, collector or ownership permission changed.

The old `frontend/let/resolve.lua` syntactic capture pass and the prototype's bare-call
receiver heuristic were removed, not retained underneath a new facade. Syntax tests
now assert actual semantic capture results. Bodies elaborate once; there is no source
replay/evaluator or runtime name search. Noninterned ordinary IR occurrences finish
before checking/execution; pure expressions and their value identities are unchanged.

Place-interface discovery does not execute an index. Its existing place expression
is realized once by the selected consumer. Receiver argument preparation then joins
the ordinary application, pending-saturation, defer and borrow machinery.

## Validation

`frontend/tests/receiver_scopes.lua` is integrated into Makefile validation:
**323 checks / 304 executions**, interpreted/threaded/eager/lazy, optimized and
unoptimized. Coverage includes:

- reference mutation versus value copies, compatible references and explicit arguments;
- temporary and local-borrow return rejection;
- reference callbacks, field snapshots, local callables and innermost scopes;
- namespace qualification, import-spread opt-in and function-value bypass;
- member priority and selected-signature/noncallable failure without fallback;
- one-time receiver/index evaluation and argument effect order;
- lexical captured dot calls versus actual-member noncaptures;
- shared capture holdings and scope-local receiver replacement without outer captures;
- early recursive calls with later-discovered captures, nested recursive transport,
  reference snapshots, deferred recursive calls and deferred receiver effects;
- late ownership rejection and finite recursive completion dependencies;
- dynamic member routing structurally, without claiming dynamic runtime lowering.

Two fixtures use the existing managed frontend admission for *local*, nonescaping
callable environments, then execute their entirely typed IR through the ordinary
SLet backend. They test late capture completion for views and partial adapters, not
new owned-closure admission or `.let` runtime execution.

The tested lifted `p.nudge(2)` has **identical ABC assembly** to explicit
`nudge(ref(p), 2)`. This is structural evidence, not a timing measurement.

Evidence:

- `qualification.log`: complete receiver suite.
- `full-validation.log`: full `make ... validate` passes, including the receiver suite,
  source demands, staging sessions, capacity, continuations and all four runtime modes.
- `isolation.log`: current frontend with only `abc.lua` restored from `9cfd7f65`;
  receiver, vocabulary, word, chain, demand and lambda suites pass. Runtime is shared
  with the current rebuilt tree; this is lowering isolation, not a clean baseline build.
- `regression.log`: earlier passing vocabulary/compiler/word/chain/lambda regressions.
- `capture-probe.log`: all three focused capture controls now accept and return 42.

Full validation command:

```sh
make -j4 LUA=/tmp/lua-compat CC=/tmp/clang20 \
  WARN='-std=c11 -Wall -Wextra -Wpedantic -Werror -Wno-newline-eof' validate
```

## Preserved failure evidence

`before-resolved-captures.log` records the prototype passing 193 pre-import checks /
184 executions, then failing import-spread `41.inc()` with `unknown-name`.
`capture-before.log` records failure of nested lexical `40.addition()` while the
ordinary `addition(40)` and genuine-member `r.addition()` controls already passed.

Adding every dotted spelling as a capture would have broken the genuine-member
control, potentially retaining an unrelated environment or rejecting a capture-free
word. Copying parent-frame IR bindings into a child would instead use the wrong frame.
Neither workaround was used.

## Limits

No clean/sanitizer or timing qualification is claimed. Against `9cfd7f65`, the four
changed frontend implementation files (`semantic.lua`, `source_state.lua`, `demand.lua`
and removed `resolve.lua`) grow by a net 144 lines, excluding tests/docs and the unrelated
packed `abc.lua` edits. Capture completion adds metadata/finalization code while removing
the syntactic traversal; passing execution tests is not a compile-time performance claim.

Typed frozen/readonly-place enforcement and discarded-copy-write effect analysis remain
outstanding. Borrowing uses the existing place/reference checks, not a new writability
proof. Broader interface propagation (including collection element method interfaces),
generic qualification, source-demand completion and owned/escaping closures remain
separate work. Q11 stays unchecked. These limits must not be hidden by the successful
capture migration or by the unrelated packed-lowering work still in the working copy.
