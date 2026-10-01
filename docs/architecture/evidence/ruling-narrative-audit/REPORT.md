# Ruling Narrative Claims Audit — REPORT

**Task**: `t-muorukqg-0pes`
**Audit date**: 2026-09-30
**Auditor**: Main (coordinated seat)
**Branch**: `audit/ruling-narrative-claims` (base `1ae6de72`)

---

Three prose rulings were checked for docs-only (GATE-LEDGER:365–366); this audit
separately verifies their **falsifiable narrative claims** against measurement and
source documents. Each claim is assigned: `confirmed`, `partly-confirmed` (with
conditions), `contradicted` (with conflicting evidence), or `not-verifiable-here`.

---

## A. BUILD-PHASE-DIAGNOSTIC-RULING.md (commit `1a486ebd`)

### A1. Verbatim quote of spec `:78`/`:80`

**Claim**: The ruling's §2.1 quotes lines 78 and 80 of
`docs/specs/style/02-translator-implementation-standard.md` verbatim.

**Verdict**: `confirmed`

**Evidence** — byte-identical comparison:

```
$ sed -n '78p;80p' docs/specs/style/02-translator-implementation-standard.md
1. Generated code compiles without warnings on every target: kotlinc, rustc, the TypeScript compiler, the Dart analyzer, and the Swift type-checker. A translation that produces a warning is an emitter defect with the same severity as a translation that produces wrong output.
3. Acceptance for any emitter change counts the warning lines in the target suite output that name files under the generated trees; the count is zero. A change that replaces a warning with a suppression marker fails acceptance.
```

The ruling §2.1 (lines 70–73 of the ruling file) quotes these identically. `diff` of
the two byte strings is empty (rc=0).

The coordinator's own note in the ruling header independently confirms this
("协调者独立复现了本文的两条承重论断…① :78/:80 逐字引述准确"). My measurement
agrees.

---

### A2. `swiftc -typecheck` reports 0 on baseline; `-c` reports 1

**Claim** (ruling §4.1, §6.3): `swiftc -typecheck` does not run SILGen and reports
0 warnings on the baseline gap fixture; `swiftc -c -whole-module-optimization`
reports exactly 1 warning `will never be executed` at `Gap.swift:117:9`.

**Verdict**: `confirmed`

**Evidence** — my measurement on the baseline gap fixture (current base
`1ae6de72`, which does NOT include `cd70eb12`):

```
$ SWIFTC=/nix/store/f0pa9lppswnls248abfl142s77a99yw4-swift-6.2.4-wrapped/bin/swiftc
$ HAXE=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin/haxe
$ PATH=$PATH:/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin
$ haxe tests/swift-gap-boundary/swift.hxml -D swift-output=$TMP/gen -D swift-test-output=$TMP/tests
  rc=0
$ swiftc -typecheck $TMP/gen/gap/Gap.swift $TMP/gen/Runtime.swift $TMP/gen/std/UStringException.swift $TMP/gen/std/UStringFault.swift
  rc=0  (stderr empty — 0 B)
$ swiftc -c -whole-module-optimization $TMP/gen/gap/Gap.swift $TMP/gen/Runtime.swift $TMP/gen/std/UStringException.swift $TMP/gen/std/UStringFault.swift -o $TMP/gap.o
  rc=0
  stderr:
    gen/gap/Gap.swift:117:9: warning: will never be executed
    115 | return ReadOnlyArray(Gap.sourceSecond())
    116 | }
    117 | return ReadOnlyArray(Gap.sourceFirst())
        | `- warning: will never be executed
    118 | }
    119 | }
  shape count = 1 (exactly)
```

- `-typecheck` stderr: 0 B (0 warnings). SILGen is not run; the `will never be
  executed` diagnostic is invisible to this command.
- `-c -WMO` stderr: exactly 1 diagnostic at `Gap.swift:117:9`.

The S1 REPORT §2.5 independently confirms the same: "swiftc -typecheck … rc=0, 0 B
stderr on the BASELINE too — it cannot see this diagnostic at all".
`dc-warn/out/p08-s1/evidence/trap2-typecheck-baseline.stderr.log` is empty (0 B).

*Side observation*: the coordinator note in the ruling header says "两态产物均为
278824 B" for the object file size. The evidence files
(`baseline-gap.o`, `after-gap.o`) are both 278824 B. My generated object was
278288 B. The 536-byte difference is explained by generation from a different base
commit (`1ae6de72` vs the S1 branch base `5a8f19e6`), not a measurement error.
This does not affect the diagnostic-count claim.

---

### A3. S1 (`cd70eb12`) makes diagnostic 1 → 0

**Claim** (ruling §6.3, coordinator note): S1 ("after") build emits 0 diagnostics
vs baseline 1.

**Verdict**: `confirmed`

**Evidence** — shape-counted from the archived evidence logs:

```
$ grep -cE '^[^ ]+\.swift:[0-9]+:[0-9]+: (warning|error):' \
    dc-warn/out/p08-s1/evidence/baseline-build.stderr.log
