# Feature spec 44: shortest f32 record float text under the oracle

This specification amends the record printing rules so the Haxe oracle can
remain byte-comparable with the Kotlin reference when `float-precision=f32` is
selected.

## Scope

A record `Float` field currently reaches string concatenation directly in the
oracle. Java's `Float.toString` instead renders the binary32 value using its
shortest decimal text, so values such as `0.8` can disagree with the oracle's
binary64 expansion. This feature covers record fields and the `Float` operands
the stage-1 operand forms print; it does not alter ordinary arithmetic or other
string conversions.

## Ruling

1. The record field operand is routed through `std.FpText.shortest(read)` only
   when both `boring_oracle` and `float-precision=f32` are defined. This applies
   to `Float` and `Null<Float>` fields. A nullable field uses an explicit null
   comparison and prints `null` for the null state. Every other compilation,
   including all five generated targets, their f32 configurations, and stage 1
   without f32, remains byte-for-byte unchanged.
2. `FpText` searches one through nine significant digits. Each decimal
   candidate is parsed back and compared by `FPHelper.floatToI32`; the closest
   candidate is selected, with an even final digit for an exact tie. The result
   uses ordinary decimal placement, appends `.0` to whole numbers, and renders
   negative zero as `-0.0`. A value for which the search window finds no
   candidate (including extreme magnitudes or subnormals) keeps the platform
   text. Java's scientific notation conventions, such as `1.0E-4`, outside the
   ordinary window `[1e-3, 1e7)` are outside this specification. Fixtures remain
   inside that window.
3. The oracle runner defines both `boring_oracle` and `float-precision=f32`.
   Consumers may adopt the same defines independently.
4. `std.FpText` is referenced only by the gated oracle branch. Generated target
   compilations do not include it, and it is not registered in any
   `examples/*.hxml` file. It is portable Haxe, but need not belong to the
   translatable subset.
5. The same gate routes every `Float` operand printed by the stage-1 operand
   forms through `std.FpText.shortest(read)`: an array element of a record
   collection field (`Array<Float>` and `std.ReadOnlyArray<Float>`, including
   nested arrays) and a `Float` payload argument of a payload enum constructor.
   A `Null<Float>` element keeps the `Std.string` form of the pre-existing null
   branch. Ruling 1's unchanged-compilation guarantee applies to this routing
   verbatim.
