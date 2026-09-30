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
| 3 | Preserved source behaviour (branches distinguishable, alias, lifetime, single evaluation, lazy effects, control exits) | **PARTIAL** | `dc-warn/out/p08-candidate-freeze/FREEZE.md` §5.3 [DOC]; branch discrimination was broken and is now repaired (`d1180768`); **lazy effects are now MEASURED** - `p08-review-1` built a side-effecting probe over four routes (switch / try / ternary / expression-block argument at a ReadOnlyArray destination) and got **7/7 byte-identical to `haxe --interp`**, each showing exactly one arm's effect and exactly one producer call; the P08 behaviour-matrix seat independently measured laziness on three axes at once (effect order, effect count, and **termination**: lazy terminates rc=0 where eager recurses to SIGSEGV rc=139). **F3** was the freeze cross-check's label for "lazy effects were never measured" - it was cited without a definition until now | seat 4 |
| 4 | Two independently recorded reviews | **FAIL** | behaviour review (`out/p08-behaviour-review/`) non-accepting; implementation review (`out/p08-implementation-review/`) **REJECT** with four open conditions | seat 6 |

**Re-freeze recorded** (`fc89d5d8`, `docs/architecture/REFREEZE.md`): the candidate
identity is now **`c8ae0054`** (chain `a14345ce` -> `28820ff5` -> `c8ae0054`). This is an
identity record, not an acceptance. Any subsequent P08 review must target that revision,
not scratch trees and not the superseded `dc-warn/out/p08-candidate-freeze/FREEZE.md`.

**P08 overall: NOT PASSED.** The candidate is REJECT. Its post-review repair is now complete and on the line - the integration ruling's option (b) was executed as `a14345ce` (revert the lambda half, keep W1) followed by `c8ae0054` (the corrected lambda as one atomic commit) - so the line no longer carries a known regression, and a re-freeze is the next step. What still blocks is the build-phase diagnostic above and the absence of a second independent acceptance on a frozen revision.

## Restoring contract 3 - progress against the four conditions

The round-5 ruling downgraded contract 3 to "the gate is implemented; its run
reliability is not achieved" and named four conditions for restoring it. Progress,
recorded under the entry gate below (each line carries a hash or is marked
`in-flight`):

| # | Condition | State |
|---|---|---|
| 1 | repeated generation from clean inputs yields identical bytes and checksums | **in-flight** (`npm-determinism` seat, no hash yet) |
| 2 | the `MathNaNTestSupport.{js,d.ts}` entries are stable; `package-artifacts.test.ts:333` passes repeatedly | **in-flight**, same seat |
| 3 | `collected-suite` no longer fails on the flake, and **its log distinguishes real product/spec failures from environment/timeout failures** | **the attribution half is in-flight** (`ci-attribution` seat); the flake half waits on 1-2 |
| 4 | an independent spec ruling on `package-shell.test.ts:249` | **RESOLVED** - `eec707b9` |

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

**A correction to this record's own history**: `BASELINE-FAILURES.md` had called
this a "product/spec gap" on an "unconditional abort" reading of spec 24. That
reading was wrong; the entry now carries a supersession note preserving the
original text.

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
| **P08 review 1** on the frozen `c8ae0054` | **REJECT** - obligation 2 fails on exactly one build-phase diagnostic; four exact conditions | `dc-warn/out/p08-review-1/REPORT.md` |
| **P08 review 2**, reached independently from a `git archive` export | **REJECT** - same single in-scope ground, not waived; it also confirmed the P08-1 correction is accurate and that **no remaining row credits `c8ae0054` with bytes it lacks** | `dc-warn/out/p08-review-2/REPORT.md` |
| **Timeout-budget commits** (`9905949e`, `36e7540e`, `e8a4c3bb`, `4c292c64`) | **CONFIRMED** on five claims: margins 2.03-2.64x recomputed, no assertion touched, 8/8 cascades explained, changed tests pass, no other regression | `dc-warn/out/verify-timeouts/REPORT.md` |
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
| 1 | A recorded revision pair | **FAIL** | Tiqian side settled (`8504d230`, a commit in the **Tiqian repository**, not this one); **Boring side undecided** — three-way (`2159c657` prepared / `e1c65975` partial / `0a5c42a7` nothing) [DOC: `out/p09-tiqian-feasibility/`] | gate owner; decision work ordered stopped pending a stable candidate |
| 2 | Boring checks executed | **NOT ESTABLISHED** | no run exists | — |
| 3 | Tiqian checks executed | **NOT ESTABLISHED** | `work-plan:108` "the Tiqian candidate gate has not run" [DOC]; feasibility check confirmed the matrix is not startable | B4 authorization + pair |
| 4 | Logs, generated-output identity, warning results preserved | **NOT ESTABLISHED** | preparation artefacts exist but no run produced them | — |
| 5 | Baseline debt has a finite recorded list | **PASS** | `docs/architecture/BASELINE-FAILURES.md` — 1033 tests collected, 1001 pass / 32 fail / 8 errors, classified into 6 pre-existing assertions (judged by mechanism, limit stated), 26 environment timeouts (all budget-marked), 8 cascade errors; recorded per `work-plan:417` with revision and reproduction | — |

**P09 overall: NOT PASSED.**

## P10 — "Classify review failures, revise the appropriate documents, and publish the first round's acceptance and reflection record." (`work-plan:220`, unchecked)

| # | Criterion | Verdict | Evidence | Blocked by |
|---|---|---|---|---|
| 1 | Review failures classified | **PASS (drafted)** | `out/p10-reflection/ACCEPTANCE-REFLECTION.md` — four kinds × owner (candidate fault / pre-existing repo state / missing documentation) [DOC] | — |
| 2 | Appropriate documents revised | **PARTIAL** | record corrections landed in the working copy; **the frozen record revision is now 452 lines**, and two reviews' citations were re-anchored (`out/reanchor-v2/`) | seat 5 |
| 3 | Acceptance and reflection record published | **PARTIAL** | drafted and complete, **but lives in scratch `dc-warn/out/`, not in the repository** | seat 5 |

**P10 overall: NOT PASSED (draft exists; publication is the missing verb).**

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
| P10-3 | the record published into the repository |
| P12-3/4 | the above |
