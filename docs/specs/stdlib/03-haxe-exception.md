# Standard library spec 03: haxe.Exception

## Scope

This specification rules the translation of `haxe.Exception`, exception propagation, and catch block mechanics into Rust, TypeScript, and Kotlin. In the current codebase, exceptions appear in Haxe in `haxe/src/boring/VectorCodec.hx` (lines 32, 50) and `tests/haxe/Main.hx` (lines 97-103), structured error variants appear in Rust in `rust/src/lib.rs` (lines 28-48, 62, 66, 79, 85, 102, 106, 128) and `tests/rust/vector.rs` (lines 72-96), and thrown errors appear in TypeScript in `ts/src/vector-format.ts` (lines 34, 49) and `tests/ts/codec.test.ts` (lines 66-80). No Kotlin implementation exists yet; the Kotlin rulings bind generated code.

## Haxe construct

`haxe.Exception` is the base class for all exceptions in Haxe 4. Its module surface includes:

- `new Exception(message:String, ?previous:Exception, ?native:Any)`: constructs a new exception instance.
- `e.message:String`: the diagnostic message string.
- `e.stack:CallStack`: the call stack trace captured at throw time.
- `e.previous:Null<Exception>`: previous chained exception if present.
- `e.native:Any`: target-specific native error object.
- `e.unwrap():Any`: retrieves the underlying native error.
- `Exception.caught(value:Any):Exception`: wraps an unknown caught target value into a `haxe.Exception`.
- `Exception.thrown(value:Any):Any`: converts an exception into the target-specific representation for throwing.

On the JavaScript target, `haxe.Exception` wraps JavaScript `Error` objects and captures native stack traces. Catching `haxe.Exception` catches all thrown JavaScript errors.

In the Haxe typed AST, exceptions are constructed via `haxe.macro.TypedExprDef.TNew` targeting `haxe.Exception` or subclasses, thrown via `haxe.macro.TypedExprDef.TThrow`, and intercepted via `haxe.macro.TypedExprDef.TTry`.

## Current translations

### Haxe (`haxe/src/boring/VectorCodec.hx`, `tests/haxe/Main.hx`)

```haxe
if (magic != MAGIC) {
	throw new haxe.Exception('bad vector magic: $magic');
}

if (reader.remaining() != 0) {
	throw new haxe.Exception('trailing bytes in vector: ${reader.remaining()}');
}
```

Catching exceptions in `tests/haxe/Main.hx` (lines 97-103):

```haxe
var badMagicThrew = false;
try {
	VectorCodec.decode(Bytes.ofHex("5858585800000000"));
} catch (error:haxe.Exception) {
	badMagicThrew = true;
}
expectTrue("bad magic raises an exception", badMagicThrew);
```

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

impl std::error::Error for VectorError {}
```

### TypeScript (`ts/src/vector-format.ts`)

```ts
if (magic !== VECTOR_MAGIC) {
  throw new Error(`bad vector magic: ${magic}`);
}

if (reader.remaining() !== 0) {
  throw new Error(`trailing bytes in vector: ${reader.remaining()}`);
}
```

## Candidate translations

### Rust Candidate 1: Result enum implementing std::error::Error with exact error variants

```rust
#[derive(Debug, PartialEq)]
pub enum VectorError {
    BadMagic,
    CountOverflow,
    UnexpectedEof,
    TrailingBytes { remaining: usize },
}

pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    // ...
}
```

### Rust Candidate 2: Boxed dynamic std::error::Error trait object

```rust
pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, Box<dyn std::error::Error>> {
    if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
        return Err("bad vector magic".into());
    }
    // ...
    Ok(records)
}
```

### TypeScript Candidate 1: Standard Error instances thrown with matching message prefixes

```ts
if (magic !== VECTOR_MAGIC) {
  throw new Error(`bad vector magic: ${magic}`);
}

if (reader.remaining() !== 0) {
  throw new Error(`trailing bytes in vector: ${reader.remaining()}`);
}
```

### TypeScript Candidate 2: Custom Exception class hierarchy extending Error

```ts
export class VectorError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VectorError";
  }
}

export class BadMagicError extends VectorError {}
export class TrailingBytesError extends VectorError {}
```

### Kotlin Candidate 1: Sealed exception hierarchy with one variant per failure mode

```kotlin
sealed class VectorException(message: String) : Exception(message) {
    data object BadMagic : VectorException("bad vector magic")
    data object CountOverflow : VectorException("record count exceeds u32")
    data object UnexpectedEof : VectorException("vector ended mid-record")
    data class TrailingBytes(val remaining: Int) :
        VectorException("trailing bytes in vector: $remaining")
}
```

### Kotlin Candidate 2: Message-only exceptions

```kotlin
throw Exception("bad vector magic")
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Result enum) | Enum returns allocate zero heap memory and propagate via CPU registers. | Exhaustive variants define every failure mode explicitly for callers. | Error variants map directly to domain validation checkpoints. | The question mark operator provides idiomatic Rust error handling. |
| Rust Candidate 2 (Boxed dynamic Error) | Allocating Box pointers on every error creates heap pressure during error recovery. | Dynamic error trait objects hide concrete error causes behind type erasure. | Dynamic errors require string formatting at every instantiation site. | Dynamic boxes obscure domain errors from unit test assertions. |
| TS Candidate 1 (Thrown standard Error) | Standard Error throws incur zero overhead on successful execution paths. | Message prefixes provide clear failure diagnostics in test assertions. | Direct Error instantiation relies on built-in JavaScript platform types. | Standard throw expressions communicate failure directly to TypeScript developers. |
| TS Candidate 2 (Custom class hierarchy) | Custom class construction invokes constructor inheritance and prototype lookups. | Prototype inheritance checks require instanceof matching across package boundaries. | Custom error classes add boilerplate code for four distinct error states. | Class hierarchies introduce unnecessary object-oriented complexity into error reporting. |
| Kotlin Candidate 1 (Sealed exception hierarchy) | Failures allocate exactly one exception instance carrying its payload inline. | `when` over the sealed type is exhaustive, and each variant names its failure mode. | One hierarchy serves every throw site in the codec. | Variant names and messages stay adjacent in one declaration. |
| Kotlin Candidate 2 (Message-only exceptions) | String construction allocates on every failure, matching the success-path cost of none. | Message strings are the only failure identity, so tests match on text. | Every throw site re-states its message literal. | Untyped messages hide the variant set from callers and the compiler. |

## Ruling

`haxe.Exception` translates to `Result<T, VectorError>` return types in Rust with explicit enum variants, to standard `Error` instances thrown with descriptive message strings in TypeScript, and to a sealed exception hierarchy thrown in Kotlin, adhering to `docs/specs/features/06-errors-and-results.md`.

The exact mapping of exception types and messages to Rust variants and Kotlin variants is:
- `'bad vector magic'` maps to `VectorError::BadMagic` and `VectorException.BadMagic`.
- `'record count exceeds u32'` maps to `VectorError::CountOverflow` and `VectorException.CountOverflow`.
- `'vector ended mid-record'` maps to `VectorError::UnexpectedEof` and `VectorException.UnexpectedEof`.
- `'trailing bytes in vector: ${remaining}'` maps to `VectorError::TrailingBytes { remaining }` and `VectorException.TrailingBytes(remaining)`.

## Test hooks

Exact error variants and exception throws are asserted in:
- `tests/rust/vector.rs` (lines 72-96)
- `tests/haxe/Main.hx` (lines 97-103)
- `tests/ts/codec.test.ts` (lines 66-80)
