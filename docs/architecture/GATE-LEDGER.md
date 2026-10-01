# Gate ledger — P08 / P09 / P10 / P12

Sol's ruling (2026-09-30) requires a one-page ledger in which every criterion is
**PASS / FAIL / NOT ESTABLISHED**, with the evidence location and the owner of
any blockage, so that a second person can reconstruct the state from the ledger
alone. This is that ledger.

Method: every row cites where its evidence lives. **Rows marked `[DOC]` rest on a
document's assertion; rows marked `[MINE]` rest on an observation I made myself.**
A row with neither is NOT ESTABLISHED.

---

## P08 — "Delegate reproduction and behavior tests, then implementation." (`work-plan:216`, unchecked)

| # | Criterion | Verdict | Evidence | Blocked by |
|---|---|---|---|---|
| 1 | Correct fact-and-requirement handoffs; in-scope reconstruction removed | **PARTIAL**, and a correction is owed | `blockExpression` no longer reads `currentReturnType` (`c8ae0054` - a block's value is its own result type), and the lambda reseed is structurally enforced there. **CORRECTION owed to an independent review (`p08-review-1`): an earlier revision of this cell credited `switchExpression` with taking an explicit destination, and that change is NOT in the frozen `c8ae0054`** - the frozen signature is `switchExpression(sw:TypedExpr):String` (:5562) calling `switchReturn(sw, 1, false, sw.t)` (:5566), with `switchBindingLines` calling it without `v.t` (:5528). The explicit-destination form was committed later as `71a60c7d`, so it belongs to a **successor** candidate, not to this one. The destination-owner mechanism is still **not** enforced structurally (that work was ordered stopped) | seat 3 |
| 2 | Legal generated output — zero diagnostics on the same candidate inputs | **FAIL (reason changed)** | The two `[#no-usage]` warnings that were the original ground are GONE - W1 is on the line as `d14aae11` and three independent sessions measured 0/0 on the fixture [MINE + 2 seats]. What fails now is one **build-phase** diagnostic: `swiftc -c` emits `will never be executed` at `Gap.swift:117` (W1's unreachable trailing return). Per the round-145 gate-owner ruling such a diagnostic **COUNTS** against `:78`/`:80`, so the fixture records it as an unwaived deviation and keeps zero diagnostics under `-c` as the stated goal (`tests/swift-gap-boundary/gap-boundary.test.ts`) | seat 1 or a gate-owner ruling on the `-c` criterion |
| 3 | Preserved source behaviour (branches distinguishable, alias, lifetime, single evaluation, lazy effects, control exits) | **PARTIAL** | `docs/architecture/evidence/ledger-cited-reports/p08-candidate-freeze-FREEZE.md` §5.3 [DOC] (the freeze record's `## 5. Obligation map` at `:299` carries `### 5.3 Obligation 3 — Preserved source behaviour` at `:408`; the companion `p08-candidate-freeze-REPORT.md` - sections 1-5, no subsections - remains cited for the freeze method and its limits); branch discrimination was broken and is now repaired (`d1180768`); **lazy effects are now MEASURED** - `p08-review-1` built a side-effecting probe over four routes (switch / try / ternary / expression-block argument at a ReadOnlyArray destination) and got **7/7 byte-identical to `haxe --interp`**, each showing exactly one arm's effect and exactly one producer call; the P08 behaviour-matrix seat independently measured laziness on three axes at once (effect order, effect count, and **termination**: lazy terminates rc=0 where eager recurses to SIGSEGV rc=139). **F3** was the freeze cross-check's label for "lazy effects were never measured" - it was cited without a definition until now | seat 4 |
| 4 | Two independently recorded reviews | **FAIL** | behaviour review (`out/p08-behaviour-review/`) non-accepting; implementation review (`out/p08-implementation-review/`) **REJECT** with four open conditions | seat 6 |

**Re-freeze recorded** (`fc89d5d8`, `docs/architecture/REFREEZE.md`): the candidate
identity is now **`c8ae0054`** (chain `a14345ce` -> `28820ff5` -> `c8ae0054`). This is an
identity record, not an acceptance. Any subsequent P08 review must target that revision,
not scratch trees and not the superseded `docs/architecture/evidence/ledger-cited-reports/p08-candidate-freeze-REPORT.md`.

**Successor re-freeze recorded** (`2905bdfb` + `d31041eb`, superseding the paragraph
above; `docs/architecture/REFREEZE-SUCCESSOR.md`): the successor candidate is frozen at
**`2ba5766b`** (`merge: recov/r31-successor-declaration into
arch/agent-guided-governance`). `REFREEZE.md` carries a pointer at its head and its
original lines are left intact, so the supersession is auditable rather than silent.

The successor is a **lineage**, not one commit: `c8ae0054` plus three components S1
`cd70eb12`, S2 `71a60c7d`, S3 `449444cf`, each of which entered the line separately.
`2ba5766b` is the revision the declaration prescribes - the HEAD after R1, R2 and the
declaration land. All five are ancestors of `2ba5766b` (`git merge-base --is-ancestor`
gives rc=0 for each).

The freeze point was first recorded as `649aa881`, and that was wrong: `649aa881` is a
**later** HEAD that also carries R4.3 (`1e0d8169`), a same-day unrelated repair, so a
reviewer would have been asked to certify work the declaration never covered. The
correction is recorded in `REFREEZE-SUCCESSOR.md` with the seat's original row left in
place rather than rewritten.

Still an identity record, not an acceptance, and it nominates nothing: `RULING-137` stands
and P08 remains PREPARABLE / NOT NOMINATE-ABLE. Its **scope caveat** is a fact for the
R3.3 reviewer, not a defect in the successor: at `2ba5766b`, `SwiftExpr.hx` differs from
`c8ae0054` by **230 insertions / 15 deletions**, because unrelated Swift-backend work
entered the line before the declaration as well. Nine commits touched that file between
`c8ae0054` and the freeze - four are successor components, five are unrelated mainline
work.

**P08 overall: NOT PASSED.** The candidate is REJECT. Its post-review repair is now complete and on the line - the integration ruling's option (b) was executed as `a14345ce` (revert the lambda half, keep W1) followed by `c8ae0054` (the corrected lambda as one atomic commit) - so the line no longer carries a known regression, and a re-freeze is the next step. What still blocks is the build-phase diagnostic above and the absence of a second independent acceptance on a frozen revision.

## Restoring contract 3 - progress against the four conditions

The round-5 ruling downgraded contract 3 to "the gate is implemented; its run
reliability is not achieved" and named four conditions for restoring it. Progress,
recorded under the entry gate below (each line carries a hash or is marked
`in-flight`):

| # | Condition | State |
|---|---|---|
| 1 | repeated generation from clean inputs yields identical bytes and checksums | **entry-gate evidence form satisfied (`2aadcb69`); all four requirements independently CONFIRMED by the R2.2 three-way check** (`evidence/condition-1-2-generation/r22-three-way-check-REPORT.md`). 5 clean-input generations, one unique hash, independently re-measured |
| 2 | the `MathNaNTestSupport.{js,d.ts}` entries are stable; the byte-identity test passes repeatedly | **entry-gate evidence form satisfied (`2aadcb69`); all four requirements independently CONFIRMED by the R2.2 three-way check** (`evidence/condition-1-2-generation/r22-three-way-check-REPORT.md`). Entries stable at 405/absent across 10 real-fixture generations; the test passes on repeated runs. **Citation note: at `2aadcb69` the comparison is at `:338`** (`:351` in the parent; `:333` names the declaration there) - documentation drift, content unchanged |
| 3 | `collected-suite` no longer fails on the flake, and **its log distinguishes real product/spec failures from environment/timeout failures** | **EXERCISED (SYNTHETIC FLAKE-SHAPED INPUT; NO REAL FLAKE OBSERVED)** - the classification framework was exercised in both directions on a synthetic flake-shaped input (V1 flake=1 and no other class up; V2 same test id failing on its own exit-code assertion -> flake 0; V3 Buffer diff in an unrelated file -> flake 0; V4 residual 1 raised `::warning::` verbatim), with the plan pre-recorded, the step extracted verbatim from the committed blob, and the stale-log trap closed structurally. **No real flake was observed, and none is claimed** - the flake-catching behaviour remains exercised synthetically rather than in the wild. Evidence: `dc-warn/out/flake-synthetic/` (`00-PLAN.md` + `evidence/`, SYNTHETIC-labelled); commit `f1eb7498`. The real-rendering method and the inability to re-invoke bun 1.3.13 locally are stated in that report and are not softened here. The flake half is `cause removed` (`2aadcb69`) |
| 4 | an independent spec ruling on `package-shell.test.ts:249` | **technical claims independently CONFIRMED (`eec707b9`); R2/R3 evidence package is in-repo (commit `1704c3db`); all four entry-gate requirements are now met** - R2/R3 by the committed package `docs/architecture/evidence/entry-gate-r2r3/` (commit `1704c3db`), independently re-derived; R4 by the executor's adjudication and the independent five-claim check, both now committed in-repo at `docs/architecture/evidence/condition-4-entry-gate/evidence/package-shell-adjudication-REPORT.md` and `docs/architecture/evidence/condition-4-entry-gate/evidence/verify-eec707b9-REPORT.md` (merge commit `84eff599`, byte-identical to `dc-warn/out/` scratch originals, SHA256SUMS 15/15 OK); the mechanical verdict and the four-requirement table are committed at `docs/architecture/evidence/condition-4-entry-gate/`. **The entry gate's evidence form is satisfied; condition 4 itself remains NOT SATISFIED per `MANAGEMENT-RULING-137.md:17-19`, and P08 remains PREPARABLE / NOT NOMINATE-ABLE (`:32-35`)** |

**Condition 4, resolved** (`eec707b9`): the test was a **stale expectation, not a
product defect**. Spec 24 (Ruling 5) stops only a compilation combining a
**by-name** runtime import with an **emitted** manifest, and expressly requires
accepting a relative specifier; the guard matches that scope. Git forensics found
the mechanism: the test was written at `52044ed1` while `examples/ts.hxml` carried
`-D runtime-import=@boring/runtime`, and `2bd609b9` changed it to `./runtime`
without updating the test, whose helper matched only the historical value - so the
scenario silently became *relative + emit*, which the spec mandates accepting,
while the assertion still demanded a by-name abort. The fix pins the import in the
test itself; no assertion was weakened. Discriminating readings: relative+emit ->
exit 0; by-name+emit -> exit 1 with the sanctioned message; by-name+none -> exit 0.
Full file after the fix: 6 pass / 0 fail.

**Condition 4, verified** (independent check of `eec707b9`, five claims, all CONFIRMED
by the verifier's own measurements): spec 24 Ruling 5 does stop only by-name+emitted
and does require accepting a relative specifier, and the guard matches that scope;
the commit touches only the test file and the supersession note with no assertion
deleted, loosened or skipped; the git forensics hold (the hxml carried
`@boring/runtime` and only `2bd609b9` changed it to `./runtime`, the helper's literal
match making that a silent scenario change); the three configurations reproduce
(`relative+emit` -> exit 0 with a manifest, `by-name+emit` -> exit 1 with the exact
sanctioned message, `by-name+none` -> exit 0 with none); and the file runs 6 pass /
0 fail.

**But the same check ruled that this entry does not satisfy the entry gate**, and the
entry is now worded accordingly rather than claiming resolution: a traceable hash and
an independent claim-versus-commit check are present, while **a clean working-tree
proof and independently exported content are not** - the tree carries other seats'
in-flight edits, so the former cannot be produced right now. The technical claims are
true; the record is not yet in the form the gate requires. **(Superseded 2026-10-01:
the R2/R3 package `1704c3db` supplied the missing requirements 2 and 3, and the two
reports named in requirement 4 were committed in-repo by merge `84eff599`; see
below.)**

**Condition 4's entry gate is now satisfied in evidence form (corrected 2026-10-01).**
The technical claims are independently CONFIRMED (`eec707b9`) and the R2/R3 evidence
package is in-repo (commit `1704c3db`). [Corrected by this entry] The two reports that
requirement 4 names are now committed in-repo: `docs/architecture/evidence/condition-4-entry-gate/evidence/package-shell-adjudication-REPORT.md`
(14037 B) and `docs/architecture/evidence/condition-4-entry-gate/evidence/verify-eec707b9-REPORT.md`
(7415 B), both committed by merge `84eff599`, byte-identical to their `dc-warn/out/`
scratch originals, `SHA256SUMS.txt` re-computed and `sha256sum -c` 15/15 OK. The R2.2
three-way independent check independently re-confirmed all four entry-gate requirements
for both `eec707b9` and `2aadcb69` (`evidence/condition-1-2-generation/r22-three-way-check-REPORT.md`),
with `bun run gate:verify` returning PASS, 0 mismatches, RC=0 in both runs.
`docs/architecture/evidence/entry-gate-r2r3/`
(commit `1704c3db`, the separate evidence commit the round-128 ruling authorized, which
found the R2/R3 threshold closed) supplies requirement 2
(`eec707b9.R2-worktree.txt` - the raw output of a detached worktree at that commit,
`git rev-parse HEAD`, `^{tree}` and `git status --porcelain`, **0 porcelain lines**)
and requirement 3 (`eec707b9.export.tar.sha256` plus `eec707b9.R3-manifest.txt`, 1455
entries). Requirement 1 is the hash itself; requirement 4's two reports are the
executor's adjudication and the independent five-claim check, now in-repo at the paths
above. The historical narrative below still marks this entry as NOT satisfied; that
marking is superseded by the in-repo intake above and is retained only as the state
*before* this correction.

**Satisfying the entry gate's evidence form does not satisfy condition 4, and does not
nominate P08.** Per `MANAGEMENT-RULING-137.md:17-19`, condition 4 is STILL NOT
SATISFIED and P08 remains PREPARABLE / NOT NOMINATE-ABLE; per `:32-35` the standing
prohibition against nominating, declaring a pass, or changing P08's status remains in
force until condition 4 is satisfied and a later explicit ruling says otherwise.

The condition-4 closure seat re-derived all four from the committed artefacts rather
than from the tool's word: the archive checksum recomputes to `ad7004d7…` and equals
the committed one; the manifest equals `git ls-tree -r eec707b9` normalized to
`oid  path` (1455/1455) and is commit-specific; **all 1455 exported files re-hash with
`git hash-object` to their recorded blobs**; a fresh detached worktree at the hash
shows 0 porcelain lines; `bun run gate:verify` returns **PASS with 0 mismatches** in
both `archive-verify` and `--verify-export` mode; and appending one byte to a copy of
the export makes the tool **FAIL**, naming that file - so the PASS is not vacuous.
Verdict, raw logs and the four-requirement table:
`docs/architecture/evidence/condition-4-entry-gate/`.

Limits kept rather than papered over: the requirement-2 proof is a detached worktree
and is therefore empty for *any* commit - it is ruling-sanctioned (round-112 clause 1)
and it is what the gate's method paragraph defines, but it cannot speak for the
worktree `eec707b9` was originally delivered from, and that state is not retroactively
recoverable; the export **tarball** is checksum-pinned and one command from the commit
rather than retained in-tree; and requirement 4's two reports were in
`dc-warn/out/` scratch at the time of the closure — they were subsequently committed
in-repo by merge `84eff599` (see above), so the closure record no longer carries this
gap.
**This changes no gate's pass status and does not nominate P08.**

One limit the verifier stated: nothing re-executed at `52044ed1`/`2bd609b9`, so "the
test was green before `2bd609b9`" is inference rather than measurement - the failure
mechanism itself was re-measured directly.

**A correction to this record's own history**: `BASELINE-FAILURES.md` had called
this a "product/spec gap" on an "unconditional abort" reading of spec 24. That
reading was wrong; the entry now carries a supersession note preserving the
original text.

## The tracked-fixture failure-path proof (owed by the round-215 ruling)

The round-215 ruling required a *discriminating* proof: after deliberately taking
the failure path, the tracked file's contents must still equal what they were before
the test ran - and a manual `git checkout` restore counts as neither the fix nor the
proof. That proof is delivered and recorded as `ed41e14d`
(`docs/architecture/TRACKED-FILE-PROOF.md`), and its entry satisfies the gate above:
a traceable hash, a clean-tree statement for the committed file, content exportable
from that commit, and a report consistent with the commit.

| What | Result |
|---|---|
| Control: pre-fix damage at `4cf3165d^` (`ab20a8af`) | **reproduced** - SIGTERM mid-run with the stub live leaves the file corrupted (`Test.equals` 5 -> 0, sha256 `1c2acf93...` -> `4f910e40...`). Without this, "it survived" would prove nothing. |
| Fixed revision, forced throw from the probe path | **file intact** (`Test.equals` 5, hash equal to the clean-export control) |
| Fixed revision, SIGINT mid-run | **intact** |
| Fixed revision, harness timeout (`SIGTERM` at t+25s) | **intact** (rc=124) |
| Residual limit, **demonstrated not merely stated** | **SIGKILL with the stub provably live still corrupts the file**, byte-identical to the pre-fix damage - no handler runs, so `finally` cannot cover it |
| **Superseded while the proof was in flight** | `2aadcb69` removed the stub/restore entirely, so at HEAD `runHaxe` never writes the fixture at all. The hazard is now **eliminated rather than guarded**, which is strictly stronger; the SIGKILL gap applies only to `4cf3165d..2aadcb69^`. |

Every fixed-revision run **ended in test failure** - that is the point: the
evidence is fixture survival, not a green test. Limits recorded by the prover:
a machine reset was not exercised (same no-handler class), and bun 1.3.13 running
`finally` on SIGINT/SIGTERM is runtime behaviour rather than a portable guarantee.

## The first real end-to-end run (the round-65 ruling's single next action)

The ruling required exactly one new piece of evidence before anything else could
move: a real, exclusive, CI-shaped run with the two unmerged repairs applied. It
exists now. Artifacts: `docs/architecture/evidence/ledger-cited-reports/e2e-run-REPORT.md` and `evidence/`.

| What | Result |
|---|---|
| Run identity | HEAD `9388aa62`, exclusive (no other suite or compiler process), tree clean before and after, `Test.equals` = 5 before and after (blob matched HEAD's; no restore needed) |
| Pipeline | `bun install` rc 0; **all eight CI-prelude generators** (`gen:ts` .. `gen:dart`) rc 0; then `bun run test` |
| **Suite result** | **rc 0 - `Ran 1035 tests across 304 files / 1035 pass / 0 fail`, 2344.66 s** |
| Domain | **304 files**, i.e. the full prelude-built domain, not the shrunken one a bare `bun run test` would have collected |
| Attribution, applied verbatim from the committed workflow | five classes all 0, **residual 0**, no `::warning::` or `::error::`, generated-tree warning count 0 |
| Substitutions, named | chainA PATH instead of `nix develop -c`; `sudo sysctl` and `nix-store --import` not performed (no sudo approval available) |
| Fixture and tree | untouched; fixture blob equals HEAD's; `git status --porcelain` empty |

**The five acceptance conditions, item by item.** (1) **PASS vacuously** - zero
failures, so nothing was left unattributed. (2) **PASS** - the class counts
reconcile against the reported fail count with residual 0, so no warning was
required. (3) **NOT-EXERCISED** - the byte-identity target test *passed* (358.4 s of
its 420 s budget) and no Buffer-diff shape appears anywhere in the log, so **no flake
was witnessed and none is claimed**; the flake-catching behaviour of `2aadcb69`
remains **analytically verified only**. (4) **PASS** - exit codes read outside pipes,
hashes in `evidence/sha256.txt`, HEAD recorded. (5) **PASS** - fixture and tracked
tree unchanged.

**So the attribution framework and the other classes may be accepted by this run;
the flake class may not.** Per the ruling that is the correct reading, not a
shortfall to paper over. Demonstrating the flake class requires either a real
occurrence or a controlled, auditable injection labelled as synthetic verification.

**One misstep, self-reported and kept for audit.** The first invocation of the report
step read the script's hardcoded `LOG=out/collected-suite.log` and found a **stale red
log from 15:44**, producing a bogus "7 fail" table (retained as
`evidence/report-step-stdout.misdirected-at-stale-out-log.log`). Every published
number comes from this run's own log. The stale file lived in the git-ignored `out/`
tree, so it never dirtied the repository - but it was a reproducible way to publish
wrong attribution, so it has been **archived beside this run's evidence and removed
from the path the script reads**.

## Ledger entry gate (required by the round-5 ruling)

Added because the coordinator wrote in-flight work into this ledger as though it
had landed, and a reviewer caught it. The ruling's finding was that the cause is a
**missing process**, not merely a lapse of care: making the requirement "be more
careful" does not prevent a recurrence.

**No entry may claim "on the line / delivered / frozen" unless it carries all four:**

1. **A traceable commit hash.** Uncommitted work may only be marked `in-flight` and
   may not be given a main-line status at all.
2. **A clean working-tree proof for that hash.**
3. **The candidate content/checksums, exported independently** from that commit or
   from an explicit freeze archive - not read out of a live worktree.
4. **A claim-versus-commit consistency check, by both the executor and a reviewer.**

**Before any status transition a non-implementer performs a three-way check of
`HEAD` / commit hash / freeze archive. If it fails, the entry goes back.** Oral
delivery, the mere presence of work in a workspace, or a later commit may not
retroactively authorize a claim.

**How requirements 2 and 3 are produced and checked.** Neither depends on the
live worktree (which may sit on a rewritten branch): `git archive <hash>`
exports the commit's tree independently of any checkout, and every path
recorded by `git ls-tree -r <hash>` is re-hashed with `git hash-object` and
compared against its recorded blob oid. The verdict is the comparison result —
a successful export is not a verification. `tools/gate-proof/verify-commit.ts`
(runnable as `bun run gate:verify -- <commit-ish>`) performs this mechanically:
it reports the full commit id, tree id, total file count, per-path mismatches,
a file-list sha256, and a PASS/FAIL verdict, and exits non-zero on any
mismatch. With `--verify-export <dir>` it instead verifies an already-exported
freeze archive against the commit's tree, which is the check requirement 3
demands. A clean working tree of the live checkout is never an input, so
requirement 2 is always satisfiable for any existing commit. No requirement
above is relaxed by this tooling; it only states how the evidence is produced.
Added because two independent verification seats confirmed every technical
claim and then failed their entries (`eec707b9`, `2aadcb69`) on requirements 2
and 3 for the same reason: the gate stated the requirement but not the method,
and the live worktree sits on a branch that keeps being rewritten. Both entries
were afterwards supplied with the two requirements their verifiers found missing:
the R2/R3 package `docs/architecture/evidence/entry-gate-r2r3/` (commit
`1704c3db`) carries the per-commit R2 worktree output, the per-file manifest and
the export checksum for `2aadcb69`, `4f80322c` and `eec707b9`. Whether that
closes each entry is judged **per entry** - it is recorded for condition 4 above
and at `docs/architecture/evidence/condition-4-entry-gate/`, and is **not**
asserted here for conditions 1-2, whose rows still read `in-flight`. The
mechanical verdict for condition 4 was re-derived independently rather than
re-run and pasted. Requirement 2's proof is taken at a detached worktree created
from the hash (round-112 clause 1), so it never depends on the live tree, and no
requirement above is relaxed by it.

Applied to this ledger retroactively: `449444cf` and `71a60c7d` carry hashes and
are on the line; the stopped `w2-diagnostic-fix` work has no hash and is therefore
recorded as abandoned, never as a delivery.

## The P08 candidate is SEALED (round-245 management ruling)

`c8ae0054` is **P08 NOT PASSED / REJECTED, finally.** Two independent reviews
reached that verdict and agree on the ground: under `swiftc -c
-whole-module-optimization` the counterexample fixture emits exactly one
build-phase diagnostic at `Gap.swift:117:9`, while
`02-translator-implementation-standard.md:78/:80` requires the count to be zero.
Neither reviewer waived it.

**The rejection may not be lifted** - not by supplementary explanation, not by
editing this ledger, not by re-measuring, and not by re-interpreting the
build-phase diagnostic. On that candidate only evidence preservation, state
recording and stopping remain permissible. **No new P08 review may be opened**,
and P08 may not be described as unblocked until a new candidate is frozen.

**What the repairs now on the line actually are.** `449444cf` (the lambda
single-statement fast-path repair) and the stopped `w2-diagnostic-fix` work are
**changes of candidate content**, not patches to `c8ae0054`: a fix that alters
generated text changes the candidate even when run semantics are unchanged.
`449444cf` therefore belongs to the **successor** candidate and must never be
cited as evidence that `c8ae0054` was repaired. Any re-freeze must name a
revision that includes it.

**The route forward**, if it is taken: put every needed repair into **one**
clearly identified new candidate - the unreachable-trailing-return fix and the
lambda fast-path fix together - then re-freeze it and run **both** independent
reviews again, with the independence requirements still met.

## Verification results recorded (2026-09-30, latest)

| What was verified | Verdict | Where |
|---|---|---|
| **P08 review 1** on the frozen `c8ae0054` | **REJECT** - obligation 2 fails on exactly one build-phase diagnostic; four exact conditions | `docs/architecture/evidence/ledger-cited-reports/p08-review-1-REPORT.md` |
| **P08 review 2**, reached independently from a `git archive` export | **REJECT** - same single in-scope ground, not waived; it also confirmed the P08-1 correction is accurate and that **no remaining row credits `c8ae0054` with bytes it lacks** | `docs/architecture/evidence/ledger-cited-reports/p08-review-2-REPORT.md` |
| **Timeout-budget commits** (`9905949e`, `36e7540e`, `e8a4c3bb`, `4c292c64`) | **CONFIRMED** on five claims: margins 2.03-2.64x recomputed, no assertion touched, 8/8 cascades explained, changed tests pass, no other regression | `docs/architecture/evidence/ledger-cited-reports/verify-timeouts-REPORT.md` |
| **Tracked-fixture damage root cause** | **repaired and on the line** as `4cf3165d` (restore moved into a `finally`). **The failure-path proof is still owed**: interrupting the test and confirming the fixture survives has not been reproduced. | commit `4cf3165d` |

**Two loose ends recorded rather than dropped:**

1. A pre-existing **knife-edge** test - "two generations byte-identical artifacts" - carries an untouched 420 s budget that the recorded baseline already consumed to **98.8%** (414.8 s). It fails under contention in two different ways. It needs its own budget-or-determinism task; the timeout commits neither caused nor fixed it.
2. One attribution typo in the timeout fix report (line 525 follows the extern-bindings timeout, not printed-record); the commit message and the report's own section 2 attribute it correctly.

**Both reviews agree on the route out**: clear the unreachable trailing `return` so the `-c` diagnostic count reaches zero, then re-freeze. The alternative - a gate-owner ruling that build-phase diagnostics do not count - has already been ruled against.

## What changed since the previous ledger revision (2026-09-30, later)

| Item | State |
|---|---|
| Candidate identity | **`c8ae0054`**, recorded by `fc89d5d8`; a re-freeze establishes identity, **not** acceptance |
| Condition 3 (destination from the owning composition) | **landed** as `71a60c7d` - `switchExpression` takes an explicit destination and `blockExpression` no longer reads `currentReturnType`; 4 generated trees byte-identical, `swiftc -c` green including a full link + 30/30-line run |
| Six baseline reds | **discharged** as `28820ff5`, `ac4099ea`, `50a95377`, `a80690f1`; record updated by `d36e6d3f` (history preserved, the "judged by mechanism" limit superseded by fresh-tree reproduction) |
| **Contract 3's counting mechanism** | **the gate is implemented; its RUN RELIABILITY is not achieved** (`99ba67fd`) - downgraded by the round-5 ruling because it can go red for a pre-existing npm-artifact non-determinism unrelated to any change under review, so its red light cannot be attributed: every run extracts warning lines naming generated-tree files, writes count + lines + domain + baseline reconciliation into the job summary, and **fails** on a missing log, an unparseable count, or a count deviating from the recorded baseline. Baseline **0** is measured from the retained `695940e8` proof-run log, not assumed. No `continue-on-error` anywhere in the workflow. |
| Collected domain | **304 files / 55 non-generated**, not 303/54 - `tests/swift-gap-boundary/gap-boundary.test.ts` entered the repo after the CI commit (`d14231a6`). Recorded per the round-195 ruling; baseline pass/fail numbers stay tied to the 303-file domain. |
| `out/` domain guard | kept, and annotated honestly: **present, never triggered - not an exercised guard** |

## P09 — "Run the candidate's required Boring checks and Tiqian checks on fixed revisions…" (`work-plan:218`, unchecked)

| # | Criterion | Verdict | Evidence | Blocked by |
|---|---|---|---|---|
| 1 | A recorded revision pair | **FAIL — and its first rewrite of this cell was retracted**; the source report calls the Boring side "the single open decision". A prep pin now exists (`docs/architecture/evidence/p09-revision-pin/REVISION-PAIR.md`) | Tiqian side settled (`8504d230`, a commit in the **Tiqian repository**, not this one). Boring side: see the correction below, and `evidence/layered-verification-review/P09-CRITERION1-RECHECK.md` for what the retraction rests on | the **gate owner's decision** — the report states a preference (against `2159c657`) but hands three options to a decider; the drift is real and measured |
| 2 | Boring checks executed | **NOT ESTABLISHED** | no run exists | — |
| 3 | Tiqian checks executed | **NOT ESTABLISHED** | `work-plan:108` "the Tiqian candidate gate has not run" [DOC]; feasibility check confirmed the matrix is not startable | B4 authorization + pair |
| 4 | Logs, generated-output identity, warning results preserved | **NOT ESTABLISHED** | preparation artefacts exist but no run produced them | — |
| 5 | Baseline debt has a finite recorded list | **PASS** | `docs/architecture/BASELINE-FAILURES.md` — 1033 tests collected, 1001 pass / 32 fail / 8 errors, classified into 6 pre-existing assertions (judged by mechanism, limit stated), 26 environment timeouts (all budget-marked), 8 cascade errors; recorded per `work-plan:417` with revision and reproduction | — |

**P09 overall: NOT PASSED.**

### Correction to criterion 1: it is a moving target, not a three-way choice (2026-10-01)

This cell used to read that the Boring side was "**undecided — three-way**
(`2159c657` prepared / `e1c65975` partial / `0a5c42a7` nothing)", blocked by a **gate owner
decision**. Reading the source material instead of the summary changes both halves.

**1. The three are not alternatives — they are three points on one line, in order.**
Measured on the base branch:

| Commit | Message | Relation |
|---|---|---|
| `2159c657` | `refactor(compiler): migrate target comparison policy consumers` | ancestor of `e1c65975` |
| `e1c65975` | `merge: integrate fix/rust-readonly-alias-emitter …` | ancestor of `0a5c42a7` |
| `0a5c42a7` | `baseline` | 9 commits past `2159c657` |

All three are **ancestors of the base branch**, and its head is **124 commits past `0a5c42a7`**
on the local ref (see the table below for the ref that matters).

**Correction, second pass (2026-10-01).** An independent recheck refuted this section's first
pass; the full measurement is in `evidence/layered-verification-review/P09-CRITERION1-RECHECK.md`.
**The ancestry and the order above are confirmed. The inference the first pass drew from them is
withdrawn, together with two figures.** Recorded here rather than quietly replaced, because the
first pass's two errors are each a reusable trap:

**1. "They are all ancestors, therefore it is not a choice" is a non sequitur.** Being three
ancestors of one branch is *exactly* what makes them three **candidate pins**; the ancestor set of
a branch has more than one element. Ancestry reduces the choice to **a position on a line** — it
does not remove it.

**2. The first pass quoted half a conjunction and rendered it as an opposition.** The sentence it
cited — *"Boring side: STILL UNDECIDED, and the ground has shifted again"* — is verbatim accurate,
but the report asserts **both** halves; the first pass turned the "and" into a "not". Three
sentences from the same report, none of them quoted by the first pass, settle the reading:

- §5 closing: *"Therefore: the pair is half-fixed. **The Boring side is the single open
  decision**; without it no stage command may legitimately be run."*
- §6 heading: *"**Decider's** minimum (everything cited exists on disk)"*
- §6 item 1: *"**Decide the pair and write it down**: Tiqian `8504d230…` × Boring `2159c657` …
  **or** `e1c65975` … **or** re-select at current HEAD"* — and per the same report's `:25`,
  "current HEAD" **is** `0a5c42a7`, so this is the same three candidates.

The pre-existing scope audit had **already** recorded the ancestry (*"`2159c657` **is** an
ancestor of HEAD but is 8 commits behind"*, `dc-warn/out/p09-tiqian-scope/REPORT.md:136`) and
still framed the side as open (*":286"* "*still an open decision*"; *":410"* "*Choose Boring side:
`2159c657…` … **or** `e1c65975`*"). **Ancestry was never the reason the criterion was open** —
which is the single most useful thing this recheck produced.

**So the criterion IS blocked on a decision**, as the cell said before the first pass rewrote it.
What survives from the first pass, stated at its true strength: the decision has a **stated
preference with a reason** (item 3 below), and the ground has **measurably moved** (item 2).
Neither removes the need to pick.

**And there are two grounds, not one.** The same cell's own delivery rule (below, "reachable
from a commit that is on a remote ref") means the pin has to name a **remote** ref, so the
distance that matters is not the local one:

| Ref | Commit | Commits past `0a5c42a7` |
|---|---|---|
| `arch/agent-guided-governance` (local) | `0641991b` | **124** |
| `origin/arch/agent-guided-governance` | `372c42a6` | **167** |

The local base is an **ancestor of the remote one** (remote is 43 commits further), so the
two do not disagree — the remote is simply ahead, and a pin quoted against the local ref
would understate the drift by 43 commits and would not be obtainable by a clone. **Under the
delivery rule the operative figure is 167; "124" is true of a local ref but is incomplete and
misleading as a headline.** This is the same defect the delivery-surface audit recorded, now
attached to the very criterion that needs a pin.

**Dating caveat on the remote-tracking refs.** At recheck time
`origin/arch/agent-guided-governance` and `origin/ci/collected-suite-failure-attribution` both
resolved to the **same object** `372c42a6`, and the first-pass commits (`18d44ec1`, `696acd93`)
are themselves **local-only** — no remote ref contains them. So the two remote names give no
independent corroboration of each other right now. Separately, the `115` figure elsewhere in this
ledger is **stale, not wrong-at-the-time**: `c9e2cff9` is now **131** behind the local base and
the relationship has since **inverted**. Date it or drop it.

**2. The ground has measurably moved — and one pair of numbers must never be quoted as a trend.**
The drift is measured **from `2159c657`**, which is what both source reports do:
`2159c657`→HEAD = **8** (scope audit `:136`) → **10** (feasibility `:25`); today the base is
**124** past `0a5c42a7` locally and **167** on the remote.

The first pass wrote *"9 commits then, 124 … now"*. **Those are unlike quantities:** 9 is the
**fixed span between the three candidates** (`2159c657..0a5c42a7` — a property of the commit
graph that cannot change), while 124/167 is the **drift of the base past `0a5c42a7`**. Putting
them on one line made two measurements look like one time series. Quote 9 as the inter-candidate
span, 124/167 as the drift, never as a trend.

**3. The report states a preference, not a determination** — the first pass over-read this too:
pinning `2159c657` *"would freeze a candidate that predates both Rust fixes **and** the
additional `0a5c42a7` compiler work. That contradicts the evident intent of 'baseline'."*
Choosing `e1c65975` instead requires the alternate staging snapshot and a full
re-preparation whose per-file hashes were never verified. **But this is a preference with a
stated reason, not a determination.** The same report goes on to list choosing `e1c65975` and
choosing `0a5c42a7` as live options, and closes item 1 of §6 by handing all three to a decider.
The first pass's claim that the criterion is *"no longer blocked on a decision"* and *"not a
question for the gate owner"* has **no sentence in the source supporting it and two opposing it**.
What the report supports is: *there is a stated reason against pinning `2159c657`*. That is what
is recorded here.

**4. The `304ed70c` divergence — the same remote-ref standard must apply here, and the first
pass failed to apply it.**
The report's headline finding is that the Tiqian flake pins Boring lineage `304ed70c`. The report
records *"merge-base `378dfdbf`; `rev-list 304ed70c..HEAD` = 150"*. Every element of that
parenthetical **reproduces exactly** when `HEAD` is read as `0a5c42a7` — which is the report's own
reading, since `:25` names `0a5c42a7` "Boring coordinator HEAD". So the figure is neither
fabricated nor irreproducible; it is anchored to a commit the report names, and the first pass
dropped the anchor.

**But the first pass then stated the divergence in the present tense without applying the very
standard it had just used for 124/167.** Measured against the refs that matter:

| Ref | `304ed70c` an ancestor? | `rev-list <ref>..304ed70c` |
|---|---|---|
| `origin/arch/agent-guided-governance` (remote base) | **YES** | **0** |
| `arch/agent-guided-governance` (local base) | no | 274 |
| `0a5c42a7` (the report's HEAD) | no | 150 |
| `ci/collected-suite-failure-attribution` | no | 349 |

`git merge-base origin/arch/agent-guided-governance 304ed70c` returns **`304ed70c` itself**, i.e.
that lineage is an **ancestor of the remote base** — the divergence has **already been closed by a
merge**, and the convergence point falls inside the 43-commit window by which the local base lags
the remote one.

**So the present-tense claim "the two halves are natively pinned to divergent Boring lineages" is
withdrawn**, and `150` must always carry its anchor (`0a5c42a7`) — never a bare "HEAD". What
remains true and still matters for a P09 run: the runbook handles the flake mapping **by
procedure** (`HAXELIB_PATH` shadowing, verified resolving to the fixed snapshot) rather than by
revision identity, so **a run must never rely on the flake's default mapping**. Any revision pair
recorded for criterion 1 has to state that explicitly, or the pair is not self-describing.

**What this changes:** criterion 1 stays **FAIL** (no pair is recorded). It **is** blocked on a
**decision** — the source report calls the Boring side "the single open decision" and hands three
options to a decider — and it is **not** blocked on an environment limit. What the recheck adds is
that the decision has a stated preference with a reason (item 3) and that the ground has
measurably moved (item 2); it does **not** remove the need to pick.

**Checkout presence, established 2026-10-01 (adds a fact; changes no verdict).**
A search for the Tiqian tree failed once and was reported as "no consumer exists".
That was **imprecise**, and the accurate statement matters because it points at
different next actions. Three Tiqian checkouts **are** present:

| Path | HEAD (Tiqian repository, not this one) | holds `8504d230` (frozen rev, Tiqian repository)? |
|---|---|---|
| `/home/losses/Development/tiqian` | `f5c48441` Tiqian repository | **no** |
| `/home/losses/Development/tiqian-master` | `1ad3816` Tiqian repository | **no** |
| `/home/losses/Development/tiqian-f64only` | `3d52039d` Tiqian repository | **no** |

**All four hashes above are commits in the Tiqian repository, not this one** —
`git cat-file` here cannot resolve any of them, and that is expected rather than
staleness. (Stated because a bare hash reads as locally resolvable; the
reference-integrity guard flags exactly this, and did.)

`/home/losses/Development/tiqian/engine-haxe` is a real consumer: `src/`,
`tests/` with `compile.hxml`, oracles, `baseline-goldens/`, and a spec that uses
`-lib boring`, `Intercept.run` and `-D boring_oracle` — the integration this
project compiles against.

**So the blocker is not "there is nothing to run against".** It is narrower and
more tractable: the checkouts exist, **none is at the settled revision
`8504d230`** (a commit in the Tiqian repository, not this one), and criterion 1
additionally needs the Boring side decided.

**Why the distinction is worth recording:** "no consumer exists" invites building
one or declaring the clause impossible. "The consumer exists but not at the pinned
revision" invites **fetching that revision** — a different, cheaper task, and one
criterion 3 is actually waiting on.

**Fetching it was then attempted, 2026-10-01 — and it is blocked, for a reason
worth naming.** The remote is reachable and the checkout has one:

```
$ git -C /home/losses/Development/tiqian remote -v
origin    https://github.com/Losses/tiqian.git (fetch)
$ git -C /home/losses/Development/tiqian ls-remote origin | head -1
0d3ded4b…  HEAD
```

but the fetch itself fails on the sandbox, not on the revision:

```
$ git fetch origin 8504d230228e8206689a2049bbb84b671c1f079a
error: cannot open '.git/FETCH_HEAD': Permission denied

$ touch /home/losses/Development/tiqian/.git/probe
touch: cannot touch '…': Permission denied
```

`.git` reads as writable by mode, and the denial is the sandbox refusing writes
**outside the workspace** — the same boundary that blocks `nix develop` and the
Swift lane. So the accurate status of the Tiqian side is:

| Question | Answer |
|---|---|
| does a consumer exist? | **yes** — three checkouts |
| at the settled revision? | **no** |
| is the revision on the remote? | **not as an advertised ref**; it would need fetch-by-SHA |
| can it be fetched **into that checkout**? | **no** — sandbox denies writes to its `.git` |

**SUPERSEDED within the same session: it CAN be obtained — clone into the
workspace.** The row above answers "can that checkout be updated", which is not
the question the criterion needs. Writing **inside** the workspace is permitted:

```
$ cd /home/losses/Development/tq-workspace
$ git clone --filter=blob:none --no-checkout https://github.com/Losses/tiqian.git .tiqian-probe
Cloning into '.tiqian-probe'...            # rc=0

$ git -C .tiqian-probe cat-file -t 8504d230228e8206689a2049bbb84b671c1f079a
commit
$ git -C .tiqian-probe log --oneline -1 8504d230…
8504d230 fix(ffi-js): pass the rubySpans argument the LayoutInput call omits
$ git -C .tiqian-probe cat-file -e 8504d230…:engine-haxe/tests/compile.hxml && echo PRESENT
PRESENT
```

So **the frozen Tiqian input `8504d230` (a commit in the Tiqian repository, not
this one) is obtainable, and the consumer is present at that revision**
(`engine-haxe` and its `tests/compile.hxml` both verified in the tree). The status
table becomes:

| Question | Answer |
|---|---|
| does a consumer exist? | **yes** — three checkouts |
| is the settled revision obtainable? | **yes** — clone into the workspace |
| does `engine-haxe` exist at that revision? | **yes**, with `tests/compile.hxml` |
| is the repo a fourth environment limit? | **no** — that reading was wrong |

**What remains before P09 criterion 3 can run** is therefore **not** an environment
limit: it is (a) criterion 1's **Boring side**, still undecided three-way, and
(b) deciding to spend the run. The environment no longer blocks it.

**Why the earlier reading was wrong, recorded rather than quietly replaced:** the
blocked command was *"fetch into the existing checkout"*, and the conclusion drawn
was *"the revision cannot be obtained"*. Those are different questions — the
workspace is writable, the checkout is not. Generalising from one blocked form to
the whole capability is the same error shape as concluding "the trees are clean"
from checking one cause.

**Superseded (kept so the same error is not repeated):** an earlier version of this
paragraph called the Tiqian checkout "a fourth independent environment limit" and
said the next action needed an environment with write access to it. Both halves are
wrong, and the feasibility report settles why.

### What actually blocks criterion 3 — a DECISION, not an environment limit

Read from `docs/architecture/evidence/ledger-cited-reports/p09-tiqian-feasibility-REPORT.md`, the blockers are:

| Blocker | Kind | Evidence |
|---|---|---|
| **B4 authorization** | **a decision** | `manifest.json` `protocolCException.status = "requires-execution-authorization"`; `protocol-c afterGen` must not run without an explicit authorization |
| **Write mandate on the run location** | **a constraint the seat accepted** | every stage's cwd is the locked `tiqian-validation-round2` worktree; that seat's mandate made it read-only, so it did not start the matrix |

Neither is an environment limit, and neither is a capability gap. The toolchain,
pinned inputs, driver, haxelib shadowing and the Swift fallback recipe were **all
verified working** by that report — the Tiqian half is *locally executable*.

**Two premises the report also records as moved** (they would change how a run is
read): Tiqian's flake natively pins a **different, divergent** Boring lineage
(`304ed70c`, not an ancestor of HEAD), handled by procedure via
`HAXELIB_PATH` shadowing rather than by revision identity; and the 30-manifest hash
invariant is **PARTIAL FAIL today** (17/30 match — 13 originals mismatch, all 15
derived live inputs still match).

So the accurate status of criterion 3 is: **startable in principle, gated on an
authorization decision and on a seat whose mandate permits writing there.** The
next action is a decision, which is the gate owner's, not a code change.

## P10 — "Classify review failures, revise the appropriate documents, and publish the first round's acceptance and reflection record." (`work-plan:220`, unchecked)

| # | Criterion | Verdict | Evidence | Blocked by |
|---|---|---|---|---|
| 1 | Review failures classified | **PASS (drafted)** | `docs/architecture/ACCEPTANCE-REFLECTION.md` §2 — four kinds × owner (candidate fault / pre-existing repo state / missing documentation) [DOC; published in-repo by `ec4c5c2d`] | — |
| 2 | Appropriate documents revised | **PARTIAL** | record corrections landed, and the surviving record is now the published in-repo revision (`docs/architecture/ACCEPTANCE-REFLECTION.md`, 368 lines, commit `ec4c5c2d`); two reviews' citations were re-anchored (`out/reanchor-v2/`) [DOC] | seat 5 |
| 3 | Acceptance and reflection record published | **PARTIAL** | **superseded fact**: the record no longer lives only in scratch — it is published in the repository at `docs/architecture/ACCEPTANCE-REFLECTION.md` (commit `ec4c5c2d`, 2026-09-30, "docs(architecture): publish the acceptance and reflection record"). Verdict stays PARTIAL because the published record is still marked DRAFT for gate sign-off, and sign-off is the gate owner's verb, not the ledger's | gate owner |

**P10 overall: NOT PASSED.** The publication verb is discharged in-repo (`ec4c5c2d`), which
reconciles the ledger with the published fact; the conclusion is not changed — the work-plan
checkbox stays unchecked (`work-plan:220`) pending gate-owner sign-off, and publishing a
DRAFT record is not gate acceptance (the same rule as `plan:93-94`, "committing is not
accepting", applied to publishing).

## P12 — "Publish the programme review, accepted revisions, evidence gaps, and next scheduled mechanisms. Close the goal only when its criteria hold." (`work-plan:225`, unchecked)

| # | Criterion | Verdict | Evidence | Blocked by |
|---|---|---|---|---|
| 1 | Five-target survey mapping failures to responsibilities, unknowns recorded | **PASS (first-cycle reading)** | `out/p12-programme-review/PROGRAMME-REVIEW.md` §1 [DOC]; expanded-scope reading NOT ESTABLISHED | — |
| 2 | Documents with clear ownership for each decision kind | **PASS** | `work-plan:36-72` [DOC]; independently re-verified in `out/p12-xcheck/` | — |
| 3 | One mechanism change completed through its consumers | **FAIL** | see P08; `plan:160-162` forecloses the loose reading | seat 1/3/4 |
| 4 | Accepted candidate + fresh Boring checks + Tiqian regression from a recorded pair | **FAIL** | see P09 | seat 5 |
| 5 | Later task exercises revised guidance, with failures recorded | **PASS (with caveats)** | P11 fixture accepted; `x-guidance-evaluation.md:95`; the plan's own caveat "Passing tests alone do not establish this condition." | — |

**P12 overall: NOT PASSED. Per P12's own closure rule, the goal must not be closed.**
Independently re-judged and confirmed at `out/p12-xcheck/REPORT.md`.

---

## The one open question that changes several rows

`0a5c42a7` committed the frozen P08 candidate **byte-exact** (verified: recomputed
`bf7dde2c…` = `FREEZE` §6.2's candidate hash) plus four board-accepted fix rows and
the P09 runbook. **Committing is not accepting** (`plan:93-94`), so this does not
move any verdict above. But it means the candidate now has a revision identity in
version control, which is what P08 condition 1 and the re-freeze both need.

## What would move each FAIL

| Row | Needs |
|---|---|
| P08-2 | the `will never be executed` diagnostic cleared, or its `-c` criterion ruled on by the gate owner (board row t-muo92xms-s28t) |
| P08-4 | a second, independent acceptance on the **same** frozen revision |
| P09-1 | a Boring-side revision decision by the gate owner |
| P09-5 | **DONE** (`695940e8` collects; `40e94772` records the enumeration) |
| P10-3 | **DONE** (`ec4c5c2d` publishes the record at `docs/architecture/ACCEPTANCE-REFLECTION.md`); the row's remaining half is the gate owner's sign-off of the published record |
| P12-3/4 | the above |

## Delivery integrity — measured, not assumed (2026-09-30, coordinator)

### Correction (same day, after an independent reachability audit)

The rule below said "reachable from a commit". An independent audit showed that is **not
enough**, and that this session's own deliveries fail the stronger test. Measured:

    git ls-remote --heads origin                    10 heads, none matching ci/* or audit/*
    branch -r --contains <this session's commits>   empty, for all five sampled
    origin/arch/agent-guided-governance             c9e2cff9, 115 commits behind local

So every "merged into base" in this session means **merged into a local branch only**. A
fresh clone gets neither the base branch nor any of the work. The rule is therefore:
reachable from a commit **that is on a remote ref**. Run all three - `ls-remote --heads
origin <branch>` non-empty, `branch -r --contains HEAD` non-empty, and record
`rev-list --count origin/<branch>..<branch>` - and if any fails, the claim is "local only",
not "delivered".

Two companion gaps the same audit measured: the `dc-warn` ignore rule lives in the LOCAL
`.git/info/exclude:7`, so a clone does not even carry the reason those paths are
unreachable; and of 43 `*.sha256` manifests, only 5 verify with `rc=0` from the repo root -
several of the rest record bytes that exist in **no commit at all**, yet match an
uncommitted worktree copy byte for byte.

### The original measurement

A gate decision may only rest on work that is reachable from a commit. I measured the
delivery surface rather than trusting the board's fields:

    dc-warn/worktrees/          37 worktrees
    detached HEAD               37 of 37
    with uncommitted changes    37 of 37
    commits beyond e1c65975     0  (spot-checked charcodeat, promoted-eval, enum-switch)

So the working convention for this effort has been "do it in a detached worktree, write the
conclusions into dc-warn/out/, do not commit". Three consequences, each hit in practice:

1. **Not reproducible.** The sha256 lists in the reports anchor files that exist only in a
   worktree. A clone cannot obtain them. (PIT-285 and PIT-330 recorded one instance each;
   the charCodeAt fixture family is a third - I verified 20/20 byte-identical on disk, but
   the files are on no branch.)
2. **Not decidable.** A criterion that says "this defect is fixed" without saying on which
   tree cannot distinguish branch-state from base-state, so both can claim to satisfy it.
3. **Board fields do not locate work.** Every readyForReview row in this milestone names a
   branch that does not exist (`git rev-parse --verify` fails). The `branch` field is a
   label, not a pointer. Worse, it invites reading "correct on a branch" as "in effect in
   base".

### The three-step check a sign-off must run

    git rev-parse --verify <branch>                    # does it exist at all
    git merge-base --is-ancestor <commit> arch/agent-guided-governance   # is it in base
    read the actual file in the shared tree            # what state is base really in

The third step is not optional. For tools/roots-guard/ the base copy (introduced at
0a5c42a7) validates only that a `reason` field is present and non-empty, while the hardened
copy on fix/roots-guard-defeat-classes (1cafaa42, +923 lines, NOT an ancestor of base)
additionally rejects reasons under 4 words. The two copies reach OPPOSITE verdicts on the
same input: deleting the real root boring.ArraySliceOps from examples/kotlin-f32.hxml and
exempting it with the one-word reason "because" gave **rc=0 PASS on the base copy at the
time of this observation** - that is, at 0a5c42a7, BEFORE the hardening landed - and rc=1
with a named diagnostic on the hardened copy. **The current base now gives rc=1**, because
that hardening has since landed as `8b32f8a0`; read the rc=0 reading as a historical one,
not as a claim about the tree you are holding. That hardening is row
gate/land-roots-guard-hardening.

(The time-scoping above was added after an independent audit pointed out that the present
tense made a true-then claim read as false now - a reader checking it against the current
tree finds rc=1 and would conclude this ledger is wrong. Same failure mode as the
delivery-integrity correction at the top of this file: a claim true when written, read as
if still true.)

### Effect on this ledger

- Acceptance criteria from here on state **which tree** the claim holds on, and carry the
  commit hash plus whether that commit is an ancestor of base.
- Load-bearing artifacts (tools, guards, fixtures, drivers, assertion scripts) must be
  committed. Evidence may live in reports; artifacts may not.
- Rows already signed off in this round were signed on work I reproduced myself, and each
  sign-off records the landing state explicitly rather than implying it.

## Update: the build-phase diagnostic question is answered

`t-muo92xms-s28t` (the P08-2 need above) now has a ruling of record:
docs/architecture/rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md (commit 3e2e7cde on
gate/build-phase-diagnostic-standard; **not yet in base at the time of writing**). It holds
that build-phase diagnostics DO fall under 02-translator-implementation-standard.md:78/:80,
that the standard's naming of only "the Swift type-checker" is a drafting omission rather
than an intentional exemption, and that excluding build-phase diagnostics would make the
zero-warning criterion non-falsifiable.

I reproduced the two load-bearing claims rather than accepting the prose:
  baseline  swiftc -c -WMO -> 1 diagnostic (gen/gap/Gap.swift:117:9 will never be executed)
  after S1  swiftc -c -WMO -> 0 diagnostics; object 278824 B in both states
Count diagnostics by `file:line:col: severity` shape, NOT by `grep 'warning:'`, which returns
2 on the baseline because Swift also prints a caret line. The naive count would have made a
correct fix look like a false claim.

## Independent audit of the session-integration batch (run-102)

I commissioned an adversarial audit of everything this session merged into base (from
5a8f19e6 to the then-tip), briefed explicitly to FIND COUNTEREXAMPLES rather than to
restate the claims. It returned three partly-confirmed verdicts out of six findings. I
reproduced the actionable ones; all three were real defects in work I had signed off.

1. **charCodeAt `FILES.sha256` claimed "one command, rc=0" — false from a clean tree.**
   Two of its 22 entries pointed at `dc-warn/out/...`, and `dc-warn/` is git-ignored with
   zero tracked files. The claim held only on a working copy that happens to have the
   mount. Fixed by splitting the file into SECTION 1 repo-verifiable (verifies standalone:
   rc=0, 20/20 from the base repo root) and SECTION 2 evidence-only, which states plainly
   that those paths do not resolve in a clone. The whole-file check still fails with
   exactly those 2 dangling, so nothing is hidden.

2. **My own sign-off wording on `t-munebyud-bxbr` overstated the predicate's scope.**
   I wrote that registration and lookup share "the single identity predicate". In fact
   `Compiler.hx:2584-2587` computes the absorbed arm's key inline (`? enumName`) and calls
   `throwGrowthKey` only on the unabsorbed arm. The code is correct and documented for both
   arms; the over-claim was in my confirmation text. Corrected on the row.

3. **host-String `CLOSURE.md` carried a sentence that has since gone stale.** It said four
   timeout-budget commits were "branch state, not in effect on base"; all four are
   ancestors of the current base now. The original wording is kept and a dated coordinator
   note records that the state changed, rather than rewriting the sentence.

Two further audit caveats I accept as scope statements rather than regressions:
`registerFaultConversion`/`enumGrowthFor` key the growth table by bare enum name (predates
this batch; the auditor explicitly could not build a compiled counterexample and marked it
an argument, not a measurement), and the predicate cannot see two short-circuits the lookup
performs. Both are recorded as follow-up candidates.

The audit also reported that guard PASS is devShell-dependent (without `.haxelib` it is
rc=1), i.e. not a property of the tracked tree alone.

**Filed follow-up:** `test/wire-payload-key-controls` (t-muoqi2yb-icpu) - the audit's
reproducibility gap: the `pkrev` and `rust-faultnames` controls are in base as fixtures
but no committed command drives them, so the declaration-order discriminating power is
not reproducible from the repository.

The lesson this batch keeps teaching, now recorded three times over (PIT-339, PIT-344,
PIT-346): a claim that holds at the moment it is written gets read later as if it still
holds. Prefer claims that carry their own tree, commit and cwd.

## Two facts measured this session that the ledger did not yet carry

**1. The zero-warning standard now has a gate, and it is a baseline-difference gate.**
Before this session no automated check rejected a target compiler warning at all:
`test:dart` passed `--no-fatal-warnings`, `test:rust` had no `-D warnings`, and the only CI
warning check grepped a log that does not contain the five compilers' output (its search
domain was empty on a passing run). Existing warning stock was Dart 46 / Kotlin 59 /
Rust 4, all rc=0. `tools/warning-gate/check.sh` (commit `90b9c71a`) now runs after all
`gen:*` targets and before the test line, allowing the current count not to exceed the
recorded baselines and failing on any new warning. The baselines were recomputed here
from the audit's own logs, so they are not hand-copied numbers. Clearing the stock to zero
and dropping the baseline to zero is still open - the gate is not compliance yet.

The discriminator worth reusing: inject ONE warning into the SAME tree and run the existing
command versus a strict one. dart loose rc=0 versus strict rc=2; rust loose rc=0 versus
strict rc=101. If both rc agree, the gate does not exist.

**Caveat added 2026-10-01 - this gate can pass VACUOUSLY, and its PASS text is identical
either way.** `check.sh` takes each compiler from `${DART_BIN:-dart}`-style defaults, and in
this environment none of the five are on `PATH` (they live in the nix store). Measured on
base `5c85feb5`, same script, changing only the environment:
- bare PATH -> `dart: loose=127 strict=127 warnings=0 baseline=46` (and likewise for kotlin,
  rust, swift, typescript), then `WARNING GATE PASS`, rc=0.
- real binaries exported (`DART_BIN`/`KOTLINC_BIN`/`CARGO_BIN` pointing into the store) ->
  `dart: loose=0 strict=2 warnings=46 baseline=46`, `kotlin: loose=0 strict=1 warnings=59
  baseline=59`, `rust: loose=0 strict=101 warnings=4 baseline=4`, `WARNING GATE PASS`, rc=0.
`127` is command-not-found, so every count was `0` on an empty log and `0 <= baseline` was
trivially true. **A `warnings=0` reading opposite a non-zero baseline means the compiler
probably did not run, not that the warnings were cleared.** Two columns (swift, typescript)
are still `127` even in the second run: there is no `swift` or `tsc` in this environment, so
those columns remain unmeasured and no zero-warning claim may be made from them. It follows
that the strict-vs-loose discriminator above is necessary but not sufficient - it shows a
column CAN fail, not that this run exercised it. The reproducible form is: **rc=127 means
unmeasured; require at least one column with rc != 127 and count != 0 before reading a PASS.**
The minimal fix is for the script to assert `rc != 127` (or `command -v` each binary up
front), so "did not run" is distinguishable from "ran and found zero". **That fix has since
landed** - see the next entry.

**1b. The vacuous-pass mode is fixed (`f8bb6d40`), and the fix was mutated to prove it did
not weaken anything.** `require_measured()` now checks `rc=127` before the count comparison.
An unmeasured column FAILS by default; `WARNING_GATE_ALLOW_UNMEASURED=1` downgrades it to a
printed skip for environments where a toolchain is genuinely absent, and the PASS line then
reads "N column(s) SKIPPED" instead of claiming every column was measured. Four readings,
same commit, changing only the environment:

| environment | mode | verdict | rc |
|---|---|---|---|
| bare PATH | default | FAIL, 5 columns NOT measured | 1 |
| bare PATH | allow-unmeasured | PASS, 5 columns SKIPPED | 0 |
| 3 real compilers | default | FAIL, swift+tsc NOT measured | 1 |
| 3 real compilers | allow-unmeasured | PASS, 2 columns SKIPPED | 0 |

**Discriminating power is preserved**, which is the half that could have been lost: injecting
ONE warning into the dart tree (46 -> 47) still FAILS under the permissive mode, rc=1, with
`dart: loose=0 strict=2 warnings=47 baseline=46`. So the fix separates "did not run" from "ran
and found zero" without making a real regression pass. The general lesson is the one this
ledger keeps re-learning: **a gate's failure modes must be enumerated, not just its success
path** - here the same PASS string covered "checked and clean" and "never ran".

**2. Which default-argument shapes Haxe actually admits - measured, and it splits.**
Cross-review had warned that spec 22 V16 limits default expressions to compile-time
constants and closed coalescing forms, so a throwing call in a default might be outside
the accepted source domain, which would have cancelled that row. It splits:
a default position holding a call is REJECTED (`rc=1`, "Default argument value should be
constant"), while a coalescing default containing a throwing call is ACCEPTED
(oracle rc=0, with three anchored expectation lines). So the premise holds for the
coalescing spelling only. The fixture also states the boundary that keeps this honest:
acceptance does not prove the site is registered as a coalescing default.

**3. A reachable soundness defect is now measured rather than argued.**
`enumGrowth` is keyed by bare enum name, so two modules declaring a same-named `*Fault`
enum share one bucket: both modules' `EFault` end up declaring
`BFault(Box<crate::cmb::cross_b::B>)`, and `cma`'s throw site constructs `cma`'s `B`,
giving `error[E0308]`. Fixture `tests/haxe/growth-cross/` (`f22f55ab`) reproduces it;
against `05e375b2` it also fails, so the defect predates this batch. A key-strategy fix is
in flight.
