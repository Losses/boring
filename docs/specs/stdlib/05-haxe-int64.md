# Standard library spec 05: haxe.Int64

## Scope

This specification rules the representation and serialization of 64-bit integers (`haxe.Int64`) across Haxe, Rust, TypeScript, and Kotlin. In the current codebase, 64-bit integers do not appear as domain fields in glyph metrics records; `GlyphMetrics` uses 32-bit integers for `codePoint` and 64-bit floats for coordinates in `haxe/src/boring/GlyphMetrics.hx` (lines 12-16), `rust/src/lib.rs` (lines 17-22), and `ts/src/records.ts` (lines 14-18). 64-bit integer bit manipulation appears exclusively during floating-point conversion in `haxe/src/boring/BinaryWriter.hx` (lines 30-36) and `rust/src/lib.rs` (line 66). No Kotlin implementation exists yet; the Kotlin rulings bind generated code.

## Haxe construct

`haxe.Int64` is an abstract type providing signed 64-bit integer arithmetic. Its module surface includes:

- `Int64.make(high:Int32, low:Int32):Int64`: constructs a 64-bit integer from two 32-bit words.
- `Int64.ofInt(x:Int):Int64`: converts a 32-bit integer into an `Int64`.
- `Int64.toInt(x:Int64):Int`: truncates an `Int64` to a 32-bit integer.
- `Int64.getHigh(x:Int64):Int32`: extracts the high 32-bit word.
- `Int64.getLow(x:Int64):Int32`: extracts the low 32-bit word.
- `Int64.is(val:Dynamic):Bool`: tests if a dynamic value is an `Int64`.
- `Int64.compare(a:Int64, b:Int64):Int`: signed comparison returning -1, 0, or 1.
- `Int64.ucompare(a:Int64, b:Int64):Int`: unsigned comparison returning -1, 0, or 1.
- `Int64.toStr(x:Int64):String`: formats the 64-bit integer as a decimal string.
- Arithmetic operators (`+`, `-`, `*`, `/`, `%`) and bitwise operators (`&`, `|`, `^`, `<<`, `>>`, `>>>`).

Per-target differences: On JavaScript and 32-bit targets, `haxe.Int64` is emulated via a composite object containing `high:Int32` and `low:Int32` fields. On 64-bit C++, Java, and C# targets, `haxe.Int64` compiles to native 64-bit integer primitives (`int64_t`, `long`).

In the Haxe typed AST, `haxe.Int64` is represented by `haxe.macro.Type.TAbstract` referencing the `haxe.Int64` abstract definition.

## Current translations

### Haxe (`haxe/src/boring/BinaryWriter.hx`, `haxe/src/boring/BinaryReader.hx`)

Haxe uses `haxe.Int64` high and low 32-bit words during floating-point conversion:

```haxe
public function writeF64(value:Float):Void {
	final bits = haxe.io.FPHelper.doubleToI64(value);
	writeU32(bits.high);
	writeU32(bits.low);
}

public function readF64():Float {
	final high = readU32();
	final low = readU32();
	return haxe.io.FPHelper.i64ToDouble(low, high);
}
```

### Rust (`rust/src/lib.rs`)

Rust uses native `u64` bit conversions for floating-point decoding:

```rust
pub fn read_f64(&mut self) -> Result<f64, VectorError> {
    Ok(f64::from_bits(u64::from_be_bytes(self.take_n::<8>()?)))
}
```

### TypeScript (`ts/src/codec.ts`)

TypeScript uses `DataView` floating-point conversions without 64-bit integers:

```ts
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

### Rust Candidate 1: Native primitive types u64 and i64

```rust
pub fn write_u64(bytes: &mut Vec<u8>, value: u64) {
    bytes.extend_from_slice(&value.to_be_bytes());
}

