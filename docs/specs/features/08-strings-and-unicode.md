# Feature spec 08: Strings and Unicode

## Scope

This specification rules the representation of strings, character encodings, Unicode code points, and string conversions across Haxe, Rust, TypeScript, and Kotlin. In the current codebase, ASCII magic strings appear in `samples/boring/VectorCodec.hx` (lines 11, 30) and `reference/ts/src/vector-format.ts` (line 10), ASCII byte serialization appears in `samples/boring/BinaryReader.hx` (lines 41-48), `samples/boring/BinaryWriter.hx` (lines 38-42), and `reference/ts/src/codec.ts` (lines 46-52, 101-108), raw magic byte arrays appear in `reference/rust/src/lib.rs` (line 24), and Unicode scalar values appear as integer code points in `samples/boring/GlyphMetrics.hx` (line 13), `reference/rust/src/lib.rs` (line 19), and `reference/ts/src/records.ts` (line 15). In Kotlin, the ASCII magic appears in `reference/kotlin/src/boring/VectorCodec.kt`, byte serialization in `reference/kotlin/src/boring/BinaryReader.kt` and `reference/kotlin/src/boring/BinaryWriter.kt`, and code points as `Int` fields in `reference/kotlin/src/boring/GlyphMetrics.kt`.

## Haxe construct

Haxe defines `String` as an immutable sequence of characters. On the JavaScript target, `String` operates as UTF-16 code units, where surrogate pairs require two indices. On C++ and Neko targets, `String` exposes byte-oriented storage. Haxe provides `StringTools` for Unicode handling, including `StringTools.fastCodeAt` and `StringTools.fromCharCode`.

```haxe
final magic:String = "BRG1";
final firstCodeUnit:Int = magic.charCodeAt(0);
final charStr:String = String.fromCharCode(65);
```

In the Haxe typed AST, string literals are represented by `haxe.macro.TypedExprDef.TConst(TString(s:String))` and macro AST nodes `haxe.macro.Expr.Constant.CString(s:String)`. The core `String` type is an extern class, represented by `haxe.macro.Type.TInst` referencing it.

## Current translations

### Haxe (`samples/boring/BinaryReader.hx`, `samples/boring/BinaryWriter.hx`, `samples/boring/VectorCodec.hx`)

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

### Rust (`reference/rust/src/lib.rs`)

```rust
pub const VECTOR_MAGIC: &[u8; 4] = b"BRG1";

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlyphMetrics {
    pub code_point: u32,
    pub advance_em: f64,
    pub bounds: BoundsEm,
}
```

### TypeScript (`reference/ts/src/codec.ts`, `reference/ts/src/records.ts`, `reference/ts/src/vector-format.ts`)

```ts
export const VECTOR_MAGIC = "BRG1";

export interface GlyphMetricsRecord {
  readonly codePoint: number;
  readonly advanceEm: number;
  readonly bounds: BoundsEmRecord;
}

writeAscii(value: string): void {
  const count = value.length;
  this.ensure(count);
  for (let i = 0; i < count; i += 1) {
    this.buffer[this.length + i] = value.charCodeAt(i) & 0xff;
  }
  this.length += count;
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

### Kotlin Candidate 1: Int for code points and String for ASCII markers

```kotlin
const val VECTOR_MAGIC = "BRG1"

