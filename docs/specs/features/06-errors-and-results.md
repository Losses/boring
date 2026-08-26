# Feature spec 06: Errors and results

## Scope

This specification rules error representation and failure propagation across Haxe, Rust, and TypeScript. In the current repository, error handling appears in Haxe via `throw new haxe.Exception(...)` in `haxe/src/boring/VectorCodec.hx` (lines 32 and 50), in Rust via `Result<T, VectorError>` in `rust/src/lib.rs` (lines 84 and 100), and in TypeScript via `throw new Error(...)` in `ts/src/vector-format.ts` (lines 34 and 49) and `ts/src/vector-json.ts`.

## Haxe construct

Haxe uses structured exceptions derived from `haxe.Exception` for error propagation:

```haxe
if (magic != MAGIC) {
	throw new haxe.Exception('bad vector magic: $magic');
}
```

Exceptions unwind the call stack until intercepted by a `try ... catch` block:

```haxe
try {
	VectorCodec.decode(bytes);
} catch (error:haxe.Exception) {
	Console.log(error.message);
}
```

In the Haxe typed AST, exception operations are represented by `haxe.macro.TypedExprDef.TThrow(e:TypedExpr)` and `haxe.macro.TypedExprDef.TTry(e:TypedExpr, catches:Array<{v:TVar, expr:TypedExpr}>)`. In the macro expression AST, these map to `haxe.macro.Expr.ExprDef.EThrow` and `haxe.macro.Expr.ExprDef.ETry`.

## Current translations

### Haxe (`haxe/src/boring/VectorCodec.hx`)

```haxe
public static function decode(bytes:Bytes):Array<GlyphMetrics> {
	final reader = new BinaryReader(bytes);
	final magic = reader.readAscii(MAGIC.length);
	if (magic != MAGIC) {
		throw new haxe.Exception('bad vector magic: $magic');
	}
	final count = reader.readU32();
	// ...
	if (reader.remaining() != 0) {
		throw new haxe.Exception('trailing bytes in vector: ${reader.remaining()}');
	}
	return records;
}
```

### Rust (`rust/src/lib.rs`)

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

### TypeScript (`ts/src/vector-format.ts`)

```ts
export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  const reader = new BinaryReader(bytes);
  const magic = reader.readAscii(VECTOR_MAGIC.length);
  if (magic !== VECTOR_MAGIC) {
    throw new Error(`bad vector magic: ${magic}`);
  }
  const count = reader.readU32();
  const records: GlyphMetricsRecord[] = [];
  for (let i = 0; i < count; i += 1) {
    const codePoint = reader.readU32();
    const advanceEm = reader.readF64();
    const xMin = reader.readF64();
    const yMin = reader.readF64();
    const xMax = reader.readF64();
    const yMax = reader.readF64();
    const bounds = { xMin, yMin, xMax, yMax };
    records.push({ codePoint, advanceEm, bounds });
  }
  if (reader.remaining() !== 0) {
    throw new Error(`trailing bytes in vector: ${reader.remaining()}`);
  }
  return records;
}
```

## Candidate translations

### Rust Candidate 1: Result enum with structured error variants

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

### TypeScript Candidate 1: Thrown Error instances

```ts
export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  if (bytes.length < 4) {
    throw new Error("vector ended mid-record");
  }
  // ...
  return records;
}
```

### TypeScript Candidate 2: Discriminated Result object union

```ts
export type Result<T, E> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: E };

export function decodeVector(
  bytes: Uint8Array,
): Result<GlyphMetricsRecord[], string> {
  if (bytes.length < 4) {
    return { ok: false, error: "vector ended mid-record" };
  }
  // ...
  return { ok: true, value: records };
}
```

### TypeScript Candidate 3: Sentinel null on error

```ts
export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] | null {
  if (bytes.length < 4) {
    return null;
  }
  // ...
  return records;
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Result enum) | Return values pass in CPU registers without stack unwinding overhead. | Explicit Result return types require caller handling and prevent silent error ignoring. | Error variant definitions are centralized in the crate error enum. | The question mark operator provides idiomatic error propagation to Rust engineers. |
| Rust Candidate 2 (Panics) | Normal path executes quickly but panics incur heavy unwind table execution. | Function signatures hide failure possibilities from callers. | Error strings are duplicated across individual panic call sites. | Unhandled panics crash host processes unexpectedly. |
| TS Candidate 1 (Thrown Error) | Successful execution paths incur zero object allocation overhead. | Exception throwing is untyped in TypeScript function signatures. | Standard Error classes integrate with host platform stack traces. | Idiomatic JavaScript exception handling communicates failures directly to TypeScript developers. |
| TS Candidate 2 (Result object union) | Every function call allocates a wrapper object on the heap. | Return signatures state success and failure types explicitly. | Callers must unwrap result containers across every intermediate helper function. | Monadic wrapper unwrapping adds verbosity to standard procedural pipelines. |
| TS Candidate 3 (Sentinel null) | Returning null incurs zero heap allocation. | Null provides no diagnostic context explaining why an operation failed. | Callers must write manual null guards without access to error causes. | Null returns conceal the underlying reason for decoder failures. |

## Ruling

In Rust, all fallible codec operations return `Result<T, VectorError>` with structured error variants. In Haxe, errors throw `haxe.Exception`. In TypeScript, codec decoding functions throw standard `Error` instances containing descriptive messages.

This ruling respects `AGENT.md` requirements for zero `as` casts and explicit `Result` returns in Rust, while maintaining idiomatic exception propagation in Haxe and TypeScript.

## Test hooks

Error handling is asserted in:
- `tests/rust/vector.rs` (lines 72-96) asserting `VectorError::BadMagic`, `VectorError::UnexpectedEof`, and `VectorError::TrailingBytes`.
- `tests/haxe/Main.hx` (lines 97-104) asserting that decoding bad magic raises an exception.
- `tests/ts/codec.test.ts` (lines 66-80) asserting that bad magic and trailing bytes throw errors.
