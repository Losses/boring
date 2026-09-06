# Feature spec 50: `Math.min`/`Math.max` NaN semantics

## Scope

This specification rules the two-argument `Math.min(a, b)` and
`Math.max(a, b)` calls for `Float` and `Int` operands on all five generated
targets: TypeScript, Kotlin, Swift, Dart, and Rust. Integer operands are
widened to the target's real type at the call site under the existing numeric
tower contract (feature spec 07); this specification rules the resulting
floating-point operation, including NaN, infinities, and signed zero.

## Current verification

The current five Math-member dispatch sites were located by grepping each
`*Expr.hx` for the Math static call lowering. The exact anchors and current
forms at commit `4b1fec9` are:

| Target | Dispatch anchor | Current emitted form |
| --- | --- | --- |
| TypeScript | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:1786` (the general static-call path; Math has no dedicated min/max arm) and `:1422` (static reference) | `Math.min(a, b)` or `Math.max(a, b)` through the native JavaScript Math operation. |
| Kotlin | `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:2449` (the general static-call path; Math has no dedicated min/max arm) and `:2077` (static reference) | `Math.min(a, b)`/`Math.max(a, b)` (or `kotlin.math.min`/`max` in the f32 configuration), using the Kotlin/Java floating-point operation. |
| Swift | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2087` | Bare Swift `min(a, b)`/`max(a, b)` after `mathFloatArg` widening. |
| Dart | `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2019` | `math.min(a, b)`/`math.max(a, b)` after `mathFloatArg` widening. |
| Rust | `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:4775` (with `:3880` providing the static reference) | `f64::min(a, b)`/`f64::max(a, b)` (or `f32` under the precision switch), a bare native call whose NaN behavior returns the other operand and therefore currently disagrees with the oracle. |

The TypeScript, Kotlin, Swift, and Dart native forms propagate NaN in the
required way in the supported floating-point domain. Rust's `f32::min`,
`f32::max`, `f64::min`, and `f64::max` are non-conforming despite their Haxe-
like names: their specified NaN behavior is the known existing cross-target
defect.

## Semantics ruling

1. Evaluation is left-to-right. If either operand is NaN, the result is NaN;
   if both operands are NaN, the result is also NaN. This rule is independent
   of operand order and applies after integer widening.
2. If neither operand is NaN, the result is the ordered minimum or maximum,
   with signed zero selected exactly as in the Haxe/JavaScript oracle:

   | Operation | First operand | Second operand | Required result |
   | --- | --- | --- | --- |
   | `min` | `-0` | `+0` | `-0` |
   | `min` | `+0` | `-0` | `-0` |
   | `max` | `-0` | `+0` | `+0` |
   | `max` | `+0` | `-0` | `+0` |

3. The infinity and signed-zero edges are contract cases. For each operation
   and operand order, the required results are:

   | Operation | First operand | Second operand | Required result |
   | --- | --- | --- | --- |
   | `min` | `-0` | `-∞` | `-∞` |
   | `min` | `-∞` | `-0` | `-∞` |
   | `min` | `-0` | `+∞` | `-0` |
   | `min` | `+∞` | `-0` | `-0` |
   | `min` | `+0` | `-∞` | `-∞` |
   | `min` | `-∞` | `+0` | `-∞` |
   | `min` | `+0` | `+∞` | `+0` |
   | `min` | `+∞` | `+0` | `+0` |
   | `max` | `-0` | `-∞` | `-0` |
   | `max` | `-∞` | `-0` | `-0` |
   | `max` | `-0` | `+∞` | `+∞` |
   | `max` | `+∞` | `-0` | `+∞` |
   | `max` | `+0` | `-∞` | `+0` |
   | `max` | `-∞` | `+0` | `+0` |
   | `max` | `+0` | `+∞` | `+∞` |
   | `max` | `+∞` | `+0` | `+∞` |
   | `min` | `+∞` | `-∞` | `-∞` |
   | `min` | `-∞` | `+∞` | `-∞` |
   | `max` | `+∞` | `-∞` | `+∞` |
   | `max` | `-∞` | `+∞` | `+∞` |

   In addition, `min(NaN, +∞)`, `min(+∞, NaN)`, `max(NaN, +∞)`, and
   `max(+∞, NaN)` are NaN; the same four cases with `-∞` are NaN as well.
   These cases pin both NaN propagation and the infinity boundary.