pub fn read_u64(reader: &mut VectorReader<'_>) -> Result<u64, VectorError> {
    Ok(u64::from_be_bytes(reader.take_n::<8>()?))
}
```

### Rust Candidate 2: Custom two-word composite struct

```rust
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Int64Composite {
    pub high: u32,
    pub low: u32,
}
```

### TypeScript Candidate 1: BigInt primitive with DataView 64-bit accessors

```ts
export function writeU64(writer: BinaryWriter, value: bigint): void {
  const view = new DataView(new ArrayBuffer(8));
  view.setBigUint64(0, value, false);
  for (let i = 0; i < 8; i += 1) {
    writer.writeU8(view.getUint8(i));
  }
}
```

### TypeScript Candidate 2: JavaScript number primitive with 53-bit range check

```ts
export function writeU64Number(writer: BinaryWriter, value: number): void {
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`value out of safe 64-bit integer range: ${value}`);
  }
  const high = Math.floor(value / 0x100000000);
  const low = value >>> 0;
  writer.writeU32(high);
  writer.writeU32(low);
}
```

### Kotlin Candidate 1: Long primitives with manual byte assembly

```kotlin
fun readI64Be(bytes: ByteArray, offset: Int): Long {
    var value = 0L
    for (i in 0 until 8) {
        value = (value shl 8) or (bytes[offset + i].toLong() and 0xFF)
    }
    return value
}
```

### Kotlin Candidate 2: Two-word composite class

```kotlin
class Int64Parts(val high: Int, val low: Int)
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Native u64/i64) | Native 64-bit integers compile directly to 64-bit machine registers and arithmetic. | Type names specify exact bit widths and signedness. | Zero composite wrappers or conversion helpers are needed. | Standard Rust integer types communicate numeric bounds directly. |
| Rust Candidate 2 (Composite struct) | Multi-word structs prevent register-level arithmetic optimizations on 64-bit hardware. | Manual carry management across words introduces arithmetic edge cases. | Translators must write custom arithmetic and bitwise methods. | Composite types obscure standard numerical operations. |
| TS Candidate 1 (BigInt with DataView) | BigInt values allocate small heap objects when exceeding inline pointer representations. | BigInt represents full 64-bit precision without silent rounding or overflow truncation. | Built-in DataView methods handle 64-bit big-endian serialization directly. | BigInt type annotations state full 64-bit integer intent explicitly. |
| TS Candidate 2 (number with 53-bit check) | Standard number arithmetic runs directly in CPU floating-point units. | JavaScript number values lose precision silently for integers exceeding 2^53 - 1. | Runtime guard functions are required at every serialization boundary. | Number typing conceals 64-bit integer overflow limitations from callers. |
| Kotlin Candidate 1 (Long primitive) | `Long` is a native primitive on JVM and Android targets and runs in 64-bit registers. | `Long` states the exact 64-bit width in every signature. | No composite wrappers or conversion helpers are required. | Standard integer typing communicates the width directly. |
| Kotlin Candidate 2 (Two-word composite) | Composite classes allocate on the heap and prevent register-level arithmetic on every target. | Manual carry handling across two words introduces arithmetic edge cases. | Custom arithmetic and bitwise methods must be written by hand. | Composite types hide the standard numeric operations behind property access. |

## Ruling

This repository currently carries no 64-bit integer domain fields. Code points, record counts, and em coordinates fit within 32-bit integers and 64-bit floats. The governing rule is a use-case standard for wide integer representations: it states when each representation is required, when it is prohibited, and how values cross between representations. On the web target, `bigint` values allocate heap objects, leave V8 small integer optimizations, and require conversion at every `DataView` boundary, so the standard keeps `bigint` away from every value that `number` carries without loss.

TypeScript `bigint` use-case standard:

- Required: domain values outside the 53-bit safe integer range of `number`, which covers `i64` and `u64` wire fields and 64-bit bit manipulation.
- Prohibited: fields of 32 bits or narrower, loop counters, indexes, lengths, and every value whose range fits `number`.
- Every `bigint` to `number` crossing passes through a named conversion function at a wire or API boundary. Mixing `bigint` and `number` operands in one expression is banned.

Fields bounded by 2^53 use `number` with `Number.isSafeInteger` guards.

Kotlin applies the same standard through `Long`. On JVM and Android targets, `Long` is a native 64-bit primitive that runs in registers. On Kotlin/JS, `Long` is an emulated class whose values box, so the `bigint` standard above governs `Long` on that target. `Long` appears for genuine 64-bit domain values only; `Int` and `Double` carry every narrower field on every Kotlin target.

`haxe.Int64` follows the matching rule on the Haxe side: it appears as the return type of `haxe.io.FPHelper.doubleToI64`, where `bits.high` and `bits.low` are written as `Int` words, and in the same 64-bit domain cases the TypeScript and Kotlin standards permit. Arithmetic, comparison, storage, and API exposure of `Int64` values outside these paths is banned.

A format that declares a `WireI64Be` or `WireU64Be` field is a format revision: the entry enters `docs/specs/binary/02-binary-meta-abstraction.md` only after the `bigint` cost on the web target and the `Long` boxing cost on Kotlin/JS are measured and accepted in writing. Until such a revision exists, translators reject 64-bit integer domain fields as unsupported.

For bit-level floating-point serialization where integer semantics are unused, Haxe translates `haxe.io.FPHelper` conversions to `f64::from_bits`/`to_bits` in Rust, `DataView.getFloat64`/`setFloat64` in TypeScript, and `Double.toBits()`/`Double.fromBits(...)` in Kotlin.

## Test hooks

64-bit floating-point bit preservation is verified in:
- `tests/rust/vector.rs` (lines 54-70)
- `tests/haxe/Main.hx` (lines 79-88)
- `tests/ts/codec.test.ts` (lines 26-34)

Unit tests for 64-bit domain integer fields are none yet.
