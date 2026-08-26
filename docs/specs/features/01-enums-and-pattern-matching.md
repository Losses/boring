# Feature spec 01: Enums and pattern matching

## Scope

This specification rules the translation of Haxe algebraic data types (enums with parameters) and pattern matching constructs into Rust, TypeScript, and Kotlin. In the current codebase, algebraic sum types appear in Rust as `VectorError` in `rust/src/lib.rs` (lines 28-33). The Haxe codebase (`haxe/src/boring/VectorCodec.hx`) and TypeScript codebase (`ts/src/vector-format.ts`) do not define enums today, using string-based exception messages instead. No Kotlin implementation exists yet; the Kotlin rulings bind generated code.

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

### Rust (`rust/src/lib.rs`)

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

### Haxe (`haxe/src/boring/VectorCodec.hx`)

Absent. The Haxe tree uses string exceptions:

```haxe
if (magic != MAGIC) {
    throw new haxe.Exception('bad vector magic: $magic');
}
```

### TypeScript (`ts/src/vector-format.ts`)

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
| TS Candidate 4 (Unique symbol tags) | Symbol comparisons are single pointer identity checks; string comparison degrades to content inspection whenever a compared string was dynamically constructed, while symbol identity never does. | Unique symbols are nominal: no value except the declared constant satisfies the tag type, so tags cannot be spoofed or built from arbitrary strings. | Each variant needs one module-level symbol constant in addition to its interface. | JSON serialization drops symbol values, and the description string is the only debug label, so wire-facing data cannot carry them. |
| Kotlin Candidate 1 (Sealed interface) | `data object` variants are process-wide singletons with zero per-reference allocation, and `data class` variants store the payload inline. | The compiler rejects a `when` over a sealed subject that misses a variant, so exhaustiveness is enforced without an `else` branch. | One declaration per Haxe constructor, with no tag constants to keep in sync. | `is` checks plus smart-cast payload access read as one branch per variant. |
| Kotlin Candidate 2 (Enum class with optional payload) | The nullable `Int?` payload boxes on every use and forces null handling on every consumer. | Any kind can pair with a null or present payload, so invalid combinations type-check. | Callers duplicate payload-presence checks at every access. | The `kind` plus `remaining` pair hides which variants own the payload. |

## Ruling

Haxe enums translate to native tagged `enum` declarations in Rust, to discriminated unions of named interfaces with a `readonly kind: string` literal tag in TypeScript, and to a `sealed interface` in Kotlin with one `data object` per payload-less constructor and one `data class` per constructor with parameters.

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
