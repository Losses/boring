# Standard library spec 04: haxe.ds.Vector

## Scope

This specification rules the translation of fixed-length contiguous arrays (`haxe.ds.Vector<T>`) into Rust, TypeScript, and Kotlin. In the current codebase, fixed-size byte headers appear in Rust as `[u8; 4]` and const generic chunk arrays `[u8; N]` in `reference/rust/src/lib.rs`, pre-allocated record vectors appear in Rust as `Vec::with_capacity` in `reference/rust/src/lib.rs`, dynamically populated record lists appear in Haxe in `samples/boring/VectorCodec.hx`, pre-allocated buffers appear in TypeScript in `reference/ts/src/codec.ts` and `reference/ts/src/vector-format.ts`, and counted fills appear in Kotlin as the array initializer in `reference/kotlin/src/boring/VectorCodec.kt`.

## Haxe construct

`haxe.ds.Vector<T>` represents a fixed-length indexed collection with constant-time indexed access and no dynamic resizing. Its exports include:

- `new Vector<T>(length:Int)`: allocates a vector of fixed length.
- `v.get(index:Int):T`: retrieves the element at the specified index.
- `v.set(index:Int, val:T):T`: stores the element at the specified index.
- `v.length:Int`: returns the immutable length of the vector.
- `v.blit(srcPos:Int, dst:Vector<T>, dstPos:Int, len:Int):Void`: copies elements between vectors.
- `v.toArray():Array<T>`: converts vector contents into a standard dynamic array.
- `v.toData():VectorData<T>`: extracts underlying platform-specific storage.
- `Vector.fromArrayCopy(a:Array<T>):Vector<T>`: copies array elements into a new vector.
- `Vector.fromData(data:VectorData<T>):Vector<T>`: wraps platform data without copying.
- `v.copy():Vector<T>`: creates a shallow copy of the vector.
- `v.join(sep:String):String`: concatenates string representations of elements.
- `v.sort(f:(a:T, b:T) -> Int):Void`: sorts vector elements in place.

On the JavaScript target, `haxe.ds.Vector` compiles to a native JS `Array` initialized with `new Array(length)`. On C++ and HashLink, it compiles to fixed-size contiguous memory blocks.

In the Haxe typed AST, `haxe.ds.Vector` is represented by `haxe.macro.Type.TAbstract` wrapping the underlying vector class.

## Current translations

### Haxe (`samples/boring/VectorCodec.hx`)

Haxe currently uses `Array<GlyphMetrics>` for record collections:

```haxe
public static function encode(records:Array<GlyphMetrics>):Bytes {
	// ...
}

public static function decode(bytes:Bytes):Array<GlyphMetrics> {
	final count = reader.readU32();
	final records = new Array<GlyphMetrics>();
	for (index in 0...count) {
		// ...
		records[index] = {
			codePoint: codePoint,
			advanceEm: advanceEm,
			bounds: { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax }
		};
	}
	return records;
}
```

### Rust (`reference/rust/src/lib.rs`)

```rust
pub const VECTOR_MAGIC: &[u8; 4] = b"BRG1";

fn take_n<const N: usize>(&mut self) -> Result<[u8; N], VectorError> {
    match self.bytes[self.offset..].split_first_chunk::<N>() {
        Some((head, _)) => {
            self.offset += N;
            Ok(*head)
        }
        None => Err(VectorError::UnexpectedEof),
    }
}

pub fn decode_vector(bytes: &[u8]) -> Result<Vec<GlyphMetrics>, VectorError> {
    // ...
    let count = reader.read_u32()?;
    let capacity = usize::try_from(count).map_err(|_| VectorError::CountOverflow)?;
    let mut records = Vec::with_capacity(capacity);
    // ...
}
```

### TypeScript (`reference/ts/src/codec.ts`, `reference/ts/src/vector-format.ts`)

```ts
export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  // ...
  const count = reader.readU32();
  const records: GlyphMetricsRecord[] = new Array<GlyphMetricsRecord>(count);
  for (let i = 0; i < count; i += 1) {
    // ...
    records[i] = { codePoint, advanceEm, bounds };
  }
  return records;
}
```

### Kotlin (`reference/kotlin/src/boring/VectorCodec.kt`)

