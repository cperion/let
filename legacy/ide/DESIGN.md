# IDE analysis: symbols, navigation, diagnostics

This designs the semantic layer of the editor integration: go-to-definition, references,
hover, document highlight, rename, name-aware semantic tokens, and resolution diagnostics,
across files as well as within one. It is written before implementation so the changes to
the compiler are deliberate.

The governing constraint is the project's own: **one owner per decision**. Let has one
resolver (`let/resolve.lua`). The editor must consume it, never restate scope, shadowing,
name identity, or import lookup.

Two decisions shape everything below:

- **Required source ranges.** Every node that names something carries the range of that
  name, as a required field, filled by the parser. A forgotten range is a constructor
  error, not a silent `nil`.
- **Canonical symbol identity is `(file, byte offset)`**, not an AST node or a definition
  object. Resolving a workspace one root at a time produces a separate `Context` per root,
  so the same declaration in an imported file appears as two different definition objects.
  A declaration's location is the same in every context, so it is the stable key.

## 1. What the compiler already provides

`A.Program:resolve(options)` walks the AST and returns a `Context`. It is already an API:
`test/resolve.lua` reads `resolved.module.names`, `resolved.references`, and
`template.captures`.

| Field | Meaning |
| --- | --- |
| `definitions[id]` | `{id, name, kind, node, owner, template?, captured?, address_taken?}` |
| `bindings[node]` | declaration node → its definition |
| `references[node]` | use node → list of `{definition, node, scope, access, path, template}` |
| `namespace_members[Project]` | `c.puts` → the dictionary entry |
| `constraints[Constraint]` | `: Int` → the use of the constraint definition |
| `scopes`, `templates`, `chains` | lexical structure and word templates |
| `module.names` | the file's top-level names (the module namespace) |
| `imports[node]` | import node → the parsed imported `Chain` |

`definition.kind` is `binding`, `stage`, `dictionary`, `namespace`, or (proposed) `unknown`.
`definition.owner` is the enclosing template and `definition.template` is the word a binding
denotes. `V.Contract.template(template, resolved, types)` adds the interface — the stage
types the body forces and the result type — with deliberate conservatism.

Critically, `Context:import_file` resolves an imported file **into the same context**:
it parses the named file and resolves its chain here. So one `resolve` already yields the
definitions and references of every file reachable through imports, each carrying its own
`Source.Span.file`. Cross-file is not a new resolver; it is a workspace over this one.

The symbol graph exists. The editor needs a view over it and four compiler changes.

## 2. Gap 1 — name ranges (required fields)

The AST keeps the `let` keyword's span but drops the identifier's. `A.Constraint` has no
span at all, and `A.Project.span` is the *base*'s span, so `c.puts` and `: Int` have no
target. An imported file has the same problem at its own declarations.

Add to `module Source`:

```
Range = (Span start, Span stop)
```

and append **required** fields:

| Node | New field |
| --- | --- |
| `Binding`, `Stage`, `Extern` | `Source.Range name_range` |
| `Constraint` | `Source.Range name_range` |
| `Project` | `Source.Range member_range` |

The parser saw the name token, so the parser fills them. The resolver copies the range onto
the definition (`definition.range`), so a consumer never digs into node types.

Required, not optional: every parsed node of these kinds genuinely has a name, and a
required field makes that a fact the constructor checks. The parenthesized nested-constraint
head is a synthetic `A.Name`, which already carries a span; it is not one of these nodes.
Constructor position matters for one node. ASDL appends a sum's `attributes` after its
declared fields, and `Project` is an `Expr` with `attributes (Source.Span span)`. So
`Project(base, name)` becomes `Project(base, name, member_range, span)`: the new field
precedes the appended span, and the two existing `A.Project(...)` call sites change
position. `Binding` is a product and `Stage`/`Extern` are `Item` constructors without
attributes, so their new field is simply appended.

Test helpers construct nodes directly and pass the range, which is the point — the
explicitness is visible at each site.

This also improves the compiler's own diagnostics: "duplicate binding x" currently points
at `let`, and should point at `x`.

**Rejected:** deriving ranges in the editor by pairing tokens with AST nodes. That is a
partial second parser, which this project refuses elsewhere.

## 3. Gap 2 — tolerant resolution

`resolve` fails fast: `Context:lookup` throws on `unknown name`. During editing that is the
normal state, and one typo would disable every semantic feature in the file. Diagnostics
also cannot be reported together.

Change resolution from "throw on the first problem" to "collect problems, return them":

- Add `Context:problem(span, message)` recording into `context.diagnostics`.
- `A.Program:resolve` returns `(context, diagnostics)`.
- An unknown name produces a definition of `kind == 'unknown'` and is recorded in
  `references`, so the walk continues and hover can say "unresolved".
- `A.Program:build` requires zero diagnostics and fails with the first one
  (`V.Lexer.fail(d.span, d.message)`), so compilation stays fail-fast and its messages are
  unchanged.

