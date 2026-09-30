# Management ruling, round 137

Retained because it is binding. Source: the Sol management review of round 137
(dispatched as run-92 against this line); its raw output is
`dc-warn/out/sol-review-137/SOL-REVIEW.md`. This file exists because the ruling was
cited and acted on but never retained into the repository - an omission on the
coordinator's side, recorded here rather than left as a dangling reference.

Operative points:

- **Contract 3 condition 3: APPROVED (`核可`).** The status is to be written exactly as
  `EXERCISED (SYNTHETIC FLAKE-SHAPED INPUT; NO REAL FLAKE OBSERVED)`. Keep the wording
  "No real flake was observed, and none is claimed", and keep the evidence's own
  limitation about the real-rendering method and the inability to re-invoke bun 1.3.13
  locally. The implementation and that evidence are merged onto the line and are
  approved; **it must never be described as having observed a real flake.**
- **Contract 3 condition 4: STILL NOT SATISFIED.** The standing ruling holds: P08 remains
  **PREPARABLE, NOT NOMINATE-ABLE**. Conditions 1-3 being merged does not change this,
  and beginning preparation must not be used to imply P08 is now nomination-eligible.
- **The R2/R3 evidence package: not committing the three ~32MB tars is APPROVED.** Given
  that the commits, the README, the checksums and the regeneration commands already
  suffice for byte-level re-verification - and that three
  `git archive --format=tar <commit> | sha256sum` comparisons were measured identical -
  the tars are not to be committed. This holds unless regeneration conditions, the
  checksums, or the independence claim are later found to be invalid.
- **Stale board rows may continue to wait** for the per-name adjudication of the remaining
  budget-class timeouts on their baseline; they are not to be re-executed merely because
  `40cf0ad0` already covers the premise.

## Minimum action for the next round

**Begin preparing the P08 successor candidate material only**, explicitly labelled
"preparable, not nominate-able", and close or verify condition 4. Until condition 4 is
satisfied and a later explicit ruling says otherwise: do not nominate, do not declare a
pass, and do not change its status.

Beyond that preparation and the condition-4 verification: no new implementation, no new
tests, no new evidence archiving, and no history rewriting.
