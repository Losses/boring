# Feature spec 02: Abstract types

## Scope

This specification rules the translation of Haxe abstract types into Rust, TypeScript, and Kotlin. In the current codebase, one abstract appears: `ReadOnlyArray<T>` in `samples/std/ReadOnlyArray.hx`, the read-only array type ruled in `docs/specs/features/18-immutability.md`. Domain records otherwise use primitive `Int` and `Float` types; specialized scalar domains such as `CodePoint` (constrained to valid Unicode ranges) and `EmUnit` (floating-point em coordinates) are future work. In Kotlin, the `ReadOnlyArray` type lowers to the read-only `List` return type of `reference/kotlin/src/boring/VectorCodec.kt`. A planned extension below rules member-carrying abstracts that keep a runtime wrapper type on every target.

## Haxe construct

Haxe abstract types provide compile-time type distinctions over underlying representation types with zero runtime overhead:

```haxe
abstract CodePoint(Int) from Int to Int {
	public inline function new(value:Int) {
		this = value;
	}

	@:to
	public inline function toHex():String {
		return StringTools.hex(this, 4);
	}
}
```

An abstract type introduces a distinct nominal type at compile time while compiling directly to the underlying primitive type on the target platform. Explicit casts (`@:from`, `@:to`) control conversions between the abstract type and other representations.

In the Haxe typed AST, an abstract type is represented by `haxe.macro.Type.TAbstract(t:Ref<AbstractType>, params:Array<Type>)`. The `AbstractType` structure stores the underlying type in `t:Type`, defined conversions in `from:Array<{t:Type, field:Null<ClassField>}>` and `to:Array<{t:Type, field:Null<ClassField>}>`, and the implementation class in `impl:Null<Ref<ClassType>>`.

## Current translations

### Haxe (`samples/boring/GlyphMetrics.hx`)

Absent. Primitive types are used directly:

```haxe
typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}
```

### Rust (`reference/rust/src/lib.rs`)

Absent. Primitive types are used directly:

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### TypeScript (`reference/ts/src/records.ts`)

Absent. Primitive types are used directly:

```ts
export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

## Candidate translations

### Rust Candidate 1: Newtype tuple struct

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct CodePoint(pub u32);

impl From<u32> for CodePoint {
    fn from(value: u32) -> Self {
        CodePoint(value)
    }
}
```

### Rust Candidate 2: Primitive type alias

```rust
pub type CodePoint = u32;
```

### TypeScript Candidate 1: Branded primitive type

```ts
declare const CodePointBrand: unique symbol;
export type CodePoint = number & { readonly [CodePointBrand]: true };

export function asCodePoint(value: number): CodePoint {
  return value as CodePoint;
}
```

### TypeScript Candidate 2: Primitive type alias

```ts
export type CodePoint = number;
```

### TypeScript Candidate 3: Wrapper class

```ts
export class CodePoint {
  constructor(readonly value: number) {}
}
```

### Kotlin Candidate 1: typealias

```kotlin
typealias CodePoint = Int
```

### Kotlin Candidate 2: value class

