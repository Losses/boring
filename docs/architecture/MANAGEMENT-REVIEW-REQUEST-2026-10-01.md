# Management review request, filed 2026-10-01 by seat R2.3-b

**Status: REQUEST ONLY. This file makes no ruling and changes nothing by itself.**
It exists to place one question before the management review that alone can resolve
it, per `MANAGEMENT-RULING-137.md:34-35`:

> Until condition 4 is satisfied and a later explicit ruling says otherwise: do not
> nominate, do not declare a pass, and do not change its status.

## 0. Why this file name

The repository retains five ruling files, numbered by review round:
`MANAGEMENT-RULING-005`, `-065`, `-137`, `-215`, `-245` (plus the round-0
`MANAGEMENT-RULING.md`). No request-type file exists anywhere under
`docs/architecture/`; there is therefore no inherited request format or numbering
to reuse. The next round number belongs to the review that answers this request,
not to the seat filing it, so numbering this file as a ruling would fabricate a
round. The name is dated and seat-attributed instead:
`MANAGEMENT-REVIEW-REQUEST-2026-10-01.md` — distinct from every existing file,
and neutral as to the round the reviewer will assign.

## 1. The request (one item per line)

1. Given that requirement 4's two reports are now committed in-repo (merge
   `84eff599`, path `docs/architecture/evidence/condition-4-entry-gate/evidence/`),
   and that a three-way independent check has confirmed all four entry-gate
   requirements for `eec707b9` (condition 4) and `2aadcb69` (conditions 1/2) with
   `gate:verify` PASS — **have contract 3 conditions 1, 2 and 4 now reached the
   state `MANAGEMENT-RULING-137` calls "satisfied"?**
2. If the answer to item 1 is yes: **is the standing prohibition at
   `MANAGEMENT-RULING-137.md:32-35` lifted** — i.e. may the P08 successor
   candidate now enter the declaration and re-freeze process (nominate, declare,
   change status) — or does the prohibition stand until some further condition is
   met?

No other relief is requested.

## 2. Verified facts (each with commit / file / command)

All ancestor checks below were re-run for this request in the worktree at
`dc-warn/worktrees/recov-r23rr`, base `arch/agent-guided-governance` = `84eff599`;
command `git merge-base --is-ancestor <sha> 84eff599; echo $?`, rc=0 for every one:

```
f8df0ef6 rc=0   7792198e rc=0   83542288 rc=0   84eff599 rc=0
eec707b9 rc=0   2aadcb69 rc=0
449444cf rc=0   cd70eb12 rc=0   e550fa52 rc=0
f6f7e3d3 rc=0   c8ae0054 rc=0
```

- **R1's three corrections are on the line**: `f8df0ef6` (condition-4 entry-gate
  status corrected per RULING-137), `7792198e` (P08 S1-existence statements
  corrected per RULING-245), `83542288` (criterion-2 boundary note per disaster
  report R1.3).
- **R2.1 intake merge `84eff599`** committed requirement 4's two reports in-repo
  (`recov/r21-evidence-intake` → `arch/agent-guided-governance`). In-repo
  sha256, re-measured for this request:

  ```
  7fe58a4bf1a4f763723c9f25a1370bd9dd557584e64190ee5cd62dbe91bc2d51
    docs/architecture/evidence/condition-4-entry-gate/evidence/package-shell-adjudication-REPORT.md
  19479238cae6ce73152112b00a91e9fb2954c5d64c64eb276c804bcf82d6ab68
    docs/architecture/evidence/condition-4-entry-gate/evidence/verify-eec707b9-REPORT.md
  ```

- **R2.2 three-way check** (`audit-reports/r22-three-way-check-2026-10-01.md`):
  for both `eec707b9` and `2aadcb69`, all four entry-gate requirements
  (GATE-LEDGER.md:189-194) are judged **CONFIRMED** — traceable commit hash,
  clean working-tree proof, independent export/checksums, and executor+reviewer
  claim-versus-commit reports — with

  ```
  bun run gate:verify -- eec707b9   # PASS, 1455/0, RC=0
  bun run gate:verify -- 2aadcb69   # PASS, 1455/0, RC=0
  ```

