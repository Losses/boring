# Target spec: Swift

## Scope

This specification rules the translation of the translatable subset into
Swift for the boring repository. It binds the Reflaxe generator that emits
the Swift target the same way the in-document Kotlin rulings bind the
Kotlin generator: every construct the translatable subset exercises arrives with its
translation decision written down before the generator implements it.
Construct semantics, typed-AST shapes, and the Haxe-side restrictions live
in the `features/`, `macros/`, and `stdlib/` specifications; this document
adds the Swift column and cross-references them by number.

The toolchain is `swiftc` 5.10 without Foundation: the dev shell carries no
Foundation for the Linux target, so every ruling below uses the Swift
standard library only. A linked Swift binary resolves `libswiftCore`
through its `RUNPATH`, which loads `libdispatch`; the test entry runs with
`LD_LIBRARY_PATH` set to `BORING_SWIFT_LIBDISPATCH` from the dev shell.

## Facts the rulings cite

Measured or compile-verified on this toolchain:

- `String` comparison operators implement Unicode canonical ordering, not
  UTF-16 code unit order: `"\u{212B}" < "A\u{030A}1"` is `true` natively
  and `false` unit-wise.
- `String.UTF8View` and `String.UTF16View` are bidirectional collections
  with opaque indices: `index(_:offsetBy:)` walks from its argument,
  integer-indexed subscripts do not exist, and `index(after:)` costs one
  step. `utf16.count` and `utf8.count` are stored, constant-time.
- A native `String` cannot hold an unpaired surrogate: scalar construction
  rejects the surrogate range.
- Value enums carry associated values with no heap allocation, and a
  `switch` over a resident enum without a default arm enforces
  exhaustiveness at compile time.
- `Result`, `Optional`, and `String(decoding:as:)` exist in the standard
  library without Foundation.
- `Int32` and `UInt32` arithmetic trap on overflow; the wrapping
  operators `&+`, `&-`, `&*` wrap.
- `UInt32.init(_: Int32)` traps on a negative argument; it does not
  reinterpret bits. Unsigned reinterpretation goes through
  `UInt32(bitPattern:)` and `Int32(bitPattern:)`.
- A typed catch pattern (`catch let error as C`) never makes a
  `do`/`catch` cluster exhaustive; only a bare final `catch` arm does.
- `try` scopes a whole expression: `total = try total + parse(s)` is the
  legal spelling of a throwing call nested inside an operator, and `try`
  on a subexpression to the right of an operator is rejected.
- Appending to a uniquely referenced `String` amortizes to constant time
  per append through storage regrowth.

## Module and name mapping

One Swift module holds the generated business tree, so cross-module
references need no imports. Haxe modules become one Swift file each.
Top-level statics attach to a case-less `enum` namespace named after the
Haxe class, because Swift has no file-level static members.

| Haxe | Swift |
| --- | --- |
| module `boring.VectorCodec` | file `boring/VectorCodec.swift`, `enum VectorCodec` namespace |
| class instance code | `final class` |
| static function | `static func` on the namespace enum |
| package path | directory path of the file |
| visibility | `public` for used-elsewhere declarations, `internal` otherwise |

## Numbers (`features/07`, `features/14`)

Haxe `Int` maps to `Int32`; Haxe `Float` maps to `Double`.

### Candidates

1. `Int32` and `Double` for the two Haxe types.
2. `Int` (the word-sized signed integer) and `Double`.
3. `Int32` with wrapping operators everywhere arithmetic occurs.

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| 1 (`Int32`/`Double`) | Register-width on every ABI Apple and Linux expose for `Int32`; no conversion at codec boundaries that already carry 32-bit fields. | The 32-bit domain of `features/14` is visible in the type; widening or narrowing is explicit. | One mapping, no call-site conversions. | Readers see the wire width in the type name. |
| 2 (`Int`) | Word arithmetic avoids sign-extension on array indexing. | The 64-bit range silently admits out-of-domain values; overflow traps differ from every other lane. | Boundary code must mask to keep the domain, duplicating the check per site. | The wire width disappears from the type. |
| 3 (wrapping operators) | Same as 1. | Conforming source never leaves the i32 domain, so the wrapping behavior is dead code that contradicts `features/14`. | Every arithmetic site carries a marker no lane needs. | `&+` reads as a deliberate wrap, which the samples never perform. |

### Ruling

