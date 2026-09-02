# Feature spec 39: Constructor statement parity and array comprehension

## Scope

Two gaps share one observable: constructs whose desugaring yields a
statement sequence in expression position lower inside ordinary methods
and fail inside constructor bodies on the Kotlin target. This spec rules
the array comprehension construct, rules the constructor gap, and records
the probe evidence.

## Evidence (filed 2026-09-02; status: Planned)

Probes ran in a standalone worktree against the vendored tree at
`ab567bc`, with the compiler invocation of `probe.hxml` (std-shadow,
kotlin target, `float-precision=f32`).

| Probe | Site | Source shape | Result |
| --- | --- | --- | --- |
| 1 | field assignment in a constructor | `gapPrefix = [for (_ in 0...n + 1) 0];` | rejected, `expression has no Kotlin lowering in the subset: TBlock` at `src/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx` line 1061 |
| 2 | final local in a constructor | same comprehension | rejected, same error |
| 4 | final local in a plain method | same comprehension | accepted |
| 5 | var local with a runtime bound in a plain method | same comprehension | accepted |
| 6 | pipeline call, block lambda body, plain method | `xs.map(x -> { final t = x + 1; t; })` | accepted; product `Array(xs.size) { pipeline_index -> ... }` per `docs/specs/macros/01-functional-idiom-expansion.md` |
| 7 | same call in a constructor | same source | rejected, same TBlock error; the failing expression is the desugared `var _g = []; <fill>; _g` sequence |

Engine-port consequence: the port hand-writes fill loops in constructor
bodies (`engine-haxe/src/org/tiqian/layout/ParagraphDpLineBreaker.hx`
lines 215-226, five prefix arrays) and earlier port guidance banned array
comprehensions everywhere. This specification removes the need for both
the hand rewrite and the ban.

## Rulings

1. **Array comprehension is in the translatable subset.**
   `[for (x in 0...n) body]` desugars in the typed common layer into a
   result local, a fill loop, and a result read, and every target lowers
   that sequence through the same statement pipeline it applies to method
   bodies. The method-position acceptance that exists today is spec'd by
   this ruling; constructor bodies follow ruling 2.
2. **Constructor bodies receive the same passes as method bodies.** The
   default-argument expansion of `docs/specs/features/22-default-argument-expansion.md`,
   the pipeline idiom expansion of
   `docs/specs/macros/01-functional-idiom-expansion.md` and
   `docs/specs/macros/02-pipeline-idiom-additions.md`, and the statement
   pipeline the Kotlin renderer applies to method bodies all apply to
   constructor statements as well. `src/DefaultArgExpander.hx` line 1542
   already reads `cls.constructor`; the expansion and rendering paths must
   reach the same coverage.
3. **Block-bodied lambda literals are accepted pipeline arguments.**
   Recognition rule 1 of `macros/01` requires one inline function literal
   written at the call site and places no constraint on the body form;
   probe 6 shows the block statements inside the generated target lambda.
   This ruling quotes that clarification into `macros/01` in the same
   change that implements this spec.

## Implementation notes

- Candidate sites, in pass order: `src/Intercept.hx` line 485
  (`walkClassFields` covers `fields.get()` and `statics.get()`; the
  constructor lives in `classType.constructor`),
  `src/PipelineExpander.hx` lines 103-116, and the Kotlin renderer:
  constructor statements flow through `initBlockStatements`
  (`src/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx` lines 276-284),
  which renders per statement, while method bodies flow through
  `blockLines` (line 1151) with `fuseUninitializedVars`, `regroupLoops`,
  and `matchInterval` (line 640).
- The implementation change adds a constructor that fills an array
  comprehension and a constructor that calls one pipeline idiom with a
  block lambda body to the existing test trees under `tests/`, and
  records the exact files and line ranges in the Test hooks section
  below.

## Test hooks

The implementation change fills this section with the exact test files
and line ranges.
