# P12 cross-verification — xcheck of the programme review's closure refusal

**Date:** 2026-09-30 (America/Toronto). **Reviewer under test:**
`dc-warn/out/p12-programme-review/PROGRAMME-REVIEW.md` (+ its `REPORT.md`).
**Judged against:** `boring-wt-architecture/docs/architecture-work-plan.md` (453 lines, read
in full), the repository, the board (`m-mulwvr32-3jht`), and the retained consultations and
candidate reviews. Read-only outside this output directory.

**Labels.** *verified in plan/repo* = I checked it myself this session (file reads, git
reads, board queries). *review asserts* = the review states it and I checked the underlying
source where the task required it. *not verified* = I could not establish it; the blocker is
named.

**Headline findings before the detail:**

1. **The five criterion quotations are verbatim** (lines 539-549 of the review vs plan
   lines 20-30), the P12 gate quote is verbatim and unchecked, and the `e5e21854` quote is
   accurate and correctly sourced. Three minor citation blemishes are found (section 2).
2. **The closure refusal is sound.** My independent re-judgement agrees with the review on
   all five criteria (section 3), for reasons that do not depend on the review's evidence
   where that evidence is weakest (criterion 2).
3. **The review's anchor is stale, in a way that matters for the record but not for the
   conclusion.** A commit `0a5c42a7 "baseline"` (2026-09-30 11:23:41 local, author "wire")
   was created 5 minutes after the review's board snapshot and committed, for the first
   time, the frozen P08 candidate's bytes into the coordination tree's history, together
   with four board-accepted fix rows and the P09 runbook (section 4). The review's
   `[NOT ESTABLISHED]` row-to-commit mappings are now partially resolved by that commit;
   the W1 fix is still committed nowhere (verified across all refs).
4. **No genuinely accepted work was written off.** The review's accepted-revision count
   (33 board done rows + 10 plan-table commits + `2159c657` with caveats + P11) is complete
   against everything I found; nothing accepted exists outside it (sections 4, 6).

---

## 1. Mandate restatement

The review's central conclusion: the five completion conditions (plan:18-31) do not hold —
criterion 1 holds only in the first-cycle reading, 2 holds, 3 fails, 4 fails, 5 holds with
caveats — and therefore "Per P12, the goal must not be closed." My task: verify the
quotations, re-judge each criterion from the repository, look for written-off completed
work, check the review's honesty claims, and attempt falsification in both directions.

## 2. Quotation verification

Full method and per-quote results: `evidence/verbatim-check.md`.

| # | Review quote (location) | Source (verified line numbers) | Verdict |
|---|---|---|---|
| 1 | Criterion 1, "A revision-specific survey covers TypeScript, Kotlin, Rust, Swift, and Dart, maps recurring failures to compiler responsibilities, and records unknowns." (review §5, line 539-540) | plan:20-21 | **VERBATIM** (line-join) |
| 2 | Criterion 2, "The repository documents task assignment, architectural review, verification, and reflection, with clear ownership for each kind of decision." (review line 540-541) | plan:22-23 | **VERBATIM** |
| 3 | Criterion 3, "Execution agents complete one selected mechanism change through its analysis, representation, lowering, and printing consumers as applicable." (review line 542-543) | plan:24-25 | **VERBATIM** |
| 4 | Criterion 4, "The accepted candidate has fresh Boring checks and the required Tiqian platform regression evidence from a recorded pair of revisions." (review line 544-545) | plan:26-27 | **VERBATIM** |
| 5 | Criterion 5, "A later agent task exercises the revised guidance on another case. Review records whether the agent used the intended reasoning and where guidance still failed. Passing tests alone do not establish this condition" (review line 546-548) | plan:28-30 | **VERBATIM** except the review drops the sentence-final period (plan: "…condition.") |
| 6 | P12 gate, "- [ ] P12: Publish the programme review, accepted revisions, evidence gaps, and next scheduled mechanisms. Close the goal only when its criteria hold." (review lines 22-23) | plan:225-226 | **VERBATIM**; unchecked state **VERIFIED** in the live plan file |
| 7 | `e5e21854` "The Swift array pilot remains an unfinished checkpoint at e5e21854" (review §2.2, "plan delivery table") | plan:101 (delivery table, package A row); reinforced by plan:138-139 and plan:8-10 | **VERBATIM** modulo backticks; attribution **CORRECT**. The characterisation "unfinished checkpoint, not accepted" is accurate — `e5e21854`'s own subject is "checkpoint unfinished Swift arrays and policy migration plan", and the plan says its completion "is no longer a prerequisite for those migrations" (plan:8-9) |
| 8 | plan:108 "the Tiqian candidate gate has not run" (review §5, criterion 4) | plan:108, inside the "Reading the task labels and current delivery" section that opens at plan:93 "This snapshot records the state on 2026-09-28." | **VERBATIM**, but it is a **status-snapshot statement about the 2026-09-28 state**, not a standing requirement (section 3.4) |
| 9 | plan:134 "P08–P10 and P12 remain open pending accepted fixed-input regression evidence" (review §5) | plan:134 | **VERBATIM**, line number exact |
| 10 | plan:186-190 naming-violations carry-forward (review §5 closing) | plan:189-190 | **VERBATIM** |
| 11 | plan:32-34 scope-end paragraph (review §4) | plan:32-34 | **VERBATIM** |

