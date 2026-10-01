# P10 ledger reconciliation — change report (board row t-mup47bdm-av4j)

Branch: `docs/p10-ledger-reconciliation` (base `arch/agent-guided-governance`, head of base `0641991b`).
Scope: governance documents only. No compiler change, no matrix run, no gate checkbox ticked.

## The contradiction

The record was published into the repository by commit `ec4c5c2d` (2026-09-30,
"docs(architecture): publish the acceptance and reflection record"), but the
gate ledger still described it as living in scratch (`dc-warn/out/`), cited the
superseded draft path `out/p10-reflection/ACCEPTANCE-REFLECTION.md`, and
reported a "452-line frozen record revision" while the published file is
368 lines.

## Changes

1. `docs/architecture/GATE-LEDGER.md` (P10 section):
   - P10-1 evidence now cites the published record `docs/architecture/ACCEPTANCE-REFLECTION.md` §2.
   - P10-2 evidence now cites the published in-repo revision (368 lines, `ec4c5c2d`).
   - P10-3 evidence states the superseded fact: the record is published in-repo
     (`ec4c5c2d`); the verdict stays PARTIAL because the published record is
     marked DRAFT and sign-off belongs to the gate owner.
   - P10 overall stays **NOT PASSED**; the reasoning note explains that
     publication reconciles the ledger with fact but does not accept the gate.
   - "What would move each FAIL": the P10-3 row is marked **DONE** with the
     publication commit, the same pattern as the P09-5 row.
   - P09 and P12 sections untouched: both remain **NOT PASSED**.
2. `docs/architecture/ACCEPTANCE-REFLECTION.md`: the "Published here" note now
   names the publication commit and states that publication does not tick
   `work-plan:220` or change any gate verdict. Record body unchanged.
3. `docs/architecture/PROBLEM-CLASSIFICATION.md`: rule 4's citation of the P10
   record now points at the published path, noting the superseded scratch path.
4. `docs/architecture-work-plan.md`: scheduling paragraph now records that the
   first-round record is published in-repo (`ec4c5c2d`) while the checkbox
   stays unchecked pending gate-owner sign-off.

## What was deliberately not done

- No `- [ ]` checkbox ticked anywhere (P08/P09/P10/P12 all remain unchecked).
- No verdict changed for P09 or P12; P10's overall conclusion unchanged.
- No matrix evidence fabricated; every new claim cites `ec4c5c2d`, the published
  file, or an existing retained report.

## Verification

Grep consistency check on this branch (run at change time):

- `grep -rn "out/p10-reflection"` in the four governance documents returns only
  the PROBLEM-CLASSIFICATION mention, which is explicitly labelled as superseded.
- No governance document still claims the record lives only in scratch; the
  phrase "lives in scratch" no longer appears in GATE-LEDGER.md.
- `git log --oneline -1 ec4c5c2d` and `wc -l docs/architecture/ACCEPTANCE-REFLECTION.md`
  (= 368) confirm the publication fact cited by the ledger.