```kotlin
@JvmInline
value class CodePoint(val value: Int)
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Newtype struct) | The compiler lays out single-field tuple structs identically to the wrapped primitive without heap overhead. | Distinct nominal types prevent accidental assignment of incompatible integer values. | Trait implementations for arithmetic and conversions must be declared explicitly for the new type. | The explicit type signature documents domain constraints directly in function signatures. |
| Rust Candidate 2 (Type alias) | Machine code emission operates directly on native primitive registers. | Type aliases are transparent to the compiler and allow accidental substitution of any u32 value. | Zero duplicate trait or conversion boilerplate is required. | Aliases provide lightweight domain naming with familiar standard primitive semantics. |
| TS Candidate 1 (Branded type) | Type branding exists entirely in the type checker and incurs zero runtime cost. | Nominal brand symbols prevent accidental assignment of raw numbers. | Creation functions must cast raw primitives at validation boundaries. | Type signatures declare domain types while preserving native number operations. |
| TS Candidate 2 (Type alias) | Primitives execute with native JavaScript number performance. | Aliases are erased by TypeScript and provide no protection against assigning arbitrary numbers. | Zero validation wrappers or branding symbols are defined. | Simple type aliases integrate straightforwardly with existing TypeScript code. |
| TS Candidate 3 (Wrapper class) | Class wrappers allocate heap objects for every numeric value and trigger garbage collection churn. | Class instances cannot be compared using value equality without custom methods. | Wrapper classes duplicate storage and conversion logic across modules. | Object wrapping introduces unnecessary ceremony for basic scalar values. |
| Kotlin Candidate 1 (typealias) | Aliases are erased, so values stay plain `Int` primitives on every target. | Aliases accept any `Int`, so constraint violations appear only in guard functions. | Zero wrapper declarations or conversion functions are required. | A typealias names the domain without new syntax. |
| Kotlin Candidate 2 (value class) | A `value class` stores the underlying primitive inline and boxes only in nullable or generic positions. | The wrapper type rejects raw `Int` assignments at compile time. | Construction requires invoking the class constructor with the primitive literal. | The declaration states the domain and its representation in one line. |

## Ruling

On codec hot paths and record data carriers, abstract types translate to primitive type aliases (`type CodePoint = u32` in Rust, `type CodePoint = number` in TypeScript, `typealias CodePoint = Int` in Kotlin) to maintain direct memory access and zero allocation overhead. At domain validation boundaries, abstract types with explicit constraints translate to single-field newtype structs in Rust, branded primitive types in TypeScript, and `@JvmInline value class` wrappers in Kotlin; Kotlin `value class` values box when stored in nullable or generic positions, so boundary wrappers stay out of dense record arrays.

This separation prevents validation overhead during dense array serialization while providing strong compile-time type safety at API ingestion boundaries.

## Planned extension: value wrappers with members

Status: implemented. The rules below amend the Ruling for abstracts marked as
value wrappers. The engine port is the consumer that fixes the required
shape. The sample set and the tree and mutation assertions below render on
every target. The handwritten Kotlin engine declares
`@JvmInline value class` wrappers with members and consumes them across
packages: `Units.Ic` (a `Float` representation holding `toPx`, the operators
`plus` and `unaryMinus`, and the constant `Zero` in a companion object,
consumed as far as nullable and defaulted fields such as
`firstLineIndent: Ic?` and `blockIndent: Ic = Ic.Zero`), and
`FontFaceId` (a `String` representation whose constructor rejects blank
values and whose `toString` returns the value). Erasing these abstracts to
aliases breaks their members, their equality, their validation, and the
Kotlin regeneration of the ported files.

### Source-side contract

The marker is metadata on a single-field abstract whose representation is
one of `Int`, `Float`, `Bool`, and `String`:

```haxe
@:valueType
abstract Ic(Float) from Float {
    public inline function new(count:Float) this = count;

    inline function count():Float return this;

    public inline function toPx(emPx:Float):Float return this * emPx;

    @:op(A + B) static inline function plus(a:Ic, b:Ic):Ic
        return new Ic(a.count() + b.count());

    @:op(-A) static inline function negate(a:Ic):Ic
        return new Ic(-a.count());

    public static var ZERO:Ic = new Ic(0.0);
}
```

The declared members accept: the constructor with an optional body that
validates and throws; instance methods; `@:op` statics over the wrapper
type; a `toString` member; and static fields of the wrapper type whose
initializers are constructor calls over closed constants. A marker on an
abstract whose representation is outside the closed class, on a generic
abstract, or on any non-abstract declaration stops the compilation with
`value type markers accept single-field abstracts over a primitive
representation only`. Unmarked abstracts keep the erasure ruling above.

### Per-target products

| Target | Declaration |
| --- | --- |
| Kotlin | `@JvmInline value class Name(val field: Rep)` with the declared members; `@:op` members render as `operator fun`; static fields render inside `companion object`; construction sites render `Name(rep)`. |
| TypeScript | `export type Name = Rep;` and member functions in the module file with the value first, following the `@:extension` shape of `docs/specs/features/10-static-extension.md`; operators render as those functions and operator call sites render as direct calls to them; a validating constructor renders as a module function that validates, throws, and returns the representation. |
| Swift | `struct Name: Equatable, Hashable` with the representation as a `let` field, the declared members, static operators as members of the struct, and `toString` as `CustomStringConvertible`; validation renders in `init`. |
| Dart | `extension type Name(Rep field)` with the declared members and operators; `toString` renders as a declared `String toString()`; a validating constructor renders as a factory function that constructs, validates, and throws, and construction sites route through it. |
| Rust | `#[derive(...)] pub struct Name(pub Rep);` with the declared members in an inherent `impl`, operators as the matching standard trait implementations (`Add` for `+`, `Neg` for the prefix minus), `toString` as `Display`, validation in a constructor function following the error convention of `docs/specs/features/06-errors-and-results.md`. Derives follow the representation: `PartialEq` always; `Eq` and `Hash` only when the representation holds them, so a `Float` representation derives `PartialEq` alone. |

Equality, hashing, and rendering are observable: two wrappers over equal
representations are equal; a declared `toString` overrides the rendering,
and its absence keeps the representation's existing string conversion on
every target. Validation that throws preserves its observable rejection on
every target through the error model of features 06. Nullable positions
follow each target's null convention for the shape above, including the
boxed nullable positions of the Kotlin value class.

Member calls and construction add no allocation on any target: the Kotlin
value class stores the representation inline and boxes only in nullable or
generic positions, the Rust newtype is layout-identical to the
representation, the Swift struct is a stack value, and the Dart extension
type and the TypeScript alias erase to the representation at runtime.

### Ordering and composition

Implementation follows `docs/specs/features/10-static-extension.md`:
member functions of the TypeScript alias render in the extension shape of
that specification, and a Swift operator may render as a file scope
function. The planned extension of
`docs/specs/features/22-default-argument-expansion.md` composes with this
one: a coalescing default may read a static field of a value wrapper, for
example `Ic.ZERO` as a defaulted parameter value.

### Extension test hooks

- `samples/boring/ValueTypeOps.hx` declares the two port shapes over the
  closed representations: the arithmetic wrapper (`Float`, `toPx`, the two
  operators, the static field) and the validating wrapper (`String`,
  blank rejection, `toString` returning the value), each consumed from
  another module in the sample tree.
- `@:test` functions assert the arithmetic results, the equality of
  wrappers over equal representations, the static field, the rejection of
  a blank construction, and the rendered string of both shapes; the
  four-side consistency run compares the rows across kotlin (baseline),
  haxe, ts, rust, swift, and dart.
- Tree assertions: the Kotlin tree renders `@JvmInline value class` with
  `companion object` statics and `operator fun`; the Swift tree renders
  the struct with synthesis and static operators; the Dart tree renders
  `extension type`; the Rust tree renders the newtype with
  representation-matched derives (`PartialEq` without `Eq` over `Float`);
  the TypeScript tree renders the alias plus member functions with the
  value first.
- Mutation checks: the marker over a non-primitive representation, over a
  generic abstract, and over a class declaration each trigger
  `value type markers accept single-field abstracts over a primitive
  representation only`.


## Test hooks

Round-trip tests in `tests/ts/codec.test.ts` and `tests/rust/vector.rs` verify primitive integer and float behavior on the wire. Specific unit tests for abstract domain types are none yet.
