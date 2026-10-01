# P08 successor candidate — PREPARABLE, NOT NOMINATE-ABLE

**Status marking: PREPARABLE, NOT NOMINATE-ABLE.**

This record prepares material for a possible FUTURE P08 candidate. It does not
nominate any candidate, does not freeze anything, does not declare anything
passed, and does not change the status of `c8ae0054`, which remains
**P08 NOT PASSED / REJECTED, finally**, sealed by the round-245 management
ruling (`docs/architecture/MANAGEMENT-RULING-245.md`). Nothing in this record
reopens, patches, reinterprets or re-reviews that candidate, and its rejection
is not lifted by anything written here. A nomination requires a further
explicit ruling.

Why this directory (`docs/architecture/p08-candidate-material/`): the material
is expected to grow (a future candidate would add its own re-freeze record and
review pointers beside this one), so it gets a directory of its own rather than
a single file in the flat architecture directory, and it must not be confused
with the governing documents it cites.

Labels: `[EXEC]` executed/measured here; `[CODE]` read from source/commits;
`[DOC]` a named document asserts it; `[UNVERIFIED]` not established.

---

## 1. Governing ground — what the two reviews actually required

Grounded **only** in the two rejections and the sealed rulings; nothing here is
invented.

### Review 1 (`dc-warn/out/p08-review-1/REPORT.md`, VERDICT REJECT) — four exact conditions

