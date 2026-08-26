# Binary spec 04: Key-index retrieval

## Scope

This specification rules the generation of per-key retrieval methods from the format definition. For every field key of a fixed-stride format, each target language receives one accessor method that reads the field value directly at a build-time computed byte offset, without materializing intermediate records and without scanning prior records. The ruled target languages are Haxe, Rust, TypeScript, and Kotlin; no Kotlin tree exists yet, and the Kotlin shape below binds generated code.

This document rules the requirement and the generated shapes. The generator described in `docs/specs/binary/02-binary-meta-abstraction.md` does not exist in the repository yet, so no accessor exists yet.

## Requirement

Decoding a full record collection allocates one record object per record. Consumers that need one field of one record pay the full decode cost plus the allocation of every record. The generator therefore emits, for each field of each record type in the `FormatDef`, one accessor bound to a view over the raw bytes:

- The accessor takes the record index and returns the field value.
- The accessor validates the index against the record count decoded from the header before reading.
- The accessor reads through the same bit-level primitive paths as the full decoder (`features/07-numeric-tower.md`) and returns a scalar value with no intermediate allocation.

## Offset arithmetic

The byte offset of a field is computed entirely at build time from the schema:

```text
fieldOffset(index) = headerWidth + index x recordStride + fieldBaseOffset
```

`headerWidth`, `recordStride`, and `fieldBaseOffset` derive from field order and field widths in the `FormatDef` and fold into constants at generation time (`docs/specs/features/11-inline-and-macros.md`). For the glyph metrics format of `docs/specs/binary/01-wire-format.md`:

| Field | Accessor offset |
| --- | --- |
| `recordCount` | 4 |
| `records[R].codePoint` | 8 + R x 44 + 0 |
| `records[R].advanceEm` | 8 + R x 44 + 4 |
| `records[R].xMin` | 8 + R x 44 + 12 |
| `records[R].yMin` | 8 + R x 44 + 20 |
| `records[R].xMax` | 8 + R x 44 + 28 |
| `records[R].yMax` | 8 + R x 44 + 36 |

The runtime work of an accessor is one bounds comparison, one multiply, one add, and one primitive read.

## Shape and content rule

Accessor offsets depend only on the format shape: field order, field widths, and record stride. Record content and record count vary at runtime and never enter the formula, so content changes require no regeneration.

A format is accessor-eligible only when every record field has a constant byte width, making the stride fixed. A variable-width field such as a variable-length string breaks the stride and makes the format accessor-ineligible; such a format falls back to full decode into records, and introducing one requires revising this specification first.

## Generated shapes

### Rust

```rust
pub struct VectorView<'a> {
    bytes: &'a [u8],
    record_count: usize,
}

impl<'a> VectorView<'a> {
    pub fn record_code_point(&self, index: usize) -> Result<u32, VectorError> {
        self.check_index(index)?;
        let base = 8 + index * 44;
        Ok(u32::from_be_bytes(self.bytes[base..base + 4].try_into().unwrap()))
    }
}
```

The generated code replaces the `unwrap` with the same checked slice extraction the full decoder uses.

### TypeScript

```ts
export class VectorView {
  private readonly view: DataView;

  recordCodePoint(index: number): number {
    this.checkIndex(index);
    return this.view.getUint32(8 + index * 44, false);
  }
}
```

### Haxe

```haxe
class VectorView {
	final bytes:Bytes;

	public function recordCodePoint(index:Int):Int {
		checkIndex(index);
		final base:Int = 8 + index * 44;
		return (bytes.get(base) << 24)
			| (bytes.get(base + 1) << 16)
			| (bytes.get(base + 2) << 8)
			| bytes.get(base + 3);
	}
}
```

### Kotlin

```kotlin
class VectorView(private val bytes: ByteArray) {
    fun recordCodePoint(index: Int): Int {
        checkIndex(index)
        val base = 8 + index * 44
        return (bytes[base].toInt() and 0xFF shl 24) or
            (bytes[base + 1].toInt() and 0xFF shl 16) or
            (bytes[base + 2].toInt() and 0xFF shl 8) or
            (bytes[base + 3].toInt() and 0xFF)
    }
}
```

Out-of-range indexes follow the error ruling of `docs/specs/features/06-errors-and-results.md`: `Result` with a dedicated error variant in Rust, thrown `Error` in Haxe and TypeScript, and a thrown sealed `VectorException` variant in Kotlin.

## Test hooks

Required once the generator exists; none exist yet:

- For every field and every language, the accessor value equals the value obtained from a full decode of `tests/vectors/roundtrip.bin` at the same record index.
- For every language, an out-of-range index produces the documented error variant or throw.
- A structure test asserts that generated accessors contain no loop, no closure, and no allocation call; the accessor body is one bounds check plus one primitive read as specified above.
