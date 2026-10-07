# Direct symbolic lowering to a compact residual IR

> Status: implementation specification. This is an archive-and-port rewrite; intermediate active-tree commits are allowed not to build.

## 1. Decision

The JIT and C-AOT path will not use ASDL.

ABC bytecode is already the input IR. The symbolic engine remains a bytecode interpreter over the verified byte stream, but its values become core-owned residual value IDs. It produces one compact handwritten residual IR consumed by native lowering, portable-C emission and canonical-ABC emission.

The concrete banked interpreter remains unchanged and executes verified bytecode directly.

```text
verified ABC bytes
    |
    +--> concrete banked interpreter
    |       direct execution; no residual construction
    |
    +--> symbolic bytecode interpreter
            A/B/C stacks contain residual value IDs
            constants and known control execute immediately
            unknown runtime work is recorded
                    |
                    v
            compact residual IR
              |          |          |
              v          v          v
           native       C AOT    canonical ABC
           stencils               scheduling
```

There is no persistent decoded ABC object graph and no generic compiler-IR runtime.

## 2. Architectural invariants

1. The concrete and symbolic interpreters consume the same verified ABC semantics.
2. The concrete interpreter executes bytecode directly and allocates no residual objects.
3. The symbolic interpreter owns values, facts, semantic versions, CFG construction and virtual continuations.
4. Residual values are dense core-owned IDs, never native registers, ABC DAG IDs or C-local IDs.
5. Residual operations describe only runtime work. ABC stack transport does not appear in the residual IR.
6. Consumers read completed residual blocks. They cannot return symbolic values or alter symbolic execution.
7. Semantic block versions contain no native register or home information.
8. Native layout variants are backend objects keyed by residual block and incoming physical layout.
9. The residual program retains its verified `abc_module`; descriptor, extern, image and source-function indices refer to that immutable module.
10. No consumer decodes source bytecode. Only the symbolic interpreter does.
11. No operation, edge, value or block is allocated separately with `malloc`.
12. Every hot table is a contiguous typed vector addressed by a 32-bit ID or span.

## 3. Non-goals

- Do not change the ABC wire format or public instruction semantics.
- Do not route interpreted execution through residualization.
- Do not create an ABC ASDL layer.
- Do not serialize the residual IR.
- Do not support plugins or consumers in other languages.
- Do not preserve the old callback protocol behind an adapter or feature flag.
- Do not introduce a generic visitor framework, reference counting or per-node ownership.
- Do not require a global graph-coloring register allocator.
- Do not keep `abc-asdlc` merely because it already exists; it has no remaining production user after this refactor.

## 4. Archive-and-port workflow

The current implementation is not discarded as knowledge. Before changing the active tree, preserve one immutable reference revision and open it side-by-side:

```text
archive branch/tag: archive/symbolic-sinks-v1
reference worktree: ../let-symbolic-sinks-v1
active worktree: current rewrite branch
```

The archive contains the old files, generated outputs and specification state exactly as they worked together. Record the archive revision in the first rewrite commit and in the workflow notes. During reconstruction, read the archive implementation and `docs/spec.md` to recover actual behavior, edge cases, invariants and low-level techniques.

Do not copy the archive into an `old/` directory in the active source tree. It is a read-only Git revision/worktree, not a compatibility implementation and not part of the build.

The workflow for each subsystem is:

1. inspect the archived implementation and relevant normative specification sections;
2. write down the semantic obligations and reusable algorithm;
3. remove the old active-tree structure that owns those obligations incorrectly;
4. rewrite the behavior against the new compact types and ownership boundary;
5. record the old-to-new mapping in the commit message or workflow task evidence;
6. continue without adding an adapter back to the archive design.

This is a semantic and algorithmic port, not a line-by-line port. Proven machinery is reused where it already belongs; coupling is not.

### 4.1 Old-to-new port map

| Archived implementation | Knowledge to port | New owner |
| --- | --- | --- |
| `gen/semantics.lua`, generated concrete handlers | exact arithmetic, checks, stack effects and edge cases | generated concrete and symbolic semantics |
| `src/symbolic.c` folding and stack helpers | constant behavior, A/B/C transformations, call frame rules | standalone symbolic interpreter |
| `src/residual_builder.c` version/edge construction | canonicalization, alias handling, joins, SCC behavior, provenance | symbolic session plus compact builder |
| `src/residual_analysis.c` | call graph, recursive SCC and entry-fact analysis | rewritten residual analysis |
| `src/residualize.c` register helpers | copy-on-write, materialization, spills, roots, edge conformance | `native_lower.c` |
| `src/residualize.c` runtime helpers | lazy stubs, IC transitions, executable publication | `native_runtime.c` |
| `src/optimize.c` | use counts, Ershov scheduling, module rewriting and provenance | residual-to-ABC consumer |
| `src/residual_c.c` | typed C signatures, declarations, control emission and diagnostics | residual-to-C consumer |
| `schema/residual.asdl`, validator and dump | semantic cases and validation obligations | handwritten compact IR, validator and dump |
| `docs/spec.md` and profile documents | normative VM, dynamic, ownership, ABI and versioning behavior | all rewritten components |

