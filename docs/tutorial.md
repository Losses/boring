# Tutorial: the translatable subset and its performance rules

boring compiles a subset of Haxe to TypeScript, Kotlin, Rust, Swift, and
Dart. One source tree produces six executable trees: the stage-one Haxe
reference tree and the five generated trees. Every construct the subset
accepts has a ruled translation and a ruled cost, recorded in the
specifications under `docs/specs/`.

This tutorial lists every language feature of the subset, states when to
use each feature, and names the construct the specifications select when
two constructs solve the same problem. The performance grounds quoted
here (allocation, boxing, engine behavior) come from the specifications;
this document adds no rulings. Spec references abbreviate the directory:
`features/09` stands for `docs/specs/features/09-iterators.md`, and the
same applies to `macros/`, `stdlib/`, `style/`, `binary/`, and `targets/`.
The Swift and Dart lanes carry their per-target rulings in `targets/swift`
and `targets/dart`; the feature specs name the older three targets, and
those two files state the mapping for the newer two.

## Writing conforming source

`style/01` states the source standard as seven positive rules:

1. Declarations carry explicit types. Public functions declare parameter
   and return types; structure typedefs declare every field with a type
   and a mutability marker; locals use `final` unless reassigned.
2. Arrays iterate by index range. `for (i in 0...array.length)` with
   `array[i]` access is the only array iteration form. Collections are
   arrays; keyed lookup goes through `std.SortedMap` and `std.SortedSet`
   (`stdlib/07`).
3. Static objects use their source syntax: dot access reads fields,
   bracket access with an `Int` index reads arrays, brace literals
   construct (`features/16`).
4. Failures are enum-carrying exceptions. Every `throw` constructs a
   `haxe.Exception` subclass that carries a Haxe enum instance naming
   the variant (`features/06`).
5. Control flow stays flat: `if`, `switch`, `while`, `do`/`while`, range
   `for`, `break`, `continue`, and early `return` are the only forms
   (`features/15`).
6. Numbers use the platform tower: `Int` and `Float` carry all codec
   arithmetic; `haxe.Int64` appears only in the cases `stdlib/05`
   permits.
7. Data has no inheritance. Record types are structure typedefs or
   classes with fields; polymorphism goes through generics
   (`features/05`).

A canonical decode function, quoted from `style/01`:

```haxe
public static function decode(bytes:Bytes):Array<GlyphMetrics> {
	final reader:BinaryReader = new BinaryReader(bytes);
	final count:Int = reader.readU32();
	final records:Array<GlyphMetrics> = new Array<GlyphMetrics>();
	for (index in 0...count) {
		final codePoint:Int = reader.readU32();
		final advanceEm:Float = reader.readF64();
		records[index] = {
			codePoint: codePoint,
			advanceEm: advanceEm,
			bounds: readBounds(reader),
		};
	}
	if (reader.remaining() != 0) {
		throw new VectorException(TrailingBytes(reader.remaining()));
	}
	return records;
}
```

Every construct outside the standard is rejected before generation by the
interception macro of `style/01`, with a named violation (`V01` through
`V18`) at the offending site. A rejection is fatal: the source changes or
the specification changes. The rejection table lives in `style/01`; the
sections below name the violation that guards each area.

## Quick selection

| Need | Construct | Spec |
| --- | --- | --- |
| Iterate an array | `for (i in 0...array.length)` with `array[i]` | `features/09` |
| Fill an array whose count is known | pre-allocated fill, one allocation, indexed stores | `stdlib/04` |
| Transform or scan a collection in pipeline form | closed-list idiom with one inline function literal | `macros/01`, `macros/02` |
| Group entries by key | `groupBy`, product `std.SortedMap<K, Array<V>>` | `macros/03` |
| Copy a record with fields replaced | `item.copy(field = expr)` | `macros/04` |
| Sort an array | named `VectorSort` strategy | `features/17` |
| Keyed lookup or keyed set | `std.SortedMap` / `std.SortedSet` | `stdlib/07` |
| Count, index, or slice possibly non-ASCII text | `std.UString.count` / `at` / `slice` | `stdlib/10` |
| Count user-perceived characters | `std.Graphemes` | `stdlib/11` |
| Build a string incrementally | `std.StringBuf` | `stdlib/08` |
| Read and write binary payloads | `haxe.io.Bytes` with reader and writer primitives | `stdlib/01`, `stdlib/02` |
| Signal a failure | throw an enum-carrying exception subclass | `features/06` |
| Express absence of a value | `Null<T>` | `features/04` |
| Distinguish two same-shaped types | abstract type: alias on hot paths, wrapper at boundaries | `features/02` |
| Carry a genuine 64-bit value | `haxe.Int64`, only the cases `stdlib/05` permits | `stdlib/05` |
| Compile the same source with binary32 floats | `-D float-precision=f32` at generation | `features/23` |
| Constant lookup table above 64 entries | compile-time data table | `features/20` |
| Range check or clamp | `within`, `coerceAtLeast`, `coerceAtMost`, `coerceIn` | `stdlib/09` |
| Declare a unit test | `@:test` static function with `std.Test` assertions | `features/19` |

## Numbers

### Int and Float (`features/07`)

`Int` is 32-bit signed on every supported target; `Float` is 64-bit IEEE
754. Wire alignment is fixed by the wire type: `WireU8` maps to `Int`,
`u8`, `number`, `Int`; `WireU16Be` and `WireU32Be` map to `Int`, `u16` or
`u32`, `number`, `Int`; `WireF64Be` maps to `Float`, `f64`, `number`,
`Double`, listing Haxe, Rust, TypeScript, and Kotlin in order.
`WireF32Be` and `WireF16Be` (`binary/05`) keep the `WireF64Be` language
mapping and differ in byte width and in the rounding at the block edge.

