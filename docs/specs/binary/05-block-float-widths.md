# Binary spec 05: Block float widths

## Scope

This specification rules the selectable floating-point width of a vector
block. One marker in the header declares the width of every float field in
the block: binary64 (`BRG1`, 8 bytes per field), binary32 (`BRG2`, 4 bytes
per field), or binary16 (`BRG3`, 2 bytes per field). The width serves
transfer-size-sensitive consumers that accept fewer mantissa bits in
exchange for smaller blocks. The marker is a property of the encoded bytes;
readers dispatch on it at decode time, and a reader that knows no given
magic rejects the block explicitly; no reader guesses a layout.

The width marker is implemented in:

- `samples/boring/FloatWidth.hx` (the width enum)
- `samples/boring/VectorCodec.hx` (magic dispatch, encode, decode)
- `samples/boring/Fp32.hx` and `samples/boring/Fp16.hx` (bit-pattern edge cases)
- `samples/boring/BinaryReader.hx` and `samples/boring/BinaryWriter.hx`
  (`readF32`, `readF16`, `writeF32`, `writeF16`)
- `reference/kotlin/src/boring/VectorCodec.kt`, `reference/rust/src/lib.rs`,
  and `reference/ts/src/vector-format.ts` (hand-written counterparts)
- `reference/ts/src/fp16.ts` and `reference/kotlin/src/boring/Fp16.kt`
  (hand-written binary16 edges; the Rust edges live in `lib.rs`)

Committed vectors verifying every width live in:

- `tests/vectors/roundtrip.bin` (`BRG1`, 184 bytes)
- `tests/vectors/roundtrip-f32.bin` (`BRG2`, 104 bytes)
- `tests/vectors/roundtrip-f16.bin` (`BRG3`, 64 bytes)

All three encode the same records from `tests/vectors/roundtrip.json`; every
value in them is an exact binary16 value, so the three blocks carry equal
values at decreasing widths.

## Width marker

The first 4 header bytes declare the block float width:

| Magic bytes | ASCII | Block float width | Bytes per float field |
| --- | --- | --- | --- |
| `0x42 0x52 0x47 0x31` | `BRG1` | binary64 | 8 |
| `0x42 0x52 0x47 0x32` | `BRG2` | binary32 | 4 |
| `0x42 0x52 0x47 0x33` | `BRG3` | binary16 | 2 |

The record count field, the count domain of binary spec 01, and the
trailing-bytes rejection are unchanged by the width. `BRG1` blocks are
byte-for-byte what binary spec 01 ruled before this specification existed.

## Record layout per width

A record holds one `u32` code point and five float fields at the block
width:

| Width | Record bytes | Total bytes for N records |
| --- | --- | --- |
| binary64 | 4 + 5 x 8 = 44 | 8 + 44 x N |
| binary32 | 4 + 5 x 4 = 24 | 8 + 24 x N |
| binary16 | 4 + 5 x 2 = 14 | 8 + 14 x N |

Field order follows the canonical order of binary spec 01 at every width.

## Rounding at the block edges

1. **Encode rounds once per field.** A binary32 field rounds the module
   real to binary32 with round-to-nearest-even at the write edge; a
   binary16 field rounds to binary16 the same way. Decoded values widen to
   the module real exactly, because every binary32 and binary16 value is
   exactly representable in binary64.
2. **Binary16 encode goes through binary32.** The binary16 edge is defined
   as two successive roundings: the module real rounds to binary32, then
   the binary32 value rounds to binary16. The composition is deterministic
   and identical on every tree; defining it this way keeps one bit-conversion
   implementation per target and needs no second direct 52-bit narrowing
   path.
3. **Special values.** Infinity passes through at every width. NaN stays a
   NaN with the quiet bit set; payload bits beyond the target mantissa are
   dropped. Magnitude at or above the largest finite value of the target
   width rounds to infinity (the boundary 65520 is the tie between 65504
   and 65536 under round-to-nearest-even and rounds up). Signed zero keeps
   its sign at every width.
4. **Subnormals.** A binary64 subnormal rounds to signed zero in binary32
   (its magnitude lies far below half of the smallest binary32 subnormal),
   and a binary32 subnormal likewise rounds to signed zero in binary16.
   Widening directions map subnormals exactly: a binary16 subnormal
   normalizes into a binary32 normal, and a binary32 subnormal normalizes
   into a binary64 normal.

The hand-written TypeScript and Kotlin trees use the platform bit edges
(`DataView.setFloat32`, `Float.toRawBits`) for the binary32 step and the
shared integer algorithm for the binary16 step; the Haxe source and the
Rust tree run the integer algorithm for both steps. Both routes compute
the same rounding rule, and the shared vectors pin the agreement.

## Relationship to the float-precision define

The block width and the `float-precision` define of feature spec 23 are
independent axes:

- The define selects the module real width once per compilation and never
  changes the bytes of a block.
- The block width is chosen per encode call and recorded in the magic; any
  compilation can encode and decode all three widths.

On the f32 module lane a `BRG2` block performs no rounding at all: the
encoded binary32 values are the module reals themselves. On the default
lane the same block widens each decoded value exactly and rounds each
encoded value once. The four combinations of module width and block width
are all valid and produce identical bytes for the same records whenever
the values are exact on the narrower grid.

## Reader rejection

A decoder reads the 4 magic bytes and maps them to a width. A magic outside
the table answers `BadMagic`, the existing failure identity of feature
spec 06. A reader built before a width existed therefore rejects that
block explicitly; no silent misread is possible, because every width change
requires a new magic. The rejection path adds no new failure variant.

## Wire field types

The wire type table of feature spec 07 gains two rows: `WireF32Be` maps to
`Float`-to-`f32` edges of 4 bytes big-endian, and `WireF16Be` covers the
2-byte binary16 fields. A binary32 or binary16 value never travels in the
8-byte `WireF64Be` field; each width has its own field type and its own
reader and writer methods (`readF32`, `readF16`, `writeF32`, `writeF16`).

## Test hooks

- `samples/tests/VectorCodecTests.hx` round-trips every width through
  encode and decode on all generated lanes.
- `samples/tests/Fp32Tests.hx` and `samples/tests/Fp16Tests.hx` pin
  bit-exact edge behavior on integer bit inputs, including ties, overflow,
  subnormals, signed zero, infinity, and NaN.
- `tests/haxe/Main.hx`, `tests/kotlin/Main.kt` (with its `MainF32.kt`
  copy), `tests/rust/vector.rs`, and `tests/ts/block-width.test.ts` assert
  the committed binaries of all three widths byte for byte, the rejection
  of unknown magics, and the per-width record byte counts.
- `tests/swift/main.swift` and `tests/dart/vector_main.dart` assert the
  same committed binaries byte for byte and the unknown-magic rejection
  on the Swift and Dart generated trees (`test:swift`, `test:dart`).
- `tools/gen-vector.ts` regenerates all three committed binaries from
  `tests/vectors/roundtrip.json`.
