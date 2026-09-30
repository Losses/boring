# Layered Verification Plan

The classification says "who owns it", the contract says "what is promised", and this document says **what observable each layer is verified with**, and **when each criterion lies**.

## Layers and Criteria

| Layer | Property under test | Observable | Pass criterion | **When this criterion lies** |
|---|---|---|---|---|
| **L1 generation** | Compiler did not crash, artifacts complete | Generator process exit code + file list | `rc=0` and expected files present | **rc=0 does not mean the artifacts are correct**: `:2609`'s `fail()` also reaches rc=1, but an input that "does not reach a crash" gets rc=0 while the output is wrong |
| **L2 syntax/types** | Artifacts are valid in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 errors | **`-typecheck` does not run SILGen**: multi-statement closures with `return` stripped only report a warning; only a real build fails. **Such forms must use `swiftc -c`** |
| **L3 build** | Artifacts can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 errors | Build-phase diagnostics (`will never be executed`) **do not appear under `-typecheck`**. **Ruled: counted into the acceptance standard** — see `rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (`1a486ebd`); S1 has driven it to zero (1 → 0, counted by `file:line:col: severity` shape, `grep -c 'warning:'` counts 1 as 2 because of the caret line, PIT-336) |
| **L4 behavior** | Runtime results are correct | Line-by-line comparison against the oracle | **byte-identical** | If the oracle itself is wrong, everything is wrong; and "identical to the oracle on the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 discrimination** | The check **can** find the target defect | Run against an intentionally wrong backend | Intentionally wrong ⇒ **FAIL** | Without this layer, L1–L4 all green may only mean **the property was not observed** |

## L5 is a layer added in this session (previously missing)

**Three instances of "checks that cannot find the target defect"**:

1. **`branchBoundary` fixture**: the two branches are equal length, the consumer only prints length ⇒ a backend that "always takes either branch"
   **passes all assertions**. After the fix, `branch-false=1:2:present` FAILs against the intentionally wrong
   backend (commit `d1180768`).
2. **`swiftc -typecheck`**: misses "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Concatenation-type changes**: the generated tree is byte-identical pre/post ⇒ cannot distinguish "not applied" from "changed correctly".

**⇒ L5's operational form**: every fixture must be paired with an **intentionally wrong backend** (takes the wrong branch, returns the wrong value, strips the conversion), and prove that the fixture FAILs against it. **Proving only that "the correct backend passes" is not verification.**

## Every criterion must state "on which tree it holds" (new in this session, L0 precondition)

**Rule**: any criterion claiming "fixed / applied / closed" must give, on the **same line**, the **commit hash** and the **result of `git merge-base --is-ancestor <commit> arch/agent-guided-governance`**. If the result is negative, it may only be written as "branch state / worktree state", and must **not** be written as applied.

**Why this is not formalism**: this session measured the same thing giving **opposite conclusions** on two trees — the hardened version of `tools/roots-guard/` (`1cafaa42`, +923 lines) **was reviewed and signed** but **was never an ancestor of base**, so what runs on base is the weak version: delete the real root `boring.ArraySliceOps` and add an exemption with reason `"because"`, and the weak version gives **rc=0 PASS (4 exemptions)** while the hardened version gives **rc=1** and names it verbatim. That is, "signed off" and "applied" are two different things; without stating the tree, a **non-existent guard** will be recorded as existing.

**Three-step verification (must run before sign-off or takeover)**:
1. `git rev-parse --verify <branch>` — does that branch **exist** (this session has several rows whose `branch` field points to branches that were **never created**)
2. `git merge-base --is-ancestor <commit> arch/agent-guided-governance` — **did it get into base**
3. **Read the file in the shared tree directly** — what form is it actually in, in base (step 3 cannot be skipped: in this case the first two steps passed, and only step 3 found the weak version)

**After merging, also verify the landing point**: `git rev-parse --abbrev-ref HEAD` (which line am I on now) **and** step 2 (is it really on the **declared base**) — this session had one case where all four merges landed on the work line while the declared base was untouched, so newly opened worktrees could not get those fixes.

## Delivery side: load-bearing artifacts must answer "which commit has it"

**Rule**: things that later people will depend on — tools, guards, fixtures, drivers, assertion scripts — **must be committed**; evidence may live only in the report. If a criterion depends on a file, it must also give the basis for **its reachability in a clone** (for example, `git ls-files --error-unmatch <path>` passes, and `git archive HEAD` can extract it).

**Two measurements in this session**: ① under `dc-warn/worktrees/`, **37/37** are all detached HEAD, **all have uncommitted changes**, **none carries commits beyond `e1c65975`** — "done in the worktree + report on file" became the actual delivery convention of this batch; ② the evidence manifest `FILES.sha256` mixed in 2 **git-ignored** `dc-warn/out/...` paths, making "one command rc=0" **true only for the author's working copy** and false for a clone (PIT-346). **Fix**: the manifest may **mark reachability by section** (repo-verifiable / evidence-only), and verify in a **clean export tree containing only committed files**.

## Each layer's evidence strength must be stated separately

**Must not** conflate the three:
- "generation succeeded" (L1)
- "the generated code type-checks" (L2)
- "the runtime results are correct" (L4)

**One misjudgment in this session came from this**: `d14aae11` was committed with `-typecheck` 0/0 as the acceptance criterion, but that criterion cannot see the L3/L4 layer problems (the P4 regression only surfaces under a full build).

## Honest reporting of coverage

**Rule**: when reporting "covered N/M", you must also give the **items skipped and why**.

**Example**: the P1 scoped run claimed "every P1 update's expectation is exercised", actually **56/57** — `printed-record.test.ts:88` is only consumed in a test that times out, so it never executes; and the pre-existing red at `array-root.test.ts:18` means `L28` is never reached. (Lesson PIT-321)

## Timeouts and failures must be distinguished

**The criterion is "did the subject finish", not "did it time out".**

**Example**: the coupled run of `value-type` was **not killed** — `Bun.spawnSync` blocks the bun timer, takes 351 s ≈ 15 runs, and the temporary directory disappears in both copies ⇒ the subject **finished**. Reading it as "coupling masked by a timeout" is wrong; the correct statement is **latent coupling** (the fix is not on the execution path of those probes at all).

## Commands for each layer (current status)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | Partially (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | Partially |
| L3 | `swiftc -c` | **No** |
| L4 | Fixture's own runner + oracle | **No** |
| L5 | Discriminating backend | **No** |
| Collection | **`bun run test` (collects `tests/**`)** | **Yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (since `9f26e1ef`): the `collected-suite` job runs entry point `bun run test` every time, reporting the collection domain and counts; the job blocks, has no `continue-on-error`, and fails when a protected assertion is broken (negative-control proof at `dc-warn/out/ci-wire/`). **The count already exists**, but the standard `:80`'s "count is zero" is **still not satisfied**: the baseline (`1001 pass / 32 fail / 8 errors`) has not yet been cleared, and `BASELINE-FAILURES.md` only records, does not exempt. The collection domain is 303 files, of which 249 come from the generated tree `reference/ts/gen-tests`, so the job regenerates first, then collects.

## Unresolved

- **Whether L3 build-phase diagnostics count toward acceptance** (`t-muo92xms-s28t`, unclaimed)
- **Whether L5's discriminating backend should be written into every fixture** (currently only `branchBoundary` and the gap driver have it)
- **Whether `swiftc -c` should replace `-typecheck` as the standard for all Swift acceptance** — the evidence supports distinguishing by form (ordinary forms: `-typecheck` suffices; forms with `return` stripped: `-c` required)
