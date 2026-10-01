# P09 revision pair — the Boring-side pin

Prep record for P09 criterion 1 ("A recorded revision pair"). Task handle
`prep/p09-boring-revision-pin`. Every value below is a measurement, and every
measurement is given as one command plus its captured output so a reader can
re-derive the conclusion instead of accepting it.

## 0. Scope: what this record is, and what it is not

- It records **one fixed** Boring revision for the P09 pair, and the commands
  that reproduce every value in it.
- It **does not replace P09 execution** and **does not claim criterion 1 has
  passed**. Criterion 1 is "a recorded revision pair"; what is recorded here is a
  preparation input. Criterion 2 (Boring checks executed), criterion 3 (Tiqian
  checks executed) and criterion 4 (logs preserved) stay NOT ESTABLISHED, and
  this file changes none of those verdicts.
- It does not decide whether the staging snapshot is rebuilt, and it changes no
  existing ruling, no compiler source, no test and no CI file.

Measurement environment, stated so the reader can place the numbers:

    $ git rev-parse --show-toplevel
    /home/losses/Development/tq-workspace/boring-wt-p09pin
    [rc=0]

    $ git log -1 --format='%h %s' 696acd93
    696acd93 docs(gate): P09's pin has two grounds -- quote the remote ref, not the local one
    [rc=0]

(That commit is the branch tip at measurement time; this record is added on top
of it.)

    $ git status --porcelain
    (empty)
    [rc=0]

Date 2026-10-01 (America/Toronto). All commands below run from the worktree root
above. Every `[rc=...]` is captured directly; no value was read through a pipe
(that convention is this repository's, recorded in the same source report at
§8).

## 1. The pin

| Field | Value |
|---|---|
| Boring-side ref, full name | `refs/heads/arch/agent-guided-governance` |
| Same ref, local tip | `0641991bc481bb929f010506f4bbed5aff10cc22` |
| Same ref, remote tip | `refs/heads/arch/agent-guided-governance` on `origin`, in this checkout `origin/arch/agent-guided-governance` = `372c42a629bf8cfe968e4ddc9e7c3a890212cc61` |
| Is that ref on the remote | **Yes.** `git ls-remote --heads origin arch/agent-guided-governance` is non-empty and names `372c42a6…` |
| **Pinned Boring revision** | **`0a5c42a702d938ca4da39cbcefae2cc450e021fe`** (subject `baseline`) |
| Tiqian side | `8504d230228e8206689a2049bbb84b671c1f079a`, a commit in the **Tiqian repository**, not this one (§1.2) |

**Local or remote.** The name `arch/agent-guided-governance` exists in this
repository **both** ways, and the two spellings point at different commits (the
local tip is 43 commits behind the remote tip). This record quotes the **remote**
spelling: the delivery-surface rule requires a pin reachable from a commit that
is on a remote ref, and a pin quoted against the local tip would report a
different drift number and would not be reproduced by a clone (§5).

The pinned revision is a **fixed commit**, not a ref tip: `0a5c42a7` is reachable
from the remote ref. Recording a ref tip instead would record the thing that
keeps moving, which is the blocker the source report names.

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
rule, not an inference):

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

The three-step delivery check this repository requires (GATE-LEDGER.md,
"Delivery integrity") for the pinned commit:

| Step | Command | Result |
|---|---|---|
| remote ref exists | `git ls-remote --heads origin arch/agent-guided-governance` | non-empty, `372c42a6…` |
| commit is contained in a remote ref | `git branch -r --contains 0a5c42a7` | 23 remote refs |
| lag against the remote spelling | `git rev-list --count origin/arch/agent-guided-governance..arch/agent-guided-governance` | `0` |

### 1.2 The Tiqian side, and why its hash does not resolve here

