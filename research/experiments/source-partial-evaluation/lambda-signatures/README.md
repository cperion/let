# Lambda parameter annotations without repeated binding signatures

Implemented the existing syntax.md section-4 contract in the ordinary lambda
entry path. When there is no expected signature, every parameter must have an
annotation (vacuously true for nullary lambdas). Those input types are resolved
once, and the existing return-inference path establishes the result vector before
an Ir.Fn/View is emitted. Contextual lambdas retain their previous checking rules.

There is no new type-inference engine, source evaluator, capture rule, callable
representation or scheduling policy. The internal input-checking context's empty
result list is not emitted as a provisional function contract.

`frontend/tests/lambdas.lua`, now in `make validate-slet`, passes **209 checks /
60 VM executions**. Cases cover context-only, parameters-only and redundant
annotations; nullary, block, unit, integer/f64 and multiple-result lambdas;
immediate invocation; and a callable parameter supplying lambda context.
SLet original/optimized modules execute in interpreted/eager/lazy modes with
independent expected cells. Let is checked as semantic IR only. Tests verify exact
inferred result types and identical assembly for equivalent annotation spellings.
Missing parameter types, mismatched annotations/results, incompatible inferred
returns and missing returns retain source diagnostics.

`validate-slet.log` records the passing frontend integration target, including
259 compiler, 81 lowering, 105 optimizer, 24 prior staging, 217 session/ABI checks,
27 lifetime cases, schema/parser/walker, symmetric execution, 78 production-source
executions and 12 portable-C cases. The full `validate` target was not rerun for
this small frontend change; its preceding known blocker is the legacy cache
fixture's bare RET. No timing or general inference-completeness claim is made.

Source virtual values/places, required-static demand integration, SLet capture
ownership and source module initialization remain pending. This feature does not
claim to close those gaps or extend existing general result-adjustment rules.
