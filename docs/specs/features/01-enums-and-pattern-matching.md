# Feature spec 01: Enums and pattern matching

## Scope

This specification rules the translation of Haxe algebraic data types (enums with parameters) and pattern matching constructs into Rust, TypeScript, and Kotlin. In the current codebase, algebraic sum types appear in Haxe as the `VectorError` enum carried by `VectorException` in `samples/boring/`, in Rust as `VectorError` in `reference/rust/src/lib.rs`, in TypeScript as the `VectorError` union carried by `VectorException` in `reference/ts/src/vector-error.ts`, and in Kotlin as the sealed `VectorException` hierarchy in `reference/kotlin/src/boring/VectorException.kt`.

## Haxe construct

Haxe enums define algebraic data types where each constructor can carry zero or more typed parameters:

```haxe
enum VectorError {
	BadMagic;
	CountOverflow;
	UnexpectedEof;
	TrailingBytes(remaining:Int);
}
```

Pattern matching uses the `switch` expression or statement with compile-time exhaustiveness checking:

```haxe
function formatError(error:VectorError):String {
	return switch (error) {
		case BadMagic: "bad vector magic";
		case CountOverflow: "record count exceeds u32";
		case UnexpectedEof: "vector ended mid-record";
		case TrailingBytes(remaining): 'trailing bytes in vector: $remaining';
	};
}
```

Pattern forms include constructor patterns with payload binding (`TrailingBytes(remaining)`), structure patterns (`{ remaining: r }`), guards, or-patterns, and the wildcard `_`:

```haxe
switch (error) {
	case TrailingBytes(remaining) if (remaining > 8):
		'large trailing block: $remaining';
	case BadMagic | CountOverflow:
		"header rejected";
	case _:
		"other";
}
```

In the Haxe typed AST, an enum type is represented by `haxe.macro.Type.TEnum(t:Ref<EnumType>, params:Array<Type>)`. The `EnumType` structure stores constructors in `constructs:Map<String, EnumField>`. Pattern matching AST nodes are represented by `haxe.macro.TypedExprDef.TSwitch(e:TypedExpr, cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, edef:Null<TypedExpr>)` and macro expression nodes `haxe.macro.Expr.ExprDef.ESwitch`.

## Current translations

### Rust (`reference/rust/src/lib.rs`)

```rust
#[derive(Debug, PartialEq)]
pub enum VectorError {
    BadMagic,
    CountOverflow,
    UnexpectedEof,
    TrailingBytes { remaining: usize },
}

impl std::fmt::Display for VectorError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VectorError::BadMagic => write!(formatter, "bad vector magic"),
            VectorError::CountOverflow => write!(formatter, "record count exceeds u32"),
            VectorError::UnexpectedEof => write!(formatter, "vector ended mid-record"),
            VectorError::TrailingBytes { remaining } => {
                write!(formatter, "trailing bytes in vector: {remaining}")
            }
        }
    }
}
```

### Haxe (`samples/boring/VectorCodec.hx`)

Absent. The Haxe tree uses string exceptions:

```haxe
if (magic != MAGIC) {
    throw new haxe.Exception('bad vector magic: $magic');
}
```

### TypeScript (`reference/ts/src/vector-format.ts`)

Absent. The TypeScript tree uses standard `Error` objects with string messages:

```ts
if (magic !== VECTOR_MAGIC) {
    throw new Error(`bad vector magic: ${magic}`);
}
```

## Candidate translations

### Rust Candidate 1: Tagged union enum with match

```rust
#[derive(Debug, Clone, PartialEq)]
pub enum VectorError {
    BadMagic,
    CountOverflow,
    UnexpectedEof,
    TrailingBytes { remaining: usize },
}

pub fn describe_error(error: &VectorError) -> &'static str {
    match error {
        VectorError::BadMagic => "bad vector magic",
        VectorError::CountOverflow => "record count exceeds u32",
        VectorError::UnexpectedEof => "vector ended mid-record",
        VectorError::TrailingBytes { .. } => "trailing bytes in vector",
    }
}
```

### Rust Candidate 2: Struct with integer discriminant and optional payload

```rust
#[derive(Debug, Clone, PartialEq)]
pub struct VectorError {
    pub code: u8,
    pub remaining: Option<usize>,
}
```

### TypeScript Candidate 1: Discriminated union of interfaces with string tag

