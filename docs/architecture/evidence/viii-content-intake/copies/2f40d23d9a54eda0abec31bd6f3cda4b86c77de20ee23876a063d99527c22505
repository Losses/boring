# Acceptance and reflection record — first round

This is the artefact `architecture-work-plan.md:220` (P10) requires: *"Classify
review failures, revise the appropriate documents, and publish the first round's
acceptance and reflection record."* It is drafted from the retained reports by
read-only synthesis; nothing was re-run and nothing was modified to produce it.

**Published here** because a management review found that a record living only in
a scratch directory is not a publication, and the P10 verb is *publish*.

---

# P10 ACCEPTANCE AND REFLECTION RECORD — first round (draft for gate sign-off)

**Programme:** Boring architecture governance (`docs/architecture-work-plan.md`, milestone
"Boring 架构治理（首批跨目标契约与固定版本回归）", board milestone `m-mulwvr32-3jht`).
**Gate clause this record discharges (quoted verbatim from
`docs/architecture-work-plan.md:220-221`, unchecked at time of writing):**

> - [ ] P10: Classify review failures, revise the appropriate documents, and
>   publish the first round's acceptance and reflection record.

**Status of this document:** DRAFT. It is the *record*, not a verdict change: the candidate
is **not accepted**, and nothing below says otherwise. Compiled 2026-09-30 by a delegated
record-writer from retained evidence only; no repository file, report, or record was
modified. Provenance labels: **[VERIFIED]** = I checked it myself in this session;
**[DOC]** = a named retained document states it; **[NOT ESTABLISHED]** = could not be
determined, blocker named.

---

## 1. Acceptance verdict — NOT ACCEPTED

**The P08 candidate (the Swift ordinary read-only array boundary candidate, frozen as
`FREEZE-BUNDLE = b664c91cd09ba6b80517e809feca90a7995f68b84b81589126fed525da1a3878`
[DOC, `p08-candidate-freeze/FREEZE.md` §6.1, independently recomputed there by
`freeze-xcheck/REPORT.md`]) is NOT ACCEPTED.**

Independent sources, each rejecting in its own terms:

1. **Implementation review — verdict REJECT, four named conditions**
   (`p08-implementation-review/REPORT.md` §6 [DOC; I read the full report]). Its conditions,
   quoted and condensed:

   - **Condition 1 — Obligation 2 (legal generated output, zero diagnostics).** "On the
     candidate's own gap-fixture input, `swiftc -typecheck` prints **2 diagnostics**, and the
     same two sites are a wrong control exit (`switchExplicitReturn(.two)` → `2`, oracle
     `1`). Fix or obtain a written gate ruling" — either stop `switchStatement` from
     stripping `return` out of arms emitted as returns, "or have the gate owner record an
     explicit warning allowlist for the two `[#no-usage]` diagnostics, in writing … A
     reviewer cannot waive an obligation; only the owner can."
   - **Condition 2 — Obligation 1 (actual destinations; lambda defect).** "`currentReturnType`
     is the **member's** return type, written once at `:544` and not rebound by
     `functionLiteral` … the sites the candidate repaired with it — `tryReturnLines`
     `:5296/:5310`, the return-position switch `:810`, the `armLines` fallback `:5675` —
     still borrow the enclosing function's unrelated return type whenever the return contract
     belongs to a lambda." Required: carry the actual return contract; acceptance evidence
     "probeE-shaped input typechecks with 0 diagnostics, plus the existing fixtures."
   - **Condition 3 — Obligation 1 (in-scope reconstruction removed).** "`switchExpression`
     `:5559` / `switchBindingLines` `:5514-5517` still derive both the closure result type
     and the arm destination from the switch's own AST type, and the emitted local carries no
     annotation." Required: explicit destination parameter from the owning contract. The
     reviewer explicitly notes no divergence was observed in 11 instrumented generations and
     that the condition "rests on obligation 1's wording, not on a demonstrated failure."
   - **Condition 4 — delivery/collection, not the patch.** "the repo's own collector
     (`tests/swift-readonly-boundary/readonly-boundary.test.ts:55`) is red on a **stale
     expectation** in both trees … the gap fixture has no collector at all … The stale
     expectation needs an owner ruling … and the two focused observations need to enter a
     routine command before the delivery can claim 'durable collection'."