Candidate 1. `Int32`/`Double`, trapping operators. The domain rulings of
`features/07` and `features/14` keep every value inside i32, so traps are
unreachable on conforming source and cost nothing. The `float-precision`
define of `features/23` switches this lane through a define-gated type
table, the same shape as the Kotlin ruling: `Float` maps to `Double` on
the default lane and to `Float` under `f32`, in the type table and the
test assertion tags together. Swift float literals carry no suffix; they
are type-directed, so the f32 lane names the type on every declaration
whose initializer would otherwise infer the default `Double` width
(`var x = 0.0` becomes `var x: Float = 0.0`). `Math` constants read from
the `Float` family (`Float.nan`, `Float.infinity`,
`-Float.infinity`); the arithmetic and rounding members (`+`,
`.rounded(.down)`, `.squareRoot()`, `.isNaN`) come from the
`FloatingPoint` protocol both types implement, so they follow the type
table with no separate dispatch. The `FPHelper` value-edge calls dispatch
to the runtime wrappers `i64ToF32` and `f32ToI64` (feature spec 23,
ruling 7). `examples/swift-f32.hxml` generates the f32 tree; the verify
lanes are `gen:swift-f32` and `test:swift-f32`.

## Enums and pattern matching (`features/01`)

Haxe enums map to Swift value enums with labeled associated values.

```swift
enum UStringFault: Equatable {
    case invalidCodePoint(code: Int32)
    case unpairedSurrogate(unit: Int32)
}
```

Payload captures lower to `case .invalidCodePoint(let code)`; a
multi-arm switch over the enum is exhaustive without a default arm;
unused payloads bind `case .unpairedSurrogate(_)`. Guards lower to
`where` clauses. Or-patterns expand to comma-joined case labels.

## Null and optionality (`features/04`)

`Null<T>` maps to `Optional<T>`; optionals of value types occupy a
register plus a tag bit with no heap box. Sentinel returns that the
residents define (negative cursor bounds, the `-1` no-previous marker)
stay plain `Int32` and never become optionals, matching the resident ABI
of the other lanes.

## Arrays (`stdlib/04`)

`Array<T>` with `reserveCapacity` before counted fills; a pre-allocated
fill lowers to `[T](repeating:count:)` followed by indexed stores, one
allocation. Read-only arrays (`features/18`) map to `let` bindings of
`Array<T>`; `let` enforces the element-mutation ban with no wrapper
type.

## Strings

### Business strings

Haxe `String` maps to `String`. Concatenation and interpolation are
native. The `length` property is UTF-16 code unit count
(`utf16.count`, constant time). `charCodeAt` lowers to a unit read
through the UTF-16 view at an advanced index; business code uses it only
on the ASCII tier where the index walked in already, and the residents
never use it.

### Ordering

Native `<` on `String` implements canonical ordering and disagrees with
the UTF-16 code unit order the sorted tables rule (`stdlib/07`). Haxe
`<`, `>`, `<=`, `>=` on `String` therefore lower to a comparison
helper emitted once in the runtime text that walks both UTF-16 views in
lockstep and compares units. Equality stays native `==`, which is
canonicalization-preserving and agrees with unit order on equal-length
unit sequences; the samples compare keys for order and content
separately, and only order needs the helper.

### Resident string ABI (`stdlib/10`, `stdlib/11`)

The resident modules (`runtime.UString`, `runtime.Graphemes`,
`runtime.GraphemeWalk`, `runtime.TestCore`) receive strings as
`Array<UInt16>` inside the runtime package: the cursor space is UTF-16 units, `end` is `count`,
`codeAt` is an integer subscript, and `advance` is the surrogate-pair
width at the cursor, each constant time. `std.UStringPlatform` calls
lower inline against that array. Business call sites that hand a string
to a resident convert once (`Array(text.utf16)`), so a walk is one
decode pass followed by constant-time indexing, the decode-once tier of
the design principles. `substringBetween` builds
`String(decoding: units[a..<b], as: UTF16.self)`; `fromCodePoint`
encodes the scalar into units, and an argument outside the documented
valid domain yields the NUL replacement, the same out-of-domain
behavior the Rust lane's `char::from_u32` fallback takes.

### String buffer (`stdlib/08`)

