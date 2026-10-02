# Governance sweep — periodic stop/cancel for stale candidates, dead rows, orphan worktrees

**Status:** active hard process (recovery plan §3.4 item 4, "停止/取消治理常态化").
**Tool:** `tools/governance-sweep/sweep.sh` (one run = current counts + full lists for all three classes).
**Established:** 2026-10-01, recov/r34 (report: `audit-reports/r34-governance-sweep-2026-10-01.md`; out-of-repo note, 2026-10-01: this path lives in the workspace at `/home/losses/Development/tq-workspace/audit-reports/`, outside the boring repository).

## 0. Scope statement — why this file is outside the RULING-137 prohibition

`MANAGEMENT-RULING-137.md:37-38` reads, verbatim:

> Beyond that preparation and the condition-4 verification: no new implementation, no new
> tests, no new evidence archiving, and no history rewriting.

The prohibition is scoped: "Beyond that preparation and the condition-4 verification" — it
fences off the **P08 candidate line** (compiler/behaviour implementation, tests pinning P08
claims, archiving of evidence for the condition gates, history of the sealed candidate).
This document and its tool touch none of that: they implement no compiler behaviour, add no
tests, archive no evidence, rewrite no history, and change no status of any candidate or
board row. They are **recovery-process governance** — the same class of object as
`tools/merge-precheck/` (recovery plan §3.4 item 1, already reviewed and merged on
`recov/r56r-precheck-review`), which the recovery mandate itself requires to exist as an
executable hard process. A §3.4 item that exists only as prose in a report is not a hard
process; item 4 says "每轮清理，不累积到 33 行幽灵再爆", which requires a runnable check.
This file is that check's documentation, not P08 material.

## A. The three object classes — criteria and listing commands

### A.1 Stale candidates（过期候选）

**Criterion:** a revision that a management ruling has sealed/rejected/superseded, yet which
still exists in the repo under "candidate/in-play" bookkeeping — typically still recorded as
frozen in `docs/architecture/REFREEZE.md`, while a `MANAGEMENT-RULING-*.md` states it is
`NOT PASSED / REJECTED` or sealed. Example of record: the current disaster — `c8ae0054` was
finally sealed by RULING-245 ("`c8ae0054` is NOT PASSED / REJECTED, finally.") and RULING-005
re-states it ("P08 stays sealed"), yet `REFREEZE.md` still carries, as its only entry,
`Candidate revision: c8ae0054`.

**Listing command** (extract frozen revisions, cross-check every ruling):

```bash
grep -o 'Candidate revision: `[0-9a-f]\{8,\}`' docs/architecture/REFREEZE.md \
  | sed 's/.*`\([0-9a-f]*\)`.*/\1/' \
  | while read -r sha; do
      hits=$(grep -l "$sha" docs/architecture/MANAGEMENT-RULING-*.md \
             | xargs grep -liE 'REJECT|sealed')
      [ -n "$hits" ] && echo "STALE $sha -> $hits" || echo "ok    $sha"
    done
```

### A.2 Dead board rows（失效行）

**Criterion:** a board row with `status=doing` whose `branch` (and every claim branch) exists
neither under `refs/heads/` nor `refs/remotes/origin/`. Rows whose `branch` field is empty
entirely are reported too (the board cannot locate the work at all).

**Mandatory sub-classification** — "branch vanished" is two different facts, and the verdict
line always names the evidence tier that decided it:

- **DEAD-MERGED** (`basis=reachability`) — a merge commit reachable from MAIN records the
  branch in the merged-in position (`Merge branch '<br>'...`, `merge: <br> ...`,
  `merge: integrate <br> (...) ...`), so MAIN's history holds the branch's commits. The
  merge's last parent is the last-seen branch tip and is re-checked with
  `git merge-base --is-ancestor <tip> <MAIN>`. Exact token only: `warn/r1` does not match
  `warn/r10`. The *content* is safe; only the row's bookkeeping is stale.
- **DEAD-MERGED-INFERRED** (`basis=path-inference`) — no recorder merge exists, usually
  because the work was recorded under an aggregating branch name, or because it reached the
  mainline before the anchor. The sweep then reads the row's own declared artifacts and
  reports the paths that exist on MAIN, did not exist at the anchor, and are attributed to a
  reachable adding commit. This tier is an inference, so a reviewer must confirm the paths
  against the row before treating the row as reconciled.
- **DEAD-UNMERGED** — neither tier found evidence: no mainline merge records the branch, and
  no artifact the row declares is new at the anchor. The work has no known home. These are
  the rows that need a per-row disposition (rebuild / cancel / merge-register), decided by a
  human or the coordination seat, never auto-cancelled.

