# Binary spec 02: Binary record input and output

## Scope

This specification rules the declaration of a binary record format in Haxe source and the code the compiler derives from that declaration: per-field byte offsets, the record buffer kind, the record position type, the per-field read functions, and the encode, decode, and record copy functions. The byte mechanics the derived code follows are ruled in `01-binary-record-layout.md`; the reading model the derived functions serve is ruled in `06-binary-record-views.md`; the call threading and the consumer boundary are ruled in `07-binary-record-optimization.md` and `08-binary-record-boundary.md`.

This document rules the requirement and the derived shapes. The generator described here does not exist in the repository yet; today the four implementations listed in binary spec 01 synchronize the layout by hand.

## Requirement

A change to the glyph metrics format today, in field width, field order, or field type, requires one manual edit in each of the four implementations of binary spec 01 plus the vector descriptions, and the committed vectors verify the agreement after the fact. This specification removes the manual synchronization for every format declared with the annotation: one declaration in Haxe source, and the compiler derives the byte-handling code for every target through the normal Reflaxe pipeline.

## Declaration route

### Candidate 1: Annotation on the record typedef (selected)

`@:binaryRecord` on a top-level typedef declares the format. The compiler reads the typedef's typed AST and derives every artifact of this specification from it.

- performance: the derived code is the code the hand-written trees run; read functions are static inline and fold to single buffer reads (`features/11-inline-and-macros.md`).
- ambiguity: the format is declared on the types it governs; one declaration names one format.
- redundancy: one declaration serves every target; no per-target restatement of the layout.
- readability: the typedef reads as the record it already is; the annotation adds the binary meaning.

### Candidate 2: Typed schema value

A class holds a schema instance that lists field names and field types as data values; the generator reads the instance.

- performance: as Candidate 1.
- ambiguity: the schema describes the types in a second structure beside them; the reader compares two declarations to know one format.
- redundancy: every field name and field type appears twice, once in the typedef and once in the instance.
- readability: field descriptors stand between the reader and the record.

### Candidate 3: Status quo

Four hand-written implementations verified by committed vectors.

- performance: as Candidate 1.
- ambiguity: agreement lives in test comparison, with no single declaration to read.
- redundancy: four implementations of one layout.
- readability: each tree reads alone.

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 annotation on the typedef | derived code equals hand-written code | one declaration per format, on the governed types | one declaration serves every target | typedef plus one annotation |
| C2 typed schema value | as C1 | schema beside the types it describes | fields stated twice | descriptor vocabulary in between |
| C3 status quo | as C1 | agreement only in tests | four implementations | no single declaration |

Principle application: the ruling places the declaration on the governed types, and the author states the format once for every target (P4). Candidate 3 carries the restriction this specification removes, four manual synchronizations per format change, with the committed vectors as the only guard. The field-domain rejections below each name a sanctioned path (P2): booleans encode as `Int` 0 and 1, and variable-length data lives outside the block.

## Haxe construct

```haxe
package boring;

@:binaryRecord
typedef GlyphMetrics = {
	final codePoint:Int;
	final advanceEm:Float;
	final bounds:BoundsEm;
}

typedef BoundsEm = {
	final xMin:Float;
	final yMin:Float;
	final xMax:Float;
	final yMax:Float;
}
```

The two typedefs are the declarations of `samples/boring/GlyphMetrics.hx`; the annotation is the form this specification rules, and the sample gains it when the generator exists.

`@:binaryRecord` is plain custom metadata on a top-level typedef. On any other declaration or on a class member it stops the compilation with `binaryRecord is a typedef marker: place it on the declaration itself`. The annotation marks the format root; nested typedefs carry no annotation of their own.

## Field domain

| Field type | Encoded as | Byte width |
| --- | --- | --- |
| `Int` | `u32` BE | 4 |
| `Float` | `f64`, `f32`, or `f16` BE per width family (`05-block-float-widths.md`) | 8, 4, or 2 |
| nested typedef whose every field is in the domain | its flattened fields (`01-binary-record-layout.md`) | the flattened sum |

Every field type outside the domain stops the compilation before any derivation, with a named error naming the field path: `unsupported record field bounds.note: String. Fixed-width Int and Float fields and nested record typedefs are in the domain; store variable-length data outside the block and booleans as Int 0 and 1.`

Two structural rejections complete the domain:

- A typedef that references itself, directly or through another record typedef, stops the compilation with `recursive record type GlyphMetrics: record typedefs form a finite tree`. This is the finiteness rule of `04-key-index-retrieval.md` restated for the declaration route.
- A field naming another annotated root stops the compilation with `nested record root Bounds: annotated roots are separate formats; remove the annotation from the nested typedef or keep the field a plain nested typedef`.

## Magic derivation and validation

The magic is four ASCII bytes: a three-letter stem that identifies the format, followed by the width-family digit that declares the float width (`01-binary-record-layout.md`, `05-block-float-widths.md`).

