# Feature spec 54: StringBuf unpaired-surrogate rulings

## Scope

This specification rules the mutation contract for `StringBuf.add` and
`StringBuf.addChar` when UTF-16 surrogate units are involved. It covers the
shared mutation recognition, the four pairing faults, the `UnpairedSurrogate`
payload, and the capability-dependent Rust lowering. It does not prescribe
target syntax or replace the target-specific buffer and exception renderers.

## Current verification

| Target or mechanism | Current verification anchor | Current form |
| --- | --- | --- |
| Shared recognition | `packages/compiler/PolicyQueries.hx:525` | `stringBufMutationParts` identifies the mutation name and subject; targets delegate to it. |
| Dart | `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2985-3020` | Reads the trailing unit, checks both operations, and mutates a UTF-16-unit list with `addAll` or `add`. |
| TypeScript | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:2576-2607` | Applies the same pairing checks before `+=` or `String.fromCharCode`. |
| Kotlin | `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:666-700` | Appends through `StringBuilder` and constructs the payload enum on failure. |
| Swift | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:3166-3200` | Uses UTF-16-oriented tail checks and throws the target `UStringException` form. |
| Rust | `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:857-903` | Requires `isFallible`, returns `Err` on a fault, and currently folds the string trail-start case for well-formed `&str`. |
| Fault payload | `samples/std/UStringFault.hx:1-11` and `samples/std/UStringException.hx:8-18` | `UnpairedSurrogate(unit)` is carried by `UStringException` and is described with the offending unit. |

## Semantics ruling

1. Haxe source behavior is target-dependent at the handbook level for
   ill-formed UTF-16. For this compiler subset, `StringBuf.add` and
   `StringBuf.addChar` have one contract: every checked mutation must preserve
   surrogate pairing at the boundary, and a rejected mutation raises the
   `std.UStringException` exception family with an `UnpairedSurrogate(unit)`
   payload. This ruling is semantic; the target spelling remains local to the
   renderer. The existing target checks are at Dart `:2985-3020` and TypeScript
   `:2576-2607`.

2. A mutation faults under exactly these boundary conditions. First, the
   current buffer tail is a lead surrogate and `add` is empty or starts with a
   non-trail unit. Second, `addChar` supplies a trail surrogate while the
   current tail is not a lead surrogate. Third, `addChar` supplies a
   non-trail unit while the current tail is a lead surrogate. The final
   successful operation is the complementary pairing case: a lead tail may be
   followed by a trail start, and a trail character may follow a lead tail.
   The Haxe-side payload precedent is `UStringFault.UnpairedSurrogate(unit)`
   at `samples/std/UStringFault.hx:9-11`; the operation predicates are visible
   at Dart `:2998-3018` and TypeScript `:2588-2605`.

3. The fault unit is the unit that makes the boundary invalid: the held tail
   for an invalid `add` boundary or a non-trail continuation, and the supplied
   trail character when it has no lead predecessor. The exception must be
   constructed through the existing payload-enum shape. An unrelated string or
   target-native error is not conforming. `UStringException` stores the
   payload in `fault` at `samples/std/UStringException.hx:8-12`, while target
   constructors are retained in Dart `:2972-2982`, Swift `:3160-3163`, and
   Rust `:866-883`.

4. Rust has no ordinary throw path. When the enclosing operation has the
   `isFallible` capability, `Err` carrying the same
   `UnpairedSurrogate { unit }` payload is the equivalent observable fault;
   when it does not, the subset must reject the operation. Silently weakening the
   contract is not conforming. The capability gate and error path are at
   `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:862-871`.
   Because Rust `&str` is well-formed, its `add` input cannot begin with an
   unpaired trail UTF-16 unit, so the trail-start branch may be folded only
   when that capability and representation fact are explicitly part of the
   mutation decision. It must not be folded by target-name hardcoding. The
   current fold is visible at Rust `:874-880`.

5. A future shared decision API may reserve the following signature:
   `PolicyQueries.stringBufMutationDecision(kind, tailClass, argClass)`.
   It returns the fault decision and operation category only. Tail reads,
   buffer mutation, exception construction, imports, and Rust `Err` rendering
   remain target responsibilities. The current shared recognition boundary is
   `packages/compiler/PolicyQueries.hx:525`.

## Contract examples

| Operation and boundary | Required result |
| --- | --- |
| Empty buffer, `add("x")` | Append successfully. |
| Tail lead, `add("\\uDC00...")` | Append successfully because the trail start pairs with the tail. |
| Tail lead, `add("")` | Raise `UnpairedSurrogate` for the held lead. |
| Tail lead, `add("x")` | Raise `UnpairedSurrogate` for the held lead. |
| Non-lead tail, `addChar(0xDC00)` | Raise `UnpairedSurrogate` for the supplied trail unit. |
| Lead tail, `addChar(0x61)` | Raise `UnpairedSurrogate` for the held lead. |
| Lead tail, `addChar(0xDC00)` | Append successfully. |
| Rust mutation outside a fallible region | Reject the subset input; do not discard the check. |

## Non-goals

This specification does not define string decoding APIs, change the UTF-16
representation of a target buffer, prescribe target syntax, or add a general
exception runtime. It does not require implementation of the future shared
decision signature.
