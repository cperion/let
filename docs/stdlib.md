# Let standard-library target

**Status: target API reference, not a bundled implementation inventory.** The current
checkout does not contain the `stdlib/README.md` previously cited by syntax.md.
This document replaces that dangling reference. Target APIs below depend on the
unimplemented ownership, container, dynamic and task contracts. Existing typed VM
validation does not establish standard-library support.

[syntax.md](syntax.md) owns source forms; [ownership](owners-references-ids.md) owns
value/lifetime semantics; [tasks](tasks.md) owns concurrency. This document owns the
module/API inventory and records incomplete signatures explicitly. Worklist F/L/T/U
tracks delivery; do not create dummy modules merely to match this list.

## 1. Namespace and exposure

`use std.text` binds namespace `text`. `use ...std.text` additionally introduces its
exports with the spread no-shadow rule, while retaining qualified access. Neither
form automatically re-exports names. `std.*` is reserved for bundled modules; an
unknown standard module rejects rather than loading an arbitrary working-directory
file. The target has `.let` source only.

Predefined constructors and value operations are distinct from imported module
exports. `store`, `list`, `id`, `table`, `frozen`, `freeze`, `is`, `fmt`, `has`, `remove`
and `count` are documented predefined names; this does not make them keywords or
require their algorithms to be compiler intrinsics. `count` is part of the proposed
table vocabulary, but its exact domain/signature still needs finalization (see §8).
The same applies to complete exports of the older resource modules.

`fmt` retains its documented predefined call spelling. Under
[lexical receiver-call sugar](application-sugar.md), `"{}".fmt(n)` calls that same
word when no string member named `fmt` exists; no separate builtin formatting method
is needed. Members always win over lexical names, including store `remove`/`has`.
Plain `use std.text` enables qualified text calls; `use ...std.text` brings its free
words into scope for fluent spelling on closed interfaces lacking those members.
Table/any member calls never use a runtime lexical fallback. The implementation map's
`std/fmt.let` and `std/pattern.let` are proposed implementation files, **not approval
of public `std.fmt`/`std.pattern` modules or additional implicit imports**. Formatting
and pattern operations are described below; settle their full export placement
before implementing those files. Do not expose conflicting spellings accidentally.

## 2. Public module inventory

| Target module | Established responsibility/API names | Specification status |
| --- | --- | --- |
| `std.bytes` | Shared byte read/write protocols for checked scoped resources | Protocol purpose fixed; complete method signatures/error alternatives pending |
| `std.memory` | `with_buffer`, checked scoped byte access; `result(r)` for fallible operations | Lifetime/normal-cleanup contract fixed; size/alignment/method/error signatures pending |
| `std.text` | Byte-string search, transformation, parsing and formatting/pattern library surface below | Operation semantics partly specified; exact exports/overloads and listed edge cases pending |
| `std.stream` | Shared scoped stream protocols | Complete method/result signatures pending |
| `std.file` | `with_file`, private descriptor lifetime and `result(r)` | Cleanup precedence fixed; open modes, operations and result alternatives pending |
| `std.terminal` | `with_terminal`, private terminal-token lifetime and `result(r)` | Cleanup precedence fixed; terminal operations/result alternatives pending |
| `std.program` | Program startup, scoped argument/string readers and host integration | Complete API/signatures pending; emission flags are not source words |
| `std.task` | `scope`, `yield`, `select`, `on_after`, channel/handle/result types; group/channel/handle methods | Source contract specified in §7 and tasks.md; concrete ABI/remaining API details identified there |

There is no approved public `std.store`, `std.list`, mutex module or atomic-reference
module. Containers use predefined type constructors and their methods. Standard
library source executes through the ordinary frontend/ABC path; privileged byte,
allocation, I/O and scheduler operations bind explicit runtime contracts.

## 3. Stores and ids: predefined types

`store(T) {}` creates an empty independent-slot store; `id(T)` is a non-owning
position/generation link. Copies duplicate slot state and values, not addresses.

| Expression | Result/meaning |
| --- | --- |
| `s.add(v)` | Store value copy; return its id; allocation possible |
| `s.try_add(v)` | No-allocation `added(id)` or `full` |
| `s.reserve(n)` | Reserve capacity for n further additions |
| `s[i]` | Checked read/copy or writable slot; `i` is an id |
| `s.remove(i)` | Drop live element and vacate slot |
| `s.has(i)` | Bool validity test without aborting |
| `s.length` | Occupied count, not maximum valid slot position |
| `s.each(body)` | Visit live ids in storage order |