Both tiers read the whole mainline history. The window anchor `b1188eec` is now only the
provenance anchor of the fallback tier: an earlier form scanned `b1188eec..MAIN` for the
branch name in merge subjects, which hid merges recorded before the anchor and could not see
a branch that was absorbed under another branch's name.

The `warn/dart3` pattern stays DEAD-UNMERGED on purpose: row `t-muhbbydw-w3w4` points at
`warn/dart6`, no mainline commit subject names `warn/dart6`, and the row's declared artifacts
name no path that is new at the anchor, so neither tier has evidence that this row was
absorbed. The content may well have reached the mainline under `warn/dart3` (`f6f7e3d3`); the
sweep cannot tell, and it must not claim it can.

**Listing command:**

```bash
bash tools/governance-sweep/sweep.sh          # the criterion, both tiers, live
bash tools/governance-sweep/sweep-negctl.sh   # negative control for the criterion
```

`sweep-negctl.sh` builds a fixture board whose rows are known-merged and known-unmerged and
asserts that the two judgements are opposite; pointed at the pre-fix revision it must fail
(mutation check, see §C). Per PIT-478, address board rows by internal row id, never by branch
name; the sweep prints both.

### A.3 Orphan worktrees（孤工作树）

**Criterion:** a *registered* worktree (`git worktree list`) whose HEAD is **detached** and
which is not active recovery work. Two exclusions:

- `recov-*` worktrees/branches are **never orphans** — they are active recovery work
  (r55 §1: 6 such trees correspond to recovery plan items and "不得删除");
- detached-but-pinned checkouts with a live task (e.g. a review seat mid-measurement) are a
  coordination question, not an automatic orphan — the sweep lists them; the coordination
  seat confirms before any removal.

Forensic base: r55 counted 43 registered worktrees under `dc-warn/worktrees/` + 1 non-git
entry, 37 of them detached @ `e1c65975`, all with uncommitted changes, categorized A/B/C with
"必须存档后删" for class C — removal is always archive-first (PIT-469).

**Listing command:**

```bash
git -C boring worktree list --porcelain \
  | awk '/^worktree /{p=substr($0,10)} /^branch /{p=""} /^detached/{if (p !~ /recov-/) print p}'
```

## B. Current inventory (2026-10-01, at mainline `6af45096`)

Aggregated from r52 (row-by-row ghost reconciliation), r55 (worktree forensics), r33 (freeze
review) + a live `sweep.sh` run (exit 1, 90 objects). **Removal/archival is executed only by
the coordination seat**; this seat only lists.

### B.1 Stale candidates — 1 object

| Identity | Criterion basis | Evidence | Action | Decider |
|---|---|---|---|---|
| `c8ae0054` (full: `c8ae0054d8b1937cf05c0dd849c268807ae19b8f`) — still the sole `REFREEZE.md` entry | Sealed by RULING-245 point 1/4 ("NOT PASSED / REJECTED, finally"; "do not commit, modify or rewrite that candidate") and re-stated by RULING-005 | r33 §逐条结论: 0 successor freezes, 0 independent reviews; live sweep class 1 | **Keep the freeze record as historical identity record; annotate, do not delete.** The freeze of a *sealed* candidate is not itself a violation — REFREEZE is an identity record, not a live-candidate list. What is missing is the *successor* freeze (recovery plan R3.1–R3.3) | Coordination seat annotates; next ruling (management review per R2.3) owns any status change |

**How `REFREEZE.md` must be read given current facts (one sentence):** its sole entry is a
historical *identity* record for `c8ae0054`, a candidate that RULING-245 has since sealed
REJECTED — so today the file records a dead candidate and **no live frozen candidate**;
any reader treating that entry as "P08's current frozen candidate" is reading a superseded
record. **Gap vs §3.5 fourth completion criterion:** yes, this is a gap — the successor
content (`c8ae0054` lineage + `449444cf` + S1) sits on the mainline *unfrozen and
unreviewed* (0 freezes, 0 independent reviews per r33), i.e. "未冻结、未复核却被记为已清偿
的候选内容" risk persists until R3.1–R3.3 declare/re-freeze/re-review it. Closing that gap
is R3's work, explicitly **not** this file's (see scope statement).

### B.2 Dead rows — 33 doing rows scanned: 3 DEAD-MERGED, 28 DEAD-UNMERGED, 2 empty-branch

Sub-classification of the r52 35-row reconciliation (33 ghost + 2 empty), refreshed live:
r52's "done 0 / cancelled 2 / rebuild 31" dispositions remain the per-row decision record;
live sweep adds the merge-class split:

