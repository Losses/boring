# Layered Verification Plan

Classification says "who owns it", the contract says "what is promised", and this document says **which observable each layer uses to verify**, and **when each criterion will lie to you**.

## Layers and Criteria

| Layer | Property under test | Observable | Pass criterion | **When this criterion lies** |
|---|---|---|---|---|
| **L1 Generation** | the compiler did not crash, outputs are complete | generator process exit code + file manifest | `rc=0` and the expected files exist | **rc=0 does not mean the output is correct**: the `fail()` at `:2609` also leads to rc=1, but an input that "did not reach the crash" gets rc=0 while its output is wrong |
| **L2 Syntax/Types** | the output is valid in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` does not run SILGen**: a multi-statement closure with `return` stripped only reports a warning and fails only on a real build. **This form must use `swiftc -c`** |
| **L3 Build** | the output can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 error | build-phase diagnostics (`will never be executed`) **do not appear under `-typecheck`**. **Ruled: counted into the acceptance criteria** — see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (`1a486ebd`). **The current fact for this entry is "not zeroed"**: the diagnostic count is still **1**, and it is an **unwaived, recorded baseline failure**, see the next section "This layer is not currently green" |
| **L4 Behavior** | the runtime result is correct | line-by-line comparison with the oracle | **byte-for-byte identical** | if the oracle itself is wrong, everything is wrong; and "identical to the oracle for the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 Discrimination** | the check **can** detect the target defect | run against a deliberately wrong backend | deliberate error ⇒ **FAIL** | without this layer, L1–L4 all green may only mean **the property was never observed** |

## L5 is a layer added by this session (previously missing)

**Instances of "a check that cannot discover the target defect"**:

1. **`branchBoundary` fixture**: the two branches are equal length, the consumer only prints the length ⇒ a backend that "always takes either branch" **passes all assertions**. After the fix, `branch-false=1:2:present` FAILs against the deliberately wrong backend (commit `d1180768`).
2. **`swiftc -typecheck`**: misses "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Splicing-style edits**: the generated tree is byte-identical pre/post ⇒ cannot distinguish "no effect" from "fixed correctly".
4. **The zero-warning gate does not exist at all** (`t-mum29cli-9c9w`, `89dd80b2`): `:78/:80` requires zero warnings, but `test:dart` at `package.json:21` **explicitly** carries `--no-fatal-warnings`, `test:rust` at `:12` has no `-D warnings`, and the CI's only gate `collected-suite` only greps the `bun run test` log which **does not contain** the five-target compiler output ⇒ **under a passing state the grep domain is empty**. The existing warning stock — Dart 46 / Kotlin 59 / Rust 4 — is all rc=0. **A reproducible discrimination method**: inject **one** warning into the same tree, run the "existing command" and the "strict command" — `dart: loose rc=0 / strict rc=2`, `rust: loose rc=0 / strict rc=101`; **if the two rc values are equal, the gate does not exist** (that seat turned it into a rerunnable `verify.sh`). Fix line `fix/zero-warning-gate-wiring`.
5. **"Changed the emitter" does not equal a different generated output** (PIT-347 measured): a seat added **38 lines** of AST traversal bypass to `Compiler.hx`, `diff -rq` shows **0 differences** against the **whole generated tree**, and the target site is unchanged by a single character. **Discrimination method**: any emitter change must **regenerate and diff the generated artifacts** to count; a plausible-looking source diff does not constitute evidence. (Another re-dispatch of the same line changed only **9 lines** yet genuinely changed the site.)

**⇒ L5's operational form**: every fixture must be paired with a **deliberately wrong backend** (takes the wrong branch, returns the wrong value, strips the transform), and must prove the fixture FAILs against it. **Proving only that "the correct backend passes" is not verification.**
**⇒ The corollary for "gate-type" criteria**: you must give the rc of **both** the loose and strict runs at the same time — reporting only "pass" cannot distinguish "the check passed" from "there was no check".

## Every criterion must state "on which tree it holds" (added this session, L0 prerequisite)

**Rule**: any criterion that claims "fixed / effective / closed" must, on the **same line**, give the **commit hash** and **the result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**. If the result is false, it may only be written as "branch state / working-tree state", and **must not** be written as effective.

**Why this is not formalism**: this session measured the same thing giving **opposite conclusions** on two trees — the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) **was reviewed and signed off** yet **was never an ancestor of base**, so the weak version runs on base: delete the real root `boring.ArraySliceOps` and add an exemption with reason `"because"`, and the weak version returns **rc=0 PASS (4 exemptions)** while the hardened version returns **rc=1** and names it verbatim. That is, "signed off" and "effective" are two different things; without naming the tree, a **nonexistent protection** gets recorded as existing.

**Three-step verification (must run before sign-off or handover)**:
1. `git rev-parse --verify <branch>` — does the branch **exist** (this session has several rows whose `branch` field points to branches **that were never created**)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — **did it get into base**
3. **Read the file directly in the shared tree** — what form is actually in base (step 3 cannot be skipped: in this case the first two steps both passed, and only the third found the weak version)

**After merging, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which line am I on now) **and** step 2 (is it really on the **declared base**) — this session had one instance where four merges all landed on the working line while the declared base did not move, so newly created worktrees did not get those fixes.

## Delivery side: a load-bearing piece must be able to answer "which commit contains it"

**Rule**: tools, guards, fixtures, drivers, assertion scripts — things later people will depend on — **must be committed to the repo**; evidence may live only in reports. If a criterion depends on a file, you must also give the basis that **it is reachable in a clone** (for example, `git ls-files --error-unmatch <path>` passes, and `git archive HEAD` can extract it).

**Two measurements this session**: ① under `dc-warn/worktrees/` all **37/37** are detached HEAD, **all have uncommitted changes**, **none carries a commit beyond `e1c65975`** — "done in the working tree + report on file" became this batch's actual delivery convention; ② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths, so "one command returns rc=0" **only holds for the author's working copy** and is false for a clone (PIT-346).
**Fix**: the manifest may **mark reachability by section** (repo-verifiable / evidence-only), and verify in a **clean exported tree containing only committed files**.

## The evidence strength of each layer must be stated separately

**Do not** conflate the three:
- "generation succeeded" (L1)
- "the generated code type-checks" (L2)
- "the runtime result is correct" (L4)

**One misjudgment this session came from this**: `d14aae11` was committed with `-typecheck` 0/0 as the acceptance criterion, but that criterion cannot see L3/L4 problems (the P4 regression only surfaced under a full build).

## Honest reporting of coverage

**Rule**: when reporting "covers N/M", you must also give **the skipped items and their reasons**.

**Example**: the P1 scoped run claimed "every P1-updated expectation is exercised", but actually **56/57** — `printed-record.test.ts:88` is only consumed in a test that times out, so it never executes; and the pre-existing red at `array-root.test.ts:18` means `L28` is never reached.
(lesson PIT-321)

## Timeouts and failures must be distinguished

**The criterion is "whether the subject ran to completion", not "whether it timed out".**

**Example**: the coupled run of `value-type` was **not killed** — `Bun.spawnSync` blocks the bun timer, taking 351 s ≈ 15 runs, and the temp directory disappears in both copies ⇒ the subject **ran to completion**.
Reading it as "coupling masked by a timeout" is wrong; the correct description is **latent coupling** (the fix is not on the execution path of those probes at all).

## The command corresponding to each layer (current state)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | partial |
| L3 | `swiftc -c` | **no** |
| L4 | fixture's own runner + oracle | **no** |
| L5 | discriminating backend | **no** |
| Collection | **`bun run test` (collects `tests/**`)** | **yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (since `9f26e1ef`): the `collected-suite` job runs the entry `bun run test` every time, reporting the collection domain and counts; the job is blocking with no `continue-on-error`, so breaking a protected assertion fails it (negative-control proof in `dc-warn/out/ci-wire/`). **The count already exists**, but the standard `:80` "count is zero" **is still not met**: the baseline (`1001 pass / 32 fail / 8 errors`) has not been settled, and `BASELINE-FAILURES.md` only records, never waives. The collection domain is 303 files, 249 of which come from the generated tree `reference/ts/gen-tests`, so the job regenerates first and then collects.

## This layer is not currently green (L3 build-phase diagnostics, correction record)

**An earlier version of this document wrote at line 12 "S1 already zeroed it (1 → 0)". That was wrong; it is corrected here while preserving the wrong shape, because it is exactly the kind this document's own L0 section warns about.**

The wrong shape: writing a **measurement on the candidate-material tree** as an **established fact on the current line**. Checking each:

| Question | Result |
|---|---|
| Is `cd70eb12` an ancestor of `arch/agent-guided-governance` (base)? | **no** — `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` → rc=1 |
| Which branches does it appear on? | only `prep/p08-s1-unreachable-return` (including the origin branch of the same name) — it is a piece of **candidate material** |
| Does `stmtDiverges` exist in the current tree? | **no** — `grep -rn stmtDiverges --include=*.hx packages/` → 0 hits |
| What is the diagnostic count on the current tree? | **1**, and it is **explicitly asserted by a fixture as must-exist** |

`tests/swift-gap-boundary/gap-boundary.test.ts` pins this 1 warning, and its comment describes itself as "an unwaived, recorded baseline failure -- the goal remains zero diagnostics under `-c`", with the assertion `toHaveLength(1)`. So:

- **The fixture says "the defect is still there"** (a sentinel needle; once the defect is genuinely fixed, this assertion fails and forces a re-read of the count);
- **The document at that time said "already zeroed"**.

Both cannot be true at once; the measurement sides with the fixture. The "1 → 0" record in `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` describes **that tree** `cd70eb12`, where it is true; it cannot be cited as the current line's state.
Writing the candidate-tree conclusion as line state directly conflicts with this record's L0-section requirement to "give commit + `is-ancestor` result" — and at the time that rule had no machine enforcement, so it was violated without anyone noticing.

**Lesson (already written into the L0 section)**: a candidate material's measurement result may only be written as "effective" when `is-ancestor` is true. This document previously lacked exactly that step.

## L6: conflicts between criteria (added this session)

The first five layers each answer "will this criterion lie". This layer answers a different question: **can two individually correct criteria be mutually exclusive.** Yes, and it is completely invisible in the passing state — each criterion is green when run alone, and only putting them in the same tree exposes it.

### Example one: two criteria demand the opposite of the same predicate

There are two positive controls on Kotlin smart casting (established by two different tasks, each independently re-reviewed):

| Criterion | Shape it catches | Requirement |
|---|---|---|
| `tests/haxe/kotlin-var-field-smartcast` | the mutable field's guard does not emit `!!`, the read path drops the assertion | the mutable field's **guard must emit `!!`** |
| `tests/kotlin/smartcast-tfield` | a reassignment (or closure rewrite) happens **between** the guard and the read, yet the emitter still emits a bare dot | the mutable field **does not count as proven** |

Measured (isolated one at a time, changing only one place each time):

| Configuration | `var-field-smartcast` | `smartcast-tfield` |
|---|---|---|
| keep stability narrowing | **FAIL** | pass |
| remove stability narrowing | pass | **FAIL** |

**Both cannot be true at once, and both sides are catching real kotlinc rejections.** The root cause is not that either side wrote it wrong, but that **one judgment has two sources** (guard side `smartCastableSubject`, read side `fieldProven`), i.e. a violation of contract 6. The disposition is to **unify the predicate**, not to pick one of the two — picking one just relocates the regression.

### Example two: collapsing three states into binary silently changes semantics

In the same unification, after tightening the read-side predicate to "value proven ∧ smart-castable", the output regressed from `holder.value!!.magnitude()` to `holder.value?.magnitude()`.

**Both pass kotlinc**, but `!!.` is forced extraction (throws on failure) and `?.` is a safe call (silently returns null).
So the correct model here is **three-state**, not binary:

| Form | Condition |
|---|---|
| bare dot `.` | value proven **and** will smart-cast |
| forced `!!.` | value proven **but** will not smart-cast |
| safe `?.` | value not proven |

**`?.` almost always passes kotlinc**, so "compiles" is the weakest criterion in this family: it can only collapse the three states into "not an error", and cannot distinguish that the semantics have been swapped out. **This layer's criterion must be "which of the three forms appears in the output", not "whether it compiles".**

### Example three: the same suppression mechanism "exists but covers incompletely"

`(c > 8 && c < 14) || c == 32` in `packages/compiler/runtime/StringTools.hx`, under the premise that the source is byte-identical across the two trees:

- master `cc9957dd` → `StringTools.kt:9` = `c!! > 8 && c < 14 || c == 32` (sha256 `ced8a07374d72ffa…`)
- mainline `42c805d3` → `StringTools.kt:9` = `c!! > 8 && c!! < 14 || c == 32` (sha256 `b7b22e37bd37d24d…`)

Among the three `c`s, **only the second** over-emits `!!`; the third is correct. So the mechanism "repeated extraction is suppressed" **exists**, it just **covers part of the read sites**.

**A dangerous criterion shape**: a test that only asserts "somewhere there is no `!!`" will be **all green**, because what it hits is exactly the one site the mechanism covers. To catch this family, the criterion must be **"the same subject is extracted at most once within the same expression"** — using **all** read sites of that expression as the positive control.

### This layer's criteria (for future fixtures)

1. **One judgment must have only one source**; when two criteria demand the opposite of the same predicate, first check whether there are two implementations.
2. **Enumerate the output forms, do not just assert "it compiles"** — especially when there are equivalent-but-semantically-different forms like `?.`/`!!`/bare dot.
3. **For "suppression/dedup" mechanisms, use all sites as the positive control**, do not pick one site and assert absence.
4. Conflicts between criteria **must be explicitly recorded** (which two, under which configuration they are mutually exclusive, the measured matrix), otherwise the next person to merge will treat it as an ordinary regression.

## Unresolved

- **Whether L5's discriminating backend is written into every fixture** (currently only `branchBoundary` and the gap driver have one)
- **Whether `swiftc -c` should replace `-typecheck` as the acceptance standard for all Swift work** — the evidence supports distinguishing by form (ordinary forms suffice with `-typecheck`, forms with stripped return must use `-c`)
