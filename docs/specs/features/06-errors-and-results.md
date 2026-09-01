# Feature spec 06: Errors and results

## Scope

This specification rules error representation and failure propagation across Haxe, Rust, TypeScript, and Kotlin. It defines the error taxonomy discipline: failure identity is a closed set of named variants that match one to one across all four languages, messages are display text derived from the variant, and no consumer discriminates a failure by reading a message string. In the current repository, error handling appears in Haxe via `throw new VectorException(...)` in `samples/boring/VectorCodec.hx`, in Rust via `Result<T, VectorError>` in `reference/rust/src/lib.rs`, in Kotlin via the sealed `VectorException` hierarchy in `reference/kotlin/src/boring/`, and in TypeScript via `throw new VectorException({ kind: ... })` in `reference/ts/src/vector-format.ts` and the reader guards of `reference/ts/src/codec.ts`. Every tree carries failure identity in a variant value; the TypeScript JSON boundary (`reference/ts/src/vector-json.ts`) validates a domain that exists only in that tree and carries its own `JsonError` variant set through the same exception shape.

## Haxe construct

Haxe uses structured exceptions derived from `haxe.Exception` for error propagation. The `throw` expression accepts any value in plain Haxe; the translatable subset restricts it as ruled below.

```haxe
if (magic != MAGIC) {
	throw new VectorException(BadMagic);
}
```

Exceptions unwind the call stack until intercepted by a `try ... catch` block:

```haxe
try {
	VectorCodec.decode(bytes);
} catch (error:VectorException) {
	switch (error.error) {
		case BadMagic:
			Console.log("bad vector magic");
		case TrailingBytes(remaining):
			Console.log('trailing bytes in vector: $remaining');
		case CountOverflow | UnexpectedEof:
			Console.log(error.message);
	}
}
```

The failure identity is a Haxe enum as ruled in `docs/specs/features/01-enums-and-pattern-matching.md`; the exception class carries the enum instance:

```haxe
enum VectorError {
	BadMagic;
	CountOverflow;
	UnexpectedEof;
	TrailingBytes(remaining:Int);
}

class VectorException extends haxe.Exception {
	public final error:VectorError;

	public function new(error:VectorError) {
		this.error = error;
		super(describeError(error));
	}
}
```

Throwing any value that is not an instance of such an enum-carrying `haxe.Exception` subclass is rejected before generation by the interception defined in `docs/specs/style/01-haxe-style-standard.md`. A bare `throw "string"`, a `throw` of a Haxe enum value without the exception wrapper, and a `throw` of `new haxe.Exception(message)` whose identity lives only in the message are all rejections.

In the Haxe typed AST, exception operations are represented by `haxe.macro.TypedExprDef.TThrow(e:TypedExpr)` and `haxe.macro.TypedExprDef.TTry(e:TypedExpr, catches:Array<{v:TVar, expr:TypedExpr}>)`. In the macro expression AST, these map to `haxe.macro.Expr.ExprDef.EThrow` and `haxe.macro.Expr.ExprDef.ETry`.

## Current translations

### Haxe (`samples/boring/VectorCodec.hx`)

```haxe
public static function decode(bytes:Bytes):Array<GlyphMetrics> {
	final reader = new BinaryReader(bytes);
	final magic = reader.readAscii(MAGIC.length);
	if (magic != MAGIC) {
		throw new VectorException(BadMagic);
	}
	final count = reader.readU32();
	// ...
	if (reader.remaining() != 0) {
		throw new VectorException(TrailingBytes(reader.remaining()));
	}
	return records;
}
```

The variant value inside `VectorException` is the failure identity; the message is derived from it.

### Rust (`reference/rust/src/lib.rs`)

```rust
pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
        return Err(VectorError::BadMagic);
    }
    let mut reader = VectorReader::new(&bytes[4..]);
    let count = reader.read_u32()?;
    let capacity = usize::try_from(count).map_err(|_| VectorError::CountOverflow)?;
    let mut records = Vec::with_capacity(capacity);
    for _ in 0..count {
        let code_point = reader.read_u32()?;
        let advance_em = reader.read_f64()?;
        let x_min = reader.read_f64()?;
        let y_min = reader.read_f64()?;
        let x_max = reader.read_f64()?;
        let y_max = reader.read_f64()?;
        records.push(GlyphMetrics {
            code_point,
            advance_em,
            bounds: BoundsEm {
                x_min,
                y_min,
                x_max,
                y_max,
            },
        });
    }
    let remaining = reader.remaining();
    if remaining != 0 {
        return Err(VectorError::TrailingBytes { remaining });
    }
    Ok(records)
}
```

