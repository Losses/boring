# P08 RE-FREEZE RECORD

> **SUCCESSOR FREEZE → `docs/architecture/REFREEZE-SUCCESSOR.md`**（R3.2，2026-10-01）：
> 后继候选的冻结记录，冻结修订 `649aa881`。本文件冻结的 `c8ae0054` 仍是且仅为被封存
> 的前候选身份记录，不受后继冻结影响。

> **SUPERSEDED — 本记录的候选已被封存否决（指引，2026-10-01；正文以下逐字未改）**
>
> 本记录冻结的候选 `c8ae0054` 已被 round-245 管理层裁定 **P08 NOT PASSED / REJECTED,
> finally，封存**（`docs/architecture/MANAGEMENT-RULING-245.md`）：不得重开评审、不得
> 修补、不得据其推进 P08。本记录**仅作为历史身份记录保留**——它冻结的那棵树现在
> 恰是「被封存的前候选」，不能再作为任何评审或 pin 的对象。
>
> 后继候选状态：**PREPARABLE / NOT NOMINATE-ABLE**
> （材料：`docs/architecture/p08-candidate-material/P08-SUCCESSOR-CANDIDATE-MATERIAL.md`，
> 该文件不受本指引影响）。后继候选的**声明与冻结另见**
> `docs/architecture/P08-SUCCESSOR-DECLARATION.md`——该文件定稿并冻结之前，
> P08 后继候选**不存在**可指对象的 revision。

**Candidate revision: `c8ae0054`** — `fix(swift): lambda return contract, with the block
destination it exposes` (2026-09-30 13:41:26 -0400).

**Frozen at:** 2026-09-30T14:03-04:00 (America/Toronto).

**What this record is:** an *identity* record. A management review ruled that the frozen
P08 candidate (superseded: `dc-warn/out/p08-candidate-freeze/FREEZE.md`, which froze an
uncommitted scratch patch) no longer represents current execution output, and that a
re-freeze may proceed. This record establishes a new candidate identity so that later
independent reviews target one addressable revision.

**What this record is NOT:** it is **not an acceptance gate**. Nothing here accepts P08.
P08 remains NOT PASSED per `docs/architecture/GATE-LEDGER.md` (P08-2 FAIL on a build-phase
diagnostic; P08-4 FAIL on the absent second independent review). Committing and freezing
are not accepting (`work-plan:93-94`).

Provenance marks: **[MINE]** = I computed or executed it in this session; **[INHERITED]**
= taken from a named retained source and labelled as such. The two are never blended.

---

## 1. The candidate revision and its parent chain [MINE]

Pinned by `git rev-parse` in the coordination tree
`/home/losses/Development/tq-workspace/boring-wt-architecture`
(full output: `evidence/01-revision-pins.txt`):

| revision | full hash | subject |
|---|---|---|
| **candidate** | `c8ae0054d8b1937cf05c0dd849c268807ae19b8f` | fix(swift): lambda return contract, with the block destination it exposes |
| parent | `28820ff54aa158f42d27f26a47c1f4df682bfee4` | fix(rust): rename the fold-debug define off the compiled package name |
| grandparent | `a14345ce61710c91ba987521c323d272fd328e5c` | revert(swift): drop the lambda currentReturnType seeding, keeping W1 |
| candidate tree | `3c5d977eb1657cf8e29f50da8b700bea44701c15` | `c8ae0054^{tree}` |

`c8ae0054` **is an ancestor of the current HEAD** `d14231a6211a1903bd7a7f67a6297db1d24d7709`
on branch `fix/test-collection-ignore-out` (verified with `git merge-base --is-ancestor`).
The chain `a14345ce` → `c8ae0054` is the integration ruling's option (b): the lambda
`currentReturnType` seeding was reverted, then re-landed as one atomic commit together
with the `blockExpression` repair that makes it correct.

File identities at the pinned revisions [MINE, `git show <rev>:<path> | sha256sum`]:

| file | at `c8ae0054` | bytes |
|---|---|---|
| `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` | `22fd243c044ca8c3b149c8d7c743476f088fd21cf6c375e79d3d6c3738aceef5` | 333878 |
| `tests/swift-gap-boundary/gap/Gap.hx` | `150315585b0a4aee5df5d1f9f24e217a2c5f747717aa6161eb1032769b057048` | 4197 |
| `tests/swift-gap-boundary/swift.hxml` | `87be97b5393eea5bbba9b87d0082c6378c282bc6153b304e047418798fdc7800` | 646 |
| `tests/swift-gap-boundary/gap-boundary.test.ts` | `8dd13985e410980acaa393634a22cb6202b8361866959db2fca5a7399d04fe40` | 6271 |

`SwiftExpr.hx` at the parent `a14345ce` hashes `7d7f31e5f51c835c412d2fc9dffbcfe4afb51f0b1d681eec4b378ee2dbea4532`
— the candidate differs from its parent exactly in this compiler file (plus the Rust rename
in `28820ff5`, which is outside the Swift backend). The gap fixture source `Gap.hx` is
byte-identical to the archived counterexample fixture hashed in the superseded FREEZE §3.1.

