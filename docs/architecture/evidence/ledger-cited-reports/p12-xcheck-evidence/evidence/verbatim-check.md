# XCHECK verbatim citation check (method: python line-join + exact compare)

Plan file: boring-wt-architecture/docs/architecture-work-plan.md (453 lines, read in full)
Review file: dc-warn/out/p12-programme-review/PROGRAMME-REVIEW.md (570 lines)

## The five completion criteria — review section 5, lines 539-549 of the review

Plan lines (1-based): criterion 1 = 20-21, 2 = 22-23, 3 = 24-25, 4 = 26-27, 5 = 28-30.
Intro line 18: "The initial programme is complete when all of these conditions hold:"
(Review attributes the block to "[DOC: plan:18-31]" — correct: lines 18-31 bracket the
intro + all five criteria; the block quote starts at line 20.)

Result (multi-line plan text joined on whitespace before comparing):
- criterion 1: VERBATIM
- criterion 2: VERBATIM
- criterion 3: VERBATIM
- criterion 4: VERBATIM
- criterion 5: VERBATIM except the review drops the sentence-final period
  (plan: "…Passing tests alone do not establish this condition." / review: "…this condition")

## P12 gate — review lines 22-23, attributed to plan:225-226

Plan 225-226:
  - [ ] P12: Publish the programme review, accepted revisions, evidence gaps,
    and next scheduled mechanisms. Close the goal only when its criteria hold.
Review quote: MATCH (character-for-character after removing "> " markers).
Unchecked: VERIFIED ("[ ]" present in the live plan file, line 225).

## e5e21854 quotation — review section 2.2, line ~275

Review: [DOC: plan delivery table] "The Swift array pilot remains an unfinished checkpoint
at e5e21854"; it is retained as an unfinished checkpoint, not accepted.
Plan line 101 (delivery table, package A row): "The Swift array pilot remains an unfinished
checkpoint at `e5e21854`; shared source-container facts are integrated at `f104e3bf`."
Verdict: VERBATIM modulo markdown backticks and the trailing clause; source attribution to
the delivery table is CORRECT. Reinforced by plan:138-139 ("The unfinished Swift checkpoint
is `e5e21854`.") and plan:8-10 ("The Swift pilot is being preserved as an unfinished
checkpoint with explicit TODOs. Its completion is no longer a prerequisite for those
migrations."). e5e21854's own subject line: "chore(architecture): checkpoint unfinished
Swift arrays and policy migration plan". The review's characterization is accurate.

## Other plan quotes used by the review

- plan:108 (review section 5, criterion 4): "The fixed Tiqian revision is prepared, but the
  Tiqian candidate gate has not run." VERBATIM. Context: section "Reading the task labels and
  current delivery" which opens at line 93: "This snapshot records the state on 2026-09-28.
  A committed checkpoint makes code reviewable; it does not mean its consumers or
  regression gate passed." => line 108 is a STATUS SNAPSHOT statement (2026-09-28 state),
  not a standing requirement. The standing requirements are criterion 4 itself, the P09
  gate (plan:220-221), and plan:134.
- plan:134: "P08–P10 and P12 remain open pending accepted fixed-input regression evidence."
  VERBATIM (review attributes to plan:134; line number exact).
- plan:186-190 (review section 5 closing): VERBATIM — "P09 verifies this bounded candidate;
  P12 must retain those naming violations in its remaining work and must not claim complete
  runtime naming conformance."
- plan:32-34 (review section 4): VERBATIM — "The initial scope ends with that evaluated
  cycle. Further mechanisms remain separate scheduled work. Completion does not establish
  universal compiler correctness or the absence of regressions outside the tested domain."
- plan:99-106 delivery table ten commits: all ten present in current HEAD history
  (merge-base --is-ancestor), plus 2159c657 and e5e21854.

## Consultation / retained-report quotes relied on by the review

- SOL2 section 1: "The mechanism is well chosen. The present candidate is incomplete."
  VERBATIM (SOL2-ARCH-ANSWER.md line 9).
- ASTRA section 1: "'accept a frozen candidate' is premature as the next implementation
  unit." VERBATIM (ASTRA-ANCHER.md line 5, quoted inside "The mechanism is well chosen; …").
- ASTRA section 2: "The correct acceptance order is (d) → (a) → (c) → (b)." VERBATIM
  (ASTRA-ANSWER.md line 15).
- SOL2 section 2: review renders [DOC: SOL2 section 2] "Choose d → a → b → c: baseline
  budget and restoration, refused-cell disposition, consumption repair, then freeze and both
  reviews." PARTIAL: "Choose d → a → b → c." is verbatim (line 30), but the colon clause is a
  compression of SOL2's four numbered items (1. Baseline budget decision — commit capacity to
  baseline restoration; 2. Disposition of the refused cell; 3. Complete the consumption
  repair; 4. Freeze the complete candidate and obtain both independent reviews). A
  paraphrase inside quote marks; substance faithful.
