# P09 revision pair: the Boring-side pin

Prep record for P09 criterion 1 ("A recorded revision pair"). Task handle
`prep/p09-boring-revision-pin`. Every value below is a measurement, and every
measurement is given as one command plus its captured output, so a reader can
re-derive the conclusion; accepting it on the record's word is not required.

## 0. Scope, provenance, and what this record is not

- It records **one fixed** Boring revision for the P09 pair, and the commands
  that reproduce every value in it.
- It **does not replace P09 execution** and **does not claim criterion 1 has
  passed**. Criterion 1 is "a recorded revision pair"; what is recorded here is a
  preparation input. Criterion 2 (Boring checks executed), criterion 3 (Tiqian
  checks executed) and criterion 4 (logs preserved) stay NOT ESTABLISHED, and
  this file changes none of those verdicts.
- Criterion 1 is **blocked on a decision**. `REPORT.md` §5 closes with "the
  Boring side is the single open decision" (Q5), §6 is headed "Decider's
  minimum" (Q6), and its item 1 hands three options to a decider (Q7). This
  record supplies a recorded pin together with a reproducible basis for it; it
  does not assert that no decision was needed, and it does not sign itself off.
- It does not decide whether the staging snapshot is rebuilt, and it changes no
  existing ruling, no compiler source, no test and no CI file.

### 0.1 Provenance of the claims about the coordination documents

- Authoring base: `ci/collected-suite-failure-attribution` at `696acd93`, in the
  worktree `/home/losses/Development/tq-workspace/boring-wt-p09pin`.
- The reading of P09 criterion 1 carried by `18d44ec1` and amended by `696acd93`
  in `docs/architecture/GATE-LEDGER.md` was **retracted** by `cfef07da` after an
  independent recheck,
  `docs/architecture/evidence/layered-verification-review/P09-CRITERION1-RECHECK.md`.
  Three of that reading's claims are withdrawn and are **not** relied on here:
  "all three are ancestors, therefore it is not a choice" (a non sequitur), the
  "9 commits then, 124 now" trend (two unlike quantities on one line), and the
  present-tense "the two halves are natively pinned to divergent Boring
  lineages" claim (§3.2 below).
- This branch is rebased onto `9086bf78`, which contains `cfef07da`, so the
  record ships on a base where the retraction is already present:

      $ git merge-base --is-ancestor cfef07da 9086bf78; echo rc=$?
      rc=0
      [rc=0]

- Caveat on that provenance chain, measured at the same time and stated because
  it is the defect this record's own §5 warns about: the retraction `cfef07da`
  and the base it retracts (`696acd93`) are on **no** remote ref, so the
  retraction itself is not clone-reachable.

      $ git branch -r --contains cfef07da | wc -l
      0
      [rc=0]

      $ git branch -r --contains 696acd93 | wc -l
      0
      [rc=0]

  The same holds for the branch carrying this record at the time of writing, so
  "committed" here means committed on a local branch, not delivered to a clone:

      $ git branch -r --contains prep/p09-boring-revision-pin | wc -l
      0
      [rc=0]
- Wherever this record takes a judgement from a coordination document, it names
  the commit it was read at. The quotes in §2 are read from
  `dc-warn/out/p09-tiqian-feasibility/REPORT.md`, which is a filesystem artifact
  and not revision-anchored (the recheck's §3 records that `git ls-files` finds
  it in no branch); the reader should treat those quotes as read-at-that-path,
  and the numbers beside them as measured here.

## 1. The pin

| Field | Value |
|---|---|
| Boring-side ref, full name | `refs/heads/arch/agent-guided-governance` |
| Same ref, local tip | `0641991bc481bb929f010506f4bbed5aff10cc22` |
| Same ref, remote tip | `refs/heads/arch/agent-guided-governance` on `origin`, in this checkout `origin/arch/agent-guided-governance` = `372c42a629bf8cfe968e4ddc9e7c3a890212cc61` |
| Is that ref on the remote | **Yes.** `git ls-remote --heads origin arch/agent-guided-governance` is non-empty and names `372c42a6…` |
| **Pinned Boring revision** | **`0a5c42a702d938ca4da39cbcefae2cc450e021fe`** (subject `baseline`) |
| Tiqian side | `8504d230228e8206689a2049bbb84b671c1f079a`, a commit in the **Tiqian repository**, not this one (§1.3) |