**Minor citation blemishes found (none changes what the review judged):**

- **SOL2 §2 rendering** (review §1.1): the review puts in quote marks "Choose d → a → b → c:
  baseline budget and restoration, refused-cell disposition, consumption repair, then freeze
  and both reviews." Only "Choose d → a → b → c." (SOL2-ARCH-ANSWER.md line 30) is verbatim;
  the colon clause compresses SOL2's four numbered items (baseline budget decision /
  refused-cell disposition / complete the consumption repair / freeze and both reviews).
  A paraphrase inside quote marks; the substance is faithful and the order (d→a→b→c) is the
  verbatim core.
- **freeze-xcheck §5.5.1 attribution** (review §5, criterion 3): the review quotes
  "[DOC: freeze-xcheck §5.5.1] … 'switchExplicitReturn remains a defect carrier in the
  candidate…'". `freeze-xcheck/REPORT.md` has **no section 5.5.1** (its sections are 1-8;
  §5 is "Falsification attempts"), and the phrase "defect carrier" appears in **none** of
  freeze-xcheck, FREEZE.md, p08-behaviour-review, or p08-implementation-review (full-mount
  search still running at write time, but the four candidate documents were searched
  directly). The **substance is verified**: freeze-xcheck §3 (Obligation 2) quotes FREEZE
  §5.2 — "2 warnings (Gap.swift:113, 115 — the known W1 switchExplicitReturn
  swallowed-return; unchanged by the patch)" — and its table row "switchExplicitReturn
  before/after | byte-identical (diff rc=0)". Misattributed citation, verified substance.
- **SOL2's pointer to compiler-policy-architecture.md:151**: line 151 of the current
  document is blank; the "Programme completion" section (lines 152-160) does not contain
  SOL2's sentence "the owner must explicitly settle its finite completion scope before P12
  can close". The review handles this **correctly**: it labels the sentence as
  "[DOC: SOL2 §6, citing compiler-policy-architecture.md:151]", i.e. a consultation
  interpretation, not a plan requirement. So the review did not import SOL2's sentence as
  plan text. (Relevant to section 3.1 below.)

**All other quotes the review relies on were verified in source** (SOL2 §1, ASTRA §1/§2,
CODEX-AUDIT §1/§2/overall judgement, p08-implementation-review §6 REJECT, FREEZE status
line/§0/§6.2, p08-behaviour-review claim ledger, W1 confirm record, queue §75-78,
round-1 responsibility map and work order). See `evidence/verbatim-check.md`.

## 3. Independent per-criterion re-judgement

The review's five verdicts: (1) "First-cycle scope: yes (as the plan records it). Expanded
scope: NOT ESTABLISHED." (2) "Yes (as the plan records it)." (3) "No." (4) "No."
(5) "Yes, with recorded caveats (as the plan records it)."

### 3.1 Criterion 1 — survey. Review: first-cycle yes / expanded NOT ESTABLISHED. **I agree.**

*Verified in plan/repo:*
- P04/P05 are checked in the plan (plan:212-214).
- The round-1 survey is **revision-specific**: `docs/investigations/architecture-round-1.md`
  opens "Baseline and ownership" with "Its compiler baseline is
  `e3b8bab39ac2da0e17e9d04e031f03bd39290274`. This was the remote `master` head when queried
  through the GitHub API during baseline selection."
- It **covers the five targets**: "Task F extends the conversion survey with
  representative paths across all five targets."
