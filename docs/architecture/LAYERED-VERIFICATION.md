# Layered Verification Scheme

Classification says "who owns what", the contract says "what is promised", this document says **what observable quantity each layer verifies**,
and **when each criterion will lie**.

## Layers and Criteria

| Layer | Property under test | Observable | Pass criterion | **When this criterion lies** |
|---|---|---|---|---|
| **L1 generation** | the compiler did not crash, artifacts are complete | generation process exit code + file manifest | `rc=0` and the expected files exist | **rc=0 does not mean the artifact is correct**: the `fail()` at `:2609` also reaches rc=1, but an input that "does not reach the crash" is rc=0 while the output is wrong |
| **L2 syntax/types** | the artifact is valid in the target language | `swiftc -typecheck` / `tsc` / `rustc --emit=metadata` | 0 error | **`-typecheck` does not run SILGen**: a multi-statement closure with `return` stripped only reports a warning, and a real build fails. **Such shapes must use `swiftc -c`** |
| **L3 build** | the artifact can be linked into an executable | `swiftc -c` / `swiftc -o` | 0 error | build-time diagnostics (`will never be executed`) **do not appear under `-typecheck`**, and whether they count toward acceptance **is not yet decided** (`t-muo92xms-s28t`) |
| **L4 behavior** | the runtime result is correct | line-by-line comparison against the oracle | **byte-for-byte identical** | if the oracle itself is wrong, everything is wrong; and "identical to the oracle under the same input" **does not cover** properties the oracle does not express (laziness) |
| **L5 discrimination** | the check **can** find the target defect | run against a deliberately wrong backend | deliberate error ⇒ **FAIL** | without this layer, all-green L1–L4 may only mean **the property was never observed** |

## L5 is a layer added by this session (previously missing)

**Three instances of "a check that cannot find the target defect"**:

1. **`branchBoundary` fixture**: the two branches are equally long, and the consumer only prints the length ⇒ a backend that "always takes either branch"
   **passes all assertions**. After the fix, `branch-false=1:2:present` against the deliberately wrong
   backend FAILs (commit `d1180768`).
2. **`swiftc -typecheck`**: misses "missing return in closure" (`lambda-fix-xcheck` §5).
3. **Splice-like modifications**: the generated tree's pre/post are byte-for-byte identical ⇒ cannot distinguish "did not take effect" from "changed correctly".

**⇒ L5's operational form**: every fixture must be paired with a **deliberately wrong backend** (takes the wrong branch, returns the wrong value,
strips the transformation), and must prove that the fixture FAILs on it. **Only proving "the correct backend passes" is not verification.**

## Each layer's evidence strength must be stated separately

**Must not** conflate the three:
- "generation succeeded" (L1)
- "the generated code type-checks" (L2)
- "the runtime result is correct" (L4)

**One misjudgment in this session stemmed from this**: `d14aae11` was committed with `-typecheck` 0/0 as the acceptance criterion,
but that criterion cannot see L3/L4 problems (the P4 regression only surfaces under a full build).

## Honest reporting of coverage

**Rule**: when reporting "covers N/M", you must also give **the skipped items and their reasons**.

**Example**: the P1 scoped run claimed "every P1 update's expectation was exercised",
actually **56/57** — `printed-record.test.ts:88` is only consumed in the timing-out test,
so it never executed; and the pre-existing red at `array-root.test.ts:18` means `L28` is never reached.
(lesson PIT-321)

## Timeout and failure must be distinguished

**The criterion is "did the subject finish running", not "did it time out".**

**Example**: the coupled run of `value-type` was **not killed** — `Bun.spawnSync` blocks the bun timer,
took 351 s ≈ 15 runs, and the temporary directory disappeared in both replicas ⇒ the subject **finished running**.
Reading it as "a coupling masked by timeout" is wrong; the correct phrasing is **latent coupling**
(the fix is not on those probes' execution paths at all).

## The command corresponding to each layer (current state)

| Layer | Command | In CI? |
|---|---|---|
| L1 | `haxe <fixture>.hxml` | partial (26 `bun run test:*` scripts) |
| L2 | `swiftc -typecheck` / `tsc` | partial |
| L3 | `swiftc -c` | **no** |
| L4 | the fixture's own runner + oracle | **no** |
| L5 | discriminating backend | **no** |
| — | **`bun run test` (collects `tests/**`)** | **no** (0 of the 26 scripts in `ci.yml`) |

**⇒ Conclusion**: **the 50 `tests/ts` files and the two Swift fixtures currently produce no counts** ⇒
per contract 3 (the standard `:80` "count is zero"), **the current state cannot satisfy that standard,
only bypass it**. The recorded baseline failures must be named, and CI must run the collecting command.

## Undecided

- **Whether L3's build-time diagnostics count toward acceptance** (`t-muo92xms-s28t`, unclaimed)
- **Whether L5's discriminating backend is written into every fixture** (currently only `branchBoundary` and the gap driver have it)
- **Whether `swiftc -c` should replace `-typecheck` as the standard for all Swift acceptance** —
  the evidence supports distinguishing by shape (for ordinary shapes `-typecheck` is enough, shapes with `return` stripped must use `-c`)