The buffer is `Array<UInt16>`, the same ruling as the Rust `Vec<u16>`:
a native `String` cannot store the unpaired lead the fault paths must
observe. `add` and `addChar` emit the boundary and pairing checks
reading the last unit by integer subscript; `toString` emits the
dangling-lead check and `String(decoding: buf, as: UTF16.self)`.

## Errors and faults (`features/06`)

Fault enums conform to `Error`; the runtime emits one non-`final` base
class `BoringException: Error` carrying `message`, and each exception
class is a `final class` subclass of it carrying the fault field (a
`final` base forbids the subclass the class ruling needs). `throw`
lowers to `throw`; try-regions lower to `do`/`catch` with a typed
pattern (`catch let error as UStringException`) plus a final bare
`catch { throw error }` arm, because a typed pattern never exhausts;
the rethrow arm makes the enclosing function throwing exactly when the
other lanes' unmatched-error rethrow does, and a handler that never
reads the binding emits `catch is UStringException`. The statement,
return, initializer, and handler-return positions all lower: value
regions declare the binding and assign it in both arms, because
`do`/`catch` is a statement cluster and not an expression. `try` prefixes
the whole expression of the statement once, per the fact above, not
each callee.

### Candidates

1. `throw` with typed catch, as above.
2. `Result<Value, Fault>` return types with `try`-free propagation.

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| 1 (throw) | An unwritten `throw` path costs nothing at call sites; the thrown value crosses as an error register and is boxed only on the cold fault path. | The fault type at the catch site is a cast pattern the compiler checks. | One mechanism, matching the TS and Kotlin lanes. | `do`/`catch` with a typed pattern reads as the language's own error shape. |
| 2 (Result) | `Result` is a value enum with no box, but every caller unpacks through `switch` or `try!`, adding a match at each call. | Unhandled results type-check until read. | Every signature and call site carries the type, diverging from two of three existing lanes. | Chains of `Result` plumbing read as bureaucracy next to `throw`. |

### Ruling

Candidate 1. Faults are cold paths; the hot path pays nothing, and the
fault identity (never the message) crosses exactly as in `features/06`.

## Sorted tables (`stdlib/07`)

The resident `runtime.SortedTable` compiles through this lane like any
other module: it stores alternating key and value arrays and binary
searches with the comparator passed in. The comparator for `String` keys
is the unit-order helper of the ordering ruling, which is what aligns
iteration order with the BTreeMap order the other lanes share. No
hand-written Swift table ships.

## Iteration and loops (`features/09`, `features/15`)

`for (i in 0...n)` lowers to `for i in stride(from: a, to: b, by: 1)`
on the `Int32` operands (the inclusive form widens `to` by one):
`stride` yields an empty range when the bound precedes the start,
matching the `i < n` test the Haxe loop runs, while `a..<b` traps when
`b < a` and a decoded count of `-1` reaches that path. `while` and `if`
map directly. `break` and `continue`
map natively. The closed-list pipeline idioms (`macros/01`, `macros/02`)
lower to `for` loops over the array with the inline closure body inlined
as statements, one pass, no intermediate array; `groupBy` (`macros/03`)
builds through the sorted-table builder.

## Static extension and dispatch (`features/10`, `features/12`)

Static extension calls lower to direct calls on the namespace enum of
the resolving module: no protocol requirement, no dynamic dispatch.
Classes keep their virtual methods as Swift `class` methods; the sample set
has no subclassing, so `final class` throughout costs nothing.

## Generics (`features/05`)

Swift generics specialize under optimization for monomorphic call sites
and fall back to witness-table dispatch otherwise; generic values of
value type stay unboxed through both paths. The generic use in the sample
tree is the sorted tables and the pipeline idioms, both monomorphic at their
call sites, so the specialized code is what runs. Type arguments pass
through unchanged.

## Testing (`features/19`)

`@:test` statics collect into a test `main.swift` that runs each test in
order, catching thrown values, recording the pass or fail line to the
jsonl results file the consistency run reads, and exiting nonzero on any
failure. `std.TestPlatform` lowers inline: `raise` is `throw`,
`currentTestId` reads a file-scope variable the harness sets around each
test, and number-to-text rendering uses string interpolation. The binary
runs under `LD_LIBRARY_PATH=$BORING_SWIFT_LIBDISPATCH`.

## Status

Rulings complete for the constructs the sample tree exercises. The generator
implementing them is tracked separately; until it is implemented, this document
is the decision record the implementation must match.
