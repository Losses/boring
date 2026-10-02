# VIII Priority Text Intake

**Intake timestamp**: 2026-10-02T13:23:04+00:00
**Product HEAD**: `0f5979bd14240b592b74a8b7ecddf1c5011891a0`

## What this directory is

This is a **text-priority intake** of files that were missing from the product
repository at the time of comparison. It is NOT a complete directory mirror.
The intake includes:

### Per-directory breakdown

| Directory | Non-empty text (copied) | Empty (recreated) | Total |
|---|---:|---:|---:|
| `fsmissing/` | 87 | 21 | 108 |
| `param-fix/` | 20 | 2 | 22 |
| `param-identity/` | 9 | 0 | 9 |
| `p09-coord-state/` | 6 | 0 | 6 |
| **Total** | **122** | **23** | **145** |

- **122 non-empty text files** — copied byte-for-byte from the evidence originals
- **23 empty (0-byte) files** — recreated in place. These empty files
  preserve **path meaning** (e.g., empty logs like `stderr`/`stdout` indicate
  the stage produced no output to that stream). Do NOT substitute other empty logs.

## What this directory is NOT

1. **Not a complete directory recovery.**  Content-identical (`equivalent`) files
   already exist elsewhere in HEAD and are not duplicated here. This intake does
   not claim byte-complete restoration of the four originals directories.

2. **Build binaries are NOT included.**  The 4 build artifacts (jar/rlib/ELF)
   are retained at their original path in the outer root repository (commit
   `3aeaf844`, `audit-reports/viii-evidence-originals/`). They are not moved into
   the product repo, and this intake does not claim complete restoration.

### Binaries retained in outer root-repo archive (captain-adjudicated)

These 4 files are NOT copied here. Captain decision: retain them at their
original path under the outer root repo commit `3aeaf844` →
`audit-reports/viii-evidence-originals/`; they stay out of the product repo.

- `fsmissing/attempt-01/kotlin-build/library.jar` (5,676,887 bytes) — build artifact (jar/rlib/ELF)
- `fsmissing/attempt-01/kotlin-build/tests.jar` (990 bytes) — build artifact (jar/rlib/ELF)
- `fsmissing/attempt-01/rust-build/harness` (4,576,648 bytes) — build artifact (jar/rlib/ELF)
- `fsmissing/attempt-01/rust-build/libdc_fs_missing.rlib` (713,362 bytes) — build artifact (jar/rlib/ELF)

## Equivalent files (content already in HEAD)

21 files were identified as `equivalent`: their blob oid already
exists in the product HEAD tree at `0f5979bd`. They are NOT copied here.

**Scope of "equivalent":**  The match means byte-level content reuse only —
the same blob oid happens to exist elsewhere in the product tree at this commit.
The cited HEAD paths document where that identical blob can be found, but they
do **NOT** prove that those cited runs share state, provenance, or outcomes
with this intake. The original path→oid mapping preserves THIS intake's source
identity (see `equivalent-map.tsv`).

**All HEAD path references are pinned** to commit `0f5979bd14240b592b74a8b7ecddf1c5011891a0`.
They are not relative to a floating `HEAD` ref.

| Orig dir | Orig path | Existing HEAD path(s) |
|---|---|---|
| fsmissing | `REPORT.md` | `audit-reports/viii-disaster-intake/fsmissing/REPORT.md` |
| fsmissing | `attempt-01/stages/compile-kotlin-harness/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/compile-kotlin/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/gen-dart/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/gen-kotlin/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/gen-rust/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/gen-swift/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/gen-ts/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/haxe-oracle-build/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/haxe-oracle-run/status` | `docs/architecture/evidence/ledger-cited-reports/p08-implementation-review-evidence/evidence/bun-readonly-boundary-cand.rc (+ 17 more)` |
| fsmissing | `attempt-01/stages/run-kotlin/status` | `docs/architecture/evidence/ledger-cited-reports/p08-implementation-review-evidence/evidence/bun-readonly-boundary-cand.rc (+ 17 more)` |
| fsmissing | `attempt-01/stages/run-rust/status` | `docs/architecture/evidence/xs-fixture-archive/evidence-raw/as-reviewed-xs-crossmod/cargo.status (+ 6 more)` |
| fsmissing | `attempt-01/stages/run-ts/status` | `docs/architecture/evidence/ledger-cited-reports/p08-implementation-review-evidence/evidence/bun-readonly-boundary-cand.rc (+ 17 more)` |
| fsmissing | `attempt-01/stages/rustc-bin/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/rustc-lib/status` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |
| fsmissing | `attempt-01/stages/swift-env-probe/status` | `docs/architecture/evidence/ledger-cited-reports/p08-implementation-review-evidence/evidence/bun-readonly-boundary-cand.rc (+ 17 more)` |
| fsmissing | `attempt-01/swift-gen/std/UStringException.swift` | `docs/architecture/evidence/ledger-cited-reports/p08-behaviour-review-evidence/evidence/gen-bisect-coalesced2/std/UStringException.swift (+ 1 more)` |
| fsmissing | `attempt-01/swift-gen/std/UStringFault.swift` | `docs/architecture/evidence/ledger-cited-reports/p08-behaviour-review-evidence/evidence/gen-bisect-coalesced2/std/UStringFault.swift (+ 1 more)` |
| fsmissing | `versions/REPORT.att-01-15files.md` | `audit-reports/viii-disaster-intake/fsmissing/REPORT.md` |
| param-fix | `REPORT.md` | `audit-reports/viii-disaster-intake/param-fix/REPORT.md` |
| param-fix | `post-fix-runsh/exit.txt` | `docs/architecture/evidence/ledger-cited-reports/flake-synthetic/evidence/run-v0-baseline/step-exit-code.txt (+ 41 more)` |

See `equivalent-map.tsv` for the full machine-readable listing including the
original blob oid for each entry.

## Verification

- `SHA256SUMS` contains SHA-256 hashes for all 145 files in this intake.
- Run `sha256sum -c SHA256SUMS` from this directory to verify integrity.
- Each copied file was verified byte-identical to its original via `cmp -s`.
