# Standard library spec 04: haxe.ds.Vector

## Scope

This specification rules the translation of fixed-length contiguous arrays (`haxe.ds.Vector<T>`) into Rust and TypeScript. In the current codebase, fixed-size byte headers appear in Rust as `[u8; 4]` in `rust/src/lib.rs` (line 24) and const generic chunk arrays `[u8; N]` in `rust/src/lib.rs` (line 73), pre-allocated record lists appear in Rust as `Vec::with_capacity` in `rust/src/lib.rs` (lines 86, 107), dynamically populated record lists appear in Haxe in `haxe/src/boring/VectorCodec.hx` (lines 13, 28, 35), and pre-allocated buffers appear in TypeScript in `ts/src/codec.ts` (line 16) and `ts/src/vector-format.ts` (lines 37, 54-56).

## Haxe construct

`haxe.ds.Vector<T>` represents a fixed-length indexed collection with constant-time indexed access and no dynamic resizing. Its module surface includes:

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

### Haxe (`haxe/src/boring/VectorCodec.hx`)

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
		records.push({
			codePoint: codePoint,
			advanceEm: advanceEm,
			bounds: { xMin: xMin, yMin: yMin, xMax: xMax, yMax: yMax }
		});
	}
	return records;
}
```

### Rust (`rust/src/lib.rs`)

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

### TypeScript (`ts/src/codec.ts`, `ts/src/vector-format.ts`)

```ts
export function decodeVector(bytes: Uint8Array): GlyphMetricsRecord[] {
  // ...
  const count = reader.readU32();
  const records: GlyphMetricsRecord[] = [];
  for (let i = 0; i < count; i += 1) {
    // ...
    records.push({ codePoint, advanceEm, bounds });
  }
  return records;
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

### TypeScript Candidate 1: TypedArray for byte buffers and pre-allocated Array with push discipline

```ts
export function createRecordBuffer(count: number): GlyphMetricsRecord[] {
  const records: GlyphMetricsRecord[] = [];
  records.length = 0;
  return records;
}
```

### TypeScript Candidate 2: Pre-allocated Array constructor with index assignment

```ts
export function createFixedRecords(count: number): GlyphMetricsRecord[] {
  const records = new Array<GlyphMetricsRecord>(count);
  return records;
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Fixed array and Vec with capacity) | Stack arrays incur zero allocation while Vec pre-allocation eliminates vector reallocation overhead during decoding. | Type signatures explicitly distinguish compile-time fixed buffers from runtime-sized vectors. | Direct collection construction requires no intermediate conversion layers. | Standard Rust array and Vec types communicate collection lifetimes directly. |
| Rust Candidate 2 (Boxed slice) | Converting Vec to Box<[T]> performs an extra memory reallocation to shrink excess capacity. | Boxed slices prevent further element accumulation without converting back to Vec. | Boxing requires an extra conversion step after decoding loops finish. | Boxed slice signatures add pointer notation to straightforward dynamic collections. |
| TS Candidate 1 (Array with push discipline) | Dynamic arrays pre-allocated with known capacity run with optimized V8 packed element transitions. | Array length discipline ensures elements populate sequentially without sparse holes. | Standard array methods integrate directly with JSON parsers and test runners. | Standard JavaScript arrays communicate collection mechanics directly. |
| TS Candidate 2 (Array constructor) | Pre-sizing with new Array allocates array slots upfront but initializes holes until populated. | Sparse array holes introduce undefined values when index loops terminate early. | Allocation sizing requires manual index tracking without sequential push benefits. | Index assignment loops add boilerplate compared to standard push patterns. |

## Ruling

Compile-time fixed-length byte buffers translate to fixed-size array types (`[u8; N]`) in Rust and fixed-size `Uint8Array` views in TypeScript. Runtime collections with known lengths translate to pre-allocated vectors (`Vec::with_capacity(capacity)`) in Rust and dense `Array<T>` collections in TypeScript and Haxe.

Length mismatches on wire decoding fail immediately with `VectorError::UnexpectedEof` in Rust and thrown `Error` instances in Haxe and TypeScript.

## Test hooks

Fixed-size chunk reading and collection allocations are verified in:
- `tests/rust/vector.rs` (lines 54-70, 80-86)
- `tests/haxe/Main.hx` (lines 60-66, 79-88)
- `tests/ts/codec.test.ts` (lines 42-53)
- `tests/ts/vector.test.ts` (lines 13-25)