2. **Behaviour review — does not accept** (`p08-behaviour-review/REPORT.md`, re-anchored
   revision `review-reanchor-apply/REVIEW.reanchored.md` [DOC; the re-anchored revision's §0
   states its citations were re-checked against the frozen 390-line record]). It does not
   issue an accept verdict; it establishes that the defect class is **not closed**: the two
   discriminating observations O-A (acceptance-fixture generation) and O-B (gap-fixture
   swiftc zero-diagnostics) "only close when … green on the same candidate revision," O-A was
   measured **rc=1** on the pre-candidate tree and O-B **rc=1, 12 errors / 2 warnings** at
   review time, and O11 (the optional-source → required-destination cell) "blocks the
   acceptance fixture itself." It also documents that CI collects neither observation.

3. **Both architecture consultations direct rejection of acceptance of the checkpoint**
   [DOC]: `SOL2-ARCH-ANSWER.md` — "reject the current candidate for acceptance"; `ASTRA-ANSWER.md`
   — "reject acceptance of the current checkpoint." Both prescribe the order
   (d) baseline budget decision → (a) SW04 → (c) switch/try destination repair → (b) freeze +
   two independent reviews, both of which "must accept."

4. **The candidate freeze itself** [DOC, `FREEZE.md` status line]: "the *implementation* is
   now pinnable and reproducible byte-for-byte; the *acceptance* is **not complete**." Its
   obligation audit finds all three obligations **PARTIAL, not sufficient**. The freeze
   cross-check (`freeze-xcheck/REPORT.md`) verdict is **CONFIRMED** (identity and
   reproduction), with findings F1 (one irreproducible hash on a disclaimed document), F2
   (line-citation slip), F3 (lazy-effect conflation) — none of which accepts the candidate.

5. **The board corroborates** [VERIFIED]: board row `gate/p08-swift-readonly-boundary`
   (`t-munq08t2-rgxp`, "P08：接受一个冻结的 Swift 只读数组边界实现候选…") is **still
   `todo`** with 0/3 criteria evidenced, and P08/P09/P10/P12 are unchecked in the work plan
   [VERIFIED against the live file].

### Post-review delivery work — what it changes, and what it does not

A defect on the critical path was fixed after the reviews: **W1**, the swallowed arm `return`
in `switchExplicitReturn` (`w1-fix/REPORT.md` [DOC]; board row `fix/swift-switch-explicit-return`
`t-munu29i9-70b7` status **done** [VERIFIED]). Post-fix, the gap fixture reaches
`swiftc -typecheck` **rc=0 with 0 errors and 0 warnings**, and execution shows `.two`
returning the correct value `[3]` [DOC, `w1-fix/REPORT.md` §3, with retained logs].