### 4.2 Active structure to yank

After the archive exists, remove these structures from the active tree before reconstruction:

```text
abc_symbolic_value.reg
ABC_SYM_BACKEND
sink and transfer_mask
all emit_* symbolic callbacks
virtualize / direct / residualize feedback fields
machine.extra_advance
consumer writes to machine.exit
native register identity stored as a symbolic value
optimize.c DagSink symbolic result identity
residual_builder.c callback-built ASDL graph
schema/residual.asdl and generated residual ASDL types
```

The following algorithms and low-level mechanisms are ported or moved, not casually reinvented:

```text
constant-folding expressions and exact trap behavior
source call-SCC and entry-fact analysis
stack-cache copy-on-write and edge parallel copies
root materialization and safepoint handling
stencil tables, patching and executable-memory publication
inline-cache state transitions
ABC module serialization and provenance
C signature and text emission
```

The old file organization, callback ownership and sink-specific value identity do not survive in active code.

## 5. Compact residual representation

`src/residual_ir.h` is the only semantic definition of the residual IR.

### 5.1 Dense typed IDs

```c
typedef uint32_t abc_res_value_id;
typedef uint32_t abc_res_operation_id;
typedef uint32_t abc_res_block_id;
typedef uint32_t abc_res_function_id;
typedef uint32_t abc_res_frame_id;
typedef uint32_t abc_res_origin_id;
typedef uint32_t abc_res_type_id;
typedef uint32_t abc_res_facts_id;
typedef uint32_t abc_res_signature_id;

typedef struct {
    uint32_t first;
    uint32_t count;
} abc_res_span;
```

ID zero is invalid. ID `n` addresses element `n - 1` of its typed table. IDs from different tables are different C typedefs conceptually even though C represents them as `uint32_t`.

There is no global entity-ID namespace, hash lookup, sorting or binary search.

### 5.2 Scalar type table

```c
typedef enum {
    ABC_RES_BOOL,
    ABC_RES_U8,
    ABC_RES_U16,
    ABC_RES_U32,
    ABC_RES_I32,
    ABC_RES_U64,
    ABC_RES_I64,
    ABC_RES_F64,
    ABC_RES_ADDRESS,
    ABC_RES_ANY,
    ABC_RES_CELL
} abc_res_scalar_type;

typedef enum {
    ABC_RES_OWN_NONE,
    ABC_RES_OWN_RAW_POINTER,
    ABC_RES_OWN_STRICT_BORROW,
    ABC_RES_OWN_MANAGED
} abc_res_ownership;

typedef enum {
    ABC_RES_ROOT_NONE,
    ABC_RES_ROOT_DYNAMIC,
    ABC_RES_ROOT_MANAGED_OBJECT,
    ABC_RES_ROOT_MANAGED_INTERIOR,
    ABC_RES_ROOT_MANAGED_ENVIRONMENT
} abc_res_root_kind;

typedef struct {
    uint32_t descriptor;       /* source module descriptor index + 1, or zero */
    uint8_t scalar;
    uint8_t ownership;
    uint8_t root;
    uint8_t reserved;
} abc_res_type;
```

Types are interned. Values store `abc_res_type_id`, not an inline type.

### 5.3 Facts table

```c
typedef enum {
    ABC_RES_REPR_NONE,
    ABC_RES_REPR_RAW,
    ABC_RES_REPR_ENCODED,
    ABC_RES_REPR_BOXED,
    ABC_RES_REPR_CANONICAL,
    ABC_RES_REPR_UNKNOWN
} abc_res_representation;

enum {
    ABC_RES_FACT_HAS_LAYOUT = 1u << 0,
    ABC_RES_FACT_FROZEN     = 1u << 1,
    ABC_RES_FACT_NOT_FROZEN = 1u << 2
};

typedef struct {
    uint64_t dynamic_tags;
    uint64_t layout_token;
    abc_res_span callable_targets; /* function-ID pool; empty means unknown */
    uint8_t dynamic_width;
    uint8_t representation;
    uint8_t flags;
    uint8_t reserved;
} abc_res_facts;
```

Facts are interned. Fact ID zero is the generic no-fact record. A value with raw proven dynamic bits has a noncanonical representation and no dynamic root obligation. A canonical `any` uses the dynamic root kind in its type.

### 5.4 Origins

```c
typedef struct {
    uint32_t source_function;
    uint32_t bytecode_offset;
    abc_res_origin_id caller;
} abc_res_origin;
```

Origins are interned by `(source_function, bytecode_offset, caller)`. Virtual calls extend the caller chain by one interned origin ID; they never copy linked origin structures.

### 5.5 Values and definitions