`8504d230228e8206689a2049bbb84b671c1f079a` is a commit in the **Tiqian
repository**, not this one. The command below is included so the reader sees
that rather than assuming local resolvability:

    $ git cat-file -e 8504d230228e8206689a2049bbb84b671c1f079a; echo rc=$?
    rc=1
    [rc=0]

The Tiqian-side identity is quoted from the source report, which measured it in
the consumer checkout (§2, Q1).

## 2. Why this revision — the source report's own criterion

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

Q6 (§6.1, lines 106-109), which names the three candidate revisions:

> 1. **Decide the pair and write it down**: Tiqian `8504d230228e8206689a2049bbb84b671c1f079a` ×
>    Boring `2159c657` (prepared; excludes subsequent compiler work) **or** `e1c65975`
>    (alternate snapshot prepared) **or** re-select at current HEAD (requires a fresh staging
>    snapshot + re-preparation). Specified by: runbook §Fixed revision pair; scope-audit §6 C1.

Q7 (§1, line 21), the Tiqian-side identity:

> | Tiqian HEAD | `git rev-parse HEAD` = `8504d230228e8206689a2049bbb84b671c1f079a` (detached) | **Confirmed exactly as pinned.** |

### 2.2 The mechanical form of that criterion

The report names exactly three candidate revisions (Q6). Its criterion eliminates
the first (Q2). Written so a machine can run it, on the line the pair lives on:

This predicate is the record's own text, not a quote:

    A candidate C survives iff `git merge-base --is-ancestor 0a5c42a7 C` exits 0,
    that is, iff C does not predate the `0a5c42a7` compiler work that Q2 rules
    out. The pin is the only surviving named candidate.

Its single premise is Q2 (and
Q1's "superseded by `0a5c42a7`"); the report does not itself write an
`is-ancestor` command. Measured:

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
that Q2 names. `0a5c42a7` is the only named candidate that survives, and it is a
fixed commit, which is what "record one revision and stop the ground moving"
requires.

The three candidates are one line in order, not three alternatives (this is the
correction the ledger records, and it reproduces here):

    $ git merge-base --is-ancestor 2159c657 e1c65975; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base --is-ancestor e1c65975 0a5c42a7; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base --is-ancestor 2159c657 0a5c42a7; echo rc=$?
    rc=0
    [rc=0]

### 2.3 Why the ref tip is not the pin

Both ref spellings are ref **tips**, and a tip is the moving quantity itself:
the local tip is 124 commits past `0a5c42a7` and the remote tip 167 (§4).
Recording the remote tip as the pin would additionally make the divergence
statement in §3 read as false, because a merge that landed only on the remote
side brought `304ed70c` into that tip's history (§3.2). The pin is therefore the
fixed commit `0a5c42a7`, and the ref is recorded as the place the delivery rule
requires it to be reachable from.

## 3. The `304ed70c` divergence — declaration and run-time requirement

### 3.1 The declaration, measured against the pinned revision

Tiqian's flake pins Boring lineage `304ed70c`. The source report found it
divergent from its HEAD. Measured here against the pinned revision
`0a5c42a7`, the divergence reproduces exactly:

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

`[rc=1]` means `304ed70c` is **not** an ancestor of the pinned revision: the two
halves are pinned to **divergent** Boring lineages. The merge base is `378dfdbf`
and the count `150` match the source report's own numbers (Q8 below), so the
declaration is a reproduction rather than a repetition.

Q8 (`REPORT.md` line 24), the report's headline finding:

> **FINDING (new): the two halves are natively pinned to different, divergent Boring lineages.** The runbook anticipates this: the flake mapping must be shadowed for the whole run by `HAXELIB_PATH=out/tiqian-fixed-2159c657-prep/haxelib` (verified resolving to the fixed snapshot, probe 5). So the divergence is handled **by procedure**, not by revision identity — but it means a P09 run must never rely on the flake default mapping.

Q9 (`REPORT.md` lines 97-99):

> **Native flake pin divergence:** Tiqian's own flake pins `304ed70c` (divergent lineage, 150
> commits off the candidate line). Any P09 run is valid only under the prep-haxelib shadow;
> the runbook already mandates this, and I verified the shadow resolves correctly.

