# Layered Verification Scheme

Classification says "who owns what", contract says "what is promised", this document says **what observable quantity each layer uses to verify**, and **when each criterion lies**.

## Layers and criteria

| Layer | Property under test | Observable | Pass criterion | **When that criterion lies** |
|---|---|---|---|---|
| **L1 Generation** | compiler did not crash, artifacts complete | generation process exit code + file manifest | `rc=0` and expected file exists | **rc=0 does not mean the artifact is correct**: the `fail()` at `:2609` also reaches rc=1, but an input that "did not hit the crash" returns rc=0 while the output is wrong |
| **L2 Syntax/Type** | artifact is legal in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` does not run SILGen**: multi-statement closures with `return` stripped only report a warning, a real build fails. **Such forms must use `swiftc -c`** |
| **L3 Build** | artifact can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 error | build-phase diagnostics (`will never be executed`) **do not appear in `-typecheck`**. **Adjudicated: counted into the acceptance criteria** — see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (`1a486ebd`). **The current fact for this entry is "not zeroed"**: that diagnostic count is still **1**, it is an **unwaived recorded baseline failure**, see the section below "This layer is not green right now" |
| **L4 Behavior** | runtime result is correct | compare line by line against the oracle | **byte-for-byte identical** | if the oracle itself is wrong everything is wrong; and "identical to the oracle on the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 Discriminative** | the check **can** discover the target defect | run against a deliberately wrong backend | deliberate error ⇒ **FAIL** | without this layer, all-green L1–L4 may only mean **the property was not observed** |

## L5 is a layer added by this session (previously missing)

**Instances of "the check cannot discover the target defect"**:

1. **`branchBoundary` fixture**: the two branches are equal length, the consumer only prints the length ⇒ a backend that "always takes either branch" **passes all assertions**. After the fix `branch-false=1:2:present` FAILs against the deliberately wrong backend (commit `d1180768`).
2. **`swiftc -typecheck`**: misses "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Concatenation-type edits**: generated tree pre/post byte-identical ⇒ cannot distinguish "not effective" from "changed correctly".
4. **A zero-warning gate does not exist at all** (`t-mum29cli-9c9w`, `89dd80b2`): `:78/:80` require zero warnings, but `test:dart` at `package.json:21` **explicitly** carries `--no-fatal-warnings`, `test:rust` at `:12` has no `-D warnings`, the sole CI gate `collected-suite` only greps the `bun run test` log, and that log **does not contain** the five-target compiler output ⇒ **in the passing state the grep domain is empty**. The existing warning backlog Dart 46 / Kotlin 59 / Rust 4 all return rc=0. **Reproducible discrimination**: inject **one** warning into the same tree, run the "existing command" and the "strict command" — `dart: loose rc=0 / strict rc=2`, `rust: loose rc=0 / strict rc=101`; **if the two rc are identical, the gate does not exist** (that seat made it into a re-runnable `verify.sh`). Fix line `fix/zero-warning-gate-wiring`.
5. **"Changed the emitter" is not the same as producing different artifacts** (PIT-347 measured): a seat added a **38-line** AST-traversal bypass in `Compiler.hx`, `diff -rq` over the **entire generated tree** shows **0 differences**, the target site unchanged by a single character. **Discrimination**: any emitter change must **regenerate and diff the generated artifacts** to count; a plausible-looking source diff is not evidence. (Another re-dispatch of the same line changed only **9 lines** yet actually changed the site.)

**⇒ L5's operational shape**: every fixture must be paired with a **deliberately wrong backend** (takes the wrong branch, returns the wrong value, strips the conversion), and prove the fixture FAILs on it. **Only proving "the correct backend passes" does not count as verification.**
**⇒ Corollary for "gate-type" criteria**: you must give the rc of **both** the loose and the strict runs — reporting only "pass" cannot distinguish "the check passed" from "there was no check".

## Every criterion must state "on which tree it holds" (added this session, L0 prerequisite)

**Rule**: any criterion claiming "fixed / in effect / closed" must give, **on the same line**, the **commit hash** and **the result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**. Where the result is false, it may only be written as "branch state / working-tree state", and must **not** be written as in effect.

**Why this is not formalism**: this session measured the same thing giving **opposite conclusions** on two trees — the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) was **reviewed and signed** yet was **never an ancestor of base**, so what runs on base is the weak version: delete the real root `boring.ArraySliceOps` and add an exemption with reason `"because"`, the weak version returns **rc=0 PASS (4 exemptions)** while the hardened version returns **rc=1** and names it verbatim. That is, "signed off" and "in effect" are two different things; without naming the tree, a **nonexistent guard** will be recorded as existing.

**Three-step verification (must run before sign-off or handoff)**:
1. `git rev-parse --verify <branch>` — does that branch **exist** (this session has several rows whose `branch` field points at branches **never created**)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — **has it entered base**
3. **directly read the file in the shared tree** — **what form is it actually in** in base (step 3 cannot be skipped: in this case the first two steps passed, and only the third discovered it was the weak version)

**After merging, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which line am I on now) **and** step 2 (is it really on the **declared base**) — once this session all four merges landed on the working line while the declared base did not move, so a newly opened worktree could not get those fixes.

## Delivery surface: a load-bearing artifact must be able to answer "which commit contains it"

**Rule**: tools, guards, fixtures, drivers, assertion scripts — things that will be depended on by later people — **must be committed**; evidence may live only in reports. If a criterion depends on some file, it must also give the basis that **it is reachable in a clone** (for example `git ls-files --error-unmatch <path>` passes, and `git archive HEAD` can extract it).

**Measured twice this session**: ① under `dc-warn/worktrees/` **37/37** are all detached HEAD, **all have uncommitted changes**, **none carries a commit beyond `e1c65975`** — "done in the working tree + report on file" became this batch's actual delivery convention; ② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths, making "one command rc=0" **hold only for the author's working copy** and false for a clone (PIT-346). **Fix**: the manifest may **annotate reachability by section** (repo-verifiable / evidence-only), and be verified in a **clean export tree containing only committed files**.

## Each layer's evidence strength must be stated separately

**Must not** conflate the three:
- "generation succeeded" (L1)
- "the generated code type-checks" (L2)
- "the runtime result is correct" (L4)

**One misjudgment this session came from exactly this**: `d14aae11` was committed using `-typecheck` 0/0 as the acceptance criterion, but that criterion cannot see L3/L4 problems (the P4 regression only surfaces under a full build).

## Honest reporting of coverage

**Rule**: when reporting "covers N/M" you must also give **the skipped items and their reasons**.

**Instance**: a P1-scoped run claimed "every P1 update's expectation is exercised", actually **56/57** — `printed-record.test.ts:88` is consumed only in the timed-out test, so it never executed; and the pre-existing red at `array-root.test.ts:18` meant `L28` was never reached. (Lesson PIT-321)

## Timeout and failure must be distinguished

**The criterion is "whether the subject ran to completion", not "whether it timed out".**

**Instance**: the coupled run of `value-type` was **not killed** — `Bun.spawnSync` blocks the bun timer, taking 351 s ≈ 15 runs, and the temp directory disappeared in both copies ⇒ the subject **ran to completion**. Reading it as "coupling masked by timeout" is wrong; the correct statement is **latent coupling** (the fix is not on the execution path of those probes at all).

## Commands corresponding to each layer (current state)

| Layer | Command | In CI |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | partial |
| L3 | `swiftc -c` | **no** |
| L4 | fixture's own runner + oracle | **no** |
| L5 | discriminative backend | **no** |
| Collection | **`bun run test` (collects `tests/**`)** | **yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (from `9f26e1ef`): the `collected-suite` job's entry point each run is `bun run test`, reporting the collection domain and count; that job blocks, has no `continue-on-error`, and breaking a protected assertion fails it (negative-control proof in `dc-warn/out/ci-wire/`). **The count already exists**, but standard `:80`'s "count is zero" is **still not met**: the baseline (`1001 pass / 32 fail / 8 errors`) has not been paid down, and `BASELINE-FAILURES.md` only records, does not waive. The collection domain is 303 files, of which 249 come from the generated tree `reference/ts/gen-tests`, so that job regenerates before collecting.

## This layer is not green right now (L3 build-phase diagnostics, correction record)

**An earlier version of this document wrote at line 12 "S1 has zeroed it (1 → 0)". That was wrong; here it is corrected while keeping the wrong shape, because it is exactly the kind this document's L0 section itself warns about.**

The wrong shape: writing **a measurement on the candidate-material tree** as **an accomplished fact on the current line**. Verify each:

| Question | Result |
|---|---|
| Is `cd70eb12` an ancestor of `arch/agent-guided-governance` (base)? | **No** — `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` → rc=1 |
| Which branches does it appear on? | only `prep/p08-s1-unreachable-return` (including the origin branch of the same name) — it is a piece of **candidate material** |
| Does `stmtDiverges` exist in the current tree? | **No** — `grep -rn stmtDiverges --include=*.hx packages/` → 0 hits |
| What is the diagnostic count on the current tree? | **1**, and it is **explicitly asserted as required to exist** by a fixture |

`tests/swift-gap-boundary/gap-boundary.test.ts` pins this 1 warning, and its comment describes it as "an unwaived, recorded baseline failure -- the goal remains zero diagnostics under `-c`", asserting `toHaveLength(1)`. So:

- **The fixture says "the defect remains"** (a preservative pin; once the defect is actually fixed, this assertion fails and forces a re-read of the count);
- **The document at that time said "zeroed".**

The two cannot both be true; the measurement sides with the fixture. The "1 → 0" record in `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` describes **that tree** `cd70eb12`, within which it is true; it cannot be cited as the current line's state. Writing a candidate-tree conclusion as a line state directly conflicts with this record's L0 section requirement "must give commit + `is-ancestor` result" — and that rule had no machine enforcement at the time, so it was violated and nobody noticed.

**Lesson (already written into the L0 section)**: a candidate material's measured result can only be written as "in effect" when `is-ancestor` is true. Previously this document lacked exactly that step.

## L6: conflicts between criteria (added this session)

The first five layers each answer "will this criterion lie". This layer answers a different question: **whether two individually-correct criteria can be mutually exclusive.** Yes, and it is completely invisible in the passing state — each criterion run alone is green, and only putting them in the same tree exposes it.

### Instance one: two criteria make opposite demands on the same predicate

There are two positive controls on Kotlin smart-casting (each established by a different task, each independently reviewed):

| Criterion | Shape it catches | Requirement |
|---|---|---|
| `tests/haxe/kotlin-var-field-smartcast` | the guard on a mutable field does not emit `!!`, the read path loses the assertion | the **guard on a mutable field must emit `!!`** |
| `tests/kotlin/smartcast-tfield` | reassignment (or closure rewrite) happens **between** the guard and the read, the emitter still emits a bare dot | a mutable field **does not count as proven** |

Measured (isolating one at a time, changing only one thing each time):

| Configuration | `var-field-smartcast` | `smartcast-tfield` |
|---|---|---|
| keep the stability narrowing | **FAIL** | pass |
| drop the stability narrowing | pass | **FAIL** |

**The two cannot both be true, and both sides are catching real kotlinc rejections.** The root cause is not that either side wrote it wrong, but that **one judgment has two sources** (guard side `smartCastableSubject`, read side `fieldProven`), i.e. a violation of contract 6. The disposition is to **unify the predicate**, not to pick one of two — picking one only moves the regression to another place.

### Instance two: collapsing three states into a binary silently changes semantics

In the same unification, after tightening the read-side predicate into "value proven ∧ smart-castable", the artifact regressed from `holder.value!!.magnitude()` to `holder.value?.magnitude()`.

**Both pass kotlinc**, but `!!.` is a forced extraction (throws on failure) and `?.` is a safe call (silently returns null). So the correct model here is **three-state**, not binary:

| Form | Condition |
|---|---|
| bare dot `.` | value proven **and** will smart-cast |
| forced `!!.` | value proven **but** will not smart-cast |
| safe `?.` | value not proven |

**`?.` almost always lets kotlinc pass**, so "compiles" is the weakest criterion in this family: it can only compress the three states into "not an error", and cannot distinguish that the semantics have been swapped out. **This layer's criterion must be "which of the three forms appears in the artifact", not "whether it compiles".**

### Instance three: the same suppression mechanism "exists but covers incompletely"

For `(c > 8 && c < 14) || c == 32` in `packages/compiler/runtime/StringTools.hx`, on the premise that the source is byte-identical across two trees:

- master `cc9957dd` → `StringTools.kt:9` = `c!! > 8 && c < 14 || c == 32` (sha256 `ced8a07374d72ffa…`)
- mainline `42c805d3` → `StringTools.kt:9` = `c!! > 8 && c!! < 14 || c == 32` (sha256 `b7b22e37bd37d24d…`)

Of the three `c` occurrences, **only the second** emits an extra `!!`, the third is correct. So the "duplicate extraction is suppressed" mechanism **exists**, it just **covers only some read sites**.

**The dangerous criterion shape**: a test that only asserts "there is no `!!` somewhere" will be **all green**, because it hits exactly the one site the mechanism covers. To catch this class, the criterion must be **"extraction of the same subject within the same expression at most once"** — using **all** read sites of that expression as the positive control.

### Instance four: the optimization attaches to one form, and is re-materialized inside nesting

The Rust emitter's per-char loop units precompute (`perCharLoopInfo` in `RustExpr.hx`) has **only one call site** (`case TWhile`), the `TFor` path has none of it — so Haxe's most common `for (i in 0...s.length)` traversal is unprotected.

But the execution seat, after measuring, gave a **more accurate mechanism** and corrected this pre-study: the main cause is not "some loop form lacks the optimization", but that **in nested per-char loops, the inner level re-materializes the unit vector the outer level already holds** — that duplicated `let __units = u_string::units(&s);` lands inside the outer loop body, which is what makes it quadratic. Under this fix, **nested `TWhile` benefits equally**, not just `TFor`.

**Implication for criteria**: the entry can ask "how many loop forms does this optimization cover", but **must continue to ask "how many times the same precompute is re-materialized across nesting levels"**. Only adding forms misses the main cause. Reusable technique: count the **occurrences** of the same `let <temp> = <expensive call>(` in the generated artifact — appearing >1 time inside nested loops is that defect.

**It has the same structure as the first three instances**: the criterion's observation domain (one loop form / one loop level) is **smaller than** the property it claims to cover (any per-char traversal / any nesting depth).

### Instance five: audit-type guards define "covered" by location, not by reference

The first four instances are about **artifact criteria** (emission / optimization / suppression). The fifth is about the **audit-type guard itself**: its criterion is "whether this fixture is collected", and it implemented that sentence as "whether there is a `*.test.ts` **inside** the fixture directory".

So fixtures whose tests live under `tests/<target>/` and which drive the hxml inside the fixture directory are judged "unattended". Measured, that blind spot has **3** cases: `dc-promoted-eval`, `swift-package-shell-emit` (driven by `tests/ts/package-shell.test.ts:388`), `kotlin-smartcast-tfield` (driven by `tests/kotlin/smartcast-tfield.test.ts:74`). After the criterion changed to "a test inside the directory **or** any collected test mentioning that fixture path", the count went 37 → 34.

**Why it deserves a standalone entry**: this is an instance of "observation domain smaller than the claimed scope" at the **meta level** — not some product criterion lying, but **the guard responsible for discovering that criteria lie** lying itself. It is more concealed than the first four, because the number it produces looks very concrete (37 uncollected fixtures), and concreteness is easily mistaken for correctness.

**When relaxing this kind of guard you must do two checks** (missing either is a let-down):
1. print the **real reference** that makes each item "pass" (the test file and line number that hit);
2. confirm that **the true orphans are still counted** — in this example `kotlin-mutable-chain-probe` has no test reference anywhere, and remains uncollected after the relaxation.

### This layer's criteria (for future fixtures)

1. **One judgment may have only one source**; when two criteria make opposite demands on the same predicate, first check whether there are two implementations.
2. **Enumerate artifact forms, do not only assert "it compiles"** — especially when there are equivalent-but-semantically-different spellings like `?.`/`!!`/bare dot.
3. **For "suppression / dedup" mechanisms, use all sites as the positive control**, do not pick one site and assert absence.
4. Conflicts between criteria **must be recorded explicitly** (which two, under what configuration they are mutually exclusive, the measured matrix), otherwise the next person merging will treat it as an ordinary regression.
5. **An optimization / suppression / dedup mechanism's criterion must be expanded along the two dimensions "form × nesting depth"**, not asserted as existing at a single site. Instances three and four are both failures of this shape.

## Open questions

- **Whether L5's discriminative backend should be written into every fixture** (currently only `branchBoundary` and the gap driver have it)
- **Whether `swiftc -c` should replace `-typecheck` as the acceptance standard for all Swift** — the evidence supports distinguishing by form (ordinary forms, `-typecheck` suffices; return-stripped forms must use `-c`)