- **R3.3-a independent review** (`audit-reports/r33-review-a-2026-10-01.md`)
  confirms the successor candidate's three components are ancestors of the
  reviewed HEAD `f6f7e3d3`:
  `449444cf` rc=0, `cd70eb12` rc=0, `e550fa52` rc=0 (against `f6f7e3d3`), and
  re-measured against `84eff599` above with the same rc.

Verbatim, `MANAGEMENT-RULING-137.md:17-19`:

> **Contract 3 condition 4: STILL NOT SATISFIED.** The standing ruling holds: P08
> remains **PREPARABLE, NOT NOMINATE-ABLE**. Conditions 1-3 being merged does not
> change this, and beginning preparation must not be used to imply P08 is now
> nomination-eligible.

Verbatim, `MANAGEMENT-RULING-137.md:32-35`:

> **Begin preparing the P08 successor candidate material only**, explicitly
> labelled "preparable, not nominate-able", and close or verify condition 4. Until
> condition 4 is satisfied and a later explicit ruling says otherwise: do not
> nominate, do not declare a pass, and do not change its status.

## 3. What is still NOT done (stated as found; nothing here is claimed as done)

- **The successor candidate is not frozen.** `docs/architecture/REFREEZE.md` has
  exactly one entry, and it freezes the old candidate `c8ae0054` (2026-09-30) —
  the candidate RULING-245 sealed as NOT PASSED/REJECTED. No successor revision
  (`449444cf`/`cd70eb12`/`e550fa52` lineage at `f6f7e3d3`) appears in any freeze
  record.
- **Zero independent reviews of the successor content.** R3.3-a measured this as
  **0/2** against RULING-245 points 2/4 (re-freeze + two independent reviews):
  neither condition has any successor-targeted review or freeze record. R3.3-a
  itself is a review of the *components' technical claims*, not the double
  review the ruling requires of a candidate.
- **P08 overall remains NOT PASSED** (`GATE-LEDGER.md`, P08 section), and its
  status remains PREPARABLE, NOT NOMINATE-ABLE per RULING-137.
- **P09 overall: NOT PASSED** — criterion 1 still needs the gate owner's
  Boring-side revision decision (`GATE-LEDGER.md` P09 section, criterion 1 FAIL).
- **P10 overall: NOT PASSED** — publication is discharged in-repo (`ec4c5c2d`)
  but the gate owner's sign-off of the published record is outstanding.
- **P12 overall: NOT PASSED** — per P12's own closure rule the goal must not be
  closed; criteria 4 depends on P09's recorded pair.

## 4. Accounting convention for the freeze (carried from R3.3-a)

R3.3-a found that the disaster report's "object 278824 B, equal on both sides"
is a **2026-09-30 reading of the S1-time tree** (confirmed by byte re-read of the
retained evidence), **not a fact about today's tree**: recompiling at HEAD
`f6f7e3d3` yields `gap.o` = **434568 B** (reproduced across two independent
clean copies; object bytes are non-deterministic, size is reproducible).
**Convention proposed for whichever ruling follows: when the successor candidate
is frozen, object sizes and checksums are to be recorded from fresh measurement
at the frozen revision, not carried over from the 278824 B figure.** This
request does not itself re-measure beyond citing R3.3-a's recorded readings.

## 5. What this request does NOT do

- It does not change any ledger row (`GATE-LEDGER.md` untouched by this seat).
- It does not declare any pass, any gate satisfied, or any check cleared.
- It does not change P08's status, which remains PREPARABLE, NOT NOMINATE-ABLE
  until the later explicit ruling RULING-137 itself requires ("a later explicit
  ruling says otherwise").
- It does not touch `REFREEZE.md`, `P08-SUCCESSOR-CANDIDATE-MATERIAL.md`,
  `P08-SUCCESSOR-DECLARATION.md`, or any board row.
- It only places the question of section 1 before the party empowered to rule on
  it.