```kotlin
fun decode(bytes: ByteArray): List<GlyphMetrics> {
    // ...
    val count = reader.readU32()
    val records = Array(count) { index ->
        GlyphMetrics(
            codePoint = reader.readU32(),
            advanceEm = reader.readF64(),
            bounds = GlyphBounds(
                xMin = reader.readF64(),
                yMin = reader.readF64(),
                xMax = reader.readF64(),
                yMax = reader.readF64()
            )
        )
    }
    return records.asList()
}
```

## Candidate translations

### Rust Candidate 1: Fixed arrays [T; N] for static sizes and Vec with capacity for dynamic counts

```rust
pub fn read_magic(reader: &mut VectorReader<'_>) -> Result<[u8; 4], VectorError> {
    reader.take_n::<4>()
}

pub fn create_record_buffer(capacity: usize) -> Vec<GlyphMetrics> {
    Vec::with_capacity(capacity)
}
```

### Rust Candidate 2: Boxed slice Box<[T]> for all collections

```rust
pub fn decode_vector_boxed(bytes: &[u8]) -> Result<Box<[GlyphMetrics]>, VectorError> {
    let records = Vec::new();
    // ...
    Ok(records.into_boxed_slice())
}
```

### TypeScript Candidate 1: TypedArray for byte buffers

```ts
export function createRecordBuffer(count: number): GlyphMetricsRecord[] {
  const records: GlyphMetricsRecord[] = [];
  records.length = 0;
  return records;
}
```

### TypeScript Candidate 2: Pre-allocated Array constructor with index assignment (selected)

```ts
export function createFixedRecords(count: number): GlyphMetricsRecord[] {
  const records = new Array<GlyphMetricsRecord>(count);
  return records;
}
```

### Rust Candidate 3: Unrolled constant stores for static-length constant arrays

```rust
pub const VECTOR_MAGIC_U32: u32 = 0x42524731;

pub fn encode_magic(bytes: &mut Vec<u8>) {
    bytes.extend_from_slice(&VECTOR_MAGIC_U32.to_be_bytes());
}
```

### TypeScript Candidate 3: Unrolled constant stores for static-length constant arrays

```ts
const MAGIC_U32 = 0x42524731;

function encodeMagic(writer: BinaryWriter): void {
  writer.writeU32(MAGIC_U32);
}
```

### Kotlin Candidate 1: Pre-sized ArrayList for mutable lists (selected where the API requires MutableList)

```kotlin
fun createRecordBuffer(count: Int): ArrayList<GlyphMetrics> {
    return ArrayList(count)
}

fun readMagic(reader: BinaryReader): Unit {
    reader.readAscii(4)
}
```

### Kotlin Candidate 2: Array constructor with per-element initializer lambda (selected for fixed-size fills)

```kotlin
fun decodeRecords(reader: BinaryReader, count: Int): Array<GlyphMetrics> {
    return Array(count) { index -> readRecord(reader) }
}
```

### Kotlin Candidate 3: Unrolled constant stores for static-length constant arrays

