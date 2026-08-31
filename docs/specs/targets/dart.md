# Target spec: Dart

## Scope

This specification rules the translation of the translatable subset into
Dart for the boring repository. It binds the Reflaxe generator that emits
the Dart target the same way the in-document Kotlin rulings bind the
Kotlin generator. Construct semantics, typed-AST shapes, and the
Haxe-side restrictions live in the `features/`, `macros/`, and `stdlib/`
specifications; this document adds the Dart column and cross-references
them by number.

The toolchain is the Dart SDK 3.13 (`dart run` for the test entry). The
language features used come from the core libraries only: `dart:collection` for the
splay trees and `dart:typed_data` where a fixed-width view is needed.

## Facts the rulings cite

Verified on this toolchain:

- `String.compareTo` compares UTF-16 code units with no
  canonicalization: `"\u{00E9}".compareTo("e\u{0301}")` is `1`, matching
  the unit sequence `[233]` against `[101, 769]`.
- `String.length` and `codeUnitAt` are constant-time UTF-16 unit access;
  `runes` iterates code points.
- `SplayTreeMap` and `SplayTreeSet` of `dart:collection` iterate in key
  order and expose `firstKey` and `lastKey`.
- A sealed class hierarchy plus a `switch` expression with object
  patterns is exhaustive at compile time.
- `int` is 64-bit signed on the VM: `4000000000 + 4000000000` is
  `8000000000`, with no 32-bit wrap.
- `List.filled` allocates a fixed-length list in one step;
  `StringBuffer` appends amortized.
- String interpolation and `print` need no imports.

## Module and name mapping

Each Haxe module becomes one Dart library file under the package path,
with relative imports between them. Dart allows top-level functions and
variables, so a Haxe class with only statics lowers to top-level
functions in a library named after the module, without a wrapper class.
Every import binds a prefix taken from the referenced file's stem, so
top-level names of two modules never collide inside one file.

Residents are the exception to the flattening: the runtime library and
the test host each merge several resident modules into one file, and
their flattened top-level names would collide (`UString.count` against
`Graphemes.count`), so resident classes keep the class form.

| Haxe | Dart |
| --- | --- |
| module `boring.VectorCodec` | file `lib/boring/vector_codec.dart` |
| static function | top-level function |
| class instance code | `final class` |
| package path | directory path of the library |
| visibility | public by default; underscore prefix for internal |

## Numbers (`features/07`, `features/14`)

Haxe `Int` maps to `int`; Haxe `Float` maps to `double`.

### Candidates

1. `int` and `double` as the two Haxe types.
2. `int` with 32-bit masking at every arithmetic site.

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| 1 (`int`) | VM integers are unboxed machine words in locals and fields; no masking arithmetic runs. | `int` is 64-bit, wider than the i32 domain, exactly as `number` is wider on the TypeScript lane; the `features/14` rulings enforce the domain and the type adds none. | One mapping with no call-site conversions. | Readers see the language's own integer. |
| 2 (masked) | Every arithmetic site executes an extra `& 0xFFFFFFFF`. | Same width question, now hidden behind masks. | The mask repeats across every expression. | Masked arithmetic reads as a wrapping semantics the samples never use. |

### Ruling

Candidate 1. The TypeScript lane already carries a wider-than-i32
integer and relies on the domain rulings to keep values in range; Dart
matches that precedent. Wrapping that `features/14` never permits is
absent on both lanes for the same reason. Two operators are the
structural exception: `<<` and `>>>` produce results outside i32 on a
64-bit word even from in-range operands, so each lowers with the domain
restore attached (`(... << n).toSigned(32)` and
`(... .toUnsigned(32) >> n).toSigned(32)`), the wrap targets with a
native 32-bit integer perform in hardware. The `float-precision` define
of `features/23` is rejected at plugin registration on this lane: Dart
has one storage width for reals (`double`), so an f32 variant cannot
change result bits. A compile with `-D float-precision=f32` fails with
`float-precision=f32 is not available on the Dart target: double is the
one real storage width; compile without the define for f64 semantics`
before any type rendering; `tests/dart/precision-switch.test.ts` pins
the rejection.

## Enums and pattern matching (`features/01`)

Haxe enums map to a `sealed class` hierarchy: one subclass per
constructor, payload fields on the subclass, a private base constructor.
Pattern matching lowers to `switch` expressions with object patterns and
is exhaustive without a default arm.

```dart
sealed class UStringFault {
  const UStringFault();
}

final class InvalidCodePoint extends UStringFault {
  final int code;
  const InvalidCodePoint(this.code);
}

final class UnpairedSurrogate extends UStringFault {
  final int unit;
  const UnpairedSurrogate(this.unit);
}
```

A value enumeration (every constructor declares zero parameters, the
parameterless amendment of `features/01`) maps to an enhanced enum: one
constant per constructor, a `final String label` field holding the
constructor name spelled in Haxe source, a `const` constructor assigning
it, and the built-in `values` list. Construction sites reference the
constants (`FloatWidth.f64`), the constants compare by canonical
instance, and the `label` field is the constructor-name read of
`features/28-enum-value-queries.md`.

