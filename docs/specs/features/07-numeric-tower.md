# Feature spec 07: Numeric tower

## Scope

This specification rules numeric type representations, bit widths, endian serialization, floating-point precision, and conversion restrictions across Haxe, Rust, TypeScript, and Kotlin. In the current codebase, numeric operations appear in Haxe in `samples/boring/BinaryWriter.hx` and `samples/boring/BinaryReader.hx`, in Rust in `reference/rust/src/lib.rs`, and in TypeScript in `reference/ts/src/codec.ts` and `reference/ts/src/records.ts`. In Kotlin, numeric reads and writes appear in `reference/kotlin/src/boring/BinaryReader.kt` and `reference/kotlin/src/boring/BinaryWriter.kt`.

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

### Haxe (`samples/boring/BinaryWriter.hx`)

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

### Rust (`reference/rust/src/lib.rs`)

```rust
pub fn read_u32(&mut self) -> Result<u32, VectorError> {
    Ok(u32::from_be_bytes(self.take_n::<4>()?))
}

pub fn read_f64(&mut self) -> Result<f64, VectorError> {
    Ok(f64::from_bits(u64::from_be_bytes(self.take_n::<8>()?)))
}
```

### TypeScript (`reference/ts/src/codec.ts`)

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

### Kotlin Candidate 1: Int and Double with named range guards

```kotlin
fun writeCodePoint(writer: BinaryWriter, codePoint: Int): Unit {
  if (codePoint < 0 || codePoint > 0x10FFFF) {
    throw IllegalArgumentException("invalid code point: $codePoint")
  }
  writer.writeU32(codePoint)
}
```

### Kotlin Candidate 2: Long for every integer field

