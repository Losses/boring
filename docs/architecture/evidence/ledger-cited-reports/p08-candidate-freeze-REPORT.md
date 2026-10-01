# REPORT — P08 candidate freeze record: what I did, and what I could not do

Deliverables in this directory:

- `FREEZE.md` — the freeze record itself (the record the P08 gate needs).
- `REPORT.md` — this file: method, limits, and the short version of the findings.
- `evidence/` — raw hash listings, the patch application logs, and my own execution logs.

**Nothing was modified.** The coordination tree, `INTEGRATION.diff`, `MANIFEST.md`,
`REPORT.md`, every fixture, and every test were read only. All patch application and all
fixture generation happened in `/tmp/p08-freeze/` and `/tmp/p08-freeze/coord-copy`,
`/tmp/p08-freeze/verify-apply`. Writes under `dc-warn/` are confined to this output directory.
Post-run, the coordination tree's `SwiftExpr.hx` still hashes
`0a9bed91ef91ca68b75a2e7e4e2482d2743a16fe5caf4150018686c2131e33f0` and its
`git status --porcelain` is byte-identical to the listing captured by the behaviour review
at 02:16 — i.e. the tree did not move under me.

## 1. Method

1. **Read the objects first.** `INTEGRATION.diff` (all 175 lines), `MANIFEST.md`, `REPORT.md`,
   the three consultation answers, the behaviour review, the route-fixture reports and
   cross-check, the branch-expectation ruling, the armLines-separability report, and the gap
   archive. Nothing was accepted from a manifest on its own authority.
2. **Recomputed every identity** with `sha256sum`, `git rev-parse`, `git status --porcelain`,
   `cmp` and `diff -rq` — including the claim that the patch touches one file (checked by
   reading the diff, not by reading the manifest).
3. **Reproduced the patch application** in a fresh `/tmp` copy of the coordination tree and
   captured `patch`'s exit codes **directly** (never through a pipe), then `cmp`-ed the result
   against the verified worktree.
4. **Re-executed the verification** myself rather than quoting it: the interpreter oracle, both
   focused fixture generations, both `swiftc -typecheck` runs, the acceptance build and run
   compared line-for-line against the oracle, and — new — the three discriminating route
   fixtures against the candidate (they had only ever been measured pre-patch).
5. **Pinned the governing record and the toolchain**, and discovered both a drift and a
   contradiction that change what the gate can currently claim.

## 2. What I found (short version)

**Green — the freezing half is done.**

- The patch touches exactly **one** file; `INTEGRATION.diff` applied to a fresh coordination
  copy gives `patch` rc **0** (dry-run 0, apply 0) and reproduces the verified worktree's
  `SwiftExpr.hx` **byte-for-byte** (`cmp` rc 0), and the whole 5440-file tree matches it with
  exactly one differing file.
- Base `SwiftExpr.hx` `0a9bed91…` → candidate `bf7dde2c…`; coordination HEAD `e1c65975…`,
  **dirty, 25 entries (15 M + 10 ??)**.
- Whole-tree content anchors: coordination `986807b2…`, candidate `b75c8c0f…`.

**Green — new evidence I produced.**

- The three route-discriminating fixtures c1/c2/c3, which the author and an independent
  cross-check both measured **RED** pre-patch (4 / 2 / 2 swiftc errors), are **GREEN** on the
  candidate: `gen rc=0`, `swiftc -typecheck rc=0`, **0 errors / 0 warnings** for all three.
  Only the `*Ops.swift` files changed; the `*Oracle.swift` files are unchanged.
- The acceptance fixture on the candidate: generation rc=0, typecheck rc=0 with **empty
  stderr**, build rc=0, run rc=0, and **30/30 lines identical to the interpreter oracle**.

**Red / partial — the acceptance half is not there yet.**

1. **Obligation 1 is not verified by its designated reviewer.** The implementation review has
   produced no report (5 of 8 checklist items open; scratch logs only, still being written at
   03:54). And the obligation's own "in-scope reconstruction is removed" is falsified by the
   patch text: `switchAssign` still rewrites printed `return ` lines.