---

## 2. W1's `[#no-usage]` warnings are gone [MINE, plus named retained sessions]

**My own measurement at the frozen revision [MINE].** I exported a clean tree of exactly
`c8ae0054` (`git archive c8ae0054` into `/tmp/refreeze-c8ae`, no working-tree edits — the
live worktree carries unrelated uncommitted `SwiftExpr.hx` edits), generated the gap
fixture with the pinned toolchain (haxe 4.3.7, `HAXELIB_PATH` per
`dc-warn/out/chainA-fixed-rerun/evidence/env.json`), and typechecked:

- generation rc=0, empty stderr (`evidence/gen.stderr` is 0 bytes);
- generated `gap/Gap.swift` sha256 **`8f66594fb51263aee633ee6769cb91d043ffc05398eab489b066410d624b1bc0`**
  (`evidence/03-generated-identities.sha256`; runtime files match the archived identities
  `a24d5fa3…` / `ca9b2487…` / `36499cfb…` from the superseded FREEZE §3.1 — [INHERITED
  hashes, re-confirmed byte-identical by me]);
- `swiftc -typecheck` over the 4 generated files: **rc=0, stderr 0 bytes → 0 errors,
  0 warnings** (`evidence/04-typecheck.status`, `evidence/04-typecheck.stderr`).

The two `[#no-usage]` warnings of the W1 defect (`Gap.swift:113:17` / `:115:17`, retained
pre-fix readings in `dc-warn/out/w1-policy/REPORT.md:20` and `w1-policy-xcheck/REPORT.md:113-119`
[INHERITED]) are absent from the frozen revision's output.

**How it was measured, and by whom — three prior independent sessions [runs and logs
re-verified by me; the seat attribution is INHERITED from `GATE-LEDGER.md:19`
("three independent sessions measured 0/0 on the fixture [MINE + 2 seats]")]:**

1. **The W1 fix seat** — post-fix counterexample measurement in `dc-warn/out/w1-fix/`:
   `evidence/gap-fixture-after/gap-typecheck.log` is **0 bytes** (0 errors / 0 warnings),
   with the runtime before/after proof (`run-baseline.out` vs `run-fixed.out`: `.two`
   returned `[1,2]` pre-fix, `[3]` post-fix) showing the semantic defect, not just the
   warnings, was repaired.
2. **The collection seat** — retained fixture run
   `out/swift-gap-boundary/test-d9311426-191a-48c9-b87b-48ab21a29ff0` (13:40:19, at
   candidate time): `typecheck.status=0`, `typecheck.stderr.log` 0 bytes (`evidence/06-fixture-runs.txt`).
3. **The fixture-repair seat** — retained runs `test-ab05489b` (13:51) and
   `test-9f15c47f` (13:57): both `typecheck.status=0`, stderr 0 bytes.

My own clean-`c8ae0054` regeneration is an independent fourth confirmation, taken at the
frozen revision itself rather than on a moving tree.

---

## 3. The one remaining diagnostic: `swiftc -c` at `Gap.swift:117` — FAIL / unwaived deviation

**[MINE]** On the same clean-`c8ae0054` generated tree:

```
$ swiftc -c -whole-module-optimization gap/Gap.swift Runtime.swift \
      std/UStringException.swift std/UStringFault.swift -o gap.o
gap/Gap.swift:117:9: warning: will never be executed
115 |                 return ReadOnlyArray(Gap.sourceSecond())
116 |         }
117 |         return ReadOnlyArray(Gap.sourceFirst())
    |         `- warning: will never be executed
