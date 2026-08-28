# Macro spec 02: Pipeline idiom additions

## Scope

This specification adds six collection pipeline idioms to the closed list
of `docs/specs/macros/01-functional-idiom-expansion.md`. The mechanism is
unchanged: one typed expansion pass in the common layer, the same
recognition rules (one inline single-parameter function literal written at
the call site), the same position rule, the same `pipeline_` mint naming,
and the same chain handling. The three target compilers receive only loop
statements and never a function value. The downstream motivation is the
engine port audit of 2026-08-27: `firstOrNull` 38, `any` 33, `sumOf` 31,
`mapNotNull` 23, `flatMap` 20, and `all` 14 uses, each with a lambda that
never becomes a value.

`reduce` and `fold` stay outside the list. The engine port carries no use
of either, and the Haxe standard library holds no initial-less `reduce`,
so sanctioning them adds rejection rules without verification value.

## Added idioms

| Idiom | Accepted source | Product |
| --- | --- | --- |
| `any` | `arr.any(item -> pred)` | A false boolean mint, then a loop that stores `true` and breaks on the first match. |
| `all` | `arr.all(item -> pred)` | A true boolean mint, then a loop that stores `false` and breaks on the first non-match. |
| `firstOrNull` | `arr.firstOrNull(item -> pred)` | A `Null<T>` mint initialized to `null`, then a loop that stores the item and breaks on the first match. |
| `sumOfInt` | `arr.sumOfInt(item -> expr)` with `expr:Int` | An `Int` mint initialized to `0`, then a loop that adds the selector value. |
| `sumOfFloat` | `arr.sumOfFloat(item -> expr)` with `expr:Float` | A `Float` mint initialized to `0.0`, then a loop that adds the selector value. |
| `mapNotNull` | `arr.mapNotNull(item -> expr)` with `expr:Null<T>` | A compact push loop that stores the selector value in a minted local and pushes it when the local is not `null`. |
| `flatMap` | `arr.flatMap(item -> expr)` with `expr:Array<R>` | A compact push loop over the receiver with a nested loop over the selector value. |

`sumOf` carries two names because generic arithmetic does not unify: the
selector's return type picks the name, and the engine port maps each
Kotlin `sumOf` call to the matching one. An empty receiver yields `false`,
`true`, `null`, `0`, and `0.0` respectively, identically on every side.

The early exit is a `break` inside the hoisted loop, so no control flow
leaves the expansion and the position rule of `macros/01` applies
unchanged. Every product uses the `stdlib/04` array forms already ruled
for `map` and `filter`: pre-allocated fill where the count is known,
compact push where it is not.

A `flatMap` selector whose return type is not an `Array` is rejected with
the named error `flat map selectors return arrays only`. The other six
forms add no named error beyond the two frozen in `macros/01`.

## Stage-one oracles

`any`, `all`, `firstOrNull`, and `flatMap` declare as static extensions
routing to the Haxe standard library: `Lambda.exists`, `Lambda.foreach`,
`Lambda.find`, and `Lambda.flatMap`. These are real standard-library
implementations, the same evidence tier as `map` and `filter`.
`sumOfInt` and `sumOfFloat` route to one fold over `Lambda.fold`.
`mapNotNull` holds no standard-library match and runs a handwritten
extension body, the same weaker tier as `forEach` and `associate` in
`macros/01`; this specification records that tier honestly.

## Test hooks

- A sample module exercises each idiom, including the empty receiver, the
  no-match receiver, a `mapNotNull` selector returning `null` and non-null
  values, and a `flatMap` selector returning empty and mixed-length
  arrays.
- The four-side consistency run of `docs/specs/features/19-testing.md`
  compares the jsonl output.
- `tests/ts/` tree assertions move `.flatMap(`, `.some(`, and `.every(`
  from the samples ban list to the reference ban list: samples may now
  carry the source calls, and the generated trees must not. `.reduce(`
  and `.fold(` stay banned in samples.
- The mutation checks for this module live in the dispatch task file.