**Local or remote.** The name `arch/agent-guided-governance` exists in this
repository **both** ways, and the two spellings point at different commits (the
local tip is 43 commits behind the remote tip). This record quotes the **remote**
spelling: the delivery rule in `docs/architecture/GATE-LEDGER.md` requires a pin
reachable from a commit that is on a remote ref, and a pin quoted against the
local tip would report a different drift number and would not be reproduced by a
clone (§5).

The pinned revision is a **fixed commit**, and it is not a ref tip: `0a5c42a7` is
reachable from the remote ref. A ref tip is the quantity the source report
describes as shifting (Q1), so recording a tip would record the thing that moves.

One caveat on the remote spelling, measured here: at this time the two remote
names `origin/arch/agent-guided-governance` and
`origin/ci/collected-suite-failure-attribution` resolve to the **same object**
`372c42a6`, so they are one observation and not two independent ones.

### 1.1 Reproduction commands and outputs

    $ git rev-parse --symbolic-full-name arch/agent-guided-governance
    refs/heads/arch/agent-guided-governance
    [rc=0]

    $ git rev-parse arch/agent-guided-governance
    0641991bc481bb929f010506f4bbed5aff10cc22
    [rc=0]

    $ git rev-parse --symbolic-full-name origin/arch/agent-guided-governance
    refs/remotes/origin/arch/agent-guided-governance
    [rc=0]

    $ git rev-parse origin/arch/agent-guided-governance
    372c42a629bf8cfe968e4ddc9e7c3a890212cc61
    [rc=0]

    $ git ls-remote --heads origin arch/agent-guided-governance
    372c42a629bf8cfe968e4ddc9e7c3a890212cc61	refs/heads/arch/agent-guided-governance
    [rc=0]

    $ git rev-parse 0a5c42a7^{commit}
    0a5c42a702d938ca4da39cbcefae2cc450e021fe
    [rc=0]

    $ git log -1 --format='%H %s' 0a5c42a7
    0a5c42a702d938ca4da39cbcefae2cc450e021fe baseline
    [rc=0]

Reachability of the pinned commit from the remote ref (this is the delivery
rule, and it is not an inference):

    $ git merge-base --is-ancestor 0a5c42a7 origin/arch/agent-guided-governance; echo rc=$?
    rc=0
    [rc=0]

    $ git branch -r --contains 0a5c42a7 | wc -l
    23
    [rc=0]

    $ git branch -r --contains 0a5c42a7 | head -3
      origin/arch/agent-guided-governance
      origin/audit/consumer-missing-resident
      origin/audit/container-alias-nullable
    [rc=0]

The three-step delivery check this repository requires (`GATE-LEDGER.md`,
"Delivery integrity") for the pinned commit:

| Step | Command | Result |
|---|---|---|
| remote ref exists | `git ls-remote --heads origin arch/agent-guided-governance` | non-empty, `372c42a6…` |
| commit is contained in a remote ref | `git branch -r --contains 0a5c42a7` | 23 remote refs |
| lag against the remote spelling | `git rev-list --count origin/arch/agent-guided-governance..arch/agent-guided-governance` | `0` |

### 1.2 Measurement environment

    $ git rev-parse --show-toplevel
    /home/losses/Development/tq-workspace/boring-wt-p09pin
    [rc=0]

    $ git log -1 --format='%h %s' 696acd93
    696acd93 docs(gate): P09's pin has two grounds -- quote the remote ref, not the local one
    [rc=0]

    $ git log -1 --format='%h %s' 9086bf78
    9086bf78 fix(warning-gate): adjudicate the rcs the gate already measures
    [rc=0]

