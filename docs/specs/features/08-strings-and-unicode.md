# Feature spec 08: Strings and Unicode

## Scope

This specification rules the representation of strings, character encodings, Unicode code points, and string conversions across Haxe, Rust, and TypeScript. In the current codebase, ASCII magic strings appear in `haxe/src/boring/VectorCodec.hx` (lines 11, 30) and `ts/src/vector-format.ts` (line 10), ASCII byte serialization appears in `haxe/src/boring/BinaryReader.hx` (lines 41-48), `haxe/src/boring/BinaryWriter.hx` (lines 38-42), and `ts/src/codec.ts` (lines 46-52, 101-108), raw magic byte arrays appear in `rust/src/lib.rs` (line 24), and Unicode scalar values appear as integer code points in `haxe/src/boring/GlyphMetrics.hx` (line 13), `rust/src/lib.rs` (line 19), and `ts/src/records.ts` (line 15).

## Haxe construct

Haxe defines `String` as an immutable sequence of characters. On the JavaScript target, `String` operates as UTF-16 code units, where surrogate pairs require two indices. On C++ and Neko targets, `String` exposes byte-oriented storage. Haxe provides `StringTools` for Unicode handling, including `StringTools.fastCodeAt` and `StringTools.fromCharCode`.

```haxe
final magic:String = "BRG1";
final firstCodeUnit:Int = magic.charCodeAt(0);
final charStr:String = String.fromCharCode(65);
```

In the Haxe typed AST, string literals are represented by `haxe.macro.TypedExprDef.TConst(TString(s:String))` and macro AST nodes `haxe.macro.Expr.Constant.CString(s:String)`. The core type is `haxe.macro.Type.TAbstract` referencing the core `String` class.

## Current translations

### Haxe (`haxe/src/boring/BinaryReader.hx`, `haxe/src/boring/BinaryWriter.hx`, `haxe/src/boring/VectorCodec.hx`)

```haxe
public static inline var MAGIC:String = "BRG1";

public function readAscii(length:Int):String {
	final parts = new Array<String>();
	for (index in 0...length) {
		parts.push(String.fromCharCode(bytes.get(offset + index)));
	}
	offset += length;
	return parts.join("");
}

public function writeAscii(value:String):Void {
	for (index in 0...value.length) {
		buffer.addByte(value.charCodeAt(index) & 0xFF);
	}
}
```

### Rust (`rust/src/lib.rs`)

```rust
pub const VECTOR_MAGIC: &[u8; 4] = b"BRG1";

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### TypeScript (`ts/src/codec.ts`, `ts/src/records.ts`, `ts/src/vector-format.ts`)

```ts
export const VECTOR_MAGIC = "BRG1";

export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}

writeAscii(value: string): void {
  this.ensure(value.length);
  for (let i = 0; i < value.length; i += 1) {
    this.buffer[this.length + i] = value.charCodeAt(i) & 0xff;
  }
  this.length += value.length;
}

readAscii(length: number): string {
  let value = "";
  for (let i = 0; i < length; i += 1) {
    value += String.fromCharCode(this.view.getUint8(this.offset + i));
  }
  this.offset += length;
  return value;
}
```

## Candidate translations

### Rust Candidate 1: Integer u32 for code points and byte slices for ASCII markers

```rust
pub const VECTOR_MAGIC: &[u8; 4] = b"BRG1";

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### Rust Candidate 2: Rust char type for code points and &str for markers

```rust
pub const VECTOR_MAGIC: &str = "BRG1";

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: char,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### TypeScript Candidate 1: Number integer for code points and string for ASCII markers

```ts
export const VECTOR_MAGIC = "BRG1";

export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

### TypeScript Candidate 2: Single-character string for code points

```ts
export interface GlyphMetricsRecord {
  readonly char: string;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (u32 code point and byte slice) | Primitive u32 values and byte slices copy directly without allocations or validation passes. | Explicit u32 types define exact 32-bit wire width across all platforms. | No conversion routines exist between wire decoders and record structures. | Direct numerical representation matches the binary format definition. |
| Rust Candidate 2 (char code point and &str) | Converting wire u32 values to char requires runtime Unicode scalar validation on every record. | Char types reject surrogate code units that binary font tables can transport. | Decoders and encoders require intermediate conversion functions between u32 and char. | Char types express Unicode intent while adding conversion boilerplate. |
| TS Candidate 1 (number code point and string) | Number primitives fit in V8 small integer representations with zero object allocations. | Integer bounds are validated at format boundaries before record creation. | Interface definitions share numerical typing across all modules. | Number properties state numerical code point values directly. |
| TS Candidate 2 (Single-character string) | String instances require heap allocations and surrogate pair encoding for supplementary code points. | Multi-byte characters produce two UTF-16 code units that complicate length checks. | Translators must invoke code point conversion functions across every record boundary. | String fields conceal the underlying integer code point value. |

## Ruling

Unicode code points are represented as 32-bit unsigned integers (`Int` in Haxe, `u32` in Rust, `number` in TypeScript), and fixed ASCII wire tags are represented as byte arrays in Rust and ASCII strings in Haxe and TypeScript.

The codec operates on glyph indices and Unicode scalar values where integer representation avoids encoding overhead and surrogate pair handling. Binary wire serialization treats code points as big-endian 32-bit integers without UTF-8 or UTF-16 transcoding.

## Test hooks

Code point values and ASCII magic headers are asserted in:
- `tests/rust/vector.rs` (lines 12, 22, 32, 42, 75)
- `tests/haxe/Main.hx` (lines 24, 29, 34, 39, 45, 99)
- `tests/ts/codec.test.ts` (lines 36-40, 68)
- `tests/ts/vector.test.ts` (lines 14, 18, 22)