Lookup checks slot extent, occupancy and generation. Foreign-store ids are not
security capabilities; matching slot/generation can succeed. Generation wraps after
2^32 fills. Slot references are temporary borrows; growth preserves them, invalidating
removal/replacement requires proof. Callback mutation behavior and exact method
result signatures not fixed above remain library completion work, not implicit safe
iteration guarantees.

## 4. Lists, strings and snapshots

`list(T) {}` is a COW growable value sequence. `l[i]` copies/updates a value; it is
not a stable addressable element. `ref(l[i])` rejects. Local instance aliases differ
from value copies across parameters, returns and field stores.

| List member | Contract |
| --- | --- |
| `length` | Element count |
| `push(v)` / `try_push(v)` | Append / nonallocating `done` or `full` |
| `pop()` | Remove and return last element; empty bounds-aborts |
| `insert(i,v)` / `remove_at(i)` | Ordered insertion/removal with shifting |
| `append(view)` | Append values from slice |
| `reserve(n)` | Capacity for n further appends; future sharing can still require detach |
| `view()` | Read-only snapshot retaining immutable buffer storage |
| `each(body)` | Positions/values in order; callback/mutation details need completion |

`try_push` returns `full` rather than allocating to detach shared storage. Element
method copy-out under reentrant mutation is unresolved and must be specified before
accepting such calls; do not invoke a method on a stale element address.

A string is a COW byte value, not `slice(u8)`. No Unicode normalization or implicit
numeric formatting is imposed. Literal buffers are immortal; substrings share storage.

| String member/conversion | Contract |
| --- | --- |
| `length`, `s[i]` | Byte count and checked byte read/store |
| `append(t)`, `push(b)` | Grow by string/byte, detaching when required |
| `sub(a,b)` | Shared substring over [a,b) |
| `compact()` | Explicit copy retaining only selected bytes |
| `view()` | Immutable snapshot `slice(u8)` |
| `string(view)` | Copy byte view into a string |

`ref(s[i])` rejects. Readonly views of **mutable** arrays are not immutable snapshots
and are not automatically transferable. `..` concatenates strings or same-element
lists; `..=` derives a compound store. No numeric coercion or spread/reduction into
`..` is implied.

## 5. Text, formatting and patterns

These are the approved operation vocabulary and semantics, not yet a complete export
signature set. Receiver-style versus namespace-style spellings must be finalized in
one L01 contract; examples in proposals are not authorization to expose both silently.

| Operation names | Contract |
| --- | --- |
| `sub`, `prefix`, `suffix` | Shared substrings |
| `find`, `find_from` | `found(u32)` or `missing` |
| `contains`, `starts_with`, `ends_with` | Bool byte tests |
| `split` | List of shared substrings; empty-separator policy pending |
| `join`, `repeat` | Construct resulting string |
| `replace`, `reverse` | Construct resulting byte string |
| `upper`, `lower` | ASCII case conversion; other bytes unchanged |
| `trim`, `trim_start`, `trim_end` | ASCII whitespace removal via substring |
| `compare` | Bytewise `less`, `equal`, `greater`; no builtin string `<` |
| `hash` | u64 content hash consistent with table key equality; algorithm/stability pending |
| `each` | Positions and bytes |
| `parse(t,s)` | `parsed(T)` or `invalid`, for integer types/f64; detailed parsing grammar pending |

`fmt(format, ...args)` produces a string. Supported placeholder vocabulary is `{}`,
`{x}`, `{N}`, `{N x}` with escaped `{{`/`}}`. Literal format checking uses normal
static specialization; runtime formats use checked runtime behavior and
`format-mismatch`. Complete index base, auto/explicit mixing, accepted kinds and
numeric formatting rules remain L01/L03 specification work. Static-shape packs do
not automatically make a runtime format string static.

Patterns use Lua-style **byte** syntax: classes/complements, ranges, `* + - ?`, anchors,
`%b`, `%f`, substring and position captures. Operation vocabulary: `match`,
`find_pattern`, `each_match`, `replace_pattern`; replacement strings use `%0`…`%9`.
Malformed runtime patterns abort `bad-pattern`; literals specialize. Backtracking
is allowed, so no linear-time claim. Position-capture sum/type, empty-match progress,
replacement callback rules and resource handling must be settled before implementation.