```c
typedef enum {
    ABC_RES_DEF_FUNCTION_ARGUMENT,
    ABC_RES_DEF_BLOCK_ARGUMENT,
    ABC_RES_DEF_CONSTANT,
    ABC_RES_DEF_OPERATION_RESULT
} abc_res_definition_kind;

typedef struct {
    uint32_t owner;  /* function, block, constant-pool or operation ID */
    uint16_t index;
    uint8_t kind;
    uint8_t reserved;
} abc_res_definition;

typedef struct {
    abc_res_definition definition;
    abc_res_type_id type;
    abc_res_facts_id facts;
    abc_res_origin_id origin;
} abc_res_value;
```

Constant definitions index a contiguous `uint64_t` constant pool. Constants may be interned by `(bits, type, facts)`.

### 5.6 Value spans

All variable operand/result lists use ranges into one contiguous value-ID pool:

```c
typedef struct {
    const abc_res_value_id *items;
    uint32_t count;
} abc_res_value_view;
```

Stored records contain `abc_res_span`, not pointers. This applies to:

```text
operation results
activation arguments
block arguments
edge arguments
return/halt values
callable target sets
```

### 5.7 Effects

```c
enum {
    ABC_RES_EFFECT_MAY_ABORT       = 1u << 0,
    ABC_RES_EFFECT_READS_MEMORY    = 1u << 1,
    ABC_RES_EFFECT_WRITES_MEMORY   = 1u << 2,
    ABC_RES_EFFECT_CALLS           = 1u << 3,
    ABC_RES_EFFECT_MAY_ALLOCATE    = 1u << 4,
    ABC_RES_EFFECT_SAFEPOINT       = 1u << 5,
    ABC_RES_EFFECT_SYNC_ROOTS      = 1u << 6,
    ABC_RES_EFFECT_MANAGED_BARRIER = 1u << 7
};
```

Effects are a validated bitmask. `src/residual_ops.def` supplies the required and permitted effect mask for each operation kind.

### 5.8 Operation kinds

`src/residual_ops.def` is the single operation manifest. It generates:

- `abc_res_operation_kind`;
- operation names;
- required/permitted effects;
- validator and dump coverage tables;
- an operation-count constant used by exhaustive tests.

The semantic families are:

```text
unary, binary, conversion, check
frame enter, frame leave, frame address
image address, load, store, memory copy
function reference
encode, box and decode materialization
any box, cast and test
dynamic unary, binary, literal and require-bool
open-word and string operations
direct and captured callable construction
managed allocate, copy and write barrier
direct, indirect, foreign and dynamic materialized activation
```

There is no generic “ABC opcode” residual operation. Dynamic operations use semantic residual enums, not `EXT` selector numbers.

### 5.9 Operation layout

```c
typedef struct {
    uint16_t kind;
    uint16_t effects;
    abc_res_origin_id origin;
    abc_res_span results;

    union {
        struct {
            uint16_t operation;
            uint16_t reserved;
            abc_res_value_id input;
        } unary;

        struct {
            uint16_t operation;
            uint16_t reserved;
            abc_res_value_id left;
            abc_res_value_id right;
        } binary;

        struct {
            abc_res_value_id address;
            abc_res_value_id value;
            uint32_t offset;
            abc_res_type_id type;
            uint8_t address_space;
            uint8_t reserved[3];
        } memory;

        struct {
            uint32_t target; /* residual function ID or module extern index */
            abc_res_signature_id signature;
            abc_res_span arguments;
            uint32_t frame_cells;
            uint32_t hidden_result_bytes;
            uint8_t adjustment;
            uint8_t reserved[3];
        } activation;

        struct {
            uint16_t operation;
            uint16_t flags;
            uint32_t descriptor;
            abc_res_span arguments;
            abc_res_value_id literal;
        } dynamic;

        struct {
            abc_res_value_id first;
            abc_res_value_id second;
            uint32_t first_immediate;
            uint32_t second_immediate;
        } generic;
    } data;
} abc_res_operation;
```

Named builder functions are the only producer API. Generated symbolic code does not initialize this union directly.

Required size gate:

```c
_Static_assert(sizeof(abc_res_operation) <= 48,
               "residual operation exceeds compact layout budget");
```

If a rare operation cannot fit, its uncommon payload moves to a typed side pool. The common operation struct is not enlarged.

### 5.10 Edges, requirements and terminators

