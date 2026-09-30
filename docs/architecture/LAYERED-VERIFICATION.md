# Layered Verification Scheme

The classification says "who owns what," the contract says "what is promised," this document says **what observable quantity each layer uses for verification**,
and **when each criterion will mislead**.

## Layers and Criteria

| Layer | Property Under Test | Observable Quantity | Passing Criterion | **When This Criterion Misleads** |
|---|---|---|---|---|
| **L1 Generation** | Compiler did not crash, artifacts are complete | Generation process exit code + file manifest | `rc=0` and expected files exist | **`rc=0` does not mean artifacts are correct**: `:2609`'s `fail()` also leads to rc=1, but inputs that "did not reach a crash" have rc=0 while output is wrong |
| **L2 Syntax/Types** | Artifacts are legal in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 errors | **`-typecheck` does not run SILGen**: multi-statement closures with stripped `return` only report a warning, the real build fails. **Such patterns must use `swiftc -c`** |
| **L3 Build** | Artifacts can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 errors | Build-time diagnostics (`will never be executed`) **do not appear under `-typecheck`**; whether they count toward acceptance **is not yet decided** (`t-muo92xms-s28t`) |
| **L4 Behavior** | Runtime results are correct | Line-by-line comparison against oracle | **Byte-for-byte identical** | If the oracle itself is wrong, everything is wrong; and "identical to oracle under the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 Discriminability** | The check **can** discover the target defect | Run against an intentionally erroneous backend | Intentional error ⇒ **FAIL** | Without this layer, all-green L1–L4 may only mean **the property was never observed** |

## L5 Is a Layer Added by This Session (Previously Missing)

**Three instances where "checks cannot discover the target defect"**:

1. **`branchBoundary` fixture**: two branches are equal-length, the consumer only prints length ⇒ a backend that
   "always takes either branch" **passes all assertions**. After the fix, `branch-false=1:2:present` FAILs against
   an intentionally erroneous backend (commit `d1180768`).
2. **`swiftc -typecheck`**: missed reporting "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Concatenation-style changes**: generated tree pre/post are byte-for-byte identical ⇒ cannot distinguish
   "did not take effect" from "changed correctly."

**⇒ L5's operational form**: every fixture must be paired with an **intentionally erroneous backend**
(taking the wrong branch, returning the wrong value, stripping a transformation), and prove that
the fixture FAILs on it. **Proving only "a correct backend passes" is not verification.**

## The Evidence Strength of Each Layer Must Be Stated Separately

**Must not** conflate the three:
- "Generation succeeded" (L1)
- "Generated code type-checks" (L2)
- "Runtime result is correct" (L4)

**One misjudgment in this session stems from this**: using `-typecheck` 0/0 as the acceptance criterion when
submitting `d14aae11`, but that criterion cannot see problems at L3/L4
(the P4 regression only surfaces under a full build).

## Honest Reporting of Coverage

**Rule**: when reporting "coverage N/M," the skipped items and their reasons must be given at the same time.

**Instance**: the P1 scoped run claimed "every P1 update's expectation was exercised,"
actually **56/57** — `printed-record.test.ts:88` is only consumed in a test that times out,
so it was never executed; and the pre-existing red in `array-root.test.ts:18` means `L28` was never reached.
(Lesson PIT-321)

## Timeout and Failure Must Be Distinguished

**The criterion is "whether the main body finished running," not "whether it timed out."**

**Instance**: the coupled run of `value-type` **was not killed** — `Bun.spawnSync` blocks bun timers,
took 351 s ≈ 15 runs, the temp directory vanished in both copies ⇒ the main body **finished running**.
Reading it as "coupling masked by timeout" is wrong; the correct description is **latent coupling**
(the fix is not on the execution path of those probes at all).

## Commands Corresponding to Each Layer (Current State)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | Partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | Partial |
| L3 | `swiftc -c` | **No** |
| L4 | Fixture's own runner + oracle | **No** |
| L5 | Discriminative backend | **No** |
| Collection | **`bun run test` (collects `tests/**`)** | **Yes** (`collected-suite` job, `9f26e1ef`) |

**⇒ Conclusion** (since `9f26e1ef`): the `collected-suite` job runs `bun run test` as entry point on every run,
reporting the collection domain and count; the job blocks, has no `continue-on-error`,
breaking a protected assertion means failure
(negative-control proof at `dc-warn/out/ci-wire/`). **The count already exists**, but standard `:80`'s
"count is zero" **is still not met**: the baseline (`1001 pass / 32 fail / 8 errors`) has not yet been cleared,
`BASELINE-FAILURES.md` only records, does not exempt. The collection domain is 303 files, of which 249 come
from the generated tree `reference/ts/gen-tests`, so the job regenerates first, then collects.

## Open

- **Whether L3 build-time diagnostics count toward acceptance** (`t-muo92xms-s28t`, unclaimed)
- **Whether L5's discriminative backend is written into every fixture** (currently only `branchBoundary` and gap-driven ones have it)
- **Whether `swiftc -c` should replace `-typecheck` as the standard for all Swift acceptance** —
  evidence supports distinguishing by pattern (normal patterns: `-typecheck` suffices; patterns with stripped `return`: `-c` is required)
