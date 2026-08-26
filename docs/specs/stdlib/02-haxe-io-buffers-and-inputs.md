# Standard library spec 02: haxe.io.BytesBuffer and input streams

## Scope

This specification rules sequential byte buffer writing, stream reading, endianness configuration, and bounds checking across Haxe, Rust, and TypeScript. In the current codebase, buffer building appears in Haxe via `haxe.io.BytesBuffer` in `haxe/src/boring/BinaryWriter.hx` (lines 4, 12, 15), stream reading appears in Haxe via cursor tracking in `haxe/src/boring/BinaryReader.hx` (lines 11-57), slice extraction and big-endian conversions appear in Rust in `rust/src/lib.rs` (lines 50-82, 84-98), and growable buffer writing and `DataView` reading appear in TypeScript in `ts/src/codec.ts` (lines 10-117).

## Haxe construct

The Haxe I/O library provides three sequential buffer classes:

- `haxe.io.BytesBuffer`: A growable buffer accumulating raw bytes via `addByte(v:Int)`, `addBytes(src:Bytes, pos:Int, len:Int)`, and `getBytes():Bytes`. It carries no built-in multi-byte endianness dispatch.
- `haxe.io.BytesInput`: A stream reader wrapping a `Bytes` instance with a position cursor. It provides `readByte():Int`, `readInt32():Int`, `readDouble():Float`, `readString(len:Int):String`, and property `bigEndian:Bool`.
- `haxe.io.BytesOutput`: A stream writer wrapping a `BytesBuffer` with big-endian support via `writeInt32(v:Int)`, `writeDouble(v:Float)`, and property `bigEndian:Bool`.

Per-target differences: `BytesInput` and `BytesOutput` perform per-byte conversions using target floating-point representations. To maintain strict IEEE 754 bit-identical float representations across all targets, this repository bypasses `BytesInput`/`BytesOutput` endian methods in favor of explicit bitwise operations and `haxe.io.FPHelper` conversions in `BinaryReader` and `BinaryWriter`.

In the Haxe typed AST, these classes are represented by `haxe.macro.Type.TClassDecl` referencing their respective standard library definitions.

## Current translations

### Haxe (`haxe/src/boring/BinaryReader.hx`, `haxe/src/boring/BinaryWriter.hx`)

```haxe
class BinaryWriter {
	final buffer:BytesBuffer;

	public function writeU32(value:Int):Void {
		buffer.addByte((value >>> 24) & 0xFF);
		buffer.addByte((value >>> 16) & 0xFF);
		buffer.addByte((value >>> 8) & 0xFF);
		buffer.addByte(value & 0xFF);
	}

	public function writeF64(value:Float):Void {
		final bits = haxe.io.FPHelper.doubleToI64(value);
		writeU32(bits.high);
		writeU32(bits.low);
	}
}

class BinaryReader {
	final bytes:Bytes;
	var offset:Int;

	public function readU32():Int {
		final value = (bytes.get(offset) << 24)
			| (bytes.get(offset + 1) << 16)
			| (bytes.get(offset + 2) << 8)
			| bytes.get(offset + 3);
		offset += 4;
		return value;
	}
}
```

### Rust (`rust/src/lib.rs`)

```rust
impl<'a> VectorReader<'a> {
    pub fn read_u32(&mut self) -> Result<u32, VectorError> {
        Ok(u32::from_be_bytes(self.take_n::<4>()?))
    }

    pub fn read_f64(&mut self) -> Result<f64, VectorError> {
        Ok(f64::from_bits(u64::from_be_bytes(self.take_n::<8>()?)))
    }

    fn take_n<const N: usize>(&mut self) -> Result<[u8; N], VectorError> {
        match self.bytes[self.offset..].split_first_chunk::<N>() {
            Some((head, _)) => {
                self.offset += N;
                Ok(*head)
            }
            None => Err(VectorError::UnexpectedEof),
        }
    }
}
```

### TypeScript (`ts/src/codec.ts`)