**Criterion refresh (2026-10-01, `fix/sweep-merge-criterion`):** the counts below come from
the window+substring form that §A.2 now replaces, so the split moved once the criterion was
fixed at `f434a9c4` (32 doing rows scanned):

```
stale candidates:   1
dead rows (unmerged): 23  dead rows (merged): 6  dead rows (merged, path-inference): 1  empty-branch rows: 2
orphan worktrees:   31
RESULT: 64 object(s) need governance action (exit 1)
```

Four rows moved from DEAD-UNMERGED to DEAD-MERGED by reachability (`warn/kotlin` x3 via
`9d37247b Merge branch 'warn/kotlin' into warn/zero`, `warn/dartts` via `9ff90845`), and
`gate/p08-swift-readonly-boundary` moved to DEAD-MERGED-INFERRED. `warn/dart6` and the W0 row
stay DEAD-UNMERGED (§A.2 explains why that is the intended result).

- **DEAD-MERGED (3)** — `t-muhbc7gp-sg81` (`warn/ts3`), `t-muhbc7hk-zvbl` (`warn/r1`),
  `t-mum0usfn-wwg8` (`audit/variable-bound-loop-eval`): content on mainline via the
  disaster merges; rows stay `doing` (work *not* complete per R4), merge fact
  timeline-noted per PIT-477. Action: **reconcile bookkeeping, keep doing**. Decider:
  coordination seat.
- **DEAD-UNMERGED (28)** — per r52 §2: most are **rebuild** (P08/P09/gate lines
  `t-munq08t2-rgxp`, `t-muog1rcu-59ow`, `t-mun7x2g3-m4zs`, `t-mun0d1bn-klvo`,
  `t-mun0d7xm-mfwb`, `t-mumy6e28-80nx`, `t-mulyrvsc-96b1`, `t-mumx4s8p-7y5n`, … — work
  still to do, branch re-created from base `f6f7e3d3`); 2 were r52-**cancelled**
  (`t-mumx5bo4-na2g`, `t-mumx5iil-guqs`, superseded by
  `t-mun0colg-y4qu`/`fix/runner-identity-and-provenance` — itself now DEAD-UNMERGED).
  Action: per-row (rebuild / cancel), **decided by coordination seat with the owning
  seat**; I cannot judge row-by-row whether each task is still wanted — that needs the
  work-plan owner.
- **Empty-branch (2)** — `t-muhbbhp0-d4r3`, `t-muhbbhp7-bpln` (W2 gate / integration
  acceptance): unjudgeable by branch presence; need branch assignment. Decider:
  coordination seat.

### B.3 Orphan worktrees — 56 listed by live sweep

Groups and actions (removal always by coordination seat, archive-first per r55 class C and
PIT-469):

- **`dc-warn/worktrees/*` detached @ `e1c65975` (≈43)** — the r55 A/B/C inventory is the
  authoritative per-tree disposition (A: direct delete ×5; B: archive-then-delete ×1;
  C: archive-then-delete ×32, archived to `audit-reports/worktree-archives-2026-10-01/`).
  Action: **archive-then-delete** per r55. Decider: coordination seat (r55 already made the
  classification; no re-adjudication needed).
- **Other detached registered trees (~13)** — `architecture-workspaces/repair-kotlin-staticfnops`,
  `boring-wt-{cs-tipcheck,cs42c805d3,driver-provenance,intmodkey-*,mainline,master-cc9957dd,rust-generic,swift-systempkg}`,
  `dc-warn/cs-*`, `fp-xcheck-*`, `ttsfix-pre`, `xs-run-e1c65975`, `/tmp/{boring-base-perchar,wt-master}`:
  **I cannot judge these** — some are review/checkpoint pins (`cs-*` = commit-pinned checks,
  `*-pre/post` = comparison pairs). Action: coordination seat confirms each against its
  origin task before remove; `/tmp` ones are disposable.
- **Not orphans (excluded by design):** all `recov-*` trees (r55 §1: active recovery work,
  不得删除) and branch-carrying trees.

## C. Periodic check — executable, fail-closed

Run:

```bash
bash tools/governance-sweep/sweep.sh           # the sweep
bash tools/governance-sweep/sweep-negctl.sh    # its class-2 negative control
```

Exit-code contract (**fail-closed**: the failure path can never print "0 objects"):