## 6. Tables and frozen/dynamic values

`table {}` creates an ordered COW value map. `w.name` addresses a named string key;
`w[k]` accepts string/integer/bool keys. Values are transferable `any`. Missing reads
abort; `has(w,k)` tests presence and `remove(w,k)` removes. There is no nil, escaped
entry ref or shared mutable identity across copies.

Dense integer keys start at zero. `length` is the exact consecutive run, not total
map occupancy. `push`, `pop`, `insert`, `remove_at` act on that dense portion;
`view()` snapshots it; `each` visits dense entries then other keys in insertion order.
Map removal creates a gap rather than shifting. Builtin-member versus user-key
collisions and insertion history during dense/map migration remain explicit gates.

`freeze(v)` copies or safely moves into immutable counted storage; it never invalidates
surviving mutable aliases. `frozen(T)` access is immutable. `any` holds only transferable
values and immutable boxes, not raw pointers, mutable-backed views or group capabilities.
`is(x,t)` and checked conversions preserve ordinary scalar rules.

## 7. Task API: ordinary words, no async syntax

Import with `use std.task` (qualified `task`) or import-and-spread. Groups/channels/
handles are scoped capabilities, not unrestricted transferable values.

| Word/member | Result/behavior |
| --- | --- |
| `task.scope(r, body)` | Run `body(g)` and return its r result after all children finish |
| `g.spawn(work)` | Start nullary work; return group-bound handle |
| `h.join()` | Wait and copy work's result vector; repeated joins supported |
| `g.channel(t, capacity)` | Explicit group-owned channel; zero means rendezvous |
| `ch.send(v)` | `sent` or `closed` |
| `ch.receive()` | `item(v)` or closed-and-drained `closed` |
| `ch.close()` | Idempotent, stop sends, preserve queued drain |
| `g.cancel()` / `g.cancelled()` | Mark/close descendants / query bool |
| `task.yield()` | Explicit cooperative scheduling point |
| `task.select { label = case, ... }` | One committed case, one handler in selecting task |
| `ch.on_receive(handler)` | Handler receives receive result |
| `ch.on_send(v, handler)` | Handler receives send result |
| `task.on_after(ns, handler)` | Monotonic timer case; handler receives unit |

Library result types: `sent_or_closed = oneof { sent: unit, closed: unit }` and
`received(t) = oneof { item: t, closed: unit }`; channel type `task.chan(t)`.
Concrete result-vector `task.handle(...)` type construction, time representation/
limits, empty select and scope multi-result extension remain tasks.md API gates.
No ambient `task.channel`, old `with_tasks`, detached spawn, public mutex or automatic
forceful cancellation is specified. Cancellation is not a guaranteed completion
deadline. Other tasks cannot read or write mutable module storage.

```let
use std.task

let total(): u64 = task.scope(u64) do |g|
  let a = g.spawn() do return sum_range(0, 500) end
  let b = g.spawn() do return sum_range(500, 1000) end
  return a.join() + b.join()
end
```

This uses approved trailing-block sugar and is not a runnable current example.

## 8. Resource modules and specification completion gates

`with_buffer`, `with_file` and `with_terminal` lend checked views backed by private
resources. Views cannot escape their scope. Normal completion performs cleanup;
abort does not unwind. File-close/terminal-restore failure supersedes the body's
result. Raw `ptr` combinators do not acquire these guarantees merely by using a
trailing block. Byte/stream interfaces and result sums must preserve borrow origins.

Before calling the library reference complete, specify:

1. Exact `std.bytes`/`stream` method signatures and fallible alternatives.
2. `with_buffer` size/alignment, file open modes, terminal operations, all resource
   callback signatures and cleanup-error precedence for nested failures.
3. Text exports versus receiver methods, formatting/pattern module placement and all
   formatting/parsing/pattern edge cases listed in §5.
4. `count` domain/signature, table member collisions and iteration/mutation behavior.
5. Container callback contracts and list element copy-out under reentrant mutation.
6. Task handle/scope result type constructors, time ranges and empty select.
7. Standard module packaging/discovery and program/argv/host entry API.

These are visible pending decisions, not a completed library hidden behind a nonexistent
README. Keep the inventory updated with decisions and corresponding worklist evidence.