### 3.2 Run-time requirement, and one further measured fact

**Requirement.** A P09 run **must not** rely on the flake's default mapping. The
flake `shellHook` re-asserts `304ed70c` and stamps
`.haxelib/boring/git/.boring-flake-revision` with it, i.e. the native mapping
resolves to a revision that is not the pin. `HAXELIB_PATH` must be overridden to
a prep haxelib **in the same shell, after** the flake `shellHook` (runbook §Stage
commands; Q8). This holds for any pin, because the flake resolves `304ed70c`
literally. The concrete shadow path named in Q8 belongs to the
`fixed-compiler-2159c657` snapshot and therefore does **not** transfer to the pin
recorded here; which snapshot the run uses is the re-preparation question this
record does not decide (§0). What is fixed by this record is only that the run
must shadow, not which directory it points at.

**One further measured fact, stated because it changes how the pin must be
read.** The divergence is a property of **which commit** you measure against, and
the remote ref tip no longer has it: a merge that landed on the remote side but
not on the local tip brings `304ed70c` into the remote tip's history.

    $ git merge-base --is-ancestor 304ed70c origin/arch/agent-guided-governance; echo rc=$?
    rc=0
    [rc=0]

    $ git merge-base 304ed70c arch/agent-guided-governance
    378dfdbf8313206e68a074b80cb381fd83293cbc
    [rc=0]

    $ git merge-base --is-ancestor 304ed70c arch/agent-guided-governance; echo rc=$?
    rc=1
    [rc=0]

    $ git show -s --format='%H %P %s' aceda352
    aceda352770dfb04bf247b49176d1b6b6107cbba 94eace13c1d1fb2a8e3c80ffa07e56a70f23c68a cc9957dd7f624f4deced5e722d2a57b45e0c2d36 Merge origin/master into ci/collected-suite-failure-attribution
    [rc=0]

    $ git merge-base --is-ancestor 304ed70c cc9957dd; echo rc=$?
    rc=0
    [rc=0]

So `304ed70c` is an ancestor of the remote tip (via merge `aceda352`, whose
second parent `cc9957dd` is `origin/master`) and **not** an ancestor of the
pinned revision or of the local tip (merge base `378dfdbf` for both). Quoting a
ref tip as the pair's Boring side would therefore make the report's own
divergence finding read as false. The declaration in §3.1 is made against the
pinned revision, which is the only reading that is true and checkable. The merge
does not remove the run-time requirement above: an ancestor is still not the
pinned revision, and the flake checks out `304ed70c` literally.

## 4. Every commit-distance number in this record

Each row is one command; the value in the first column is that command's output
alone.

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
| 274 | `git rev-list --count 304ed70c..arch/agent-guided-governance` |
| 299 | `git rev-list --count 304ed70c..origin/arch/agent-guided-governance` |
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

    $ git rev-list --count 304ed70c..arch/agent-guided-governance
    274
    [rc=0]

    $ git rev-list --count 304ed70c..origin/arch/agent-guided-governance
    299
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
  (§1.2); it lives in the Tiqian repository.

## 6. Non-claims

- This record is a **preparation** record. It does not run the P09 matrix, and it
  does not assert that P09 criterion 1 has passed. Criterion 1 asks for a
  *recorded* revision pair; whether the recorded pair is accepted, and whether
  the pair is executable against a prepared snapshot, remain open, and P09
  criteria 2, 3 and 4 remain NOT ESTABLISHED.
- It does not decide whether the staging snapshot is rebuilt or re-prepared
  (`0a5c42a7` has no prepared snapshot per Q4). That decision is out of scope
  here, and nothing in this file should be read as a snapshot ruling.
- It changes no existing ruling and no code: the only file added by this task is
  this one.