1. The stem is exactly three ASCII uppercase letters. A stem that fails the shape stops the compilation with `record format stem must be three ASCII uppercase letters: got "Br1"`.
2. With no argument, the stem derives from the typedef name: the first three letters, uppercased (`GlyphMetrics` gives `GLY`).
3. With an argument, `@:binaryRecord("BRG")` supplies the stem.
4. Two annotated formats in one compilation with one stem stop the compilation with `duplicate record format stem BRG: GlyphMetrics and RasterBox`, naming both declarations.
5. The glyph metrics sample declares `@:binaryRecord("BRG")`, so the magics stay `BRG1`, `BRG2`, `BRG3` and the committed vectors `roundtrip.bin`, `roundtrip-f32.bin`, and `roundtrip-f16.bin` stay valid unchanged.

## Derived artifacts

For an annotated typedef `Name`, the compiler derives the following at compile time from the typed AST, through the macro architecture of `features/11-inline-and-macros.md`: a native Haxe macro builds the declarations, and the Reflaxe targets translate them. No code generator outside the pipeline participates (`features/20-compile-time-data-tables.md` states the same architecture for data tables).

1. **Field offsets.** Per `01-binary-record-layout.md`: declaration order, depth-first flattening, zero padding. For `GlyphMetrics` at the binary64 family:

| Field | Offset in record (bytes) | Width (bytes) |
| --- | --- | --- |
| `codePoint` | 0 | 4 |
| `advanceEm` | 4 | 8 |
| `bounds.xMin` | 12 | 8 |
| `bounds.yMin` | 20 | 8 |
| `bounds.xMax` | 28 | 8 |
| `bounds.yMax` | 36 | 8 |

The record width is 44 bytes; record `i` begins at byte 8 + 44 x i; the total block length is 8 + 44 x N.

2. **Record buffer kind.** `abstract GlyphMetricsBuffer(RecordBuffer)`. `RecordBuffer` is one runtime class of boring's runtime package (`stdlib/06-std-modules.md`): it holds one `haxe.io.Bytes` and offers the positional reads `readU8`, `readU16`, `readU32`, `readF32`, `readF64`, `readF16`, each taking a byte position, in the byte order binary spec 01 fixes. One class serves every format; the kinds are nominal over it and erase at runtime (`features/02-abstract-types.md`). The kind is the unit the threading rewrite of binary spec 07 keys on. The kind carries an implicit cast from `RecordBuffer` (`features/02-abstract-types.md`), so a value held as `RecordBuffer` binds to the needed kind where a read requires it; the binding stops of binary spec 07 rely on this cast.

3. **Record position type.** `abstract GlyphMetricsPos(Int)`: the byte offset of one record's first byte in the block. `positionOf(buffer, index)` returns 8 + index x recordWidth after the index validation of `04-key-index-retrieval.md`; `next(pos)` returns pos + recordWidth; `recordCount(buffer)` returns the header count. Positions 0 to 7 hold the header, so the value 0 names no record (binary spec 06).

4. **Read functions.** One static inline extension function per scalar field, on the position type (`features/10-static-extension.md`, `features/11-inline-and-macros.md`):

```haxe
class GlyphMetricsFields {
	public static inline function codePoint(pos:GlyphMetricsPos):Int {
		return buffer.readU32(pos);
	}

	public static inline function advanceEm(pos:GlyphMetricsPos):Float {
		return buffer.readF64((pos : Int) + 4);
	}

	public static inline function boundsXMin(pos:GlyphMetricsPos):Float {
		return buffer.readF64((pos : Int) + 12);
	}
}
```

The body reads through the implicit `buffer` binding that binary spec 07 threads. Inlined, one call is one buffer read at a constant offset, and the offset arithmetic folds at compile time. A nested field reads at the position plus the nested base offset, which is a constant (12 for `bounds`).

5. **Encode.** `encode(records, width)` writes the header, the magic of the encoded family plus the record count, and then every record's flattened fields in the canonical order of binary spec 01, through `BinaryWriter` (`stdlib/02-haxe-io-buffers-and-inputs.md`). A count at or above 2^31 stops with `CountOverflow` before any byte is written.

6. **Decode.** `decode(bytes):GlyphMetricsBuffer` validates the magic (`BadMagic`), the count domain (`CountOverflow`), and the total length (`TrailingBytes`), and returns the buffer together with the family it read. Decode reads the family from the magic, so one reader decodes every family the runtime implements (binary spec 05); the compiled family selects what encode writes.

7. **Record copy.** `toRecord(pos):GlyphMetrics` copies one record into a plain value, field by field, deep over nested typedefs. It is the sanctioned path when a plain value is required, and the boundary of binary spec 08 inserts the same conversion at returns.

## Test hooks

Required once the generator exists; none exist yet:

- Round trip: generated encode and decode pass the committed vectors of binary specs 01 and 05 on every lane, byte-identically.
- Field agreement: for every field, record index, and width family, the generated read function returns the value a full decode returns at the same index, the hook binary spec 04 states for accessors.
- Rejections: each named error of the field domain, the magic derivation, and the marker position stops a compilation that triggers it.
- Decode identities: crafted inputs with an unknown magic, a count at or above 0x80000000, and trailing bytes produce `BadMagic`, `CountOverflow`, and `TrailingBytes`.