Use `Int` and `Float` for all arithmetic. Every numeric conversion is an
explicit named function at an API or wire boundary; implicit narrowing
and unchecked `as` casts are banned, and a generator that meets a numeric
type outside the table fails the build.

Performance ground:

- A JavaScript `number` holds every `u32` wire value inside the 53-bit
  integer range, so `number` carries each field without loss.
  `bigint` for fields of 32 bits or fewer is banned: bigint values
  allocate heap objects, leave the V8 small-integer path, and require a
  conversion at every `DataView` boundary.
- Kotlin `Long` for fields of 32 bits or fewer is banned: it boxes on
  Kotlin/JS. Kotlin `UInt` and `ULong` box in nullable and generic
  positions, so wire representations use `Int` and `Long`.
- Rust `char` for code points is banned: it adds surrogate validation to
  raw binary codecs.
- Single-precision float paths for `WireF64Be` are banned, as are boxed
  `Number` objects and numbers stored in strings.
- Float bit identity goes through the bit-level paths on every target:
  `haxe.io.FPHelper` in Haxe, `to_bits`/`from_bits` in Rust, `DataView`
  reads and writes with the little-endian argument `false` in
  TypeScript, `Double.toBits()`/`Double.fromBits(...)` in Kotlin. Test
  vectors assign dyadic rationals so every target produces identical bit
  patterns, and tests compare decoded floats without arithmetic on them.

TypeScript validates `Number.isInteger` at the API boundary before
encoding.

### Precision switch (`features/23`)

`-D float-precision=f32` selects the binary32 family for every `Float`
in the compilation: `f32` fields and `2.5f32` literals in Rust, `Float`
fields and `2.5f` literals in Kotlin, `f32::NAN` and `Float.NaN` for
the constants, and `f32::<name>` / `kotlin.math.<name>` for the `Math`
functions. The absent define (or `=f64`) keeps the default binary64
mapping. The switch is whole-compilation: the Haxe source declares
nothing about it, and the consumer passes the define like any other
compilation flag. A consumer needing both widths in one artifact
compiles the single-precision part as a separate compilation.

The TypeScript and Dart targets reject `f32` at compiler startup, the
error text naming `number is binary64` and `double is the one real
storage width` respectively; wrapping arithmetic in `Math.fround` or
storing fields in `Float32Array` are the rejected emulation paths
(design principle 3).

Rust, Kotlin, and Swift are the three lanes the define switches. Swift
maps `Float` to `Float` under `f32` and `Double` on the default lane;
its literals are type-directed and carry no suffix, so the f32 lane
names the type on every declaration whose initializer would otherwise
infer the default `Double` width (`var x: Float = 0.0`), and its
arithmetic and rounding members come from the `FloatingPoint` protocol
both types implement. Dart holds one storage width for reals, so an f32
variant cannot change result bits (`targets/swift`, `targets/dart`).

The wire does not switch: `WireF64Be` stays f64 on every lane. A wire
read decodes the 8 f64 wire bytes and rounds the value to the module
real at the decode point (`FPHelper.i64ToDouble` dispatches to the
`i64ToF32` runtime variant); a wire write widens the module real
losslessly before the bit conversion (`doubleToI64` dispatches to
`f32ToI64`). Test vectors assign dyadic binary32 values, so the
committed vector bytes are identical on every lane and the shared test
suites run unmodified.

Generation entries: `examples/rust-f32.hxml`, `examples/kotlin-f32.hxml`,
`examples/swift-f32.hxml`; verify lanes `gen:rust-f32`, `gen:kotlin-f32`,
`gen:swift-f32`, `test:rust-f32`, `test:kotlin-f32`, `test:swift-f32`.

### Wide integers (`stdlib/05`)

`haxe.Int64` serves two cases: domain values outside the 53-bit safe
integer range of `number`, and the `haxe.io.FPHelper.doubleToI64` bit
conversion, whose `bits.high` and `bits.low` words are written as `Int`.
Arithmetic, storage, and API exposure of `Int64` outside these paths is
banned (`V11 Int64Misuse`).

Every `bigint` to `number` crossing passes through a named conversion
function at a wire or API boundary, and mixing `bigint` and `number`
operands in one expression is banned. Kotlin carries the same standard
through `Long`, which is a native primitive on the JVM and an emulated,
boxed class on Kotlin/JS.

A wire format that declares `WireI64Be` or `WireU64Be` is a format
revision: the web-target `bigint` cost and the Kotlin/JS `Long` boxing
cost are measured and accepted in writing before the field enters the
binary specifications.

### Inline arithmetic helpers (`stdlib/09`)

`within`, `coerceAtLeast`, `coerceAtMost`, and `coerceIn` are static
inline functions whose bodies are one comparison, one conditional, or a
composition of those; `IntRange` is an abstract over
`{ start:Int, end:Int }` carrying `contains`. The Haxe compiler inlines
each body at the call site in the common layer, so every target receives
the expanded expression and no helper name survives to emission. The
helper list is frozen; a new helper joins only through a specification
amendment.

Loop-head sugar is absent on purpose: descending and stepped loops write
as `while` loops, the half-open Kotlin `0 until count` writes as the
Haxe range `0...count`, and inclusive iteration over `a..b` writes
`a...(b + 1)`. A range stored as a value uses `IntRange`.

