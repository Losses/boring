# Feature spec 07: Numeric tower

## Scope

This specification rules numeric type representations, bit widths, endian serialization, floating-point precision, and conversion restrictions across Haxe, Rust, and TypeScript. In the current codebase, numeric operations appear in Haxe in `haxe/src/boring/BinaryWriter.hx` and `haxe/src/boring/BinaryReader.hx`, in Rust in `rust/src/lib.rs`, and in TypeScript in `ts/src/codec.ts` and `ts/src/records.ts`.

## Haxe construct

Haxe defines two fundamental numeric primitive types and one standard library 64-bit integer type:
- `Int`: 32-bit signed two's-complement integer on the JavaScript and C++ targets (31-bit signed on Neko).
- `Float`: 64-bit IEEE 754 double-precision floating-point number.
- `haxe.Int64`: 64-bit signed integer library type.

Bitwise operators in Haxe operate on 32-bit signed integers. Unsigned bit shifting uses the zero-fill right shift operator `>>>`. Conversions between 64-bit floating-point numbers and raw bit representations use `haxe.io.FPHelper`:

```haxe
public function writeF64(value:Float):Void {
	final bits = haxe.io.FPHelper.doubleToI64(value);
	writeU32(bits.high);
	writeU32(bits.low);
}
```

In the Haxe typed AST, numeric primitives are represented by `haxe.macro.Type.TAbstract` referencing the core abstract types `Int` or `Float`. `haxe.Int64` is represented by `haxe.macro.Type.TAbstract` wrapping an underlying 64-bit composite structure.

## Current translations

### Haxe (`haxe/src/boring/BinaryWriter.hx`)

```haxe
public function writeU16(value:Int):Void {
	buffer.addByte((value >>> 8) & 0xFF);
	buffer.addByte(value & 0xFF);
}

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
```

### Rust (`rust/src/lib.rs`)

```rust
pub fn read_u32(&mut self) -> Result<u32, VectorError> {
    Ok(u32::from_be_bytes(self.take_n::<4>()?))
}

pub fn read_f64(&mut self) -> Result<f64, VectorError> {
    Ok(f64::from_bits(u64::from_be_bytes(self.take_n::<8>()?)))
}
```

### TypeScript (`ts/src/codec.ts`)

```ts
writeU16(value: number): void {
  this.ensure(2);
  this.buffer[this.length] = (value >>> 8) & 0xff;
  this.buffer[this.length + 1] = value & 0xff;
  this.length += 2;
}

writeU32(value: number): void {
  this.ensure(4);
  this.buffer[this.length] = (value >>> 24) & 0xff;
  this.buffer[this.length + 1] = (value >>> 16) & 0xff;
  this.buffer[this.length + 2] = (value >>> 8) & 0xff;
  this.buffer[this.length + 3] = value & 0xff;
  this.length += 4;
}

writeF64(value: number): void {
  this.scratch.setFloat64(0, value, false);
  this.ensure(SCRATCH_LENGTH);
  for (let i = 0; i < SCRATCH_LENGTH; i += 1) {
    this.buffer[this.length + i] = this.scratch.getUint8(i);
  }
  this.length += SCRATCH_LENGTH;
}
```

## Candidate translations

### Rust Candidate 1: Exact integer types (u32, f64) with checked conversions

```rust
pub fn encode_code_point(code_point: u32) -> [u8; 4] {
    code_point.to_be_bytes()
}

pub fn encode_coordinate(value: f64) -> [u8; 8] {
    value.to_bits().to_be_bytes()
}
```

### Rust Candidate 2: Unicode scalar char type for code points

```rust
pub fn encode_char(c: char) -> [u8; 4] {
    (c as u32).to_be_bytes()
}
```

### TypeScript Candidate 1: Number primitive with integer runtime guards

```ts
export function writeCodePoint(writer: BinaryWriter, codePoint: number): void {
  if (!Number.isInteger(codePoint) || codePoint < 0 || codePoint > 0x10ffff) {
    throw new Error(`invalid code point: ${codePoint}`);
  }
  writer.writeU32(codePoint);
}
```

### TypeScript Candidate 2: BigInt for all integer fields

```ts
export function writeCodePointBigInt(
  writer: BinaryWriter,
  codePoint: bigint,
): void {
  const num = Number(codePoint);
  writer.writeU32(num);
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Exact u32 and f64) | Primitive registers compile directly to native machine instructions. | Bit widths are specified explicitly by type names. | Zero custom conversion wrappers are required. | Exact numeric types communicate bit layout directly to Rust engineers. |
| Rust Candidate 2 (Rust char) | Char conversions require UTF-32 surrogate validation checks on every decode. | Char types reject surrogate code points that raw wire formats may transport. | Decoding requires conversion between u32 and char across boundaries. | Char types add unnecessary Unicode validation steps to raw binary codecs. |
| TS Candidate 1 (number with guards) | Standard number operations execute with optimized V8 Smi representations. | Type signatures say number while runtime guards enforce 32-bit integer ranges. | Guard helpers are written once in vector-json.ts and reused. | Standard number typing provides idiomatic TypeScript code. |
| TS Candidate 2 (BigInt) | BigInt values require heap allocation and cannot be mixed with standard numbers without explicit conversions. | Dual numeric types create friction when interacting with DataView APIs. | Callers must convert between number and BigInt across all API boundaries. | BigInt literals add visual clutter to integer metrics. |

## Ruling

Code points are represented as `Int` in Haxe, `u32` in Rust, and `number` in TypeScript. Coordinate metrics are represented as `Float` in Haxe, `f64` in Rust, and `number` in TypeScript. Implicit narrowing conversions and unchecked `as` casts are banned across all implementations. Test vectors must assign dyadic rational numbers to all floating-point fields to guarantee bit-identical encoding across platforms.

Unicode code points span the range `0x0000` to `0x10FFFF`, fitting within positive 32-bit signed integers and the 53-bit integer range of JavaScript numbers.

## Test hooks

Numeric encoding and precision are verified by:
- `tests/ts/codec.test.ts` (lines 13-34)
- `tests/haxe/Main.hx` (lines 89-96)
- `tests/rust/vector.rs` (lines 54-70)