1

$ grep -cE '^[^ ]+\.swift:[0-9]+:[0-9]+: (warning|error):' \
    dc-warn/out/p08-s1/evidence/after-build.stderr.log
0
```

The trap (caret-line overcount) is confirmed:

```
$ grep -c 'warning:' dc-warn/out/p08-s1/evidence/baseline-build.stderr.log
2
```

The baseline log contains:
```
gen/gap/Gap.swift:117:9: warning: will never be executed
115 |                 return ReadOnlyArray(Gap.sourceSecond())
116 |         }
117 |         return ReadOnlyArray(Gap.sourceFirst())
    |         `- warning: will never be executed
```

The `grep -c 'warning:'` returns 2 because Swift also emits a caret line
containing the word `warning:` — the naive count would have made a correct fix
look like a false claim. This is the exact trap GATE-LEDGER:364–366 warns about.

The `after-build.stderr.log` is empty (0 B, both shape-count and naive-count = 0).

---

### A4. P08 boundary — NOT PASSED / REJECTED, no S1 nomination

**Claim** (task A4): The ruling explicitly writes that P08 status remains
NOT PASSED / REJECTED and that downstream must not nominate S1 based on this
document. It does NOT overclaim the authority to unilaterally change P08 status.

**Verdict**: `confirmed`

**Evidence** — verbatim quote from the ruling header (coordinator note):

> **尚未主张**：本裁定对 P08/S1 验收口径的效力须经管理层确认后才算定案；在获得该确认前，
> 下游不得据本文改变 P08 状态（维持 NOT PASSED / REJECTED，最终）或提名 S1。

And §5 point 1:

> 已封存候选 `c8ae0054` 维持 **P08 NOT PASSED / REJECTED** 裁定，不得翻案或追溯修改。

And §8 point 1:

> 确认 Management Ruling 245 决议有效且不可撼动。`c8ae0054` ... 其 **P08 NOT PASSED /
> REJECTED** 为终局状态。不得通过重新解释口径试图为其"翻案"或免检。

The ruling explicitly says it does NOT have independent authority over P08 status:
"须经管理层确认后才算定案" (requires management confirmation to take effect).
It does NOT claim to override MANAGEMENT-RULING-245. The boundary is correctly
written.

---

## B. MANAGEMENT-RULING-137.md (commit `46b83a20`)

### B1. Four operative points vs SOL-REVIEW-137 source

**Claim**: The ruling's four operative points faithfully transcribe SOL-REVIEW-137
without weakening or strengthening.

**Verdict**: `confirmed`

**Evidence** — point-by-point comparison:

| # | SOL-REVIEW-137 (Chinese source) | MANAGEMENT-RULING-137 (English) | Assessment |
|---|---|---|---|
| 1 | 条件 3：核可。状态使用 EXERCISED (SYNTHETIC FLAKE-SHAPED INPUT; NO REAL FLAKE OBSERVED)。保留 "No real flake was observed, and none is claimed" 以及证据自身关于真实渲染方法和本机无法再次调起 bun 1.3.13 的限界。条件 3 的实现与该证据均已随主线连续历史合入；不得将其表述为观察到真实 flake。 | Contract 3 condition 3: APPROVED. The status is to be written exactly as EXERCISED (SYNTHETIC FLAKE-SHAPED INPUT; NO REAL FLAKE OBSERVED). Keep the wording "No real flake was observed, and none is claimed", and keep the evidence's own limitation about the real-rendering method and the inability to re-invoke bun 1.3.13 locally. The implementation and that evidence are merged onto the line and are approved; it must never be described as having observed a real flake. | Exact. "不得将其表述为观察到真实 flake" → "must never be described as having observed a real flake". |
| 2 | 条件 4：仍未满足。继续保持既有裁定：P08 可准备、不可提名。条件 1–3 已合入主线不改变这一点；不得因开始准备而暗示 P08 已具备提名资格。 | Contract 3 condition 4: STILL NOT SATISFIED. The standing ruling holds: P08 remains PREPARABLE, NOT NOMINATE-ABLE. Conditions 1-3 being merged does not change this, and beginning preparation must not be used to imply P08 is now nomination-eligible. | Exact. "可准备、不可提名" → "PREPARABLE, NOT NOMINATE-ABLE". |
| 3 | R2/R3 证据包：核可当前不入库三个 tar。在提交、README、校验和及可再生命令已足以逐字节复核，且已实测三项 git archive --format=tar <commit> \| sha256sum 一致的前提下，不要求补提 tar。除非后续发现再生条件、校验或独立性声明失效，否则不补提。 | The R2/R3 evidence package: not committing the three ~32MB tars is APPROVED. Given that the commits, the README, the checksums and the regeneration commands already suffice for byte-level re-verification — and that three git archive --format=tar <commit> \| sha256sum comparisons were measured identical — the tars are not to be committed. This holds unless regeneration conditions, the checksums, or the independence claim are later found to be invalid. | Exact. The "~32MB" descriptor is the only additional detail — not a weakening or strengthening of the ruling itself. |
| 4 | 陈旧板行可继续等待其基线上剩余预算类超时的逐名裁定，不因已由 40cf0ad0 覆盖而重复执行。 | Stale board rows may continue to wait for the per-name adjudication of the remaining budget-class timeouts on their baseline; they are not to be re-executed merely because 40cf0ad0 already covers the premise. | Exact. |