**This discharges implementation-review Condition 1 via its first remedy** (stop the splice —
the fix removes `switchStatement`'s text splice rather than obtaining an allowlist), **but it
does not by itself accept the candidate**, because:

- it is a *new candidate state* (a second `SwiftExpr.hx` delta on top of the frozen one);
  under the consultations' own rule, "every subsequent relevant change invalidates the
  affected acceptance" [DOC, `SOL2-ARCH-ANSWER.md` §1.2 order item 4]. The reviews' conditions
  2–4 were adjudicated against the frozen candidate, not this one;
- Conditions 2 and 3 (lambda return contract; `switchExpression` destination) have **no
  recorded repair or re-measurement** — nothing in the retained reports shows a probeE-shaped
  input typechecking clean on any tree [NOT ESTABLISHED — blocker: no such report exists in
  `dc-warn/out/`];
- Condition 4 (stale `branch-*` expectation; no CI collection) has no recorded owner ruling
  or collector change [NOT ESTABLISHED — same blocker];
- a **new open standard question** emerged from the W1 work: a build-phase
  `will never be executed` warning on the fixed fixture, which `-typecheck` does not surface
  [DOC, `w1-fix/REPORT.md` §4]; it is now a board row awaiting adjudication
  (`gate/build-phase-diagnostic-standard`, `t-muo92xms-s28t`, still `todo` [VERIFIED]).

---

## 2. Failure classification (P10's first verb)

Grouping the round's findings by kind, and by **who owns the fault** — the distinction a
prior audit of this programme found systematically missing [DOC: the tasking for this record
attributes that finding to a prior programme audit; the audit report itself was not supplied
to me, so I cannot cite or verify it — **NOT ESTABLISHED**].

### 2.1 Unmet obligation — the candidate's fault (or its delivery's)

| Finding | Source | Owner |
|---|---|---|
| Gap-fixture 2 diagnostics + wrong `.two` control exit (W1) | impl-review Cond. 1; FREEZE §5.2; behaviour review Q5 | candidate's defect surface; **pre-existing** in base (byte-identical function, base emits same warnings [DOC, FREEZE §5.2]) — but the *obligation* is the candidate's to discharge |
| Lambda return-contract defect (`currentReturnType` not rebound) — measured, survives the patch | impl-review §4.1, Cond. 2 | candidate (its claim was false); defect pre-existing in base |
| `switchExpression`/`switchBindingLines` AST-type derivation retained | impl-review Cond. 3 | candidate (obligation-1 wording, no demonstrated failure) |
| In-scope reconstruction not removed: 9 derivation sites, candidate removes none, string surgery still load-bearing | impl-review §3; FREEZE §5.1; behaviour review Q4 | candidate + pre-existing architecture |
| Branches indistinguishable by the fixture; "distinguish both branches" untestable as written | FREEZE §5.3; branch-expectation-ruling (quoted there) | **missing documentation/fixture authorship** — expectation wrong "at birth" (template copy-paste, squash commit `e5e21854` [DOC, FREEZE §5.3]) |
| No durable collection: CI runs only `test:*` scripts; gap fixture collected by nothing | behaviour review Q5; impl-review Cond. 4 | **pre-existing repo state** (CI wiring), surfaced by the round |
| Stale tracked expectation `branch-true=1:1`/`branch-false=2:1` reds the collector | impl-review §4.6; FREEZE §7.16 | **pre-existing repo state**, not the patch |

### 2.2 Stale or drifting assets — documentation fault, not candidate fault

| Finding | Source |
|---|---|
| Governing `RECORD.md` drifted through ≥6 revisions (131→186→279→362→367→390 lines) and moved *after* the behaviour review was written, so the two reviews initially could not cite the same governing record | FREEZE §4.1–4.2 [DOC]; drift chain quoted from consult/review reports; **the 390-line endpoint VERIFIED by me: sha256 `9886fe25c9c5ea392958b3ec2167c7903934d0f1593b25a7ae90633bba45b24e`, 390 lines** |
| Record's §6 open set contradicted its own §4 ("SILENTLY ABSENT" claims false) — fixed by CORRECTION 12 after the behaviour review caught it | RECORD CORRECTION 12 (`:285-302`) [VERIFIED by reading the record]; re-anchored review §3.3 items 5–6 |
| Record §3 heading "Each fact has exactly ONE producer" false as written | behaviour review §2.1 |
| Record declared the `MutableArrayWrapper × optional → required` cell REFUSED end-to-end while the candidate's SW04 override makes it succeed on a live route — later adjudicated SPEC-PREScribed (planner-cell verdict mis-scoped) | override-ruling [DOC]; override-ruling-xcheck CONFIRMED with a line correction (:58, not :56) |
| Archive's `swiftc-version.log` is a failed invocation, not a version | FREEZE §3.4 |
| Freeze record's hash for `swc-try-fix-wt/REPORT.md` irreproducible (F1); line slip on the OtherArrayStorage row (F2); lazy-effect conflation (F3) | freeze-xcheck §7 |

### 2.3 Specification gap — genuine open ruling, not defect

| Finding | Source |
|---|---|
| The override as a *rule* is SPEC-PERMITTED-BUT-UNRECORDED: extensionally correct today, but the "required final result" precondition is nowhere recorded | override-ruling sub-finding [DOC] |
| No end-to-end policy for build-phase (`swiftc -o`) diagnostics; `-typecheck` and `-o` disagree on the fixed fixture | w1-fix §4 [DOC]; board row `t-muo92xms-s28t` todo |
| W1 fix's new standard question (suppression of faithfully-rendered dead trailing returns) is a *different defect class* deliberately not folded into W1 | w1-fix §4 |

### 2.4 Process defect — how the round worked on itself

| Finding | Source |
|---|---|
| Coordinator amended the record citing the **wrong row** (`:56` instead of `:58`) by grepping a keyword; an independent cross-check caught it and the amendment was **reverted** | FREEZE §4.3 "Citation note (REVERTED)" [DOC] |
| Record sections edited in separate rounds with **no cross-section consistency check**, producing two independent contradictions | RECORD CORRECTION 12 root-cause note [VERIFIED] |
| Freeze taken while the implementation review was still writing (no REPORT existed at 03:55); reviews and record moved concurrently | FREEZE §5.0; freeze-xcheck timeline note |
| A candidate report claim ("29 lines" runtime match) contradicted by measurement (30) | FREEZE §7.15 |
| Summary assessments contradicted by retained evidence ("oracle gap, small" — rejected by SOL2; archive README's CI claim contradicted by `ci.yml`) | SOL2 §1; behaviour review Q5 |

### 2.5 Attribution summary

- **Candidate's fault:** obligation-1 handoff defects (lambda destination; retained AST-type
  derivation; un-removed reconstruction) and the unruled-in-advance override. Note the
  round's own honest split: the W1 control-exit defect is *pre-existing* in the base, but the
  *obligation to discharge it* belongs to the candidate.
- **Pre-existing repo state:** stale tracked expectation reding the collector; CI collecting
  neither focused observation; the base's 12 gap errors; wrong-at-birth branch expectation.
- **Missing documentation:** the mis-scoped planner-cell rows; the unrecorded override
  precondition; the build-phase diagnostic policy; the withdrawn-scope history (CORRECTION 9)
  that had let "incomplete discovery reduce the obligations."

---

## 3. What was revised in response (P10's second verb)

Document revisions actually made, in order [each marked VERIFIED = I read the artifact or its
application report]:

1. **`RECORD.md` correction series (governing boundary-policy record).** Revisions
   CORRECTION 1–12 accumulated across the record's drift chain; CORRECTION 9 withdrew the
   blanket exclusion clause (found by the Codex consult); CORRECTION 10 applied independent
   reviewer corrections N1–N4 (`record-corrections/REPORT.md` [VERIFIED — its REPORT states
   the corrected document was written back to `boundary-policy-record/RECORD.md` and
   byte-compared]); CORRECTION 11 (N7); CORRECTION 12 withdrew the false "SILENTLY ABSENT"
   open-set claims **after the behaviour review caught them**, and records the root cause
   (no cross-section consistency check) [VERIFIED in the frozen record at `:285-302`].
   Endpoint frozen at 390 lines / `9886fe25…` [VERIFIED].
2. **The reverted correction — stated honestly.** During the override adjudication the
   coordinator amended the record to relocate the REFUSED row to `:56`, "and it is the
   **`OtherArrayStorage`** row … **That was wrong and has been reverted.**" The error arose
   by grepping a keyword belonging to row `:56`; the keyword "hit the *wrong row*"; a second
   independent check (`override-ruling-xcheck`) verified the original `:58` citation as exact
   and caught the error [DOC — FREEZE §4.3, which preserves the revert note verbatim]. So:
   at least one correction in this round was applied and then reverted, and it was the
   cross-check, not the author, that caught it.
3. **The record-cell-scope fix — prepared but NOT applied to the frozen record.**
   `record-cell-fix/REPORT.md` [VERIFIED] applied the override ruling's §4 record text to a
   **copy** (`RECORD.corrected.md`, 438 lines, sha `cf746291…`), leaving the frozen file
   untouched (still `9886fe25…` [VERIFIED]). All 21 code citations in the new text verified
   exact; a formatting slip (double spaces) was introduced and caught by self-check and
   fixed. **Status: the corrected record is a pending artifact, not the governing one**;
   adoption is an open item (§4).
4. **Re-anchoring of the behaviour review** (`review-reanchor-apply/REVIEW.reanchored.md`
   [VERIFIED]): after the record moved 367→390 lines at 03:06, the review's §0 and affected
   §3.3/§8/§9 items were revised to pin the new revision, with the drift chain and the
   byte-identity of unaffected sections stated. This is the revision that makes the two
   reviews citable against one governing record.
5. **The candidate freeze** (`FREEZE.md` [VERIFIED by reading; hashes independently
   recomputed by freeze-xcheck, 28/29 MATCH]): identity record + obligation audit; establishes
   the freeze bundle hash, the byte-for-byte reproduction recipe, and the honest
   "acceptance not complete" status line.
6. **Integration manifest corrections.** `integration-manifest/REPORT.md` [DOC]: the
   manifest's "+54/−15" diff-stat error corrected to **+55/−15** (freeze-xcheck row 7
   confirms the correction).