data class GlyphMetrics(
    val codePoint: Int,
    val advanceEm: Double,
    val bounds: BoundsEm,
)
```

### Kotlin Candidate 2: Char for code points

```kotlin
data class GlyphMetrics(
    val char: Char,
    val advanceEm: Double,
    val bounds: BoundsEm,
)
```

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust Candidate 1 (u32 code point and byte slice) | Primitive u32 values and byte slices copy directly without allocations or validation passes. | Explicit u32 types define exact 32-bit wire width across all platforms. | No conversion routines exist between wire decoders and record structures. | Direct numerical representation matches the binary format definition. |
| Rust Candidate 2 (char code point and &str) | Converting wire u32 values to char requires runtime Unicode scalar validation on every record. | Char types reject surrogate code units that binary font tables can transport. | Decoders and encoders require intermediate conversion functions between u32 and char. | Char types express Unicode intent while adding conversion boilerplate. |
| TS Candidate 1 (number code point and string) | Number primitives fit in V8 small integer representations with zero object allocations. | Integer bounds are validated at format boundaries before record creation. | Interface definitions share numerical typing across all modules. | Number properties state numerical code point values directly. |
| TS Candidate 2 (Single-character string) | String instances require heap allocations and surrogate pair encoding for supplementary code points. | Multi-byte characters produce two UTF-16 code units that complicate length checks. | Translators must invoke code point conversion functions across every record boundary. | String fields conceal the underlying integer code point value. |
| Kotlin Candidate 1 (Int and String) | `Int` is a primitive on every Kotlin target, and string constants fold into the constant pool. | `Int` states the 32-bit wire width, and the marker reads as the ASCII text it is. | No conversion between record fields and wire values is required. | Number properties state numerical code point values directly. |
| Kotlin Candidate 2 (Char fields) | Kotlin `Char` holds one UTF-16 code unit, so supplementary code points do not fit at all. | Two `Char` values are required for code points above `0xFFFF`, splitting one logical value across fields. | Every boundary converts between `Char` pairs and the wire integer. | Char fields state text intent while the wire carries an integer. |

## Ruling

Unicode code points are represented as 32-bit unsigned integers (`Int` in Haxe, `u32` in Rust, `number` in TypeScript, `Int` in Kotlin), and fixed ASCII wire tags are represented as byte arrays in Rust, ASCII strings in Haxe and TypeScript, and `String` constants in Kotlin. Kotlin `Char` is a 16-bit UTF-16 code unit and never carries a code point field.

The codec operates on glyph indices and Unicode scalar values where integer representation avoids encoding overhead and surrogate pair handling. Binary wire serialization treats code points as big-endian 32-bit integers without UTF-8 or UTF-16 transcoding.

## String index access ruling

Added 2026-08-28. The three runtimes expose two index spaces on `String`: the
TypeScript, Kotlin, and stage-one JavaScript runtimes address UTF-16 code
units, and the Rust runtime addresses UTF-8 bytes (`String::len`,
`as_bytes()[index]`). The two spaces and the values they return coincide for
code points U+0000..U+007F and diverge everywhere else. `String.length`,
`String.charCodeAt`, and every operation that takes or returns a string index
(`charAt`, `codePointAt`, `substring`, `substr`, `indexOf`, `lastIndexOf`)
carry an ASCII-bounded contract.

Source obligation: a string that may hold content above U+007F must not be
indexed. Such strings are consumed as whole strings or as code-point integers
under the existing code-point ruling. `String.fromCharCode` constructs from
wire bytes; its sanctioned domain is 0..255, the range the Rust lowering
`char::from(u8)` accepts.

Enforcement: style rule `V18 NonAsciiStringIndex` reports at Haxe compile
time, split across the two interception passes. The call forms are checked
in the untyped pass, because the typer expands the inline std String methods
before the typed pass runs (`charCodeAt` becomes an `HxOverrides.cca` call
on the JavaScript std); that check fires on a literal subject and on a local
whose final declaration initializes it from a non-ASCII literal. The
`length` read and the call forms that survive typing are checked in the
typed pass, where the subject may also be a field initialized from a string
literal; a field that receives an assignment anywhere leaves the checked
set. `String.fromCharCode` reports when an integer literal argument falls
outside 0..255. Subjects holding runtime data stay outside the checker; the
four-side consistency harness reports exercised divergence between the
UTF-16 and byte index spaces.

## Test hooks

Code point values and ASCII magic headers are asserted in:
- `tests/rust/vector.rs` (lines 12, 22, 32, 42, 75)
- `tests/haxe/Main.hx` (lines 24, 29, 34, 39, 45, 99)
- `tests/ts/codec.test.ts` (lines 36-40, 68)
- `tests/ts/vector.test.ts` (lines 14, 18, 22)
