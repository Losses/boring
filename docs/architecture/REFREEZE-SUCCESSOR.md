# P08 SUCCESSOR CANDIDATE — RE-FREEZE RECORD (R3.2)

> **状态勘误 (2026-10-02):** 本记录冻结于 2026-10-01，当时 RULING-137:32-35
> 禁令仍在生效。2026-10-02 `MANAGEMENT-RULING-RECOVERY-VIII.md`（commit
> `a0c1517b`）§3 已解除该禁令（condition 4 satisfied + later explicit ruling
> 两条件均已满足）。本记录中称该禁令「依然有效」的语句系冻结当时的准确记录，
> 现标为 **[当时记录]**。
>
> **边界明确（不将旧封存套新候选）：** 旧候选 `c8ae0054` = 永久 REJECTED
> （RULING-245 点 1/4，已封存）；新候选 `2ba5766b` = 尚无法判定（双独立复核
> 0/2，RULING-245 点 2 门槛未过），**非**永久 REJECT。P08 整体仍为
> `NOT PASSED`，但 `2ba5766b` 路径未封死。
> RULING-245 双独立复核门槛仍未满足 (0/2)；`P08-SUCCESSOR-DECLARATION.md`
> 仍为 DRAFT。

> **IDENTITY RECORD ONLY — NOT A DECLARATION, NOT A NOMINATION, NOT ACCEPTANCE.**
>
> 本记录冻结的是 P08 **后继候选**的一个可指 revision（身份对象），供 R3.3 的两份
> 独立复核瞄准同一棵树。本记录**不**提名、**不**宣称 P08 通过、**不**改任何 gate、
> 台账或看板状态；`docs/architecture/MANAGEMENT-RULING-137.md` 的常设禁令
> （condition 4 满足**且**有后续明示裁定之前：不得提名、不得宣称通过、不得改状态）
> **依然有效 [当时记录]**。P08 整体维持 `NOT PASSED / REJECTED, finally`（RULING-245）。

**Candidate revision: `2ba5766b`** — `merge: recov/r31-successor-declaration into
arch/agent-guided-governance`.

> **[SUPERSEDED LINE, RETAINED FOR AUDIT — the revision this seat first pinned was
> `649aa881` (`merge: recov/r34-governance-sweep into arch/agent-guided-governance`).
> The revision to review is `2ba5766b`; see the correction in §1 below.]**

**Frozen at:** 2026-10-01T17:30-04:00 (America/Toronto) — the wall-clock time this
seat performed the freeze, **not** the commit timestamp. For the avoidance of doubt,
the commits' own times are `2ba5766b` = `2026-10-01 17:24:18 -0400` and `649aa881` =
`2026-10-01 17:26:33 -0400`; both precede the freeze instant, as they must. A reader
comparing this line against `git show -s --format=%ci` will otherwise read the
25-second gap as a fabrication.

> **[AMENDED 2026-10-01 by the coordinator: this line read `649aa881` until the
> superseding correction in §1 landed. `649aa881` is a *later* HEAD than
> `2ba5766b` and carries R4.3 (`1e0d8169`), which
> `P08-SUCCESSOR-DECLARATION.md` §3 step 1 never covered. The line is corrected
> rather than deleted so the audit trail keeps both.]**

**What this record is:** an *identity* record, in the exact sense of the superseded
`docs/architecture/REFREEZE.md` (which froze the now-sealed predecessor `c8ae0054`).
It establishes one addressable revision so later independent reviews target a single
frozen tree instead of a moving line. Committing and freezing are not accepting
(`work-plan:93-94`).

**What this record is NOT:** it is **not** an acceptance gate, **not** a nomination,
and it **does not** finalise `docs/architecture/P08-SUCCESSOR-DECLARATION.md` (which
remains `DRAFT / PREPARATION ONLY / NOT YET DECLARED`). Nothing here accepts P08.

Provenance marks: **[MINE]** = I computed or executed it in this session (worktree
`dc-warn/worktrees/recov-r32`, branch `recov/r32-successor-refreeze`, base
`649aa881`); **[INHERITED]** = taken from a named retained source and labelled as such.

---

## 1. The frozen revision and its tree [MINE]

