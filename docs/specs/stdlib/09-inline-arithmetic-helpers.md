# Standard library spec 09: Inline arithmetic and range-check helpers

## Scope

This specification records the sanctioned static inline helper functions for
arithmetic shorthands that the engine port brings over: range checks,
clamping, and two-field range values. Every helper is a static inline function
declared in `samples/std/`; the haxe compiler inlines the body at each call
site in the common layer, so every target receives the expanded expression and
no helper name survives to emission. No per-platform implementation and no
runtime module exist for anything in this specification. `Math.min` and
`Math.max` stay haxe standard library calls where a port needs them.

## Sanctioned helpers

| Helper | Type | Expansion |
| --- | --- | --- |
| `within(value, low, high)` | `(T, T, T) -> Bool` | `value >= low && value <= high` |
| `coerceAtLeast(value, floor)` | `(T, T) -> T` | `value < floor ? floor : value` |
| `coerceAtMost(value, ceiling)` | `(T, T) -> T` | `value > ceiling ? ceiling : value` |
| `coerceIn(value, low, high)` | `(T, T, T) -> T` | `coerceAtMost(coerceAtLeast(value, low), high)` |
| `IntRange` | structure typedef | `{ start:Int, end:Int }` with `inline contains(value:Int):Bool` expanding to `within(value, start, end)` |

The helpers are expression-level and pure: each body is one comparison, one
conditional, or one composition of those. The helper list is frozen; no
helper joins this module without a specification amendment.

## Generic instantiation

Each helper is one generic static inline function. The type parameter
instantiates at `Int` or `Float` per call site, and inlining happens per
instantiation in the common layer, so the targets receive the expanded
comparisons and conditionals for the concrete type. `IntRange` holds `Int`
fields only.

## Port notes

Descending and stepped loops (`downTo`, `step`) are written as `while` loops
per `docs/specs/features/09-iterators.md`; no loop-head sugar is sanctioned.
The half-open Kotlin range `0 until count` writes as the haxe range
`0...count` directly. Inclusive iteration over `a..b` writes `a...(b + 1)`.
A range stored as a value uses the `IntRange` typedef above.

## Test hooks

A sample module calls each helper on `Int` and `Float` and reads
`IntRange.contains`. `tests/ts/` tree assertions confirm the generated trees
contain no helper call sites: every use appears as the expanded comparison or
conditional. The four-side consistency run of
`docs/specs/features/19-testing.md` compares the jsonl output. The mutation
checks for this module live in the dispatch task file.