```c
typedef struct {
    abc_res_block_id target;
    abc_res_span arguments;
} abc_res_edge;

typedef enum {
    ABC_RES_REQUIRE_TAGS,
    ABC_RES_REQUIRE_LAYOUT,
    ABC_RES_REQUIRE_FROZEN,
    ABC_RES_REQUIRE_CALLABLE
} abc_res_requirement_kind;

typedef struct {
    uint64_t expected;
    abc_res_value_id value;
    uint32_t target;
    uint8_t kind;
    uint8_t boolean_value;
    uint8_t reserved[2];
} abc_res_requirement;

typedef enum {
    ABC_RES_TERM_JUMP,
    ABC_RES_TERM_BRANCH,
    ABC_RES_TERM_SWITCH,
    ABC_RES_TERM_GUARD,
    ABC_RES_TERM_RETURN,
    ABC_RES_TERM_HALT,
    ABC_RES_TERM_TAIL_DIRECT,
    ABC_RES_TERM_TAIL_INDIRECT,
    ABC_RES_TERM_TAIL_DYNAMIC,
    ABC_RES_TERM_ABORT,
    ABC_RES_TERM_UNREACHABLE
} abc_res_terminator_kind;

typedef struct {
    uint64_t low;
    uint64_t high;
    abc_res_edge edge;
} abc_res_switch_arm;

typedef struct {
    uint16_t kind;
    uint16_t flags;
    abc_res_origin_id origin;

    union {
        abc_res_edge jump;

        struct {
            abc_res_value_id left;
            abc_res_value_id right;
            uint16_t relation;
            uint16_t reserved;
            abc_res_edge yes;
            abc_res_edge no;
        } branch;

        struct {
            abc_res_value_id value;
            abc_res_span arms;
            abc_res_edge fallback;
        } switch_value;

        struct {
            abc_res_requirement requirement;
            abc_res_edge pass;
            abc_res_edge fallback;
        } guard;

        struct {
            abc_res_span values;
        } exit;

        struct {
            uint32_t target;
            abc_res_signature_id signature;
            abc_res_span arguments;
            uint32_t frame_cells;
            uint32_t hidden_result_bytes;
            uint8_t adjustment;
            uint8_t reserved[3];
        } activation;

        struct {
            uint8_t reason;
            uint8_t reserved[7];
        } abort;
    } data;
} abc_res_terminator;
```

Switch arms live in one contiguous arm pool. The largest terminator payload is a guard with two edges, so the complete terminator remains within 64 bytes.

### 5.11 Frames, blocks and functions

```c
typedef struct {
    uint32_t bytes;
    uint32_t alignment;
    abc_res_origin_id origin;
    uint8_t initialized;
    uint8_t reserved[3];
} abc_res_frame;

typedef struct {
    uint32_t bytecode_offset;
    abc_res_span arguments;
    abc_res_span operations; /* operation-ID range */
    abc_res_terminator terminator;
} abc_res_block;

typedef struct {
    uint32_t source_function;
    abc_res_signature_id signature;
    abc_res_span arguments;
    abc_res_span frames;
    abc_res_span blocks;
    abc_res_block_id entry;
    uint16_t summary_effects;
    uint16_t reserved;
} abc_res_function;
```

Block and function IDs are their indexes in the corresponding program tables.

### 5.12 Program ownership

`abc_residual_program` is opaque and owns typed vectors for:

```text
values
operations
blocks
functions
frames
origins
types
facts
signatures
constants
value IDs
operation IDs
switch arms
function IDs used by callable facts
```

It retains or is lifetime-nested under the immutable verified `abc_module`. Residual references to descriptors, dynamic constants, externs, image offsets and source functions use verified module indices. Consumers receive both through the program API and never inspect source bytecode.

The session owns the program. Freeing the session frees every vector in bulk.

## 6. Layout and allocation requirements

The compact layout is part of the architecture, not a later optimization.

```c
_Static_assert(sizeof(abc_res_span) == 8, "span layout changed");
_Static_assert(sizeof(abc_res_type) <= 8, "type layout grew");
_Static_assert(sizeof(abc_res_origin) <= 12, "origin layout grew");
_Static_assert(sizeof(abc_res_value) <= 24, "value layout grew");
_Static_assert(sizeof(abc_res_facts) <= 32, "facts layout grew");
_Static_assert(sizeof(abc_res_operation) <= 48, "operation layout grew");
_Static_assert(sizeof(abc_res_edge) <= 12, "edge layout grew");
_Static_assert(sizeof(abc_res_requirement) <= 24, "requirement layout grew");
_Static_assert(sizeof(abc_res_terminator) <= 64, "terminator layout grew");
_Static_assert(sizeof(abc_res_block) <= 96, "block layout grew");
```

Hot vectors use geometric growth and transfer ownership directly. They are not copied into a second arena representation during finalization.

There is:

- no `malloc` per instruction, value, operation, edge or block;
- no recursive pointer graph;
- no `size_t + pointer` sequence inside hot records;
- no blanket `memset` of large unused union storage;
- no all-program clearing of backend side tables when a generation stamp suffices.

A small chunk arena may be used only for strings, diagnostics and rare cold metadata.

## 7. Residual builder API

Only the symbolic interpreter uses mutation APIs from `src/residual_builder.h`.

Representative constructors are:

