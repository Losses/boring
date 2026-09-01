# Standard library spec 07: std.SortedMap and std.SortedSet

## Scope

This specification is the keyed-lookup amendment that
`docs/specs/style/01-haxe-style-standard.md` rule 2 reserves: `haxe.ds.Map`
stays banned (`V13 HashMapCollection`), and the sanctioned structure is
the immutable sorted table named here with its per-platform shape. The
behavioral baseline is ordered-collection semantics: iteration ascends by
key, lookups are deterministic, and no hash order is observable on any
target. The grounding is the consumer audit of the tiqian engine:
of 41 mutable Map/Set declarations in its layout core, 40
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
expansion of `docs/specs/macros/03-group-by-idiom.md`. The Rust builder
`get` returns an owned clone of the stored value; the TypeScript and
Kotlin builders return the stored reference. References route through each
target's import table into the runtime package, exactly as `std.Console`
routes; neither the `std.` namespace nor a Haxe collection type appears
in any output.

Every ruled key domain lowers through the same resident; none is
deferred:

- **Structure keys**: the comparison is field-lexicographic over the
  structure's fields in declaration order, and the compiler generates
  the per-type comparison from the typed AST into the output tree,
  following the type-directed-helper ruling of
  `docs/specs/features/19-testing.md` (no name-keyed tables, no sample
  type names in compiler source; Kotlin overloads, Rust and TypeScript
  the same generated function). Sample source never passes a function
  value; the comparison binds at the call site during emission.
- **String keys**: ordering must be identical across targets, and
  UTF-16 code-unit order (JavaScript) differs from code-point order
  (Rust byte order) astral to the BMP. The order is
  **UTF-16 code-unit order**. The resident `compareStrings` walks both
  strings by code point and applies one adjustment at the first
  differing code point: when one side is astral (at or above U+10000)
  and the other side is a BMP code point at or above U+E000, the
  astral side sorts first, because its leading surrogate
  (U+D800..U+DBFF) sorts below every unit at or above U+E000. Unit
  order and code-point order agree at every other differing pair. The
  walk advances by code point, so every target reads the same
  sequence: the cursor primitives come from `std.UStringPlatform`, and
  each target compiles them to its native string representation.
  Keys must be valid Unicode scalar sequences: lone surrogates are
  representable on UTF-16 targets but not in Rust strings, and no
  cross-target order is defined for them.

## Single-source runtime

`src/runtime/SortedTable.hx` is the one implementation. It compiles as a
resident module: the class `SortedTable` holds the domain comparators
(`compareInts`, `compareStrings`) and the builder factories
(`mapBuilder`, `setBuilder`); `SortedMapTable<K, V>`,
`SortedMapTableBuilder<K, V>`, `SortedSetTable<K>`, and
`SortedSetTableBuilder<K>` hold the storage. The extern faces
`std.SortedMap` and `std.SortedSet` keep their names on every target;
each target lowers references to them onto these classes.

Storage is generic parallel arrays on every target: `Array<K>` and
`Array<V>`, sorted at `build()` through an index-permutation insertion
sort that applies the last-put-wins rule per equal-key run. The sort
permutes entry indices, so values of parameter type are only read,
never moved. Kotlin boxes integer keys this way; the retired
hand-written shim held an `IntArray`. The cost is one object per
integer key inside a table, accepted for one source. The comparator is
a function value bound when the builder is created: the resident
integer comparator, the resident string comparator, or the per-type
generated structure comparator. On Rust, the table members borrow their
key and value parameters (`&K`, `&V`) and clone inside, `size` returns
`i32`, and the call boundary converts between the resident `i32` domain
and the business unsigned domain.

The stage-one Haxe run binds the same resident: `TestCollector`
injects the compiled `runtime.SortedTable` class and builds
`globalThis.std.SortedMap` and `globalThis.std.SortedSet` factories on
it, so the intercepted JavaScript exercises the one implementation;
no handwritten copy remains. The resident enters each target behind
the same `runtime-import` and `runtime-emit` defines as the rest of
the runtime package, with the same missing-define error contract.

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

### Swift target rulings

#### Sorted tables (`stdlib/07`)

The resident `runtime.SortedTable` compiles through this target like any
other module: it stores alternating key and value arrays and binary
searches with the comparator passed in. The comparator for `String` keys
is the unit-order helper of the ordering ruling, which is what aligns
iteration order with the BTreeMap order the other targets share. No
hand-written Swift table ships.

### Dart target rulings

#### Sorted tables (`stdlib/07`)

`std.SortedMap` and `std.SortedSet` compile the resident
`runtime.SortedTable` classes into the emitted runtime library
(`SortedMapTable` and `SortedSetTable` with their builder faces), the
same resident-source ruling the Swift target carries: the splay trees of
`dart:collection` expose no builder face over shared storage and their
iteration order, while key-ordered, gives no structural-equality handle
for the consistency run. The comparator tears off
`compareUnitOrder` for the String key domain and the generated
`compare<Record>` functions for structure keys; the endpoints and the
insert-then-build shape of the extern are the resident classes' own.
No hand-written table ships in the generated business tree.