The one awkward case is `A.Binding:resolve`, which currently catches the "not visible in its
own initializer" condition by matching an error string. That becomes a recorded diagnostic,
not a message comparison.

Invariants:

- A tolerant context is **analysis-only**. It must not reach `build`, `emit`, or `known`.
- Downstream passes ignore `unknown` definitions; the editor checks for them.
- `build`'s zero-diagnostics gate is tested, so tolerance cannot silently mask a real
  program error.

## 4. Gap 3 — one host, one reader

`let/cli.lua` privately decides that every program gets the `c` namespace and the `CAlloc`
resource, and installs the file resolver. If the server chooses differently, the editor
reports errors the compiler does not.

Extract that policy into an explicit module, `let/host.lua`:

```
V.host.configure(options, {read = ...}) -> options with dictionary.c, resources, resolve
```

used by both `let/cli.lua` and the server. The server then analyzes exactly what the CLI
would compile.

The reader is the second half. `Context:import_file` calls `options.resolve(path, from)`,
and today `V.file_resolver` searches for the path and then reads it from disk itself. In an
editor, an imported file may be open with unsaved changes, so the search policy and the
bytes must be separable:

```
V.file_resolver{suffix = ..., roots = ..., read = function(path) ... end}
```

`read` defaults to the current disk read. The server passes a reader that first consults the
open-document store (by normalized absolute path) and falls back to disk. There is one owner
of "which file is this", and one of "what are its bytes".

## 5. Analysis pipeline and cache

One function produces everything a handler needs, once per document version:

```
ide/analysis.lua
analyze(text, file, host) -> {
  file        = normalized path,
  text_index  = ide/text for this file,
  scan        = ide/tokens.scan,       -- tolerant, always available
  program     = AST or nil,
  resolved    = Context or nil,
  diagnostics = {...},                 -- lexical, then parse, then resolution
  imports     = {path -> true},        -- files this analysis pulled in
}
```

Diagnostics are a ladder; each rung runs only when the one below produced something:

1. **lexical** — `scan.errors` (already tolerant).
2. **parse** — `V.parse` fails, one diagnostic (the parser fails fast; unchanged).
3. **resolution** — `resolved.diagnostics`, reported together because resolution is now
   tolerant.

Construction diagnostics (constraint failures, ownership, arity) are a later rung: they
need `build`, which is expensive and rejects more than resolution. Out of scope here, and
named as such rather than half-done.

The result is cached per `(file, version)`. All handlers — diagnostics, symbols,
completion, definition, hover, semantic tokens — read the same analysis, so a keystroke
parses and resolves once per root.

## 6. Symbol identity and the workspace index

This is the part that must be right before any feature is written.

**Canonical identity.** A declaration is identified by `(file, byte offset)` of its name
range start. A use is identified the same way. Definition objects are *not* identity: a file
imported by two roots is resolved twice, producing two `Context`s and two definition objects
for the same declaration.

**Per-root analysis, union index.** The server analyzes every open document as a root. Each
analysis already reaches its imports, so the transitive closure of imports from all open
documents is covered. `ide/symbols.lua` builds one index over the union of all analyses:

```
declarations[(file, offset)] = {name, kind, file, range, signature?}
uses[(file, offset)]         = {target, file, range}
```

Merging is safe because a declaration has one location: two contexts that find the same
declaration contribute the same key, and two uses of different bindings never share an
offset. Rename and references therefore work across roots without a shared `Context`, and
survive re-analysis because the key is source-derived.

**Non-source definitions.** Dictionary entries (`Int`, `c.puts`) have no file and offset.
They get a synthetic key (`kind:name`) that hover can describe but definition and rename
refuse.

Queries:

```
index:at(file, offset)          -- innermost range covering the cursor
index:definition(file, offset)  -- canonical target, or nil for a dictionary entry
index:occurrences(key)          -- declaration + every use, across files
index:describe(key)             -- hover text
index:classify(range)           -- semantic token type and modifiers
```

Range sources from the resolver:

- **declaration** — `definition.range`.
- **reference** — the use node's own range (`Name.span` + `#name`) from
  `resolved.references`.
- **namespace member** — `Project.member_range`.
- **constraint name** — `Constraint.name_range`.
- **dictionary entry** — no source range.

The index holds an `ide/text.lua` per file, so a span in any file converts with that file's
line map.

## 7. Feature mapping

- **definition** — `index:definition` → open the target `(file, range)`; nil for a
  dictionary entry.
- **references** — `index:occurrences`, filtered by `includeDeclaration`, across files.
- **hover** — the declaration as written (`let x mut : Int`, `let n : Int` as a stage,
  `extern c.puts`), the definition kind, and an inferred type **only** when
  `Contract.template` forces exactly one — the builder's own conservatism.
- **document highlight** — `index:occurrences` restricted to the current file.
- **rename** — `index:occurrences` rewritten, grouped into a `WorkspaceEdit` by file.
  Identity comes from the resolver, so shadowed names are distinguished correctly; this is
  the reason not to match text. Refused for dictionary entries and `unknown`.