```kotlin
const val MAGIC_U32 = 0x42524731

fun encodeMagic(writer: BinaryWriter): Unit {
    writer.writeU32(MAGIC_U32)
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Fixed array and Vec with capacity) | Stack arrays incur zero allocation while Vec pre-allocation eliminates vector reallocation overhead during decoding. | Type signatures explicitly distinguish compile-time fixed buffers from runtime-sized vectors. | Direct collection construction requires no intermediate conversion layers. | Standard Rust array and Vec types communicate collection lifetimes directly. |
| Rust Candidate 2 (Boxed slice) | Converting Vec to Box<[T]> performs an extra memory reallocation to shrink excess capacity. | Boxed slices prevent further element accumulation without converting back to Vec. | Boxing requires an extra conversion step after decoding loops finish. | Boxed slice signatures add pointer notation to straightforward dynamic collections. |
| TS Candidate 1 (Array with push discipline) | A push-built array grows through geometric reallocation and copy passes; the count is known before the loop, so the growth work is pure overhead. | Array length discipline ensures elements populate sequentially without sparse holes. | Standard array methods integrate directly with JSON parsers and test runners. | Standard JavaScript arrays communicate collection mechanics directly. |
| TS Candidate 2 (Array constructor) (selected) | One upfront allocation of the exact size and plain indexed stores; no growth copies, no per-iteration capacity checks. | The constructor argument states the element count at the allocation site. | The index the fill loop already carries is the store index; no extra state. | The declaration states the final length the loop establishes. |
| Rust Candidate 3 (Unrolled constants) | Constant writes fold into single machine stores with zero loop and bounds check overhead. | One constant states the exact bytes of the whole field. | The loop plus its length bound disappear entirely. | Readers see the wire bytes as one literal value. |
| TS Candidate 3 (Unrolled constants) | Literal constant loads execute with no loop, no bounds check, and no closure. | One constant declares the entire field payload, so no length variable can drift from the data. | The generator derives the constant from the record format declaration once at build time. | Readers see the exact wire bytes at the call site. |
| Kotlin Candidate 1 (Pre-sized ArrayList) | Pre-sized backing storage removes reallocation; each `add` still executes a store plus a size update, and HotSpot eliminates part of that path and never all of it. | The declared type states the mutable-list requirement explicitly. | One construction per collection with no wrapper layers. | Standard Kotlin collection types state the layout directly. |
| Kotlin Candidate 2 (Array initializer) (selected for fixed-size fills) | One exact-size backing array allocation; the initializer lambda inlines into the construction, so no growth check and no residual `add` path executes. | The constructor argument states the element count at the allocation site. | The fill loop, its counter, and its store statement are expressed as one construction. | The declaration states the final array and how every element is computed. |
| Kotlin Candidate 3 (Unrolled constants) | `const val` folds into the call site with no loop, no bounds check, and no closure. | One constant declares the entire field payload. | The generator derives the constant from the record format declaration once at build time. | Readers see the exact wire bytes at the call site. |

## Ruling

Compile-time fixed-length byte buffers translate to fixed-size array types (`[u8; N]`) in Rust, fixed-size `Uint8Array` views in TypeScript, and `ByteArray` slices with a named length constant in Kotlin. Runtime collections with known lengths translate to the platform's pre-allocated fill form: `Vec::with_capacity(capacity)` with `push` in Rust, `new Array<T>(count)` with indexed stores `records[i] = ...` in TypeScript, the array initializer `Array(count) { index -> ... }` in Kotlin when the destination is a fixed-size array, `ArrayList<T>(count)` with `add` in Kotlin only where the API requires a mutable list, and indexed stores `records[index] = ...` on a fresh Haxe array, whose JavaScript lowering allocates the exact size. The fill and the allocation share the count, one allocation covers the whole fill, and no growth copy runs. The `arrayOfNulls` plus `requireNoNulls` form is retired: it fills through a nullable view and casts at the boundary, while the array initializer states the fill directly.

Static-length arrays whose length and contents are compile-time constants unroll at build time. When the constant width matches a primitive wire write, the whole array folds into one constant: `writeAscii("BRG1")` becomes the u32 constant `0x42524731` written through `writeU32`, replacing the per-character loop in `BinaryWriter.writeAscii` (`samples/boring/BinaryWriter.hx`, lines 38-42) and `writeAscii` in `reference/ts/src/codec.ts` (lines 46-52). The same fold produces the `Int` constant `0x42524731` in Kotlin, which fits the positive `Int` range. When the constant width matches no primitive write, the generator emits one named constant per element and references the constants by name; no runtime array is allocated for data whose contents are already known at compile time. Kotlin declares no `const` arrays, so per-element constants are the only constant-array form. Generated and handwritten codec code keeps no per-element loop over compile-time constant data. Index-computed lookup tables sit outside this ruling: a constant array of `Int` with more than 64 elements follows the data-table emission of `docs/specs/features/20-compile-time-data-tables.md`, because computed-index access cannot be expressed as per-element constants.

Length mismatches on wire decoding fail immediately with `VectorError::UnexpectedEof` in Rust, the thrown `VectorException` carrying `UnexpectedEof` in Haxe and TypeScript, and thrown `VectorException.UnexpectedEof` in Kotlin.

## Test hooks

Fixed-size chunk reading and collection allocations are verified in:
- `tests/rust/vector.rs` (lines 54-70, 80-86)
- `tests/haxe/Main.hx` (lines 60-66, 79-88)
- `tests/ts/codec.test.ts` (lines 42-53)
- `tests/ts/vector.test.ts` (lines 13-25)
