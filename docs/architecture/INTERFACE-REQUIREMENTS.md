# Architecture Contract

The classification (`PROBLEM-CLASSIFICATION.md`) clarifies "which class of failure belongs to whom"; this file clarifies
**what each side of the interface commits to**, i.e., what a site must hand over, under what conditions.

## Contract 1: Destination is passed in by composition (class D)

**Rule**: a conversion site must be given the **destination** (target type); it must not infer it from compiler-instance state.

**Current facts** (verified; candidate tree `SwiftExpr.hx`, 7041 lines):
- `currentReturnType` is an **instance field** of `SwiftExpr` (`:218`); its only write is at `:544`
  (`functionBody`, from the member's `TFun` return), cleared at `:563`.
- `functionLiteral` (`:2338-2345`) only saves/restores `currentFuncReturnsOptional`,
  and does **not re-bind** `currentReturnType`.
- Inside a lambda the correct value is **`f.t`** (`:2349` already uses it to print the closure header).

**Contract form**:
```
conversion-site(value, destination, fallback) -> text
where destination is provided by the composition that owns the site:
  - member body       -> the member's return type
  - lambda body       -> the lambda's return type (f.t)
  - inline block / anonymous helper -> the block's own result type (not the outer lambda's)
  - binding route     -> the type of the bound variable (v.t)
  - argument route    -> the parameter type declared by the callee
```
**The last item is this session's lesson**: the `blockExpression` block has its own destination;
treating it as the lambda's return contract **injects a wrong conversion** (the P4 regression of `lambda-fix-xcheck`,
`mx/MXProbe.swift:19:12`, `cannot convert 'ReadOnlyArray<Int32>' to closure
result type 'TiqianArray<Int32>'`).

## Contract 2: The intermediate destination of a nil-merge is provided by composition (class-C boundary × class-D destination)

**Spec text** (`docs/compiler-policy-interfaces.md:171-173`, verbatim):
> "A nil-merge with a required final result passes an **optional intermediate
> destination** to the optional left operand's conversion."

**Implementation**: the third input of `prepare(operand, destinationType, override)`
`destinationOptionalOverride` (`SwiftArrayBoundary.hx:173`).
- `override == null` ⇒ the planner decides by the destination's own optionality (the default context of the three REFUSED rows)
- `override == true` ⇒ the composition declares "an optional intermediate result is accepted here" ⇒ that cell becomes a conversion
  (`MapOptionalMutableArrayView` `:200-202`, etc.)

**Contract boundary**: `override` is **the composition's obligation**, not a property of the operand and not an exemption.
The three REFUSED rows in `RECORD.md` (the session-record file of the Swift boundary planner seat, not in the product repo) are therefore qualified in the record as **PLANNER-CELL ONLY**
(CORRECTION 13; the point is implemented in this contract).

## Contract 3: Warnings count toward acceptance (class F)

**Binding standard**: `docs/specs/style/02-translator-implementation-standard.md`
- `:78` *"Generated code compiles **without warnings** on every target … A
  translation that produces a warning is an emitter defect **with the same
  severity as a translation that produces wrong output**."*
- `:80` *"…counts the warning lines in the target suite output that name files
  under the generated trees; **the count is zero**."*

**Corollary (made and written down this session, TCN-156)**:
- warnings **count**; **baseline failures must be recorded, but not exempted** (`work-plan:417`).
- ⇒ **a suite must actually run**: no suite collection ⇒ no count is produced ⇒ the standard cannot be met,
  only bypassed. **That gap has been wired up** (`9f26e1ef`): `ci.yml` adds a `collected-suite`
  job that runs the entry point `bun run test` each time and reports the collected domain (303 files, 249 of them from
  the generated tree `reference/ts/gen-tests`). The job blocks and has no `continue-on-error`;
  baseline `1001 pass / 32 fail / 8 errors` (originally recorded in `BASELINE-FAILURES.md`, deleted 2026-10-03 with the cleanup; the current record is the baseline wiring in `.github/workflows/ci.yml`), not yet discharged.
- ⇒ the recorded form must be "**known baseline failures + explicit PIN**", and must **not** be named "zero-diagnostics met":
  the owner ruling at `tests/swift-gap-boundary/gap-boundary.test.ts:44` is this contract's implementation.

