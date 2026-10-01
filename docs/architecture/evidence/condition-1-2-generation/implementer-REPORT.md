# npm tgz non-determinism (MathNaNTestSupport 405/407 flip) — root cause & fix

Repo: `boring-wt-architecture`, branch **`fix/npm-artifact-determinism`**, commit **`2aadcb69`**
(only `tests/ts/package-artifacts.test.ts`; another worker's uncommitted `ci.yml` was left untouched).

## 1. Reproduction (discriminative, not single-pair)

Standalone driver replicating the test's `rewriteHxml`/`runHaxe` exactly (ts package, `-D package-tsc=...`),
one tgz per generation, sha256 + `tar -tzf` entry count per generation. Logs in `evidence/`.

Pre-fix, harness stubbing in place (as the test shipped it) — `evidence/repro-base.log`:

| gen | entries | sha256 | MathNaNTestSupport entries |
|-----|---------|--------|----------------------------|
| 0-4 | 407 | `4bb614bc2a321413…7f580c` | PRESENT (`.js`, `.d.ts`) |

5/5 identical, so the *stubbed* state is deterministic — but it is the WRONG input state (see §2).

Pre-fix, real tracked fixture (no stub) — `evidence/repro-real-fixture.log`:

| gen | entries | sha256 | MathNaNTestSupport entries |
|-----|---------|--------|----------------------------|
| 0-2 | 405 | `5b85d7564e03abe9…dd0abc373` | ABSENT |

**The 405 vs 407 flip is the entry set**: ±2 entries (`package/dist/boring/MathNaNTestSupport.{js,d.ts}`),
matching the reported ±116–118 compressed bytes. Metadata is not involved (dates pinned 1969-12-31, names sorted).

## 2. Root cause

The test harness (`runHaxe`) **rewrote the TRACKED fixture `samples/boring/MathNaNTestSupport.hx` to an
assertion-free stub for the duration of every haxe run**. Which artifact you get depends solely on which
version of that file the compiler process reads:

- Real fixture: the module references the runtime test entry (`import { Test } from "../runtime/test.ts"`).
  `Compiler.anyRuntimeTestUsed()` → `runtime/test.ts` is excluded from the npm stage, and the import-closure
  in `PackageArtifacts.npmCompileSet` transitively drops its importer `MathNaNTestSupport.ts` → **405**.
- Stub: no runtime/test reference → exclusion cannot classify it as test code → the module ships → **407**
  (and with it, a `node:fs`-pulling test helper in a published package).

So the emitter/packaging side (`packages/compiler/PackageArtifacts.hx`, `npmCompileSet`) was **already
correct for honest inputs**; the non-determinism was the harness fabricating two different input states.
Because the fixture is a shared tracked file, the mutation window also races every concurrently running
suite that compiles from `samples/` in `bun run test` (collected-suite), and pre-`4cf3165d` (no
`try/finally`) the stub could persist after a killed run. That is why the flake was pre-existing and
intermittent.

## 3. Fix (side chosen: harness/test-infrastructure)

Commit `2aadcb69` removes the workaround entirely from `tests/ts/package-artifacts.test.ts`:
no fixture rewrite, no restore path, no shared-state race; `rewriteHxml` no longer filters
`boring.MathNaNTestSupport` from the module list (it stays compiled as a dependency, exactly as committed).
Generations now always compile the repository's real inputs; the package stably excludes the test support
module — the direction the test's own comment block (lines ~55-60) intended. The assertion at :333 is
**unchanged**: full-byte comparison across generations. No test deleted, skipped, or weakened.

Why not patch `PackageArtifacts.hx`: for the real fixture the exclusion already produces the correct,
deterministic 405-entry package (proven above, exit 0). Any emitter change would only re-encode what the
closure already does.

## 4. N-generation determinism proof (post-fix)

`evidence/postfix-5gen.log` — 5 generations from clean inputs, same fixed tree and toolchain:

| gen | entries | sha256 | MathNaNTestSupport |
|-----|---------|--------|--------------------|
| 0-4 | 405 | `5b85d7564e03abe9…dd0abc373` | absent, stably |

unique hashes = **1**; hash identical to the honest-input pre-fix state (emitter behavior unchanged; only
the input mutation removed). The full test file: **11 pass / 0 fail** with the real fixture, and the
byte-identity test re-run repeatedly (see `evidence/`, repeated-run log; each run re-generates all 5
package formats through fresh temp roots).

Fixture integrity: `grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` = 5 before and after every
run; with the fix the file is never opened for writing at all.

## 5. Ruling completion conditions — mapping

1. Repeated clean-input generations, byte-identical archives — **met** (§4, 5 gens, 1 hash).
2. MathNaNTestSupport entries stable, no 407/405 oscillation; `package-artifacts.test.ts:333` passes on
   repeated runs — **met** at suite level (stably 405/absent; repeated runs pass). CI-identical repetition
   not available locally (no runner).
3. collected-suite no longer flakes on this artifact — **cause removed** (no shared-input mutation → no
   cross-suite interference mechanism exists anymore). Full `bun run test` repetition can only be proven by
   the CI job itself; not run here (no runner; suite is hours-long).
4. `package-shell.test.ts:249` — out of scope per ruling; not touched, not counted here (other seat).

## 6. Unverified / limits

- Repeated **full-file** test runs: 1 full run (11 pass) + 2 additional runs of the byte-identical test.
- collected-suite end-to-end repetition: requires the CI runner.
- The concurrent-suite race itself was not staged live; it is established from the mechanism (shared-file
  mutation + empirically proven stub-vs-real artifact flip) and the pre-`4cf3165d` persistence path.