```c
abc_res_value_id abc_res_constant(
    abc_res_builder *, uint64_t bits,
    abc_res_type_id, abc_res_facts_id, abc_res_origin_id);

abc_res_value_id abc_res_unary(
    abc_res_builder *, abc_res_unary_op,
    abc_res_value_id input,
    abc_res_type_id result_type,
    abc_res_facts_id result_facts,
    abc_res_origin_id);

abc_res_value_id abc_res_binary(
    abc_res_builder *, abc_res_binary_op,
    abc_res_value_id left, abc_res_value_id right,
    abc_res_type_id result_type,
    abc_res_facts_id result_facts,
    abc_res_origin_id);

abc_res_span abc_res_activate_direct(
    abc_res_builder *, abc_res_function_id,
    abc_res_signature_id, abc_res_value_view arguments,
    uint32_t frame_cells, abc_res_origin_id);

void abc_res_finish_jump(abc_res_builder *, abc_res_edge);
void abc_res_finish_branch(
    abc_res_builder *, abc_res_relation,
    abc_res_value_id left, abc_res_value_id right,
    abc_res_edge yes, abc_res_edge no,
    abc_res_origin_id);
void abc_res_finish_guard(
    abc_res_builder *, abc_res_requirement,
    abc_res_edge pass, abc_res_edge fallback,
    abc_res_origin_id);
```

Every constructor:

1. validates local arity and ID ranges;
2. appends operand/result IDs to shared pools;
3. obtains required effects from `residual_ops.def`;
4. creates result definitions and values;
5. appends exactly one compact operation;
6. returns result IDs or a result span.

Backends include `residual_ir.h`, not `residual_builder.h`.

## 8. Symbolic interpreter state

```c
typedef struct {
    abc_res_value_id value;
} abc_symbolic_slot;

typedef enum {
    ABC_SYMBOLIC_C_VALUE,
    ABC_SYMBOLIC_C_FRAME_CELL
} abc_symbolic_c_slot_kind;

typedef struct {
    abc_res_value_id value;
    abc_res_frame_id frame;
    uint32_t byte_offset;
    uint8_t kind;
    uint8_t reserved[3];
} abc_symbolic_c_slot;

typedef struct {
    uint32_t return_pc;
    uint32_t caller_source_function;
    abc_res_function_id caller_residual_function;
    uint32_t a_base;
    uint32_t b_base;
    uint32_t c_base;
    abc_res_origin_id call_origin;
    uint8_t destination;
    uint8_t reserved[3];
} abc_symbolic_continuation;

typedef struct {
    uint32_t source_function;
    uint32_t pc;
    abc_res_function_id residual_function;
    abc_symbolic_slot *a;
    abc_symbolic_slot *b;
    abc_symbolic_c_slot *c;
    abc_symbolic_continuation *continuations;
    uint32_t a_count, b_count, c_count;
    uint32_t continuation_count;
} abc_symbolic_state;
```

No symbolic structure contains:

```text
native register
native home
ABC output DAG node
C local
stencil ID
backend pointer
backend callback
```

## 9. Symbolic session API

```c
typedef struct abc_symbolic_session abc_symbolic_session;

typedef struct {
    uint32_t semantic_version_limit;
} abc_symbolic_options;

typedef enum {
    ABC_SYMBOLIC_OBSERVED_TAGS,
    ABC_SYMBOLIC_OBSERVED_LAYOUT,
    ABC_SYMBOLIC_OBSERVED_FROZEN,
    ABC_SYMBOLIC_OBSERVED_CALLABLE
} abc_symbolic_observation_kind;

typedef struct {
    uint32_t parameter;
    uint64_t first;
    uint64_t second;
    uint8_t kind;
    uint8_t reserved[7];
} abc_symbolic_observation;

abc_status abc_symbolic_session_create(
    const abc_module *module,
    const abc_symbolic_options *options,
    abc_symbolic_session **out,
    abc_error *error);

abc_status abc_symbolic_seed_function(
    abc_symbolic_session *session,
    uint32_t source_function,
    abc_res_block_id *entry,
    abc_error *error);

abc_status abc_symbolic_specialize_entry(
    abc_symbolic_session *session,
    abc_res_block_id generic_entry,
    const abc_symbolic_observation *observations,
    size_t observation_count,
    abc_res_block_id *guarded_entry,
    abc_error *error);

int abc_symbolic_next_pending(
    abc_symbolic_session *session,
    abc_res_block_id *block);

abc_status abc_symbolic_build_block(
    abc_symbolic_session *session,
    abc_res_block_id block,
    abc_error *error);

abc_status abc_symbolic_drain(
    abc_symbolic_session *session,
    abc_error *error);

const abc_residual_program *abc_symbolic_program(
    const abc_symbolic_session *session);

void abc_symbolic_session_free(abc_symbolic_session *session);
```

The session may reallocate vectors. Consumers retain IDs, never pointers, across session mutation. Lookup functions return pointers valid only until the next mutation.

Eager and C/ABC build paths seed roots and call `abc_symbolic_drain`. Lazy native execution retains the session and builds requested blocks only.

## 10. Semantic version algorithm

