# Layered Verification Scheme

Classification answers "who owns it," contracts answer "what is promised," and this document answers **which observable to use for verification at each layer**, as well as **when each criterion deceives**.

## Layers and Criteria

| Layer | Property Verified | Observable | Passing Criterion | **When This Criterion Deceives** |
|---|---|---|---|---|
| **L1 Generation** | Compiler did not crash, outputs are complete | Generation process exit code + file manifest | `rc=0` and expected files exist | **rc=0 does not mean correct output**: `:2609`'s `fail()` also reaches rc=1, but inputs that "did not hit a crash" get rc=0 with wrong output |
| **L2 Syntax/Types** | Output is legal in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 errors | **`-typecheck` does not run SILGen**: multi-statement closures with elided `return` only produce a warning; a real build fails. **Such forms must use `swiftc -c`** |
| **L3 Build** | Output can link into an executable | `swiftc -c` / `swiftc -o` | 0 errors | Build-phase diagnostics (`will never be executed`) **do not appear under `-typecheck`**. **Ruled: counted in acceptance criteria** — see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (`1a486ebd`); S1 has driven them to zero (1 → 0, counted by `file:line:col: severity` shape; `grep -c 'warning:'` would count 1 as 2 due to caret lines, PIT-336) |
| **L4 Behavior** | Runtime results are correct | Line-by-line comparison against oracle | **Byte-identical** | If the oracle itself is wrong, everything is wrong; additionally, "identical to oracle on the same input" **does not cover** properties the oracle does not express (e.g., laziness) |
| **L5 Discriminability** | The check **can** detect the target defect | Run against a deliberately-wrong backend | Deliberate error ⇒ **FAIL** | Without this layer, L1–L4 all green may only mean **the property was never observed** |

## L5 Is a Layer Added During This Session (Previously Missing)

**Instances of "the check cannot detect the target defect"**:

1. **`branchBoundary` fixture**: two branches of equal length, consumer only prints length ⇒ a backend that "always picks either branch"
   **passes every assertion**. After the fix, `branch-false=1:2:present` FAILs against the deliberately-wrong
   backend (commit `d1180768`).
2. **`swiftc -typecheck`**: misses "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Splicing-style changes**: pre/post generation trees are byte-identical ⇒ cannot distinguish "not applied" from "correctly changed".
4. **The zero-warning gate simply did not exist** (`t-mum29cli-9c9w`, `89dd80b2`): `:78/:80` requires zero warnings,
   but `package.json:21`'s `test:dart` **explicitly** carries `--no-fatal-warnings`, `:12`'s
   `test:rust` lacks `-D warnings`, and the sole CI gate `collected-suite` only greps `bun run test`
   logs which **do not contain** the five-target compiler output ⇒ **the grep domain is empty under the passing state**. The existing warning stockpile —
   Dart 46 / Kotlin 59 / Rust 4 — all exit rc=0. **A reproducible discriminability method**: inject **one** warning into the same tree,
   run the "existing command" vs. the "strict command" — `dart: loose rc=0 / strict rc=2`, `rust: loose rc=0 /
   strict rc=101`; **if both rc values are identical, that gate does not exist** (this seat made it into a re-runnable
   `verify.sh`). Fixed on branch `fix/zero-warning-gate-wiring`.
5. **"Changed the emitter" does not equal "produced different output"** (PIT-347 measured): one seat added **38 lines**
   of AST traversal bypass in `Compiler.hx`, and `diff -rq` across **the entire generation tree** showed **0 differences**, the target site
   unchanged character for character. **Discriminability method**: any emitter change must be **re-generated and the generated output diffed** to count;
   a plausible-looking source diff does not constitute evidence. (Another dispatch on the same row changed only **9 lines** and genuinely altered the site.)

**⇒ L5 operational form**: every fixture must be paired with a **deliberately-wrong backend** (picking the wrong branch, returning the wrong value,
stripping a transform), and must prove that the fixture FAILs against it. **Proving "the correct backend passes" is not verification.**
**⇒ Corollary for "gate-type" criteria**: must report the rc of **both** the loose and strict runs — reporting only "pass"
cannot distinguish "the check passed" from "there was no check."

## Every Criterion Must State "On Which Tree It Holds" (Added This Session, L0 Prerequisite)

**Rule**: any criterion claimed as "fixed / in effect / closed" must, **on the same line**, give
the **commit hash** and the **result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**.
If the result is false, write only "branch state / worktree state" and **never** write "in effect."