Date 2026-10-01 (America/Toronto). All commands below run from the worktree root
above. Every `[rc=...]` is captured directly; no value was read through a pipe
(that convention is the source report's, §8).

### 1.3 The Tiqian side, and why its hash does not resolve here

`8504d230228e8206689a2049bbb84b671c1f079a` is a commit in the **Tiqian
repository**, not this one. The command below is included so the reader sees
that, so local resolvability is not assumed:

    $ git cat-file -e 8504d230228e8206689a2049bbb84b671c1f079a; echo rc=$?
    rc=1
    [rc=0]

The Tiqian-side identity is quoted from the source report, which measured it in
the consumer checkout (Q8).

## 2. Why this revision

### 2.1 Verbatim quotes

From `dc-warn/out/p09-tiqian-feasibility/REPORT.md`. Line numbers are that
file's. Nothing in this subsection is paraphrased.

Q1 (§5, lines 84-86):

> **Boring side: STILL UNDECIDED, and the ground has shifted again.** Runbook says
> `2159c657` (now 10 commits behind HEAD `0a5c42a7`); the audit's alternative `e1c65975` is
> now itself superseded by `0a5c42a7` ("baseline"), which additionally commits the runbook,
> f32 example HXMLs, and further Rust/Swift/Dart compiler changes.

Q2 (§5, lines 88-91):

> The prepared artifacts (snapshot `fixed-compiler-2159c657`, 12 prep HXMLs, 3 project
> JSONs, prep haxelib) are pinned to `2159c657` and remain internally consistent — but a
> gate run on them would freeze a candidate that predates both Rust fixes *and* the
> additional `0a5c42a7` compiler work. That contradicts the evident intent of "baseline".

Q3 (§5, lines 92-95):

> Choosing `e1c65975` instead requires the alternate staging snapshot
> (`publication-staging/fixed-compiler-e1c65975`, present, 26 top-level entries) and the
> second prep tree (`tiqian/out/p09-e1c65975-round2-prep/`) — a full re-preparation, none
> of whose per-file hashes I verified.

Q4 (§5, line 96):

> Choosing current HEAD `0a5c42a7` has **no prepared snapshot or prep tree at all**.

Q5 (§5, lines 101-102):

> **Therefore: the pair is half-fixed. The Boring side is the single open decision; without it
> no stage command may legitimately be run.**

Q6 (§6 heading, line 104):

> ## 6. Decider's minimum (everything cited exists on disk)

Q7 (§6 item 1, lines 106-109), which names the three candidate revisions:

> 1. **Decide the pair and write it down**: Tiqian `8504d230228e8206689a2049bbb84b671c1f079a` ×
>    Boring `2159c657` (prepared; excludes subsequent compiler work) **or** `e1c65975`
>    (alternate snapshot prepared) **or** re-select at current HEAD (requires a fresh staging
>    snapshot + re-preparation). Specified by: runbook §Fixed revision pair; scope-audit §6 C1.

Q8 (§1, line 21), the Tiqian-side identity:

> | Tiqian HEAD | `git rev-parse HEAD` = `8504d230228e8206689a2049bbb84b671c1f079a` (detached) | **Confirmed exactly as pinned.** |

### 2.2 The mechanical form of the stated reason

Q2 gives a reason against one of the three candidates. Written so a machine can
run it:

    A candidate C is excluded by Q2's stated reason iff
    `git merge-base --is-ancestor 0a5c42a7 C` exits 1, that is, iff C predates the
    `0a5c42a7` compiler work that Q2 names.

This predicate is the record's own text and is not quoted from anything. Q2 is
its only premise; neither source report writes an `is-ancestor` command.
Measured:

    $ git merge-base --is-ancestor 0a5c42a7 2159c657; echo rc=$?
    rc=1
    [rc=0]

    $ git merge-base --is-ancestor 0a5c42a7 e1c65975; echo rc=$?
    rc=1
    [rc=0]

    $ git merge-base --is-ancestor 0a5c42a7 0a5c42a7; echo rc=$?
    rc=0
    [rc=0]

`2159c657` and `e1c65975` both fail: each predates the `0a5c42a7` compiler work
that Q2 names. `0a5c42a7` does not fail, and it is a fixed commit. It is
therefore the revision this record pins.

**What this does not settle.** Q2 rules out one option; it does not choose among
the rest. `REPORT.md` §5 calls the Boring side "the single open decision" (Q5),
§6 is headed "Decider's minimum" (Q6) and hands the three options to a decider
(Q7). So this record's pin is a **recorded choice with a stated reason**; it is not a
determination, and criterion 1 stays FAIL until a decider accepts a pair.

### 2.3 The candidates are ordered on one line

The three candidates are ancestors of one another in a fixed order. That is a
property of the commit graph, and it reduces the choice to a position on a line;
it does not remove the choice, since the ancestor set of a branch has more than
one element.

    $ git merge-base --is-ancestor 2159c657 e1c65975; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base --is-ancestor e1c65975 0a5c42a7; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base --is-ancestor 2159c657 0a5c42a7; echo rc=$?
    rc=0
    [rc=0]

    $ git log -1 --format='%H parents=%P' 0a5c42a7
    0a5c42a702d938ca4da39cbcefae2cc450e021fe parents=e1c6597514634fd347d392709793cc19bd96c9a2
    [rc=0]

The parent link shows the order comes from the graph and not from timestamps.

**Two unlike quantities.** The span between the candidates (`2159c657..0a5c42a7`
= 9, §4) is a constant of the commit graph. The base's drift past `0a5c42a7`
(124 local, 167 remote, §4) is a different quantity. This record keeps them in
separate rows of §4 and never presents them as one trend.

### 2.4 Why the ref tip is not the pin

Both ref spellings are ref **tips**, and a tip is the quantity the source report
describes as shifting (Q1): the local tip is 124 commits past `0a5c42a7` and the
remote tip 167 (§4). Recording the remote tip as the pin would additionally make
the report's own `304ed70c` finding read as false, because a merge that was made
only on the remote side brought `304ed70c` into that tip's history (§3). The pin
is therefore the fixed commit `0a5c42a7`, and the ref is recorded as the place
the delivery rule requires it to be reachable from.

## 3. The `304ed70c` flake pin: anchored divergence and the run-time requirement

### 3.1 The report's `150` reproduces, and only with its anchor

Tiqian's flake pins Boring lineage `304ed70c`. The source report records,
against its own HEAD, "merge-base `378dfdbf`; `rev-list 304ed70c..HEAD` = 150".
Every element of that parenthetical reproduces when `HEAD` is read as
`0a5c42a7`, which is the commit the report names as Boring coordinator HEAD:

    $ git rev-parse 304ed70c
    304ed70c4ba09fe21edadcca4c85f963fd692927
    [rc=0]

    $ git merge-base 304ed70c 0a5c42a7
    378dfdbf8313206e68a074b80cb381fd83293cbc
    [rc=0]

    $ git rev-list --count 304ed70c..0a5c42a7
    150
    [rc=0]

    $ git merge-base --is-ancestor 304ed70c 0a5c42a7; echo rc=$?
    rc=1
    [rc=0]

    $ git rev-list --count 0a5c42a7..304ed70c
    18
    [rc=0]

`[rc=1]` means `304ed70c` is **not** an ancestor of the pinned revision, so the
flake-pinned lineage is not in the pinned revision's history, and 18 commits of
the pinned revision's line are outside that lineage. The divergence is real
**at this anchor**.

The same measurement per ref, each anchored to the commit the ref resolves to,
because the count changes with the anchor:

| Ref | Resolves to | `304ed70c` an ancestor? | `rev-list <ref>..304ed70c` |
|---|---|---|---|
| `0a5c42a7` (the pin) | `0a5c42a7` | no | 150 |
| `arch/agent-guided-governance` (local base) | `0641991b` | no | 274 |
| `696acd93` (authoring base) | `696acd93` | yes | 349 |
| `9086bf78` (rebase base) | `9086bf78` | yes | 354 |
| `origin/arch/agent-guided-governance` (remote base) | `372c42a6` | **yes** | **299** |

    $ git merge-base --is-ancestor 304ed70c arch/agent-guided-governance; echo rc=$?
    rc=1
    [rc=0]

    $ git merge-base --is-ancestor 304ed70c 696acd93; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base --is-ancestor 304ed70c 9086bf78; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base --is-ancestor 304ed70c 372c42a6; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base origin/arch/agent-guided-governance 304ed70c
    304ed70c4ba09fe21edadcca4c85f963fd692927
    [rc=0]

    $ git rev-list --count origin/arch/agent-guided-governance..304ed70c
    0
    [rc=0]

### 3.2 The present-tense claim is withdrawn; what survives

The report's §1 wording, quoted for completeness (Q9):

> **FINDING (new): the two halves are natively pinned to different, divergent Boring lineages.** The runbook anticipates this: the flake mapping must be shadowed for the whole run by `HAXELIB_PATH=out/tiqian-fixed-2159c657-prep/haxelib` (verified resolving to the fixed snapshot, probe 5). So the divergence is handled **by procedure**, not by revision identity — but it means a P09 run must never rely on the flake default mapping.

That wording is the report's, measured against its own HEAD. Stated in the
present tense without an anchor it is **false of the remote base**: the table in
§3.1 shows `304ed70c` is an ancestor of `origin/arch/agent-guided-governance`
(the merge base is `304ed70c` itself, and `rev-list` from that ref to `304ed70c`
is 0, so nothing of that lineage is outstanding). The GATE-LEDGER retraction
`cfef07da` withdraws the unanchored form for this reason, and this record does
not repeat it.

What survives, and is what a P09 run depends on:

1. **Anchored, historical.** Against `0a5c42a7`, the two are divergent:
   merge base `378dfdbf`, 150 (§3.1). The value `150` must always carry that
   anchor; a bare "HEAD" no longer means `0a5c42a7`.
2. **Procedural, and still binding.** The flake mapping must be shadowed for the
   whole run, whatever the revision pair is, because the flake resolves
   `304ed70c` literally by its own `shellHook` and stamps
   `.haxelib/boring/git/.boring-flake-revision` with it. An ancestor is not the
   pinned revision.

### 3.3 The run-time requirement

A P09 run **must not** rely on the flake's default mapping. `HAXELIB_PATH` must
be overridden to a prep haxelib **in the same shell, after** the flake
`shellHook` (runbook §Stage commands; Q9). The concrete shadow path named in Q9
belongs to the `fixed-compiler-2159c657` snapshot and therefore does **not**
transfer to the pin recorded here; which snapshot the run uses is the
re-preparation question this record does not decide (§0). What this record
fixes is that the run must shadow; which directory it points at is not fixed
here.

## 4. Every commit-distance number in this record

Each row is one command; the value in the first column is that command's output
alone. Rows that leave a ref name in the command are also anchored in the text
above, because a ref can move and a commit hash cannot.

| Value | Single command |
|---|---|
| 9 | `git rev-list --count 2159c657..0a5c42a7` |
| 8 | `git rev-list --count 2159c657..e1c65975` |
| 1 | `git rev-list --count e1c65975..0a5c42a7` |
| 124 | `git rev-list --count 0a5c42a7..arch/agent-guided-governance` |
| 167 | `git rev-list --count 0a5c42a7..origin/arch/agent-guided-governance` |
| 43 | `git rev-list --count arch/agent-guided-governance..origin/arch/agent-guided-governance` |
| 43 | `git rev-list --count 0641991b..origin/arch/agent-guided-governance` |
| 0 | `git rev-list --count origin/arch/agent-guided-governance..arch/agent-guided-governance` |
| 150 | `git rev-list --count 304ed70c..0a5c42a7` |
| 18 | `git rev-list --count 0a5c42a7..304ed70c` |
| 274 | `git rev-list --count 304ed70c..0641991b` |
| 349 | `git rev-list --count 304ed70c..696acd93` |
| 354 | `git rev-list --count 304ed70c..9086bf78` |
| 299 | `git rev-list --count 304ed70c..origin/arch/agent-guided-governance` |
| 0 | `git rev-list --count origin/arch/agent-guided-governance..304ed70c` |
| 23 | `git branch -r --contains 0a5c42a7 \| wc -l` |

Captured outputs, in full:

    $ git rev-list --count 2159c657..0a5c42a7
    9
    [rc=0]

    $ git rev-list --count 2159c657..e1c65975
    8
    [rc=0]

    $ git rev-list --count e1c65975..0a5c42a7
    1
    [rc=0]

    $ git rev-list --count 0a5c42a7..arch/agent-guided-governance
    124
    [rc=0]

    $ git rev-list --count 0a5c42a7..origin/arch/agent-guided-governance
    167
    [rc=0]

    $ git rev-list --count arch/agent-guided-governance..origin/arch/agent-guided-governance
    43
    [rc=0]

    $ git rev-list --count 0641991b..origin/arch/agent-guided-governance
    43
    [rc=0]

    $ git rev-list --count origin/arch/agent-guided-governance..arch/agent-guided-governance
    0
    [rc=0]

    $ git rev-list --count 304ed70c..0a5c42a7
    150
    [rc=0]

    $ git rev-list --count 0a5c42a7..304ed70c
    18
    [rc=0]

    $ git rev-list --count 304ed70c..0641991b
    274
    [rc=0]

    $ git rev-list --count 304ed70c..696acd93
    349
    [rc=0]

    $ git rev-list --count 304ed70c..9086bf78
    354
    [rc=0]

    $ git rev-list --count 304ed70c..origin/arch/agent-guided-governance
    299
    [rc=0]

    $ git rev-list --count origin/arch/agent-guided-governance..304ed70c
    0
    [rc=0]

    $ git branch -r --contains 0a5c42a7 | wc -l
    23
    [rc=0]

Ancestry relations used above, each its own command:

    $ git merge-base --is-ancestor arch/agent-guided-governance origin/arch/agent-guided-governance; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base --is-ancestor 0641991b origin/arch/agent-guided-governance; echo rc=$?
    rc=0
    [rc=0]

## 5. What a clone gets

`git ls-remote` reports the remote's own state, so it answers this without
depending on this checkout:

    $ git ls-remote --heads origin arch/agent-guided-governance
    372c42a629bf8cfe968e4ddc9e7c3a890212cc61	refs/heads/arch/agent-guided-governance
    [rc=0]

- A fresh clone gets `refs/heads/arch/agent-guided-governance` at
  `372c42a629bf8cfe968e4ddc9e7c3a890212cc61`, and that is the ref tip the clone
  will check out.
- It does **not** get the local tip `0641991b` as a ref tip: `0641991b` is 43
  commits behind the remote tip and is an ancestor of it, so the commit is
  fetchable, but the local ref spelling is not reproduced. This is why §1 quotes
  the remote spelling.
- The pinned revision `0a5c42a7` is obtainable by a clone: it is reachable from
  `372c42a6` (`merge-base --is-ancestor` `rc=0`, §1.1), 167 commits behind it.
- The Tiqian-side hash is **not** obtainable from this repository at all
  (§1.3); it lives in the Tiqian repository.

## 6. Non-claims

- This record is a **preparation** record. It does not run the P09 matrix, and it
  does not assert that P09 criterion 1 has passed. Criterion 1 asks for a
  *recorded* revision pair; the pair above is recorded, and accepting it is the
  decider's step (Q5, Q6, Q7). P09 criteria 2, 3 and 4 remain NOT ESTABLISHED.
- It does not decide whether the staging snapshot is rebuilt or re-prepared
  (`0a5c42a7` has no prepared snapshot per Q4). That decision is out of scope
  here, and nothing in this file should be read as a snapshot ruling.
- It changes no existing ruling and no code: the only file added by this task is
  this one.