### TypeScript (`reference/ts/src/vector-format.ts`)

```ts
export function decodeVector(bytes: Uint8Array): readonly GlyphMetricsRecord[] {
  const reader = new BinaryReader(bytes);
  const magic = reader.readAscii(VECTOR_MAGIC.length);
  if (magic !== VECTOR_MAGIC) {
    throw new VectorException({ kind: "BadMagic" });
  }
  const count = reader.readU32();
  const records: GlyphMetricsRecord[] = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    const codePoint = reader.readU32();
    const advanceEm = reader.readF64();
    const xMin = reader.readF64();
    const yMin = reader.readF64();
    const xMax = reader.readF64();
    const yMax = reader.readF64();
    const bounds = Object.freeze({ xMin, yMin, xMax, yMax });
    records[i] = Object.freeze({ codePoint, advanceEm, bounds });
  }
  if (reader.remaining() !== 0) {
    throw new VectorException({ kind: "TrailingBytes", remaining: reader.remaining() });
  }
  return Object.freeze(records);
}
```

The variant value on `VectorException` is the failure identity; the message is derived from it. The reader guards (`reference/ts/src/codec.ts`) throw the `UnexpectedEof` variant, mirroring the bounds checks of the other trees.

## Candidate translations

### Rust Candidate 1: Result enum with structured error variants (selected)

```rust
pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
        return Err(VectorError::BadMagic);
    }
    // ...
    Ok(records)
}
```

### Rust Candidate 2: Panicking execution on invalid input

```rust
pub fn decode_vector(bytes: &[u8]) -> Vec<GlyphMetrics> {
    if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
        panic!("bad vector magic");
    }
    // ...
    records
}
```

### Rust Candidate 3: Boxed dynamic error trait object

```rust
pub fn decode_vector(
    bytes: &[u8],
) -> Result<Vec<GlyphMetrics>, Box<dyn std::error::Error>> {
    if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
        return Err("bad vector magic".into());
    }
    // ...
    Ok(records)
}
```

### TypeScript Candidate 1: Typed exception class carrying the error union (selected)

```ts
export type VectorError =
  | { readonly kind: "BadMagic" }
  | { readonly kind: "CountOverflow" }
  | { readonly kind: "UnexpectedEof" }
  | { readonly kind: "TrailingBytes"; readonly remaining: number };

export class VectorException extends Error {
  readonly error: VectorError;

  constructor(error: VectorError) {
    super(describeError(error));
    this.name = "VectorException";
    this.error = error;
  }
}

export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  if (bytes.length < 4 || !hasVectorMagic(bytes)) {
    throw new VectorException({ kind: "BadMagic" });
  }
  // ...
  if (reader.remaining() !== 0) {
    throw new VectorException({
      kind: "TrailingBytes",
      remaining: reader.remaining(),
    });
  }
  return records;
}
```

The `VectorError` union follows `docs/specs/features/01-enums-and-pattern-matching.md`; `describeError` is the same per-variant function that spec rules, so the message derives from the variant and no consumer reads it back for identity.

### TypeScript Candidate 2: One Error subclass per variant

```ts
export class BadMagicError extends Error {}
export class CountOverflowError extends Error {}
export class UnexpectedEofError extends Error {}
export class TrailingBytesError extends Error {
  constructor(readonly remaining: number) {
    super(`trailing bytes in vector: ${remaining}`);
  }
}

throw new BadMagicError();
```

### TypeScript Candidate 3: Standard Error instances carrying identity in the message

```ts
export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  if (bytes.length < 4) {
    throw new Error("vector ended mid-record");
  }
  // ...
  return records;
}
```

### TypeScript Candidate 4: Discriminated Result object union

```ts
export type Result<T, E> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E };

export function decodeVector(
  bytes: Uint8Array,
): Result<GlyphMetricsRecord[], VectorError> {
  if (bytes.length < 4) {
    return { ok: false, error: { kind: "UnexpectedEof" } };
  }
  // ...
  return { ok: true, value: records };
}
```