## Data

### Enums and pattern matching (`features/01`)

An enum declares a closed variant set once per domain and shares it with
all six trees. Haxe enums translate to tagged `enum` declarations in
Rust, discriminated unions of named interfaces with a `readonly kind:
string` literal tag in TypeScript, a `sealed interface` in Kotlin
with one `data object` per payload-less constructor and one `data class`
per constructor with parameters, value enums with labeled associated
values in Swift, and sealed class hierarchies in Dart (`targets/swift`,
`targets/dart`).

Use string literal tags when the tagged data crosses or mirrors the wire
format, so JSON serialization, error messages, and debug output keep
working without conversion. Use `unique symbol` tags when tag values
stay internal to the process and one of these holds: a tag is compared
against strings that may be constructed at runtime, or the type system
must guarantee that no unrelated string satisfies the discriminant.
Switching a union between the two tag representations is a specification
edit.

Pattern matching translates to branch code with cast-free payload
access: Rust binds payloads in match arms, TypeScript branches on the
discriminant and reads the payload property after narrowing, Kotlin
matches with `is` and reads after the smart cast. Guards and or-patterns
keep one branch per variant. An enum subject is matched exhaustively
variant by variant; a wildcard or `default` arm for an enum subject is
rejected (`V15 EnumDefaultArm`). The exhaustiveness check is the
performance mechanism as well: adding a variant fails the build of every
tree whose handling was not extended, at compile time, with no runtime
cost.

### Structures and typedefs (`features/03`)

Record data declares as named structure typedefs. They translate to
named `struct` declarations in Rust with public fields and derived
traits (`Debug`, `Clone`, `Copy`, `PartialEq`), named `interface`
declarations in TypeScript with `readonly` properties, and `data class`
declarations in Kotlin with `val` properties. Inline object types are
banned outside the direct right-hand side of a type alias
(`boring/no-inline-types`), and TypeScript interfaces declare data shape
only, with no method signatures (`boring/no-interface-methods`,
`features/12`).

Construction follows the static-object rules of `features/16`: one
literal initializes every declared field exactly once, in declaration
order.

### Abstract types (`features/02`)

An abstract type distinguishes a domain of values that share a primitive
representation. Where it is used decides its translation:

- On codec hot paths and record data carriers, abstract types translate
  to primitive type aliases (`type CodePoint = u32`,
  `type CodePoint = number`, `typealias CodePoint = Int`), keeping
  direct memory access with no allocation.
- At domain validation boundaries, abstract types with explicit
  constraints translate to single-field newtype structs in Rust, branded
  primitive types in TypeScript, and `@JvmInline value class` wrappers
  in Kotlin.

Kotlin `value class` values box when stored in nullable or generic
positions, so boundary wrappers stay out of dense record arrays; dense
arrays carry the primitive alias.

### Null (`features/04`)

`Null<T>` and optional fields translate to `Option<T>` in Rust, optional
properties (`prop?: T` or `T | undefined`) in TypeScript, and `T?` in
Kotlin. Sentinel values that encode absence inside the value domain are
forbidden on every target; the compiler enforces absence. A query miss
returns `null` (`std.UString.at`, `std.SortedMap.get`); a programmer
error throws (`features/06`).

### Generics (`features/05`)

Generic declarations translate to monomorphized static generics with
trait bounds in Rust and to erased generic declarations with interface
bounds in TypeScript and Kotlin. Runtime type reflection on type
parameters is forbidden in every language, and generated Kotlin code
declares no `reified` parameters; the bounds already guarantee what a
type check would ask. Rust monomorphization yields direct code per
instantiation; the erased targets add no runtime type discovery.

### Type mapping (`features/14`)

The base-type mapping table is fixed (Haxe, Rust, TypeScript, Kotlin):

| Haxe | Rust | TypeScript | Kotlin |
| --- | --- | --- | --- |
| `Int` | `i32` or `u32` selected by wire width | `number` | `Int` (`Long` above `0x7FFFFFFF`) |
| `Float` | `f64` | `number` | `Double` |
| `Bool` | `bool` | `boolean` | `Boolean` |
| `String` | `String` or `&str` | `string` | `String` |
| `enum` | `enum` | discriminated union, `kind` tag | `sealed interface` |
| `class` | `struct` plus `impl` | `class` | `class` |
| anonymous structure | named `struct` | named `interface` | `data class` with `val` |
| typedef alias | type alias | type alias | `typealias` |
| `abstract` over `T` | newtype or alias per `features/02` | brand or alias per `features/02` | `value class` or `typealias` |
| `Null<T>` | `Option<T>` | `prop?: T` per `features/04` | `T?` |
| `Dynamic` | banned | banned | banned |

Type identity never merges: two distinct named Haxe types translate to
two distinct target types even when their shapes coincide. Every target
type is named; inline object, function, mapped, and tuple types are
banned. `Dynamic`, value-less `cast`, and `untyped` blocks are rejected
(`V05 DynamicValue`).

### Static objects (`features/16`)

A static object declares every field in a named structure type and
translates to a named `struct` in Rust, an object literal typed by a
named interface in TypeScript, and a `data class` with `val` properties
in Kotlin. The performance rules bind all targets:

1. Construction initializes every declared field exactly once, in
   declaration order. Declaration order keeps hidden-class transitions
   in V8 monomorphic and keeps JSON serialization of equal values
   identical across trees.