```dart
enum FloatWidth {
  f64("F64"),
  f32("F32"),
  f16("F16");

  final String label;
  const FloatWidth(this.label);
}
```

Payload captures lower to `InvalidCodePoint(code: var code)`; unused
payloads capture an underscore name; guards lower to `if` guards;
or-patterns expand to comma-joined cases.

## Null and optionality (`features/04`)

`Null<T>` maps to `T?` with the sound null-safety the language enforces.
Sentinel returns that the residents define stay plain `int`, never
optionals, matching the resident ABI of the other lanes.

## Arrays (`stdlib/04`)

`List<T>`; a pre-allocated fill lowers to `List<T>.filled(n, filler)`
with indexed stores, one allocation. Read-only arrays (`features/18`)
map to a `List` bound through `List.unmodifiable` when the samples hand
it across a boundary, and to a plain `final` reference when it stays
inside one module.

## Strings

Haxe `String` maps to `String`. UTF-16 is the native storage: `length`
is the unit count, `codeUnitAt` is the unit read, `substring` is the
unit-range cut. Code point access goes through `String.fromCharCode`
with surrogate combination where a pair is present, the same shape the
TypeScript lane lowers into `codePointAt`.

### Resident string ABI (`stdlib/10`, `stdlib/11`)

`std.UStringPlatform` lowers inline with the cursor space of UTF-16
units: `end` is `s.length`, `codeAt` combines a surrogate pair when
present, `advance` is the pair width, `substringBetween` is
`s.substring(a, b)`, `fromCodePoint` is `String.fromCharCode` over one
or two units. Dart has no `codePointAt`, so the pair-combining read is
a private `_codePointAt(String, int)` top-level function that every
library inlining the walk carries (the runtime prelude and the test
host). Every primitive is constant time, so the resident walks
stay one linear pass.

### String ordering

`<` and friends on `String` lower to native `compareTo`-based
comparisons: Dart compares code units with no canonicalization, which is
the UTF-16 unit order the sorted tables rule (`stdlib/07`), so no helper
runs.

### String buffer (`stdlib/08`)

The buffer is `List<int>` over the UTF-16 units: the dangling unit is
`buf[buf.length - 1]`, `add` emits the pairing check of `stdlib/08` and
appends through `addAll(part.codeUnits)`, `addChar` emits the trail
check and appends one unit, and `toString` emits the dangling-lead
check and builds through `String.fromCharCodes(buf)`. The fault is the
sealed `UStringFault` hierarchy above.

## Errors and faults (`features/06`)

Fault hierarchies and exception classes are plain Dart classes; `throw`
lowers to `throw`; try-regions lower to `try`/`on`/`catch` with the
typed `on UStringException catch (error)` form. The statement, return,
initializer, and handler-return positions all lower; value regions bind
a late-assigned local through both arms, because `try`/`catch` is a
statement cluster. This matches the TS and Kotlin lanes mechanism for
mechanism.

## Sorted tables (`stdlib/07`)

`std.SortedMap` and `std.SortedSet` compile the resident
`runtime.SortedTable` classes into the emitted runtime library
(`SortedMapTable` and `SortedSetTable` with their builder faces), the
same resident-source ruling the Swift lane carries: the splay trees of
`dart:collection` expose no builder face over shared storage and their
iteration order, while key-ordered, gives no structural-equality handle
for the consistency run. The comparator tears off
`compareUnitOrder` for the String key domain and the generated
`compare<Record>` functions for structure keys; the endpoints and the
insert-then-build shape of the extern are the resident classes' own.
No hand-written table ships in the generated business tree.

## Iteration and loops (`features/09`, `features/15`)

`for (i in 0...n)` lowers to `for (var i = 0; i < n; i++)` (inclusive
form with `<=`); `while` and `if` map directly; `break` and `continue`
map natively. The closed-list pipeline idioms (`macros/01`, `macros/02`)
lower to `for` loops with the inline closure body inlined as statements,
one pass, no intermediate list; `groupBy` (`macros/03`) builds through
the splay-tree map.

## Static extension and dispatch (`features/10`, `features/12`)

Static extension calls lower to direct top-level calls in the library of
the resolving module. Classes keep their methods; the samples contain no
subclassing, so `final class` throughout costs nothing.

## Generics (`features/05`)

Dart generics reify type arguments and specialize in the VM's optimizing
compiler for monomorphic call sites; the sorted tables pass through
their type arguments unchanged. The generic use in the sample tree is the
tables and the pipeline idioms, both covered.

## Testing (`features/19`)

`@:test` statics collect into a test entry `main()` that runs each test
in order, catches thrown values, records the pass or fail line to the
jsonl results file the consistency run reads, and exits nonzero on any
failure. `std.TestPlatform` lowers inline: `raise` is `throw`,
`currentTestId` reads a top-level variable the harness sets around each
test, and number-to-text rendering uses interpolation. The entry runs
under `dart run`.

## Status

Rulings complete for the constructs the sample tree exercises, and the
generator implementing them ships in the verify chain: `gen:dart`
regenerates the tree, `test:dart` runs it, and the consistency run
reads the Dart jsonl alongside the other five targets.