7. **Three-step partition with a carried correction** (`three-step-partition/REPORT.md`
   [DOC]): established that `litop-migration/PATCH.diff` is expressed against commit
   `4581308d`, not the coordination tree, and **must not be applied there**; regenerated
   step (x) mechanically; corrected a previous `STEP-GROUPED.diff` **off-by-one annotation**
   (STEP A/C labels swapped onto adjacent hunks; hunks themselves were already correct).
8. **Delivery revisions to the candidate (document revisions adjacent):** the W1 fix
   (`w1-fix/PATCH.diff`, board row `t-munu29i9-70b7` done [VERIFIED]) revised the *code*, and
   its REPORT records the adjudication boundary (do not fold the build-phase warning into W1)
   plus a full 21-driver generated-tree sweep showing exactly 2 changed lines.

**Not established about revisions:** who performed the 03:06 record edit (CORRECTION 12) and
the exact times of the 131→279-line revisions [NOT ESTABLISHED — the drift chain is quoted
from consult/review reports; no report names the 03:06 editor].

---

## 4. What is still open

### Tier 1 — blocking acceptance of a P08 candidate

1. **Implementation-review Condition 2** — actual return contract for lambda bodies
   (`:810`, `:5296`, `:5310`, `:5675`); acceptance evidence: probeE-shaped input typechecks
   0-diagnostic. No repair or re-measurement retained. [NOT ESTABLISHED as addressed]
