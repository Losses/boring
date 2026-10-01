# Layered Verification Scheme

Classification says "who owns it", contracts say "what is promised", this document says **what observable quantity each layer uses for verification**,
and **when each criterion will deceive you**.

## Layering and Criteria

| Layer | Property Under Test | Observable | Pass Criterion | **When This Criterion Deceives** |
|---|---|---|---|---|
| **L1 Generation** | Compiler did not crash, outputs are complete | Generation process exit code + file manifest | `rc=0` and expected files exist | **rc=0 does not mean output is correct**: `fail()` at `:2609` also leads to rc=1, but inputs that "did not reach a crash" get rc=0 while output is wrong |
| **L2 Syntax/Type** | Output is legal in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` does not run SILGen**: multi-statement closures with stripped `return` only report warnings; the real build fails. **Such forms must use `swiftc -c`** |
| **L3 Build** | Output can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 error | Build-phase diagnostics (`will never be executed`) **do not appear under `-typecheck`**. **Ruled: included in acceptance criteria** — see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (`1a486ebd`). **The current fact of this entry is "not yet zero"**: the diagnostic count remains **1**, it is an **unwaived, recorded baseline failure**, see next section "This layer is currently not green" |
| **L4 Behavior** | Runtime results are correct | Line-by-line comparison against oracle | **Byte-for-byte identical** | If the oracle itself is wrong, everything is wrong; and "identical to oracle on the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 Discriminability** | The check **can** discover the target defect | Run against an intentionally wrong backend | Intentional error ⇒ **FAIL** | Without this layer, L1–L4 all green may only mean **the property is not being observed** |

## L5 is a layer this session added (previously missing)

**Instances of "check cannot discover the target defect"**:

1. **`branchBoundary` fixture**: two branches are equal-length, consumer only prints length ⇒ a "always-take-either-branch" backend **passes all assertions**. After fix `branch-false=1:2:present` FAILs against an intentionally wrong backend (commit `d1180768`).
2. **`swiftc -typecheck`**: fails to report "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Splice-type modifications**: generated tree pre/post byte-for-byte identical ⇒ cannot distinguish "did not take effect" from "was fixed correctly".
4. **The zero-warning gate simply does not exist** (`t-mum29cli-9c9w`, `89dd80b2`): `:78/:80` requires zero warnings, but `package.json:21`'s `test:dart` **explicitly** carries `--no-fatal-warnings`, `:12`'s `test:rust` has no `-D warnings`, the sole CI gate `collected-suite` only greps `bun run test` log which **does not contain** the five-target compiler output ⇒ **under pass state the grep domain is empty**. Existing warning backlog Dart 46 / Kotlin 59 / Rust 4 all rc=0. **Reproducible discriminability method**: inject **one** warning into the same tree, run "existing command" vs "strict command" — `dart: loose rc=0 / strict rc=2`, `rust: loose rc=0 / strict rc=101`; **if both rc are identical, the gate does not exist** (this seat turned it into a rerunnable `verify.sh`). Fix branch `fix/zero-warning-gate-wiring`.
5. **"Changed the emitter" does not equal generated different output** (PIT-347 measured): one seat added **38 lines** of AST traversal bypass in `Compiler.hx`, `diff -rq` against the **entire generated tree** showed **0 differences**, the target site unchanged by a single character. **Discriminability method**: any emitter change must **regenerate and diff the generated artifacts** to count; source diff looking reasonable does not constitute evidence. (Another redispatch on the same row changed only **9 lines** but actually altered the site.)

**⇒ L5 operational form**: every fixture must be paired with an **intentionally wrong backend** (wrong branch taken, wrong value returned, transformation stripped), and prove the fixture FAILs against it. **Proving only that "the correct backend passes" does not count as verification.**
**⇒ Corollary for "gate-class" criteria**: must present rc for **both** loose and strict runs — reporting only "pass" cannot distinguish "check passed" from "no check".

## Every criterion must state "on which tree it holds" (new in this session, prerequisite L0)

**Rule**: any criterion claiming "fixed / in effect / closed" must, **on the same line**, provide the **commit hash** and **the result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**. If the result is negative, it may only be written as "branch state / worktree state", and must **not** be written as in effect.

**Why this is not formalism**: this session measured the same artifact giving **opposite conclusions** on two trees — the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) **was reviewed and signed off** yet **was never an ancestor of base**, so what runs on base is the weak version: delete the real root `boring.ArraySliceOps` and add an exemption with reason `"because"`, the weak version returns **rc=0 PASS (4 exemptions)**, the hardened version returns **rc=1** and names it verbatim. That is, "signed off" and "in effect" are two different things; without specifying the tree, a **non-existent safeguard** gets recorded as existing.

**Three-step verification method (must run before signoff or handoff)**:
1. `git rev-parse --verify <branch>` — does the branch **exist** (this session has several rows whose `branch` field points to branches that were **never created**)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — has it **landed on base**
3. **Directly read the file in the shared tree** — what form does it actually have in base (step 3 is non-optional: in this case the first two steps both passed, and only the third revealed it was the weak version)

**After landing, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which branch am I on) **and** step 2 (is it truly on the **declared base**) — this session had one case where four merges all landed on the work branch while the declared base was untouched, causing newly opened worktrees to miss those fixes.

## Delivery surface: load-bearing artifacts must answer "which commit has it"

**Rule**: tools, guardrails, fixtures, drivers, assertion scripts — things others will depend on — **must be checked in**; evidence may be report-only. If a criterion depends on a file, it must also provide the basis for **its reachability in a clone** (e.g. `git ls-files --error-unmatch <path>` passes, and `git archive HEAD` can retrieve it).

**Two measurements in this session**: ① under `dc-warn/worktrees/`, **37/37** are all detached HEAD, **all have uncommitted changes**, **none carry commits beyond `e1c65975`** — "done in worktree + report on file" became the actual delivery convention for this batch; ② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths, making "one command rc=0" **true only for the author's working copy** and false for a clone (PIT-346). **Fix**: the manifest may **section-label reachability** (repo-verifiable / evidence-only), and be verified on a **clean export tree containing only committed files**.

## Evidence strength of each layer must be stated separately

**Do not** conflate the three:
- "Generation succeeded" (L1)
- "Generated code passes type-check" (L2)
- "Runtime results are correct" (L4)

**One misjudgment in this session originated here**: `d14aae11` was submitted with `-typecheck` 0/0 as the acceptance criterion, but that criterion cannot see L3/L4 problems (the P4 regression only surfaces under a full build).

## Honest reporting of coverage

**Rule**: when reporting "N/M covered", must also give the **skipped items and why**.

**Instance**: the P1 scoped run claimed "every P1-updated expectation was exercised", actual was **56/57** — `printed-record.test.ts:88` is only consumed in a test that times out, so it was never executed; and the pre-existing red in `array-root.test.ts:18` means `L28` was never reached. (Lesson PIT-321)

## Timeout and failure must be distinguished

**The criterion is "did the subject finish running", not "did it time out".**

**Instance**: the `value-type` coupled run was **not killed** — `Bun.spawnSync` blocks the bun timer, taking 351 s ≈ 15 runs, the temp directory disappeared in both replicas ⇒ the subject **finished running**. Reading it as "coupling masked by timeout" is wrong; the correct description is **latent coupling** (the fix was simply not on the execution path of those probes).

## Commands corresponding to each layer (current state)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | Partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | Partial |
| L3 | `swiftc -c` | **No** |
| L4 | Fixture built-in runner + oracle | **No** |
| L5 | Discriminative backend | **No** |
| Collection | **`bun run test` (collects `tests/**`)** | **Yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (since `9f26e1ef`): the `collected-suite` job runs `bun run test` on every invocation, reporting collection domain and counts; the job is blocking, has no `continue-on-error`, and failing a protected assertion means failure (negative control proof under `dc-warn/out/ci-wire/`). **Counting already exists**, but the `:80` standard of "count is zero" is **still not met**: the baseline (`1001 pass / 32 fail / 8 errors`) has not yet been cleared, `BASELINE-FAILURES.md` only records, does not waive. The collection domain is 303 files, of which 249 come from the generated tree `reference/ts/gen-tests`, so the job regenerates first then collects.

## This layer is currently not green (L3 build-phase diagnostics, correction record)

**An earlier version of this document wrote on line 12 "S1 brought it to zero (1 → 0)". That was wrong; it is corrected here and the error shape is preserved, because it is exactly the type that this document's L0 section itself warns about.**

The error shape: writing **a measurement on a candidate-material tree** as **an established fact on the current branch**. Verify separately:

| Question | Result |
|---|---|
| Is `cd70eb12` an ancestor of `arch/agent-guided-governance` (base)? | **No** — `git merge-base --is-ancestor cd70eb12 arch/agent-guided-governance` → rc=1 |
| Which branches does it appear on? | Only `prep/p08-s1-unreachable-return` (including the origin branch of the same name) — it is **candidate material** |
| Does `stmtDiverges` exist in the current tree? | **No** — `grep -rn stmtDiverges --include=*.hx packages/` → 0 hits |
| What is the diagnostic count on the current tree? | **1**, and the fixture **explicitly asserts it must exist** |

`tests/swift-gap-boundary/gap-boundary.test.ts` pins this 1 warning, its comment self-describes as "an unwaived, recorded baseline failure -- the goal remains zero diagnostics under `-c`", with assertion `toHaveLength(1)`. Therefore:

- **The fixture says "defect still present"** (anti-corruption pin — once the defect is truly fixed, this assertion will fail and force a recount);
- **The document at that time said "brought to zero"**.

Both cannot be true simultaneously; measurement sides with the fixture. The "1 → 0" record in `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` describes **that tree** at `cd70eb12`, and within that tree it is true; it cannot be cited as the state of the current branch. Writing a candidate-tree conclusion as branch state directly conflicts with this record's L0 section requirement to "provide commit + `is-ancestor` result" — and at that time this rule had no machine enforcement, so it was violated and nobody noticed.

**Lesson (already written into L0 section)**: a candidate material's measurement result may only be written as "in effect" when `is-ancestor` is true. Previously this document was precisely missing this step.

## Unresolved

- Whether L5 discriminative backends are written into every fixture (currently only `branchBoundary` and gap driver have them)
- Whether `swiftc -c` should replace `-typecheck` as the acceptance standard for all Swift — evidence supports distinguishing by form (ordinary forms `-typecheck` is sufficient, return-stripped forms must use `-c`)
