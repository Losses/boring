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

## Per-file retention rationale (H7, 2026-10-01)

Five files in this tree are **not** cited anywhere in `e2e-run-REPORT.md`.
Their hashes are pinned by `SHA256SUMS.txt`, but a hash proves only that the
bytes were not altered — it says nothing about *why* the file is kept here.
This section supplies that reason for each of the five, so a reader who opens
the directory without the out-of-repo audit report can tell why each file
belongs. The reasons below were verified by reading the files and by
`git`/`diff` provenance, not transcribed from any out-of-repo report.

### `run-pipeline.sh` — the run's driver script (reproducibility)

This is the executable that actually performed the 2026-09-30 run. It is the
CI-shaped driver: it sets the chainA `PATH` env (the sanctioned toolchain
substitution recorded in REPORT.md §2), then runs each stage in order —
`bun install`, the eight `gen:*` haxe scripts, then the blocking
`bun run test` collected suite — writing each stage's raw output to
`evidence/<name>.log` and appending a start/rc/end line to
`evidence/stage-exits.txt`, aborting on the first non-zero rc.

It is kept because it is the *definition of how the run was performed*, i.e.
the reproducibility half of the evidence. Its output `stage-exits.txt` is
itself retained and its timestamps match REPORT.md §2's run table exactly
(e.g. `bun-install` 16:41:36, `collected-suite` 16:46:15 → 17:25:20, rc 0),
so the script and its log cross-check each other. Without it, a reader could
verify that `collected-suite.log` is unmodified but could not reconstruct
what command sequence produced it. It corresponds to REPORT.md §2's stage
table and to the "Substitutions, named" note (the chainA `PATH` line).

### `evidence/report-step-body.sh` — the report step as committed in CI

This is the report-step body extracted verbatim from
`.github/workflows/ci.yml` (the "Report the counts, the collection domain,
and the failure attribution" step), dedented, with the hardcoded
`LOG=out/collected-suite.log` on line 1. It is the *source* from which
`evidence/report-step-body-e2e.sh` was derived: the two scripts are
byte-identical except line 1, where the e2e variant repoints `LOG=` at this
run's log
(`/home/losses/Development/tq-workspace/dc-warn/out/e2e-run/evidence/collected-suite.log`).
That one-line difference is exactly why **both** must be retained:
`report-step-body.sh` is the "as-committed-in-CI" form and is the root cause
of the recorded misstep — its hardcoded `LOG=out/collected-suite.log`
resolved to the *stale* red log, producing the bogus "7 fail, assertion 7"
table that REPORT.md §2 documents and retains. Keeping the unmodified
committed body lets a reader reproduce that misstep and confirm the clean
numbers in REPORT.md §3 came only from the regenerated run against
`evidence/collected-suite.log`. It corresponds to REPORT.md §2's
"Report step" and "Recorded misstep" notes.

### `evidence/ci-report-step.txt` — the verbatim CI workflow block

This is the raw YAML block (lines 379–696) of the report step in
`.github/workflows/ci.yml`, captured byte-for-byte before dedent — it still
carries the `- name:`, `if: always()`, and `run: |` header and the 10-space
indentation. It is the *original source* that proves `report-step-body.sh`
(and hence `report-step-body-e2e.sh`) were extracted verbatim and not
invented or hand-edited: dedenting `ci-report-step.txt`'s `run:` body by 10
spaces yields exactly `report-step-body.sh` (`diff` rc=0). It is kept so the
"extracted verbatim from `.github/workflows/ci.yml`" claim in REPORT.md §2
is checkable inside the repository, against the actual workflow source,
rather than only against the already-transformed `report-step-body.sh`. It
corresponds to REPORT.md §2's "Report step" note.

### `evidence/sha256.txt` — the run's own four-entry manifest

This is the manifest the run itself wrote (not an intake artifact). It lists
four entries — `collected-suite.log`, `step-summary.md`,
`report-step-stdout.log`, `stage-exits.txt` — and all four hashes match this
intake's `SHA256SUMS.txt` for the same files. It is kept because it is the
run's self-declared record of what it considered its outputs, independent of
the intake's own `SHA256SUMS.txt`; the two manifests agreeing is itself
evidence that the intake mirrored the run faithfully.

### `evidence/archived/stale-out-collected-suite.log` — the misstep's input

This is the 8155-byte, 12 pass / 7 fail / 19 tests *red* log from an earlier
run (Sep 30 15:44) that the first, misdirected report-step invocation read
via the hardcoded `LOG=out/collected-suite.log`, producing the bogus "7 fail,
assertion 7" table. It is retained as the adverse/negative evidence for the
recorded misstep: it is the *input* that made the misstep happen, so a
reader can confirm the misdirected invocation was not a fabrication and that
the clean numbers in REPORT.md §3 came from a different, regenerated log. It
corresponds to REPORT.md §2's "Recorded misstep" note and to the
`report-step-stdout.misdirected-at-stale-out-log.log` limit recorded below.

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