- It **maps recurring failures to compiler responsibilities**: the six-row responsibility
  map at round-1.md:237-245 (numeric conversions / string operations / null flow /
  evaluation / identity and sharing / output structure, each with "Facts that must have a
  defined producer" and "Target responsibility").
- It **records unknowns** explicitly: "This remains a sampled architecture survey, with
  runtime behavior and uninspected forms explicitly unresolved," and "The coordinator has
  accepted the initial responsibility map and verification design for planning."

So the first-cycle criterion holds as a **verified repository fact**, not merely "as the
plan records it" — the survey exists, is revision-anchored, and has the required map and
unknowns. The review's verdict is right, and its evidence is slightly under-specified.

On the "expanded scope" hedge: the criterion's own text does not demand a current finite
list of the expanded programme's migrations; that demand comes from the consultations
(SOL2 §6, CODEX-AUDIT §2 "does not provide a sufficiently current, finite list") and from
the policy doc's "Programme completion" section (compiler-policy-architecture.md:152-160),
which adds "accepted policy decisions, a five-target migration inventory, verified removal
of duplicate decisions…, cross-platform executor review, and integration regression
evidence." The review marks the expanded scope **NOT ESTABLISHED** (a third state, not a
failure) — the right treatment. One precision note for the record: plan:10 says "The
first-cycle criteria below remain required evidence within the expanded work", so the
criterion as written is satisfied inside the expanded work by the round-1 survey; the
expanded programme's *additional* completion requirements are a separate, unsettled
question. The review's phrasing "criterion 1 holds only in the first-cycle reading" is
therefore rhetorically stronger than the plan's text requires — but the review itself
splits the verdict exactly this way (yes / NOT ESTABLISHED), so the conclusion is not
affected.

### 3.2 Criterion 2 — documented governance. Review: "Yes (as the plan records it)." **I agree — and the check is real, not a deferral, though the review presents it as one.**

The review's own evidence for this criterion is: [DOC: plan:36-72] Roles/authority +
Document responsibilities, P06 checked, "no counter-evidence in the sources I read." That
is a deferral to the plan's self-description. **But the plan's claims are directly
verifiable, and I verified them:**

- `AGENT.md` (12.9 KB) — entry instructions and required reading, exists.
- `docs/compiler-problem-analysis.md` (27.8 KB) — diagnosis method and reasoning record, exists.
- `docs/compiler-policy-architecture.md` (10.9 KB) — policy architecture and task
  boundaries, exists.
- `docs/specs/style/02-translator-implementation-standard.md` (9.7 KB) — I read it: it
  contains binding **layer ownership** rules ("Decision code … lives in the shared layer",
  "Rendering code lives in the target printer", "Adding a new copy of an existing shared
  mechanism inside a target printer fails review"), a fixed consolidation procedure with
  three verdict classes, and an acceptance/verification procedure (Step 2: regenerate every
  `boring.json` configuration, byte-identical untouched targets, consistency checks).
- **Task assignment and review records**: `docs/investigations/architecture-round-1.md` +
  `architecture-round-2.md`, plus 10 round-1 records and 17 round-2 records (briefs,
  `-review.md` files, acceptance records, the P09 runbook).
- **Reflection**: plan §"Reflection and guidance evaluation" (method + required
  observations) plus `x-guidance-evaluation.md`, which records actual coordinator
  interventions (section 3.5).
- **Clear ownership for each kind of decision**: plan:36-47 (coordinator vs execution
  agents; "Each task has a semantic owner"; "Each changed backend has one integration
  owner"; "Shared modules also have one assigned writer at a time") — and the plan's own
  Document-responsibilities table (plan:59-65) assigns decision kinds to documents.

So: **criterion 2 holds as a verifiable repository fact.** The review's "as the plan
records it" phrasing understates what could have been (and was, by me) checked; the
conclusion is correct either way.

### 3.3 Criterion 3 — one selected mechanism completed through its consumers. Review: "No." **I agree — and the review did NOT import a stricter reading than the plan states.**

This is the criterion the task asked me to probe hardest, because the phrasing matters.

**The plan's own wording** (plan:24-25, verified verbatim in section 2): "Execution agents
**complete** one selected mechanism change through its analysis, representation, lowering,
and printing consumers as applicable." The operative verb is *complete*. The plan nowhere
permits a *selected-and-specified-but-incomplete* mechanism to satisfy criterion 3. The
review's reading (the selected mechanism must be finished and accepted through its
consumers) is the plan's own standard, not an import. Three plan-internal anchors confirm:

1. **plan:160-162** (verified verbatim): "A3's five-target runtime comparison observations
   now inform a shared comparison plan and its first Swift consumer, integrated at
   4581308d. … **These tasks do not complete P08's mechanism migration or P09's regression
   requirements.**" The plan itself denies that the integrated round-2 consumer work
   (A3/B1/B2) counts as completing the selected mechanism.
2. **The selected mechanism is the Swift array boundary**: plan:293-299 ("Select the first
   mechanism after the investigations. Swift mutable and read-only array conversion is a
   candidate from earlier inspection.") and P07 (checked) / P08 (unchecked): "Delegate
   reproduction and behaviour tests, then implementation. **Independently review both
   before accepting a candidate.**"
3. **plan:93-94** (verified): "A committed checkpoint makes code reviewable; **it does not
   mean its consumers or regression gate passed.**" So even the new `0a5c42a7` baseline
   commit, which committed the candidate's bytes into HEAD (section 4), cannot satisfy
   criterion 3.

**State of the selected mechanism (verified in plan/repo):**
- The frozen candidate exists, is reproducible byte-for-byte, and was independently
  re-verified (FREEZE.md, freeze-xcheck CONFIRMED) — *review asserts + I re-verified the
  candidate hash by recompute*: `git show 0a5c42a7:packages/compiler/reflaxe/swift/
  swiftcompiler/SwiftExpr.hx | sha256sum` = `bf7dde2cec3b…` = FREEZE §6.2 candidate hash.
- **But it is not accepted**: p08-implementation-review §6 "Verdict — **REJECT** the
  candidate for P08 acceptance … REJECT, with these exact conditions" (4 unresolved
  conditions: W1 defect, Gap cell 12 errors, coalescedBoundary refusal cell, durable
  collection wiring); p08-behaviour-review claim ledger records "Gap fixture: generation
  rc=0, **swiftc rc=1 with 12 errors** / 2 warnings" and "O-B is collected nowhere in the
  repo"; FREEZE §0 "It does **not** accept the candidate"; the P08 gate row
  (t-munq08t2-rgxp) is `todo`, 0/3, unclaimed (verified on the board, section 4).
- The W1 defect is still in the candidate's bytes (freeze-xcheck: switchExplicitReturn
  function byte-identical base-vs-candidate; warnings unchanged) — and the W1 fix is
  **committed nowhere** in the repository (section 4).

