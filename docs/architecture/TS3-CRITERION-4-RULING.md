# ts3 criterion 4 — the TS6133 scope ruling, moved out of a timeline comment

The `warn/ts3` row's criterion 4 concerns whether `TS6133` (declared but never
read) belongs in the TypeScript gate profile. The substance was settled on
2026-09-27 in a board timeline comment: **TS6133 is not part of the gate
profile**, and it is run separately instead.

That ruling was reachable only by reading a comment on a board row. The criterion
itself reads "not done" in the row's evidence, which is why the disaster report
records criterion 4 as 未做. Under section 3.5's second definition — any cell
reconstructable by another person from the ledger plus cited evidence — a ruling
that lives only in a timeline comment cannot be reconstructed from the repository.

This record moves it into version control. **It does not create a new ruling and
does not change the existing one.**

## The ruling as recorded on 2026-09-27

`TS6133` is **excluded** from the strict-profile gate. The gate profile is the
embedded tier list in `engine-haxe/tools/ts-gate.sh`; `TS6133` is not among its
tiers, and it is invoked as a separate command when wanted. The reason recorded
at the time is that the generated trees carry declared-but-unread symbols that
the gate is not meant to police.

## The premise was re-measured, not assumed

The ruling's premise is that `TS6133` contributes nothing to the current reading.
Verified against the replay log for the current baseline:

```
grep -c 'TS6133' /tmp/r44/tsc.log   ->  0
```

So the criterion's premise holds at the current revision: excluding `TS6133`
changes no reported error. This is a re-measurement of the premise, not a
re-adoption of the ruling.

## What is NOT claimed here

- Criterion 4 is **not** hereby marked satisfied in the ledger. This record
  supplies the missing in-repo basis; whether the criterion counts as met is the
  row owner's call and a reviewer's to confirm.
- The gate is **not** wired. Criterion 2 requires the `ts3` gate to run inside
  `engine-haxe/tools/gates.sh`, and it does not: `gates.sh` (59 lines) contains
  only the `g4` / `tests` / `compare` targets and **no `tsc`, `ts-gate` or
  `typescript` reference at all** (grep count 0, rc=1). A gate that exists as a
  script but runs in no pipeline has the same status as a check with no
  enforcement point — the failure mode section 3.4 item 1 exists to prevent. The
  gate script also lives only on the `ts3`-family trees, not in the tiqian main
  checkout.
- The row's `readyForReview` being true means only that its evidence fields are
  non-empty; it does not mean the criteria hold (`PIT-457`).
- Convergence from 18 to 0 is **not** in this disaster recovery's scope (R1-R5
  are governance and truth-source repairs), and the row stays `doing` under R4.2's
  own wording: "判据满足后签核".

## Current reading

The mainline reading is **18** errors (`grep -c 'error TS'`), split
**TS2322 6 / TS18047 4 / TS2367 3 / TS2531 2 / TS2345 2 / TS2339 1**, down from 93
at the disaster report. Twelve of the eighteen are source-level defects needing
edits to seven `.hx` files; six are generated-shape gaps; none is a false
positive. Independently recounted twice, matching the first count.
