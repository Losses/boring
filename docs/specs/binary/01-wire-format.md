# Binary spec 01: Wire format

## Scope

This specification defines the binary wire format for glyph metrics records shared across the Haxe, Kotlin, Rust, and TypeScript implementations. It rules byte alignment, field ordering, integer and floating-point representations, endianness, count domain, and numerical precision constraints. The layout is language-independent: any other target the Reflaxe pipeline emits decodes the same bytes under the type rulings in `features/` and `stdlib/`.

The wire format is implemented in:
- `haxe/src/boring/VectorCodec.hx`
- `kotlin/src/boring/VectorCodec.kt`
- `rust/src/lib.rs`
- `ts/src/vector-format.ts`

The Reflaxe-generated trees (`ts/gen`, `kotlin/gen`) decode under the same rulings as their hand-written counterparts.

Fixed test vectors verifying this layout live in:
- `tests/vectors/roundtrip.json` (human-readable vector definitions)
- `tests/vectors/roundtrip.bin` (committed reference binary)

Count-domain edge coverage lives in the per-tree suites:
- `tests/haxe/Main.hx`
- `tests/ts/vector.test.ts` and `tests/ts/generated-tree.test.ts`
- `tests/kotlin/Main.kt`
- `tests/rust/vector.rs`

## Header layout

Every valid vector binary begins with an 8-byte header:

| Offset (bytes) | Length (bytes) | Type | Field | Value / Description |
| --- | --- | --- | --- | --- |
| 0..3 | 4 | `[u8; 4]` (ASCII) | `magic` | Exact ASCII bytes `BRG1` (`0x42`, `0x52`, `0x47`, `0x31`) |
| 4..7 | 4 | `u32` (BE) | `recordCount` | Unsigned 32-bit integer count of records following the header |

Header byte length is fixed at 8 bytes.

## Record layout

The header is followed by `recordCount` sequential, fixed-width records. Each record occupies exactly 44 bytes with zero inter-field padding:

| Offset in record (bytes) | Length (bytes) | Type | Field | Description |
| --- | --- | --- | --- | --- |
| 0..3 | 4 | `u32` (BE) | `codePoint` | Unicode scalar value (range `0x0000` to `0x10FFFF`) |
| 4..11 | 8 | `f64` (BE) | `advanceEm` | Horizontal advance width in em units |
| 12..19 | 8 | `f64` (BE) | `bounds.xMin` | Minimum bounding horizontal coordinate in em units |
| 20..27 | 8 | `f64` (BE) | `bounds.yMin` | Minimum bounding vertical coordinate in em units |
| 28..35 | 8 | `f64` (BE) | `bounds.xMax` | Maximum bounding horizontal coordinate in em units |
| 36..43 | 8 | `f64` (BE) | `bounds.yMax` | Maximum bounding vertical coordinate in em units |

Total file byte length for N records is 8 + 44 x N bytes.

Trailing bytes beyond 8 + 44 x N are strictly invalid and rejected by decoders.

## Record count domain

The decodable record count domain is [0, 2^31). The wire field is u32, but the reference trees hold decoded counts in a signed 32-bit integer (the Kotlin `Int`), so every tree rejects counts at or above 0x80000000 with the `CountOverflow` failure identity (`features/06-errors-and-results.md`) before any allocation or record byte is read:

| Input count | Result |
| --- | --- |
| 0x00000000 ..= 0x7fffffff | decode proceeds |
| 0x80000000 ..= 0xffffffff | `CountOverflow`, no allocation, no record read |

The reader implementations differ in the numeric domain of the guard and reject the same inputs. The hand-written TypeScript tree reads the count unsigned and compares against 0x7fffffff; the Rust tree reads u32 and compares against 2147483647; the Haxe tree and both generated trees hold the count in signed 32-bit semantics and compare against the negative half (`count < 0`).

Encode never writes a count outside the domain: every tree encodes its in-memory record count, which cannot exceed 2^31 - 1 elements in the reference trees' array types. The Rust encoder maps a length above u32::MAX to the same `CountOverflow` identity for type completeness.

## Endianness ruling

All multi-byte numeric fields are encoded in big-endian byte order (network byte order, most significant byte first).

1. `u32` integers write the highest-order 8 bits at the lowest memory offset.
2. `f64` floating-point values follow IEEE 754 double-precision standard format (1 sign bit, 11 exponent bits, 52 mantissa bits). The 64 bits are encoded as two sequential big-endian 32-bit words (high 32 bits followed by low 32 bits), equivalent to big-endian 64-bit integer bit casting.

## Dyadic-rational test-value rule

Test vectors stored in `tests/vectors/roundtrip.json` and generated into `tests/vectors/roundtrip.bin` require exact cross-platform reproducibility.

Floating-point decimal representations frequently produce repeating fractions in binary (for example, decimal 0.1 is binary 0.0001100110011..., which never terminates). Different compiler runtimes or decimal parsing libraries can introduce discrepancies in the least significant mantissa bit when rounding repeating binary fractions.

To guarantee bit-identical encodings across all targets, all test values assigned to `advanceEm` and `bounds` fields must be dyadic rationals: numbers of the form m / 2^k where m and k are integers.

Examples from `tests/vectors/roundtrip.json`:
- 0.5 = 1/2 (exact binary 0.1)
- 0.75 = 3/4 (exact binary 0.11)
- 0.03125 = 1/32 (exact binary 0.00001)
- -0.21875 = -7/32 (exact binary -0.00111)
- -0.875 = -7/8 (exact binary -0.111)

Because dyadic rationals terminate in finite binary fractions, IEEE 754 double-precision representation incurs zero truncation error during decimal-to-binary parsing. Haxe, Kotlin, Rust, and TypeScript generate identical 64-bit IEEE patterns for these values.

## Canonical field order

The sequential order of fields in this specification forms the canonical reading order:
1. `magic`
2. `recordCount`
3. For each record index i from 0 to recordCount - 1:
   - `record[i].codePoint`
   - `record[i].advanceEm`
   - `record[i].bounds.xMin`
   - `record[i].bounds.yMin`
   - `record[i].bounds.xMax`
   - `record[i].bounds.yMax`

This deterministic sequence establishes the foundation for binary diff localization specified in `03-diff-localization.md`.
