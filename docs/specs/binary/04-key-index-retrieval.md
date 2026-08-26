# Binary spec 04: Key-index retrieval

## Scope

This specification rules the generation of per-key retrieval methods from the format definition. For every field key of a fixed-stride format, each target language receives one accessor method that reads the field value directly at a build-time computed byte offset, without materializing intermediate records and without scanning prior records. The specification covers nested object paths and nested arrays inside a record type, and states the structural conditions a format must satisfy for accessors to exist. The ruled target languages are Haxe, Rust, TypeScript, and Kotlin; no Kotlin tree exists yet, and the Kotlin shape below binds generated code.

This document rules the requirement and the generated shapes. The generator described in `docs/specs/binary/02-binary-meta-abstraction.md` does not exist in the repository yet, so no accessor exists yet.

## Requirement

Decoding a full record collection allocates one record object per record. Consumers that need one field of one record pay the full decode cost plus the allocation of every record. The generator therefore emits, for each scalar leaf field of each record type in the `FormatDef`, one accessor bound to a view over the raw bytes:

- The accessor takes one index parameter per array level on the path from the format root to the field, in path order, and returns the field value.
- The accessor validates every index parameter against its own bound before reading: the outermost array against the record count decoded from the header, and each nested fixed-length array against its schema-constant length.
- The accessor reads through the same bit-level primitive paths as the full decoder (`features/07-numeric-tower.md`) and returns a scalar value with no intermediate allocation.

## Offset arithmetic

The byte offset of a field is computed from build-time constants and runtime index parameters:

```text
fieldOffset(i0, i1, ..., ik) = headerWidth
    + i0 x stride0
    + i1 x stride1
    + ...
    + ik x stridek
    + fieldBaseOffset
```

Every stride and every base offset derives from field order and field widths in the `FormatDef` and folds into constants at generation time (`docs/specs/features/11-inline-and-macros.md`). Each index parameter contributes exactly one multiply and one add. For the glyph metrics format of `docs/specs/binary/01-wire-format.md`:

| Field | Accessor offset |
| --- | --- |
| `recordCount` | 4 |
| `records[R].codePoint` | 8 + R x 44 + 0 |
| `records[R].advanceEm` | 8 + R x 44 + 4 |
| `records[R].xMin` | 8 + R x 44 + 12 |
| `records[R].yMin` | 8 + R x 44 + 20 |
| `records[R].xMax` | 8 + R x 44 + 28 |
| `records[R].yMax` | 8 + R x 44 + 36 |

The runtime work of an accessor is one bounds comparison per index parameter, one multiply and one add per array level, and one primitive read.

## Shape and content rule

Accessor offsets depend only on the format shape: field order, field widths, and record stride. Record content and record count vary at runtime and never enter the formula, so content changes require no regeneration.

A format is accessor-eligible only when every scalar field on every path has a constant byte width and every stride in the offset formula is a build-time constant. Two structural conditions follow:

1. **Every record field has a constant byte width.** A variable-width field such as a variable-length string breaks the stride of its enclosing record and makes the format accessor-ineligible.
2. **A runtime-count array may appear only as the outermost array.** The outermost array varies at runtime through the count in the header; its elements are indexed by arithmetic because each element has the constant stride. An array nested inside a repeated structure must carry its length as a schema constant. A nested array whose length is read at runtime makes the stride of its enclosing record runtime-dependent, so no build-time offset formula exists.

Formats that violate either condition fall back to full decode into records, and introducing support for one requires revising this specification first.

## Structural finiteness rule

The `FormatDef` must form a finite tree. A record type that references itself, directly or through another record type, is rejected during schema validation with a named error (`RecursionInFormat`) before any generation runs. Two properties depend on this rule:

- No offset formula exists for a type whose depth is unbounded, so recursive formats have no accessor arithmetic.
- Accessor generation expands one accessor per scalar leaf field. The count of generated methods equals the count of leaf fields and is independent of array cardinality, because runtime indices are parameters of one method and never expand into per-element methods. Recursive types defeat exactly this bound: expansion of a self-referential schema does not terminate.

The translatable subset therefore states: formats consumed by the accessor generator are naive finite trees of constant-width scalar fields, fixed-length nested arrays, and nested fixed-shape structures, with at most the outermost array carrying a runtime count.

## Nested path naming

Field paths below the format root consist of structure segments and array segments. Structure segments contribute name parts; array segments contribute one index parameter each. The accessor surface has candidate shapes; the ruling below selects among them. All examples use a format with `layers[L]` containing `records[R]`, each record containing a `bounds` structure with scalar fields.

### Candidate 1: Flat path-joined accessors with positional index parameters

One method per scalar leaf field on the view type. The name is the camelCase join of all path segments below the format root; the parameters are one index per array level in path order.

```ts
recordCount(): number
layerRecordBoundsXMin(layerIndex: number, recordIndex: number): number
```

### Candidate 2: Record-scoped sub-views

The view exposes one factory per array element type. The factory computes the element base offset once and returns a sub-view object whose accessors take no index parameters.

```ts
layer(layerIndex: number): LayerView
record(recordIndex: number): RecordView   // on LayerView
boundsXMin(): number                      // on RecordView
```

### Candidate 3: Chained per-level views

Every path segment, structure or array, becomes a view-returning accessor; scalar reads sit at the end of the chain.

```ts
layer(l: number): LayerView
record(r: number): RecordView             // on LayerView
bounds(): BoundsView                      // on RecordView
xMin(): number                            // on BoundsView
```

### Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Candidate 1 (Flat accessors) | One call computes the whole offset with zero allocation; each parameter is validated in the callee. | The parameter list states every dimension and its order explicitly at the call site. | One method per leaf field on one view type. | The method name reads as the field path; parameters read as indices down the path. |
| Candidate 2 (Record sub-views) | The element base offset is computed once per element, but each factory call allocates one sub-view object in TypeScript and Kotlin. | Index parameters move into factory calls; the leaf accessor carries none, so dimensions are split across two call forms. | One view class per nested element type accompanies the leaf accessors. | Reading several fields of one record groups naturally; reading one field still pays one allocation. |
| Candidate 3 (Chained views) | Every hop allocates one view object in TypeScript and Kotlin, and structure segments allocate although they carry no runtime dimension. | Structure segments gain accessor calls that select nothing. | One view class per path segment, structure or array. | The chain mirrors the schema path one segment at a time and spreads one logical read across several calls. |

## Ruling

The generated accessor surface is Candidate 1: one flat accessor per scalar leaf field on the single view type, named by the camelCase join of the path segments below the format root, taking one index parameter per array level in path order, named by the array segment with an `Index` suffix (`layerIndex`, `recordIndex`). Candidate 2 and Candidate 3 stay out of the generated surface: the motivating case is reading a small number of fields without decoding records, and that case pays zero allocation only under Candidate 1. Consumers reading many fields of one element use the full decoder.

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
- A structure test asserts that generated accessors contain no loop, no closure, and no allocation call; the accessor body is one bounds comparison per index parameter, one multiply and add per array level, and one primitive read as specified above.
- A schema validation test feeds a recursive `FormatDef` and a nested runtime-count array and asserts the named rejection errors (`RecursionInFormat`, stride violation) before any generation runs.
