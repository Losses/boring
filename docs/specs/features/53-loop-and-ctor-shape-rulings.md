# Feature spec 53: Loop and constructor shape rulings

## Scope

This specification rules four translation shapes observed in the five target
compilers: Rust constructor ownership, do-while loops, nullable loop counters,
and wrapped interval bounds. It is a shape contract and does not request changes to
source samples, tests, or compiler implementation in this document.

## Current verification

| Mechanism | Current verification anchor | Current form |
| --- | --- | --- |
| Rust constructor calls | `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:5021` (`newExpr` routes constructor calls), with argument policy at `:5156` (`ctorCallArgs`) | `TNew` uses ordinary constructor arguments; a non-`Copy` value is not implicitly cloned. |
| Do-while gate | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:475`, and equivalent target emitters at Kotlin `:519`, Rust `:718`, Swift `:468`, and Dart `:698` | `TWhile(_, _, false)` is rejected with `do-while has no lowering in the subset`. |
| Interval capabilities | `packages/compiler/reflaxe/ts/tscompiler/TsExpr.hx:803-806` and Kotlin `:857-860` | Interval recognition is capability-driven and separate from the emitter's do-while gate. |
| Nullable counter | TypeScript `TsExpr.hx:818-837`, Kotlin `KotlinExpr.hx:872-887`, and Rust `RustExpr.hx:1488-1503` | Interval matching is attempted, but the nullable-counter probe remains a `while`; Kotlin emits `i!!` in the condition. |
| Shared wrapper predicate | `packages/compiler/ExpressionPredicates.hx:8-12` | `stripWrap` recursively removes parentheses, casts, and metadata. |

The evidence is from `/tmp/dispatch-state/boring-probe-gap6iv-r2.report.md`:
regeneration results are at lines 38-41; the oracle outputs are at lines 20-26.
The Rust generated move example and constructor are quoted at lines 45-63,
with rustc E0382 at lines 65-83. Do-while rejection diagnostics are at
lines 152-156. Nullable generated forms are at lines 199-220, and the wrapped
bound outputs are at lines 242-280. The report's specification-track input is
at lines 407-414.

## Semantics ruling

1. A Rust constructor argument for a non-`Copy` value must retain ordinary Rust
   move semantics. The generated constructor call must not add an implicit
   clone, borrow, or ownership-preserving wrapper because the source
   variable is used later. A later use must be rejected by the normal Rust
   ownership rule. In the probe, `WrapHolder::new(b1)` followed by use of `b1`
   must produce rustc E0382; a moved value not used afterward, such as `b2`,
   is valid. The constructor parameter remains owning.

2. A do-while loop is an independent iteration mechanism and must not be
   treated as a pre-test `while` loop or as an interval loop. The five-target
   subset gate must reject do-while input consistently until a conforming
   lowering exists. Any future lowering must preserve the oracle trip counts
   `[1,1,1]` for the three do-while cases in the probe; the
   pre-test while counts remain `[0,0,1]`. No zero-trip substitution is permitted.

3. A nullable counter initialized as `Null<Int>` must be excluded from interval
   lowering unless initialization and null behavior are explicitly modeled.
   The required shape is a retained `while` with a nullable counter. The oracle
   result for the probe is `[0,3]`: the null-counter case contributes `0` and
   the initialized counter contributes `3`. A naive interval-for rewrite must
   not be used because it can change this observable behavior. Kotlin's
   condition may retain the observed `i!!` unwrapping; Rust and TypeScript may
   retain their target null representations.

4. Parentheses, casts, and metadata around an interval-bound subject must be
   removed recursively by the shared `ExpressionPredicates.stripWrap`
   predicate. A bare bound, `cast(n, Int)`, and `(n:Int)` must therefore be
   treated as equivalent. This equivalence must not extend to algebraic
   expressions: `n + 1` is a distinct boundary and must remain distinct. The
   oracle output `[3,3,3,4]` is the contract evidence for the three equivalent
   forms and the arithmetic boundary.

## Contract examples

| Shape | Required behavior |
| --- | --- |
| `new WrapHolder(b1)` where `b1` is non-`Copy` and used later | Move `b1`; normal rustc E0382 is expected. |
| Do-while cases with starts `5`, `6`, and `4` and bound `5` | Reject in the current subset; any future product preserves `[1,1,1]`. |
| `var i:Null<Int> = null; while (i < n)` | Retain `while` and nullable semantics; oracle contribution is `0`. |
| `while (j < n)` with initialized `j` | It remains behaviorally distinct from the nullable case; oracle contribution is `3`. |
| Bounds `n`, `cast(n, Int)`, `(n:Int)`, and `n + 1` | First three are wrapper-equivalent; the last is algebraically distinct; oracle is `[3,3,3,4]`. |

These oracle values and generated forms come from
`/tmp/dispatch-state/boring-probe-gap6iv-r2.report.md:20-26` and
`:242-280`. The ownership diagnostic is from the same report at `:65-83`.

## Non-goals

This specification does not choose a Rust integer mapping, add do-while
support, or broaden interval recognition to arithmetic expressions.