### Kotlin Candidate 1: Sealed exception hierarchy thrown at failure sites (selected)

```kotlin
sealed class VectorException(message: String) : Exception(message) {
    data object BadMagic : VectorException("bad vector magic")
    data object CountOverflow : VectorException("record count exceeds u32")
    data object UnexpectedEof : VectorException("vector ended mid-record")
    data class TrailingBytes(val remaining: Int) :
        VectorException("trailing bytes in vector: $remaining")
}

fun decodeVector(bytes: ByteArray): List<GlyphMetrics> {
    if (bytes.size < 4) {
        throw VectorException.UnexpectedEof
    }
    // ...
    return records
}
```

### Kotlin Candidate 2: kotlin.runCatching Result returns

```kotlin
fun decodeVector(bytes: ByteArray): Result<List<GlyphMetrics>> =
    runCatching {
        // ...
        records
    }
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Result enum) | Return values pass in CPU registers without stack unwinding overhead. | Explicit Result return types require caller handling and prevent silent error ignoring. | Error variant definitions are centralized in the crate error enum. | The question mark operator provides idiomatic error propagation to Rust engineers. |
| Rust Candidate 2 (Panics) | Normal path executes quickly but panics incur heavy unwind table execution. | Function signatures hide failure possibilities from callers. | Error strings are duplicated across individual panic call sites. | Unhandled panics crash host processes unexpectedly. |
| Rust Candidate 3 (Boxed dynamic error) | Allocating a box per error creates heap pressure during error recovery. | The trait object erases the variant set, so callers match on downcast or string. | String formatting runs at every instantiation site. | Type erasure hides the domain variants from assertions. |
| TS Candidate 1 (Typed exception with error union) | Successful paths allocate zero error objects; a failure allocates one exception whose payload is the union value. | `instanceof VectorException` followed by a discriminant check narrows to the exact variant and its payload fields; exhaustiveness follows `docs/specs/features/01-enums-and-pattern-matching.md`. | One exception class and the shared `VectorError` union serve every throw site and every catching site. | The throw states the variant in place; the catch reads as a switch over `error.kind`. |
| TS Candidate 2 (Subclass per variant) | Successful paths allocate zero error objects; each failure invokes one subclass constructor chain. | Variant discrimination requires sequential `instanceof` checks with no compile-time exhaustiveness. | One class per variant multiplies declarations that the union states once. | Catch sites chain instanceof tests whose order a reader must follow. |
| TS Candidate 3 (Message-string Error) | Successful paths allocate zero error objects. | The failure identity lives in a formatted string, so consumers discriminate by matching message text and the compiler checks none of it. | Every throw site states a message the variant set already defines. | Message wording becomes an API contract without a type behind it. |
| TS Candidate 4 (Result union) | Every call allocates a wrapper object on the successful path. | Return signatures state success and failure types explicitly. | Callers unwrap result containers across every intermediate helper function. | Monadic wrapper unwrapping adds verbosity to standard procedural pipelines. |
| Kotlin Candidate 1 (Sealed exceptions) | Successful paths execute zero error construction; failures allocate one exception with the payload inline. | The sealed hierarchy names every failure mode, and `when` over the caught type is exhaustive. | One hierarchy serves decode, encode, and accessor validation. | Throw sites read as one line per guard clause. |
| Kotlin Candidate 2 (runCatching Result) | `Result` wrapping allocates a boxed outcome for every successful return, and `runCatching` captures every exception including programming errors. | The catch-all boundary hides which failures the type intends to model. | Every caller unwraps through `getOrElse` or `fold` chains. | Wrapper indirection separates guard clauses from their failure messages. |

## Ruling

Failure identity is a closed variant set defined once per domain and shared by all four trees. Each domain declares its variants in one commit touching every tree: the Haxe enum and its exception wrapper, the Rust error enum, the TypeScript error union and exception class, and the Kotlin sealed exception hierarchy. The variant set of `docs/specs/binary/01-binary-record-layout.md` is the reference example: `BadMagic`, `CountOverflow`, `UnexpectedEof`, and `TrailingBytes` with one `remaining` payload.

- Rust: all fallible operations return `Result<T, DomainError>` with structured variants. Candidate 1.
- Haxe: throw sites construct a `haxe.Exception` subclass that carries a Haxe enum instance naming the variant. The interception rejects throw expressions of any other shape, as ruled in `docs/specs/style/01-haxe-style-standard.md`.
- TypeScript: throw sites construct one exception class carrying the error union value of `docs/specs/features/01-enums-and-pattern-matching.md`. Candidate 1. Catch sites narrow with `instanceof VectorException` and then branch on the discriminant; payload access after narrowing requires no cast.
- Kotlin: throw sites construct the sealed exception hierarchy with one variant per failure mode. Candidate 1.

### Catch-site lowering (`TTry`)

A `try` region with typed catch clauses lowers on every target; the
shape follows the throw rulings above.

- Haxe stage 1: the native `try`/`catch`; the oracle needs no
  adaptation.
- TypeScript: native `try`/`catch`. Each clause narrows with
  `instanceof` on its exception class and handles the match; the
  non-matching arm rethrows the caught value unchanged. A region in
  expression position hoists to a statement and a `let` binding, since
  the TypeScript `try` statement produces no value: `let v; try { v =
  body; } catch (error) { if (error instanceof X) { v = handler; } else
  { throw error; } }`.
- Kotlin: native typed `catch`. A region in expression position stays
  an expression, since the Kotlin `try` produces a value.
- Rust: the region body lowers into a closure returning
  `Result<regionValue, caughtEnum>`, where each `throw` inside the body
  is the Rust target's `Err` return; the outcome is matched immediately, the
  `Ok` arm is the region value, and the `Err` arm runs the handler with
  the payload enum bound. The catch variable's payload access
  (`error.error` on the Haxe side) lowers to the bound enum value; the
  message accessor lowers to the shared describe function.

Two restrictions keep the region translatable, each with a named
rejection and a sanctioned alternative:

- A region whose body can throw exception classes beyond the caught
  class is rejected (`tryRegionMixedDomains`); the mixed-domain region
  has no single closure error type. The alternative is nested regions,
  one per domain.
- A region body containing `return`, `break`, or `continue` is rejected
  (`tryRegionControlFlow`); control flow crossing the closure boundary
  cannot lower. The handler lowers outside the closure, so a `return`
  inside a handler keeps its function-edge meaning on every target. The
  alternative for body control flow is hoisting: evaluate the region to
  a value and place the control-flow statement after it.

Fallibility absorption: a domain fully handled by a region's clauses
does not infect the enclosing function on the Rust target. The
fallibility fixpoint walks a `TTry` by absorbing the caught enum's
edges from the body and keeping every edge of the handler expressions,
so a wrapper that converts reader faults to its own domain lowers as
an infallible-to-the-caller function only when no uncaught domain
escapes it.

Messages are display text derived from the variant at construction time. No consumer discriminates a failure by reading or matching a message string; tests assert variant identity, never message content. Adding a failure mode adds one variant to every tree in the same commit, and the exhaustiveness checking of `docs/specs/features/01-enums-and-pattern-matching.md` fails the build of any tree whose handling was not extended.

Kotlin `runCatching` and catch-all `Result` returns are banned in codec code because they capture programming errors alongside domain failures. Rust panic and `Box<dyn Error>` returns are banned for the reasons in the judgment table.

## Test hooks

Error handling is asserted in:
- `tests/rust/vector.rs` (lines 72-96) asserting `VectorError::BadMagic`, `VectorError::UnexpectedEof`, and `VectorError::TrailingBytes`.
- `tests/haxe/Main.hx` (lines 102-114) asserting that decoding bad magic and a truncated vector throw the `BadMagic` and `UnexpectedEof` variants by matching `error.error`.
- `tests/ts/codec.test.ts` (lines 67-105) asserting the variant through `error.error.kind` for wrong magic, trailing bytes (including the `remaining` payload), and a truncated vector; the wrong-magic and truncated payloads assert two distinct variants, and no assertion reads a message.
- `tests/ts/error-structure.test.ts` scanning `reference/ts/src` and `samples` for throw sites of bare `Error` or bare `haxe.Exception` in codec code and rejecting any hit.
