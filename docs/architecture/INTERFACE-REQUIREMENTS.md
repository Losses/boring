# Architecture Contract

Classification (`PROBLEM-CLASSIFICATION.md`) explains "which category of failure belongs to whom"; this file explains
**what each side of an interface promises**, i.e.: what a position must deliver under what conditions.

## Contract 1: Destination is passed in by composition (class D)

**Rule**: A conversion site must receive the **destination** (target type), and must not infer it from compiler instance state.

**Current facts** (verified, candidate tree `SwiftExpr.hx` 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), its only write is at `:544`
  (`functionBody`, from the member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  and does **not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversion site(value, destination, fallback) -> text
where destination is provided by the composition this position belongs to:
  - member body                       -> the member's return type
  - lambda body                       -> the lambda's return type (f.t)
  - inline block / anonymous helper   -> the block's own result type (not the outer lambda's)
  - binding route                     -> the bound variable's type (v.t)
  - parameter route                   -> the callee's declared parameter type
```
**The last one is this session's lesson**: `blockExpression`'s block has its own destination;
treating it as the lambda's return contract would **inject a wrong conversion** (the P4 regression of `lambda-fix-xcheck`,
`mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: nil-merge's intermediate destination is provided by composition (class C boundary × class D destination)

**Original spec** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Implementation**: the third input of `prepare(operand, destinationType, override)`,
`destinationOptionalOverride` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner decides by the destination's own optionality (the default context of the three REFUSED rows)
- `override == true` ⇒ the composition declares "an optional intermediate result is accepted here" ⇒ that cell becomes a conversion
  (`MapOptionalMutableArrayView` `:200-202` etc.)

**Contract boundary**: `override` is the **composition's obligation**, not a property of the operand, and not an exemption.
The three REFUSED rows of `RECORD.md` are therefore constrained in the record to **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: warning counts toward acceptance (class F)

**Normative standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollary (drawn and written down this session, TCN-156)**:
- warning **counts**; **a baseline failure must be recorded, but not exempted** (`work-plan:417`).
- ⇒ **a suite must be running**: no suite collects ⇒ no count is produced ⇒ the standard cannot be satisfied,
  only bypassed. **CI currently runs no command that collects `tests/**`** (0 of `ci.yml`'s 26
  scripts), so the 50 `tests/ts` files and the two Swift fixtures produce no count.
- ⇒ the recorded form must be "**known baseline failure + explicit PIN**", and must **not** be named "zero-diagnostic satisfied":
  the owner ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is this contract's implementation.

## Contract 4: the acceptance criterion for generated output must be able to observe the property under test

**Rule**: an acceptance check must **fail when that property is broken**.

**Three counterexamples from this session** (the same gap, three causes):
| Item | Why it cannot be observed |
|---|---|
| `branchBoundary` fixture | the two branches are equal-length, the consumer only prints the length |
| missing return form | **`swiftc -typecheck` does not run SILGen, does not report "missing return"** |
| splicing-type fix | the generated tree's pre/post are byte-identical (cannot distinguish "not changed" from "changed correctly") |

**⇒ The concrete criteria** (`LAYERED-VERIFICATION.md` will expand):
1. The assertion must be stricter than "not broken": e.g. `1:1:present` rather than `1:present`
2. **The form stripped of `return` must use `swiftc -c`, not `-typecheck`**
3. A splicing-type change must use a **discriminating backend** (deliberately taking the wrong branch / deliberately returning the wrong value) to prove it would FAIL

## Contract 5: a fix must not change the behavior of other categories

**Implementation method**: after the fix, regenerate against the **full driver set** and do a whole-tree comparison; **byte-identical after path normalization**
is a necessary condition. All four committed fixes satisfy it (W1: 19 drivers, only 2 lines of difference and expected;
lambda: 19 drivers, diff is empty).

**Bound**: whole-tree identity **cannot** prove the fix is correct, only that **nothing else was touched**;
"generation succeeds", "typecheck passes", "runs correctly" are three different strengths and must be stated separately.

## Open

- **`switchExpression`'s destination**: condition 3 requires giving it an explicit destination parameter
  (binding route `v.t`, parameter route uses the callee parameter), `sw.t` only as fallback when there is no contract.
  The implementation seat is running (`out/switchexpr-destination`). **This seat must report "output unchanged" as
  a legitimate result**, and must not manufacture a behavior difference to make the change look necessary.
- **The single-return fast path** (`functionLiteralInner`) never applies the boundary conversion:
  the P1 probe of `lambda-fix-xcheck` is byte-identical in both trees and both fail. A residual gap.
- **Class J migration**'s contract is undefined.
