# Root-floor sign-off review — the 14 disaster-carried entries

`tools/roots-guard/roots-baseline.txt` carries 14 entries annotated (`:5-9`) as
having entered the tree through the unreviewed disaster merge `7b4aaf8b`. The
annotation says they are "Pinned here for fact-tracking only; a deliberate
removal or a sign-off review is deferred to the next planned baseline refresh".
This record answers what "missing sign-off" actually means for them and what
each entry's disposition is, so a later reader does not have to re-derive it.

## What is missing is the decision, not a field and not a document

Three readings were possible and only one holds:

- **not a missing field** — the file format admits exactly `target<TAB>module`;
  any extra field makes the guard FAIL. There is nowhere to put a per-entry
  sign-off, by design.
- **not a missing document** — the 19-line provenance annotation is present, and
  the `r54r` review record is present.
- **the missing thing is the decision itself** — a per-entry keep/remove review
  at sign-off grade. That is what the annotation defers, and what this record
  resolves.

## The set is exactly 14, and the count is closed

Located by baseline line number:

| module family | kotlin lines | swift lines |
|---|---|---|
| `NullBoolEmphasisOps` | 170 | 1300 |
| `NullBoolStyle` | 171 | 1301 |
| `NullBoolTernaryOps` | 172 | 1302 |
| `NullInflatedLiteralOps` | — | 1307 |
| `TestLitEdgeOps` | 267 | 1392 |
| `tests.NullBoolTernaryTests` | 464 | 1589 |
| `tests.NullInflatedLiteralOpsTests` | — | 1593 |
| `tests.TestLitEdgeTests` | 562 | 1687 |

Method: against `7b4aaf8b^1` (`c037054e`), each module × hxml was counted and
**exactly 14** entries had no target-pair before that merge; the rust pair set
was unchanged by it (all 10 new rust-f32 modules were already in `rust.hxml`),
so there is no fifteenth entry.

The annotation is **19 lines** for **14 entries** — a line/entry arithmetic
difference (12 non-entry lines: 8 header + 2 blank + 1 "Via" + 1 closing, plus 7
entry lines carrying 14 entries across 3- and 4-line wraps). It is **not** 5
omitted entries. The account closes: 42 added pins = 14 disaster-carried + 20
pre-existing + 8 mirrors added by `26eb98fd` itself.

## Disposition: all 14 retained, with the annotation

Every entry was checked, not accepted on the annotation's word:

- all eight `.hx` files exist in the tree;
- all 14 still root on both sides;
- the six `tests.*` entries are **forced** by guard rule 4 — removing them makes
  the guard red by construction;
- the eight `boring.*` entries are imported or called by `@:test` modules.

So removal has no benefit and a guaranteed cost. **No entry is deleted and none
needs a human adjudication on content.** The formal keep decision still lands
with the baseline refresh coordinated through the workspace board, which is what
the annotation already says.

Not done, and stated rather than implied: **no binary32 behavioural
verification** was performed on these entries.

## Guard state at review time

```
roots guard: PASS (3 exemption(s) in force; 6 declared unrooted @:test module(s);
                   0 duplicate root line(s) reported; 1692 pinned root(s) in root-floor)
```

Exit code 0. The script was read before running and confirmed read-only against
the repository (intermediates go to a `/tmp` mktemp); `git status --porcelain`
was identical before and after.

## What this changes

Nothing in the guard's behaviour, and no status anywhere. This is the
sign-off-grade record the annotation deferred, so the deferral now has a
documented resolution instead of an open question.
