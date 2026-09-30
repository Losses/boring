# Architecture Contract

Classification (`PROBLEM-CLASSIFICATION.md`) makes clear "which type of failure belongs to whom"; this file makes clear
**what the two ends of an interface each promise**, that is: under what conditions a given location must produce what.

## Contract 1: The destination is passed in by composition (category D)

**Rule**: a conversion site must be given the **destination** (target type), and must not infer it from compiler instance state.

**Current facts** (verified; candidate tree `SwiftExpr.hx`, 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`), its only write is at `:544`
  (`functionBody`, from the member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  and **does not rebind** `currentReturnType`.
- The correct value inside a lambda is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversion-site(value, destination, fallback) -> text
where destination is provided by the composition that the location belongs to:
  - member body                   -> the member's return type
  - lambda body                   -> the lambda's return type (f.t)
  - inline block/anonymous helper -> that block's own result type (not the outer lambda's)
  - binding route                 -> the type of the bound variable (v.t)
  - argument route                -> the parameter type declared by the callee
```
**The last item is this session's lesson**: the block of `blockExpression` has its own destination;
treating it as the lambda's return contract **injects a wrong conversion** (the P4 regression of `lambda-fix-xcheck`,
`mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: The intermediate destination of a nil-merge is provided by composition (category C boundary × category D destination)

**Spec source text** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Implementation**: the third input of `prepare(operand, destinationType, override)`
`destinationOptionalOverride` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner rules by the destination's own optionality (the default context of the three REFUSED rows)
- `override == true` ⇒ the composition declares "an optional intermediate result is accepted here" ⇒ that cell becomes a conversion
  (`MapOptionalMutableArrayView` `:200-202`, etc.)

**Contract boundary**: `override` is **the composition's obligation**, not a property of the operand, nor an exemption.
The three REFUSED rows of `RECORD.md` are therefore qualified in the record as **PLANNER-CELL ONLY**
(CORRECTION 13).

## Contract 3: warnings count toward acceptance (category F)

**Binding standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollary (already drawn and written down this session, TCN-156)**:
- warnings **count**; **baseline failures must be recorded, but not exempted** (`work-plan:417`).
- ⇒ **a suite must be running**: no suite collecting ⇒ no count produced ⇒ the standard cannot be satisfied,
  only bypassed. **That gap has been wired up** (`9f26e1ef`): `ci.yml` adds a `collected-suite`
  job that runs `bun run test` at the entry point on every run and reports the collected scope (303 files, of which 249 come from
  the generated tree `reference/ts/gen-tests`). That job blocks, with no `continue-on-error`;
  the baseline `1001 pass / 32 fail / 8 errors` is recorded in `BASELINE-FAILURES.md`, not yet cleared.
- ⇒ the shape of the record must be "**known baseline failures + explicit PIN**", and must **not** be named "zero-diagnostic satisfaction":
  the owner ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is this contract's implementation.

**Supplement (`t-muo92xms-s28t` ruling, `1a486ebd`; see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`):
"which tool to use" and "which category of diagnostics can be seen" must be explained separately.**
The main clause of `:78` is universal ("on every target"), but when enumerating tools it writes only *"the Swift type-checker"*.
That narrowing leaves a hole: **`swiftc -typecheck` does not run SILGen, and reports 0 even in the baseline state**,
so for `Gap.swift:117`'s `will never be executed` it **can neither confirm nor refute**;
only `-c` (including `-whole-module-optimization`) and `-o` can actually see it.
⇒ **Ruling: build-phase diagnostics count toward `:78/:80`**. If, taken literally, only the "type checker" is recognized, "zero warnings" degenerates into
an **empty criterion** (all real emitter defects pass silently, while the downstream CI that compiles binaries will still hit it).
**Counting discipline**: count by the `file:line:col: severity` **shape**, do not use `grep -c 'warning:'`
— Swift also prints caret/context lines, which would count 1 as 2 (PIT-336).
**Same-category generalization**: for each target, ask whether the existing command **cannot see** the diagnostics it can report —
one same-family example this session is that `cargo check` and `cargo build` have different warning surfaces.

## Contract 4: The acceptance criterion for generated output must be able to observe the property under test

**Rule**: an acceptance check must **fail when that property is broken**.

**Three counterexamples this session** (the same gap, three causes):
| Item | Why it is not observable |
|---|---|
| `branchBoundary` fixture | The two branches are equal length; the consumer only prints the length |
| Missing-return form | **`swiftc -typecheck` does not run SILGen, and does not report "missing return"** |
| Splice-type fix | The generated tree pre/post is byte-identical (cannot distinguish "unchanged" from "fixed correctly") |

**⇒ Implemented criteria** (`LAYERED-VERIFICATION.md` will expand on this):
1. The assertion must be stricter than "not broken": for example `1:1:present` rather than `1:present`
2. **The form that strips `return` must use `swiftc -c`, not `-typecheck`**
3. Splice-type modifications must use a **discriminating backend** (deliberately take the wrong branch / deliberately return the wrong value) to prove it will FAIL

## Contract 5: A fix must not change other categories' behavior

**Implementation method**: after a fix, regenerate against the **full driver set** and do a whole-tree comparison; **byte-identical after path normalization**
is a necessary condition. All four committed fixes satisfy it (W1: 19 drivers, only a 2-line difference and it is expected;
lambda: 19 drivers, empty diff).

**Limits**: whole-tree identity **cannot** prove a fix is correct, it can only prove it **did not affect anything else**;
"generation succeeds", "type-check passes", "runs correctly" are three different strengths, and must be stated separately.

## Unresolved

- **The destination of `switchExpression`**: condition 3 requires giving it an explicit destination argument
  (binding route `v.t`, argument route uses the callee's parameter), and `sw.t` only serves as a fallback when there is no contract.
  An implementation seat is running (`out/switchexpr-destination`). **That seat must report "output unchanged" as
  a legitimate result**, and must not fabricate a behavior difference to make the change look necessary.
- **The single-return fast path** (`functionLiteralInner`) never applies boundary conversion:
  the P1 probe of `lambda-fix-xcheck` is byte-identical in both trees and fails in both. This is a residual gap.
- **Category J migration** has no defined contract.