1. Obligation 2: `swiftc -c -whole-module-optimization` emits exactly one
   diagnostic (`gap/Gap.swift:117:9: warning: will never be executed`); zero
   required (`02-translator-implementation-standard.md:78/:80`). Clear it
   (W1's unreachable trailing `return`) — the gate-owner-ruling alternative was
   already ruled against. Ancillary: the repo's own collector cannot gate this
   until a `swiftc -c` step is on the frozen revision.
2. Obligation 1: `switchExpression` must take its destination from its owning
   composition (`v.t` from `switchBindingLines`, the callee parameter on the
   argument route), committed and re-frozen.
3. Obligation 1: the lambda single-statement fast path
   (`functionLiteralInner:2372`) drops the boundary conversion — measured
   counterexample, `swiftc -c -WMO` rc=1. Required: apply the conversion on
   that path or prove the shape unreachable.
4. Ledger correction (P08-3 laziness) — already discharged.

### Review 2 (`dc-warn/out/p08-review-2/REPORT.md`, VERDICT REJECT, independent) — one in-scope condition

1. Zero build-phase diagnostics is not met — same `Gap.swift:117:9` warning.
   Discharge by (a) clearing the unreachable trailing `return` **and
   re-freezing**, or (b) a written gate-owner ruling (foreclosed). An
   acceptance of any successor must name: the revision hash, the measured
   `swiftc -c -WMO` diagnostic count of **0**, and the revision on which the
   fixture's own automated `-c` assertion exists and passes.

Round-245 ruling points binding on any successor: a fix that changes generated
text is a change of candidate content (point 2); the lambda fast-path defect
exists in `c8ae0054`, so its repair belongs to the successor (point 3); if both
repairs are kept they belong in **one** clearly identified new candidate frozen
together (point 3); `449444cf` must never be cited as evidence that `c8ae0054`
was repaired, and any re-freeze must name a revision that includes it
(consequence note).

## 2. Change scope — what a successor candidate would have to carry

Every row backed by `git log`/`git show`/`git merge-base --is-ancestor` in this
worktree (`prep/p08-candidate-material` @ `5a8f19e6`); raw output in
`dc-warn/out/p08-prep/evidence/01-provenance-pins.txt` `[EXEC]`.

| # | Change a successor must carry | Driven by | Commit | On the line (ancestor of `prep` HEAD `5a8f19e6`)? | Provenance |
|---|---|---|---|---|---|
| S1 | Clear the unreachable trailing `return` so `swiftc -c -WMO` diagnostic count at `Gap.swift:117` is **0** — without changing run semantics | Review 1 cond. 1; Review 2 cond. 1; Ruling-245 point 2 | **none exists** — the `w2-diagnostic-fix` work was ordered stopped and sealed with no hash (`GATE-LEDGER.md:189-190` records it as abandoned, never delivered) | **NO — not on the line** `[EXEC]`: the only two commits touching `SwiftExpr.hx` after `c8ae0054` are `71a60c7d` and `449444cf`, neither addresses the trailing return; `git log --all --grep` finds no such fix | `[CODE]` |
| S2 | `switchExpression` destination from the owning composition (`switchExpression(sw, destination)`, `v.t` from `switchBindingLines`, callee parameter on the argument route) | Review 1 cond. 2; GATE-LEDGER P08-1 correction | `71a60c7d` — "fix(swift): switch-expression closures lower against the owning destination contract" (`SwiftExpr.hx`, +48/−10) | **YES** `[EXEC]` `git merge-base --is-ancestor` | `[EXEC]` |
| S3 | Boundary conversion applied on the lambda single-statement fast path (`functionLiteralInner`) | Review 1 cond. 3; Ruling-245 point 3 | `449444cf` — "fix(swift): apply destination conversion on the single-statement lambda fast path" (`SwiftExpr.hx`, +21/−2) | **YES** `[EXEC]` | `[EXEC]` |
| S4 | Fixture carries a working automated `swiftc -c` assertion (the collector must be able to gate the zero-diagnostic criterion) | Review 1 cond. 1 ancillary; Review 2's acceptance-naming requirement | `d14231a6` — "fix(test): make gap-boundary swiftc -c invocation valid and assert its outcome" (`gap-boundary.test.ts`, +41/−2) | **YES** `[EXEC]` | `[EXEC]` |

**Key finding, stated plainly:** Review 1 condition 1 and Review 2 condition 1
(the sole in-scope ground of the sealing rejection) **cannot be met by the
changes now on the line.** The one change that would clear `Gap.swift:117`
does not exist as any commit; its work was stopped and sealed by Ruling-245
point 4. A successor candidate is therefore not assemble-able from the line
alone: S1 must be newly written, and under Ruling-245 point 2 any such fix
creates candidate content and mandates a new freeze plus both independent
reviews again. `[CODE]`

Mechanical integrity of the commits named above `[EXEC]`, via
`bun run gate:verify -- <commit-ish> --json <path>` (R2/R3 evidence: full
archive export re-hashed, verdict PASS, exit 0; JSON in
`dc-warn/out/p08-prep/evidence/`):

| commit | files hashed | mismatches | verdict |
|---|---|---|---|
| `c8ae0054` (sealed; run for the record only — no status change) | 1451 | 0 | PASS |
| `449444cf` (S3) | 1453 | 0 | PASS |
| `eec707b9` (see §5) | 1455 | 0 | PASS |

## 3. Verification checklist — what a successor would have to demonstrate

One line per item; each independently checkable. None of these has been run
for a successor, because no successor exists or is being nominated.

1. **Re-freeze**: a re-freeze record names one new revision hash (containing S1+S2+S3 on top of the sealed candidate's line, or their equivalent), its tree, and the byte-identities of every file a review must target — identity only, not acceptance (`REFREEZE.md` pattern).
2. **`swiftc -c -WMO` = 0**: on the frozen successor's own counterexample inputs, `swiftc -c -whole-module-optimization` over the four generated files reports **exactly 0 diagnostics** (Review 2's counting method: `: warning:` / `: error:` lines, not caret substrings); the raw stderr retained.
3. **`-typecheck` trap named, not substituted**: `-typecheck` cleanliness is recorded as the known false-pass and is not offered as the criterion (Review 1 §2.3, Review 2 §2).
4. **Plain `-c -o` trap avoided**: the multi-file `swiftc -c … -o` invocation (rc=1, `cannot specify -o when generating multiple output files`) is not the form measured.
5. **Fixture's automated `-c` assertion passes on the frozen revision** and fails on a deliberately injected warning (both directions demonstrated — Review 2's "exists and passes" plus Review 1's false-negative lesson).
6. **Lambda fast-path counterexample cleared**: a single-return lambda at a read-only-array destination (`P-LAM-SINGLE` shape) compiles under `swiftc -c -WMO` with 0 diagnostics (Review 1 cond. 3's measured counterexample, re-run at the successor).
7. **`switchExpression` destination on the frozen bytes**: the frozen `SwiftExpr.hx` contains the explicit-destination form and `switchBindingLines` passes `v.t` (Review 1 cond. 2), verified against the pinned blob, not a worktree.
8. **Two independent reviews, same hash**: two separately recorded reviews both cite the successor's exact revision hash (board criterion ⑤'s same-hash requirement, now with acceptance as the goal).
9. **Review independence**: neither reviewer participated in producing the candidate or its freeze; at least one works from an independent `git archive` export, as Review 2 did; prior reviews are inputs, never acceptance evidence.
10. **Entry gate on every status claim**: traceable hash, clean-tree proof, independently exported content/checksums (`gate:verify` PASS), and a claim-versus-commit consistency check by executor and reviewer (`GATE-LEDGER.md` entry gate, four requirements).
11. **No regression on the repaired W1 behaviour**: the explicit-return case still yields the single-element result (`.two` = `[3]`-shape, not `[1,2]`) and branch/laziness/single-evaluation readings stay byte-identical to the Haxe oracle on the routes review-1 probed.
12. **Ledger accuracy**: no row credits `c8ae0054` with successor bytes, and no row credits the successor with anything not on its frozen hash (the lesson of review-1's ledger correction and review-2 §4).

## 4. Residual scope — what this preparation does NOT cover

1. **No successor exists.** Nothing is frozen, nominated, named as a candidate, or declared ready/verified/acceptable. S1 does not exist as code and this record does not design or write it.
2. **`c8ae0054` status unchanged**: NOT PASSED / REJECTED, sealed. No new P08 review opened; nothing re-measured to dispute the rejection (the `gate:verify` run on `c8ae0054` is integrity evidence for the record, not a re-review).
3. **No implementation and no tests were added** by this preparation task (this record and its evidence are the only artifacts; the worktree carries no source change).
4. **Other obligations and rows** (P08-1 destination-owner structural enforcement, in-scope reconstruction's remaining derivation sites, P08-3's unprobed laziness routes, P09/P10/P12) are out of scope; they belong to their own seats and rulings.
5. **Other targets, toolchains, flag sets** (Kotlin/Rust/TS/Dart; Swift versions ≠ 6.2.4) unverified, per the reviews' own not-verified lists.
6. **The 11-family × position matrix** and board criteria ②/③/④/⑥ at a successor are not addressed here; this record only lists what the reviews required.

## 5. Condition 4 (contract-3 restoration) — mechanical entry-gate evidence completed `[EXEC]`

The one item the round-245 permission explicitly allows ("complete/verify
condition 4"): ledger condition 4 (`eec707b9`, the `package-shell.test.ts:249`
stale-expectation fix) had its technical claims independently CONFIRMED, but
its entry failed the ledger entry gate on requirements 2 and 3 (clean-tree
proof and independently exported content). Both are now produced mechanically:
`bun run gate:verify -- eec707b9 --json` = archive-export of the full tree,
1455 files re-hashed, **0 mismatches, verdict PASS, exit 0**
(`dc-warn/out/p08-prep/evidence/gate-verify-eec707b9.json`). This satisfies the
gate's stated production method for requirements 2 and 3 (the clean live
worktree is never an input). It changes no verdict recorded in the ledger; it
completes the evidence form the gate requires.

---
*Prepared on branch `prep/p08-candidate-material` in an isolated worktree;
shared tree untouched; fixture trap intact (`grep -c 'Test.equals'
samples/boring/MathNaNTestSupport.hx` = 5 before and after) `[EXEC]`.*
