# Standard library spec 03: haxe.Exception

## Scope

This specification rules the translation of `haxe.Exception`, exception propagation, and catch block mechanics into Rust, TypeScript, and Kotlin. In the current codebase, exceptions appear in Haxe in `haxe/src/boring/VectorCodec.hx` (lines 33, 51) and `tests/haxe/Main.hx` (lines 102-113), structured error variants appear in Rust in `rust/src/lib.rs` (lines 28-48, 62, 66, 79, 85, 102, 106, 128) and `tests/rust/vector.rs` (lines 72-96), and thrown errors appear in TypeScript in `ts/src/vector-format.ts` (lines 36, 51) and `tests/ts/codec.test.ts` (lines 66-80). No Kotlin implementation exists yet; the Kotlin rulings bind generated code.

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

Catching exceptions in `tests/haxe/Main.hx` (lines 102-113):

```haxe
var badMagicVariant:Null<VectorError> = null;
try {
	VectorCodec.decode(Bytes.ofHex("5858585800000000"));
} catch (error:VectorException) {
	badMagicVariant = error.error;
}
expectTrue("bad magic throws the BadMagic variant", badMagicVariant == BadMagic);
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

The candidate set, judgment axes, and selection follow `docs/specs/features/06-errors-and-results.md`; this section records the mapping mechanics for `haxe.Exception` itself.

### Rust Candidate 1: Result enum implementing std::error::Error with exact error variants (selected)

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

### TypeScript Candidate 1: Exception class carrying the error union (selected)

```ts
export class VectorException extends Error {
  readonly error: VectorError;

  constructor(error: VectorError) {
    super(describeError(error));
    this.name = "VectorException";
    this.error = error;
  }
}
```

### TypeScript Candidate 2: One Error subclass per variant

```ts
export class BadMagicError extends Error {}
export class TrailingBytesError extends Error {
  constructor(readonly remaining: number) {
    super(`trailing bytes in vector: ${remaining}`);
  }
}
```

### TypeScript Candidate 3: Standard Error instances with identity in the message

```ts
if (magic !== VECTOR_MAGIC) {
  throw new Error(`bad vector magic: ${magic}`);
}
```

### Kotlin Candidate 1: Sealed exception hierarchy with one variant per failure mode (selected)

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

The judgment table applying to these candidates lives in `docs/specs/features/06-errors-and-results.md`; the mapping mechanics specific to `haxe.Exception` are:

| Aspect | Mapping |
| --- | --- |
| `new Exception(message, previous, native)` | The translated exception constructor takes the variant value; `previous` chains through the target's native chaining (`Error.cause`, `Exception(cause)`), and `native` has no counterpart in generated code. |
| `e.message` | Derived from the variant at construction; display text only. |
| `e.stack` | The target platform stack captured by `Error` or `Exception` construction; identical mechanics, no translation step. |
| `Exception.caught(value)` | Appears only at interop boundaries outside the translatable subset; generated code never calls it. |
| `Exception.thrown(value)` | Never appears in translatable code; the interception rejects it. |
| `try ... catch (e:SpecificClass)` | Rust matches over the `Result` error; TypeScript narrows with `instanceof` then branches on the discriminant; Kotlin catches `VectorException` then matches `when` over the variant. |

## Ruling

`haxe.Exception` translates to `Result<T, DomainError>` return types in Rust with explicit enum variants, to one exception class carrying the error union value in TypeScript, and to a sealed exception hierarchy thrown in Kotlin, following `docs/specs/features/06-errors-and-results.md`. The failure identity in every language is the variant, and the message is derived display text.

The exact four-language mapping for the vector format is:

| Haxe variant | Rust variant | TypeScript `kind` | Kotlin variant | Message template |
| --- | --- | --- | --- | --- |
| `BadMagic` | `VectorError::BadMagic` | `"BadMagic"` | `VectorException.BadMagic` | `bad vector magic` |
| `CountOverflow` | `VectorError::CountOverflow` | `"CountOverflow"` | `VectorException.CountOverflow` | `record count exceeds u32` |
| `UnexpectedEof` | `VectorError::UnexpectedEof` | `"UnexpectedEof"` | `VectorException.UnexpectedEof` | `vector ended mid-record` |
| `TrailingBytes(remaining)` | `VectorError::TrailingBytes { remaining }` | `"TrailingBytes"` with `remaining` | `VectorException.TrailingBytes(remaining)` | `trailing bytes in vector: ${remaining}` |

## Test hooks

Exact error variants and exception throws are asserted in:
- `tests/rust/vector.rs` (lines 72-96)
- `tests/haxe/Main.hx` (lines 102-113)
- `tests/ts/codec.test.ts` (lines 66-80)

Required after the typed error migration: assertions match the variant or its `kind` field, never the message string, per `docs/specs/features/06-errors-and-results.md`.