- CODEX-AUDIT section 1: "commit 2159c657 and the current callers show those consumers
  integrated" VERBATIM (CODEX-AUDIT.md line 26); "P11 is a completed guided exercise …
  Reliable unaided agent execution, exhaustive lifetime correctness, and complete J
  migration were not established" VERBATIM (line 28); overall judgement "no demonstrated,
  accepted completion of the programme's integration cycle" VERBATIM (line 5); P08 row "An
  independently accepted reproduction/behaviour specification and complete implementation
  candidate have not been established for the selected mechanism" VERBATIM (line 56).
- p08-implementation-review section 6: "Verdict — REJECT the candidate for P08 acceptance"
  VERBATIM (line 311); "REJECT, with these exact conditions" (line 319).
- FREEZE status line: "the *implementation* is now pinnable and reproducible byte-for-byte;
  the *acceptance* is **not complete**" VERBATIM (FREEZE.md lines 11-12); "It does **not**
  accept the candidate" (line 30); "the two reviews cannot cite the same object today"
  (line 34).
- FREEZE section 6.2 candidate hash bf7dde2c… VERBATIM and independently confirmed by
  recompute: git show 0a5c42a7:…/SwiftExpr.hx | sha256sum = bf7dde2c… (see git-state.md).
- p08-behaviour-review claim ledger: "Gap fixture: generation rc=0, swiftc rc=1 with
  12 errors / 2 warnings" [EXEC] — the Gap cell fails compilation on the candidate.
- freeze-xcheck: the review's quote "[DOC: freeze-xcheck section 5.5.1] … 'switchExplicitReturn
  remains a defect carrier in the candidate…'" is NOT LOCATED: freeze-xcheck/REPORT.md has no
  section 5.5.1 (sections are 1-8; section 5 is "Falsification attempts"), and the phrase
  "defect carrier" appears in none of freeze-xcheck, FREEZE.md, p08-behaviour-review, or
  p08-implementation-review. The SUBSTANCE is supported: freeze-xcheck section 3 (Obligation
  2) quotes FREEZE section 5.2 — "2 warnings (Gap.swift:113, 115 — the known W1
  switchExplicitReturn swallowed-return; unchanged by the patch)" — and its table row
  "switchExplicitReturn before/after | byte-identical (diff rc=0)". So: misattributed
  citation, verified substance.
- W1 confirm record (board t-munu29i9-70b7, timeline seq 6, coordinator, 15:16:04Z): review
  quote "2 of the 3 SOP criteria were independently reproduced by the coordinator" matches
  the record's "其中两条由协调者独立复现（非采信报告）". VERBATIM in substance.
- compiler-policy-architecture.md:151 (SOL2's pointer): line 151 is BLANK in the current
  file; the "Programme completion" section (lines 152-160) does NOT contain SOL2's sentence
  "the owner must explicitly settle its finite completion scope before P12 can close". The
  review correctly labels that sentence as [DOC: SOL2 section 6, citing
  compiler-policy-architecture.md:151] — i.e. the consultation's interpretation, not a
  plan/policy verbatim requirement. The review does not misattribute it to the plan.

## Review's five-criteria verdicts (as written, review lines 551-556)

1. First-cycle scope: yes (as the plan records it). Expanded scope: NOT ESTABLISHED.
2. Yes (as the plan records it).
3. No.
4. No.
5. Yes, with recorded caveats (as the plan records it).