2. Writing obeys declared mutability: `final` fields become `readonly`
   properties in TypeScript, non-`mut` fields in Rust, and `val`
   properties in Kotlin.
3. Nothing changes an object's shape after construction (`V07
   ShapeMutation` guards the writes the compiler does not already
   reject).
4. Bracket access with a `String` key on a structure is rejected before
   generation (`V06 StringKeyedAccess`); bracket access with an `Int`
   index is array element access.
5. Field iteration over a static object does not translate. An algorithm
   that must visit every field enumerates a schema-declared constant
   array of the field names; that array is compile-time constant data
   and unrolls per `stdlib/04`. `Reflect.ownKeys` and `Object.keys` on
   static shapes are banned, consistent with `features/13`.

### Classes (`features/12`)

Stateful classes translate to Rust `struct` declarations with private
fields and `impl` blocks, TypeScript `class` declarations with explicit
`private`, `public`, and `readonly` modifiers, and Kotlin `class`
declarations with `private val` and `private var` state. A class may
extend a class only through the `haxe.Exception` chain that rule 4 of
`style/01` sanctions (`V12 DataInheritance`). Pure static utility
classes translate to free functions in target modules. In TypeScript,
callable members of an interface declare as properties whose types are
named function type aliases; method signatures in interfaces are banned
(`boring/no-interface-methods`).

### Read-only data (`features/18`)

Decoded collections expose as the `ReadOnlyArray<T>` abstract and
decoded records as all-`final` typedefs. Each platform enforces
read-only at the earliest point it can state: TypeScript decode
boundaries apply `DecodeBoundaryFreeze`, so each record, its nested
objects, and the array pass through `Object.freeze(` before return;
Kotlin returns a `List` view whose mutators throw; Rust takes `&[T]` and
`&T`, and a lowering that would mutate a read-only value plants a
`compile_error!`. Mutation failure identity is the platform's own
failure, and tests assert its class, never a message.

The sort runtime sorts its input array in place (`features/17`), so
callers pass owned mutable storage and decoded output never enters it.

## Collections

### Array allocation and fills (`stdlib/04`)

A fill whose count is known before the loop uses the pre-allocated fill
of its platform: `Vec::with_capacity(capacity)` with `push` in Rust,
`new Array<T>(count)` with indexed stores in TypeScript, the array
initializer `Array(count) { index -> ... }` in Kotlin when the
destination is a fixed-size array, and indexed stores on a fresh Haxe
array. One allocation covers the whole fill, no growth copy runs, and
the fill and the allocation share the count. `ArrayList<T>(count)` with
`add` remains in Kotlin only where the API requires a mutable list.
A push-built array grows through geometric reallocation; when the count
is known, that growth work is avoidable cost, and the `arrayOfNulls`
plus `requireNoNulls` form is retired.

A fill bound that is not structurally non-negative clamps the
allocation as `new Array<T>(Math.max(count, 0))` on TypeScript while
the loop condition keeps the plain bound, preserving the Haxe behavior
where a negative count skips the fill.

### Compile-time constant arrays (`stdlib/04`, `features/20`)

Static-length arrays whose length and contents are compile-time
constants unroll at build time, up to 64 elements. When the constant
width matches a primitive wire write, the whole array folds into one
constant: `WireAscii(4)` over `BRG1` becomes the u32 constant
`0x42524731` written through `writeU32`, with the per-character loop
gone. When the width matches no primitive write, the generator emits one
named constant per element; no runtime array is allocated for data whose
contents the compile time already knows. Kotlin declares no `const`
arrays, so per-element constants are its constant-array form.

A constant `Int` array above 64 elements used for computed-index lookup
follows the data-table emission of `features/20`: Rust emits
`static RANGES: [u32; N]`, TypeScript emits
`const RANGES = new Int32Array([...])`, Kotlin emits
`val RANGES = intArrayOf(...)` inside an object. The `DataTables`
`@:build` macro reads the data files under `samples/data/` at compile
time. The lookup algorithm stays handwritten; a binary search over the
table is ordinary indexed code.

### Keyed collections (`stdlib/07`)

`std.SortedMap<K, V>` and `std.SortedSet<K>` are immutable sorted
tables: a builder receives `put` calls, `build()` returns the table, and
no member can modify it afterwards. Keys ascend; `Int` keys order
numerically; a later `put` with an equal key replaces the earlier entry.
Iteration is by index range over `size()`, `keyAt`, and `valueAt`;
lookups are `get(key):Null<V>` and `has(key):Bool`, comparison-based,
found by binary search.

The subset holds no hash maps: `haxe.ds.Map` and its implementations are
rejected (`V13 HashMapCollection`). Ordering is the contract; an
immutable comparison-based table needs no hash function and no
per-platform hash discipline, and no hash order is observable on any
target. The structure serves the dominant consumer shape the audit
recorded: build once, then read by exact key or in ascending order. A
mutable keyed cache would need its own specification amendment.

Key domains with ruled comparison: `Int` numerically; `String` in UTF-16
code-unit order, so every target reads the same sequence astral to the
BMP (the resident comparator walks by code point with one adjustment at
the first differing pair); structure keys field-lexicographic in
declaration order, with the per-type comparison generated from the typed
AST into every output tree.

One resident implementation (`src/runtime/SortedTable.hx`) backs both
faces on every target; storage is generic parallel arrays sorted at
`build()`. Kotlin boxes `Int` keys in the generic arrays; that one
object per key is the accepted cost of a single source.

### Sorting (`features/17`)

Sorting goes through a named strategy of the sort runtime. The set
starts with `byCodePoint`; a new sorting need is a new named strategy
and a specification amendment to `features/17`. Every strategy on every
platform is ascending, in place, and stable; stability is the identity
contract that makes the six trees produce the same output array.

Performance ground: the comparator-free numeric sort is the fastest sort
primitive JavaScript exposes, so the TypeScript runtime tiers it with an
allocation-free insertion tier for small inputs and a general fallback;
Rust and Kotlin call the platform stable sort, already the fastest
available on those trees. Comparator `sort` in source is rejected
(`V02`), and the one generated-comparator path is the `sortedBy`
expansion of `macros/01`, whose comparator is generated from the key
expression and never exists as a source value.

## Control flow and iteration

### Statements (`features/15`)

Observable behavior is identical on every platform, and each platform
emits its own fastest sound construct; statement-level correspondence
with the Haxe source is not required. `if`/`else`, `while`, `break`,
`continue`, and early `return` render unchanged everywhere. Rust renders
`do`/`while` as `loop` with a trailing conditional `break`. Constructs
merge when a platform holds a faster form with identical behavior: a
counted fill loop lowers to the Kotlin array initializer and the
pre-allocated constructor forms of `stdlib/04`.

`switch` translates to Rust `match` with no catch-all arm over enums, to
Kotlin `when` with no `else` over sealed subjects, and on TypeScript to
a `switch` statement only when every case body ends in `return` or
`throw`; otherwise the translation is an `if`/`else` chain on the
discriminant. The final branch of either TypeScript form assigns the
discriminant to `never`, so an added variant fails that tree's compile.

Multi-level exit from nested loops is restructured in Haxe source: the
body moves into a function and exits through early `return`, or the loop
conditions gain guard expressions. Haxe source declares no labels;
labels appear only in generated target code. Exceptions never serve as
jumps, handler-closure dictionaries and functional combinators never
serve as control flow.

### Loops (`features/09`)

Haxe source iterates arrays through `for (i in 0...array.length)` with
`array[i]` access; an iteration subject outside an integer range is
rejected (`V01 IteratorLoop`). Each generated tree keeps the cost fixed
by the statement itself:

- TypeScript reads the iteration bound into a local before the loop,
  reads the property exactly once, and accesses elements directly with a
  non-null assertion (`records[i]!`) stating the invariant the bound
  establishes. `for...of` and `for...in` are banned: the iterator
  protocol's fast path is engine discretion, and `for...in` enumerates
  string keys including inherited ones. A `.length` read inside the loop
  head executes on every iteration, and the single-read rule keeps it
  out.
- Kotlin iterates by the static subject type: `for (item in array)` over
  `Array<T>` and primitive arrays, which lowers to an indexed loop with
  no iterator allocation; `for (i in 0 until count)` with indexed access
  over `List<T>` and other `Iterable` subjects, because the element loop
  would allocate one `Iterator` per traversal.
- Rust keeps `for item in slice` over borrowed slices and
  `for i in 0..count` ranges, both direct iteration with no protocol
  dispatch and no allocation.

Loop bodies contain no function expressions, arrow functions, or bound
method references (`V08 LoopBodyClosure`). A closure allocated inside a
loop body converts a bounded, allocation-free loop into per-iteration
context allocation, and the resulting garbage collection pauses dominate
the runtime of a decoded payload on the JavaScript target. A callback
that cannot be avoided is hoisted to module scope and receives all state
as parameters; no closure captures a loop variable. Generator functions
are banned on the decode hot path: decoders validate headers, parse
records, and verify the trailing boundary before returning complete
collections.

### Pipeline idioms (`macros/01`, `macros/02`, `macros/03`)

A closed list of collection pipeline calls is sanctioned with one shape:
the receiver is an `Array<T>`, the argument is exactly one inline
single-parameter function literal written at the call site, and the call
sits in a direct position. The typed common layer expands every call
into the loop forms of `features/09` before target emission, so the
targets receive loop statements only, never a function value, and the
cost equals the hand-written loop.

| Idiom | Product |
| --- | --- |
| `map` | pre-allocated fill per `stdlib/04` |
| `filter` | compact push loop |
| `forEach` | the `features/09` loop form, statement position |
| `associate` | loop plus `SortedMapBuilder` `put` and `build()` (`stdlib/07`) |
| `sortedBy` | copy of the receiver, stable ascending sort by the key |
| `any` / `all` | boolean loop with `break` on first decision |
| `firstOrNull` | `Null<T>` loop with `break` on first match |
| `sumOfInt` / `sumOfFloat` | accumulator loop |
| `mapNotNull` | compact push loop that skips `null` selector values |
| `flatMap` | compact push loop with a nested loop over each selector array |
| `groupBy` | loop building `std.SortedMap<K, Array<V>>`, key-ascending, buckets in receiver order |

Use the pipeline form where it reads better than the hand-written loop;
the expansion emits the same statements. An empty receiver yields
`false`, `true`, `null`, `0`, and `0.0` for the early-exit and sum
forms, identically on every side. Chains expand in source order, each
stage reading the previous stage's temporary.

Everything outside the closed list keeps the `V02 FunctionalIteration`
rejection, including `Lambda` module calls, `reduce`, `fold`, and
comparator `sort`. A point-free call (`arr.map(namedFn)`), a
multi-parameter lambda, a call in a non-direct position, or a `flatMap`
selector outside `Array<R>` is rejected with the named errors of
`macros/01` and `macros/02`.

### Record copy (`macros/04`)

`item.copy(score = 99)` constructs a new record value from an existing
one with zero or more fields replaced. The construct accepts an
anonymous structure receiver; overrides assign fields by name, name each
field at most once, evaluate in the receiver's field-declaration order,
and evaluate at most once. Assignment expressions as call arguments are
rejected everywhere else (`V17 AssignArgExpression`). The product is an
expression and composes in every expression position.

## Strings

### Two index spaces and the ASCII tier (`features/08`)

The runtimes expose two index spaces on `String`: the TypeScript,
Kotlin, and stage-one runtimes address UTF-16 code units, and the Rust
runtime addresses UTF-8 bytes. The two spaces coincide for code points
U+0000..U+007F and diverge everywhere else. The meaning of `length`,
`charCodeAt`, `charAt`, `codePointAt`, `substring`, `substr`, `indexOf`,
and `lastIndexOf` is defined over the character sequence; platform
storage decides the cost tier, never what a result means.

Use the native operations where the content is known ASCII: one
character occupies exactly one UTF-16 code unit and one UTF-8 byte
there, so every target answers in constant time with identical results.
A string that may hold content above U+007F uses `std.UString`
(`V18 NonAsciiStringIndex` reports at Haxe compile time; the violation
message names `std.UString` as the sanctioned path).

`String.substring` is the one character operation with a lowering on all
six targets, so it is permitted beyond the ASCII tier; its bounds are
Haxe string positions, UTF-16 code units, on every target, and the
guaranteed domain is in-range bounds on code-point boundaries.
`String.fromCharCode` constructs a string from a wire byte, domain
0..255; constructing from a code point goes through
`std.UString.fromCodePoint`. `StringTools.fastCodeAt` and
`StringTools.fromCharCode` are banned: their results have no
content-defined meaning across storage widths.

### Character access (`stdlib/10`)

`std.UString` carries character-sequence semantics on every target:
`count`, `at`, `slice`, `toCodePoints`, `fromCodePoints`, and
`fromCodePoint`. An out-of-range `at` returns `null`; an invalid
construction argument throws `UStringException` carrying
`InvalidCodePoint`. The cost floors are recorded per usage pattern:

| Usage pattern | Operation | Cost |
| --- | --- | --- |
| known-ASCII count or scan | native `length`, native indexing | constant time per query, every target |
| one-shot character query | `count`, `at` | one linear pass, no allocation |
| one-shot substring | `slice` | one walk plus the result string |
| repeated positional access | `toCodePoints`, then array indexing | one pass plus the output array, then constant time |

Counting characters on variable-width storage must examine every
character at least once, so the one-pass forms sit at the floor. No
target emulates another platform's storage inside the walk: Rust
iterates `chars()`, the UTF-16 platforms walk code units, and each tier
costs the same order on every target.

### Grapheme clusters (`stdlib/11`)

A grapheme cluster is a user-perceived character under UAX #29: a base
character with its combining marks, a Hangul jamo run, a carriage return
and line feed pair, an emoji sequence with modifiers, joiners, or keycap
marks, a regional-indicator pair, or an Indic conjunct. The family emoji
sequence is seven code points, eleven UTF-16 units, and one cluster, so
no storage unit and no code-point count answers what a reader sees.

`std.Graphemes.count`, `at`, `slice`, and `parts` answer over clusters,
with the same clamping and null-miss contracts as `std.UString`. One
generated table and one rule walk serve all six targets, built from a
fixed Unicode release with the official conformance file as a
compile-time gate, so the same input segments identically on every host
and host version. Repeated cluster access goes through `parts` once,
then indexes the array in constant time.

### String building (`stdlib/08`)

`std.StringBuf` is the buffered string builder: `add` appends a string,
`addChar` appends one UTF-16 code unit, `length` reports the code-unit
count, `toString` returns the content. Every target renders its native
mutable accumulator behind the contract. Surrogate pairing is checked on
every target: appending a trail surrogate with no preceding lead,
appending a lead or a plain unit while an unpaired lead waits, and
calling `toString` over a dangling lead each throw `UStringException`
carrying `UnpairedSurrogate(unit)`. Diagnostics built
from parts join through this module, so a broken sequence reports the
same fault at the same boundary on every target.

## Binary I/O

### Byte storage (`stdlib/01`)

`haxe.io.Bytes` translates to borrowed byte slices (`&[u8]`) for input
parameters and owned byte vectors (`Vec<u8>`) for outputs in Rust, to
`Uint8Array` for all inputs and outputs in TypeScript, and to
`ByteArray` in Kotlin. Reads borrow existing sequences without
intermediate buffers; writes accumulate into growable structures and
return one contiguous buffer. `Bytes.sub` and the Kotlin
`copyOfRange` both copy the sub-range.

### Readers and writers (`stdlib/02`)

Binary code shares one primitive set: `readU16`/`writeU16`,
`readU32`/`writeU32`, `readF64`/`writeF64`, `readF32`/`writeF32`,
`readF16`/`writeF16`, and fixed-length ASCII
`readAscii`/`writeAscii`. Float conversions take the bit-level paths of
`features/07`; TypeScript reads and writes through `DataView` with the
little-endian argument `false`; Kotlin assembles integers with shifts
and `Double.toBits()`/`Double.fromBits(...)`; Rust reads
`from_be_bytes` chunks. Bounds checking lives in reader slice
extraction and writer capacity growth. JVM-only stream classes
(`java.io.DataInputStream`, `java.nio.ByteBuffer`) stay out of common
Kotlin code because the Kotlin target spans JVM and JavaScript
backends.

### Block float widths (`binary/05`)

A vector block carries one marker that fixes the width of every float
field in it: `BRG1` keeps binary64 at 8 bytes per field, `BRG2` selects
binary32 at 4 bytes, and `BRG3` selects binary16 at 2 bytes. A record
holds one `u32` code point plus five float fields, so a block of N
records totals 8 + 44 x N, 8 + 24 x N, or 8 + 14 x N bytes. Decode
reads the marker and rejects a magic outside the table with `BadMagic`,
so a block written at a width a reader never knew is refused, and the
reader never guesses a layout.

Encode takes the width as a parameter next to the records:

- Haxe source: `VectorCodec.encode(records, FloatWidth.F16)`; omitting
  the width encodes binary64.
- TypeScript: `encodeVector(records, "F16")`.
- Kotlin: `VectorCodec.encode(records, FloatWidth.F16)`.
- Rust: `encode_vector_with_width(&records, FloatWidth::F16)?`, with
  `encode_vector(&records)?` as the binary64 shorthand.
- Swift: `VectorCodec.encode(records, FloatWidth.f16)`.
- Dart: `vector_codec.encode(records, float_width.FloatWidthF16())`.

Hand-written TypeScript and Kotlin callers pass the width explicitly;
the default argument completes inside the compiled trees only, and no
target emits a default into the generated signature.

Rounding follows binary spec 05: each field rounds once with
round-to-nearest-even at the write edge, and binary16 encodes through
two deterministic roundings (module real to binary32, then binary32 to
binary16). Infinity, signed zero, and quiet NaN pass through; overflow
magnitude rounds to infinity; subnormals of a wider grid round to signed
zero on the narrower one.

The block width and the `float-precision` define are independent axes.
The define selects the module real once per compilation and never
changes block bytes; the width is chosen per encode call and recorded in
the marker. Any compilation reads and writes all three widths.

Runtime cost sits at three layers:

- Generated code execution: every field pays one width comparison plus
  one write or read of 8, 4, or 2 bytes; a binary16 field adds the
  integer shift-and-round sequence over the bit pattern. The comparison
  cost is the same at every width.
- Data transfer: the block itself shrinks with the width, 44 to 24 to 14
  bytes per record under the fixed header, which is the purpose of the
  feature.
- Compile time: none. The width is a runtime parameter of ordinary
  calls; nothing about it branches code generation. The precision
  define is the axis that changes compilation, and it composes freely
  with every block width.

## Functions and modules

### Static extensions (`features/10`)

`using` static extensions translate to inherent `impl` methods for
crate-owned types in Rust, free functions in Rust for foreign types or
multi-argument operations, exported module functions taking the receiver
as the first parameter in TypeScript, and extension functions in Kotlin.
Kotlin extensions resolve statically at compile time and import
explicitly, carrying no dispatch cost. Global prototype augmentation and
declaration merging are banned in TypeScript.

### Inline declarations and macros (`features/11`)

`inline var` constants translate to `pub const` items in Rust, `export
const` bindings in TypeScript, and `const val` declarations in Kotlin;
Kotlin `const val` accepts primitive and `String` types only, and
constant arrays follow the unrolling of `stdlib/04`. `inline` accessor
functions translate to `const fn` or `#[inline]` functions, direct
functions, and `inline fun`. Haxe compile-time macros operate at build
time inside the Reflaxe pipeline; no runtime behavior of the generated
trees depends on macro interpreters, dynamic code evaluation, or
`kotlin.reflect`.

### Default arguments (`features/22`)

Omitted trailing parameters are filled by a typed completion pass in the
common layer, with defaults from the sanctioned class: literals, `null`,
and argument-less enum constructors after compile-time constant
evaluation (`V16 NonConstantDefault` rejects the rest). Declarations
lose their defaults on the way down, and every target emits full
positional calls only, so no target needs optional-parameter machinery
and each call site states its complete argument list.

### Metadata (`features/13`)

Compiler metadata is consumed at build time by the Haxe compiler and the
generator to configure emission (`@:test` in `features/19` is the
readiest example). Runtime reflection is banned everywhere: `Reflect`
and `Type` calls are rejected (`V03 Reflection`), target code uses
explicit static field access, and dynamic JSON data at boundaries is
validated through explicit type guard functions.

### std modules and the runtime package (`stdlib/06`)

Two source namespaces are reserved: `haxe.*` for the translated Haxe
standard library modules, and `std.*` for the subset's own modules
declared in `samples/std/`. `haxe.*` never reaches target output.
Runtime-backed std modules (`std.ReadOnlyArray`, `std.StringBuf`,
`std.UString`, `std.Graphemes`, `std.SortedMap` and relatives,
`std.Test`) resolve into the runtime package; compiled std modules emit
like ordinary modules.

A consumer configuration names the runtime package through defines:
`runtime-import` states how generated code references it (no default
exists; the compilation stops when the define is missing), and
`runtime-emit` decides whether the runtime files are written or only
referenced. The runtime package exposes two entries: a general entry
that a browser can load, holding no `node:` specifier and no host
process API, and a test entry holding the `std.Test` result writer.
Generated business code imports the general entry only.

### Package shells (`features/24`)

Every compilation writes the package manifest of its output tree into
the main output directory: a `Cargo.toml` for Rust, a `package.json`
for TypeScript, a `Package.swift` for Swift, a `pubspec.yaml` for Dart,
and a `build.gradle.kts` for Kotlin. The manifest states the identity
of the tree (name, version, license), the entry paths the compiler
itself wrote, the empty dependency set, and the dialect floor the
generated code needs. It is on by default; `package-shell=none` turns
it off, and `package-name` (default `generated`, a neutral value),
`package-version`, and `package-license` carry the identity.

Two lane-specific notes. On TypeScript, an emitted manifest requires a
relative `runtime-import`: a by-name import names a package coordinate
the manifest cannot declare, and the compilation stops with that
reason; the manifest also carries an `exports` map with one directory
wildcard per emitted top-level package directory plus the `./runtime`
entry, so a consumer imports `generated/boring/Fp32` and resolves the
emitted `.ts` file. On Rust, `package-test=name:path` appends one
integration-test block for repositories that keep tests outside the
crate, and the manifest sets `autotests = false` because the generated
`tests/` directory is a `#[cfg(test)]` module tree of the library.

Workspace membership, publication coordinates, repositories, and any
dependency graph beyond the tree stay with the consumer's build; a
manifest field with no source inside the compilation does not exist.

### Package artifacts (`features/25`)

`package-artifacts=emit` packs the tree the compilation wrote into
the install artifact of its ecosystem and writes it beside the output
directory: an npm `.tgz` (entries under `package/`), a cargo `.crate`,
a Swift `.zip`, and a Pub `.tar.gz`, each named
`<package-name>-<package-version>` plus its extension. The Kotlin
target stops the compilation instead, because Gradle modules publish
through the consumer's build. The define is off by default; it also
requires the package shell, since the artifact wraps the manifest.

The entry set is the recorded write list of the compilation, never a
directory walk: test-output trees, `_GeneratedFiles.txt`, and files
the compilation did not write stay out. Entries sort by name and carry
fixed metadata (tar mtime 0 and mode 0644, gzip MTIME 0, one fixed zip
date), so two generations of the same inputs on the same Haxe
toolchain produce byte-identical artifacts. The npm tarball installs
with `npm install <file>` and imports through the `exports` map of
`features/24`.

## Failures

### Errors and results (`features/06`, `stdlib/03`)

Failure identity is a closed variant set declared once per domain and
shared by all six trees in one commit: the Haxe enum with its exception
wrapper, the Rust error enum, the TypeScript error union with its
exception class, the Kotlin sealed exception hierarchy, the Swift error
enum, and the Dart sealed exception hierarchy. Every
`throw` constructs the exception subclass carrying the enum instance
(`V04 UntypedThrow` rejects every other throw shape); catch clauses name
the exception type (`V14 DynamicCatch` rejects `catch (error:Dynamic)`).

Per target: Rust returns `Result<T, DomainError>` with structured
variants; TypeScript narrows with `instanceof` on the one exception
class, then branches on the discriminant; Kotlin matches over the sealed
hierarchy; the Haxe tree matches `error.error` against the enum.

A `try` region lowers on every target: TypeScript and Kotlin use native
`try`/`catch` (an expression-position region hoists to a statement and a
`let` on TypeScript, since its `try` produces no value), and Rust lowers
the region body into a closure returning `Result`, matching the outcome
immediately. Two restrictions keep a region translatable, each with a
named rejection and a sanctioned alternative: a region throwing beyond
the caught class is rejected (`tryRegionMixedDomains`; use nested
regions, one per domain), and a region containing `return`, `break`, or
`continue` is rejected (`tryRegionControlFlow`; evaluate the region to a
value first, then place the control-flow statement after it).

Messages are display text derived from the variant at construction. No
consumer discriminates a failure by reading or matching a message
string; tests assert variant identity. Kotlin `runCatching`, catch-all
`Result` returns, Rust `panic` for domain failures, and `Box<dyn Error>`
returns are banned: they capture programming errors alongside domain
failures and erase the variant identity the six trees share.

## Tests (`features/19`)

A test case is a public static function without parameters carrying the
`@:test` metadata, with an optional description string. Test modules
live in the `tests.*` package under `samples/tests/`. Assertions go
through `std.Test`: `run` executes one body and records the outcome,
`ok` checks a boolean, `equals` compares structurally, `fail` reports
unconditionally. `equals` rejects `NaN` by IEEE equality, so a `NaN`
expectation asserts through `ok`.

Every target emits its tests into that language's own runner and writes
one results file in a shared JSON Lines format; a Haxe-side consistency
manager compares every target against the Kotlin baseline (identical
id sets, verdicts, names, and byte-identical failure messages) and exits
nonzero on any divergence. The failure message text is built by one
compiled module, `runtime.TestCore`, so the string is identical across
targets. On TypeScript, the `ts-test-runner` define selects the runner
(`node`, `bun`, or `deno`) at compile time; generated code never probes
the environment at runtime.

Test discipline follows `features/07`: floating-point fields in vectors
assign dyadic rationals, and comparisons read decoded floats without
arithmetic on them.

## Where the authority lives

The specifications under `docs/specs/` are the fact source for every
ruling quoted here: `features/` for language constructs, `stdlib/` for
the standard library and the runtime package, `macros/` for the
compile-time rewrites, `style/` for the source standard and the
rejection table, `binary/` for the wire formats. `docs/specs/README.md`
states the categories and the judgment dimensions;
`docs/specs/design-principles.md` states the principles the cost
grounds serve. A decision changes through a spec edit in the same commit
as the code; when this tutorial and a specification differ, the
specification wins.
