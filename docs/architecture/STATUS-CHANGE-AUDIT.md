# Status-change audit (section 3.4 item 2)

Section 3.4 item 2 requires every status change to answer three questions: which
ruling authorizes it, where the evidence lives in-repo, and which tree the
conclusion holds for. Until now nothing answered, required, or even noticed them.

## Why the enforcement is an audit and not a write-time hook

The board lives at `.workspace-board/board.json` in the **workspace** repository,
not in this one, and the plugin that writes it validates neither unknown fields
nor the shape of a timeline entry. A hook installed in this repository cannot see
a board write at all, so "wire it into the merge path" is not available here.

What *is* available is making the absence **reportable on every sweep**. A
missing answer that nothing reports is exactly the condition the disaster grew
out of (§1.3 item 2: "no enforcement point, the whole thing can be skipped with
nothing raising an alarm").

## Two halves

- `check.sh <branch> --ruling <p> --evidence <p> --tree <c>` judges **one**
  change when the caller supplies the three answers, and refuses when any is
  absent or false. Evidence under `dc-warn` is refused by name: an untracked
  scratch path is how the disaster lost its evidence.
- `audit.sh` looks at the whole board and reports rows that changed status with
  no three-answer record.

## What the audit reports, and what it refuses to claim

`audit.sh` separates three populations, because a report that called every
historical row a violation would be ignored:

| population | meaning |
|---|---|
| answered | a timeline entry names all three answers |
| **violation** | a status-change entry exists, dated on/after `STATUS_SINCE`, with no three-answer entry |
| legacy | a status-change entry exists but predates `STATUS_SINCE` |
| unfalsifiable | the row has **no** status-change entry at all |

The last row is the honest one. The plugin does not write a status-change entry
for every path that can move a status, so the absence of such an entry is
evidence that the board does not record the change — **not** evidence that the
questions went unanswered. Counting those as violations would manufacture
findings.

## Measured on the real board (2026-10-01)

```
STATUS-AUDIT: 0 row(s) answered; 23 violate; 147 predate 2026-10-01 (legacy);
              177 carry no status-change entry (unfalsifiable)
```

An independent count of status-change entries dated on/after 2026-10-01 gives 24,
consistent with the 23 reported (one row carries two such entries).

**The first version of this audit reported 60 violations and was wrong.** It used
the maximum timestamp across a row's entries as the status-change time, so any
row merely commented on after section 3.4 took effect was reclassified as a
violation. The class of event is what matters, so the status-change event is now
matched explicitly by `type == "updated"` and a status-moving text. The wrong
number is recorded here rather than quietly replaced.

## Exit codes

Same fail-closed contract as `governance-sweep`: `0` none found, `1` findings
printed, `2` could not run (missing board, missing python3). No "0 findings"
output is ever produced on the failure path.