```kotlin
fun writeCodePointLong(writer: BinaryWriter, codePoint: Long): Unit {
  writer.writeU32(codePoint.toInt())
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (Exact u32 and f64) | Primitive registers compile directly to native machine instructions. | Bit widths are specified explicitly by type names. | Zero custom conversion wrappers are required. | Exact numeric types communicate bit layout directly to Rust engineers. |
| Rust Candidate 2 (Rust char) | Char conversions require UTF-32 surrogate validation checks on every decode. | Char types reject surrogate code points that raw wire formats may transport. | Decoding requires conversion between u32 and char across boundaries. | Char types add unnecessary Unicode validation steps to raw binary codecs. |
| TS Candidate 1 (number with guards) | Standard number operations execute with optimized V8 Smi representations. | Type signatures say number while runtime guards enforce 32-bit integer ranges. | Guard helpers are written once in vector-json.ts and reused. | Standard number typing provides idiomatic TypeScript code. |
| TS Candidate 2 (BigInt) | BigInt values require heap allocation and cannot be mixed with standard numbers without explicit conversions. | Dual numeric types create friction when interacting with DataView APIs. | Callers must convert between number and BigInt across all API boundaries. | BigInt literals add visual clutter to integer metrics. |
| Kotlin Candidate 1 (Int and Double with guards) | `Int` and `Double` are primitives on JVM and Android and unboxed locals on Kotlin/JS. | `Int` states the 32-bit width, and the named guard states the domain range. | Guard helpers are written once and reused at ingestion boundaries. | Standard integer typing communicates the width directly. |
| Kotlin Candidate 2 (Long everywhere) | `Long` boxes on the Kotlin/JS target for every value it carries. | Signatures state 64-bit width for fields the wire fixes at 32 bits. | Every write narrows through `toInt()` at the codec boundary. | Width mismatch between signature and wire conceals the actual field width. |

## Ruling

Code points are represented as `Int` in Haxe, `u32` in Rust, `number` in TypeScript, and `Int` in Kotlin. Coordinate metrics are represented as `Float` in Haxe, `f64` in Rust, `number` in TypeScript, and `Double` in Kotlin. Implicit narrowing conversions and unchecked `as` casts are banned across all implementations. Test vectors must assign dyadic rational numbers to all floating-point fields to guarantee bit-identical encoding across platforms.

Unicode code points span the range `0x0000` to `0x10FFFF`, fitting within positive 32-bit signed integers and the 53-bit integer range of JavaScript numbers.

Standard integer alignment is fixed by the wire type: `WireU8` maps to `Int`, `u8`, `number`, and `Int`; `WireU16Be` maps to `Int`, `u16`, `number`, and `Int`; `WireU32Be` maps to `Int`, `u32`, `number`, and `Int`; `WireF64Be` maps to `Float`, `f64`, `number`, and `Double`; `WireF32Be` and `WireF16Be` (binary spec 05) keep the same language mapping as `WireF64Be` and differ only in the byte width and the rounding at the block edge, listing Haxe, Rust, TypeScript, and Kotlin in order. Haxe `Int` is 32-bit signed on every supported target, and every `u32` wire value fits within the 53-bit integer range of JavaScript `number`, so no platform silently narrows or widens a value. Kotlin `Int` is 32-bit signed on every target. A `u32` field whose declared range exceeds `0x7FFFFFFF` exceeds the Kotlin `Int` range; the record format declaration records that range, and the Kotlin translation carries the field as `Long` with the range stated in the field name or the guard. Kotlin unsigned types (`UInt`, `ULong`) are value classes that box in nullable and generic positions, so wire representations use `Int` and `Long` instead. TypeScript validates `Number.isInteger` at the API boundary before encoding (`reference/ts/src/vector-json.ts`, lines 43-45); a full `0x0000` to `0x10FFFF` range check at that boundary is required by this specification and does not exist yet.

Float precision alignment requires bit-exact paths on every target: `haxe.io.FPHelper` conversions in Haxe, `to_bits` and `from_bits` in Rust (`reference/rust/src/lib.rs`, line 66), `DataView` reads and writes with the littleEndian argument set to `false` in TypeScript (`reference/ts/src/codec.ts`, lines 37-44 and 95-99), and `Double.toBits()` and `Double.fromBits(...)` in Kotlin. Tests compare decoded floats directly and never perform arithmetic on them before comparison; test vectors assign dyadic rationals so every target produces identical bit patterns.

The following type choices are banned because they degrade hot path performance or hide bit widths: `bigint` for fields of 32 bits or fewer, Rust `char` for code points, single-precision float paths for `WireF64Be`, boxed `Number` objects, numbers stored in strings, `Long` for Kotlin/JS fields of 32 bits or fewer, and `UInt` or `ULong` in nullable or generic positions. Single-precision storage travels through `WireF32Be` and `WireF16Be`, the dedicated field types of binary spec 05; a narrow value never rides `WireF64Be`. A translator or generator that meets a numeric type outside the fixed wire type table fails the build; it never selects a near match. The full `Long` and `bigint` use-case standard is ruled in `docs/specs/stdlib/05-haxe-int64.md`. The `float-precision` define of feature spec 23 does not touch this table: it selects a binary32 module real for the `Float` type of the language, while `WireF64Be` stays f64 on the wire and the f32 configuration rounds the decoded value to the module real at the decode point, so the define brings no single-precision wire path into existence.

## Test hooks

Numeric encoding and precision are verified by:
- `tests/ts/codec.test.ts` (lines 13-34)
- `tests/haxe/Main.hx` (lines 89-96)
- `tests/rust/vector.rs` (lines 54-70)

### Swift target rulings

#### Numbers (`features/07`, `features/14`)

Haxe `Int` maps to `Int32`; Haxe `Float` maps to `Double`.

#### Candidates

1. `Int32` and `Double` for the two Haxe types.
2. `Int` (the word-sized signed integer) and `Double`.
3. `Int32` with wrapping operators everywhere arithmetic occurs.

#### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| 1 (`Int32`/`Double`) | Register-width on every ABI Apple and Linux expose for `Int32`; no conversion at codec boundaries that already carry 32-bit fields. | The 32-bit domain of `features/14` is visible in the type; widening or narrowing is explicit. | One mapping, no call-site conversions. | Readers see the wire width in the type name. |
| 2 (`Int`) | Word arithmetic avoids sign-extension on array indexing. | The 64-bit range silently admits out-of-domain values; overflow traps differ from every other target. | Boundary code must mask to keep the domain, duplicating the check per site. | The wire width disappears from the type. |
| 3 (wrapping operators) | Same as 1. | Conforming source never leaves the i32 domain, so the wrapping behavior is dead code that contradicts `features/14`. | Every arithmetic site carries a marker no target needs. | `&+` reads as a deliberate wrap, which the samples never perform. |

#### Ruling

Candidate 1. `Int32`/`Double`, trapping operators. The domain rulings of
`features/07` and `features/14` keep every value inside i32, so traps are
unreachable on conforming source and cost nothing. The `float-precision`
define of `features/23` switches this target through a define-gated type
table, the same shape as the Kotlin ruling: `Float` maps to `Double` on
the default configuration and to `Float` under `f32`, in the type table and the
test assertion tags together. Swift float literals carry no suffix; they
are type-directed, so the f32 configuration names the type on every declaration
whose initializer would otherwise infer the default `Double` width
(`var x = 0.0` becomes `var x: Float = 0.0`). `Math` constants read from
the `Float` family (`Float.nan`, `Float.infinity`,
`-Float.infinity`); the arithmetic and rounding members (`+`,
`.rounded(.down)`, `.squareRoot()`, `.isNaN`) come from the
`FloatingPoint` protocol both types implement, so they follow the type
table with no separate dispatch. The `FPHelper` value-edge calls dispatch
to the runtime wrappers `i64ToF32` and `f32ToI64` (feature spec 23,
ruling 7). `examples/swift-f32.hxml` generates the f32 tree; the verify
steps are `gen:swift-f32` and `test:swift-f32`.

### Dart target rulings

#### Numbers (`features/07`, `features/14`)

Haxe `Int` maps to `int`; Haxe `Float` maps to `double`.

#### Candidates

1. `int` and `double` as the two Haxe types.
2. `int` with 32-bit masking at every arithmetic site.

#### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| 1 (`int`) | VM integers are unboxed machine words in locals and fields; no masking arithmetic runs. | `int` is 64-bit, wider than the i32 domain, exactly as `number` is wider on the TypeScript target; the `features/14` rulings enforce the domain and the type adds none. | One mapping with no call-site conversions. | Readers see the language's own integer. |
| 2 (masked) | Every arithmetic site executes an extra `& 0xFFFFFFFF`. | Same width question, now hidden behind masks. | The mask repeats across every expression. | Masked arithmetic reads as a wrapping semantics the samples never use. |

#### Ruling

Candidate 1. The TypeScript target already carries a wider-than-i32
integer and relies on the domain rulings to keep values in range; Dart
matches that precedent. Wrapping that `features/14` never permits is
absent on both targets for the same reason. Two operators are the
structural exception: `<<` and `>>>` produce results outside i32 on a
64-bit word even from in-range operands, so each lowers with the domain
restore attached (`(... << n).toSigned(32)` and
`(... .toUnsigned(32) >> n).toSigned(32)`), the wrap targets with a
native 32-bit integer perform in hardware. The `float-precision` define
of `features/23` is rejected at plugin registration on this target: Dart
has one storage width for reals (`double`), so an f32 variant cannot
change result bits. A compile with `-D float-precision=f32` fails with
`float-precision=f32 is not available on the Dart target: double is the
one real storage width; compile without the define for f64 semantics`
before any type rendering; `tests/dart/precision-switch.test.ts` pins
the rejection.
