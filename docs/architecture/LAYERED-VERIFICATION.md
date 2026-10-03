# Layered Verification Plan

Classification says "who owns what", contracts say "what is promised", and this document says **what observable each layer verifies against**,
and **when each criterion deceives you**.

## Layers and Criteria

| Layer | Property under test | Observable | Pass criterion | **When this criterion deceives** |
|---|---|---|---|---|
| **L1 Generation** | Compiler did not crash, artifacts complete | Generation process exit code + file list | `rc=0` and expected files exist | **rc=0 does not mean the artifact is correct**: the `fail()` at `:2609` also reaches rc=1, but an input that "does not reach the crash" returns rc=0 while outputting wrong results |
| **L2 Syntax/Types** | Artifact is valid in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` does not run SILGen**: a multi-statement closure with `return` stripped only reports a warning; only a real build fails. **This form must use `swiftc -c`** |
| **L3 Build** | Artifact links into an executable | `swiftc -c` / `swiftc -o` | 0 error | Build-phase diagnostics (`will never be executed`) **do not appear under `-typecheck`**. **Already ruled: counted into the acceptance criteria** — see the `t-muo92xms-s28t` ruling (`1a486ebd`; the original file `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` was deleted with the repo cleanup; the ruling content is in that row's note in the wb system). **The current fact for this entry is "not yet zeroed"**: that diagnostic count is still **1**, and it is an **unwaived, recorded baseline failure** — see the next section "This layer is not currently green" |
| **L4 Behavior** | Runtime result is correct | Line-by-line comparison against the oracle | **Byte-for-byte identical** | If the oracle itself is wrong, everything is wrong; and "matches the oracle under the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 Discrimination** | The check **can** find the target defect | Run against a deliberately wrong backend | Deliberate error ⇒ **FAIL** | Without this layer, L1–L4 all green may only mean **that property was never observed** |

## L5 is a layer added by this session (previously missing)

**Instances of "a check cannot find the target defect"**:

1. **The `branchBoundary` fixture**: the two branches have equal length and the consumer only prints the length ⇒ a backend that "always takes either branch"
   **passes all assertions**. After the fix, `branch-false=1:2:present` FAILs against the deliberately wrong
   backend (commit `d1180768`).
2. **`swiftc -typecheck`**: misses "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Concatenation-type changes**: the generated tree is byte-identical pre/post ⇒ cannot distinguish "not applied" from "changed correctly".
4. **The zero-warning gate does not exist at all** (`t-mum29cli-9c9w`, `89dd80b2`): `:78/:80` require zero warnings,
   but `package.json:21`'s `test:dart` **explicitly** carries `--no-fatal-warnings`, and `:12`'s
   `test:rust` has no `-D warnings`, and the CI's only gate `collected-suite` merely greps the `bun run test`
   log, which **does not contain** the five-target compiler output ⇒ **the grep domain is empty in the passing state**. The existing warning backlog
   — Dart 46 / Kotlin 59 / Rust 4 — all return rc=0. **A reproducible discriminating method**: inject **one** warning into the same tree,
   run the "existing command" and the "strict command" — `dart: loose rc=0 / strict rc=2`, `rust: loose rc=0 /
   strict rc=101`; **if the two rc values are identical, that gate does not exist** (that seat turned it into a re-runnable `verify.sh`, now at the archive `boring-docs-archive/evidence/zero-warning-gate-coverage/verify.sh`). Fix branch `fix/zero-warning-gate-wiring`.
5. **"Changed the emitter" does not mean a different artifact was generated** (PIT-347 measured): one seat added a
   **38-line** AST-traversal bypass in `Compiler.hx`, yet `diff -rq` over the **entire generated tree** showed **0 differences** and the target site
   was byte-for-byte unchanged. **Discriminating method**: any emitter change must **regenerate and diff the generated output** to count;
   a source diff that looks plausible is not evidence. (Another re-dispatch on the same row changed only **9 lines** but genuinely changed the site.)

**⇒ L5's operating form**: every fixture must be paired with a **deliberately wrong backend** (takes the wrong branch, returns the wrong value,
strips the conversion), and must prove that the fixture FAILs on it. **Proving only that "the correct backend passes" is not verification.**
**⇒ Corollary for "gate-type" criteria**: you must give the rc of **both** the loose and the strict run — reporting only "pass"
cannot distinguish "the check passed" from "there was no check".

## Every criterion must state "on which tree it holds" (new in this session, L0 prerequisite)

**Rule**: any criterion claiming "fixed / in effect / closed" must, on the **same line**, give the
**commit hash** and the **result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**.
If the result is false, it may only be written as "branch state / working-tree state", and must **not** be written as in effect.

**Why this is not formalism**: this session measured the same thing giving **opposite conclusions** on two trees —
the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) **was reviewed and signed off** yet **was never an ancestor of base**,
so what runs on base is the weak version: delete the real root `boring.ArraySliceOps` and add an exemption with reason `"because"`
— the weak version gives **rc=0 PASS (4 exemptions)** while the hardened version gives **rc=1** and names it verbatim.
So "signed off" and "in effect" are two different things; without naming the tree, a **nonexistent safeguard** gets recorded as existing.

**Three-step verification method (must run before sign-off or takeover)**:
1. `git rev-parse --verify <branch>` — does that branch **exist** (this session has several rows whose `branch` field points to a branch that was **never created**)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — **did it get into base**
3. **Directly read the file in the shared tree** — what form does base **actually** hold (step 3 cannot be skipped: in this case the first two steps passed, and only step 3 revealed the weak version)

**After merging, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which line am I on now) **and** step 2 (is it really on the **declared base**) —
this session had one case where all four merges landed on the work line while the declared base was untouched, so newly opened worktrees did not get those fixes.

## Delivery side: load-bearing artifacts must answer "which commit contains it"

**Rule**: tools, guardrails, fixtures, drivers, assertion scripts — anything later people will depend on — **must be committed to the repo**;
evidence may live only in reports. If a criterion depends on a file, you must also give the basis that **it is reachable in a clone**
(for example, `git ls-files --error-unmatch <path>` passes, and `git archive HEAD` can extract it).

**Two measurements this session**: ① under `dc-warn/worktrees/`, **37/37** are all detached HEAD, **all have uncommitted changes**, and
**none carries a commit beyond `e1c65975`** — "done in the worktree + report on file" became this batch's de facto delivery convention;
② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths,
making "one command rc=0" **true only for the author's working copy** and false for a clone (PIT-346).
**Fix**: the manifest may **mark reachability by section** (repo-verifiable / evidence-only), and verify it in a **clean exported tree containing only committed files**.

## Each layer's evidence strength must be stated separately

**Must not** conflate the three:
- "generation succeeded" (L1)
- "the generated code type-checks" (L2)
- "the runtime result is correct" (L4)

**One misjudgment this session originated here**: committed `d14aae11` using `-typecheck` 0/0 as the acceptance criterion,
but that criterion cannot see L3/L4-layer problems (the P4 regression only surfaces under a full build).

## Honest reporting of coverage

**Rule**: when reporting "covers N/M", you must also give **the skipped items and their reasons**.

**Instance**: the P1 scoped run claimed "every P1 update's expectation is exercised",
but actually **56/57** — `printed-record.test.ts:88` is only consumed in a test that times out,
so it never executes; and the pre-existing red at `array-root.test.ts:18` means `L28` is never reached.
(Lesson PIT-321)

## Timeouts and failures must be distinguished

**The criterion is "did the subject finish running", not "did it time out".**

**Instance**: the coupled run of `value-type` was **not killed** — `Bun.spawnSync` blocks bun's timers,
taking 351 s ≈ 15 runs, and the temp directory disappeared in both replicas ⇒ the subject **did finish running**.
Reading it as "coupling masked by a timeout" is wrong; the correct description is **latent coupling**
(the fix is simply not on those probes' execution path).

## Commands corresponding to each layer (current state)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | Partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | Partial |
| L3 | `swiftc -c` | **No** |
| L4 | Fixture's own runner + oracle | **No** |
| L5 | Discriminating backend | **No** |
| Collection | **`bun run test` (collects `tests/**`)** | **Yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (since `9f26e1ef`): the `collected-suite` job runs the entry `bun run test` every time,
reporting the collection domain and count; the job blocks, has no `continue-on-error`, and fails when a protected assertion breaks
(negative-control proof in `dc-warn/out/ci-wire/`). **The count already exists**, but the standard `:80`'s
"count is zero" **is still not met**: the baseline (`1001 pass / 32 fail / 8 errors`) is not yet cleared,
and the baseline ledger (originally `BASELINE-FAILURES.md`, deleted 2026-10-03 with the cleanup; the current record is the baseline wiring in `.github/workflows/ci.yml`) only records, never waives. The collection domain is 303 files, of which 249 come from
the generated tree `reference/ts/gen-tests`, so the job regenerates before collecting.

## This layer is not currently green (L3 build-phase diagnostics, correction record)

**An earlier version of this document wrote, at line 12, "S1 made it zero (1 → 0)". That was wrong; it is corrected here while preserving the
wrong shape, because it is exactly the kind this document's own L0 section warns about.**

The wrong shape: writing a **measurement on a candidate-material tree** as an **established fact on the current line**. Verify each separately:

| Question | Result |
|---|---|
| Is `cd70eb12` an ancestor of `arch/agent-guided-governance` (base)? | **No** — `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` → rc=1 |
| Which branches does it appear on? | Only `prep/p08-s1-unreachable-return` (including the same-named origin branch) — it is a piece of **candidate material** |
| Does `stmtDiverges` exist in the current tree? | **No** — `grep -rn stmtDiverges --include=*.hx packages/` → 0 hits |
| What is the diagnostic count on the current tree? | **1**, and the fixture **explicitly asserts it must exist** |

`tests/swift-gap-boundary/gap-boundary.test.ts` pins this one warning, and its comment describes itself as
"an unwaived, recorded baseline failure -- the goal remains zero diagnostics under
`-c`", with the assertion `toHaveLength(1)`. So:

- **The fixture says "the defect remains"** (an anti-rot pin: once the defect is actually fixed, this assertion fails and forces a re-read of the count);
- **The document at that time said "already zeroed"**.

The two cannot both be true, and the measurement sides with the fixture. In the build-phase diagnostic ruling (originally `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`, deleted with the cleanup, traceable via `1a486ebd`),
the "1 → 0" record describes **that tree** of `cd70eb12`, where it is true; it cannot be cited as the current line's state.
Writing a candidate-tree conclusion as line state directly conflicts with this record's L0 section requirement of "must give commit + `is-ancestor` result"
— and that rule had no machine enforcement at the time, so it was violated and nobody noticed.

**Lesson (already written into the L0 section)**: a candidate material's measured result may only be written as
"in effect" when `is-ancestor` is true. Previously this document was missing exactly that step.

## L6: Conflicts between criteria (new in this session)

The first five layers each answer "does this criterion deceive". This layer answers a different question:
**whether two individually correct criteria can be mutually exclusive.** They can, and it is completely invisible in the passing state — each criterion
is green when run alone, and only putting them into the same tree exposes it.

### Instance one: two criteria impose opposite requirements on the same predicate

On Kotlin smart-casting there are two positive controls (established by two different tasks, each independently re-reviewed):

| Criterion | Shape it catches | Requirement |
|---|---|---|
| `tests/haxe/kotlin-var-field-smartcast` | A mutable field's guard does not emit `!!`, and the read path drops the assertion | A mutable field's **guard must emit `!!`** |
| `tests/kotlin/smartcast-tfield` | A reassignment (or closure rewrite) happens **between** the guard and the read, and the emitter still emits a bare dot | A mutable field **does not count as proven** |

Measured (isolated one at a time, changing only one spot each run):

| Configuration | `var-field-smartcast` | `smartcast-tfield` |
|---|---|---|
| Keep the stability narrowing | **FAIL** | pass |
| Remove the stability narrowing | pass | **FAIL** |

**The two cannot both be true, and both sides are catching real kotlinc rejections.** The root cause is not that either side is wrong,
but that **one judgment has two sources** (guard-side `smartCastableSubject`, read-side `fieldProven`),
i.e. a violation of contract 6. The disposition is to **unify the predicate**, not to pick one — picking one just moves the regression elsewhere.

### Instance two: collapsing three states into binary silently changes semantics

In the same unification, after tightening the read-side predicate to "value proven ∧ can smart-cast", the output regressed from
`holder.value!!.magnitude()` to `holder.value?.magnitude()`.

**Both pass kotlinc**, but `!!.` is a forced extraction (throws on failure) and `?.` is a safe call (silently returns null).
So the correct model here is **three states**, not binary:

| Form | Condition |
|---|---|
| Bare dot `.` | Value proven **and** will smart-cast |
| Forced `!!.` | Value proven **but** will not smart-cast |
| Safe `?.` | Value not proven |

**`?.` almost always lets kotlinc pass**, so "compiles" is the weakest criterion in this family:
it can only compress the three states into "not an error" and cannot distinguish that the semantics have been swapped. **This layer's criterion must be
"which of the three forms appears in the output", not "does it compile".**

### Instance three: the same suppression mechanism "exists but with incomplete coverage"

The `(c > 8 && c < 14) || c == 32` in `packages/compiler/runtime/StringTools.hx`,
under the premise that the source is byte-identical on the two trees:

- master `cc9957dd` → `StringTools.kt:9` = `c!! > 8 && c < 14 || c == 32` (sha256 `ced8a07374d72ffa…`)
- main line `42c805d3` → `StringTools.kt:9` = `c!! > 8 && c!! < 14 || c == 32` (sha256 `b7b22e37bd37d24d…`)

Among the three `c`'s, **only the second** emits an extra `!!`, and the third is correct. So the "repeated extraction is suppressed" mechanism
**exists**, only it **covers part of the read sites**.

**A dangerous criterion shape**: a test that only asserts "there is no `!!` somewhere" would be **all green**, because it hits exactly
the one site the mechanism covers. To catch this class, the criterion must be
**"the same subject within the same expression is extracted at most once"** — using **all** read sites of that expression as positive controls.

### Instance four: an optimization hooks onto one form, and is repeatedly materialized inside nesting

The Rust emitter's per-char loop-units precomputation (`perCharLoopInfo` in `RustExpr.hx`)
**has only one call site** (`case TWhile`), and the `TFor` path has none of it — so Haxe's most common
`for (i in 0...s.length)` iteration is unprotected.

But after measurement the execution seat gave a **more accurate mechanism** and corrected this preliminary finding: the main cause is not "a loop form lacks the optimization",
but that **in a nested per-char loop, the inner layer re-materializes the unit vector the outer layer already holds** —
that duplicate `let __units = u_string::units(&s);` lands inside the outer loop body, which is what makes it quadratic.
Under this fix, **a nested `TWhile` benefits equally**, not just `TFor`.

**Implication for the criterion**: the entry point may ask "how many loop forms does this optimization cover", but it **must keep asking
"how many times the same precomputation is re-materialized across nesting levels"**. Patching only the form misses the main cause.
Reusable technique: count the **number of occurrences** of the same `let <temp> = <expensive call>(` in the generated output —
appearing >1 time in a nested loop is that defect.

**It shares the same structure as the previous three instances**: the criterion's observation domain (one loop form / one loop level) is **smaller than**
the property it claims to cover (any per-char iteration / any nesting depth).

### Instance five: audit-type guardrails define "covered" by location, not by reference

The previous four instances concern **product criteria** (emission / optimization / suppression). The fifth concerns the **audit-type guardrail itself**:
its criterion is "has this fixture been collected", and it implements that sentence as "is there, **inside** the fixture directory, a
`*.test.ts`".

Thus a fixture whose test lives under `tests/<target>/` and drives the hxml in the fixture directory is judged "unwatched".
The measured blind spot had **3** entries: `dc-promoted-eval`, `swift-package-shell-emit`
(driven by `tests/ts/package-shell.test.ts:388`), `kotlin-smartcast-tfield`
(driven by `tests/kotlin/smartcast-tfield.test.ts:74`). After changing the criterion to "a test inside the directory **or**
any collected test mentioning the fixture path", the count went 37 → 34.

**The reason it deserves a separate listing**: this is the "observation domain smaller than the claimed scope" at the **meta level** — not a product
criterion deceiving, but **the guardrail responsible for detecting criteria that deceive** itself deceiving. It is more concealed than the previous four, because
the number it produces looks concrete (37 uncollected fixtures), and concreteness is easily mistaken for correctness.

**When relaxing such a guardrail you must do two cross-checks** (missing either is rubber-stamping):
1. Print the **real reference** that makes each item "pass" (the matching test file and line number);
2. Confirm **true orphans are still counted** — in this example `kotlin-mutable-chain-probe` has no test reference anywhere,
   and remains uncollected after the relaxation.

### This layer's criteria (for future fixtures)

1. **One judgment can have only one source**; when two criteria impose opposite requirements on the same predicate, first check whether there are two implementations.
2. **Enumerate the output forms, don't just assert "it compiles"** — especially when `?.`/`!!`/bare-dot forms exist that are equivalent but semantically different.
3. **For "suppression/deduplication"-type mechanisms, use all sites as positive controls**, don't pick one site and assert absence.
4. Conflicts between criteria **must be explicitly recorded** (which two, under what configuration they are mutually exclusive, the measured matrix),
   otherwise the next person to merge will treat it as an ordinary regression.
5. **An optimization/suppression/deduplication mechanism's criterion must expand along two dimensions, "form × nesting depth"**,
   not assert its existence at a single site. Instance three and instance four are both failures of this shape.

## Unresolved

- **Whether L5's discriminating backend is written into every fixture** (currently only `branchBoundary` and the gap driver have it)
- **Whether `swiftc -c` should replace `-typecheck` as the criterion for all Swift acceptance** —
  the evidence supports distinguishing by form (ordinary forms: `-typecheck` suffices; forms that strip `return`: must use `-c`)
