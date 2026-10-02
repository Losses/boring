# viii-w0-originals — forensic byte-copies of the W0 deliverables

This directory holds **byte-for-byte forensic copies** of four W0-related
deliverables. They
are preserved here as evidence and as a recovery anchor, **not** as a verified,
runnable installation. (Note: these files are not "uncommitted" in the sense of
lost — the workspace-root originals are tracked in the root repository; the
`scripts/warn-tree.sh` copy has long been tracked there, and the other three
were preserved in commit `5333913c`.)

## Status and caveat

- **Forensic copies, not an install.** Each file below is a byte-identical copy
  of the workspace-root original (verified by `cmp`, `sha256sum -c`, and the
  `SHA256SUMS` manifest in this directory). The scripts reference absolute paths
  (`/home/losses/Development/tq-workspace`, `/tmp/swift-shim/...`,
  `dc-warn/warn/...`) and appear to expect specific worktrees, mounts, and
  toolchains; whether those are available here was **not verified in this
  intake**. Copying them into a live `tools/` or `scripts/` location does
  **not** by itself make them runnable here.
- **Style exemption is a user authorization.** The originals contain Chinese
  prose (notably `FREEZE.md` and some diagnostic strings inside the scripts).
  The user has explicitly granted a temporary exemption from the English-only /
  doc-style requirement for this intake, to be handled separately later. This
  exemption applies to the preserved copies; it is **not** a license to add new
  non-English content elsewhere.
- **No translation substitution.** These are the original bytes, not English
  translations. A translation, if one is ever produced, must be a separate
  additional reading aid and must not replace these originals.
- **Missing file.** `scripts/rclone-warn-watchdog.sh` was also named in the W0
  row. Historical records describe it as missing (no copy was found at intake
  time and no git history known to the intake contained it); a dedicated
  recovery search is currently in progress, so this is **not** a claim that it
  is unrecoverable, and it is **not** fabricated here; see the intake record
  `.tq-logs/viii/w0-intake-execution.md` for the evidence.

## Directory layout

The relative layout mirrors where each original lived in the workspace root, so
a reader can tell at a glance what each copy corresponds to:

```
viii-w0-originals/
├── README.md
├── SHA256SUMS
├── tq-warnings.sh                 (was: <workspace>/tq-warnings.sh)
├── tq-verdicts.sh                 (was: <workspace>/tq-verdicts.sh)
├── scripts/
│   └── warn-tree.sh               (was: <workspace>/scripts/warn-tree.sh)
└── .tq-logs/
    └── warnstd/
        └── FREEZE.md              (was: <workspace>/.tq-logs/warnstd/FREEZE.md)
```

## Files and their purpose / usage

| File | Purpose | Usage (not run here) |
|---|---|---|
| `tq-warnings.sh` | Per-target diagnostic histogram for the non-Rust targets. Regenerates the generated trees first, then counts what each target toolchain reports (kotlin / ts / dart / swift), normalised by family. | `bash tq-warnings.sh measure <label>` (regenerate + count → `<label>.tsv`); `bash tq-warnings.sh count <label>` (count only); `bash tq-warnings.sh diff <base.tsv> <cur.tsv>` (family deltas). |
| `tq-verdicts.sh` | Runs the six tiqian bundles and compares their per-case verdicts against the frozen baseline, per case id (never by count). | `bash tq-verdicts.sh run <label> [boring-wt] [tiqian-wt]`; `bash tq-verdicts.sh compare <label>`. |
| `scripts/warn-tree.sh` | Prepares an independent check-and-measure pair of worktrees (one boring, one tiqian) for one warning flow, wiring the three inputs a Haxe generation needs (`.haxelib`, `baseline-goldens`, `unicode-data`) and pointing the generator at the pair's own boring worktree. | `bash scripts/warn-tree.sh <flow> [boring-base] [tiqian-base]`. |
| `.tq-logs/warnstd/FREEZE.md` | W0 freeze record: frozen revisions (boring `f740451e` master as modification baseline, tiqian `fabb08a9` main as verified side), baseline readings, behaviour baseline, disk notes, and the rerun method. This is the anchor document for the "fixed-version regression" criterion. | Read-only reference document; no invocation. |

## Verification performed

- `cmp` original vs copy: **OK** for all four files.
- `sha256sum -c SHA256SUMS` (self-check of the copies): **OK**, rc=0.
- Cross-check of each copy's SHA-256 against the workspace-root original's
  SHA-256: **OK** for all four.
- `bash -n` syntax check on the three shell scripts: **rc=0** for
  `tq-warnings.sh`, `tq-verdicts.sh`, `scripts/warn-tree.sh`.

The scripts were only syntax-checked and described; they were **not** executed.

## Why this path was chosen

The copies live under `tools/recovery/viii-w0-originals/`, not in the live
`tools/` or `scripts/` trees, on purpose: **forensic material is kept separate
from production tooling.** These files are evidence and a recovery anchor; they
are not validated, installed, or wired into any workflow here. Placing them in
the live `scripts/` directory would (a) suggest to callers that they are
supported tooling when they are not, and (b) risk the preserved bytes being
"fixed up" over time, defeating their role as byte-exact originals. The
subdirectory naming (`recovery/viii-w0-originals`) states both the provenance
(VIII incident, W0 row) and the nature (originals) in the path itself.

## Locatability impact on the W0 row (criterion "doing rows all locatable")

With commit `b3c3e8f4`, **four of the five files the W0 row claimed are now
locatable** in the boring repo: `tq-warnings.sh`, `tq-verdicts.sh`,
`scripts/warn-tree.sh` (byte-identical copy) and `.tq-logs/warnstd/FREEZE.md`
(now reachable from HEAD, so no longer dangling). The fifth,
`scripts/rclone-warn-watchdog.sh`, remains unlocated — see below.

**Locatable does not equal accepted.** The W0 row's *technical* criteria (the
substance of SOP1–SOP5: frozen-version regression run, readings, verdicts)
are **not** satisfied by the mere act of archiving these files. Preserving the
bytes answers only the "can we point at what W0 claimed to deliver" question;
it does not make the W0 deliverables' claims verified, and this intake makes
no such claim.

## The missing watchdog: what is and is not claimed

`scripts/rclone-warn-watchdog.sh`: the dedicated recovery search
(`.tq-logs/viii/watchdog-recovery-evidence.md`) was a **bounded search** —
three repositories' full ref history, the root repo's object listing, the
`scripts/` and `scripts/archive/` directories, `.tq-logs` and `docs` greps,
systemd user units, and a targeted `DataCenter` warn-area check. It found
**no original bytes** and concluded: (1) the original is **not fabricated** —
nothing is invented to fill its place; (2) **no rewrite is performed this
round** — and that is a scoped decision, **not** a finding that its function
is fully replaced. The `dc-warn-sshfs.service` notes confirm the old rclone
mount was superseded by sshfs, but the watchdog's full original behaviour
(monitoring logic, restart policy, thresholds) is unrecorded, so functional
replacement is **unproven**. A genuinely exhaustive search (deep mount areas,
Mac side, full-disk find) was **not completed** — criterion-level closure of
"loss proven" therefore requires that complete search and is **not yet met**.

## Source of truth

The authoritative intake record for this recovery is
`.tq-logs/viii/w0-intake-execution.md` in the workspace root. This directory is
the boring-repo copy of the four originals; the workspace-root originals remain
untouched and are the reference the copies were taken from.