**Minimum action section** — also matches exactly:

| Source | Ruling |
|---|---|
| 仅开始准备 P08 新候选材料，明确标注"可准备、不可提名"，并补齐/验证条件 4；在条件 4 满足并获后续明确裁定前，不得提名、宣布通过或改变其状态。 | Begin preparing the P08 successor candidate material only, explicitly labelled "preparable, not nominate-able", and close or verify condition 4. Until condition 4 is satisfied and a later explicit ruling says otherwise: do not nominate, do not declare a pass, and do not change its status. |
| 除上述准备与条件 4 的验证外，不新增实现、测试、证据归档或历史改写。 | Beyond that preparation and the condition-4 verification: no new implementation, no new tests, no new evidence archiving, and no history rewriting. |

No weakening, no strengthening in any operative point.

---

### B2. "P08 preparable, not nominate-able" matches candidate material

**Claim**: "P08 可准备、不可提名" (= PREPARABLE, NOT NOMINATE-ABLE) as stated in
MANAGEMENT-RULING-137 matches the actual annotation in
`docs/architecture/p08-candidate-material/P08-SUCCESSOR-CANDIDATE-MATERIAL.md`.

**Verdict**: `confirmed`

**Evidence** — the candidate material file (committed as `32f76bd9` in the
`boring-wt-p08prep` worktree, branch `prep/p08-candidate-material`) opens with:

```
# P08 successor candidate — PREPARABLE, NOT NOMINATE-ABLE

**Status marking: PREPARABLE, NOT NOMINATE-ABLE.**
```

This is the exact English rendering of "可准备、不可提名" used by
MANAGEMENT-RULING-137 point 2 and the "Minimum action" section. The file is
committed and tracked (`git status --porcelain` empty in that worktree).

---

## C. GATE-LEDGER.md (incremental commit `73c33200`)

### C1. 37/37 worktree count — recount

**Claim** (GATE-LEDGER:308–311): `dc-warn/worktrees/` has 37 worktrees, all
detached HEAD, all with uncommitted changes, and 0 with commits beyond
`e1c65975`.

**Verdict**: `partly-confirmed` (still holds for git worktrees; count nuance)

**Evidence** — my measurement at audit time (2026-09-30):

```
$ ls -d dc-warn/worktrees/*/ | wc -l
38                          # directory entries

$ for wt in dc-warn/worktrees/*/; do [ -f "$wt/.git" ] && total=$((total+1)); done
total=37                    # actual git worktrees

$ for wt in dc-warn/worktrees/*/; do
    [ -f "$wt/.git" ] || continue
    git -C "$wt" rev-parse --abbrev-ref HEAD  # → "HEAD" for all 37
  done
detached HEAD: 37 of 37

$ git status --porcelain    # run per worktree
with uncommitted changes: 37 of 37

$ git merge-base --is-ancestor HEAD e1c65975  # run per worktree
beyond e1c65975: 0 (spot-check confirmed on all 37)
```

The 38th directory entry is `rust-modkey/`, which lacks a `.git` file
(contains `.envpath` and `.gitattributes` only). It is not a git worktree
and was not counted as one.