```text
request(state):
    canonical = canonicalize(state)
    family = family_key(canonical)

    if exact semantic key exists:
        return edge(existing block, actual arguments)

    if family version count == semantic_version_limit:
        canonical = generalize(canonical)
        if generalized key exists:
            return edge(general block, actual arguments)

    allocate block ID
    allocate one block argument for each distinct nonconstant incoming value
    preserve alias classes: duplicate stack slots share one block argument
    rewrite saved entry state to constants and new block-argument IDs
    insert the version key before interpreting the body
    enqueue the block
    return edge(new block, actual arguments)
```

The key contains:

```text
source function and bytecode PC
A/B depths and per-slot constant or (type, facts, alias class)
C value/frame-cell shape and alias classes
frame-region sizes and nesting
virtual continuation sequence
residual root function receiving virtual callees
```

Global value IDs do not distinguish versions. Alias equivalence does.

The family key removes constants and refinable tag/layout/callable facts while retaining bytecode location, scalar/root types, stack shape, frame layout and continuation ABI. Generalization creates a new generic version; it never mutates a published block.

## 11. Symbolic bytecode execution

`gen/symbolic.lua` continues generating bytecode handlers from the authoritative opcode manifest. The handlers call core symbolic helpers and tail-dispatch within the bytecode block. They do not call consumers.

The symbolic machine contains:

```text
module/code/pc/end
current symbolic state
symbolic session
open residual block builder
core build result and abc_error
```

It does not contain sink, transfer mask, callbacks or `extra_advance`.

A handler either:

- performs a purely symbolic stack/state transition and dispatches next;
- folds a known value and dispatches next;
- appends a residual operation and dispatches next;
- seals a residual terminator and returns to the session;
- reports an internal construction error.

## 12. Instruction mapping

| ABC family | Symbolic action | Residue when runtime-dependent |
| --- | --- | --- |
| `PUSH*` | intern constant and push ID | none |
| `DUP`, `COPY`, `MOVE`, `DROP` | rearrange IDs | none |
| `CPUSH*`, `CGET*`, `CSET*`, `CPOP` | rearrange IDs/C slots | none |
| integer/float binary, immediate, C-operand, `POW` | fold or define result | binary operation |
| unary and width forms | fold or define result | unary/conversion operation |
| checks and trapping conversions | remove known success; terminate known failure | check/conversion with abort effect |
| jumps and conditional branches | select known target or request successors | jump/branch terminator |
| `SWITCH` | select known arm or request all arms | switch terminator |
| `CALLOC` | create frame ID and push frame cells | frame-enter operation |
| `CFREE` | pop matching frame cells | frame-leave operation |
| frame/image/pointer loads/stores | retain semantic address and type | address/load/store operations |
| `IDX`, `LDX` | build scaled address | binary address operations plus load |
| `MEMCPY` | consume addresses | copy plus managed barrier when required |
| direct `CALL` | virtual transition or materialized activation | no node when virtual; otherwise direct activation |
| `TCALL` | frame replacement/edge or materialized tail | jump or direct-tail terminator |
| `RET` | restore virtual continuation or root return | jump or return terminator |
| `CALLI` | direct only with proved target; otherwise materialize | indirect activation |
| `TCALLI` | as above | indirect-tail terminator |
| `FCALL` | use verified extern metadata | foreign activation |
| dynamic call/tail | direct only after proved callable guard | dynamic activation/tail |
| `ABORT`, `HALT` | terminate | abort/halt terminator |
| `ANY_BOX/CAST/IS` | fold only with exact safe facts | explicit any operation |
| dynamic arithmetic/comparison/condition | fold when exact | semantic dynamic operation |
| open-word/string operations | preserve mutation/allocation/order | word/string operation |
| callable construction | retain target/signature/environment | callable operation |
| managed allocation/copy/write | preserve descriptor/root/barrier | managed operation |
| internal quickened opcode | impossible in verified input | hard internal error |

No residual operation stores an ABC opcode number as its semantic meaning.

## 13. Calls and continuations

Compute direct-call SCCs once from verified bytecode.

### 13.1 Known acyclic call

```text
remove argument IDs from caller A
push virtual continuation
construct callee C argument slots
continue symbolic bytecode execution at callee entry
clone/specialize callee residual blocks under caller residual function
on RET, restore caller state and continue at return PC
```

No activation operation or runtime return address is emitted.

### 13.2 Recursive or capped call

A non-tail call is materialized when:

```text
target is unknown
call crosses/enters an active recursive SCC
semantic entry family reached its version limit
call is ABI-visible or independently callable
reentrancy through an unknown boundary is possible
```

The residual direct/indirect/dynamic activation operation contains semantic arguments, result values, frame requirements and signature. Native lowering decides registers and continuation storage.

### 13.3 Tail activation

A direct self-tail transition replaces frame arguments and becomes a CFG edge. Other known virtual tails may also become edges when their residual root permits it. Recursive cross-function or unknown tails use explicit tail-activation terminators and preserve the runtime continuation.

The backend never decides whether a call is virtual.