**Why this is not formalism**: this session measured the same artifact giving **opposite conclusions** on two trees —
the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) was **reviewed and signed off** yet was **never an ancestor of base**,
so what runs on base is the weak version: delete the real root `boring.ArraySliceOps` and add one exemption with reason `"because"`,
the weak version **rc=0 PASS (4 exemptions)**, the hardened version **rc=1** and names it verbatim.
That is, "signed off" and "in effect" are two different things; without stating the tree, a **non-existent guard** gets recorded as present.

**Three-step verification method (must run before sign-off or handoff)**:
1. `git rev-parse --verify <branch>` — does the branch **exist** (this session has several rows whose `branch` field points to a branch **never created**)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — **has it landed on base**
3. **Directly read the file on the shared tree** — what form is it **really** in on base (step 3 cannot be omitted: in this case steps 1 and 2 both passed, and step 3 was what revealed the weak version)

**After merge, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which line am I on now) **and** step 2 (is it truly on the **declared base**) —
once in this session, four merges all landed on the working line while the declared base was untouched, causing newly-opened worktrees not to receive those fixes.

## Delivery Surface: Load-Bearing Artifacts Must Answer "Which Commit Contains It"

**Rule**: tools, guards, fixtures, drivers, assertion scripts — anything that later people will depend on — **must be checked into the repo**;
evidence may be report-only. If a criterion depends on a file, it must also give the basis for **its reachability in a clone**
(e.g., `git ls-files --error-unmatch <path>` passes and `git archive HEAD` can retrieve it).

**Two measurements from this session**: ① under `dc-warn/worktrees/`, **37/37** are all detached HEADs, **all have uncommitted changes**,
**not one carries a commit beyond `e1c65975`** — "done in a worktree + report on file" became the de facto delivery contract for this batch;
② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths,
making "one command rc=0" **true only for the author's working copy** and false for a clone (PIT-346).
**Fix**: the manifest may **sectionally annotate reachability** (repo-verifiable / evidence-only), and must be verified in a **clean export tree containing only committed files**.

## Evidence Strength at Each Layer Must Be Stated Separately

**Never** conflate these three:
- "Generation succeeded" (L1)
- "Generated code type-checks" (L2)
- "Runtime results are correct" (L4)

**One misjudgment in this session originated from this**: `d14aae11` was submitted with `-typecheck` 0/0 as the acceptance criterion,
and that criterion cannot see problems at the L3/L4 layers (the P4 regression is only exposed under a full build).

## Honest Coverage Reporting

**Rule**: when reporting "covered N/M," must also give **the skipped items and their reasons**.

**Instance**: the P1 scoped run claimed "every P1-updated expectation was exercised,"
but actually **56/57** — `printed-record.test.ts:88` is only consumed in a test that times out,
and was therefore never executed; while the pre-existing red at `array-root.test.ts:18` meant `L28` was never reached.
(lesson PIT-321)

## Timeouts and Failures Must Be Distinguished

**The criterion is "did the subject finish running," not "did it time out."**

**Instance**: the coupled run for `value-type` was **not killed** — `Bun.spawnSync` blocks the bun timer,
taking 351 s ≈ 15 runs, the temporary directory disappeared in both replicas ⇒ the subject **finished running**.
Reading it as "coupling masked by timeout" is wrong; the correct description is **latent coupling**
(the fix was not on the execution path of those probes at all).

## Commands Corresponding to Each Layer (Current State)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | Partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | Partial |
| L3 | `swiftc -c` | **No** |
| L4 | Fixture-internal runner + oracle | **No** |
| L5 | Discriminative backend | **No** |
| Collection | **`bun run test` (collects `tests/**`)** | **Yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (since `9f26e1ef`): the `collected-suite` job runs `bun run test` as its entry point on every invocation,
reporting the collection domain and count; this job blocks, has no `continue-on-error`, and a broken protected assertion causes failure
(negative-control proof at `dc-warn/out/ci-wire/`). **Counting exists**, but the standard `:80`
"count is zero" **is still not met**: baseline (`1001 pass / 32 fail / 8 errors`) is not yet cleared,
and `BASELINE-FAILURES.md` records only, does not exempt. The collection domain is 303 files, 249 of which come from
the generation tree `reference/ts/gen-tests`, so the job regenerates before collecting.

## Open

- **Whether L3 build-phase diagnostics count toward acceptance** (`t-muo92xms-s28t`, unclaimed)
- **Whether L5 discriminative backends are written for every fixture** (currently only `branchBoundary` and gap drivers have them)
- **Whether `swiftc -c` should replace `-typecheck` as the acceptance standard for all Swift verification** —
  evidence supports distinguishing by form (normal forms: `-typecheck` suffices; return-eliding forms: `-c` is mandatory)
