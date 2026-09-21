# Standard library spec 15: String code-unit operations

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
- Haxe exposes no indexed read form on a `String`: `s[i]` is rejected at
  compile time with `Array access is not allowed on String`, so
  `charCodeAt` is the only member that reads one UTF-16 code unit at an
  index. The rows below name members, and no row names an index syntax.

A comparison of a `charCodeAt` result against an `Int` literal and a
null test on the result follow the nullable `Null<Int>` forms the
targets already lower.

## Current state

| Member | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| `length` | `.length` (code units) | `.length` (code units) | current lowering | current lowering | `u_string::unit_count(&s)`, one `encode_utf16` scan per call, in the `u32` domain of `Int` |
| `charCodeAt` | `Number.isNaN(s.charCodeAt(i)) ? null : s.charCodeAt(i)` for pure operands; `readUnit(s, i)` when either operand may have effects | `run { val _s = s; val _i = i; if (_i >= 0 && _i < _s.length) _s[_i].code else null }` with single evaluation | current lowering | `(() { final _s = s; final _i = i; return _i >= 0 && _i < _s.length ? _s.codeUnitAt(_i) : null; })()` with single evaluation | `u_string::unit_at(&s, i)` walks `s.encode_utf16()`, so the index counts UTF-16 code units: each half of a surrogate pair carries its own address and the value is the unit, while an index past the last unit answers `None`. The code-point read `u_string::at` stays with `std.UString.at` (stdlib spec 10) |
| `split` | `.split(sep)` | current lowering | current lowering | current lowering | `u_string::split(&s, &sep)` scans the two `encode_utf16` unit vectors for the literal separator and returns a `Vec<String>`, keeping empty parts and answering one part per unit for the empty separator |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Route the three members through the code-unit domain on every target | One native read or one scan per call on four targets; Rust scans its UTF-8 storage into the UTF-16 unit count behind `u_string` | One ruled domain shared with `substring`; the out-of-range result is the nullable form everywhere | The Rust runtime keeps one unit-domain helper set under `u_string` | Sites read as the native member call |
| Keep the Rust byte domain and document it | No runtime work | A byte count differs from a code-unit count on non-ASCII input and from `substring` positions in the same expression | Two index domains in one type | Wrong results on valid input |
| Route callers through `std.UString` by hand | No compiler work | Every consumer re-spells the walk | The port repeats the loop at every caller | Port source stops using the native members |

## Ruling

1. On every target the three members address UTF-16 code units, the
   domain `substring` addresses:

   | Member | TypeScript | Kotlin | Swift | Dart | Rust |
   | --- | --- | --- | --- | --- | --- |
   | `s.length` | `s.length` | `s.length` | current lowering, verified against the Contract | current lowering, verified against the Contract | the `u_string` unit count cast to the `u32` domain of `Int` |
   | `charCodeAt` | the nullable NaN conversion in the pure-operand expression form, or `readUnit(s, i)` for effectful operands | `run` expression captures receiver and index once, bounds-checks, and reads `.code`; an out-of-range index yields null | current lowering, verified | closure expression captures receiver and index once, bounds-checks, and reads `codeUnitAt`; an out-of-range index yields null | the `u_string` unit read in the nullable form; an out-of-range index yields the null value, never a panic |
   | `s.split(sep)` | `s.split(sep)` | current lowering, verified | current lowering, verified | current lowering, verified | one scan collecting a `Vec<String>`; empty parts are kept; the empty separator yields one part per code unit |

2. A row marked "current lowering, verified" keeps its native rendering
   once the sample suite proves the Contract on that target; a
   divergence found by the suite is a defect this specification rules
   against and the target fixes its rendering in the same change.
3. The Rust length rendering and its sample rows appear in the value
   semantics specification (feature spec 38); this specification rules the
   behavior and the rendering, and its samples cover `charCodeAt` and
   `split`.

## Samples and tests

- `samples/boring/StringUnitOps.hx`: `charCodeAt` in range, at the last
  index, and out of range; `charCodeAt` at a caller-supplied unit index,
  which addresses each half of a surrogate pair separately; `split` on
  a present separator, an absent separator, and repeated separators
  producing empty parts; one BMP-range row over a CJK string. The same
  module carries the `substr` unit cut that feature spec 08 ruling 9
  rules, with and without a length over an astral string.
- `samples/tests/StringUnitTests.hx`: the in-range code value, the
  out-of-range null test, the split part counts, the split contents, and
  the `length` of a string holding one astral code point as four units.
  out-of-range null test, the split part counts, the split contents, the
  four unit values of an astral string, the two units of its surrogate
  pair, and the unit cuts that fall between them.
- Both modules are entered in all eight generation hxml files.
