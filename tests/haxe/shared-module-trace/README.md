# Shared-module behavior trace

The registry (`packages/compiler/SemanticPassRegistry.hx`) names the shared
compiler mechanisms each target must consume. The old backstop proved a row by
matching the module name in the target's source text. That proof accepts a dead
reference (a wrapper nobody calls) and says nothing about a target that ships
its own copy.

This corpus proves consumption behaviorally. Each target compiles the standard
Haxe behavior corpus with `-D shared-module-trace=<path>`; every public entry
point of a registered module records the class that called it, and the
after-generate flush writes one `module<TAB>caller` line per pair. The runner
asserts that each `(module, target)` row in the registry appears in that
target's trace. A row that never appears is a bypass: the target produced that
behavior without the shared implementation.

## Running it

```sh
bun tools/registry-guard/trace-check.ts            # all five targets
bun tools/registry-guard/trace-check.ts dart rust  # selected targets
```

The runner writes `out/shared-module-trace/<target>/trace.tsv`. The consumer
table comes from `out/shared-module-consumers.json`, written by
`SemanticPassRegistry.emitArtifact()` during every compile, so the assertion
always reads the registry, so there is one copy.

## Attribution

The recorded caller is the first stack frame outside the recording module. A
target that reaches a mechanism through another shared module therefore records
that module, so the registry's direct-consumer column stays
meaningful. Those rows stay green because the module ran, and the runner prints
them under `transitive-only` so a dead direct wrapper stays visible.

## Adding or instrumenting a module

1. Add the row to `SemanticPassRegistry.consumers`.
2. Put `SharedModuleTrace.record("<Module>");` at the top of every public
   static function of the module. `@:build` auto-instrumentation is not
   available here: Haxe rejects a build macro on a type used from macro code
   ("You cannot use @:build inside a macro"), and every shared module is used by
   the target compiler macros.
3. Add a corpus or an `examples/*.hxml` feature that reaches the module on the
   targets the row expects. The trace only proves what the corpus exercises.

## The trace corpus

The runner derives `out/shared-module-trace/<target>/trace.hxml` from
`examples/<target>.hxml` and drops `tests.DriverPlanTests`. That test pulls in
`driver.Config`, whose `StepOverride` object literal the dart and swift emitters
reject on the current baseline (verified on unmodified compiler sources).
Keeping it would make the settled targets and the unsettled ones incomparable.
Drop the exclusion in `trace-check.ts` once both emitters accept the literal.
Deriving the hxml keeps the corpus from drifting from the generation entries.
