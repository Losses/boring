# Standard library spec 01: haxe.io.Bytes

## Scope

This specification rules the representation of contiguous byte arrays, buffer allocation, and byte slicing across Haxe, Rust, TypeScript, and Kotlin. In the current codebase, `haxe.io.Bytes` appears in Haxe in `haxe/src/boring/BinaryReader.hx` (lines 3, 12, 15), `haxe/src/boring/BinaryWriter.hx` (lines 3, 44-46), and `haxe/src/boring/VectorCodec.hx` (lines 3, 13, 28), in Rust as borrowed byte slices `&[u8]` and owned byte vectors `Vec<u8>` in `rust/src/lib.rs` (lines 51-54, 84, 100), and in TypeScript as `Uint8Array` in `ts/src/codec.ts` (lines 11, 54-56, 78-81) and `ts/src/vector-format.ts` (lines 15, 30). In Kotlin, byte arrays appear as `ByteArray` with cursor tracking in `kotlin/src/boring/BinaryReader.kt` and `kotlin/src/boring/BinaryWriter.kt`.

## Haxe construct

`haxe.io.Bytes` encapsulates an immutable-length contiguous sequence of unsigned 8-bit bytes. Its module surface includes:

- `Bytes.alloc(length:Int):Bytes`: allocates a zero-initialized byte buffer.
- `Bytes.ofString(s:String):Bytes`: encodes a UTF-8 string into bytes.
- `Bytes.ofHex(s:String):Bytes`: decodes a hexadecimal string into bytes.
- `Bytes.ofData(b:BytesData):Bytes`: wraps target-specific raw buffer storage.
- `b.get(pos:Int):Int`: reads an unsigned byte at the given zero-based index.
- `b.set(pos:Int, v:Int):Void`: writes an unsigned byte at the given zero-based index.
- `b.sub(pos:Int, len:Int):Bytes`: creates a copy of a byte sub-range.
- `b.blit(srcPos:Int, dst:Bytes, dstPos:Int, len:Int):Void`: copies bytes from source to destination.
- `b.length:Int`: returns total buffer byte count.
- `b.getString(pos:Int, len:Int):String`: decodes a UTF-8 string from a sub-range.
- `b.toHex():String`: encodes bytes into a hexadecimal string.

On the JavaScript target, `haxe.io.Bytes` wraps a `Uint8Array` over an `ArrayBuffer`. On C++ and HashLink, it wraps native memory allocations.

In the Haxe typed AST, `haxe.io.Bytes` is represented by `haxe.macro.Type.TClassDecl` referencing class `haxe.io.Bytes`.

## Current translations

### Haxe (`haxe/src/boring/BinaryReader.hx`, `haxe/src/boring/BinaryWriter.hx`, `haxe/src/boring/VectorCodec.hx`)

```haxe
public static function encode(records:Array<GlyphMetrics>):Bytes {
	final writer = new BinaryWriter();
	// ...
	return writer.finish();
}

public static function decode(bytes:Bytes):Array<GlyphMetrics> {
	final reader = new BinaryReader(bytes);
	// ...
}
```

### Rust (`rust/src/lib.rs`)

```rust
pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    let mut bytes = Vec::with_capacity(8 + records.len() * RECORD_BYTE_LENGTH);
    // ...
    Ok(bytes)
}

pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    if bytes.len() < 4 || &bytes[..4] != VECTOR_MAGIC {
        return Err(VectorError::BadMagic);
    }
    let mut reader = VectorReader::new(&bytes[4..]);
    // ...
}
```

### TypeScript (`ts/src/codec.ts`, `ts/src/vector-format.ts`)

```ts
export function encodeVector(records: readonly GlyphMetricsRecord[]): Uint8Array {
  const writer = new BinaryWriter();
  // ...
  return writer.finish();
}

export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  const reader = new BinaryReader(bytes);
  // ...
}
```

## Candidate translations

### Rust Candidate 1: Borrowed slices for readers, owning Vec for writers

```rust
pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    let mut reader = VectorReader::new(bytes);
    // ...
}

pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Vec<u8>, VectorError> {
    let mut bytes = Vec::with_capacity(capacity);
    // ...
    Ok(bytes)
}
```

### Rust Candidate 2: Boxed byte slices for all inputs and outputs