| Metric | Ledger claim | My measurement | Diff |
|---|---|---|---|
| Directory entries | (not stated) | 38 | +1 (rust-modkey, non-worktree) |
| Git worktrees | 37 | 37 | 0 |
| Detached HEAD | 37/37 | 37/37 | 0 |
| Uncommitted changes | 37/37 | 37/37 | 0 |
| Beyond e1c65975 | 0 | 0 | 0 |

The ledger's implicit counting was of git worktrees (directories with `.git`
pointers), of which there are exactly 37. My measurement confirms all three
sub-claims at this later time point on the same day.

---

### C2. rc=0 PASS / rc=1 roots-guard claim

**Claim** (GATE-LEDGER:337–340): "deleting the real root `boring.ArraySliceOps`
from `examples/kotlin-f32.hxml` and exempting it with the one-word reason
`because` gives rc=0 PASS on base and rc=1 with a named diagnostic on the
hardened copy."

**Verdict**: `partly-confirmed` — the rc=0/rc=1 behavior is reproducible; a
narrative defect exists.

#### 2a. The rc=0/rc=1 behavior — reproducible

**Pre-hardening base** (`0a5c42a7`'s `check-roots-guard.sh`):
- Reason check: only validates that `reason` is present and non-empty
  (`!e.reason || !String(e.reason).trim()`).
- "because" passes → rc=0, `roots guard: PASS`.

```
$ bash guard-pre.sh sandbox/examples --repo-root=sandbox
EXEMPT: kotlin-f32.hxml may omit boring.ArraySliceOps -- because
...
roots guard: PASS (4 exemption(s) in force)
rc=0
```

**Current hardened base** (`8b32f8a0`, landed from `1cafaa42`):
- Reason check: requires ≥ 4 words, ≥ 24 chars, and passes anti-spam checks.
- "because" is 1 word → rc=1, `roots guard: FAILED`.

```
$ bash tools/roots-guard/check-roots-guard.sh sandbox/examples --repo-root=sandbox
FAIL: allowlist: exempt[3].module boring.ArraySliceOps: reason is too short to be
      an exemption sentence (1 word(s): "because"); need >= 4 words
roots guard: FAILED
rc=1
```

The hardening commit (`8b32f8a0`) is now an ancestor of base. The pre-hardening
base (`0a5c42a7`) is also in base but was superseded by the landing.

#### 2b. Narrative defect — "rc=0 PASS on base" not time-scoped

The GATE-LEDGER text:

> "The two copies reach OPPOSITE verdicts on the same input: deleting the real root
> boring.ArraySliceOps from examples/kotlin-f32.hxml and exempting it with the
> one-word reason "because" gives **rc=0 PASS on base** and rc=1 with a named
> diagnostic on the hardened copy."

The preceding paragraph says the hardened copy is "NOT an ancestor of base", which
implies pre-merge state. However, the sentence "gives rc=0 PASS on base" is in
**present tense** and does NOT carry an explicit "合入前" (pre-merge) time-scope
marker.

**Why this matters**: now that the hardened guard is in base (via `8b32f8a0`), a
reader who checks "rc=0 PASS on base" against the current tree will find rc=1 and
conclude the ledger is factually wrong — when it is merely describing a state
that was true at writing time but is no longer current. The GATE-LEDGER does NOT
explicitly say "at the time of writing" or "before the hardening landed" in the
rc=0/rc=1 sentence itself.

**Suggested correction** (not applied — per task rules, ruling text is not modified here):

After "gives rc=0 PASS on base", add "(at the time of this observation, before
the hardening landed as `8b32f8a0`; the current base now gives rc=1)".

Or more tersely: change "gives rc=0 PASS on base" to "at that revision gave rc=0
PASS on the base copy (0a5c42a7, before the hardening landed)".

---

## Summary

| Claim | Verdict |
|---|---|
| A1. Spec :78/:80 verbatim quote | `confirmed` |
| A2. `-typecheck` = 0, `-c` = 1 on baseline | `confirmed` |
| A3. S1 diagnostic 1 → 0 | `confirmed` |
| A4. P08 boundary written, no overreach | `confirmed` |
| B1. Four-points match SOL-REVIEW-137 | `confirmed` |
| B2. Candidate material annotation match | `confirmed` |
| C1. 37/37 worktree recount | `partly-confirmed` — still 37 git worktrees; 38th dir is non-worktree |
| C2. rc=0/rc=1 roots-guard repro | `partly-confirmed` — behavior reproducible; narrative defect: no explicit "合入前" time-scope on rc=0 claim |

---

*Audit conducted in worktree `boring-wt-rulingaudit` on branch `audit/ruling-narrative-claims`
(base `1ae6de72`). No ruling text was modified. All destructive experiments were
performed in `/tmp` and cleaned up.*