```

rc=0, object produced (278 288 bytes) — and **exactly one code diagnostic**
(`evidence/05-swiftc-c.stderr`, `evidence/05-swiftc-c.status`). The toolchain is Swift
6.2.4 (swift-6.2.4-RELEASE), x86_64-unknown-linux-gnu; the shim's host-side
`libc not found` line is a host/SDK state message, not a diagnostic about generated code.
(The `-whole-module-optimization` form is required: plain multi-file `swiftc -c -o`
rejects the invocation outright — see §5.)

**Classification: FAIL / unwaived deviation — explicitly NOT a baseline waiver.**
- `docs/specs/style/02-translator-implementation-standard.md:78` — generated code compiles
  "without warnings on every target", and a warning is "an emitter defect with the same
  severity as a translation that produces wrong output".
- `:80` — "Acceptance for any emitter change counts the warning lines in the target suite
  output that name files under the generated trees; the count is zero."
- The round-145 gate-owner ruling (recorded in `tests/swift-gap-boundary/gap-boundary.test.ts`
  at HEAD and in `GATE-LEDGER.md:19`): a **build-phase diagnostic COUNTS** against :78/:80.
- `work-plan:417` (via GATE-LEDGER): a baseline finding "does not waive the standard".

Accordingly `GATE-LEDGER.md` P08-2 is **FAIL** on this diagnostic [INHERITED, consistent
with my measurement], and this freeze records it as an open, unwaived deviation. The
warning points at W1's unreachable trailing return — the faithful rendering of a Haxe
statement that is dead in the source (both switch arms return); the analysis and the
"do not fold into W1" adjudication are in `dc-warn/out/w1-fix/REPORT.md` §4 [INHERITED].

## 4. The stated goal remains zero diagnostics under `-c` as well

The goal has not been relaxed. It remains **zero diagnostics under `swiftc -c`**, exactly
as stated in the fixture at HEAD (`tests/swift-gap-boundary/gap-boundary.test.ts:57-75`)
and in `GATE-LEDGER.md:19`: the `-c` row is a recorded, asserted, unwaived deviation —
asserted *present* precisely so the count cannot rot silently — and the final goal stays
zero. Nothing in this freeze downgrades, allowlists, or waives it.

## 5. Caveat — the fixture's own automated `-c` check does not exist at the frozen revision

Stated plainly so the record cannot imply a working automated check that does not exist:

- **At `c8ae0054`, `gap-boundary.test.ts` contains no `swiftc -c` invocation at all**
  (grep for `"-c"` = 0) — it typechecks and records the `-c` deviation in a comment only
  (`evidence/02-file-identities.txt`, `evidence/07-fixture-caveat.txt`).
- A `-c` step was added afterwards and was **broken in its first form**: retained run
  `test-ab05489b` (13:51) shows `build.status=1` with stderr `error: cannot specify -o
  when generating multiple output files`, **zero recorded warnings, no object file — and
  the run was treated as passing**. This is exactly the caveat the re-freeze was told to
  check; it is real, and it is retained as evidence.
- The fix landed as HEAD `d14231a6` ("fix(test): make gap-boundary swiftc -c invocation
  valid and assert its outcome", 13:57:32). The current form is genuinely discriminating:
  run `test-9f15c47f` records `build.status=0`, a 278 288-byte `gap.o`, exactly one
  pending diagnostic, and both failure-mode probes correctly return 1.

**Consequence:** the working automated `-c` assertion belongs to `d14231a6`, a *later*
revision than the one this record freezes. All `-c` facts in §3 above are **my direct
measurements**, not fixture output at `c8ae0054`.

## 6. Binding effect — subsequent P08 reviews target THIS revision

Any subsequent P08 review — the second independent acceptance that P08-4 requires — must
target **`c8ae0054d8b1937cf05c0dd849c268807ae19b8f`** as pinned in §1, not any scratch
tree, not the superseded `FREEZE.md` object (a dirty working tree plus `INTEGRATION.diff`,
now obsolete), and not the moving working tree of `fix/test-collection-ignore-out`, which
currently carries uncommitted `SwiftExpr.hx` edits. Reviews should verify they are on the
pinned revision with `git rev-parse` and the file identities in §1 before judging.

---

## 7. Honest limits — what this freeze does NOT establish

1. **No acceptance.** P08 stays NOT PASSED (GATE-LEDGER): the `-c` diagnostic (§3) and the
   absent second independent acceptance on a frozen revision (P08-4) remain open blockers.
2. **Scope of measurement.** I measured the gap counterexample fixture only (generation,
   `-typecheck`, `-c`). I did not rebuild or re-run the acceptance fixture
   (`tests/swift-readonly-boundary/`), the route fixtures, other targets (Kotlin/Rust/TS/Dart),
   or the compiler's own test suite at this revision. The 0/0 acceptance-fixture readings
   and the branch-discrimination repair (`d1180768`) are [INHERITED], not re-measured.
3. **Inherited evidence.** The three prior 0/0 sessions (§2) are retained logs I re-read,
   not runs I executed; the seat attribution wording is inherited from the ledger. The
   runtime before/after proof for W1 is inherited from `w1-fix/REPORT.md`.
4. **The fixture's `-c` gap (§5).** At the frozen revision there is no working automated
   `-c` assertion; the repaired one lives at a later commit.
5. **Lazy effects never measured** (GATE-LEDGER P08-3, F3) — unchanged by this freeze.
6. **Tree state.** The freeze is the *commit* `c8ae0054`, reproducible by `git archive`;
   it is not a pin of any working tree, and the coordination tree currently holds
   uncommitted edits beyond it.
7. **Toolchain identity** (Swift 6.2.4, haxe 4.3.7, `HAXELIB_PATH`) is the pinned chain-A
   environment; the shim's host-side libc warning is environmental, not a code diagnostic.

*Raw evidence: `evidence/01-revision-pins.txt`, `02-file-identities.txt`,
`03-generated-identities.sha256`, `04-typecheck.{status,stderr}`, `05-swiftc-c.{status,stderr}`,
`06-fixture-runs.txt`, `07-fixture-caveat.txt`, `gen.{stdout,stderr}`.*