## 14. Guarded runtime specialization

Observed facts are not inserted directly into a semantic context.

`abc_symbolic_specialize_entry` constructs guard blocks:

```text
guard entry(generic arguments):
    guard requirement
      pass     -> specialized entry(refined facts)
      fallback -> generic entry(original facts)
```

Requirements cover:

```text
dynamic tag set
open-word layout token
frozen/not-frozen state
exact callable target
```

Tag guards inspect canonical `any` values. Raw decoding occurs in the pass block, leaving the canonical value intact for fallback. Layout checks happen before slot access. Callable checks happen before environment extraction or effects.

Site monotonic state remains session/runtime metadata keyed by bytecode offset. The guard itself is residual IR.

## 15. Validation

`abc_residual_validate` validates one completed program for eager/C/ABC use. `abc_residual_validate_block` validates one newly completed block before lazy publication.

Validation performs:

1. direct range checks for every typed ID and span;
2. exactly one definition for every value;
3. definition ownership and result-index checks;
4. operation-specific operand/result type and arity checks;
5. exact required/permitted effect checks from `residual_ops.def`;
6. frame-region nesting, lifetime and address-range checks;
7. edge argument count, type, facts and target-function checks;
8. guard pass refinement and unrefined fallback checks;
9. activation signature, environment, frame and result checks;
10. root representation/materialization checks at safepoints and ABI boundaries;
11. terminator completeness and function return contract checks.

Every operation and terminator kind has an explicit validator case. Unknown kinds reject.

## 16. Native lowering

Native lowering consumes:

```text
residual program
residual block ID
incoming native entry layout
```

and produces one native layout variant.

Its private table is:

```text
residual value ID -> constant | native register | native home
```

The table uses generation stamps so compiling one block does not clear an array proportional to the whole program.

For each operation, native lowering:

1. obtains operand representations;
2. materializes roots required by its effect mask;
3. chooses register-addressed stencil and writable destination;
4. emits the stencil;
5. records result representations.

For each edge it chooses/creates a native target variant and computes a parallel copy from residual edge arguments to target block arguments. The control stencil is emitted before edge-local conformance stubs.

Materialized activation operations lower to frame/continuation storage and control transfer. Virtual calls have no activation operation and therefore cannot accidentally reappear.

## 17. C and canonical-ABC consumers

### 17.1 Portable C

The C writer maps:

```text
value ID -> typed C local/expression
block ID -> label
block argument -> home variable
activation -> typed/direct, indirect, foreign or dynamic C boundary
abort/effect -> required error/control plumbing
```

It reads residual semantics and immutable module metadata. It never invokes symbolic execution.

### 17.2 Canonical ABC

The ABC writer computes residual use counts and Ershov scheduling, chooses A/B/C placement, emits stack transport required by that schedule and serializes a verified module. Stack scheduling is an output concern and is not stored in residual values.

`abc-opt` remains a build-time tool. Runtime interpreted execution does not invoke it.

## 18. Exact file disposition

| Path | Action | End state |
| --- | --- | --- |
| `schema/residual.asdl` | delete in Cut 1 | no ASDL residual schema |
| `tools/asdlc/` | delete in Cut 1 | no unused project-local ASDL compiler |
| `tools/validate_asdlc.c` | delete in Cut 1 | no dead ASDL tests |
| generated residual ASDL rules in `Makefile` | delete | handwritten compact IR builds directly |
| `src/residual_ir.[ch]` | complete rewrite | compact read-only types, pools, lookup and lifetime API |
| new `src/residual_ops.def` | create | single semantic operation/effect manifest |
| `src/residual_validate.c` | complete rewrite | typed-ID and semantic validation |
| `src/residual_builder.[ch]` | delete old callback sink; recreate header/source | only compact mutation constructors used by symbolic core |
| `src/residual_analysis.[ch]` | remove sink-value dependencies | call SCC and semantic summary analysis |
| `src/symbolic.[ch]` | delete callback protocol and rewrite | target-independent bytecode interpreter over residual IDs |
| `gen/symbolic.lua` | remove callback generation | handlers calling core symbolic helpers only |
| `src/residualize.c` | remove `native_emit_*`, old semantic `version_for`, `edge`, `compile_version` | native session/entry driver |
| new `src/native_lower.[ch]` | create | residual block to stencil lowering and physical variants |
| new `src/native_runtime.c` | create | lazy stubs, inline caches and executable-memory publication |
| `src/optimize.c` | delete `DagSink`, `dag_*`, `simulate_tree` | residual use analysis, scheduling and ABC serialization |
| `src/residual_c.c` | remove bundle/fallback symbolic assumptions | direct residual consumer |
| concrete banked interpreter files | leave direct execution intact | no residual dependency |
| `Makefile` | remove ASDL objects/rules; add compact IR/native objects | one symbolic producer and three consumers |

No deleted callback or ASDL type is reintroduced under a compatibility name.

## 19. Archive-and-port implementation order

### Archive checkpoint

