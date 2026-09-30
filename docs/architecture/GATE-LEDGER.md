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
| 1 | Correct fact-and-requirement handoffs; in-scope reconstruction removed | **PARTIAL (improved)** - condition 3 landed as `71a60c7d` | Two destinations are now supplied by their owning composition rather than inferred: `switchExpression` takes an explicit destination (`out/switchexpr-land/` - 4 hunks, byte-identical trees) and `blockExpression` no longer reads `currentReturnType` (`c8ae0054` - a block's value is its own result type). The destination-owner mechanism is still **not** enforced structurally (that work was ordered stopped) | seat 3 |
| 2 | Legal generated output — zero diagnostics on the same candidate inputs | **FAIL (reason changed)** | The two `[#no-usage]` warnings that were the original ground are GONE - W1 is on the line and three independent sessions measured 0/0 on the fixture [MINE + 2 seats]. What fails now is one **build-phase** diagnostic: `swiftc -c` emits `will never be executed` at `Gap.swift:117` (W1's unreachable trailing return). Per the round-145 gate-owner ruling such a diagnostic **COUNTS** against `:78`/`:80`, so the fixture records it as an unwaived deviation and keeps zero diagnostics under `-c` as the stated goal (`tests/swift-gap-boundary/gap-boundary.test.ts`) | seat 1 or a gate-owner ruling on the `-c` criterion |
| 3 | Preserved source behaviour (branches distinguishable, alias, lifetime, single evaluation, lazy effects, control exits) | **PARTIAL** | `dc-warn/out/p08-candidate-freeze/FREEZE.md` §5.3 [DOC]; branch discrimination was broken and is now repaired (`d1180768`); **lazy effects were never measured** (F3, recorded) | seat 4 |
| 4 | Two independently recorded reviews | **FAIL** | behaviour review (`out/p08-behaviour-review/`) non-accepting; implementation review (`out/p08-implementation-review/`) **REJECT** with four open conditions | seat 6 |

**Re-freeze recorded** (`fc89d5d8`, `docs/architecture/REFREEZE.md`): the candidate
identity is now **`c8ae0054`** (chain `a14345ce` -> `28820ff5` -> `c8ae0054`). This is an
identity record, not an acceptance. Any subsequent P08 review must target that revision,
not scratch trees and not the superseded `dc-warn/out/p08-candidate-freeze/FREEZE.md`.

**P08 overall: NOT PASSED.** The candidate is REJECT. Its post-review repair is now complete and on the line - the integration ruling's option (b) was executed as `a14345ce` (revert the lambda half, keep W1) followed by `c8ae0054` (the corrected lambda as one atomic commit) - so the line no longer carries a known regression, and a re-freeze is the next step. What still blocks is the build-phase diagnostic above and the absence of a second independent acceptance on a frozen revision.

## What changed since the previous ledger revision (2026-09-30, later)

| Item | State |
|---|---|
| Candidate identity | **`c8ae0054`**, recorded by `fc89d5d8`; a re-freeze establishes identity, **not** acceptance |
| Condition 3 (destination from the owning composition) | **landed** as `71a60c7d` - `switchExpression` takes an explicit destination and `blockExpression` no longer reads `currentReturnType`; 4 generated trees byte-identical, `swiftc -c` green including a full link + 30/30-line run |
| Six baseline reds | **discharged** as `28820ff5`, `ac4099ea`, `50a95377`, `a80690f1`; record updated by `d36e6d3f` (history preserved, the "judged by mechanism" limit superseded by fresh-tree reproduction) |
| **Contract 3's counting mechanism** | **now a gate, not a printout** (`99ba67fd`): every run extracts warning lines naming generated-tree files, writes count + lines + domain + baseline reconciliation into the job summary, and **fails** on a missing log, an unparseable count, or a count deviating from the recorded baseline. Baseline **0** is measured from the retained `695940e8` proof-run log, not assumed. No `continue-on-error` anywhere in the workflow. |
| Collected domain | **304 files / 55 non-generated**, not 303/54 - `tests/swift-gap-boundary/gap-boundary.test.ts` entered the repo after the CI commit (`d14231a6`). Recorded per the round-195 ruling; baseline pass/fail numbers stay tied to the 303-file domain. |
| `out/` domain guard | kept, and annotated honestly: **present, never triggered - not an exercised guard** |

## P09 — "Run the candidate's required Boring checks and Tiqian checks on fixed revisions…" (`work-plan:218`, unchecked)

| # | Criterion | Verdict | Evidence | Blocked by |
|---|---|---|---|---|
| 1 | A recorded revision pair | **FAIL** | Tiqian side settled (`8504d230`); **Boring side undecided** — three-way (`2159c657` prepared / `e1c65975` partial / `0a5c42a7` nothing) [DOC: `out/p09-tiqian-feasibility/`] | gate owner; decision work ordered stopped pending a stable candidate |
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
