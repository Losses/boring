# Contract 3 condition 4 - entry-gate evidence record

**Subject:** `eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e` ("test(ts): pin the by-name
runtime import the package shell rejection test asserts against"), tree
`0a61e32ab7978b37de4d5362c548b50609b6b3fd`.

**Seat:** condition-4 closure seat. Not the implementer of `eec707b9`, not the
author of the R2/R3 package committed as `1704c3db`, not the independent reviewer
whose report is in `dc-warn/out/verify-eec707b9/`.

**Worktree:** `boring-wt-cond4`, branch `evidence/contract3-condition4-closure`,
based on `arch/agent-guided-governance` at `5a8f19e6`. The shared tree
`boring-wt-architecture` was read-only throughout.

**Scope:** evidence only. No implementation, test or workflow file is touched.
P08 is **not** nominated; no gate's pass status is changed; `c8ae0054` is not
touched or reopened.

---

## 1. What already existed when this seat started

| Artefact | Where | Producer |
|---|---|---|
| R2/R3 package for `2aadcb69`, `4f80322c`, `eec707b9` | `docs/architecture/evidence/entry-gate-r2r3/` (commit `1704c3db`) | the round-128-authorized evidence commit |
| Independent five-claim check of `eec707b9` | `dc-warn/out/verify-eec707b9/REPORT.md` (scratch) | independent verification seat |
| Executor's own claim-versus-commit adjudication | `dc-warn/out/package-shell-adjudication/REPORT.md` (scratch) | the implementing seat |
| The tool | `tools/gate-proof/verify-commit.ts`, `bun run gate:verify --` (commit `6322af89`) | tooling seat |
| A sibling seat's condition-4 claim | `docs/architecture/p08-candidate-material/P08-SUCCESSOR-CANDIDATE-MATERIAL.md` §5, branch `prep/p08-candidate-material`, commit `32f76bd9` (**not** an ancestor of this branch) | the P08-preparation seat |

The independent check (`verify-eec707b9`) confirmed all five technical claims and
then failed the entry on **requirement 2** (no clean working-tree proof) and
**requirement 3** (no independently exported content), explicitly leaving
requirements 1 and 4 met.

## 2. The four requirements, item by item

Requirement text is quoted from `docs/architecture/GATE-LEDGER.md`, "Ledger entry
gate (required by the round-5 ruling)".

| # | Requirement (verbatim) | Status under the gate | What evidences it | This seat's independent verification |
|---|---|---|---|---|
| 1 | "A traceable commit hash." | **MET** | Ledger condition-4 row names `eec707b9`; `MAPPING.md` carries the full id `eec707b9b09ccabdc7541b74174c6d8cf1e9ef0e` | `[EXEC]` `git rev-parse --verify eec707b9^{commit}` resolves to that full id; `^{tree}` = `0a61e32a…`, the tree the package's R2 file and my own detached worktree both report |
| 2 | "A clean working-tree proof for that hash." | **MET** | `entry-gate-r2r3/eec707b9.R2-worktree.txt` (committed): raw output of a detached worktree at that commit - `git rev-parse HEAD`, `git rev-parse HEAD^{tree}`, `git status --porcelain` | `[EXEC]` reproduced from scratch at a fresh temporary detached worktree: HEAD and tree identical, **0 porcelain lines** (`evidence/R2-independent-eec707b9.txt`). Method is the one round-112 clause 1 itself prescribes |
| 3 | "The candidate content/checksums, exported independently from that commit or from an explicit freeze archive - not read out of a live worktree." | **MET** | `entry-gate-r2r3/eec707b9.export.tar.sha256` (committed checksum) + `entry-gate-r2r3/eec707b9.R3-manifest.txt` (committed per-file manifest, 1455 entries) + the mechanical verdict committed here | `[EXEC]` recomputed `git archive --format=tar eec707b9 \| sha256sum` = `ad7004d7…`, equal to the committed checksum; manifest is byte-identical to `git ls-tree -r eec707b9` normalised to `oid  path` (1455/1455) and is commit-specific (4 and 6 lines differ from the other two commits' manifests); **every one of the 1455 exported files re-hashed with `git hash-object` equals both the manifest and the recorded tree blob - 0 disagreements**; `bun run gate:verify` returns **PASS, 0 mismatches** in `archive-verify` mode *and* in `--verify-export` mode over an independently extracted export |
| 4 | "A claim-versus-commit consistency check, by both the executor and a reviewer." | **MET** | Executor: `dc-warn/out/package-shell-adjudication/REPORT.md` (the implementing seat's own spec/git/exec derivation). Reviewer: `dc-warn/out/verify-eec707b9/REPORT.md` - five claims re-derived from the spec, git history and the reviewer's own runs, **5/5 CONFIRMED**, and it states requirement 4 as met by that report | `[EXEC]` re-checked the load-bearing commit-scope claim: `git show --stat eec707b9` touches exactly 2 files, +20/-3 (`docs/architecture/BASELINE-FAILURES.md`, `tests/ts/package-shell.test.ts`); the *exported* `tests/ts/package-shell.test.ts` (oid `e2dc5965…`) carries the pin `runtimeImport: "@boring/runtime"` at :253 and the rewritten matcher `/^-D runtime-import=[^\s]+$/m` at :45 - i.e. the export really is the fixed revision, not a same-named file |

**All four requirements are met.** No requirement is unmet, waived or reinterpreted
by this record. Clause 3 of round-112 ("fix the one-to-one correspondence with the
full commit id, tree id and review id") is carried by `MAPPING.md` plus this table.

## 3. What was actually missing, and what this record adds

Nothing in the four requirements was missing an artefact any more. Two things were
still missing from the **record**:

1. **The project's own mechanical verdict for `eec707b9` was never in the
   repository.** `gate:verify` had been run against `eec707b9` three times in
   git-ignored scratch (`dc-warn/out/gate-evidence/eec707b9.json`,
   `dc-warn/out/gate-tooling/evidence/pass-eec707b9.json`,
   `dc-warn/out/p08-prep/evidence/gate-verify-eec707b9.json` — all the same
   `archive-verify` PASS), and the third of those is cited by the sibling seat's
   committed candidate-material record. No verdict was committed as an evidence
   artefact. The committed package pins the export by checksum and lists the
   manifest; it does not carry the re-hash comparison verdict that requirement 3's
   own method paragraph calls "the check". This record commits that verdict, in both
   modes, with the raw stdout, obtained through the project's tooling.
2. **The ledger row contradicted its own evidence.** The condition-4 row still read
   "entry does not yet satisfy the entry gate" after the package had been committed
   and after round-128 ruled the R2/R3 threshold closed. The sibling seat's record §5
   states that the mechanical evidence "completes the evidence form the gate requires"
   while explicitly changing no ledger verdict, so the contradiction stood. The row is
   corrected in the same commit, preserving the original text.
3. **The sibling run is not a second independent confirmation of this one.** It is
   `archive-verify` only: it never checks the committed R2/R3 artefacts against
   reality (the manifest against `git ls-tree -r`, the R2 worktree output, or whether
   the PASS could fail), and it does not touch the ledger. It is recorded here so the
   two records are not mistaken for mutually corroborating reviews of the same thing.
   The overlap is also posted to the workspace chatroom.

Raw logs are in `evidence/`. `SHA256SUMS.txt` covers every file in this record
**except itself** (it cannot hash itself); unlike the R2/R3 package's copy, it
contains no self-referential line.

## 4. What this record does not claim

- **Requirement 2's proof is empty for any commit.** A fresh detached worktree is
  clean by construction, so the porcelain result carries no information about the
  state of the worktree `eec707b9` was originally delivered from; that state is not
  retroactively recoverable. The gate's method paragraph adopts this definition and
  round-112 clause 1 prescribes exactly this procedure, so the requirement is met as
  written - but the limit is stated rather than hidden.
- **Requirement 3's content is checksum-pinned, not retained.** The 10.8 MB export
  tarball is deliberately not committed (`entry-gate-r2r3/README.md` gives the
  reason); it is one command from the commit and its SHA-256 matches the committed
  checksum. `gate:verify` was therefore run over both a freshly produced archive and
  an independently extracted directory.
- **I did not re-execute the test suite or the three discriminating haxe
  configurations.** Those are the executor's and the reviewer's measurements;
  requirements 2-3 ask for export/clean-tree evidence, which was this seat's
  verification target.
- **Requirement 4's evidence has no in-repo location.** Both the executor's
  adjudication and the reviewer's check live under `dc-warn/out/` (scratch). That is
  a record-location weakness of the entry, not a missing check.
- The `MAPPING.md` "Reviewed by" ids `02507c97` / `e32fd55e` **do not resolve to
  commits in this repository** - they name review seats/reports, not objects. The
  correspondence they assert is to review documents, and those documents are the two
  reports named in row 4.
- Nothing here reopens, re-explains or re-measures `c8ae0054`, and nothing here
  nominates P08.

## 5. Discrepancies observed and left alone

- `entry-gate-r2r3/SHA256SUMS.txt` contains a line for itself whose value is
  `e3b0c442…` - the SHA-256 of the empty string, not (impossibly) the file's own
  hash; `sha256sum -c` reports that one line FAILED while the other 11 verify OK.
  Recorded, not repaired: rewriting a committed evidence package would rewrite the
  evidence.
- Round-128 authorises "R2/R3 的 14 个构件" for the repo; the package actually holds
  **12** tracked files (9 per-commit artefacts + `MAPPING.md` + `README.md` +
  `SHA256SUMS.txt`). The count difference is recorded, not resolved.
- `bun run check:docs` is **red at baseline** (418 candidate hits, exit 1 on a tree
  stashed back to `5a8f19e6`) and red after this record's documentation change (437,
  exit 1); 14 of the added hits name this record. It is a repo-wide candidate
  scanner, not a gate, so nothing was broken by this change; the 8 em-dashes in the
  first draft of this README were converted to ASCII hyphens. `bun run check:ledger`
  is green (exit 0). Measurement and the residual: `evidence/doc-style-and-ledger-check.txt`.

## 6. Provenance of this record

Produced and committed by the condition-4 closure seat on 2026-09-30 (America/Toronto)
from worktree `boring-wt-cond4`. Commands and raw output are in `evidence/`; the
export tarball and extracted tree used for verification live in
`dc-warn/out/cond4-closure/` (scratch, not committed).