```ts
export interface BadMagicError {
  readonly kind: "BadMagic";
}

export interface CountOverflowError {
  readonly kind: "CountOverflow";
}

export interface UnexpectedEofError {
  readonly kind: "UnexpectedEof";
}

export interface TrailingBytesError {
  readonly kind: "TrailingBytes";
  readonly remaining: number;
}

export type VectorError =
  | BadMagicError
  | CountOverflowError
  | UnexpectedEofError
  | TrailingBytesError;

export function describeError(error: VectorError): string {
  switch (error.kind) {
    case "BadMagic":
      return "bad vector magic";
    case "CountOverflow":
      return "record count exceeds u32";
    case "UnexpectedEof":
      return "vector ended mid-record";
    case "TrailingBytes":
      return `trailing bytes in vector: ${error.remaining}`;
  }
}
```

### TypeScript Candidate 2: Class hierarchy with instanceof narrowing

```ts
export abstract class VectorErrorBase {}
export class BadMagicError extends VectorErrorBase {}
export class CountOverflowError extends VectorErrorBase {}
export class UnexpectedEofError extends VectorErrorBase {}
export class TrailingBytesError extends VectorErrorBase {
  constructor(readonly remaining: number) {
    super();
  }
}
```

### TypeScript Candidate 3: Numeric enum tag and unstructured payload

```ts
export enum VectorErrorKind {
  BadMagic = 0,
  CountOverflow = 1,
  UnexpectedEof = 2,
  TrailingBytes = 3,
}

export interface VectorError {
  readonly kind: VectorErrorKind;
  readonly payload?: number;
}
```

### TypeScript Candidate 4: Unique symbol discriminants

```ts
const BAD_MAGIC = Symbol("BadMagic");
const COUNT_OVERFLOW = Symbol("CountOverflow");
const UNEXPECTED_EOF = Symbol("UnexpectedEof");
const TRAILING_BYTES = Symbol("TrailingBytes");

export interface BadMagicError {
  readonly kind: typeof BAD_MAGIC;
}

export interface CountOverflowError {
  readonly kind: typeof COUNT_OVERFLOW;
}

export interface UnexpectedEofError {
  readonly kind: typeof UNEXPECTED_EOF;
}

export interface TrailingBytesError {
  readonly kind: typeof TRAILING_BYTES;
  readonly remaining: number;
}

export type VectorError =
  | BadMagicError
  | CountOverflowError
  | UnexpectedEofError
  | TrailingBytesError;

export function describeError(error: VectorError): string {
  if (error.kind === BAD_MAGIC) {
    return "bad vector magic";
  }
  if (error.kind === COUNT_OVERFLOW) {
    return "record count exceeds u32";
  }
  if (error.kind === UNEXPECTED_EOF) {
    return "vector ended mid-record";
  }
  if (error.kind === TRAILING_BYTES) {
    return `trailing bytes in vector: ${error.remaining}`;
  }
  const exhausted: never = error;
  return exhausted;
}
```

### Kotlin Candidate 1: Sealed interface with data object and data class variants

```kotlin
sealed interface VectorError {
    data object BadMagic : VectorError
    data object CountOverflow : VectorError
    data object UnexpectedEof : VectorError
    data class TrailingBytes(val remaining: Int) : VectorError
}

fun describeError(error: VectorError): String = when (error) {
    is VectorError.BadMagic -> "bad vector magic"
    is VectorError.CountOverflow -> "record count exceeds u32"
    is VectorError.UnexpectedEof -> "vector ended mid-record"
    is VectorError.TrailingBytes -> "trailing bytes in vector: ${error.remaining}"
}
```

### Kotlin Candidate 2: Enum class with shared optional payload

