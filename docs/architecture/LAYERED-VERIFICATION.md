# Layered Verification Scheme

Classification says "who owns it", the contract says "what is promised", and this document says **what observable quantity each layer uses to verify**, and **when each criterion misleads**.

## Layers and Criteria

| Layer | Property being verified | Observable quantity | Pass criterion | **When this criterion misleads** |
|---|---|---|---|---|
| **L1 Generation** | The compiler did not crash and all artifacts are present | Generator process exit code + file list | `rc=0` and expected files exist | **rc=0 does not mean the artifact is correct**: the `fail()` at `:2609` also reaches rc=1, but an input that "does not reach the crash" yields rc=0 while its output is wrong |
| **L2 Syntax/Type** | The artifact is valid in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` does not run SILGen**: a multi-statement closure with `return` stripped only reports a warning, and only a real build fails. **Such forms must use `swiftc -c`** |
| **L3 Build** | The artifact can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 error | The build-phase diagnostic (`will never be executed`) **does not appear under `-typecheck`**. **Ruled: it counts in the acceptance criteria** — see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (`1a486ebd`). **The current fact for this entry is "not zeroed"**: the diagnostic count is still **1**, and it is an **unwaived, recorded baseline failure**, see the section below "This layer is not green right now" |
| **L4 Behavior** | The runtime result is correct | Line-by-line comparison against the oracle | **Byte-for-byte identical** | If the oracle itself is wrong, everything is wrong; and "identical to the oracle on the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 Discrimination** | The check **can** detect the target defect | Run against an intentionally wrong backend | Intentional error ⇒ **FAIL** | Without this layer, all-green L1–L4 may only mean **the property was not observed** |

## L5 is a layer this session added (previously missing)

**Instances of "the check cannot detect the target defect"**:

1. **`branchBoundary` fixture**: both branches are equal length and the consumer only prints the length ⇒ a backend that "always takes either branch" **passes all assertions**. After the fix, `branch-false=1:2:present` FAILs against the intentionally wrong backend (commit `d1180768`).
2. **`swiftc -typecheck`**: misses "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Splicing-type changes**: the generated tree is byte-for-byte identical pre/post ⇒ unable to distinguish "not effective" from "changed correctly".
4. **The zero-warning gate simply does not exist** (`t-mum29cli-9c9w`, `89dd80b2`): `:78/:80` require zero warnings, but `package.json:21`'s `test:dart` **explicitly** carries `--no-fatal-warnings`, `:12`'s `test:rust` has no `-D warnings`, and the CI's only gate `collected-suite` merely greps the `bun run test` log, which **does not contain** the five-target compiler output ⇒ **in the passing state the grep domain is empty**. The existing warning inventory Dart 46 / Kotlin 59 / Rust 4 all rc=0. **A reproducible discrimination method**: inject **one** warning into the same tree, run the "existing command" and the "strict command" — `dart: loose rc=0 / strict rc=2`, `rust: loose rc=0 / strict rc=101`; **if the two rc values are identical, the gate does not exist** (that seat turned it into a re-runnable `verify.sh`). Fix branch `fix/zero-warning-gate-wiring`.
5. **"Changed the emitter" does not equal produced a different artifact** (PIT-347 measured): some seat added a **38-line** AST traversal bypass in `Compiler.hx`, `diff -rq` over the **entire generated tree** showed **0 differences**, and the target site did not change by a single character. **Discrimination method**: any emitter change must **regenerate and diff the generated artifacts** to count; a source diff that looks reasonable is not evidence. (Another reassignment on the same line changed only **9 lines** yet genuinely changed the site.)

**⇒ L5's operational form**: every fixture must be paired with an **intentionally wrong backend** (takes the wrong branch, returns a wrong value, strips the transformation), and prove that the fixture FAILs against it. **Proving only that "the correct backend passes" is not verification.**
**⇒ Corollary for "gate-type" criteria**: you must give the rc of **both** a loose and a strict run — reporting only "pass" cannot distinguish "the check passed" from "there was no check".

## Every criterion must state "on which tree it holds" (added this session, L0 prerequisite)

**Rule**: any criterion claiming "fixed / effective / closed" must give, on the **same line**, the **commit hash** and the **result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**. If the result is false, it can only be written as "branch state / working-tree state" and **must not** be written as effective.

**Why this is not formalism**: this session measured the same thing giving **opposite conclusions** on two trees — the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) is **reviewed and signed** yet **was never an ancestor of base**, so what runs on base is the weak version: delete the real root `boring.ArraySliceOps` and add an exemption with reason `"because"`, and the weak version yields **rc=0 PASS (4 exemptions)** while the hardened version yields **rc=1** and names it verbatim. That is, "signed off" and "effective" are two different things; without stating the tree, a **nonexistent guard** gets recorded as existing.

**Three-step verification (must run before sign-off or handoff)**:
1. `git rev-parse --verify <branch>` — does the branch **exist** (this session has several rows whose `branch` field points to a **never-created** branch)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — **is it in base yet**
3. **directly read the file in the shared tree** — what form does it **actually have** in base (step 3 cannot be omitted: in this case the first two steps passed, and only the third discovered the weak version)

**After merging, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which line am I on now) **and** step 2 (is it really on the **declared base**) — this session had one case where four merges all landed on the working line while the declared base did not move, so newly opened worktrees did not get those fixes.

## Delivery side: load-bearing items must be able to answer "which commit has it"

**Rule**: tools, guards, fixtures, drivers, assertion scripts — things later people will depend on — **must be committed**; evidence can live only in reports. If a criterion depends on a file, you must also give the basis that **it is reachable in a clone** (e.g. `git ls-files --error-unmatch <path>` passes, and `git archive HEAD` can extract it).

**Two measurements this session**: ① under `dc-warn/worktrees/`, **37/37** are all detached HEAD, **all have uncommitted changes**, **none carries a commit beyond `e1c65975`** — "done in the working tree + report on file" became this batch's actual delivery convention; ② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths, making "one command rc=0" **true only for the author's working copy** and false for a clone (PIT-346). **Fix**: the manifest can **mark reachability in sections** (repo-verifiable / evidence-only), and verify in a **clean export tree containing only committed files**.

## The evidence strength of each layer must be stated separately

You **must not** conflate the three:
- "generation succeeded" (L1)
- "the generated code type-checks" (L2)
- "the runtime result is correct" (L4)

**One misjudgment this session stemmed from this**: `d14aae11` was committed with `-typecheck` 0/0 as the acceptance criterion, but that criterion cannot see the L3/L4 problems (the P4 regression is only exposed under a full build).

## Honest reporting of coverage

**Rule**: when reporting "covers N/M", you must also give **the skipped items and their reasons**.

**Example**: the P1 scoped run claimed "every P1 update's expectation was exercised", but actually **56/57** — `printed-record.test.ts:88` is only consumed in the timed-out test, so it was never executed; and the pre-existing red in `array-root.test.ts:18` means `L28` was never reached. (Lesson PIT-321)

## Timeouts and failures must be distinguished

**The criterion is "whether the subject finished running", not "whether it timed out".**

**Example**: the coupled run of `value-type` **was not killed** — `Bun.spawnSync` blocks the bun timer, took 351 s ≈ 15 runs, and the temp directory disappeared in both copies ⇒ the subject **finished running**. Reading it as "coupling masked by timeout" is wrong; the correct statement is **latent coupling** (the fix is not on the execution path of those probes at all).

## The command corresponding to each layer (current state)

| Layer | Command | Is it in CI |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | Partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | Partial |
| L3 | `swiftc -c` | **No** |
| L4 | fixture's own runner + oracle | **No** |
| L5 | Discriminating backend | **No** |
| Collection | **`bun run test` (collects `tests/**`)** | **Yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (since `9f26e1ef`): the `collected-suite` job runs the entry point `bun run test` every time, reporting the collection domain and counts; the job blocks, has no `continue-on-error`, and fails when a protected assertion is broken (negative-control proof in `dc-warn/out/ci-wire/`). **The counts already exist**, but the standard `:80` "count is zero" is **still not satisfied**: the baseline (`1001 pass / 32 fail / 8 errors`) is not yet paid down, and `BASELINE-FAILURES.md` only records, never waives. The collection domain is 303 files, of which 249 come from the generated tree `reference/ts/gen-tests`, so the job first regenerates and then collects.

## This layer is not green right now (L3 build-phase diagnostic, correction record)

**An earlier version of this file wrote, at line 12, "S1 has zeroed it (1 → 0)". That was wrong; it is corrected here while preserving the error shape, because it is exactly the kind this file's own L0 section warns about.**

The error shape: writing a **measurement on a candidate-material tree** as an **established fact on the current line**. Checked separately:

| Question | Result |
|---|---|
| Is `cd70eb12` an ancestor of `arch/agent-guided-governance` (base)? | **No** — `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` → rc=1 |
| Which branches does it appear on? | Only `prep/p08-s1-unreachable-return` (including the origin branch of the same name) — it is **candidate material** |
| Does `stmtDiverges` exist in the current tree? | **No** — `grep -rn stmtDiverges --include=*.hx packages/` → 0 hits |
| What is the diagnostic count on the current tree? | **1**, and it is **explicitly asserted to exist** by the fixture |

`tests/swift-gap-boundary/gap-boundary.test.ts` pins down this 1 warning, and its comment describes itself as "an unwaived, recorded baseline failure -- the goal remains zero diagnostics under `-c`", with the assertion `toHaveLength(1)`. So:

- **The fixture says "the defect still exists"** (a preservation needle: once the defect is actually fixed, this assertion fails and forces a recount);
- **The documentation at the time said "already zeroed"**.

Both cannot be true at once, and the measurement sides with the fixture. The "1 → 0" record in `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` describes the tree `cd70eb12` **that tree**, within which it is true; it cannot serve as a state reference for the current line. Writing a candidate-tree conclusion as line state directly conflicts with this record's L0 requirement of "must give commit + `is-ancestor` result" — and at the time that rule had no machine enforcement, so it was violated and no one noticed.

**Lesson (already written into the L0 section)**: a candidate material's measured result can only be written as "effective" when `is-ancestor` is true. Previously this file was missing exactly that step.

## L6: Conflict between criteria (added this session)

The first five layers each answer "does this criterion mislead". This layer answers a different question: **whether two individually correct criteria are mutually exclusive.** Yes, and it is completely invisible in the passing state — each criterion is green when run alone, and only putting them into the same tree exposes it.

### Example one: two criteria make opposite demands on the same predicate

There are two positive controls on Kotlin smart-cast (established by two different tasks, each independently reviewed):

| Criterion | Shape it catches | Requirement |
|---|---|---|
| `tests/haxe/kotlin-var-field-smartcast` | The guard on a mutable field does not emit `!!`, and the read path drops the assertion | A mutable field's **guard must emit `!!`** |
| `tests/kotlin/smartcast-tfield` | A reassignment (or closure rewrite) happens **between** guard and read, yet the emitter still emits a bare dot | A mutable field **does not count as proven** |

Measured (isolated one at a time, changing only one thing each time):

| Configuration | `var-field-smartcast` | `smartcast-tfield` |
|---|---|---|
| Keep the stability narrowing | **FAIL** | pass |
| Remove the stability narrowing | pass | **FAIL** |

**Both cannot be true at once, and both sides are catching a real kotlinc rejection.** The root cause is not that either side is wrong, but that **one judgment has two sources** (guard-side `smartCastableSubject`, read-side `fieldProven`) — a violation of contract 6. The disposition is to **unify the predicate**, not pick one of the two — picking one only relocates the regression.

### Example two: collapsing three states into binary silently changes semantics

In the same unification, after tightening the read-side predicate to "value proven ∧ smart-castable", the artifact regressed from `holder.value!!.magnitude()` to `holder.value?.magnitude()`.

**Both pass kotlinc**, but `!!.` is a forced extraction (throws on failure) and `?.` is a safe call (silently returns null). So the correct model here is **three states**, not binary:

| Form | Condition |
|---|---|
| Bare dot `.` | Value proven **and** will smart-cast |
| Forced `!!.` | Value proven **but** will not smart-cast |
| Safe `?.` | Value not proven |

**`?.` almost always passes kotlinc**, so "compiles" is the weakest criterion in this family: it can only squeeze the three states into "not an error" and cannot distinguish that the semantics have been swapped. **This layer's criterion must be "which of the three forms appears in the artifact", not "does it compile".**

### Example three: the same suppression mechanism "exists but covers incompletely"

For `(c > 8 && c < 14) || c == 32` in `packages/compiler/runtime/StringTools.hx`, under the premise that the source is byte-for-byte identical on the two trees:

- master `cc9957dd` → `StringTools.kt:9` = `c!! > 8 && c < 14 || c == 32` (sha256 `ced8a07374d72ffa…`)
- mainline `42c805d3` → `StringTools.kt:9` = `c!! > 8 && c!! < 14 || c == 32` (sha256 `b7b22e37bd37d24d…`)

Among the three `c`s, **only the second** emits an extra `!!`, and the third is correct. So the mechanism "repeated extraction is suppressed" **exists**, it just **covers only some read sites**.

**A dangerous criterion shape**: a test that only asserts "there is no `!!` somewhere" would be **all green**, because it hits exactly the one site the mechanism covers. To catch this class, the criterion must be **"the same subject is extracted at most once within the same expression"** — using **all** read sites of that expression as positive controls.

### Example four: the optimization hooks one form, but is re-materialized in nesting

The Rust emitter's per-char loop units precomputation (`perCharLoopInfo` in `RustExpr.hx`) has **only one call site** (`case TWhile`), and the `TFor` path has none of it — so Haxe's most common `for (i in 0...s.length)` traversal is unprotected.

But the execution seat, after measuring, gave a **more accurate mechanism** and corrected this preliminary study: the main cause is not "some loop form lacks the optimization", but that **in a nested per-char loop, the inner layer re-materializes the unit vector the outer layer already holds** — that repeated `let __units = u_string::units(&s);` lands inside the outer loop body, which is what makes it quadratic. Under this fix, **nested `TWhile` benefits equally**, not just `TFor`.

**Implication for criteria**: the entry point may ask "how many loop forms does this optimization cover", but **must keep asking "how many times is the same precomputation re-materialized across nesting levels"**. Only patching the form misses the main cause. A reusable technique: count the **occurrences** of the same `let <temp> = <expensive call>(` in the generated artifact — appearing >1 time inside a nested loop is that defect.

**It has the same structure as the previous three examples**: the criterion's observation domain (one loop form / one loop level) is **smaller than** the property it claims to cover (arbitrary per-char traversal / arbitrary nesting depth).

### This layer's criteria (for future fixtures)

1. **One judgment can have only one source**; when two criteria make opposite demands on the same predicate, first check whether there are two implementations.
2. **Enumerate artifact forms, don't just assert "it compiles"** — especially when there are equivalent-but-semantically-different spellings like `?.`/`!!.`/bare dot.
3. **For "suppression/deduplication" mechanisms, use all sites as positive controls**, don't just pick one site and assert absence.
4. Conflicts between criteria **must be recorded explicitly** (which two, under what configuration they are mutually exclusive, the measured matrix), otherwise the next person to merge will treat it as an ordinary regression.
5. **A criterion for an optimization/suppression/deduplication mechanism must unfold across two dimensions, "form × nesting depth"**, not assert its existence at a single site. Examples three and four are both failures of this shape.

## Open items

- **Whether L5's discriminating backend is written into every fixture** (currently only `branchBoundary` and the gap driver have it)
- **Whether `swiftc -c` should replace `-typecheck` as the criterion for all Swift acceptance** — evidence supports distinguishing by form (ordinary forms: `-typecheck` suffices, return-stripped forms: must use `-c`)
