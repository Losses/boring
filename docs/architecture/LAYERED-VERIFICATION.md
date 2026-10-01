# Layered Verification Plan

Categories say "who is responsible", contracts say "what is promised"; this document says **which observable quantity each layer uses to verify**,
and **when each criterion lies**.

## Layers and Criteria

| Layer | Property Under Test | Observable Quantity | Passing Criterion | **When This Criterion Lies** |
|---|---|---|---|---|
| **L1 Generation** | Compiler did not crash, artifacts are complete | Generation process exit code + file manifest | `rc=0` and expected files exist | **rc=0 does not mean the artifact is correct**: `:2609` `fail()` also reaches rc=1, but for inputs that "did not trigger a crash", rc=0 with wrong output |
| **L2 Syntax/Types** | Artifact is legal in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` does not run SILGen**: multi-statement closures with a stripped `return` only emit a warning but fail a real build. **Such forms MUST use `swiftc -c`** |
| **L3 Build** | Artifact can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 error | Build-time diagnostics (`will never be executed`) **do not appear under `-typecheck`**. **Ruled: counted as acceptance criteria** — see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (`1a486ebd`). **The current fact for this entry is "not zeroed"**: the diagnostic count is still **1**, which is an **unwaived, recorded baseline failure**; see the section below "This layer is not currently green" |
| **L4 Behavior** | Runtime result is correct | Line-by-line comparison against an oracle | **Byte-identical** | If the oracle itself is wrong, everything is wrong; also, "identical to oracle under the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 Discrimination** | The check **can** detect the target defect | Run against an intentionally wrong backend | Intentional error ⇒ **FAIL** | Without this layer, L1–L4 all green may only mean **the property is not observed** |

## L5 is a layer added in this session (previously absent)

**"Check cannot detect the target defect" — instances**:

1. **`branchBoundary` fixture**: two branches equal length, consumer only prints length ⇒ a backend that
   "always picks either branch" **passes all assertions**. After fix, `branch-false=1:2:present` FAILs
   against an intentionally wrong backend (commit `d1180768`).
2. **`swiftc -typecheck`**: missed "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Splicing-style changes**: pre/post generation tree byte-identical ⇒ cannot distinguish "not applied" from "correctly changed".
4. **Zero-warning gate did not exist at all** (`t-mum29cli-9c9w`, `89dd80b2`): `:78/:80` required zero warnings,
   but `package.json:21` `test:dart` **explicitly** carries `--no-fatal-warnings`, `:12`
   `test:rust` lacks `-D warnings`, and CI's only gate `collected-suite` merely greps `bun run test`
   logs while those logs **do not include** the five-target compiler output ⇒ **grep domain is empty in the passing state**. Existing warning backlog
   Dart 46 / Kotlin 59 / Rust 4 all rc=0. **Reproducible discrimination method**: inject **one** warning into the same tree,
   run both the "existing command" and the "strict command" — `dart: loose rc=0 / strict rc=2`, `rust: loose rc=0 /
   strict rc=101`; **if both rc are identical, the gate does not exist** (this party turned it into a re-runnable
   `verify.sh`). Fix on `fix/zero-warning-gate-wiring`.
5. **"Changed the emitter" does not equal generated different output** (PIT-347 measured): one party added **38 lines**
   of AST traversal bypass in `Compiler.hx`, `diff -rq` across the **entire generation tree** showed **0 differences**, the target site
   unchanged by a single character. **Discrimination method**: any emitter change must **regenerate and diff the generated artifacts** to count;
   source diffs looking plausible do not constitute evidence. (Another dispatch on the same row changed only **9 lines** yet genuinely altered the site.)

**⇒ L5 operational form**: every fixture must be paired with an **intentionally wrong backend** (picking the wrong branch, returning the wrong value,
stripping a transform), and prove that the fixture FAILs against it. **Proving "the correct backend passes" is not verification.**
**⇒ Corollary for "gate-type" criteria**: must report **both** loose and strict run rc — reporting only "pass"
cannot distinguish "the check passed" from "there was no check".

## Every criterion must state "on which tree it holds" (added in this session, L0 prerequisite)

**Rule**: any criterion claimed as "fixed / in effect / closed" MUST provide in the **same line**
the **commit hash** AND the **result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**.
If the result is false, it may only be written as "branch state / worktree state" and **must not** be written as in effect.

**Why this is not formalism**: this session measured that the same thing gave **opposite conclusions** on two trees —
the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) was **reviewed and signed off** yet **was never an ancestor of base**,
so what runs on base is the weak version: delete the real root `boring.ArraySliceOps` and add an exemption with reason `"because"`,
weak version **rc=0 PASS (4 exemptions)**, hardened version **rc=1** naming it verbatim.
That is, "signed off" and "in effect" are two different things; without stating the tree, a **non-existent guard** gets recorded as existing.

**Three-step verification (mandatory before sign-off or handoff)**:
1. `git rev-parse --verify <branch>` — does that branch **exist** (this session has several rows whose `branch` field points to branches **never created**)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — **has it landed on base**
3. **Directly read the file in the shared tree** — what **exact form** does it have on base (step 3 cannot be skipped: in this case the first two steps both passed, and only step 3 revealed it was the weak version)

**After merge, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which line am I on now) **and** step 2 (is it really on the **declared base**) —
in this session four merges all landed on the working line once while the declared base was untouched, so newly opened worktrees could not get those fixes.

## Delivery side: load-bearing artifacts must answer "which commit has it"

**Rule**: tools, guards, fixtures, drivers, assertion scripts — things downstream users will depend on — **must land in the repo**;
evidence may be report-only. If a criterion depends on a file, it must also state **evidence that it is reachable from a clone**
(e.g. `git ls-files --error-unmatch <path>` passes, and `git archive HEAD` can extract it).

**Two measurements from this session**: ① `dc-warn/worktrees/` — **37/37** all detached HEAD, **all have uncommitted changes**,
**none carries a commit beyond `e1c65975`** — "done in worktree + report on file" became the actual delivery convention for this batch;
② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths,
making "one command rc=0" **only true on the author's working copy** and false on a clone (PIT-346).
**Fix**: manifest may **annotate reachability by section** (repo-verifiable / evidence-only), and verify in a **clean export tree containing only committed files**.

## Evidence strength per layer must be stated separately

**Do not** conflate these three:
- "Generation succeeded" (L1)
- "Generated code type-checks" (L2)
- "Runtime result is correct" (L4)

**One misjudgment in this session originated from this**: `d14aae11` was submitted with `-typecheck` 0/0 as acceptance criteria,
and that criterion cannot see L3/L4 layer problems (P4 regression only exposed under a full build).

## Honest reporting of coverage

**Rule**: when reporting "covered N/M", you must also state **the skipped items and the reason for each**.

**Instance**: P1 scoped run claimed "every P1 updated expectation is exercised",
in fact **56/57** — `printed-record.test.ts:88` is only consumed inside a timed-out test,
so it was never executed; and the pre-existing red at `array-root.test.ts:18` made `L28` never reached.
(lesson PIT-321)

## Timeout and failure must be distinguished

**The criterion is "did the subject finish", not "did it time out".**

**Instance**: the coupled run of `value-type` was **not killed** — `Bun.spawnSync` blocks bun timers,
took 351 s ≈ 15 runs, the temp directory disappeared in both replicas ⇒ the subject **finished**.
Reading it as "coupling masked by timeout" is wrong; the correct description is **latent coupling**
(the fix is simply not on the execution path of those probes).

## Commands corresponding to each layer (current state)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | Partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | Partial |
| L3 | `swiftc -c` | **No** |
| L4 | Fixture's own runner + oracle | **No** |
| L5 | Discriminative backend | **No** |
| Collection | **`bun run test` (collects `tests/**`)** | **Yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (from `9f26e1ef` onward): the `collected-suite` job runs entry point `bun run test` each time,
reporting collection domain and counts; that job blocks, has no `continue-on-error`, and breaking a protected assertion means failure
(negative-control proof at `dc-warn/out/ci-wire/`). **Counting already exists**, but the standard `:80`
"count is zero" **is still not satisfied**: the baseline (`1001 pass / 32 fail / 8 errors`) has not been cleared,
`BASELINE-FAILURES.md` only records, does not waive. Collection domain is 303 files, of which 249 come from
the generation tree `reference/ts/gen-tests`, so that job regenerates first then collects.

## This layer is not currently green (L3 build-time diagnostic, correction record)

**An earlier version of this file wrote on line 12 "S1 has zeroed it (1 → 0)". That was wrong; it is corrected here, and the wrong
shape is preserved, because it is precisely the kind this file's own L0 section warns about.**

The wrong shape: writing a **measurement on a candidate material tree** as if it were **an established fact on the current line**. Separate verification:

| Question | Result |
|---|---|
| Is `cd70eb12` an ancestor of `arch/agent-guided-governance` (base)? | **No** — `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` → rc=1 |
| On which branches does it appear? | Only `prep/p08-s1-unreachable-return` (including the origin branch of the same name) — it is a **candidate material** |
| Does `stmtDiverges` exist in the current tree? | **No** — `grep -rn stmtDiverges --include=*.hx packages/` → 0 hits |
| What is the diagnostic count on the current tree? | **1**, and the fixture **explicitly asserts it must be present** |

`tests/swift-gap-boundary/gap-boundary.test.ts` pins this 1 warning, its comment self-describing as
"an unwaived, recorded baseline failure -- the goal remains zero diagnostics under
`-c`", with the assertion `toHaveLength(1)`. Therefore:

- **The fixture says "the defect remains"** (a preservative pin; if the defect is genuinely fixed, this assertion will fail and force a recount);
- **The document at that time said "zeroed"**.

Both cannot be true; measurement sides with the fixture. In `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`,
the "1 → 0" record describes **that tree** of `cd70eb12`; within that tree it is true; it cannot be cited as the state of the current line.
Writing a candidate tree conclusion as line state directly conflicts with this record's L0 section requirement of "must provide commit + `is-ancestor` result" —
and at the time this rule had no machine enforcement, so it was violated and nobody noticed.

**Lesson (written into L0 section)**: a measurement result from a candidate material may only be written as
"in effect" when `is-ancestor` is true. Previously this file lacked precisely that step.

## L6: Conflicts between criteria (added in this session)

The first five layers each answer "can this criterion lie". This layer answers a different question:
**can two individually correct criteria contradict each other.** They can, and it is completely invisible in the passing state — each criterion
run individually is green; only placing them in the same tree exposes it.

### Instance 1: two criteria make opposite demands on the same predicate

There are two positive controls on Kotlin smart-casting (established by two different tasks, each independently reviewed):

| Criterion | Shape caught | Demand |
|---|---|---|
| `tests/haxe/kotlin-var-field-smartcast` | Guard on mutable field does not emit `!!`, read path drops the assertion | Guard on mutable field **must emit `!!`** |
| `tests/kotlin/smartcast-tfield` | Reassignment (or closure mutation) occurs **between** guard and read, emitter still emits bare dot | Mutable field **does not count as proven** |

Measured (isolated one at a time, changing only one thing each time):

| Configuration | `var-field-smartcast` | `smartcast-tfield` |
|---|---|---|
| Keep stability narrowing | **FAIL** | pass |
| Remove stability narrowing | pass | **FAIL** |

**Both cannot be true simultaneously, and both sides are catching real kotlinc rejections.** The root cause is not that either side wrote it wrong,
but that **one judgment has two sources** (guard-side `smartCastableSubject`, read-side `fieldProven`),
i.e. a violation of contract 6. The remedy is **unifying the predicate**, not picking one — picking one just relocates the regression.

### Instance 2: collapsing ternary to binary silently changes semantics

In the same unification, after tightening the read-side predicate to "value proven ∧ smart-castable", the artifact regressed from
`holder.value!!.magnitude()` to `holder.value?.magnitude()`.

**Both pass kotlinc**, but `!!.` is forced extraction (throws on failure), `?.` is safe call (silently returns null).
So the correct model here is **ternary**, not binary:

| Form | Condition |
|---|---|
| Bare dot `.` | Value proven **and** will smart-cast |
| Forced `!!.` | Value proven **but** will not smart-cast |
| Safe `?.` | Value not proven |

**`?.` almost always gets past kotlinc**, so "compilation passes" is the weakest criterion in this family:
it can only collapse ternary into "not error", cannot distinguish that semantics has been swapped. **The criterion at this layer must be
"which of the three forms appears in the artifact", not "does it compile".**

### Instance 3: the same suppression mechanism "exists but is incomplete"

`packages/compiler/runtime/StringTools.hx` `(c > 8 && c < 14) || c == 32`,
given that the source code two trees are byte-identical:

- master `cc9957dd` → `c!! > 8 && c < 14 || c == 32`
- mainline `42c805d3` → `c!! > 8 && c!! < 14 || c == 32`

Of the three `c` occurrences, only the **second** emits an extra `!!`, the third is correct. So the mechanism "repeat extraction is suppressed"
**exists**, it just **covers only some read sites**.

**Dangerous criterion shape**: a test asserting only "there is no `!!` somewhere" would be **all green**, because it hits precisely
the site the mechanism does cover. To catch this class, the criterion must be
**"at most one extraction of the same subject within the same expression"** — using **all** read sites of that expression for positive control.

### Criteria for this layer (for future fixtures)

1. **A single judgment can only have one source**; when two criteria make opposite demands on the same predicate, first check whether there are two implementations.
2. **Enumerate artifact forms, do not only assert "compiles"** — especially when `?.`/`!!`/bare-dot exist as equivalent forms with different semantics.
3. **For "suppression/dedup" mechanisms, use all sites for positive control**, do not pick a single site and assert absence.
4. Conflicts between criteria **must be explicitly recorded** (which two, under what configuration they are mutually exclusive, measured matrix),
   otherwise the next person merging will treat it as an ordinary regression.

## Open

- **Whether L5's discriminative backend is written into every fixture** (currently only `branchBoundary` and the gap driver have it)
- **Whether `swiftc -c` should replace `-typecheck` as the acceptance baseline for all Swift verification** —
  evidence supports distinguishing by form (ordinary forms `-typecheck` is sufficient, return-stripped forms must use `-c`)
