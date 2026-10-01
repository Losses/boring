# e2e-run evidence intake (D6, 2026-10-01)

This directory is a byte-for-byte mirror of `dc-warn/out/e2e-run/` - the
2026-09-30 end-to-end collected-suite run cited by the GATE-LEDGER entry "The
first real end-to-end run (the round-65 ruling's single next action)". It was
copied `cp -a` to local disk before any reading or hashing (PIT-178: reads
directly off the dc-warn mount can serve stale content), cross-checked by
sha256 against the mount (30/30 files identical), and committed with a
`SHA256SUMS.txt` covering the 29 mirrored run files. It exists so the ledger's
`and evidence/` citation resolves inside the repository.

## Layout mapping

- Every path cited inside `e2e-run-REPORT.md` (one level up) resolves
  **relative to this directory**: the report's `evidence/<name>` is
  `./evidence/<name>` here, and its bare top-level citations
  (`step-summary.md`, `report-step-stdout.log`) are the files of those names
  here. No file was renamed or restructured during intake.
- `REPORT.md` itself is not duplicated here. The committed copy is
  `../e2e-run-REPORT.md`, byte-identical to the run's own `REPORT.md`
  (sha256 `32383504…45c49`, already pinned by this directory's parent
  `SHA256SUMS.txt`).
- `README.md` and `SHA256SUMS.txt` are intake artifacts written by D6 on
  2026-10-01; everything else is run output, unmodified.
- The run's own four-entry manifest is `evidence/sha256.txt`; all four of
  its entries match this intake.
- `step-summary.md` and `report-step-stdout.log` are byte-identical by
  construction (the report step writes the same body to
  `GITHUB_STEP_SUMMARY` and to stdout); the run's own manifest records both
  under the same hash.

## Recorded limits of the retained bytes (observed at intake, not repaired)

- `evidence/report-step-stdout.misdirected-at-stale-out-log.log` is
  byte-identical to `report-step-stdout.log` (sha256 `20d22def…9035`).
  REPORT.md §2 states that the first, misdirected report-step invocation
  produced a bogus "7 fail, assertion 7" table and that its output "is
  retained" in that file. The retained bytes do **not** contain that table -
  they are the clean run's output. The misstep's *input* is verifiable (the
  stale red log is retained as
  `evidence/archived/stale-out-collected-suite.log`, 8155 bytes, 12 pass /
  7 fail / 19 tests), but the misdirected invocation's *output* is not
  reconstructible from what was kept.
- `evidence/report-step-body-e2e.sh` line 1 points `LOG=` at the
  host-absolute path this run used
  (`/home/losses/Development/tq-workspace/dc-warn/out/e2e-run/evidence/collected-suite.log`);
  kept verbatim, as run.
- REPORT.md cites `dc-warn/out/chainA-fixed-rerun/evidence/env.json` as the
  source of the chainA `PATH` substitution. That file remains outside this
  repository (it still existed on the dc-warn mount at intake time).
- The run executed in the `boring-wt-architecture` worktree, which no longer
  exists; its HEAD `9388aa62a7f8678d6297c200ff0198cefcf55b95` is in this
  repository's history, and the fixture blob it records
  (`f3849049fe96d32cfed77bce2cea0977822af3f4`) still resolves at that
  revision.
