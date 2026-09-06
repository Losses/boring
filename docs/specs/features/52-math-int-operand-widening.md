# Feature spec 52: Math Int operand widening

## Scope

This specification rules calls to `Math.floor`, `Math.ceil`, `Math.sqrt`,
`Math.isNaN`, and `Math.isFinite` when the argument is an `Int` variable.
The Haxe signature baseline is:

```text
floor:Float->Int
ceil:Float->Int
sqrt:Float->Float
isNaN:Float->Bool
isFinite:Float->Bool
```

The rule applies to TypeScript, Kotlin, Rust, Swift, and Dart. It covers the
f64 path and the corresponding f32 path where the target supports that
configuration. Integer operands must be widened through the numeric tower of
feature spec 07 before the floating-point operation.

## Current verification

| Target | Current verification anchor | Current form |
| --- | --- | --- |
| TypeScript | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:1776-1779` | `Number.isNaN(...)` and `Number.isFinite(...)` are special-cased; native Math calls otherwise receive the expression directly. |
| Kotlin | `packages/compiler/reflaxe/kotlin/kotlincompiler/KotlinExpr.hx:2497-2508` | Predicates call members on the argument; floor and ceil use `kotlin.math` and `.toInt()`; sqrt has a `toDouble()` path. |
| Rust | `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:4760-4775` | Predicates call members on the argument and floor/ceil use the target real operation without the required Int widening. |
| Swift | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx:2087-2102` | Predicates and rounding members are applied directly to the argument; floor and ceil currently form `Int32((x).rounded(.down/.up))`. |
| Dart | `packages/compiler/reflaxe/dart/dartcompiler/DartExpr.hx:2004-2023` | Floor and ceil use `(x).floor()` and `(x).ceil()`; sqrt uses `math.sqrt(x)`; predicates use direct members. |
| Numeric tower | `docs/specs/features/07-numeric-tower.md:168-172` | Haxe `Int` is the integer primitive and Haxe `Float` is the real primitive; target widening and explicit conversion are required. |

The probe evidence in `/tmp/dispatch-state/boring-probe-gap47-r1.report.md:70-113`
records generation for a variable `x:Int`, oracle inputs `4`, `-4`, and `0`,
and the current target forms. The report's oracle output is at lines 48-52.
Its typecheck results and known defects are at lines 114-136. Rust's generated
Int shape was `u32` at the report's lines 137-145; the independent Int mapping
problem is not decided by this specification.

## Semantics ruling

1. Before each of the five calls, the argument must be widened through the
   numeric tower to the target floating-point type. The operation must then be
   invoked in that floating-point domain. The result must converge to the Haxe
   signature: floor and ceil return an integer, sqrt returns a floating-point
   value, and both predicates return `Bool`.

2. TypeScript must use the single `number` numeric domain. `Math.floor(x)`,
   `Math.ceil(x)`, and `Math.sqrt(x)` are valid direct forms, and the predicate
   forms must remain `Number.isNaN(x)` and `Number.isFinite(x)`.

3. Kotlin must use these f64 forms for an `Int` variable:
   `floor(x.toDouble()).toInt()`, `ceil(x.toDouble()).toInt()`,
   `sqrt(x.toDouble())`, `x.toDouble().isNaN()`, and
   `x.toDouble().isFinite()`. The corresponding f32 configuration must use
   its configured real type. The current `kotlin.math.floor(x)` and
   `.toInt()` shape is a known defect: it has both an Int/Double argument
   mismatch and a result shape that does not match a floating-point result
   consumer, and must be corrected.

4. Rust must use `(x as f64).floor() as i32` and
   `(x as f64).ceil() as i32` in the default real configuration,
   `(x as f64).sqrt()` for sqrt, and widened-float predicate calls. Under an
   f32 configuration the corresponding path must use f32. The existing
   mapping of Haxe `Int` to `u32`, including its inability to represent
   negative values, is an independent feature-spec-07 issue. This
   specification requires the widening at the operation boundary but does not
   rule that mapping itself.

5. Swift must use `Int32((Double(x)).rounded(.down))`,
   `Int32((Double(x)).rounded(.up))`, `Double(x).squareRoot()`, and predicate
   checks on `Double(x)`. The f32 configuration must use the configured real
   type where applicable. Direct Int32 member calls are not conforming.

6. Dart must use `(x).floor()` and `(x).ceil()` for floor and ceil, because
   Dart `num` methods return `int` and naturally converge to the Haxe result.
   Dart has no `(x).sqrt()` form; sqrt must use `math.sqrt(x.toDouble())`.
   Predicates must inspect the widened value, such as
   `x.toDouble().isNaN` and `x.toDouble().isFinite`. The observed
   `math.sqrt(x)` form is a known unexpanded-Int defect and must be corrected.

7. `isNaN` and `isFinite` are mathematically constant for an integer argument:
   an integer is neither NaN nor infinite. Nevertheless, the compiler must
   widen and call the predicate; folding, rejecting, or substituting
   a target-specific constant. This keeps the generated call shape consistent
   across all five targets.

## Contract examples

For each input, every target must preserve the following call/result shape;
only the target syntax in the product column differs. These three input rows
are the oracle input set from `/tmp/dispatch-state/boring-probe-gap47-r1.report.md:72`.

| `x` | Required floor / ceil | Required sqrt | Required predicates |
| --- | --- | --- | --- |
| `4` | floor `4`, ceil `4` | `2` in the target Float domain | `false`, `true` |
| `-4` | floor `-4`, ceil `-4` | `2` in the target Float domain | `false`, `true` |
| `0` | floor `0`, ceil `0` | `0` in the target Float domain | `false`, `true` |

| Target | Required expression family for each oracle row |
| --- | --- |
| TypeScript | `Math.floor(x)`, `Math.ceil(x)`, `Math.sqrt(x)`, `Number.isNaN(x)`, `Number.isFinite(x)` |
| Kotlin | `floor(x.toDouble()).toInt()`, `ceil(x.toDouble()).toInt()`, `sqrt(x.toDouble())`, widened member predicates |
| Rust | `(x as f64).floor() as i32`, `(x as f64).ceil() as i32`, widened sqrt and predicates; f32 analogues under f32 |
| Swift | `Int32((Double(x)).rounded(.down))`, `.rounded(.up)`, `Double(x).squareRoot()`, widened predicates |
| Dart | `(x).floor()`, `(x).ceil()`, `math.sqrt(x.toDouble())`, widened predicates |

The numeric oracle rows are reported by the probe at
`/tmp/dispatch-state/boring-probe-gap47-r1.report.md:48-52`; the required
per-target direction is the input recorded at lines 146-153 of that report.

## Non-goals

This specification does not decide the Rust representation chosen for Haxe
`Int`, does not alter other Math members, and does not introduce a runtime
abstraction for floating-point operations.
