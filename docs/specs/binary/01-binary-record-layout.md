# Binary spec 01: Binary record layout

## Scope

This specification rules the byte layout of a binary record block: the header shape, the field order inside a record, the byte widths of the field types, endianness, the record count domain, and the precision rule for committed test values. A binary record block is one contiguous byte sequence holding an 8-byte header followed by a fixed number of fixed-width records of one record type. The record type is declared in Haxe source under `docs/specs/binary/02-binary-record-io.md`; this specification rules the byte mechanics that hold for every record type declared there.

The rules are language-independent: every target the Reflaxe pipeline emits decodes the same bytes under the type rulings in `features/` and `stdlib/`.

The layout is implemented for the glyph metrics format in:
- `samples/boring/VectorCodec.hx`
- `reference/kotlin/src/boring/VectorCodec.kt`
- `reference/rust/src/lib.rs`
- `reference/ts/src/vector-format.ts`

The Reflaxe-generated trees (`reference/ts/gen`, `reference/kotlin/gen`) decode under the same rulings as their hand-written counterparts.

Fixed test vectors verifying this layout live in:
- `tests/vectors/roundtrip.json` (human-readable vector definitions)
- `tests/vectors/roundtrip.bin` (committed reference binary)

Count-domain edge coverage lives in the per-tree suites:
- `tests/haxe/Main.hx`
- `tests/ts/vector.test.ts` and `tests/reference/ts/generated-tree.test.ts`
- `tests/kotlin/Main.kt`
- `tests/rust/vector.rs`

## Header layout

Every valid block begins with an 8-byte header:

| Offset (bytes) | Length (bytes) | Type | Field | Value / Description |
| --- | --- | --- | --- | --- |
| 0..3 | 4 | `[u8; 4]` (ASCII) | `magic` | Four ASCII bytes: a three-letter format stem followed by one digit declaring the float width family |
| 4..7 | 4 | `u32` (BE) | `recordCount` | Unsigned 32-bit integer count of records following the header |

Header byte length is fixed at 8 bytes. The digit declares the float width family ruled in `05-block-float-widths.md`: `1` for binary64, `2` for binary32, `3` for binary16 float fields. The three-letter stem identifies the record format; its derivation from the declaration and its validation are ruled in `02-binary-record-io.md`. A decoder that meets a magic it does not know rejects the block with `BadMagic` (`features/06-errors-and-results.md`) before reading any record byte.

## Record layout

The header is followed by `recordCount` sequential, fixed-width records of one record type.

1. Fields occupy the record in declaration order.
2. A field whose type is itself a record typedef flattens in place: its own fields continue the byte sequence depth-first in their declaration order.
3. Records carry zero inter-field padding and zero inter-record padding.

The byte width of each field type per float width family:

| Field type | binary64 family | binary32 family | binary16 family |
| --- | --- | --- | --- |
| `Int` | 4 bytes, `u32` BE | 4 bytes, `u32` BE | 4 bytes, `u32` BE |
| `Float` | 8 bytes, `f64` BE | 4 bytes, `f32` BE | 2 bytes, `f16` BE |
| nested record typedef | sum of its flattened field widths at the same family | same | same |

A record's byte width is the sum of its flattened field widths and is constant for one format and one family. Total block byte length for N records is 8 + recordWidth x N bytes. Trailing bytes beyond that total are strictly invalid and decoders reject them with `TrailingBytes` (`features/06-errors-and-results.md`).

For the glyph metrics format (one `Int` field, one `Float` field, and one nested typedef of four `Float` fields), the binary64 family gives a 44-byte record; `05-block-float-widths.md` rules the 24-byte and 14-byte records of the binary32 and binary16 families. The per-field offsets of this format are worked out as the example of `02-binary-record-io.md`.

## Record count domain

The decodable record count domain is [0, 2^31). The header field is u32, but the reference trees hold decoded counts in a signed 32-bit integer (the Kotlin `Int`), so every tree rejects counts at or above 0x80000000 with the `CountOverflow` failure identity (`features/06-errors-and-results.md`) before any allocation or record byte is read:

| Input count | Result |
| --- | --- |
| 0x00000000 ..= 0x7fffffff | decode proceeds |
| 0x80000000 ..= 0xffffffff | `CountOverflow`, no allocation, no record read |

The reader implementations differ in the numeric domain of the guard and reject the same inputs. The hand-written TypeScript tree reads the count unsigned and compares against 0x7fffffff; the Rust tree reads u32 and compares against 2147483647; the Haxe tree and both generated trees hold the count in signed 32-bit semantics and compare against the negative half (`count < 0`).

Encode never writes a count outside the domain: every tree encodes its in-memory record count, which cannot exceed 2^31 - 1 elements in the reference trees' array types. The Rust encoder maps a length above u32::MAX to the same `CountOverflow` identity for type completeness.

## Endianness ruling

All multi-byte numeric fields are encoded in big-endian byte order (network byte order, most significant byte first).

1. `u32` integers write the highest-order 8 bits at the lowest memory offset.
2. `f64` floating-point values follow IEEE 754 double-precision standard format (1 sign bit, 11 exponent bits, 52 mantissa bits). The 64 bits are encoded as two sequential big-endian 32-bit words (high 32 bits followed by low 32 bits), equivalent to big-endian 64-bit integer bit casting. `f32` and `f16` fields follow the IEEE 754 binary32 and binary16 layouts at 4 and 2 big-endian bytes (binary spec 05).

## Dyadic-rational test-value rule

Test vectors stored in `tests/vectors/roundtrip.json` and generated into `tests/vectors/roundtrip.bin` require exact cross-platform reproducibility.

Floating-point decimal representations frequently produce repeating fractions in binary (for example, decimal 0.1 is binary 0.0001100110011..., which never terminates). Different compiler runtimes or decimal parsing libraries can introduce discrepancies in the least significant mantissa bit when rounding repeating binary fractions.

To guarantee bit-identical encodings across all targets, every float value assigned to a committed test vector must be a dyadic rational: a number of the form m / 2^k where m and k are integers.

Examples from `tests/vectors/roundtrip.json`:
- 0.5 = 1/2 (exact binary 0.1)
- 0.75 = 3/4 (exact binary 0.11)
- 0.03125 = 1/32 (exact binary 0.00001)
- -0.21875 = -7/32 (exact binary -0.00111)
- -0.875 = -7/8 (exact binary -0.111)

Because dyadic rationals terminate in finite binary fractions, IEEE 754 double-precision representation incurs zero truncation error during decimal-to-binary parsing. Haxe, Kotlin, Rust, and TypeScript generate identical 64-bit IEEE patterns for these values.

## Canonical field order

The sequential order of header fields and record fields forms the canonical reading order:
1. `magic`
2. `recordCount`
3. For each record index i from 0 to recordCount - 1, the flattened field sequence of the record type in declaration order (for the glyph metrics format: `codePoint`, `advanceEm`, `bounds.xMin`, `bounds.yMin`, `bounds.xMax`, `bounds.yMax`).

This deterministic sequence establishes the foundation for binary diff localization specified in `03-diff-localization.md`.
