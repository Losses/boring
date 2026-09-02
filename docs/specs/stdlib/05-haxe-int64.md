# Standard library spec 05: haxe.Int64

## Scope

This specification defines `haxe.Int64` as the fixed-width 64-bit integer
capability of the translatable subset. It covers native target
representations, wrapping arithmetic, bitwise operations, shifts, word
construction and extraction, and conversions at named boundaries. The
capability is independent of `float-precision` and every wire float width.

## Haxe construct

The supported operations and conversions are:

- `Int64.make(high:Int, low:Int):Int64`
- `Int64.ofInt(value:Int):Int64`
- `Int64.toInt(value:Int64):Int`
- `Int64.getHigh(value:Int64):Int`
- `Int64.getLow(value:Int64):Int`
- the `high` and `low` read properties
- `+`, `-`, `&`, `|`, `^`, `~`, `<<`, `>>`, and `>>>`
- `==`, `!=`, `<`, `>`, `<=`, and `>=`

Addition and subtraction wrap modulo `2^64`. `>>` is arithmetic right shift.
`>>>` is logical right shift. Shift distances are `Int` values from 0 through
63. Construction joins the two input words by their 32-bit patterns. Word
extraction returns the corresponding signed 32-bit pattern.

Multiplication, division, remainder, decimal parsing, decimal
formatting, dynamic type tests, and implicit conversion to `Float` are outside
the initial capability. A later extension adds one of these operations with
its target lowering and cross-target tests in the same change.

In the Haxe typed AST, the type is `TAbstract` with module `haxe.Int64`.
Inline standard-library methods may expose their underlying expression shape;
the compiler recognizes the operation from typed type identity and resolved
field identity. Source text does not participate in recognition.

## Target mapping

| Haxe | TypeScript | Rust | Kotlin | Swift | Dart |
| --- | --- | --- | --- | --- | --- |
| `haxe.Int64` | `bigint` restricted to 64 bits | `i64` | `Long` | `Int64` | `int` restricted to 64 bits |

TypeScript applies `BigInt.asIntN(64, value)` at arithmetic and left-shift
results. Bitwise operations already preserve a signed infinite-width pattern,
so values crossing an Int64 result boundary are normalized to 64 bits. Shift
amounts convert from `number` to the target shift operand at the operation.

Rust uses `wrapping_add` and `wrapping_sub`. Logical right shift reinterprets
the left value as `u64`, shifts, and restores the `i64` bit pattern. Other
bitwise operations use native `i64` operators.

Kotlin uses `Long` arithmetic and bitwise members. `ushr` supplies logical
right shift. Int shift amounts stay `Int`.

Swift uses `Int64`, `&+`, and `&-`. Logical right shift reinterprets through
`UInt64(bitPattern:)` and restores the result through `Int64(bitPattern:)`.

Dart output runs on the Dart VM target. Every Int64 result is normalized with
`toSigned(64)`. Logical right shift reads the left value through
`toUnsigned(64)` before shifting and normalizes the result.

The four ordering operators compare the signed 64-bit pattern directly on
every target representation; no normalization precedes the comparison.

## Emission

Simple operations emit target-native expressions at the call site. Constant
`Int64.make` calls fold to native 64-bit literals when both words are integer
constants. Runtime helpers are reserved for target behavior that cannot be
expressed by one compact native expression. No wrapper class is emitted for
Int64 arithmetic.

`Int64.make`, `ofInt`, `toInt`, high/low extraction, and the supported
operators are recognized by typed AST field and type identity. Compiler code
does not search generated text or source spelling.

## V11 capability validation

`V11 Int64Misuse` validates operation identity and ignores source paths. Every module may use
the supported operations and conversions. Any other call or operator stops before
generation. In particular, generic string conversion, decimal formatting,
unsupported arithmetic, dynamic tests, and implicit mixed-width arithmetic
are rejected. Tests and algorithms receive no module-name exemption.

## Float boundary

`haxe.io.FPHelper` continues to carry binary64 bit patterns through high and
low words. Target-specific floating-point conversion may lower directly to
native bit conversion APIs. This optimized boundary and ordinary Int64
arithmetic share the same 64-bit observable patterns.

## Tests

One Haxe capability suite runs on every target. It covers construction,
high/low extraction, positive and negative values, carries across the low
word, wrapping at both limits, bitwise operations, arithmetic and logical
shifts at 0, 1, 31, 32, and 63, ordering at both limits and across zero, and
equality. The suite runs under each supported float configuration to prove independence from `float-precision`.
Generated source is compiled and executed by each target toolchain.
