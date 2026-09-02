# Macro spec 05: Indexed pipeline idioms

## Scope

This specification adds two indexed collection pipeline idioms to the
closed list of `docs/specs/macros/01-functional-idiom-expansion.md` and
`docs/specs/macros/02-pipeline-idiom-additions.md`. The mechanism is
unchanged: one typed expansion pass in the common layer, the same
position rule, the same `pipeline_` mint naming, and the same chain
handling. The targets receive only loop statements and never a function
value.

Demand evidence (engine port audit, filed 2026-09-02): `forEachIndexed`
32 uses, `mapIndexed` 19 uses, and `withIndex` 1 use, fifty-two uses
across ten layout source files, the largest being
`PreparedParagraph.kt` 12, `AnnotationGeometryStage.kt` 8,
`WidthIndependentAnnotationCache.kt` 7, and `PunctuationGeometryStage.kt`
5. `macros/01` included `associate` at 19 uses and `sortedBy` at 8 uses
on the same audit basis. Every exclusion recorded in those specs carries
a reason (`groupBy`: no ordered multimap contract; `let`/`also`/`apply`:
no standard-library oracle; `reduce`/`fold`: no engine-port use). The
indexed family carries no recorded reason, and this spec fills that gap.

Status: Proposed.

## Added idioms

| Idiom | Accepted source | Product |
| --- | --- | --- |
| `forEachIndexed` | `arr.forEachIndexed((index, item) -> body)` | The `features/09` loop form with an integer index binding and the element binding, declared in the source parameter order. |
| `mapIndexed` | `arr.mapIndexed((index, item) -> body)` | The `stdlib/04` pre-allocated fill with the index binding and the element binding: Kotlin `Array(count) { index -> ... }`, TypeScript indexed stores, Rust fill loop with the counter. |

The parameter order is `(index, item)`, matching the Kotlin originals
the port translates (`mapIndexed(transform: (index: Int, T) -> R)`). The
`withIndex` source shape ports to these two idioms.

## Recognition and hygiene

The accepted-shape sentence of `macros/01` ("exactly one parameter")
gains the two-parameter exception for exactly these two idioms; the
amendment is quoted into `macros/01` in the implementing change. All
other recognition rules, the position rule, and the mint and
parameter-reuse rules of `macros/01` apply unchanged, with the index
binding and the element binding both reused verbatim.

`forEachIndexed` and `mapIndexed` do not exist on Haxe `Array`. They are
declared as static extensions in `samples/std/` and the haxe stage-1 side
runs implementations injected in the `TestCollector` bootstrap shim, the
same weaker evidence tier recorded in `macros/01`.

## Test hooks

- A sample module demonstrates both idioms, chains included, with a
  `describe`-style function per idiom.
- `samples/tests/` additions cover: index order, capture of enclosing
  locals, shadowing (an index parameter named like an outer local), and
  nested loops.
- `tests/ts/` tree assertions pin the products: the generated trees
  contain the loop and fill forms and contain no `.mapIndexed(` or
  `.forEachIndexed(` call site; the sample source keeps the closed-list
  forms.