**Supplement (`t-muo92xms-s28t` ruling, `1a486ebd`; the original file `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` was deleted with the cleanup; the ruling content is in that row's note in the wb system):
"Which tool is used" and "which class of diagnostics it can see" must be stated separately.**
The main clause of `:78` is universal ("on every target"), but when enumerating tools it only writes *"the Swift type-checker"*.
That narrowing leaves a hole: **`swiftc -typecheck` does not run SILGen, so even in the baseline state it reports 0 diagnostics**,
so for `Gap.swift:117`'s `will never be executed` it can **neither confirm nor falsify**;
the only things that can actually see it are `-c` (including `-whole-module-optimization`) and `-o`.
⇒ **Ruling: build-phase diagnostics count toward `:78/:80`**. If we literally accept only "the type-checker", "zero warnings" degenerates into
**an empty criterion** (real emitter defects all pass invisibly, while the downstream CI that compiles the binary still hits them).
**Counting discipline**: count by the `file:line:col: severity` **shape**, not with `grep -c 'warning:'`
— Swift also prints caret/context lines, which would count 1 as 2 (PIT-336).
**Generalization to the same family**: for every target, ask "does the current command **fail to see** a diagnostic it can report" —
one same-family example from this session is that `cargo check` and `cargo build` differ in their warning surface.

## Contract 4: The acceptance criterion for generated output must be able to observe the property under test

**Rule**: an acceptance check must **fail when the property is violated**.

**Three counter-examples from this session** (the same gap, three causes):
| Item | Why it cannot be observed |
|---|---|
| `branchBoundary` fixture | the two branches are equal-length; the consumer only prints the length |
| missing-return shape | **`swiftc -typecheck` does not run SILGen, does not report "missing return"** |
| splice-style fixes | the generated tree is byte-identical pre/post (cannot distinguish "unchanged" from "changed correctly") |

**⇒ Implemented criteria** (`LAYERED-VERIFICATION.md` will expand):
1. assertions must be stricter than "not broken": e.g. `1:1:present` rather than `1:present`
2. **the shape that strips `return` must use `swiftc -c`, not `-typecheck`**
3. splice-style changes must use a **discriminating backend** (deliberately take the wrong branch / deliberately return the wrong value) to prove it would FAIL

## Contract 5: A fix must not change other classes' behavior

**Implementation**: after the fix, regenerate against **the full driver set** and do a whole-tree comparison; **byte-identical after path normalization**
is the necessary condition. All four committed fixes satisfy it (W1: 19 drivers, only 2 differing lines and those expected;
lambda: 19 drivers, diff empty).

**Limit**: whole-tree identity **cannot** prove the fix is correct; it can only prove **no spillover elsewhere**;
"generation succeeded", "type-check passed", and "runtime correct" are three different strengths and must be stated separately.

## Contract 6: One judgment must have only one source; what can be derived from facts must not be separately decided

**Rule**: when whether something "holds" affects output, that judgment must have **only one authoritative source**.
If it can be **derived from facts that have already occurred** (whether a file was actually written, whether a declaration was actually emitted),
then it **must be derived**; a second piece of code must not judge it **independently** again.

**Why**: when a criterion and a fact are judged **in parallel**, the two can diverge, and **divergence is invisible in the passing state**.
This is the same family as Contract 4 but at a different layer: Contract 4 says "the check must be able to observe the violated property",
this one says "**the criterion itself must not become decoupled from the fact it describes**".

**Measured (Rust target `state.shimsUsed`)**:
| Quantity | Value |
|---|---|
| write sites (each believes "some shim is used") | **28 sites**, scattered across `RustDecl.hx` / `RustExpr.hx` / `RustImports.hx` |
| read sites (deciding whether a resident should be emitted) | **15 sites** |
| contract specifying "which path must write" | **none** |

(Write-site distribution: `RustExpr.hx` 23, `RustImports.hx` 3, `RustDecl.hx` 2;
read-site distribution: `Compiler.hx` 13, `RustImports.hx` 1, `RustEmissionState.hx` 1.
Counted at `aceda352`, criterion is "line shape": left-hand assignment, subscript assignment, or `push|add|set|insert|remove|clear`.)

⇒ this global is used **with two different meanings**: "business code referenced some extern" (intent layer) and
"should some resident be written as `.rs`" (emission layer). **The two layers are not equivalent, and nobody is responsible for ensuring equivalence.**
The outcome is that `runtime/mod.rs` declares a module that was never written (`E0583`):
**declarations follow one criterion, file emission follows another, and the write surfaces of the two do not overlap.**

**Two fix approaches, different criteria**:
- **Add write sites**: every time an uncovered path is discovered, write the criterion again on that path
  (the one added at the end of `RustImports.requireType` on master is of this kind).
  Correctness is staked on "**complete write-site coverage**"; but the number of write sites **cannot be exhaustively verified**, and a new path means regression.
- **Derive from facts**: make the emission function **return whether it actually wrote a file**, recorded by the caller,
  and generate the declaration list **from that record** (this branch `94eace13`: `emitResidentModule` returns `Bool`
  ⇒ `emittedResidentMods` ⇒ `runtimeMods`). Correctness is staked on "**declarations come from facts**",
  **verifiable and does not regress with new paths**.

**⇒ Implemented criteria**:
1. When "two pieces of code make the same judgment" appears, first distinguish whether it is **same-layer duplication** or **write-side / read-side**;
   if both sides are needed, **the correctness-source side must be designated**.
2. Ask "**is there a contract specifying who must write**". If the answer is "no + write sites far outnumber read sites",
   the real defect is **not a missing merge**; it is that the criterion lacks a unique source.
3. Verify whether the derivation is **self-sufficient**: if, without activating those write sites, the invariant still holds by derivation alone,
   then the derivation stands on its own; **if it only holds when a particular write site fires**, then correctness still depends on
   uncoordinated write sites; **this itself is a finding that must be reported**, even if the code is syntactically correct.

**Ablation measurement (supplement, `aceda352`)**: disable the entire write site at the end of `RustImports.requireType` on master
and regenerate `examples/rust.hxml`.

| Observation | Result |
|---|---|
| gen rc | 0 |
| generated-tree diff (excluding cargo `target/`) | **zero**: 545 `.rs` files identical on both sides |
| `runtime/mod.rs` | **byte-identical** |
| declarations / references | 15 / 15, violations = **0** |
| `cargo check` | rc=0, error count 0 |

⇒ this write site is **completely inert** on this corpus, so "zero violations" **proves neither that the derivation is self-sufficient
nor that the write site is necessary**. The reason is that both paths evaluate the same set of externs: the emission gate at `Compiler.hx:862`
itself reads `state.shimsUsed.exists(externModule)` (via `externsOf`),
using the same pair `(isResident, externsOf)` as the write sites, so by construction they necessarily agree.

To truly determine self-sufficiency, a test case is needed where "only `requireType` touches it, and its importing side does not trigger
extern activation"; until then this item is recorded as **undecided**, and must not be written as "self-sufficiency verified".

**The above conclusion has been overturned (correction, independent reproduction)**: the "whole-tree zero diff" table above is **true,
but it carries almost zero information for judging whether the write site is necessary** — the gate evaluates a **global union over the same shared `shimsUsed`
map**, and any single explicit activation in the full corpus causes all residents to emit as usual,
so the absence of the write site is masked by the corpus itself. **The byte identity of the full corpus must not be taken as evidence of "inertness".**

Minimal counter-example (write site disabled, only the single root `boring.DataClassStringCompare` kept,
the sample that was added together with that write site at `19ae7db6`):

| Observation | write site present | write site disabled |
|---|---|---|
| gen rc | 0 | 0 |
| `runtime/mod.rs` | 9 `pub mod` entries, including `sorted_table` | **5 entries, `sorted_table` gone** |
| `boring/data_class_string_compare.rs` | normal | still `use crate::runtime::sorted_table::SortedTable;` (:1), :26 still calls |
| `cargo check` | **rc=0** | **rc=101, `error[E0432]: unresolved import`** |

⇒ this write site is **load-bearing, not redundant**, and **must not be removed**. Contract 6 therefore has
a far stronger implemented criterion: **judging "whether a write site is necessary" must be done by ablation on the minimal root set,
not on the full corpus** — the passing state of the full corpus masks single-point defects, the same phenomenon as class G's
"divergence is invisible in the passing state". Path: `RustDecl.hx:557` /
`RustType.hx:196-207`'s `requireType("runtime.SortedTable", …)` only activates
the `std.SortedMap` family, while in the full corpus these keys are also activated by `RustImports.hx:61` via
`RustType.hx:197/200/203/206`.

**Applicability boundary of this rule (supplement, measured from the review at `9081d0d0`)**: Contract 6 requires criteria to be derived from
facts, but **"derived fields" does not mean "can validate each other"**. Within the same record,
`stdoutAvailable` is derived from whether the stream object of the host outcome exists (`ChildEvidence.hx:439`),
`stdoutBytes` is derived from the length of the final write-disk buffer (:505); the two come from **different sources**:
in a healthy tree of 1005 records, 236 are simultaneously `available=true` and `bytes=0`.
Therefore **do not** use the available flag to verify "the stream was indeed preserved", and do not
treat available/bytes consistency as an invariant assertion — it is a normal shape in this system.

Similarly, **mutation testing must be done before weakening an assertion**: after relaxing `stdout>0 && stderr>0` to
`stdout+stderr>0`, a real regression that "silently drops stderr on the upper-limit path"
had the entire test suite rc=0 all-green (restoring the old assertion captured it at rc=1). The basis for relaxation can only be
"what does the subject under test guarantee", not "it no longer fails sporadically after the change".

## Undecided

**The three position references in this section, measured one by one on 2026-10-01, are as follows** — all three **point to nothing**,
but the **technical problems** they express **still stand**, so each is distinguished as "statement" vs "position":

- **`switchExpression` destination**: Condition 3 requires an explicit destination argument
  (binding route uses `v.t`, argument route uses the callee's parameter), `sw.t` only as a fallback when there is no contract.
  ~~implementation seat running (`out/switchexpr-destination`)~~ → **that worktree does not exist** (searched by directory name,
  branch name, and worktree name, three methods, none found; `git worktree list` returns 122 entries, this one is not among them).
  **Remove the status word "running"**: it claims a current fact; once the document is out of sync it becomes false.
  Keep the technical problem itself, and that constraint: **that seat must report "output unchanged" as a legitimate result**,
  and must not fabricate behavioral differences to make the change appear necessary.
- **Single-return fast path** (`functionLiteralInner`) has never applied boundary conversion:
  ~~the P1 probe of `lambda-fix-xcheck` is byte-identical in both trees and both fail~~ →
  **`lambda-fix-xcheck` does not exist** (same three search methods). Keep the statement: this path has never applied
  boundary conversion; it is a residual gap; **a probe must be rebuilt** before it can be cited again.
- **Class-J migration** (legacy Kotlin → Haxe) contract is undefined — **this one stands**,
  unlike the two above: the classification document `:92` **registers class J**, writing that it is "a classification gap outside A–F"
  (per CODEX-AUDIT's "complete J migration were not established").
  So this is a **valid** undecided item: **there is a class that is registered but has no contract yet**.

**These three are not the same thing; they only became distinguishable after measurement**:

| Item | Statement holds | Position reachable |
|---|---|---|
| `switchExpression` destination | yes | **no** — worktree does not exist |
| single-return fast-path gap | yes | **no** — `lambda-fix-xcheck` does not exist |
| class-J migration contract undefined | yes | **yes** — classification document `:92` |

**Supplement (my own correction)**: I initially classified class J as a "dangling reference" too; **that was wrong** —
it was indeed registered in the classification document, just not in the A–F table, so my lookup by class alphabet did not find it.
**Checking "whether some class exists" must not look only at the main table**: the section that registers gaps is likewise part of the definition.
The two that are truly broken are **worktree references**, because they point to **temporary** locations.

**The common shape of these three is worth recording**: they are the **most fragile** kind of "known but undecided" record —
they reference a **temporary** worktree, and worktrees get cleaned up leaving no trace.
**Supplement rule**: undecided items should write down **the technical problem itself** (which can stand long-term) + **a reproducible probe command**,
not + a worktree name. A worktree name is a position, and positions disappear; the problem is content, and content does not.