**The alternative reading that could falsify the review** — that some *other* "one
selected mechanism change" was completed through its consumers (e.g. the finite-comparison
consumer migration `4581308d` + the four-target migration `2159c657`, each with focused
acceptance and four done re-review rows) — is foreclosed by plan:160-162 quoted above: the
plan expressly says those tasks "do not complete P08's mechanism migration", and P07/P08
are the plan's own selection/acceptance gates for *the* selected mechanism. The review
cites plan:160 in its §2.2, so it does address this alternative.

**Verdict: I agree with the review's "No" on criterion 3.** The failure is robust to the
strict/loose reading question: even the loose reading ("execution agents finished the
implementation through its consumers") fails, because the behaviour review found the
mechanism does not pass through its printing consumers today (the generated Gap cell
does not compile: 12 errors).

### 3.4 Criterion 4 — accepted candidate with fresh Boring + Tiqian evidence from a recorded pair. Review: "No", relying in part on plan:108. **I agree; the plan:108 reliance is defensible but the line is a stale-status note, and the deeper failure is independently verified.**

**plan:108 in context** (verified verbatim, section 2): "The fixed Tiqian revision is
prepared, but the Tiqian candidate gate has not run." It sits inside the "Reading the task
labels and current delivery" section, which opens (plan:93) with "This snapshot records the
state on 2026-09-28." So **line 108 is a status-snapshot statement about the 2026-09-28
state** — a statement about the past as of the snapshot, not a standing requirement and not
a free-floating note. The standing requirements for criterion 4 are the criterion itself,
the P09 gate (plan:220-221: "Verify the accepted candidate on the fixed Boring revision and
the required Tiqian fixed inputs" — unchecked), and plan:134. The review's use of plan:108
as *evidence* that the gate has not run is therefore legitimate only as "the plan's own
latest status record, with nothing in retained evidence showing a later run" — and that
"nothing shows a later run" is what I independently verified (section 6.1):

- No P09 execution evidence anywhere: the board's P09 rows are prep/audit/doing only;
  `audit/p09-fixed-matrix-preparation` (done) accepted **static preparation only** — its
  confirm record states the acceptance "不宣称全矩阵已执行或通过" (does not claim the full
  matrix was executed or passed).
- The P09 runbook (committed in `0a5c42a7`) is `status: preparation-only-not-executed`,
  `generationStarted: false`.
- The newest independent check (dc-warn/out/p09-tiqian-feasibility, 2026-09-30 11:47,
  post-review) finds the matrix "not safely startable" (locked worktree + open B4 gate),
  and that the preparation's manifest invariant **now fails** (13 of 30 pinned original
  hashes mismatch) — the prepared fixed pair is stale, and per the runbook's B1 rule the
  since-merged Rust fixes would force re-selection of the fixed revision.

**The deeper failure, which does not depend on plan:108 at all:** criterion 4's first
clause requires "**the accepted candidate**". There is no accepted candidate (section
3.3: P08 `todo`, REJECT verdict, no acceptance record). So criterion 4 fails on its first
clause alone; the Tiqian-gate question is secondary. The review's "No" is correct and
over-determined.

**Verdict: I agree with the review's "No". Precision correction:** plan:108 is a
2026-09-28 status snapshot, not a standing requirement; the review's evidence would be
stronger anchored on P09 (unchecked) + plan:134 + "no accepted candidate" + "no run
record". The review does cite P09/plan:134 as well, so the conclusion is unaffected.

### 3.5 Criterion 5 — later agent task exercises revised guidance. Review: "Yes, with recorded caveats (as the plan records it)." **I agree — and this one is genuinely verified, with the caveats recorded in the evaluation itself.**

*Verified in plan/repo:*
- P11 is checked (plan:222-224), and plan:236-239 records the exercise: "The
  storage-lifetime exercise was assigned to Goose at db1bb984, with an initial reasoning
  review before fixture implementation. Its focused fixture and guidance evaluation are
  accepted after integration replay, with the required coordinator interventions
  recorded."
- `docs/investigations/architecture-round-1/x-guidance-evaluation.md` (146 lines) exists
  and does exactly what criterion 5 requires: it records **whether the agent used the
  intended reasoning** ("The guidance helped the executor identify the source-language
  semantic basis and distinguish binding, container and element identity") and **where
  guidance still failed** ("The coordinator supplied the decisive post-return mutation case
  and required corrections to evidence handling. These interventions limit the outcome: P11
  establishes a completed guided exercise, with independent delivery review. It does not
  establish reliable unaided execution of the documented method." + runner-failure
  deviations recorded above it).
- The acceptance is an actual acceptance: "The coordinator accepts the eight-file fixture
  after exact-file integration and an independent replay" with retained run IDs and hashes.

So criterion 5 holds with the review's caveats — and the caveats (no reliable unaided
execution; no exhaustive lifetime correctness; no complete J migration) are the
evaluation document's own words, not the review's import. The review's "as the plan
records it" phrasing is again a deferral where direct verification was possible; the
conclusion is correct.

### 3.6 Summary table

| Criterion | Review verdict | My independent verdict | Agreement |
|---|---|---|---|
| 1 survey | first-cycle yes / expanded NOT ESTABLISHED | first-cycle **verified to hold** (survey exists, revision-anchored, map + unknowns); expanded additional requirements unsettled (consultation-level, correctly NOT ESTABLISHED) | **Agree** |
| 2 documented governance | yes (as plan records) | **verified to hold** (AGENT.md, problem-analysis, policy-architecture, 02-standard ownership rules, round-1/2 records all exist with the required content) | **Agree** (review's evidence was a deferral; the check is real) |
| 3 one mechanism completed | No | **No** — plan's own text requires "complete"; selected mechanism (Swift boundary) REJECTed, P08 unchecked, plan:160-162 forecloses the alternative-reading; robust to strict/loose reading | **Agree** (review did not import a stricter reading) |
| 4 accepted candidate + Tiqian evidence | No (partly via plan:108) | **No** — no accepted candidate (first clause fails); no P09 run; plan:108 is a 2026-09-28 status snapshot, not a standing requirement | **Agree** (with the precision correction on plan:108) |
| 5 guidance exercise | yes with caveats | **verified to hold** (P11 checked; x-guidance-evaluation.md records reasoning + failures) | **Agree** |

## 4. Completed work the review may have written off

**Short answer: none was written off. The review's accepted-revision inventory is complete.
But one post-anchor event matters and the review missed it because it postdates the
review's anchor (and its git evidence).**

### 4.1 What the review credited (and I confirmed)

- 33 board done rows + 1 cancelled — **my board snapshot is byte-identical in
  `updatedAt` (15:18:41.870Z); the count of 33 done rows re-verifies exactly**
  (6 fix / 6 arch / 8 prep / 13 audit; `evidence/board-check.md`).
- 10 plan delivery-table commits + `2159c657` — **all verified present in current HEAD
  history** (`git merge-base --is-ancestor` for each; `evidence/git-state.md`).
- The P11 guidance exercise (accepted fixture + evaluation).
- The four `2159c657` re-review done rows, with the honest `[NOT ESTABLISHED]` caveat on
  whether their accepted bytes equal the commit's bytes.
- The W1 row as accepted-but-integration-unestablished.

I found **no board-accepted or documentation-accepted compiler revision outside this
inventory.** Nothing the review treated as incomplete is actually accepted; the "few
accepted compiler revisions" framing is an honest count, not a write-off.

### 4.2 The `0a5c42a7 "baseline"` commit (post-anchor; the review's anchor is stale)

`git rev-parse HEAD` = `0a5c42a702d938ca4da39cbcefae2cc450e021fe`, subject "baseline",
author "wire", **Wed Sep 30 11:23:41 2026 -04:00** — i.e. after the review's board snapshot
(15:18:41Z = 11:18:41 local), after the W1 confirmation (15:16:04Z), and after the review's
REPORT.md mtime (11:29:10 local). The review anchored on `e1c65975` (25 dirty entries) and
never re-ran `git log`; its `evidence/git-verification.txt` ("top commit e1c65975") is
stale by one commit. This is a gap in the review's evidence currency, not a reasoning
error: at the review's own verification moment (per its evidence) the anchor was correct.

What `0a5c42a7` integrates (67 files, +2778/−29; `evidence/git-state.md`):

1. **The frozen P08 candidate, byte-exact**: committed `SwiftExpr.hx` hash =
   `bf7dde2cec3b…` = FREEZE §6.2's candidate hash (recomputed, not quoted). Plus the
   `SwiftArrayBoundary.hx`/`SwiftDecl.hx` frozen worktree edits. **The candidate's bytes are
   for the first time in the coordination tree's history.**
2. **Four board-accepted fix rows, now row-to-commit-mapped** (the review left these
   `[NOT ESTABLISHED]`): `fix/dart-fallthrough-nullguard` (DartExpr.hx fall-through gate +
   `dc-null-guard-fallthrough` fixture), `fix/dart-nullguard-mutation-closure` (DartExpr.hx
   closure reset), `fix/rust-fault-variant-regression` (RustExpr.hx fault-variant growth),
   and `fix/swift-generated-tree-runtime` (SwiftDecl.hx `imports.runtime("BoringException")`
   with an in-code comment naming the board row "t-mun5d99p-op76").
3. **The P09 runbook** (`p09-fixed-matrix-preparation-runbook.md`, 309 lines, new) and
   fixtures/tools (`try-tail`, `swift-rt-plain/probe`, `precision-guard`, roots-guard
   hardening).

**Why this does not change the conclusion:** committing ≠ acceptance. Plan:93-94 says a
committed checkpoint "does not mean its consumers or regression gate passed"; the P08 gate
row is still `todo` 0/3; the REJECT verdict and the behaviour review's 12-error Gap cell
stand; the W1 defect is still in the committed candidate bytes (bf7dde2c is pre-W1); and no
P09 run exists. The baseline commit is repair-cycle integration (consistent with the
consultations' "freeze, then repair" ordering), not gate acceptance.

**State inconsistency worth flagging:** the *working tree* `SwiftExpr.hx` now hashes
`0a9bed91ef91…` = the **pre-candidate base** file, while HEAD carries the candidate
(`bf7dde2c…`). So the live working tree does not contain the candidate patch in
`SwiftExpr.hx` even though HEAD does; `git diff HEAD` on that file is the inverse of
INTEGRATION.diff. (Worktree `SwiftArrayBoundary.hx`/`SwiftDecl.hx` do match HEAD.) Whoever
created the baseline commit left the main worktree in a mixed state; any re-freeze or
re-review must anchor on an explicit revision, not the worktree.

### 4.3 The `e5e21854` claim, verified

The review states `e5e21854` is "an unfinished checkpoint, not accepted" and quotes the
delivery table (plan:101). **Verified**: the quote is verbatim (section 2, row 7);
`e5e21854` exists in history with subject "checkpoint unfinished Swift arrays and policy
migration plan"; the plan describes it as unfinished in two places (plan:101, plan:139) and
says its completion is no longer a prerequisite (plan:8-9). "Not accepted" is accurate: the
plan never records an acceptance of it, and it is a checkpoint of unfinished work. The
review is honest here; if anything it is *more* favourable to the pilot than the plan's
own wording requires.

### 4.4 Post-anchor in-flight work (none of it accepted)

Directories in `dc-warn/out` modified after the review's snapshot (all in-flight scratch,
none an accepted gate result): `w1-fix` (PATCH.diff + evidence), `switchexpr-destination`,
`lambda-return-contract` (open implementation-review conditions, evidence logs only),
`ci-collection-wire` (CI wiring in a scratch worktree; "the coordination tree was never
written to"), `record-cell-fix`, `p1-run-xcheck` (scoped baseline-recovery runs),
`p10-reflection` (P10 record is a **draft**; P10 gate unchecked), `p09-tiqian-feasibility`
(matrix not startable; manifest invariant now failing). None converts an open criterion to
met.

## 5. Honesty-claim check (the "first half" division)

The review states (section 5 closing): "Publishing this review satisfies the first half of
P12's gate text (publication of the programme review, accepted revisions, evidence gaps,
and next scheduled mechanisms). The gate remains unchecked: its closure is conditioned on
criteria that do not hold…"

**P12's actual wording** (plan:225-226, verified verbatim): "Publish the programme review,
accepted revisions, evidence gaps, and next scheduled mechanisms. Close the goal only when
its criteria hold." The gate is two sentences: (a) a publication obligation with four
named items, (b) a closure rule conditional on the criteria. The review's "first half /
remains unchecked" division **maps exactly onto this sentence structure**: "the first half"
= sentence (a), "the gate remains unchecked … conditioned on criteria" = sentence (b).
**The division is accurate against P12's wording.**

Two precision notes:
- The review's four items are all present in the document (§1 programme review, §2
  accepted revisions, §3 evidence gaps, §4 next scheduled mechanisms) — so "satisfies the
  first half" is content-true.
- The document is titled "P12 draft" and lives in `dc-warn/out/` (retained evidence), not
  in the repository's `docs/`. If "Publish" requires publication into the repository record
  (as the programme's other records live under `docs/investigations/`), the first half is
  *drafted* rather than fully *published*. The review does not claim repository publication;
  it claims the publication content is satisfied by this document and leaves the gate
  unchecked. That is a defensible, honest framing — not an overclaim, but the single
  weakest spot in its honesty claims. The review's second honesty sentence (that per
  plan:186-190 it carries the naming violations forward and claims no complete runtime
  naming conformance) is **verified accurate**: plan:189-190 is quoted verbatim (section 2,
  row 10) and the review's §3.4 does exactly that.

## 6. Falsification attempts

### 6.1 Optimistic attempt — try to establish that the criteria hold (goal should close)

**Attempt A (criterion 3 via the comparison-consumer migration).** The finite-comparison
mechanism went through analysis (shared comparison plan), a Swift consumer (`4581308d`,
accepted; "the A3 procedure completed 19 expected stages, including Swift compilation and
execution"), and then a four-target migration (`2159c657`, present in history, with four
done re-review rows and CODEX-AUDIT §1: "commit 2159c657 and the current callers show those
consumers integrated"). Could this be "one selected mechanism change" completed through its
consumers? **Fails**: plan:160-162 expressly says "These tasks do not complete P08's
mechanism migration or P09's regression requirements", and P07/P08 are the plan's
selection/acceptance gates for the selected mechanism (P08 unchecked; REJECT verdict). The
plan itself resolves this reading against closure.

**Attempt B (criterion 3 via "implementation complete").** The frozen candidate is
reproducible byte-for-byte, independently re-verified (freeze-xcheck CONFIRMED), and now
committed in HEAD. Under the loosest reading of "complete … through its consumers as
applicable", couldn't the execution agents' completed implementation satisfy it? **Fails**:
the behaviour review found the mechanism does not pass through its printing consumers —
"Gap fixture: generation rc=0, swiftc rc=1 with 12 errors / 2 warnings", the
`coalescedBoundary` refusal cell blocks the acceptance fixture (O-A aborts at generation),
and O-B is "collected nowhere in the repo". "As applicable" does not waive a consumer that
is applicable and failing.

**Attempt C (criterion 4 via the prepared fixed pair).** The recorded pair exists
(Boring `2159c657` + Tiqian `8504d230`), the runbook is cold-start executable, the driver
was rebuilt and provenance-closed (B2), and the p09-tiqian-feasibility report (11:47,
post-review) confirms the toolchain layers "verified working today". Could criterion 4 be
arguably close? **Fails on four independent grounds**: (i) no *accepted* candidate exists
(first clause of criterion 4); (ii) the matrix was never executed — `generationStarted:
false`, "not safely startable" (locked worktree, open B4); (iii) B3 (Swift
`libSystemPackage.so` never built) blocks two stages; (iv) the preparation's manifest
invariant now fails (13 of 30 pinned hashes mismatch) and the since-merged Rust fixes force
re-selection of the fixed revision per the runbook's B1 rule. **This was the closest
optimistic approach**: criterion 4 is *within reach* — the programme demonstrably has a
funded route to execution — but criterion 4 demands executed evidence from an accepted
candidate, and that does not exist.

**Optimistic result:** no criterion can be established as holding. The closest approach was
Attempt C (criterion 4 "close but not met"). The conclusion "the criteria do not hold"
survives.

### 6.2 Pessimistic attempt — try to show the review overstates failure / writes off accepted work

**Attempt A (W1 as completed mechanism work).** The W1 row is `done` 3/3 with two SOP
criteria independently reproduced by the coordinator. Does the review discount a completed,
accepted fix? **No**: the review lists W1 in its 33 done rows, quotes its confirm record
accurately, and its only open item (integration) is true — the W1 fix is committed nowhere
(verified: `git log --all -S statementArms` and a `git grep statementArms` over
`git rev-list --all` return nothing; the fix exists only in `dc-warn/out/w1-fix/PATCH.diff`
and the w1-wt worktree). But W1 is a **defect repair, not the selected mechanism
migration**; its confirm record itself excludes the build-phase diagnostic question
("另案裁定" / separate ruling — now a board row: `gate/build-phase-diagnostic-standard`,
`todo`). It cannot satisfy criterion 3.

**Attempt B (the review downplays the accepted-revision count).** The review says the
accepted compiler revisions "are few" and its plain count lists 6 fix rows + 10 table
commits + P11. Is anything accepted missing? **No** (section 4.1): I found no accepted
revision outside the inventory. The review *adds* to the plan's table count (it credits the
plan table as a 2026-09-28 snapshot that understates integration progress, per CODEX-AUDIT
§1, and names `2159c657` explicitly). On this axis the review is, if anything,
more favourable than the plan's own table.

**Attempt C (criterion 1 "first-cycle only" phrasing).** The criterion's text does not
distinguish first-cycle from expanded readings, and plan:10 keeps the first-cycle criteria
binding inside the expanded work. The review's "criterion 1 holds only in the first-cycle
reading" imports the consultations' expanded-scope demand as a qualifier on a criterion the
plan's text would simply mark satisfied. **Partially valid as a precision critique**: the
cleaner statement is "criterion 1 (as written) holds; the expanded programme's additional
completion requirements are unsettled". But the review does exactly that split
("First-cycle scope: yes … Expanded scope: NOT ESTABLISHED"), marks the second part with
its third state rather than a failure, and the overall conclusion rests on criteria 3 and 4,
not on criterion 1. The phrasing is rhetorically stronger than necessary; it does not make
the review pessimistic in any operative way.

**Attempt D (the stale anchor hides a closure-relevant acceptance).** Could `0a5c42a7` or
any post-anchor event constitute an acceptance the review missed (making its refusal
pessimistic)? **No**: `0a5c42a7` is integration/housekeeping of already-accepted work plus
the unaccepted candidate (section 4.2); plan:93-94 and the open P08 gate keep
committing-outside-acceptance from counting. The review's refusal would be unchanged if
re-run today.

**Pessimistic result:** the strongest pessimistic finding is a **precision critique, not a
reversal**: (i) the review's criterion-2 and criterion-5 evidence is a deferral to the plan's
self-description where direct verification was possible (I verified the documents directly
— both hold), (ii) the "criterion 1 holds only in the first-cycle reading" phrasing is
stronger than the plan's text requires, (iii) the review's anchor/gt-evidence is stale by
the `0a5c42a7` commit, and (iv) two citation blemishes (SOL2 §2 compression,
freeze-xcheck §5.5.1 misattribution). None of these writes off accepted work or changes any
criterion's outcome.

**Which attempt came closest?** The **optimistic Attempt C** (criterion 4 close-but-not-met
via the prepared fixed pair) came closest to moving the conclusion, because it shows the
programme is one funded execution away from criterion 4 and the refusal is a *timing*
refusal, not a *direction* one. The closest pessimistic attempt (Attempt C) only adjusts
phrasing.

## 7. Verdict

**The closure refusal is sound.**

- The five criteria were quoted **verbatim** (one dropped terminal period) and judged
  against the plan's own text and the repository's own records.
- My independent re-judgement **agrees with all five verdicts**: 1 holds (first-cycle;
  expanded additional requirements unsettled — correctly NOT ESTABLISHED), 2 holds
  (verified, not merely asserted), 3 fails (the plan's own "complete" requirement +
  plan:160-162 + REJECT verdict + P08 unchecked; robust to strict/loose reading), 4 fails
  (no accepted candidate; no P09 run; plan:108 is a 2026-09-28 status snapshot whose
  reliance is defensible but stale-anchored), 5 holds with the evaluation's own recorded
  caveats.
- **No genuinely accepted work was written off**; the review's accepted-revision inventory
  is complete, and the one post-anchor integration event (`0a5c42a7`) commits the
  unaccepted candidate and already-accepted fixes, which does not satisfy any open
  criterion (plan:93-94; P08 todo).
- The review's "first half" honesty claim is **accurate against P12's wording**; its only
  soft spot is that the document is a draft in retained evidence, not a repository-published
  record — and it leaves the gate unchecked, which is the right call.
- Errors found in the review are **evidence-currency and citation-precision errors, not
  judgement errors**: stale git anchor (`e1c65975` → `0a5c42a7`), deferral phrasing on
  criteria 2/5 where direct verification was possible, one compressed paraphrase in quote
  marks (SOL2 §2), one misattributed section reference (freeze-xcheck §5.5.1 — substance
  verified elsewhere), and a slightly over-strong "first-cycle only" phrasing on
  criterion 1.

**Residual open items (not the review's, for the record):** the working tree's
`SwiftExpr.hx` has reverted to the pre-candidate base while HEAD carries the candidate
(section 4.2 flag); the W1 fix remains uncommitted on all refs; the P09 fixed-pair
preparation is stale (manifest invariant failing; B1/B3/B4 open); and the build-phase
diagnostic standard ruling (`t-muo92xms-s28t`) is `todo`.

## 8. Files

- `REPORT.md` — this file.
- `evidence/verbatim-check.md` — per-quote verification with line numbers and method.
- `evidence/git-state.md` — current HEAD, the `0a5c42a7` baseline-commit analysis, hash
  recomputes, W1-fix absence proof, P09 execution-evidence search.
- `evidence/board-check.md` — board snapshot comparison (33 done / 1 cancelled), gate-row
  states, the P09-prep confirm-record scope ruling.