Before active-tree deletion:

```sh
git branch archive/symbolic-sinks-v1 HEAD
git worktree add --detach ../let-symbolic-sinks-v1 archive/symbolic-sinks-v1
```

Record the archive commit ID in the workflow notes. Verify that the reference worktree contains the old symbolic, native, optimizer, residual-C, ASDL and specification files. Do not edit that worktree during the port.

### Cut 1: yank the old active structure

Delete from the active rewrite tree:

```text
symbolic sink callbacks and sink-owned values
native/optimizer/C callback implementations
old residual builder sink
ASDL residual schema, generator, generated-code rules and tests
all virtualize/direct/residualize feedback
extra_advance and sink writes to machine.exit
```

Retain the concrete interpreter. The compiled and C paths are expected not to build after this cut. Add no stubs or adapters. Use the archive worktree and archived `docs/spec.md` as the reference while writing Cut 2 and Cut 3.

### Cut 2: compact IR and standalone symbolic interpreter

Create/rewrite:

```text
src/residual_ir.[ch]
src/residual_ops.def
src/residual_builder.[ch]
src/residual_validate.c
src/residual_analysis.[ch]
src/symbolic.[ch]
gen/symbolic.lua
```

Implement sections 5–15 completely, including all verified core opcodes and all profile-5 selectors. At the end, verified bytecode can be symbolically lowered into validated compact residual blocks without any consumer.

### Cut 3: consumers

Create/rewrite:

```text
src/native_lower.[ch]
src/native_runtime.c
src/residualize.c
src/optimize.c
src/residual_c.c
Makefile
```

Native, C and canonical ABC consume the same residual program directly. There is no old fallback path.

### Cut 4: compile, test and optimize

Only after the new end-to-end architecture exists:

1. restore clean compilation;
2. test residual constructors, dump and validators;
3. run interpreted/eager/lazy differential execution;
4. run optimizer determinism/fixpoint tests;
5. run portable-C differential tests;
6. run managed-root, safepoint and malformed-module tests;
7. run sanitizers;
8. measure layout, allocation, decode/lowering latency, native code size and steady-state performance;
9. repair within the new architecture;
10. update `docs/spec.md`, `docs/symbolic-vm.md`, architecture and continuation documentation.

A failing test does not justify restoring a callback, sink-owned symbolic value or ASDL graph.

## 20. Acceptance criteria

### 20.1 Architecture

- Concrete interpreted execution still reads verified bytecode directly.
- `abc_symbolic_value.reg`, `ABC_SYM_BACKEND` and every sink callback are gone.
- Symbolic A/B/C values are residual value IDs.
- Residual semantic types exist only in `src/residual_ir.h` and `src/residual_ops.def`.
- Native registers/homes appear only in native files.
- Consumers do not decode source ABC.
- Known finite direct calls produce no activation operation.
- Observed facts always have explicit guards and generic fallbacks.
- Semantic versions contain no physical layout.
- Native variants contain no symbolic execution policy.
- ASDL is absent from the production and build-time residual pipeline.

### 20.2 Layout and allocation

- All size assertions in section 6 pass on x86-64 and ARM64 targets.
- IDs use direct bounds-checked indexing.
- No per-value, per-operation, per-edge or per-block allocation occurs.
- Lazy compilation constructs only reached residual blocks.
- Completing a block does not copy its operations into a second representation.
- Origin extension is interned O(1) average work, not caller-chain copying.

### 20.3 Semantics

- Interpreted/eager/lazy execution agrees on values, aborts, image effects and provenance.
- Optimized ABC verifies, is deterministic and is byte-identical at fixpoint.
- Portable C agrees for every supported semantic family.
- Dynamic guard failure reaches a correct generic path before guarded effects.
- Managed roots are scanner-visible at every allocating/generic boundary.
- Recursive non-tail activation materializes continuation state.
- Tail recursion remains a CFG cycle or tail activation, never an unbounded virtual continuation.

### 20.4 Performance

Measure separately:

```text
bytes per residual value
bytes per residual operation
allocations per compiled block
symbolic lowering nanoseconds per bytecode instruction
lazy first-block construction time
native lowering nanoseconds per residual operation
native code bytes per residual operation
steady-state benchmark time
```

The interpreted path must show no material startup or throughput regression because it is unchanged. Native steady-state performance must remain in the existing near-native class. Eager/lazy compilation regressions are not accepted merely because the architecture is cleaner; optimize compact builders and lowering rather than restoring fusion.

## 21. End state

```text
Concrete execution:
    verified ABC bytes
        -> banked interpreter

Compiled/build execution:
    verified ABC bytes
        -> standalone symbolic bytecode interpreter
        -> compact residual values/blocks/effects
        -> native stencils, C, or canonical ABC
```

The symbolic engine is plainly a second interpreter over the same bytecode. Its result is a compact semantic program. Native placement is plainly a consumer. There is no backend-to-symbolic feedback and no generic IR framework between them.
