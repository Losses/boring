# P09 criterion 1 — independent recheck of the `18d44ec1` correction

Task: `audit/p09-criterion1-recheck`. Rechecker is not the author of the correction; the author
does not self-certify. All claims below are re-measured from the artifacts; nothing is accepted
because the correction says it.

- Repo (read-only): `/home/losses/Development/tq-workspace/boring-wt-architecture`
  (a **linked worktree** of `/home/losses/Development/tq-workspace/boring`: `git rev-parse
  --git-common-dir` = `/home/losses/Development/tq-workspace/boring/.git`).
- No branch was switched, no repo file written except this report.
- **The shared tree was NOT on the base branch during this recheck.** `git rev-parse
  --abbrev-ref HEAD` = `audit/l4-fixture-collection-coverage`, `HEAD` = `5544570`. Every
  measurement below therefore addresses **ref names**, never `HEAD`, except where `HEAD` is the
  object under test.
- Head of the artifact under review: `18d44ec1` (`ci/collected-suite-failure-attribution`), plus
  its follow-up `696acd93` (per the dispatcher's supplement). Both are **local-only** (§2.5).

## 0. Verdict summary

| # | Assertion in `18d44ec1` (as amended by `696acd93`) | Verdict |
|---|---|---|
| 1 | the three are not mutually exclusive but three sequential points on one line, all ancestors of base | **ancestry/order CONFIRMED; the inference "hence not a choice" REFUTED** |
| 2 | order `2159c657` → `e1c65975` → `0a5c42a7`, 9 commits apart | **CONFIRMED** (reproduces exactly) |
| 3 | base leads `0a5c42a7` by 124 (local) / 167 (remote) | **both numbers CONFIRMED; the bare "124" is misleading if quoted alone** |
| 4 | the real blocker is the moving ground, not an un-made three-way decision | **REFUTED as stated** — the source says both, and explicitly says a decider must decide |
| 5 | `304ed70c` not an ancestor of HEAD, `rev-list` = 150; P09's halves pinned to divergent lineages | **150 reproduces only against `0a5c42a7`; "divergent" REFUTED on the remote base** |

Nothing in the recheck required me to decide which revision to pin (non-goal), to run the P09
matrix (non-goal), or to rewrite the correction's wording (non-goal).

## 1. Criterion 1 — ancestry, order, and the leap from "ancestor" to "not a choice"

### 1.1 Raw measurements (first-hand)

```
$ git rev-parse 2159c657 e1c65975 0a5c42a7 304ed70c
2159c657dcca870950b7bd43aa6e09a21d7cee30
e1c6597514634fd347d392709793cc19bd96c9a2
0a5c42a702d938ca4da39cbcefae2cc450e021fe
304ed70c4ba09fe21edadcca4c85f963fd692927

$ git merge-base --is-ancestor <c> arch/agent-guided-governance   # local base 0641991b
2159c657 YES   e1c65975 YES   0a5c42a7 YES   304ed70c NO

$ git merge-base --is-ancestor <c> origin/arch/agent-guided-governance   # remote base 372c42a6
2159c657 YES   e1c65975 YES   0a5c42a7 YES   304ed70c YES

$ git rev-list --count 2159c657..e1c65975   -> 8
$ git rev-list --count e1c65975..0a5c42a7   -> 1
$ git rev-list --count 2159c657..0a5c42a7   -> 9
$ git rev-list --count e1c65975..2159c657   -> 0     (so 2159c657 is an ancestor of e1c65975)
$ git rev-list --count 0a5c42a7..e1c65975   -> 0     (so e1c65975 is an ancestor of 0a5c42a7)
$ git log -1 --format='%H parents=%P' 0a5c42a7
0a5c42a702d938ca4da39cbcefae2cc450e021fe parents=e1c6597514634fd347d392709793cc19bd96c9a2
```

**Ancestry half: CONFIRMED, and it survives the hostile case.** I tried to break it three ways:

- *"maybe one of them is only a tag or lives on another branch"* — no. All three are ancestors of
  **both** the local base and the remote base; the ancestor test is ref-addressed, so it is
  independent of what the shared tree is checked out to.
- *"maybe base was rebased, so the ancestry is an artifact of the current ref"* — refuted for
  these three. `git merge-base --is-ancestor arch/agent-guided-governance
  origin/arch/agent-guided-governance` = **YES** and `rev-list --count origin..local` = **0**:
  the local base is a strict *ancestor* of the remote base, i.e. forward-only, no rewrite. A
  rebase that touched these commits would have to show one ref containing a commit the other
  does not, in the non-fast-forward direction; it does not.
- *"maybe the order is coincidental"* — no. `0a5c42a7`'s **recorded parent is `e1c65975`**, and
  `e1c65975` is reachable only through the `2159c657` line, so the three are linearly ordered by
  the commit graph itself, not by timestamp.

**Order and distance: CONFIRMED.** `2159c657` → (8) → `e1c65975` → (1) → `0a5c42a7`, span from
first to last = **9**. The correction's "nine commits apart" is the `rev-list` span and is exactly
reproducible.

> Side note, not a defect in the correction: the source report says `2159c657` "is an ancestor
> **10** commits back (was 8)" (`dc-warn/out/p09-tiqian-feasibility/REPORT.md:25`), which is a
> different counting convention from `rev-list --count` = 9. The correction silently uses 9.
> 9 is the reproducible one; the report's 10 is not reproducible by `rev-list --count`.

### 1.2 What ancestry does **not** prove — the correction's non sequitur

The correction's cell reads: *"it is **not** a three-way choice awaiting a gate owner"* and its
blocked-by column reads *"nothing needs deciding"* (`18d44ec1:docs/architecture/GATE-LEDGER.md`,
P09 table row 1). The git facts above do not support that step, and the source material
contradicts it:

- `dc-warn/out/p09-tiqian-scope/REPORT.md:136` — the **pre-existing** audit already knew the
  ancestry: *"`2159c657` **is** an ancestor of HEAD but is **8 commits behind**"* — and it still
  framed the Boring side as open, both at `:286` (*"**Boring-side revision of the pair is still an
  open decision** (`2159c657` vs `e1c65975`)"*) and at `:410` (*"[ ] Choose Boring side:
  `2159c657…` … **or** `e1c65975`"*). So "all three are ancestors" was already in the record and
  was never the reason the criterion was open.
- Being three ancestors of the same branch is *exactly* what makes them three candidate pins. The
  set of ancestor commits of a branch is not a single element; "they are all on the line" reduces
  the choice to a position on a line, it does not remove it.

So: **the factual half of assertion 1 is confirmed; the "therefore it is not a choice" half is an
inference the evidence does not carry, and it is refuted by the two source reports.**

### 1.3 The "9 commits then, 124 now" figure is a category error

`18d44ec1` / `696acd93` write: *"Each time the pair was about to be recorded, the base had
advanced again — 9 commits then, 124 on the local ref and 167 on the remote one now."* The two
numbers are **different quantities**: 9 is the *span between the three candidates*
(`2159c657..0a5c42a7`, a constant that cannot change), while 124/167 is the *drift of the base past
`0a5c42a7`*. Presenting 9 as an earlier reading of the moving drift makes it look like a time
series of one measurement. The source report's actual drift series is
`2159c657`→HEAD = 8 (scope audit, `:136`) → 10 (feasibility report, `:25`), i.e. the drift is
measured from `2159c657`, not from `0a5c42a7`. The correction should quote the base-to-`0a5c42a7`
drift as the drift, and the 9 as the fixed inter-candidate span.

## 2. Criterion 2 — "base leads `0a5c42a7` by 124" (rechecked against the amended text)

### 2.1 The number is ref-dependent, and I confirm both readings

```
$ git rev-list --count 0a5c42a7..arch/agent-guided-governance          -> 124
$ git rev-list --count 0a5c42a7..origin/arch/agent-guided-governance   -> 167
$ git rev-parse arch/agent-guided-governance origin/arch/agent-guided-governance
0641991bc481bb929f010506f4bbed5aff10cc22
372c42a629bf8cfe968e4ddc9e7c3a890212cc61
$ git rev-list --count arch/agent-guided-governance..origin/arch/agent-guided-governance -> 43
$ git rev-list --count origin/arch/agent-guided-governance..arch/agent-guided-governance -> 0
```

| Ref | Commit | Commits past `0a5c42a7` | Recheck |
|---|---|---|---|
| `arch/agent-guided-governance` (local) | `0641991b` | 124 | **CONFIRMED** |
| `origin/arch/agent-guided-governance` | `372c42a6` | 167 | **CONFIRMED** |
| local is an ancestor of remote; remote is 43 further | — | 43 / 0 | **CONFIRMED** |

The amended table in `696acd93` is therefore **correct in all three cells**, and the dispatcher's
supplement is arithmetically correct. I found no error in it. Two qualifications on it:

1. **The rewrite is incomplete inside its own section.** The paragraph *above* the new table,
   still present at `696acd93` and in the working tree at `docs/architecture/GATE-LEDGER.md:274-275`,
   still states flatly: *"All three are **ancestors of the base branch**, and
   `boring-wt-architecture`'s base is now **124 commits past `0a5c42a7`**."* The new table then
   says the number that matters is 167. A reader who stops at the paragraph keeps the misleading
   figure; the correction adds the caveat without removing the claim it undercuts.
2. **"124" alone is misleading, and specifically for the reason `696acd93` gives.** The same
   section's own delivery rule (quoted at `docs/architecture/GATE-LEDGER.md:503-508`) requires a
   pin **reachable from a commit that is on a remote ref**, and records the rule as
   `rev-list --count origin/<branch>..<branch>`. Under that rule the operative drift is **167**;
   124 understates it by 43 and, worse, 124 is not obtainable by a clone at all. So "leading 124"
   is not *false* — it is true of a local ref — but as the headline drift figure it is
   **incomplete and misleading**, and a pin quoted as "124 ahead" could not be reproduced from the
   remote.

### 2.2 …and the ref the number was measured on is itself the defect the document records

```
$ git merge-base --is-ancestor 18d44ec1 origin/ci/collected-suite-failure-attribution  -> NO
$ git merge-base --is-ancestor 696acd93 origin/ci/collected-suite-failure-attribution  -> NO
$ git branch -r --contains 696acd93   -> (empty)
$ git rev-parse origin/arch/agent-guided-governance origin/ci/collected-suite-failure-attribution
372c42a629bf8cfe968e4ddc9e7c3a890212cc61
372c42a629bf8cfe968e4ddc9e7c3a890212cc61
```

The correction commit `18d44ec1` and its amendment `696acd93` are **themselves local-only** — no
remote ref contains them — and the two remote-tracking refs the language distinguishes
("origin/arch/…" vs "origin/ci/…") currently **resolve to the same object** `372c42a6`. So the
document that fixes the "quote a remote ref" defect is, at the time of this recheck, unreachable
from any remote ref. This is worth recording because it means the local/remote distinction the
amendmed text draws is, right now, a distinction between *one* remote tip and two different local
tips, and the two remote-tracking refs give no independent corroboration of each other. I did not
run `ls-remote` (needs the network; not required for the assertions).

The "115" figure elsewhere in the ledger is **stale, not wrong-at-the-time**: `:504` records
*"`origin/arch/agent-guided-governance` `c9e2cff9`, 115 commits behind local"*, and today
`git rev-list --count c9e2cff9..0641991b` = **131** (with `0641991b..c9e2cff9` = 0, so `c9e2cff9`
is an ancestor of the current local base). Anyone re-citing "115" today would be quoting a
measurement of a ref that has since moved 16 commits, in a relationship that has since
**inverted** (local is now the one behind). It should be dated or dropped.

## 3. Criterion 3 — is "the moving target" read from the report, or read into it?

Source: `dc-warn/out/p09-tiqian-feasibility/REPORT.md`. The correction cites it as
`out/p09-tiqian-feasibility/REPORT.md`; the file on disk is
`/home/losses/Development/tq-workspace/dc-warn/out/p09-tiqian-feasibility/REPORT.md` (13,497 bytes,
dated 2026-09-30 11:47). Note for provenance: `dc-warn` is a **git-excluded** path
(`git check-ignore -v` → `/home/losses/Development/tq-workspace/boring/.git/info/exclude:7:/dc-warn`),
and `git ls-files | grep -c p09-tiqian-feasibility` = **0**; I also scanned every local head
(`ls-tree -r --name-only` per branch, 60 branches) and found the path in **none**. It is a
filesystem artifact, not a revision-anchored one — so a reader cannot re-derive it from a clone,
which is the same class of defect as §2.2.

### 3.1 The sentence, verbatim, and what it actually says

`REPORT.md:84`, §5 "Revision-pair statement", opening line:

> - **Boring side: STILL UNDECIDED, and the ground has shifted again.** Runbook says
>   `2159c657` (now 10 commits behind HEAD `0a5c42a7`); the audit's alternative `e1c65975` is
>   now itself superseded by `0a5c42a7` ("baseline"), which additionally commits the runbook,
>   f32 example HXMLs, and further Rust/Swift/Dart compiler changes.

The quoted fragment in `18d44ec1` is **verbatim accurate**. But it is a **conjunction**: the report
asserts *both* that the side is undecided *and* that the ground moved. `18d44ec1` renders the
"and" as an opposition — *"So the real blocker is that the ground moves, **not** that nobody has
chosen"* — and the sentence it quotes does not say that. The elided first half ("STILL
UNDECIDED") is the half the report puts in bold.

### 3.2 The report's own conclusion contradicts the correction's conclusion

Three further sentences from the same report, all unquoted by the correction:

`REPORT.md:101-102`, the last paragraph of §5:

> **Therefore: the pair is half-fixed. The Boring side is the single open decision; without it
> no stage command may legitimately be run.**

`REPORT.md:104`, the heading of §6:

> ## 6. Decider's minimum (everything cited exists on disk)

`REPORT.md:106-109`, §6 item 1:

> 1. **Decide the pair and write it down**: Tiqian `8504d230…` × Boring `2159c657` (prepared;
>    excludes subsequent compiler work) **or** `e1c65975` (alternate snapshot prepared) **or**
>    re-select at current HEAD (requires a fresh staging snapshot + re-preparation).

So the source report (a) names the Boring side "the **single open decision**", (b) titles the
remedy "**Decider's** minimum", and (c) enumerates **three** alternatives joined by "**or**" for
the decider to pick from. That is, textually, a three-way decision awaiting a decider — the exact
reading `18d44ec1` calls "the mis-statement that kept it open".

Why the third option is the same three candidates: the report's own §1 already fixes
`0a5c42a7` as "Boring coordinator HEAD" (`:25`), so "re-select at current HEAD" *is* the
`0a5c42a7` branch of the choice. The three options in §6.1 are the same three commits as the old
cell. The `2159c657 / e1c65975 / 0a5c42a7` reading was not, on this evidence, an artifact of
misreading separators: the scope audit uses the same "or" construction at `:410` (*"Choose Boring
side: `2159c657…` … **or** `e1c65975`"*), and the feasibility report reproduces it.

### 3.3 What the correction got right in this section

Two things, stated fairly:

- The report **does** supply a discriminating argument against option 1, verbatim at `:89-91`:
  *"a gate run on them would freeze a candidate that predates both Rust fixes **and** the
  additional `0a5c42a7` compiler work. That contradicts the evident intent of 'baseline'."*
  The correction quotes this accurately.
- The "ground has shifted again" phrasing is real, and the report does record movement (`:25`
  "moved since the scope audit"; `:32-33` "That has changed: commit `0a5c42a7` … adds this exact
  file … to git").

**But even here the correction over-reads.** `REPORT.md:92-96` immediately after that argument
still lists choosing `e1c65975` and choosing `0a5c42a7` as live options, and closes (§6.1) by
handing all three to a decider. The report expresses a *preference* with a stated reason; it does
not declare the direction "determined" to the point that no decision remains. `18d44ec1`'s claim
that the criterion is *"no longer blocked on a decision"* and *"not a question for the gate
owner"* has **no sentence in the source supporting it** and two sentences opposing it.

**Verdict on assertion 4: REFUTED as stated (over-read).** Supported: "the ground moved" and
"there is a stated reason against pinning `2159c657`". Not supported, and contradicted:
"therefore the blocker is movement **rather than** an unmade decision / nothing needs deciding".

### 3.4 Residual internal contradiction in the ledger

The same post-correction `GATE-LEDGER.md` still says, at `:411-412`:

> **What remains before P09 criterion 3 can run** is therefore **not** an environment
> limit: it is (a) criterion 1's **Boring side**, still undecided three-way, and
> (b) deciding to spend the run.

So the file asserts "not a three-way choice" at criterion 1 and "still undecided three-way" seven
screens later, and lists `P09-1 | a Boring-side revision decision by the gate owner` at `:490`.
Either the correction did not propagate, or the correction is wrong. On the source-report
evidence in §3.2 above, the *later* lines are the ones consistent with `REPORT.md`.

## 4. Criterion 4 — the `304ed70c` divergence (`rev-list` = 150), rechecked per ref

### 4.1 Where 150 comes from: it reproduces, but only against `0a5c42a7`

```
$ git rev-list --count 304ed70c..0a5c42a7     -> 150
$ git merge-base 0a5c42a7 304ed70c            -> 378dfdbf8313206e68a074b80cb381fd83293cbc
$ git merge-base --is-ancestor 304ed70c 0a5c42a7 -> NO
$ git rev-list --count 0a5c42a7..304ed70c     -> 18
```

All three elements of the report's parenthetical — *"merge-base `378dfdbf`; `rev-list
304ed70c..HEAD` = 150"* — are **exactly reproduced** when `HEAD` is read as `0a5c42a7`. And that
reading is the report's own: `REPORT.md:25` designates `0a5c42a7` "Boring coordinator HEAD".
So the number is **not fabricated and not irreproducible**; it is anchored to a commit the report
names. That much of the correction is sound, and my initial suspicion that 150 was stale was wrong.

### 4.2 …but "HEAD" is exactly the token that no longer means `0a5c42a7`

The dispatcher asked for both refs; here they are, with the trend:

```
$ git rev-list --count 304ed70c..ci/collected-suite-failure-attribution        -> 349   (18d44ec1)
$ git rev-list --count 304ed70c..arch/agent-guided-governance                  -> 274   (0641991b, local base)
$ git rev-list --count 304ed70c..origin/arch/agent-guided-governance           -> 299   (372c42a6, remote base)
$ git rev-list --count 304ed70c..HEAD                                          -> 346   (5544570, the shared tree's momentary checkout)
$ git merge-base --is-ancestor 304ed70c ci/collected-suite-failure-attribution -> YES
$ git merge-base --is-ancestor 304ed70c arch/agent-guided-governance           -> NO
$ git merge-base --is-ancestor 304ed70c origin/arch/agent-guided-governance    -> YES
$ git merge-base arch/agent-guided-governance 304ed70c        -> 378dfdbf8313206e68a074b80cb381fd83293cbc
$ git merge-base origin/arch/agent-guided-governance 304ed70c -> 304ed70c4ba09fe21edadcca4c85f963fd692927
$ git rev-list --count arch/agent-guided-governance..304ed70c -> 18
$ git rev-list --count origin/arch/agent-guided-governance..304ed70c -> 0
$ git rev-list --count ci/collected-suite-failure-attribution..304ed70c -> 0
```

The dispatcher's specific question — "does 150 reproduce on `ci/collected-suite-failure-attribution`
and on `arch/agent-guided-governance`?" — answer: **no, on neither.** It is 349 and 274
respectively. The number 150 belongs to `0a5c42a7` alone.

### 4.3 The stronger claim — "divergent Boring lineages" — is ref-false on the remote base

`18d44ec1` concludes from this: *"The two halves of P09 are natively pinned to **different,
divergent Boring lineages**."* That is true **only** against `0a5c42a7` and the stale local base.
Against the **remote base** — the ref `696acd93` itself insists must ground the pin — the
merge-base of `304ed70c` and the base **is `304ed70c`**, i.e. the flake-pinned lineage is an
**ancestor of the base**, and `rev-list base..304ed70c` = **0**, i.e. nothing of that lineage is
outstanding. The divergence had been **resolved by a merge** by the time of `372c42a6`
(2026-10-01 00:06), which is 43 commits after the local base and therefore inside the 43-commit
window the amendment is about. Same on the correction's own branch: `304ed70c` is an ancestor of
`18d44ec1` (`rev-list 18d44ec1..304ed70c` = 0).

So the section is internally inconsistent in the same way as §2.1: it applies the "must use the
remote ref" standard to the 124/167 number and **not** to the 150/divergent claim. Under the
standard it sets, the correct statement is:

- against `0a5c42a7` (a past coordinate, and the report's HEAD): `304ed70c` was divergent,
  merge-base `378dfdbf`, `rev-list` = 150 — a **historical** finding;
- against the current **remote** base `372c42a6`: `304ed70c` is an **ancestor**, `rev-list` = 299,
  merge-base = `304ed70c` — the lineages have **converged**.

Whether the native pinning still *matters operationally* is a separate question I am not deciding
(the runbook's `HAXELIB_PATH` shadowing requirement is a procedural fact, `REPORT.md:97-99`, and I
did not re-run it). But *"P09's two halves are natively pinned to divergent Boring lineages"*, as
an unqualified present-tense claim in a document whose base is the remote ref, is **REFUTED**.

**Verdict on assertion 5: the 150 is CONFIRMED as reproducible but ref-anchored to an unstated
HEAD; the "divergent lineages" characterisation is confirmed only for the past coordinate and
REFUTED against the current remote base. The correction does not describe this correctly, because
it does not say which HEAD and its next sentence generalises to the present.**

## 5. Criterion 5 — first-hand measurement vs. transcription

Everything in §1–§4 marked "measured" was produced by single-value commands in this session, run
from `/home/losses/Development/tq-workspace/boring-wt-architecture` with
`git rev-parse`, `git rev-list --count`, `git merge-base`, `git merge-base --is-ancestor`,
`git log -1 --format`, `git ls-tree -r --name-only`, `git branch -r --contains`. No branch was
switched, no loop over commits produced a number, and every integer is a `--count` scalar printed
alone.

| Claim rechecked | Command | Output | First-hand? |
|---|---|---|---|
| three are ancestors of local base | `merge-base --is-ancestor <c> arch/agent-guided-governance` | YES/YES/YES | yes |
| three are ancestors of remote base | `merge-base --is-ancestor <c> origin/arch/agent-guided-governance` | YES/YES/YES | yes |
| no base rebase | `merge-base --is-ancestor arch/... origin/arch/...` + `rev-list --count origin/... ..arch/...` | YES, 0 | yes |
| order + span | `rev-list --count 2159c657..e1c65975`, `e1c65975..0a5c42a7`, `2159c657..0a5c42a7` | 8, 1, 9 | yes |
| parent link | `git log -1 --format='%H parents=%P' 0a5c42a7` | parent = `e1c65975` | yes |
| 124 / 167 / 43 | `rev-list --count 0a5c42a7..<ref>` ×2, `arch/... ..origin/arch/...` | 124, 167, 43 | yes |
| 150 anchor | `rev-list --count 304ed70c..0a5c42a7` | 150 | yes |
| 150 off-anchor | `rev-list --count 304ed70c..ci/collected-suite-failure-attribution`, `..arch/agent-guided-governance` | 349, 274 | yes |
| divergence direction | `merge-base origin/arch/... 304ed70c`, `rev-list --count origin/arch/... ..304ed70c` | `304ed70c`, 0 | yes |
| correction is local-only | `merge-base --is-ancestor 18d44ec1 origin/ci/...`, `branch -r --contains 696acd93` | NO, empty | yes |
| report is untracked | `git ls-files \| grep -c p09-tiqian-feasibility`, per-branch `ls-tree` scan | 0, none | yes |

**Transcribed, not re-measured (stated so the reader can discount it):** the `REPORT.md` quotes in
§3.1/§3.2 (read from the file, not derived); the Tiqian-side hashes `8504d230`/`f5c48441`/`1ad3816`/
`3d52039d` (commits of a **different repository**; I did not attempt to resolve them here, matching
`18d44ec1`'s own caveat at its lines 66-69); the existence and hashes of the prep snapshots
(`fixed-compiler-2159c657`, `fixed-compiler-e1c65975`, the 30-hash manifest) — I did not reopen
those artifacts, and no assertion in this recheck depends on them; the `HAXELIB_PATH` shadowing
behaviour; and the runbook's line counts.

**Searched and not found (so "not found", not "does not exist"):** `dc-warn/out/p09-tiqian-feasibility/REPORT.md`
is absent from `arch/agent-guided-governance`, absent from `18d44ec1`, absent from all 60 local
branch trees scanned, and `git ls-files` returns 0 for the path; it exists only on the filesystem,
behind a `git info/exclude` rule. I did not query `refs/remotes/*` trees beyond
`origin/arch/agent-guided-governance` and `origin/ci/collected-suite-failure-attribution`, and I
did not fetch, so a copy on some unfetched remote-tracking ref is not excluded.

## 6. Answers to the three hostile questions posed by the dispatcher

1. **Could the three not all be on base (tag / other branch / base rebased)?**
   No. All three are ancestors of both the local and the remote base, and the local base is a
   strict ancestor of the remote base (forward-only), which excludes a rewrite affecting them.
   The ancestry and the order survive the hostile test. See §1.1.
2. **Does "124" depend on the local ref, and is it therefore misleading?**
   Yes, and yes. 124 is the **local** figure; the remote base gives **167**, and the local base is
   43 behind the remote with 0 the other way. The pin the same document demands must be reachable
   from a remote ref, so **124 is incomplete as the drift figure and misleading if quoted as
   "the base is 124 ahead"** — it understates by 43 and is not clone-reproducible. The
   `696acd93` amendment states both numbers correctly, and I found no error in it; but the
   unqualified "124 commits past `0a5c42a7`" sentence survives at `GATE-LEDGER.md:274-275` above
   the new table, so the fix is partial. See §2.
3. **Is "moving target" read out of `REPORT.md` or into it?**
   Read **into** it for its operative half. The quoted words are verbatim, but the sentence is an
   "and", and the same report says in terms *"the Boring side is the **single open decision**"*,
   heads §6 *"**Decider's** minimum"*, and enumerates three options joined by "or" for that
   decider. The correction's "not a three-way choice / nothing needs deciding" is not merely
   unsupported by the source; it is opposed by three of its sentences. See §3.
4. **(Addendum, from the same recheck.) Is the "150 / divergent lineages" half correct?**
   The 150 reproduces exactly — but only with `HEAD` = `0a5c42a7`, which the correction never
   states (on the two refs it is 349 and 274). And the generalisation to the present is false on
   the remote base, where `304ed70c` is an **ancestor** of the base and the divergence is
   resolved. The same remote-ref standard the amendment applies to the drift number is not
   applied here. See §4.

## 7. What, if anything, should change (recommendations only — not my call, non-goal to edit)

Not actions I took; listed because a recheck that finds a defect should name it precisely.

- `GATE-LEDGER.md:274-275`: qualify or remove the bare "124 commits past `0a5c42a7`", which the new
  table immediately undercuts.
- `GATE-LEDGER.md:308-314`: state which `HEAD` the 150 is measured against (`0a5c42a7`), and
  restate the divergence against the current base ref — where it is `304ed70c` **is** an ancestor,
  `rev-list` = 299, merge-base = `304ed70c`. If the operational point (the flake's native mapping)
  is what matters, say that instead of "divergent lineages".
- `GATE-LEDGER.md:411-412` and `:490`: reconcile with the criterion-1 correction, or state
  explicitly why the Boring side is simultaneously "not a choice" and "still undecided three-way".
- `GATE-LEDGER.md:504`: date the "115 commits behind local" note (it is 131 past `c9e2cff9` today
  and the local/remote relationship has inverted).
- The criterion-1 cell's blocked-by text ("nothing needs deciding") should match whatever the
  decision framing ends up being; on the source evidence it is a decider's choice with a
  documented preference, not an absent decision.
- Provenance: `dc-warn/` is git-excluded, so the correction's cited source (`REPORT.md`) and this
  recheck's own scratch copies are not recoverable from a clone. That is the same defect the
  delivery-surface rule targets; if criterion 1 is to rest on that report, the report needs a
  tracked home or a recorded digest.

---

Recheck performed 2026-10-01 (America/Toronto). Shared tree was on
`audit/l4-fixture-collection-coverage` throughout; all queries were ref-addressed. This file is
the only repository file written by this recheck.