2. **Obligation 2 fails its literal wording.** "Zero diagnostics" holds for the acceptance
   fixture but **not** for the counterexample fixture, which still emits **2 warnings**
   (`Gap.swift:113/115`, the pre-existing `switchExplicitReturn` swallowed-`return` defect).
   I verified that whole function is byte-identical base vs candidate, so the patch neither
   causes nor fixes it — but the obligation is stated over the candidate *inputs*.
3. **Obligation 3's "execution distinguish both branches" is not testable with the fixture.**
   Both branches produce the identical observable `1:present`; the tracked expectation
   (`1:1` / `2:1`) is simply wrong, so the collecting test dies at the oracle step.
4. **The governing acceptance record drifted after the first review was written**
   (367 lines / `4d348992…` → 390 lines / `9886fe25…`, rewritten 03:06). The two reviews
   therefore cannot currently be said to cite the same record.
5. **A contradiction the gate must rule on:** the candidate converts a cell that
   `RECORD.md:58` still declares **REFUSED**, via the SW04 override
   `lowerArrayBoundary(nilMerge.target, target, null, true)` — with no record row for the
   override and no correction. It is probably *right* (it is what makes the nil-merge
   composition legal), but it is unruled.

## 3. What I could not do, and why

| # | not done | blocker |
|---|---|---|
| 1 | Run the full `bun test tests/` suite | Known `tests/ts/package-artifacts.test.ts` trap hollows the tracked `samples/boring/MathNaNTestSupport.hx`; broad unrelated surface. Not run by any report either. |
| 2 | Run `bun test tests/swift-readonly-boundary/` | It **cannot** pass as it stands: it exits 1 at its oracle step on the `branch-*` expectation. I reproduced the mismatch instead (oracle prints `1:present`). |
| 3 | Re-run the route-fixture **negative** controls | Out of the time box; the positives were the open question. Negatives remain quoted green from `readings.tsv` / the x-check. |
| 4 | Rebuild Kotlin / Rust / TS / Dart | The patch touches no non-Swift file and the whole-tree delta is exactly one Swift file, but I ran no other-target generation or build. |
| 5 | Run the compiler's own unit/self tests | Not attempted; out of scope for an identity-pinning task and not run by the retained reports either. |
| 6 | Produce a report for the second (implementation) review | Not mine to produce. It is a separate reviewer's deliverable and was in flight while I worked. |
| 7 | Execute the gap fixture (not just typecheck) | The campaign has no runtime collector for it; building a runner would be new work beyond freezing, and its control-exit shape is the known W1 defect. |
| 8 | Obtain the candidate-generated `Gap.swift` as a **retained** artifact | No such artifact exists anywhere; I generated and hashed it myself (`2be5e102…`) but it survives only in my `/tmp` tree. |
| 9 | Pin `RECORD.md` at the revision the behaviour review cites | Impossible: that revision no longer exists at that path. I could only record the drift chain. |

## 4. Limits of the bundle hash

`FREEZE-BUNDLE = b664c91cd09ba6b80517e809feca90a7995f68b84b81589126fed525da1a3878` is a hash
of `evidence/06-freeze-manifest.sha256` (47 entries, sorted, documented in `FREEZE.md` §6).
It is **my construction**, not a pre-existing project artifact — the recipe is given so it can
be recomputed or replaced by the gate with its own. It pins identity, not acceptance. It hashes
a *dirty working tree*; any further edit inside `boring-wt-architecture` invalidates it.

## 5. If the gate wants to move

The two cheapest actions that would change the verdicts:

1. **Resolve the `branch-*` expectation** (the ruling already supplies `CANDIDATE.diff`). That
   turns obligation 3's collector from red to runnable — but note it still will not distinguish
   the branches, so the obligation needs a fixture whose two branches are observationally
   different, not just a corrected number.
2. **Land the implementation review and rule on the SW04 override.** Those two unblock
   obligation 1 and settle §4.3 of the freeze record.

Obligation 2 will not become "sufficient" without a decision on the two W1 warnings: either
fix the swallowed-`return` defect, or amend the obligation to "zero *errors*" and record the
warning policy — the consultation explicitly warns that "a 'zero errors' policy without a
warning policy would miss" exactly this shape.
