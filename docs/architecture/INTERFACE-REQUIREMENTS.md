# Architecture Contracts

Classification (`PROBLEM-CLASSIFICATION.md`) spells out "which failure class belongs to whom"; this document spells out
**what each side of the interface commits to**, i.e.: what a site must deliver under what conditions.

## Contract 1: Destination passed by composition (Class D)

**Rule**: A conversion site must receive a **destination** (target type) and must not infer it from compiler instance state.

**Current facts** (verified, candidate tree `SwiftExpr.hx` 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), sole write at `:544`
  (`functionBody`, from member `TFun` return), `:563` clears it.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  **does not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversion site(value, destination, fallback) -> text
where destination is supplied by the composition that owns the site:
  - member body      -> the member's return type
  - lambda body      -> the lambda's return type (f.t)
  - inline block / anonymous helper -> that block's own result type (not the outer lambda's)
  - binding route    -> the bound variable's type (v.t)
  - parameter route  -> the callee-declared parameter type
```
**The last item is this session's lesson**: a `blockExpression` block has its own destination;
treating it as the lambda's return contract **injects incorrect conversion** (P4 regression from `lambda-fix-xcheck`,
`mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: nil-merge intermediate destination supplied by composition (Class C boundary × Class D destination)

**Specification original** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Implementation**: the third input of `prepare(operand, destinationType, override)`
`destinationOptionalOverride` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ planner decides based on destination's own optionality (the default context for the three REFUSED rows)
- `override == true` ⇒ composition declares "optional intermediate result accepted here" ⇒ that cell becomes a conversion
  (`MapOptionalMutableArrayView` `:200-202` etc.)

**Contract boundary**: `override` is **composition's obligation**, not an operand property, nor an exemption.
`RECORD.md`'s three REFUSED rows are therefore scoped in the record as **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: warnings count toward acceptance (Class F)

**Binding standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollaries (established and recorded in this session, TCN-156)**:
- warnings **count**; **baseline failures must be recorded but not exempted** (`work-plan:417`).
- ⇒ **a suite must be running**: no suite collecting ⇒ no count produced ⇒ the standard cannot be met,
  only bypassed. **This gap is now wired** (`9f26e1ef`): `ci.yml` adds a `collected-suite`
  job, runs `bun run test` as entry point each time and reports the collected domain (303 files, 249 of which come from
  the generated tree `reference/ts/gen-tests`). This job blocks, no `continue-on-error`;
  baseline `1001 pass / 32 fail / 8 errors` recorded in `BASELINE-FAILURES.md`, not yet resolved.
- ⇒ the record form must be "**known baseline failure + explicit PIN**", **must not** be named "zero diagnostics satisfied":
  the owner judgment at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is this contract's implementation.

## Contract 4: acceptance criteria for generated output must observe the property under test

**Rule**: an acceptance check must **fail when that property is violated**.

**Three counterexamples from this session** (same gap, three causes):
| Item | Why unobservable |
|---|---|
| `branchBoundary` fixture | Both branches equal length, consumer only prints length |
| Missing return form | **`swiftc -typecheck` does not run SILGen, does not report "missing return"** |
| Splice-type fix | Generated tree pre/post byte-identical (cannot distinguish "not changed" from "changed correctly") |

**⇒ Concrete criteria** (`LAYERED-VERIFICATION.md` will expand):
1. Assertions must be stricter than "not broken": e.g. `1:1:present` not `1:present`
2. **form with `return` stripped must use `swiftc -c`, not `-typecheck`**
3. Splice-type modifications must use a **discriminative backend** (deliberately take the wrong branch / deliberately return the wrong value) to prove it would FAIL

## Contract 5: fixes must not alter behavior of other classes

**Implementation**: after a fix, regenerate with **full driver set** and diff the whole tree; **byte-identical after path normalization**
is a necessary condition. All four committed fixes satisfy this (W1: 19 drivers, only 2 lines difference and expected;
lambda: 19 drivers, diff empty).

**Limit**: whole-tree identicality **cannot** prove the fix is correct, only that **nothing else was affected**;
"generation success", "typecheck pass", "runs correctly" are three different strengths and must be stated separately.

## Open

- **destination for `switchExpression`**: condition 3 requires giving it an explicit destination parameter
  (binding route `v.t`, parameter route uses callee's parameter), `sw.t` only as fallback when no contract exists.
  Implementation seat is running (`out/switchexpr-destination`). **This seat must report "output unchanged" as
  a legitimate result** and must not fabricate behavioral differences to make the change appear necessary.
- **single-return fast path** (`functionLiteralInner`) never applied boundary conversion:
  the P1 probe from `lambda-fix-xcheck` is byte-identical across both trees and fails on both. This is a residual gap.
- **Class J migration** contracts are undefined.