- **semantic tokens** — lexical classification from `ide/tokens.lua` stays the base; names
  are refined by `index:classify`: a stage is `parameter`, a word is `function`, a binding
  keeps its mutability as a modifier. Degrades to the lexical answer without resolution.
  Refining names overrides a client's identifier styling, so it is behind a toggle.
- **document symbols** — top-level definitions from `resolved.module.names`, ordered by
  range.

## 8. Cross-file imports

The resolver already resolves imports into the same context; the work is workspace
orchestration and a few resolver affordances.

**Workspace.** The project is the transitive closure of imports from all open documents.
Each open document is a root and is analyzed independently; the union index covers the
closure. When a document changes, every analysis whose import set contains it — or whose
root it is — is invalidated. `didSave` and `didClose` do the same, because closing a buffer
reverts it to its disk bytes.

**Open buffers win.** The reader from §4 makes an unsaved import the analyzed content, so a
definition stays correct before the imported file is saved. Paths are normalized to absolute
form for the dependency map and converted to `file://` URIs for the wire.

**Definitions on an import site.** `resolved.imports[node]` is the imported `Chain` and its
`span.file` is the path, so definition on `import "codec.let"` opens that file. The target
range is the imported file's first top-level declaration, or the start of the file.

**Imported namespaces.** `let codec = import "codec.let"` makes `codec.JPEG` a structural
projection today, not a namespace member, so it does not navigate. Extend the resolver to
recognize a binding whose initializer is exactly an import as a namespace whose members are
the imported module's names — the cross-file form of the existing `c.puts` handling. This is
a semantic decision to confirm, not an obvious one; it is called out below.

**Diagnostics across files.** Resolution diagnostics carry `span.file`. An analysis publishes
for its root and for every file it imported, deduplicated by URI, so an error in an imported
file is visible. Files that are also open are analyzed as their own roots; the last analysis
to publish for a URI wins, and they agree because the source is the same.

**Reverse references.** References to a declaration in file A from file B are found when B is
an open root, because B's analysis resolves A. A declaration used only by a file that is
neither open nor imported by an open root is not found; finding it needs a workspace-wide
scan, which is a separate feature. The union of open roots makes this rare in practice, and
the limitation is stated rather than hidden.

## 9. Degradation rules

- No AST → lexical diagnostics, completion, lexical semantic tokens; navigation and hover
  unavailable.
- AST but no resolution → parse diagnostics only; lexical features.
- `unknown` definition → hover says "unresolved name"; definition returns nothing; rename
  refuses.
- Dictionary/namespace definitions → no location; hover describes the entry (phase, purity,
  signature) without inventing a type.
- The server never invents a diagnostic. Every message is one the compiler would produce.

## 10. Phasing

The index is built cross-file-ready from the start: keyed by `(file, offset)` and holding a
`Text` per file. Adding the workspace later is orchestration, not a rewrite.

1. **Name ranges** (compiler): `Source.Range`, required fields, parser fills them, resolver
   copies to `definition.range`, tests. Independently useful for compiler diagnostics.
2. **Host and reader** (compiler): `let/host.lua`, the `read` hook in `V.file_resolver`,
   `ide/analysis.lua` with the per-version cache. Single root.
3. **Symbol index** (editor): `ide/symbols.lua` keyed by `(file, offset)`, then definition,
   references, hover, document highlight, rename, name-refined semantic tokens, and document
   symbols from `module.names`. Single root, but already multi-file-shaped.
4. **Tolerant resolution** (compiler): `fail` → `diagnostics`, the `build` gate, resolution
   diagnostics in the editor, semantic features on partially valid files.
5. **Workspace** (editor): all open roots analyzed and unioned, the open-buffer reader,
   dependency invalidation, cross-file locations and rename, per-file diagnostics, import-site
   definition, imported-namespace members.

Each step lands with tests and keeps the suite green; steps 1, 2, and 4 regenerate the
bundle.

## 11. Decisions and open questions

Settled:

- `Source.Range`, one field, not two spans.
- Required fields, not optional: the type states the parser always provides the range.
- `let/host.lua`, an explicit module, not policy buried in `libc.configure`.
- Semantic tokens refine names, behind a toggle.
- Cross-file is designed and phased in now, and the index is keyed accordingly.

Open:

- **Imported namespaces as namespaces.** Treating `let codec = import "..."` as a namespace
  so `codec.JPEG` navigates is useful but is a semantic claim about what an import value is.
  Confirm it, or leave projection navigation to structural member resolution, which needs
  types and is a later pass.
- **Diagnostics for closed files.** Publishing for imported-but-unopened files is standard,
  but noisy if imports are large. Alternative: publish only after the file has been opened
  once. Recommend publishing for the root and its direct imports.
- **Analysis cost.** Analyzing every open root on each change is fine for a handful of
  files. If it is not, analyze lazily per request and cache; the design does not change.
