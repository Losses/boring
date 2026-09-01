# Standard library spec 13: StringTools.hex and String case conversion

## Scope

This specification rules the translation of `StringTools.hex` and the two
String case conversions `toLowerCase` and `toUpperCase` on all five source
targets (ts, kotlin, swift, dart, rust). The ported engine source is the
consumer: the evidence tests render code point labels
(`"U+" + StringTools.hex(codePoint, 0).toLowerCase()`,
`engine-haxe/src/org/tiqian/core/UnicodeScriptEvidenceTest.hx`), the profile
labels render padded uppercase hexadecimal forms
(`char.code.toString(16).uppercase().padStart(4, '0')` in the handwritten
Kotlin `ClreqProfile.kt`, ported as `StringTools.hex(char.code, 4)`), the
escape renderer pads the lowercase form
(`PreparedParagraph.kt` pads `char.code.toString(16)` to four digits, ported
as `StringTools.hex(char.code, 4).toLowerCase()`), and the locale and
hyphenation normalizations call `toLowerCase` on language tags and words
(`UnicodeEastAsianSpacing.hx`, the port of `EastAsianSpacing.kt` and
`Hyphenation.kt`). Haxe holds no infix hexadecimal literal spelling, so the
port cannot avoid the standard function.

## Contract

`StringTools.hex(value:Int, ?digits:Int):String` returns the uppercase
hexadecimal form of a non-negative `Int`, built from the low nibble up
(`"0123456789ABCDEF"`); `hex(0)` is `"0"`. When `digits` is absent, or its
value is at most the produced length, the result is unpadded; otherwise the
result is left-padded with `"0"` to exactly `digits` characters. A negative
`value` or a negative `digits` stops the compilation with
`StringTools.hex accepts non-negative arguments only`: the haxe standard
implementation shifts unsigned, so a negative input holds no
cross-target-agreeing meaning, and the rejection names the domain so no
target renders a divergent form.

`s.toLowerCase()` and `s.toUpperCase()` return the target's native Unicode
conversion of `s`. The haxe standard delegates to the platform conversion,
and every target holds one spelling of the same operation; the consistency
rows use inputs whose conversions agree across targets (ASCII letters and
language tags), the pattern the float rows of
`docs/specs/stdlib/12-std-string.md` established for agreeing shortest
forms.

## Current translations

| Target | State |
| --- | --- |
| TypeScript | Nothing lowers the two functions. `StringTools.hex` renders as an unresolved static reference; `toLowerCase` and `toUpperCase` hold the same spelling on the target, so the passthrough happens to compile. |
| Kotlin | Nothing lowers the two functions. `StringTools.hex` renders as an unresolved static reference; the String instance arm passes methods through, so `toLowerCase` renders the deprecated Kotlin spelling (`lowercase()` is the current one). |
| Swift | Nothing lowers the two functions. `StringTools.hex` renders as an unresolved static reference; `toLowerCase` passes through as an unresolved member (`lowercased()` is the target spelling). |
| Dart | Nothing lowers the two functions. `StringTools.hex` renders as an unresolved static reference; the case conversions hold the same spelling on the target, so the passthrough happens to compile. |
| Rust | Nothing lowers the two functions; both render as unresolved references. |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| One native expression per target at the call site | Each conversion is one target-native call or one format expression; the padded hexadecimal form is one format string on the format-holding targets. | The domain is checked at compile time with one named error on every target. | No runtime helper exists to keep in sync. | Sites read as the target's own conversion. |
| A resident runtime helper per target | Every call pays a dispatch for a conversion each target spells natively. | The helper re-implements the nibble loop the format machinery already holds. | Five helpers for two functions. | Sites read as a library call longer than the target's own expression. |
| Port-side re-spelling per target via dead arms | No compiler work. | The port cannot name the target in its source, so the dead-arm shape cannot express five spellings. | Every consumer re-decides the spelling. | Port source drifts from the haxe standard function. |

## Ruling