```kotlin
enum class VectorErrorKind {
    BadMagic,
    CountOverflow,
    UnexpectedEof,
    TrailingBytes,
}

class VectorError(val kind: VectorErrorKind, val remaining: Int?)
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Tagged enum) | The Rust compiler represents variants with an inline tag byte and contiguous payload without heap allocations. | Match expressions enforce exhaustive checking across all variants at compile time. | Data layout matches the Haxe enum definition directly. | Idiomatic Rust pattern matching conveys variant handling directly to Rust developers. |
| Rust Candidate 2 (Struct with discriminant) | Memory layout requires extra space for Option wrappers and lacks tag-payload coupling. | Handlers can inspect invalid field combinations when the discriminant does not match the populated field. | Translators must duplicate manual validation checks across every call site. | Manual condition checking obscures the sum type intent. |
| TS Candidate 1 (Discriminated union) | Object allocation matches standard JavaScript object creation with zero class prototype overhead. | TypeScript narrowings on the literal kind property provide compile-time exhaustiveness verification. | Each variant maps directly to a named interface conforming to repository typing rules. | Plain object shapes with string tags communicate variant semantics directly. |
| TS Candidate 2 (Class hierarchy) | Class instantiations invoke prototype chains and incur higher construction cost. | Type narrowing relies on sequential instanceof checks without guaranteed compile-time exhaustiveness. | Boilerplate constructor declarations multiply structural code across files. | Class inheritance boilerplate introduces unnecessary OOP mechanics into data definitions. |
| TS Candidate 3 (Numeric enum) | Numeric comparisons execute quickly at runtime. | The payload field is weakly coupled to the kind tag, allowing mismatched variant states. | Type checkers cannot enforce presence of payload fields for specific variants. | Readers must cross-reference enum definitions with untyped property documentation. |
| TS Candidate 4 (Unique symbol tags) | Symbol comparisons are single pointer identity checks; string comparison degrades to content inspection whenever a compared string was dynamically constructed, while symbol identity never does. | Unique symbols are nominal: no value except the declared constant satisfies the tag type, so tags cannot be spoofed or built from arbitrary strings. | Each variant needs one symbol constant declared at module scope in addition to its interface. | JSON serialization drops symbol values, and the description string is the only debug label, so wire-facing data cannot carry them. |
| Kotlin Candidate 1 (Sealed interface) | `data object` variants are process-wide singletons with zero per-reference allocation, and `data class` variants store the payload inline. | The compiler rejects a `when` over a sealed subject that misses a variant, so exhaustiveness is enforced without an `else` branch. | One declaration per Haxe constructor, with no tag constants to keep in sync. | `is` checks plus smart-cast payload access read as one branch per variant. |
| Kotlin Candidate 2 (Enum class with optional payload) | The nullable `Int?` payload boxes on every use and forces null handling on every consumer. | Any kind can pair with a null or present payload, so invalid combinations type-check. | Callers duplicate payload-presence checks at every access. | The `kind` plus `remaining` pair hides which variants own the payload. |

## Ruling

Haxe enums translate to native tagged `enum` declarations in Rust, to discriminated unions of named interfaces with a `readonly kind: string` literal tag in TypeScript, and to a `sealed interface` in Kotlin with one `data object` per payload-less constructor and one `data class` per constructor with parameters.

### Parameterless enums

An enum where every constructor declares zero parameters is a value enumeration: its constructors name a fixed set of constants, and no constructor carries data. Value enumerations translate to constant forms on every target, so constructing a constructor value allocates nothing and every construction site of one constructor yields the same value where the target has object identity. Enums with at least one parameterized constructor keep the payload translation above on every target, including their payload-less constructors. This amendment rules all five source targets (ts, kotlin, swift, dart, rust) together; the Swift and Dart forms extend the original three-target ruling to the targets added later, recorded in the Swift and Dart target-rulings subsections below.

The amendment exists because two targets allocate at every construction site today: TypeScript renders `{ kind: "F64" }` as a fresh object per evaluation (`reference/ts/gen/boring/VectorCodec.ts`, `knownWidthOf`), and Dart renders `FloatWidthF64()` as a fresh instance per evaluation (`reference/dart/gen/lib/boring/vector_codec.dart`). Principle 3 (cost tiers reach their floor) rejects both: constructing a constant is a constant-time, allocation-free operation on every target. The downstream motivation is the engine port: the swapped engine emits parameterless enums on every target, and the handwritten engine tests consume Kotlin `entries`, `valueOf`, and `name` (`engine/src/commonTest/kotlin/org/tiqian/core/EastAsianSpacingCoverageTest.kt`), which the sealed-interface form cannot satisfy.

Per-target candidates and judgment:

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Kotlin `enum class` | Each constructor is one class constant created at class initialization; `entries` and `valueOf` are library members with no per-call allocation. | One declaration names every constructor; `when` over an enum subject stays exhaustive without `else`. | No companion artifacts to keep in sync. | The Kotlin declaration readers expect for a fixed set of constants. |
| Kotlin sealed interface + `data object` (current) | Constructor references are process-wide singletons, but `entries` and `valueOf` do not exist, and every consumer enumerating the values builds its own array. | Exhaustive `when` works; enumeration does not. | Callers duplicate value listings. | Reads as a class hierarchy for what is a fixed set of constants. |
| TS shared constant record (chosen) | One frozen record per enum, one frozen object per constructor; every construction site is a property read. | The record is the single home of every constructor value; the union type from the original ruling stays the type of each member. | The record lists each constructor once; construction sites stop repeating object literals. | `FloatWidth.F64` reads the same as the Kotlin and Rust forms. |
| TS inline object literals (current) | Every evaluation allocates a fresh object; identity differs between two constructions of the same constructor. | The value shape lives at every construction site. | `{ kind: "F64" }` repeats at every site. | Reads fine locally and hides that two spellings of one constructor are distinct objects. |
| Swift `enum` with `String` raw values, `CaseIterable` (chosen) | Case values are zero-size values; `rawValue` returns a compile-time constant string; the synthesized `allCases` initializes once. | Raw values record the constructor names in the declaration. | One declaration; the conformance adds no members to maintain. | The Swift declaration readers expect; `switch` stays exhaustive. |
| Swift plain `enum` (current) | Same value cost, but no name and no enumeration without added conformances. | Constructor names exist in source form only. | Queries need generated additions anyway. | Equivalent locally, weaker in capability. |
| Dart enhanced `enum` with a name field (chosen) | Each constant is one canonical instance created once; `FloatWidth.f64` is a constant reference; the built-in `values` list is a compile-time constant. | The field records the constructor name beside the constant. | The built-in `values` and `toString` come from the language; the handwritten `==` and `hashCode` of the current form are removed. | One declaration lists every constant with its name. |
| Dart sealed classes (current) | Every construction site allocates a fresh instance; enumeration needs a hand-built list. | Identity differs between two constructions of one constructor. | Each variant repeats `==` and `hashCode` boilerplate. | Reads as a class hierarchy for a fixed set of constants. |
| Rust native `enum` (current, kept) | Unit variants are zero-sized; construction is a path constant. | Unchanged from the original ruling. | Unchanged. | Unchanged. |

Rulings:

1. Kotlin renders a value enumeration as `enum class E { C1, C2 }`. Existing construction sites keep their `E.C1` spelling; `when` over the subject stays exhaustive, and its arms compare against the constants (`E.C1 ->`) where the sealed form used type checks (`is E.C1`). Payload enums keep the sealed interface. The original Kotlin Candidate 2 (`enum class` carrying one optional shared payload) stays rejected for payload enums, because the nullable payload boxes on every use and admits combinations no constructor declares; a value enumeration declares no payload, so that defect cannot arise, and the constant form adds the enumeration members (`entries`, `valueOf`, `name`) the sealed interface lacks.
2. TypeScript keeps the union of interfaces with `readonly kind: string` literal tags from the original ruling as the type. The value side adds one shared record per enum, emitted beside the type: each constructor is one object wrapped in its own `Object.freeze(` call, and the record holding every constructor is itself wrapped in `Object.freeze(`. Every construction site renders `E.C1` as a member read of the record. The record and the union type share the enum name; TypeScript separates the value and type namespaces. Equality keeps comparing the `kind` tag: a consumer can still write an object literal that satisfies the interface, and tag comparison assigns it to the right constructor, where identity comparison would misclassify it (principle 1, content-defined semantics).
3. Swift renders `enum E: String, CaseIterable, Equatable` with one case per constructor and the raw value set to the constructor name spelled in Haxe source: `case f64 = "F64"`. Case identifiers keep the target's naming conversion; raw values preserve the source names, so name queries agree across targets.
4. Dart renders an enhanced enum: one constant per constructor, a `final String label` field holding the constructor name spelled in Haxe source, and a `const` constructor assigning it. The field name avoids the built-in `name` getter, which returns the target-mangled identifier. Construction sites render `E.c1` as a constant reference; the handwritten `==` and `hashCode` of the sealed-class form are removed because enum constants compare by canonical instance.
5. Rust keeps the native `enum` with unit variants from the original ruling. Query artifacts on top of it are ruled in `docs/specs/features/28-enum-value-queries.md`.
6. Enums absorbed into an exception hierarchy by the exception fold (the `payloadEnum` mechanism of `stdlib/03`, `KotlinEmissionState.hx` and `RustEmissionState.hx`) keep the current forms on every target, because the fold renders the constructors as members of the exception family. The amendment applies to standalone enum declarations.
7. Every constructor value initializes at most once per process on every target: Kotlin and Dart create the constants during type initialization, Swift initializes `allCases` on first access, TypeScript creates the record at module evaluation, and Rust constants are compile-time artifacts. The per-evaluation cost of constructing a constructor value is zero allocation on every target.

The samples and tree assertions that cover these forms live in `docs/specs/features/28-enum-value-queries.md`.

This ruling ensures zero-allocation representations in Rust while providing strict exhaustiveness checks in TypeScript via `switch` expressions over the discriminant tag and in Kotlin via `when` expressions over the sealed subject without an `else` branch. TypeScript interfaces declare data shape only, adhering to the interface rules in `AGENT.md`.

TypeScript narrows discriminated unions on `unique symbol` discriminant properties exactly as it does on string literal discriminants, so symbol-tagged unions keep compile-time exhaustiveness checking: the `describeError` example above fails to compile when a variant is missed, because the final `never` assignment rejects any unhandled variant.

String literal tags remain the default for discriminated data that crosses or mirrors the wire format: JSON serialization, error messages, and debug output keep working without conversion. Unique symbol tags are required when tag values stay internal to the process and one of the following holds: a tag is compared against values that may be dynamically constructed strings, or the type system must guarantee that no unrelated string satisfies the discriminant. Switching a union between the two tag representations is a specification edit, because consumers match on tag values.

Pattern forms translate to readable branch code, and every form keeps payload access cast-free:

- Constructor or structure patterns with payload binding: Rust binds the payload directly in the match arm (`VectorError::TrailingBytes { remaining }`); TypeScript branches on the discriminant and then reads the payload property (`error.remaining`), where narrowing supplies the type. TypeScript never renders payload extraction as property access on a widened type with a cast. Kotlin matches on `is VectorError.TrailingBytes` and reads `error.remaining` after the smart cast.
- Guards: Rust appends an `if` guard to the match arm; TypeScript appends the guard to the branch condition after the discriminant comparison, and the unguarded variant still gets a branch so exhaustiveness survives. Kotlin appends the guard to the `is` condition with `&&`, keeping one branch per variant.
- Or-patterns: Rust lists alternatives in one arm (`VectorError::BadMagic | VectorError::CountOverflow`); TypeScript writes consecutive comparisons joined by `||`, or consecutive `case` labels over a shared `return` body when the `switch` form is used. Kotlin lists alternatives comma-separated in one `when` branch.
- Wildcard `_`: permitted in Haxe and Rust (`_`) only for non-enum subjects; enum subjects are matched exhaustively variant by variant. The TypeScript final branch assigns the discriminant to `never` for enum subjects; a catch-all `else` appears only for non-enum subjects and documents which values it covers. Kotlin `when` over a sealed enum subject declares no `else` branch; `else` serves only non-enum subjects.

## Test hooks

Rust unit tests in `tests/rust/vector.rs` (lines 73-96) assert exact `VectorError` enum variants:
- `VectorError::BadMagic`
- `VectorError::UnexpectedEof`
- `VectorError::TrailingBytes { remaining: 1 }`

TypeScript and Haxe tests for structured enum errors are none yet.

### Swift target rulings

#### Enums and pattern matching (`features/01`)

Haxe enums map to Swift value enums with labeled associated values.

```swift
enum UStringFault: Equatable {
    case invalidCodePoint(code: Int32)
    case unpairedSurrogate(unit: Int32)
}
```

A value enumeration (every constructor declares zero parameters, the
parameterless amendment of `features/01`) maps to a `String`-raw-value
enum with `CaseIterable`: case identifiers keep the target naming
conversion, raw values preserve the constructor names spelled in Haxe
source, and `allCases` and `rawValue` are the enumeration and
constructor-name reads of `features/28-enum-value-queries.md`.

```swift
enum FloatWidth: String, CaseIterable, Equatable {
    case f64 = "F64"
    case f32 = "F32"
    case f16 = "F16"
}
```

Payload captures lower to `case .invalidCodePoint(let code)`; a
multi-arm switch over the enum is exhaustive without a default arm;
unused payloads bind `case .unpairedSurrogate(_)`. Guards lower to
`where` clauses. Or-patterns expand to comma-joined case labels.

### Dart target rulings

#### Enums and pattern matching (`features/01`)

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