2. **Condition 3** — explicit destination for `switchExpression`/`switchBindingLines` from
   the owning contract. No repair retained. [NOT ESTABLISHED]
3. **Condition 4** — owner ruling on the stale `branch-*` expectation; both focused
   observations entering a routine command/CI. No ruling or collector change retained.
   [NOT ESTABLISHED]
4. **Re-review of the post-W1 candidate.** W1 changed `SwiftExpr.hx` again; under the
   consultations' freeze rule the affected acceptance evidence must be renewed. No post-W1
   freeze or review exists.
5. **Adoption or explicit rejection of `record-cell-fix/RECORD.corrected.md`** — the
   governing record (frozen `9886fe25…`) still contains the mis-scoped REFUSED rows and no
   override-input row.
6. **A written ruling on the override precondition** (SPEC-PERMITTED-BUT-UNRECORDED), and on
   the build-phase `will never be executed` diagnostic standard (board `t-muo92xms-s28t`).

### Tier 2 — blocking only the next gate (P09)

7. Full fixed-input Boring checks and Tiqian checks with preserved logs, generated-output
   identity and warning results (P09's own clause; plan line 218-219 [VERIFIED]). The frozen
   Tiqian input is `8504d230…`; the plan records the earlier validation checkout's loss with
   "no established cause" and that copied inputs "do not establish a fresh regression result"
   [DOC, plan :176-186].
8. Baseline restoration decisions per the consultations: combined residual baseline,
   bounded account of the 166 divergences (160 missing IDs / 6 extra [DOC, ASTRA §3]),
   executable Tiqian route. Funding decision recorded as required-first by SOL2/ASTRA; whether
   the owner has made it is **NOT ESTABLISHED** from the supplied material.
9. CI/collection work from Tier-1 item 3 must land before P09 can cite "durable collection."

### Tier 3 — non-blocking

10. Freeze-xcheck findings F1–F3 (irreproducible hash on a disclaimed file; line slip;
    lazy-effect conflation) — record-quality items.
11. The archive's retained generated `Gap.swift` is the pre-patch counterexample; no retained
    artifact of candidate-generated output exists (FREEZE §3.1, §7.14) — a provenance
    inconvenience, not a gate blocker.
12. Untraced paths O8/O9/O12 and the unverified items both reviews list (double-wrap
    reachability, classifier corner cases, `LiteralProvenPresent` under a widened policy).
13. `swc-try-fix-wt/PROGRESS.md`'s "29 lines" stale statement (measurement says 30).

---

## 5. Reflection — what this round got wrong, in mechanism

Recorded lesson references found in the retained material: **PIT-301** (two fixtures cited
as discriminating had byte-identical generated trees pre/post — cited in both behaviour
reviews) and **TCN-124** (hxml root duplication chore, board row `t-munhr03l-o0hb`);
the board also carries **PIT-297, PIT-304, PIT-251, PIT-296, PIT-281, PIT-248, PIT-285,
PIT-255** as open/done repair rows [VERIFIED on the board]. `wb_note_list` was unavailable to
me, so the Wiki bodies of these were not read; only these in-report/board references are
cited. **NOT ESTABLISHED:** whether any additional PIT/TCN notes treat this round directly.

1. **Unpinned moving anchors defeated citation itself.** The governing record moved at least
   six times, once *after* a review had pinned it, so review 1's citations pointed at text
   that no longer existed, and for a window the two reviews could not "review the same
   candidate-plus-record" the freeze clause requires. Fix adopted late (freeze the record,
   re-anchor the review); the mechanism lesson is that **hash-pinning must precede review,
   not accompany sign-off** — the same lesson as the record's own anchor warnings.