```rust
pub fn decode_vector(bytes: Box<[u8]>) -> Result<Vec<GlyphMetrics>, VectorError> {
    // ...
}

pub fn encode_vector(records: &[GlyphMetrics]) -> Result<Box<[u8]>, VectorError> {
    // ...
}
```

### TypeScript Candidate 1: Uint8Array view references across function boundaries

```ts
export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  const reader = new BinaryReader(bytes);
  // ...
}

export function encodeVector(records: readonly GlyphMetricsRecord[]): Uint8Array {
  const writer = new BinaryWriter();
  // ...
  return writer.finish();
}
```

### TypeScript Candidate 2: Raw ArrayBuffer instances

```ts
export function decodeVector(buffer: ArrayBuffer): GlyphMetricsRecord[] {
  const reader = new BinaryReader(new Uint8Array(buffer));
  // ...
}
```

### Kotlin Candidate 1: ByteArray with index-based access

```kotlin
fun decodeVector(bytes: ByteArray): List<GlyphMetrics> {
    val reader = BinaryReader(bytes)
    // ...
}

fun encodeVector(records: List<GlyphMetrics>): ByteArray {
    val writer = BinaryWriter()
    // ...
    return writer.finish()
}
```

### Kotlin Candidate 2: java.nio.ByteBuffer wrapping

```kotlin
import java.nio.ByteBuffer

fun decodeVector(bytes: ByteArray): List<GlyphMetrics> {
    val buffer = ByteBuffer.wrap(bytes)
    // ...
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Borrowed slice and Vec) | Borrowed slices avoid heap allocations during decoding while Vec provides growable pre-allocated encoding. | Function signatures distinguish owning buffers from borrowed views explicitly. | Zero adapter conversions are required between standard library collections. | Standard Rust slice and Vec types convey ownership semantics directly. |
| Rust Candidate 2 (Boxed byte slice) | Boxing forces heap allocation and ownership transfer for every read operation. | Moving ownership into decoder functions prevents callers from reusing input buffers. | Extra boxing and unboxing calls add conversion lines around buffer operations. | Explicit Box wrappers add syntactic noise to standard byte inspection APIs. |
| TS Candidate 1 (Uint8Array view) | TypedArray views wrap underlying ArrayBuffer storage with zero data copying. | Uint8Array encapsulates buffer references, byte offsets, and lengths in one object. | Shared view types integrate directly with DataView and web standard APIs. | Uint8Array is the standard binary primitive for modern TypeScript applications. |
| TS Candidate 2 (Raw ArrayBuffer) | ArrayBuffer requires wrapping with typed views before reading or writing bytes. | ArrayBuffer instances cannot represent sub-slices without separate offset parameters. | Callers must allocate view wrappers manually at each API boundary. | Passing raw ArrayBuffer objects obscures offset and length handling. |
| Kotlin Candidate 1 (ByteArray) | `ByteArray` is a flat JVM primitive array with direct indexed access and no view objects. | One type covers input and output, with length carried by the array itself. | Index arithmetic matches the Haxe reader structure line for line. | `ByteArray` is the standard Kotlin binary primitive on every target. |
| Kotlin Candidate 2 (ByteBuffer) | ByteBuffer adds position, limit, and mark state that the codec re-implements with its own cursor. | Buffer state is mutable through flip, rewind, and clear, inviting mode confusion. | Every read path chooses between buffer methods and manual index arithmetic. | Heap buffer wrappers add machinery the codec does not use. |

## Ruling

`haxe.io.Bytes` translates to borrowed byte slices (`&[u8]`) for input parameters and owned byte vectors (`Vec<u8>`) for output returns in Rust, to `Uint8Array` in TypeScript for all inputs and outputs, and to `ByteArray` in Kotlin for all inputs and outputs. Kotlin slice operations use `copyOfRange`, which copies as `Bytes.sub` does on the Haxe side.

Read operations borrow existing byte sequences without allocating intermediate buffers. Write operations accumulate data into growable structures and return compact contiguous buffers sized to the encoded payload.

## Test hooks

Byte buffer boundaries and round trips are asserted in:
- `tests/rust/vector.rs` (lines 7, 54-70)
- `tests/haxe/Main.hx` (lines 79-88)
- `tests/ts/codec.test.ts` (lines 13-54)
- `tests/ts/vector.test.ts` (lines 7-25)