| exit | meaning |
|---|---|
| 0 | sweep ran; zero objects in all three classes |
| 1 | sweep ran; findings printed (any class non-empty) |
| 2 | sweep did NOT run: missing `git`/`jq`/`awk`, unreadable board/REFREEZE, unresolvable mainline or `SWEEP_MBASE` anchor, or a failing git/jq/grep step — every such step is `fail`-checked, never swallowed |

`sweep-negctl.sh` (exit 0 = control holds, 1 = an assertion failed, 2 = could not run) lifts
the live merged and unmerged rows into a fixture board, adds a substring-trap branch and a
deleted-ref branch, and asserts that the sweep under test judges the merged row and the
unmerged row differently. Pointing it at the pre-fix revision (`--sweep <file>`) must make it
fail; that is the mutation check for this criterion.

Verified run at `6af45096` (full output preserved in
`audit-reports/r34-governance-sweep-2026-10-01.md`):

```
== summary ==
stale candidates:   1
dead rows (unmerged): 28  dead rows (merged): 3  empty-branch rows: 2
orphan worktrees:   56
RESULT: 90 object(s) need governance action (exit 1)
```

Red/green validation (synthetic fixtures under `/tmp/r34-fixture`, real dirs untouched):

- **Red** — fixture repo with a sealed-but-frozen candidate (`c0ffee00abcdef` + RULING-999
  "NOT PASSED / REJECTED, sealed"), a doing row `t-red-0001` → branch `ghost/nowhere`
  (nonexistent), one detached worktree `wtred`: sweep reported all three classes,
  **exit 1** (`stale 1 / dead-unmerged 1 / orphan 1`).
- **Green** — same fixture with the sealing text removed, the branch created, the worktree
  removed: `RESULT: clean — no objects in any class`, **exit 0**.
- **Fail-closed probes** — missing board file → `SWEEP-ERROR: board file not readable`,
  **exit 2**; `PATH` without `git`/`jq` → `SWEEP-ERROR: git not found in PATH`, **exit 2**;
  missing `REFREEZE.md` → **exit 2**. In no failure case was a zero-count printed.

Known limits (documented, not hidden): class 1 matches "ruling mentions sha AND
REJECT/sealed" — a superseded-but-not-rejected candidate needs a ruling-hygiene convention
before it can be automated; class 2 decides by commit reachability with a labelled
path-inference fallback, and the fallback is an inference, so a DEAD-MERGED-INFERRED row
still needs a reviewer to confirm the paths against the row; a branch that no mainline merge
subject records and whose row declares no path that is new at the anchor stays DEAD-UNMERGED,
because a sweep cannot read content that left no trace (`warn/dart6` is the live example:
its content may have been absorbed under `warn/dart3`, and the sweep must not claim that
without evidence); class 3 deliberately reports only *registered* worktrees, so a
`git worktree prune`d
directory or non-git directory (the 44th r55 entry) is invisible to it — directory-level
audits remain a manual coordination item.

## D. Cadence, ownership, and linkage to the pre-merge gate

**Cadence:** every scheduling round that opens or closes ≥1 seat, and always before any
branch/worktree cleanup batch — item 4's whole point is "每轮清理，不累积" (never again let
33 ghost rows accumulate to a disaster). Minimum: once per recovery/scheduling round.

**Ownership:**

| Class | Listed by | Disposition decided by | Executed by |
|---|---|---|---|
| Stale candidates | sweep (any seat) | ruling-issuing mechanism (management review); nobody else may change a candidate's status (RULING-137: "do not change its status" outside a later explicit ruling) | coordination seat annotates records; successor freeze is R3.1–R3.3 work |
| Dead rows | sweep (any seat) | coordination seat + owning seat per row (rebuild / cancel / merge-register per r52 dispositions) | coordination seat is the single board writer (board writes are single-writer by mandate; sweeps never write the board) |
| Orphan worktrees | sweep (any seat) | coordination seat, per r55 A/B/C where applicable | coordination seat only, archive-first (PIT-469), never `--force` without archive |

**Linkage to §3.4 item 1 (`tools/merge-precheck/check.sh`, landed on
`recov/r56r-precheck-review`):** the two gates are the closed loop that would have stopped
the 2026-10-01 disaster. The sweep shrinks the backlog that makes "board fields do not
locate work" true (row must exist, have a live branch, and carry merges evidence before a
merge can pass precheck); the precheck stops any merge from *creating* new dead rows
(status/merges check + ruling-timeline check). Operating rule: a sweep finding of
DEAD-MERGED feeds the precheck's "merges 字段非空" requirement — reconcile bookkeeping
first, then merges of remaining live branches pass the gate; a sweep exit 2 (sweep broken)
must be treated like a red gate: fix the sweep, do not merge around it.
