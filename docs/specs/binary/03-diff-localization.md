# Binary spec 03: Diff localization

## Scope

This specification rules the procedure for localizing discrepancies when binary outputs differ across language implementations. It establishes the mathematical mapping from a byte offset to a specific logical field, and defines the reporting requirements for test failures. The procedure covers the Haxe, Rust, and TypeScript trees in the repository and the Kotlin target the pipeline will emit; no Kotlin implementation exists yet.

Implementation references:
- `samples/boring/VectorCodec.hx`
- `reference/rust/src/lib.rs`
- `reference/ts/src/vector-format.ts`
- `tests/vectors/roundtrip.bin`

## Offset localization algorithm

When comparing two byte sequences, a verification harness locates the lowest byte index B where the two streams disagree (E1[B] differs from E2[B]).

The harness maps index B to a format field using the canonical wire layout:

1. **Header region (B < 8)**:
   - 0 <= B < 4: Field `magic` (ASCII bytes `BRG1`).
   - 4 <= B < 8: Field `recordCount` (32-bit unsigned big-endian integer).

2. **Record region (8 <= B < 8 + 44 x N)**:
   - Compute record index:
     R = floor((B - 8) / 44)
   - Compute intra-record byte offset:
     K = (B - 8) mod 44
   - Map K to the record field:
     - 0 <= K < 4: `records[R].codePoint` (u32, bytes K - 0)
     - 4 <= K < 12: `records[R].advanceEm` (f64, bytes K - 4)
     - 12 <= K < 20: `records[R].bounds.xMin` (f64, bytes K - 12)
     - 20 <= K < 28: `records[R].bounds.yMin` (f64, bytes K - 20)
     - 28 <= K < 36: `records[R].bounds.xMax` (f64, bytes K - 28)
     - 36 <= K < 44: `records[R].bounds.yMax` (f64, bytes K - 36)

3. **Trailing region (B >= 8 + 44 x N)**:
   - Trailing extraneous bytes after expected record payloads.

## Code mapping per tree

Each identified field maps to a specific serialization statement in each codebase:

| Field | Haxe encoder (`samples/boring/VectorCodec.hx`) | Rust encoder (`reference/rust/src/lib.rs`) | TypeScript encoder (`reference/ts/src/vector-format.ts`) |
| --- | --- | --- | --- |
| `magic` | `writer.writeAscii(MAGIC)` | `bytes.extend_from_slice(VECTOR_MAGIC)` | `writer.writeAscii(VECTOR_MAGIC)` |
| `recordCount` | `writer.writeU32(records.length)` | `bytes.extend_from_slice(&count.to_be_bytes())` | `writer.writeU32(records.length)` |
| `codePoint` | `writer.writeU32(record.codePoint)` | `bytes.extend_from_slice(&record.code_point.to_be_bytes())` | `writer.writeU32(record.codePoint)` |
| `advanceEm` | `writer.writeF64(record.advanceEm)` | `bytes.extend_from_slice(&record.advance_em.to_bits().to_be_bytes())` | `writer.writeF64(record.advanceEm)` |
| `bounds.xMin` | `writer.writeF64(record.bounds.xMin)` | `bytes.extend_from_slice(&record.bounds.x_min.to_bits().to_be_bytes())` | `writer.writeF64(record.bounds.xMin)` |
| `bounds.yMin` | `writer.writeF64(record.bounds.yMin)` | `bytes.extend_from_slice(&record.bounds.y_min.to_bits().to_be_bytes())` | `writer.writeF64(record.bounds.yMin)` |
| `bounds.xMax` | `writer.writeF64(record.bounds.xMax)` | `bytes.extend_from_slice(&record.bounds.x_max.to_bits().to_be_bytes())` | `writer.writeF64(record.bounds.xMax)` |
| `bounds.yMax` | `writer.writeF64(record.bounds.yMax)` | `bytes.extend_from_slice(&record.bounds.y_max.to_bits().to_be_bytes())` | `writer.writeF64(record.bounds.yMax)` |

No Kotlin tree exists yet. When the pipeline emits one, its encoder statements mirror the Haxe and TypeScript column (`writer.writeU32(...)`, `writer.writeF64(...)`), with `Double.toBits()` supplying the Rust `to_bits` role; the generator adds the Kotlin column to this table in the same commit that introduces the tree.

## Worked example

Consider a byte disagreement discovered at offset B = 22 against `tests/vectors/roundtrip.bin`.

1. Offset evaluation: B = 22 >= 8.
2. Record calculation:
   R = floor((22 - 8) / 44) = floor(14 / 44) = 0
   The difference is located in the first record (`records[0]`).
3. Intra-record offset calculation:
   K = (22 - 8) mod 44 = 14
4. Field evaluation: K = 14 falls within the range 12 <= K < 20.
   The failing field is `records[0].bounds.xMin`. The disagreement is at byte 2 of the 8-byte IEEE 754 float payload.
5. Code attribution:
   - Haxe: `VectorCodec.encode` in `samples/boring/VectorCodec.hx` (line 20) via `BinaryWriter.writeF64`.
   - Rust: `encode_vector` in `reference/rust/src/lib.rs` (line 92) via `record.bounds.x_min.to_bits().to_be_bytes()`.
   - TypeScript: `encodeVector` in `reference/ts/src/vector-format.ts` (line 22) via `BinaryWriter.writeF64`.

## Test reporting rule

When a unit test or vector comparison test detects mismatched binary output, the test assertion must output the resolved field path, record index, byte offset, expected byte value, and actual byte value. Reporting a raw byte offset without the field path is non-compliant.
