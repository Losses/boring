# Standard library spec 07: std.SortedMap and std.SortedSet

## Scope

This specification is the keyed-lookup amendment that
`docs/specs/style/01-haxe-style-standard.md` rule 2 reserves: `haxe.ds.Map`
stays banned (`V13 HashMapCollection`), and the sanctioned structure is
the immutable sorted table named here with its per-platform shape. The
behavioral baseline is ordered-collection semantics: iteration ascends by
key, lookups are deterministic, and no hash order is observable on any
target. The grounding is the consumer audit of the tiqian engine
(2026-08-27): of 41 mutable Map/Set declarations in its layout core, 40
are function-local values built once and then read by exact key or in
ascending index order, and the single long-lived mutable map is a
bounded memoization cache; no unordered iteration reaches output. The
structure this specification rules serves exactly that dominant
population: build once, then read.

Hash-based maps are deliberately absent. An immutable comparison-based
table needs no hash function, no seeding, and no per-platform hash discipline;
ordering is the contract. If a mutable keyed cache ever enters the
subset, its hashing rules get their own amendment at that time.

## Contract

`std.SortedMap<K, V>` and `std.SortedSet<K>` are immutable sorted
collections:

1. **Build once, then read.** A builder receives `put` calls; `build()`
   returns the immutable table. After `build()`, no member can modify the
   collection; the types expose none.
2. **Ordering.** Keys ascend. `Int` keys order numerically.
3. **Duplicate keys.** A later `put` with an equal key replaces the
   earlier entry; exactly one entry per distinct key survives `build()`.
4. **Iteration by index range.** The collections expose `size():Int`,
   `keyAt(index:Int):K`, `valueAt(index:Int):V` (map only), and
   `at(index:Int):K` (set only). Iteration is
   `for (i in 0...table.size())`, the only sanctioned iteration form
   (`V01`); insertion order and hash order are never observable.
5. **Lookup.** `get(key:K):Null<V>` (map), `has(key:K):Bool` (both).
   Lookup is comparison-based; equal keys found by binary search.

Immutable tables are values: building two tables with the same entries
yields equal reads at every index. The tables carry no identity
semantics beyond their contents.

## Haxe declarations and routing

`samples/std/SortedMap.hx` and `samples/std/SortedSet.hx` declare the
modules as externs in the established std pattern
(`docs/specs/stdlib/06-std-modules.md`): builder construction, `put`,
`get`, `build`, and the immutable read members. The builder's
`get(key):Null<V>` reads its pending state and serves the group-by
expansion of `docs/specs/macros/03-group-by-idiom.md`. References route through each
target's import table into the runtime package, exactly as `std.Console`
routes; neither the `std.` namespace nor a Haxe collection type appears
in any output.

This dispatch implements `Int` keys end to end. Two key domains are ruled
and deferred:

- **Structure keys**: the comparison is field-lexicographic over the
  structure's fields in declaration order, and the compiler generates
  the per-type comparison from the typed AST into the output tree,
  following the type-directed-helper ruling of
  `docs/specs/features/19-testing.md` (no name-keyed tables, no sample
  type names in compiler source; Kotlin overloads, Rust concrete
  functions, TypeScript the same generated module). Sample source never
  passes a function value; the comparison binds at the call site during
  emission.
- **String keys**: ordering must be identical across targets, and
  UTF-16 code-unit order (JavaScript) differs from code-point order
  (Rust byte order) astral to the BMP. Ruled 2026-08-27: the order is
  **UTF-16 code-unit order**. Code-unit order is the native string
  comparison of the TypeScript runtime, the Kotlin runtime, and the
  Haxe stage-one JavaScript shims, so those sides compare with their
  platform operators and add no emulation. The Rust runtime stores
  keys as UTF-8 and emulates the order with one rule: compare bytes,
  and at the first differing byte, invert the byte-order result when
  one side starts a four-byte sequence (an astral code point) and the
  other side holds a three-byte sequence at or above U+E000; UTF-8
  byte order equals code-unit order everywhere else. The common case
  is a byte comparison plus a branch. Keys must be valid Unicode
  scalar sequences: lone surrogates are representable on UTF-16
  targets but not in Rust strings, and no cross-target order is
  defined for them.

## Per-platform shapes

The immutable representation is parallel storage sorted by key on every
target; the builder's internal scaffolding is the runtime's own:

| Target | Immutable shape | Lookup |
| --- | --- | --- |
| Rust | struct with `keys: Vec<i32>` and `values: Vec<V>` in the runtime crate's `sortedmap` module | `keys.binary_search` |
| TypeScript | sorted `number[]` keys and aligned `V[]` values in the runtime package | binary search over the keys array |
| Kotlin | `IntArray` keys and aligned values array in the runtime shim | binary search |

Builders accumulate entries and sort at `build()`, which applies the
last-put-wins rule and produces the aligned arrays. Build-time
scaffolding may use platform natives; iteration order of that
scaffolding never escapes `build()`.

The runtime code lives where `docs/specs/stdlib/06-std-modules.md`
places it: `TsRuntime.SOURCE`, the `KotlinRuntime` shims, and the Rust
runtime module, emitted on demand behind the same `runtime-import` and
`runtime-emit` defines, with the same missing-define error contract.

## Samples and tests

A sample in `samples/boring/` builds a code-point-keyed table from
literals through a builder, and serves exact-key lookups and one
ascending scan from the immutable result. Under the testing standard
`docs/specs/features/19-testing.md`, `samples/tests/` gains `std.Test`
cases covering: hit and miss lookups, boundary keys at the first and
last slot, last-put-wins on a duplicate key, `size` after
replacement, and ascending `keyAt` order asserted against a hand-written
expected sequence. Cross-target equality runs through the consistency
manager.

Mutation evidence follows the testing standard: renaming a test
function, changing a description, changing an assertion literal, and
reordering a test-local structure's fields each change the regenerated
output on every target.

## Bans restated

`haxe.ds.Map` and its implementations remain `V13`. `std.SortedMap` and
`std.SortedSet` are the keyed structures of the subset; a sample that
needs keyed lookup uses them, and a sample that needs a mutable
long-lived keyed cache has no structure yet and stops at this
specification until one is ruled.
