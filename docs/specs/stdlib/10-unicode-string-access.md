# Standard library spec 10: std.UString

## Scope

This specification provides the general-domain string access that
`docs/specs/features/08-strings-and-unicode.md` requires. The feature
specification bounds the storage-dependent operations (`length`,
`charCodeAt`, and the rest) to ASCII-verified strings, where UTF-16 code
units, UTF-8 bytes, and characters coincide. Every other string reaches
this module. The module exercises principles 1 through 3 of
`docs/specs/design-principles.md`: semantics defined over content,
restriction arriving with its provision, and cost tiers at their floor.

## Contract

`std.UString` is a module of static functions over the character sequence
of a string. A character is one Unicode code point. The input domain is
valid Unicode scalar sequences, the same domain
`docs/specs/stdlib/07-sorted-keyed-tables.md` states for string keys.

| Function | Contract |
| --- | --- |
| `count(s:String):Int` | The number of characters. |
| `at(s:String, index:Int):Null<Int>` | The code point at character position `index`, counting from 0; `null` when `index` is negative or at least `count(s)`. The null return on a miss matches `String.charCodeAt` and `std.SortedMap.get`. |
| `slice(s:String, from:Int, to:Int):String` | The characters from position `from` inclusive to `to` exclusive. `from` clamps upward to 0, `to` clamps downward to `count(s)`, and `from >= to` yields the empty string. |
| `toCodePoints(s:String):Array<Int>` | One array element per character, in order; the code-point-as-integer ruling of features/08 covers the element domain. |
| `fromCodePoints(codes:Array<Int>):String` | The string whose characters are `codes` in order. An element outside the Unicode scalar range throws `UStringException(InvalidCodePoint(element))`. |
| `fromCodePoint(code:Int):String` | The one-character string of `code`. An argument outside the Unicode scalar range (0..0x10FFFF excluding 0xD800..0xDFFF) throws `UStringException(InvalidCodePoint(code))`. |

The thrown exception is the enum-carrying form of
`docs/specs/features/06-errors-and-results.md`: the module declares
`enum UStringFault { InvalidCodePoint(code:Int); }` and
`UStringException extends haxe.Exception` carrying it. An out-of-range
`at` is a query miss and returns null; an invalid construction argument
is a programmer error and throws.

## Judgment

Three shapes were considered for closing the divergence the feature
specification bounds:

1. **Rust emulates UTF-16 code-unit operations.** Every indexed access
   walks from the start, an index loop over a string costs quadratic
   time, and the addressing unit stays the storage unit of one platform.
   Fails principles 1 and 3.
2. **Redefine the native operations as character semantics on every
   target.** Every `length`, including the ASCII wire-codec loops,
   becomes a walk, discarding constant-time answers that exist on all
   targets. Fails principle 3 at its first tier.
3. **A code-point-addressed std module beside the bounded native tier**
   (this specification). ASCII keeps constant-time native operations;
   everything else gains functions whose results are identical by
   construction, because a character count is the same number whatever
   stores the string.

Cost floors, recorded per principle 3:

| Usage pattern | Operation | Cost |
| --- | --- | --- |
| Known-ASCII count or scan | native `length`, native indexing | constant time per query, every target |
| One-shot character query | `count`, `at` | one linear pass, no allocation |
| One-shot substring | `slice` | one walk plus the result string |
| Repeated positional access | `toCodePoints`, then array indexing | one pass plus the output array, then constant time |

Counting characters on variable-width storage must examine every
character at least once, so the one-pass `count` sits at the floor; the
same holds for the decode-once form, whose output is the array itself.
No target emulates another platform's storage on any tier: Rust iterates
`chars()`, the UTF-16 platforms walk code units, and each tier costs the
same order on every target.

## Haxe declarations and routing

`samples/std/UString.hx` declares the module following the `SortedMap`
pattern of `docs/specs/stdlib/06-std-modules.md`: the extern class with
the six static functions, the fault enum, and the exception wrapper.
References route through the target import tables into the runtime
package exactly as `std.Console` routes; the `std.` namespace reaches no
output. The stage-one oracle follows the wrapper binding of
`docs/specs/stdlib/08-string-buffer.md`: the runner compiles a haxe
implementation of the module outside the guarded paths, and the bootstrap
binds it to `globalThis.std.UString`. The haxe implementation walks code
units with the platform's own `charCodeAt`; the interception guards
sample source, and the provided standard library sits outside the guard.

## Per-platform shapes

- Rust: `reference/rust-gen/src/runtime/ustring.rs`. `count` is
  `chars().count()`. `at` is `chars().nth(index)` mapped through the
  `Null<Int>` representation of features/04. `slice` walks to the
  boundaries and collects the substring. `toCodePoints` maps `chars()` to
  `u32`. `fromCodePoint` and `fromCodePoints` validate through
  `char::from_u32` and raise the lowered fault on `None`.
- TypeScript: the runtime package gains the six functions as
  surrogate-aware unit walks reading `codePointAt` and advancing one or
  two units per character.
- Kotlin: the `KotlinRuntime` shims gain the same six functions in the
  same walk shape, written over `charAt` unit reads, so the shim carries
  no JVM-specific string API.
- Stage-one haxe: the wrapper of the routing section, one implementation
  of the same walk.

## Samples and tests

A sample in `samples/boring/` exercises the module across three content
classes, pure ASCII, BMP CJK, and supplementary CJK: `count`; `at` hits
and the out-of-range null; `slice` clamping at both ends and the empty
mid-string case; `toCodePoints` values; the `fromCodePoints` round trip;
and `fromCodePoint` construction, with the invalid-code throw asserted
as an expected fault under the testing standard. The four-side
consistency run compares jsonl output. `tests/ts/` tree assertions pin
the native forms (`chars().count()` on Rust, `codePointAt` walks on
TypeScript) and assert that no walk appears where the ASCII tier serves
the sample.

The acceptance criterion of the features/08 replacement is this module's
existence proof: a program that counts, scans, slices, and rebuilds CJK
strings compiles under `V18` and produces identical results on the four
sides.

## Rulings restated

`V18` remains the enforcement point that features/08 names. This module
is the provided general path. `StringTools.fastCodeAt` and
`StringTools.fromCharCode` stay banned, with their replacements here.