1. `StringTools.hex` lowers at its call site on every target as one
   expression; `d` is the rendered `digits` argument when present and `v`
   the rendered value:

   | Form | TypeScript | Kotlin | Swift | Dart | Rust |
   | --- | --- | --- | --- | --- | --- |
   | `hex(v)` | `v.toString(16).toUpperCase()` | `v.toString(16).uppercase()` | `String(v, radix: 16, uppercase: true)` | `v.toRadixString(16).toUpperCase()` | `format!("{:X}", v)` |
   | `hex(v, d)` | `v.toString(16).toUpperCase().padStart(d, "0")` | `v.toString(16).uppercase().padStart(d, '0')` | the padding expression below | `v.toRadixString(16).toUpperCase().padLeft(d, "0")` | `format!("{:0w$X}", v, w = usize::try_from(d).unwrap_or_default())` |

   Swift holds no pad member; `hex(v, d)` renders one immediately-invoked
   closure carrying the statement sequence, the shape of the Swift array
   builder of `docs/specs/stdlib/12-std-string.md`:
   `{ let s = String(v, radix: 16, uppercase: true); return s.count < Int(d) ? String(repeating: "0", count: Int(d) - s.count) + s : s }()`,
   which converts once and allocates one padding string at most. The Swift
   initializer takes `uppercase: true` because its radix form without the
   flag yields lowercase digits, which the uppercase return contract of the
   Contract section rules out; the digits argument renders through `Int`
   because Swift's count members hold `Int` while the argument carries the
   Haxe `Int` width. The Rust padded form renders the width inline as
   `format!("{:0w$X}", v, w = usize::try_from(d).unwrap_or_default())`;
   the width converts without a truncating cast, and a width that fails
   `usize::try_from` (negative or wider than `usize`) lowers to no padding.

2. The domain check runs where the arguments are typed, in every target's
   `StringTools.hex` arm, with the named error of the Contract section. The
   check and the lowerings ship in one change on all five targets.

3. The case conversions lower to the target's native spelling at the call
   site:

   | Call | TypeScript | Kotlin | Swift | Dart | Rust |
   | --- | --- | --- | --- | --- | --- |
   | `s.toLowerCase()` | `s.toLowerCase()` | `s.lowercase()` | `s.lowercased()` | `s.toLowerCase()` | `s.to_lowercase()` |
   | `s.toUpperCase()` | `s.toUpperCase()` | `s.uppercase()` | `s.uppercased()` | `s.toUpperCase()` | `s.to_uppercase()` |

4. Every lowering allocates at most the returned string. No helper,
   intermediate object, or per-character loop exists on any target: the
   hexadecimal form delegates to the target's radix machinery and the case
   conversions to the target's conversion.

## Samples and tests

- `samples/boring/StringConvOps.hx`: `hex` rows over `0`, `10`, `255`,
  `40959` (a CJK code point) with the digits argument absent, `0`, `4`, and
  a value wider than the requested padding; case rows over an ASCII word, a
  language tag, and a CJK string (conversion-invariant); each row compared
  against its ruled literal.
- `samples/tests/StringConvTests.hx` with `@:test` functions; both modules
  are entered in all eight generation hxml files (ts, kotlin, kotlin-f32,
  rust, rust-f32, swift, swift-f32, dart).
- `samples/tests/StringConvProbes.hx`: the named error as ordinary statics,
  following the `ValueRecordProbes` pattern, over a negative value and a
  negative digits argument.
- Tree assertions in `tests/ts/stringtools-conv.test.ts`: no generated tree
  contains a `StringTools.` reference; the Kotlin tree renders `.uppercase()`
  and `.lowercase()`; the Swift tree renders `String(v, radix: 16)`,
  `.uppercased()`, and `.lowercased()`; the Dart tree renders
  `.toRadixString(16)` and `.padLeft`; the Rust tree renders `{:X}` and
  `{:0w$X}` and `.to_lowercase()`; the TypeScript tree renders
  `.toString(16)`, `.toUpperCase()`, and `.padStart`.
- Coverage: `bun run gen:ts && bun run gen:kotlin && bun run gen:kotlin-f32 &&
  bun run gen:rust && bun run gen:rust-f32 && bun run gen:swift && bun run
  gen:swift-f32 && bun run gen:dart`, then `bun run test && bun run test:haxe
  && bun run test:kotlin && bun run test:rust && bun run test:swift && bun
  run test:dart` and the remaining steps of `bun run verify`; the consistency
  manager must report identical identifiers and verdicts across kotlin
  (baseline), haxe, ts, rust, swift, and dart.
- The mutation checks for this feature live in the dispatch task file and are
  part of the completion criteria.