Pinned by `git rev-parse` in the freeze worktree; base given as `649aa881` (the main
line `arch/agent-guided-governance` at freeze time; local `649aa881` is an ancestor of
remote `b2f081bf`):

| revision | full hash | subject |
|---|---|---|
| **superseded pin** (formerly labelled candidate) | `649aa881ed6915ea906abf3b8902e3b730af60b9` | merge: recov/r34-governance-sweep into arch/agent-guided-governance |
| parent | `cf08733deb3a9a0e11aeac4c6f9a93bd84f1ffdd` | merge: recov/r43-vble-unblock into arch/agent-guided-governance |
| candidate tree | `22d73adee7adac64de660a9c85e3711495cf5893` | `649aa881^{tree}` |

> **[REVISED 2026-10-01 by the coordinator: the freeze point is `2ba5766b`, not
> `649aa881`.]** The reasoning below stands, but reason 3 misidentifies the point the
> declaration prescribes, and the difference matters for review.
>
> `P08-SUCCESSOR-DECLARATION.md` §3 step 1 says the freeze happens "在 R1/R2 落地后的
> HEAD 上" — the HEAD *after R1/R2 and the declaration land*. `649aa881` is a **later**
> HEAD: it also carries R4.3 (`1e0d8169`, "fix(rust,swift): unblock
> variable-bound-loop-eval native compile"), a same-day unrelated repair that landed
> after the declaration. Freezing `649aa881` asks a reviewer to certify a revision
> containing work the declaration never covered.
>
> `2ba5766b` ("merge: recov/r31-successor-declaration into
> arch/agent-guided-governance") is exactly the prescribed point — R1, R2 and the
> declaration, and **no** R4.3:
>
> Full hash `2ba5766b4d241139a99757fd12f45f07b4234c94`; tree
> `b54997ce12a2c17496a8c60c60550bdcff4aa729` (`git rev-parse 2ba5766b^{tree}`).
> These are the bytes a reviewer certifies. The table above records the earlier
> pinning point and is retained for audit.
>
> ```
> cd70eb12 (S1)   is-ancestor of 2ba5766b -> rc=0
> 71a60c7d (S2)   is-ancestor of 2ba5766b -> rc=0
> 449444cf (S3)   is-ancestor of 2ba5766b -> rc=0
> c8ae0054        is-ancestor of 2ba5766b -> rc=0
> 1e0d8169 (R4.3) is-ancestor of 2ba5766b -> rc=1   (absent, as intended)
> ```
>
> The scope caveat below shrinks accordingly but does not vanish: `SwiftExpr.hx` at
> `2ba5766b` still differs from `c8ae0054` by **230 insertions / 15 deletions**, because
> unrelated Swift-backend work entered the line before the declaration too. Neither
> number is a defect in the successor; both are facts a reviewer must see. **The
> revision to review is `2ba5766b`.** The row above records what this seat pinned; it is
> left in place rather than rewritten, so the correction is auditable.

**Why this revision, and why not the alternatives:**

1. **An immutable, already-pushed hash.** The freeze must name a hash, not a ref. The
   main line has already advanced past `649aa881` (remote HEAD is `b2f081bf`, with
   `649aa881` verified as its ancestor: `git merge-base --is-ancestor 649aa881
   origin/arch/agent-guided-governance` → rc=0). Naming the hash makes the record
   immune to that forward drift; naming a branch would not.
2. **All required content is present as ancestors** (§2 below: `c8ae0054`, S1, S2, S3
   all rc=0 against `649aa881`).
3. **It is the point R3.1's own declaration prescribes.** `P08-SUCCESSOR-DECLARATION.md`
   §3 step 1 says the freeze happens "在 R1/R2 落地后的 HEAD 上"; R1, R2 and the R3.1
   declaration merge (`2ba5766b`) have all landed by `649aa881`.
4. **Rejected alternatives.** *"An existing commit containing the three components"*:
   the successor is not a single atomic commit — it is a lineage (`c8ae0054` + S1 + S2 +
   S3), each component a separate commit that entered the line separately, so no single
   pre-existing commit *is* the candidate; every line tip after the last component is an
   equally-arbitrary "contains them" point, and `649aa881` is the canonical one after
   recovery. *"A new empty commit holding only the record"*: it would have to name its
   own hash in its own tree (a self-reference that cannot be produced without
   `--amend`, which this seat is barred from), and it would not remove the unrelated
   line content anyway; the record correctly lives *outside* the frozen revision, exactly
   as `REFREEZE.md` lives outside `c8ae0054`.

**Scope caveat, recorded as fact, not adjudicated [MINE; numbers recomputed at
`2ba5766b`].** Two scopes must be told apart, and an earlier draft of this paragraph
mixed them together:

1. **The candidate's own component.** `SwiftExpr.hx` at `2ba5766b` differs from the
   sealed `c8ae0054` by **230 insertions / 15 deletions** (`git diff --shortstat
   c8ae0054 2ba5766b -- packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx`).
   The number **246**, which stood here before, belongs to the earlier pinning point
   `649aa881` and is superseded.
2. **The whole revision under review.** The aggregate `c8ae0054..2ba5766b` is
   **671 files / +94669 / −2527**. A reviewer certifying `2ba5766b` certifies this
   aggregate and must see it; the three successor components explain only part of it.

The additional body of work entered the line through origin/master syncs
(`aceda352`), the cross-target driver (`011dd739`, `f0a31387`) and other Swift-backend
repairs. **R4.3 (`1e0d8169`) is not among them**: `git merge-base --is-ancestor
1e0d8169 2ba5766b` gives rc=1, so that commit is absent from the revision under review
and must not be listed as one of its causes. This record pins *the bytes at
`2ba5766b`* as the review target. Whether that scope is the correct successor candidate
content is a **reviewer / management question (R3.3)**, not this seat's to decide; this
record neither affirms nor rejects it.

---

## 2. Ancestry verification at the superseded pin `649aa881` [MINE, `git merge-base --is-ancestor <sha> 649aa881`]

Each line shows the true exit code (`$?`), confirmed one by one (not via a piped tail):

| component | revision | full hash | rc |
|---|---|---|---|
| sealed predecessor lineage base | `c8ae0054` | `c8ae0054d8b1937cf05c0dd849c268807ae19b8f` | **0** |
| S1 — do not emit statements after one that diverges | `cd70eb12` | `cd70eb127895ecdb6c38aeb4b3b45fd70182ded2` | **0** |
| S2 — switch-expression closures lower against owning destination | `71a60c7d` | `71a60c7d3055dbe474bf634cd54681601fdf7073` | **0** |
| S3 — destination conversion on single-statement lambda fast path | `449444cf` | `449444cf02bb0168e3370b7baae14ceb3ed5ee04` | **0** |
| S4 — fixture automated `-c` assertion (Review 2 acceptance-naming) | `d14231a6` | `d14231a6211a1903bd7a7f67a6297db1d24d7709` | **0** |

`git merge-base --is-ancestor` output is silent on success; the rc is the only signal,
and it is 0 for every row. (For the record: the piped-`tail` trap does not apply — these
rcs were read directly.)

---

## 3. File identities at the revision under review [MINE at `649aa881`; table recomputed
by repair seat D4 at `2ba5766b`, `git show 2ba5766b:<path> | sha256sum`]

Reviewers must target **these bytes**; any byte drift means the wrong tree is under
review.

| file | sha256 | bytes |
|---|---|---|
| `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` | `a736c7376287c267c6f77ef3abd056dae4ec443ad137c06261d342af7de48631` | 344718 |
| `tests/swift-gap-boundary/gap-boundary.test.ts` | `c0da2ddce29e25d30e10a4185660c80a1c080a50ac9abb1333dd065559220f02` | 10574 |
| `tests/swift-gap-boundary/gap/Gap.hx` | `150315585b0a4aee5df5d1f9f24e217a2c5f747717aa6161eb1032769b057048` | 4197 |
| `tests/swift-gap-boundary/swift.hxml` | `87be97b5393eea5bbba9b87d0082c6378c282bc6153b304e047418798fdc7800` | 646 |

The two fixture inputs `Gap.hx` and `swift.hxml` are **byte-identical to the sealed
`c8ae0054`** (same sha256 as recorded in `REFREEZE.md` §1) — the successor changed the
compiler (`SwiftExpr.hx`) and the fixture's own `-c` assertion
(`gap-boundary.test.ts`), not the counterexample input. `SwiftExpr.hx` at `c8ae0054`
hashed `22fd243c…` per `REFREEZE.md`; the successor's `SwiftExpr.hx` carries the S1
`stmtDiverges` fast path (line ~1484), the S2 `switchBindingLines` destination pass
(line ~5741) and the S3 `functionLiteralInner` conversion (line ~2506), plus the §1
scope-caveat changes.

> **[D4 — table recomputed 2026-10-01, freeze point revised to `2ba5766b`.]**
> This table was originally indexed at `649aa881`. The coordinator revised the freeze
> point to `2ba5766b` (see the §1 REVISED block above) because `649aa881` also
> carries R4.3 (`1e0d8169`), a same-day unrelated repair that landed after the
> declaration and was never covered by it — freezing at `649aa881` would ask a
> reviewer to certify work outside the declaration's scope. The three fixture files
> (`gap-boundary.test.ts`, `Gap.hx`, `swift.hxml`) are byte-identical across the two
> revisions, so their rows are unchanged. `SwiftExpr.hx` alone differs and has been
> recomputed:
> ```
> 原值 (649aa881): sha256=33e8f6a9f4d8bbee…  size=345439
> 新值 (2ba5766b): sha256=a736c7376287c267…  size=344718
> ```
> Independent recomputation confirmed by repair seat D4.

---

## 4. Boundary declaration — what this record does and does NOT do

1. **This is an identity / identity record, not an acceptance.** It establishes *which
   tree* the successor candidate is, so R3.3 reviews target one addressable revision.
2. **No nomination.** The successor remains `PREPARABLE / NOT NOMINATE-ABLE`.
3. **No declaration of a pass.** P08 stays `NOT PASSED / REJECTED, finally`.
4. **No gate, ledger or board state change.** `GATE-LEDGER.md`, the board rows and
   `MANAGEMENT-RULING-137.md` are all untouched by this record.
5. **RULING-137's standing prohibition remains in force [当时记录]**: until condition 4 is
   satisfied *and* a later explicit ruling says otherwise — do not nominate, do not
   declare a pass, do not change status. This freeze changes none of that; it is the
   "preparation" RULING-137's minimum action permits, in the identity-recording sense
   RULING-245 point 1 preserves ("recording state").

---

## 5. Relationship to the existing `REFREEZE.md` [MINE]

`REFREEZE.md` freezes the **old** candidate `c8ae0054` and is now headed by a
supersession note marking that candidate sealed/REJECTED. That record is **historical
and not deleted or rewritten**. This new record is a **separate file**
(`docs/architecture/REFREEZE-SUCCESSOR.md`), and a one-line pointer is prepended to
`REFREEZE.md`'s supersession block so a reader landing on the old record is routed
forward. The two records are disjoint: the old one names `c8ae0054`, this one names
`2ba5766b`; neither invalidates the other, and the old record's frozen tree remains
addressable for anyone who needs the sealed candidate's history.

---

## 6. Honest limits — what this freeze does NOT establish

1. **No acceptance, no nomination, no status change** (§4).
2. **No `swiftc -c -WMO` re-measurement here.** The successor's zero-diagnostic claim
   is the R3.3 reviewers' job; this record only pins the bytes. The independent R3.3-a
   review (`audit-reports/r33-review-a-2026-10-01.md`; out-of-repo note, 2026-10-01: this path lives in the workspace at `/home/losses/Development/tq-workspace/audit-reports/`, outside the boring repository) already CONFIRMED the diagnostic
   count = 0 at a line containing the components, and I do not re-adjudicate it.
3. **Scope of the frozen `SwiftExpr.hx` is wider than the three successor components**
   (§1 scope caveat). Whether that is the correct successor content is for reviewers /
   management to decide; I record the fact without ruling on it.
4. **`P08-SUCCESSOR-DECLARATION.md` remains DRAFT.** Finalising it is not this seat's
   action, and this record does not do it.
5. **Toolchain-independent.** This is an identity record; it runs no build, so it makes
   no toolchain or runtime claim beyond the byte hashes above.