```ts
export class BinaryReader {
  private readonly view: DataView;
  private offset: number;

  readU32(): number {
    const value = this.view.getUint32(this.offset, false);
    this.offset += 4;
    return value;
  }

  readF64(): number {
    const value = this.view.getFloat64(this.offset, false);
    this.offset += 8;
    return value;
  }
}
```

## Candidate translations

### Rust Candidate 1: Core from_be_bytes with const split_first_chunk bounds check

```rust
impl<'a> VectorReader<'a> {
    pub fn read_u32(&mut self) -> Result<u32, VectorError> {
        Ok(u32::from_be_bytes(self.take_n::<4>()?))
    }

    fn take_n<const N: usize>(&mut self) -> Result<[u8; N], VectorError> {
        match self.bytes[self.offset..].split_first_chunk::<N>() {
            Some((head, _)) => {
                self.offset += N;
                Ok(*head)
            }
            None => Err(VectorError::UnexpectedEof),
        }
    }
}
```

### Rust Candidate 2: Byteorder crate ReadBytesExt trait on mutable slices

```rust
use byteorder::{BigEndian, ReadBytesExt};

pub fn read_u32(cursor: &mut &[u8]) -> Result<u32, VectorError> {
    cursor.read_u32::<BigEndian>().map_err(|_| VectorError::UnexpectedEof)
}
```

### TypeScript Candidate 1: DataView with explicit big-endian flag false

```ts
export class BinaryReader {
  private readonly view: DataView;
  private offset: number;

  readU32(): number {
    if (this.offset + 4 > this.view.byteLength) {
      throw new Error("vector ended mid-record");
    }
    const value = this.view.getUint32(this.offset, false);
    this.offset += 4;
    return value;
  }
}
```

### TypeScript Candidate 2: Manual bitwise arithmetic over Uint8Array

```ts
export class BinaryReader {
  private readonly buffer: Uint8Array;
  private offset: number;

  readU32(): number {
    const b0 = this.buffer[this.offset]!;
    const b1 = this.buffer[this.offset + 1]!;
    const b2 = this.buffer[this.offset + 2]!;
    const b3 = this.buffer[this.offset + 3]!;
    this.offset += 4;
    return ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) >>> 0;
  }
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Core from_be_bytes) | Const chunk extraction optimizes to single unaligned machine word reads without branching. | Slicing checks bounds once per read and returns explicit UnexpectedEof errors. | Standard library functions eliminate external crate dependencies. | Direct standard library methods state exact numeric decoding steps. |
| Rust Candidate 2 (byteorder crate) | The byteorder trait performs dynamic error mapping and cursor updates on each field. | Trait error types require custom mapping to crate domain errors. | External crate dependencies duplicate functionality provided by modern Rust core. | Trait imports add dependency weight for standard integer conversions. |
| TS Candidate 1 (DataView explicit endian) | DataView methods compile to native host byte-swap instructions on V8. | Setting the littleEndian parameter to false guarantees big-endian decoding on every engine. | Single DataView wrapper handles integers, floats, and bounds checks. | Explicit getUint32 and getFloat64 calls state field types directly. |
| TS Candidate 2 (Manual bitwise arithmetic) | Bitwise shifts require extra operations and scratch buffers for floating-point values. | Bitwise operators produce signed 32-bit integers requiring zero-fill shifts. | Float deserialization requires duplicating conversion logic between files. | Manual byte assembly adds arithmetic noise to straightforward field reads. |

## Ruling

The three language implementations share a uniform primitive set: big-endian unsigned integers (`readU16`/`writeU16`, `readU32`/`writeU32`), IEEE 754 64-bit floats (`readF64`/`writeF64`), and fixed-length ASCII strings (`readAscii`/`writeAscii`).

Bounds checking lives in reader slice extraction (`take_n` in Rust, `DataView` range checks in TypeScript, offset checks in Haxe) and writer capacity growth (`ensure` in TypeScript, growable `BytesBuffer` in Haxe, `Vec::extend_from_slice` in Rust).

## Test hooks

Primitive read and write operations, bounds checks, and float precision are asserted in:
- `tests/rust/vector.rs` (lines 54-96)
- `tests/haxe/Main.hx` (lines 89-104)
- `tests/ts/codec.test.ts` (lines 12-54)