2. **Keyword search stood in for reading.** The wrong-row amendment (`:56` vs `:58`) happened
   because a grep hit was treated as identification. The catch came from an *independent*
   cross-check re-reading against the candidate tree, and the fix was a **revert**, not a
   forward-edit. Mechanism: single-checker edits to a governing document are not safe;
   every governing-text change needs an independent citation check before adoption — the
   record-cell-fix run later did exactly this (21/21 citation checks) and the pattern works.
3. **Corrections without cross-section consistency checks compound.** CORRECTION 12 exists
   because earlier corrections (4) and open-set claims were edited in separate rounds and
   never reconciled, producing two self-contradictions that survived several revisions until
   an outside review caught them. Mechanism: a correction log is not a consistency mechanism;
   each revision needs a whole-document contradiction scan before it ships.
4. **Obligation wording was treated as waivable by context.** "Zero diagnostics" was argued
   against with "the two warnings are pre-existing / out of scope," without the only actor
   who can waive it — the gate owner. The implementation review's refusal ("a reviewer cannot
   waive an obligation; only the owner can") is the round's clearest correction. Mechanism:
   attribution of a defect to the base discharges *regression* questions, never *acceptance*
   obligations; the two were being conflated.
5. **One-axis closure recurs.** The behaviour review's O-A/O-B pair exists precisely because
   the programme "has already committed twice" to closing one axis (decision vs consumption)
   and declaring the class closed. Even the round's success — the W1 fix achieving 0
   diagnostics — is single-axis evidence: the lambda destination defect and the collection gap
   are untouched by it. Mechanism: an acceptance claim must enumerate which *named* conditions
   it discharges and name the ones it does not.
6. **Verification language slipped into secondhand claims.** The freeze's own §8 discipline
   ([MINE]/[QUOTED], never blended) exists because earlier artifacts blended them — e.g. the
   archive README asserting CI runs `bun test tests/`, contradicted by `ci.yml`; "oracle gap,
   small" contradicted by the retained reports; 29 vs 30 lines. Mechanism: every number in an
   acceptance-adjacent document carries a provenance label or it is not quotable.
7. **Concurrent production of the object and its audit.** The freeze was taken at 03:55 while
   the implementation review was still writing (no REPORT until later), and the record moved
   mid-session. The audits then had to spend effort establishing timeline facts (freeze-xcheck's
   timeline note, F1's irreproducible stat). Mechanism: freeze events and review events need a
   declared order; a freeze taken against an in-flight review is a snapshot of a conversation,
   not of a candidate.
8. **What the round got right, so the mechanism is preserved:** the two independent reviews
   with non-overlapping mandates worked — review 2 caught a lambda defect review 1's frame
   could not see, and both explicitly refused to let the other's green stand for acceptance.
   The freeze + cross-check + independent-ruling chain caught every documented error in this
   record (including its own F1–F3). The failure was never absence of checking; it was that
   checking was repeatedly applied *after* anchors, wording, and scope had already been
   allowed to move.

---

## 6. What this record could not establish

- Who edited `RECORD.md` at 03:06 and at each earlier drift point (no report names them).
- Whether the baseline-budget decision (consultation step (d)) has been made by the owner.
- Whether any repair exists for implementation-review Conditions 2–4 beyond the frozen
  candidate (searched the retained `dc-warn/out/` reports supplied; none found).
- The prior programme audit's own text (cited in my tasking as finding "a systematic failure
  to make exactly this distinction"); I could not locate or verify it from the supplied
  material and rely on the tasking's characterization.
- The Wiki note bodies behind PIT-301/TCN-124 (tool unavailable; in-report references only).
- Where the corrected record (`RECORD.corrected.md`) stands in adoption terms — prepared
  2026-09-30, no adoption or rejection recorded in the supplied material.

*Nothing in the repository, the record, or any report was modified by this record's
preparation. Anchor verification is in `evidence/anchors.txt`.*
