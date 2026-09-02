# Standard library spec 15: String code-unit surface

## Scope

This specification rules three native members of the Haxe `String` type
on all five source targets (ts, kotlin, swift, dart, rust): `length`,
`charCodeAt`, and `split`. The ruled domain is the UTF-16 code-unit
domain the `substring` member already addresses: every index counts
UTF-16 code units and every value read is one UTF-16 code unit. The
registry tool under `tools/registry` is the consumer: its JSON reader
walks the input with `charCodeAt` and its version parser splits on
`"."`. The f32 configurations inherit the rules and differ only in float
width.

## Contract

- `s.length` returns the number of UTF-16 code units in `s` as an `Int`.
- `s.charCodeAt(i)` returns the UTF-16 code unit at index `i` as an
  `Int` when `0 <= i < s.length`, and `null` outside that range.
- `s.split(sep)` splits `s` on every occurrence of the separator string
  `sep`, keeps empty parts, and returns `Array<String>`. A call with an
  empty separator returns one single-code-unit string per code unit of
  `s`. The separator matches literally; no pattern form is accepted.

A comparison of a `charCodeAt` result against an `Int` literal and a
null test on the result follow the nullable `Null<Int>` forms the
targets already lower.

## Current state

| Member | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| `length` | `.length` (code units) | `.length` (code units) | current lowering | current lowering | `.len()` over the byte storage, `usize` type, wrong count for non-ASCII input |
| `charCodeAt` | `.charCodeAt(i)` (code units, `undefined` out of range) | current lowering | current lowering | current lowering | `.as_bytes()[i]`, one byte, panics at the end of the string |
| `split` | `.split(sep)` | current lowering | current lowering | current lowering | no lowering; the native `str::split` iterator passes through with no array type |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Route the three members through the code-unit domain on every target | One native read or one scan per call on four targets; Rust walks the UTF-16 units its runtime already stores behind `u_string` | One ruled domain shared with `substring`; the out-of-range result is the nullable form everywhere | The Rust runtime keeps one unit-domain helper set under `u_string` | Sites read as the native member call |
| Keep the Rust byte domain and document it | No runtime work | A byte count differs from a code-unit count on non-ASCII input and from `substring` positions in the same expression | Two index domains in one type | Wrong results on valid input |
| Route callers through `std.UString` by hand | No compiler work | Every consumer re-spells the walk | The port repeats the loop at every caller | Port source stops using the native members |

## Ruling

1. On every target the three members address UTF-16 code units, the
   domain `substring` addresses:

   | Member | TypeScript | Kotlin | Swift | Dart | Rust |
   | --- | --- | --- | --- | --- | --- |
   | `s.length` | `s.length` | `s.length` | current lowering, verified against the Contract | current lowering, verified against the Contract | the `u_string` unit count cast to the `u32` domain of `Int` |
   | `s.charCodeAt(i)` | `s.charCodeAt(i)` | current lowering, verified | current lowering, verified | current lowering, verified | the `u_string` unit read in the nullable form; an out-of-range index yields the null value, never a panic |
   | `s.split(sep)` | `s.split(sep)` | current lowering, verified | current lowering, verified | current lowering, verified | one scan collecting a `Vec<String>`; empty parts are kept; the empty separator yields one part per code unit |

2. A row marked "current lowering, verified" keeps its native rendering
   once the sample suite proves the Contract on that target; a
   divergence found by the suite is a defect this specification rules
   against and the target fixes its rendering in the same change.
3. The Rust length rendering and its sample rows land in the value
   semantics lane (feature spec 38); this specification rules the
   behavior and the rendering, and the samples of this lane cover
   `charCodeAt` and `split`.

## Samples and tests

- `samples/boring/StringUnitOps.hx`: `charCodeAt` in range, at the last
  index, and out of range; `split` on a present separator, an absent
  separator, and repeated separators producing empty parts; one
  BMP-range row over a CJK string.
- `samples/tests/StringUnitTests.hx`: the in-range code value, the
  out-of-range null test, the split part counts, and the split contents.
- Both modules are entered in all eight generation hxml files.