## Per-target products

The five emitters must produce behavior equivalent to the ruling above,
including signed zero, for both f64 and the f32 precision configuration.

| Target | Required product |
| --- | --- |
| TypeScript | Retain the native `Math.min`/`Math.max` calls. JavaScript's Math oracle supplies NaN propagation and signed-zero selection. |
| Kotlin | Retain the target's `Math.min`/`Math.max` or `kotlin.math.min`/`max` mapping only where the selected overload is verified to match the oracle, including signed zero. An unverified overload requires an explicit NaN-aware comparison form so the contract remains unchanged. |
| Swift | Retain native `min`/`max` only as a verified floating-point lowering with the oracle's NaN and signed-zero behavior; otherwise use an explicit NaN-aware branch. The `Float`/`Double` argument widening remains mandatory. |
| Dart | Retain `dart:math` `math.min`/`math.max` only as a verified floating-point lowering with the oracle's NaN and signed-zero behavior; otherwise use an explicit NaN-aware branch. |
| Rust | Replace the current bare `real::min`/`real::max` call with an implementation that first detects either NaN and returns NaN, then applies an ordered operation that preserves the signed-zero table. An explicit NaN-check branch is permitted and preferred when it makes the contract visible. The implementation must not depend on `f32::min`, `f32::max`, `f64::min`, or `f64::max` returning NaN, because those functions return the other operand for a NaN input. |

No target may evaluate an operand more than once while implementing the
explicit form. Integer arguments must be widened before the selected native
operation or branch; target-specific integer shortcuts are outside this
contract.

## Fixtures

The implementation sample class is `samples/boring/MathNaNOps.hx`, and the
registered test class is `samples/tests/MathNaNOpsTests.hx`. The class is
entered in every target generation and test registration list, including the
f32 variants. Its fixture matrix contains both `min` and `max` for every
pair in this set: `(NaN, finite)`, `(finite, NaN)`, `(NaN, NaN)`, an ordered
finite pair in both orders, `(-∞, finite)`, `(+∞, finite)`, `(+∞, -∞)`,
`(+0, -0)`, and `(-0, +0)`. The infinity/zero edge rows in the semantics
table are also required, as are integer calls that exercise widening.

Each target's generated text is asserted in addition to running the fixture:

- TypeScript must contain native `Math.min`/`Math.max` forms.
- Kotlin must contain the selected `Math`/`kotlin.math` forms for the active
  precision and no accidental integer overload.
- Swift must contain the native `min`/`max` form or the explicit oracle branch
  selected by the implementation.
- Dart must contain `math.min`/`math.max` or the explicit oracle branch.
- Rust must contain the NaN-checking form (and must not contain a bare
  `f32::min`, `f32::max`, `f64::min`, or `f64::max` lowering for these calls).

`MathNaNOpsTests` asserts NaN status, finite values, infinities, and the sign
bit of every signed-zero result. The consistency suite runs the same rows
through all five targets and requires identical observable results.

## Non-goals

- This does not change any Math member other than `min` and `max`.
- `floor`, `ceil`, `sqrt`, `isNaN`, and `isFinite` with Int variables are a
  separate proposal.
- This does not introduce a runtime abstraction layer that hides native
  target operations.
- This does not amend the existing Int widening contract.

## Performance note

The cost of an explicit NaN-check branch on the hot path is accepted:
semantic correctness has priority because the Haxe/JavaScript oracle behavior
is not negotiable. Native forms remain preferred on targets only when their
NaN and signed-zero behavior is proven equivalent.
