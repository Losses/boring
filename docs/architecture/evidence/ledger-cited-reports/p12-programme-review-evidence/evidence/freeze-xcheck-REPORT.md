# FREEZE XCHECK — independent cross-verification of the p08 candidate freeze record

Target: `dc-warn/out/p08-candidate-freeze/` (FREEZE.md + REPORT.md + evidence/).
All work in `/tmp/freeze-xcheck` copies and this output dir. Nothing under the
coordination tree, the worktree, the patch, or any test was modified.

**Timeline note.** At the start of this session (03:49–03:50) the record did not
exist (verified: no dir, no `FREEZE*.md`, no references —
`evidence/xfreeze-search.log` shows the late re-scan catching its appearance).
It was written in parallel between 03:55 and 04:01 (evidence file mtimes;
`00-frozen-at.txt` = 2026-09-30T03:55:40-04:00). My independent recomputation was
performed both before and after its appearance; every "mine" value below is from
my own runs (haxe 4.3.7, Swift 6.2.4 shim, git 2.55.0, GNU patch 2.8, PATH from
`chainA-fixed-rerun/evidence/env.json`, haxe cwd = tree root), never read from the
record.

---

## 1. Per-hash cross-verification (record states → I recompute)

Legend: **MATCH** = my recomputed value equals the record's stated value.

| # | Object (record §) | Record states | My recomputation | Verdict |
|---|---|---|---|---|
| 1 | Coordination tree HEAD (1.1) | `e1c65975…c9a2` | `e1c6597514634fd347d392709793cc19bd96c9a2` | **MATCH** (incl. subject "merge: integrate fix/rust-readonly-alias-emitter (0701762d) into Rust fix candidate" and date 2026-09-29 12:32:46 -0400) |
| 2 | Dirty count (1.1) | 25 = 15 M + 10 ?? | 25 = 15 M + 10 ?? (`evidence/xgit-status-coord.txt`) | **MATCH** |
| 3 | Base tree content hash (1.1) | `986807b2…301e`, 5440 files | `986807b22188952e8cd469907cc1407ab0b4378af748322f0f8344d0a43e301e` from the LIVE tree (5440 files) | **MATCH** — my manifest line-identical to record evidence `08-coord-tree-content.sha256` (diff rc=0) |
| 4 | Candidate tree content hash (1.1) | `b75c8c0f…5262` | `b75c8c0f2470aa620a1945f874b96a8bf023eb31eb38c56066c013f956cf5262` from MY patched /tmp copy (5440 files) | **MATCH** |
| 5 | One-line tree delta (1.1) | SwiftExpr.hx `0a9bed91…→bf7dde2c…` | diff of the two manifests = exactly 1 line, that line | **MATCH** |
| 6 | `INTEGRATION.diff` (1.2) | `e67ab1a4…03a3c` (10831 B) | `e67ab1a47de29432671394604b551af05945f3609a2a1ee6efa9bedbf2d03a3c` | **MATCH** |
| 7 | Diff shape (1.2) | 13 hunks, 1 file, +55/−15 | `git apply --numstat` = 55/15; 13 hunks; 1 file | **MATCH** (record explicitly corrects the manifest's +54) |
| 8 | `MANIFEST.md` / integration `REPORT.md` (1.2) | `fa308254…cb2` / `a799f533…7fe` | identical | **MATCH** |
| 9 | `SwiftExpr.hx` base (1.3) | `0a9bed91…33f0`, 328711 B, blob `19b73f18…` = HEAD blob | identical (size 328711; blob `19b73f18d373e8bf468f2f276094e6ef96ca0536`) | **MATCH** |
| 10 | `SwiftExpr.hx` candidate (1.3) | `bf7dde2c…78`, 331720 B, blob `e6e5c2a3…` | identical | **MATCH** |
| 11 | `PATCH.diff` (2) | `7b10df6e…fe86b`; NOT byte-identical to INTEGRATION.diff; 70 sign-line multisets identical | hash identical; bytes differ (headers); 72 sign lines each = 70 content + 2 headers; content multisets identical (only header lines differ) | **MATCH** |
| 12 | Gap `Gap.hx` / `swift-archived.hxml` (3.1) | `15031558…7048` / `72624696…5ad3de` | identical | **MATCH** |
| 13 | Archive `FILES.sha256` self-check (3.1) | 51 OK, 0 FAILED | `sha256sum -c` = 51 OK | **MATCH** |
| 14 | PRE-patch generated `gap/Gap.swift` (3.1) | `01cbbb81…27b` | REPRODUCED by fresh generation on a pristine /tmp base copy (gen rc=0): `01cbbb8193f73c095eb05a24c8874e7366399194e8bd607ec9e50073779b227b` | **MATCH** |
| 15 | CANDIDATE generated `gap/Gap.swift` (3.1) | `2be5e102…02ab` | REPRODUCED by fresh generation on MY patched copy (gen rc=0): `2be5e102d695146439d3fdab3c1aeee7f8096d7d1460b92fd9535055c70c02ab` | **MATCH** (and the record's cross-check file `/tmp/p08ir/out/gap-fixed/gap/Gap.swift` also hashes `2be5e102…` — verified directly while it still existed) |
| 16 | 7 acceptance fixture inputs (3.2) | `11511b36…/edcdf4f5…/12d5a005…/789f42d7…/c1b6abcd…/1fe2f482…/e8912071…` | all 7 identical in the coordination tree AND in the worktree copy | **MATCH** |
| 17 | 21 route-fixture files (3.3) | hashes in `03-fixtures.txt` | full-dir recomputation: diff vs expected list rc=0 (21/21) | **MATCH** |
| 18 | Toolchain (3.4) | `env.json` `c221c6f7…9e52`; swiftc shim `d5842a5d…221` | identical | **MATCH** |
| 19 | Governing `RECORD.md` (4) | `9886fe25…5b24e`, 390 lines, 26384 B, mtime 03:06:50 | all four identical | **MATCH** |
| 20 | `p08-behaviour-review/REPORT.md` (5.0) | `27d54a3f…80e61a`, 577 lines | identical (577 lines) | **MATCH** |
| 21 | `armlines-separability/REPORT.md` (5.0) | `c159ea34…1641d` | identical | **MATCH** |
| 22 | `branch-expectation-ruling/REPORT.md` (5.2) | `cd110bed…f513` | identical | **MATCH** |
| 23 | `ASTRA-ANSWER.md` (0) | `9beeeaea…677f`; quote at :22 | identical; the quoted freeze obligation is at line 22 verbatim | **MATCH** |
| 24 | `SOL2-ARCH-ANSWER.md` (0/07) | `5b53acad…d4` | identical | **MATCH** |
| 25 | `architecture-work-plan.md` (07) | `e5093e7b…30c2`; quote at :216-217 | identical; P08 line at 216-217 verbatim | **MATCH** |
| 26 | `SwiftParameterPlan.hx` / `SwiftRuntime.hx` (bundle) | `05f0ae87…2c` / `24af7e84…98` | identical | **MATCH** |
| 27 | Dirty deps `SwiftArrayBoundary.hx` / `SwiftDecl.hx` (bundle) | `b522865c…75` / `0210d207…973` | identical | **MATCH** |
| 28 | `swc-try-fix-wt/REPORT.md` (5.0) | `cd95e27f…f3d8`, mtime 03:04:57 | LIVE: `1778a60d2340e46ab8c7fe167c8c70362ab75a882d29d554bed2e41209fabe68`, mtime **03:20:48**, 7433 B | **NOT REPRODUCIBLE** — finding F1 (§7) |
| 29 | FREEZE-BUNDLE (6) | `b664c91c…3878` | `sha256sum evidence/06-freeze-manifest.sha256` = `b664c91cd09ba6b80517e809feca90a7995f68b84b81589126fed525da1a3878`; manifest 47 lines, `LC_ALL=C sort -k2 -c` rc=0; **all 47 entries individually re-verified** against live files/HEAD/counts (rows 1–27 above) | **MATCH** |

Result: **28 of 29 stated hashes reproduce exactly; the one miss (row 28) is a
document the record itself labels "NOT the record that accepts this candidate."**

---

## 2. Reproduction (my own runs, exit codes direct, never piped)

Fresh copies: `rsync` of the coordination tree (unpatched `base-copy`, patched
`coord-copy`).

| Step | Mine (rc) | Record claims (02/05) | Verdict |
|---|---|---|---|
| `patch -p1 --dry-run` | **0** | 0 | MATCH |
| `patch -p1` (apply) | **0** | 0 | MATCH |
| `cmp` patched vs worktree SwiftExpr.hx | **0** | 0 (byte-identical) | MATCH |
| `diff -rq` whole tree (patched copy vs worktree) | **0**, 0 entries | rc=0, 0 entries | MATCH |
| gap gen base / candidate | 0 / 0 | 0 / 0 | MATCH (hashes rows 14/15) |
| gap typecheck base / candidate | **1** (12 unique errors at 42,56,58,68,70,79,81,93,129,131,140,142) / **0** (0 errors, 2 warnings @113,115) | same | MATCH |
| `switchExplicitReturn` before/after | byte-identical (diff rc=0) | byte-identical | MATCH |
| oracle (interpreter) | rc=0, 30 lines, `branch-true=1:present` / `branch-false=1:present` | same | MATCH (my log byte-identical to record evidence `11-oracle-acceptance.out`) |
| acceptance gen / typecheck / build / run | 0 / 0 (0 B stderr) / 0 (0 B stderr) / 0 (30 lines) | same | MATCH (my runtime byte-identical to record evidence `12-acceptance-runtime-candidate.out`; record `13-…stderr` = 0 B) |
| route c1/c2/c3 gen + typecheck (candidate) | all gen rc=0 (0 B logs); all typecheck rc=0, **0 errors, 0 warnings** | all 0/0 | MATCH |
| route Ops/Oracle hashes | c1 `9dde20fb…` c2 `10264fb9…` c3 `5f3ea109…` (candidate) ; oracles `8c70d0c1…/11064ace…/da1fa3b8…` (UNCHANGED) | identical | MATCH |
| stale `branch-*` expectation | scoped bun suite rc=**1** at `readonly-boundary.test.ts:55` (`1:1`/`2:1` vs actual `1:present`/`1:present`), pre-existing | disclosed, reproduced | MATCH |
| guard file | 5 `Test.equals` intact everywhere | (n/a) | intact |

Raw logs: `evidence/x*` (index at end).

---

## 3. Obligation audit against the ACTUAL record

### Obligation 1 — handoffs
The record's own scope (§8.2): it does NOT verify the reviewer-side obligations;
it pins the object and supplies the evidence. Factual content I checked:
- route handoffs: c1 (try binding + return), c2 (switch assign + expression +
  return), c3 (switch/enum + null-merge assign + return) all generate and
  typecheck **0 errors / 0 warnings on the candidate** — reproduced by me; the
  author's pre-patch readings (4/2/2 errors) come from the route-fixtures
  evidence (hashes verified, row 17).
- `switchAssign` string-splice: still visible in the patch context lines
  (`targetType != null ? "…" : valueText`) — confirmed by reading the diff;
  the record's statement holds.
- no new IR: the diff adds one `Null<Type>` parameter and one helper, confirmed.
- **caveat stands**: the candidate behaviour depends on uncommitted dirty
  `SwiftArrayBoundary.hx` / `SwiftDecl.hx` — but unlike the earlier
  integration-manifest, **this record pins both by hash (rows 27, 29)**,
  eliminating the earlier "silently excluded dependencies" gap.
**Assessment: the record's factual content is CONFIRMED; the obligation is
correctly scoped as reviewer work it does not claim.**

### Obligation 2 — legal generated output (hard check a)
Record quote (§0, status line): "the *acceptance* is **not complete** …
obligation 2 **fails the literal 'zero diagnostics' requirement**."
Record quote (§5.2): "2 warnings (Gap.swift:113, 115 — the known W1
`switchExplicitReturn` swallowed-`return`; unchanged by the patch)" with
verbatim warning text in `evidence/14-typecheck-gap-candidate.stderr` (874 B;
my re-runs show the same two warnings, same lines, same text) and
`evidence/13-typecheck-acceptance-candidate.stderr` = **0 bytes** (zero
diagnostics on the acceptance fixture — reproduced by me).
**The record acknowledges the two warnings and correctly distinguishes warnings
from errors: yes, explicitly.** It also discloses the gap-archive README's
"zero diagnostics on Gap.swift" wording as the pre-patch "correct state" that
the 2 warnings make inaccurate today (README lines 89–92 read and confirmed).
The MANIFEST's earlier "+54/−15" error is corrected here (55/−15, row 7).
**Assessment: SUFFICIENT and honest.**

### Obligation 3 — preserved source behaviour (hard check b)
What is actually measured (my fresh oracle + binary runs, 30/30 lines
byte-identical to the interpreter oracle and to the record's evidence 11/12):
- **measured**: typed downstream uses (all 30 lines through
  `ReadOnlyArray<Int32>`; hard type errors on cross-type use), null/default
  outcomes (11 lines), shared alias mutation (`alias=7:2`, `effect=1:8:1`),
  single evaluation (`producerCalls` = 1 in `effect=1:8:1`), retained lifetime
  as reference identity (`reference=11:true:17:true`), control exits (branch,
  enum, guarded-return lines execute).
- **NOT discriminating**: the branch pair — `branch-true=1:present` /
  `branch-false=1:present` print identical strings; a backend always taking
  either arm passes every line. The record states this explicitly (§0: "one of
  its named dimensions (branches distinguishable by execution) is not testable
  with the fixture as written"; §5.3/§8.2 cite the ruling's "selects nothing"
  and note Option B is not applied) — quote verified against
  `branch-expectation-ruling/REPORT.md` (hash row 22).
- **conflation (finding F3)**: §5.3 maps "single evaluation / lazy effect"
  jointly to `effect=1:8:1`. The counter measures single evaluation; nothing in
  the 30 lines distinguishes lazy from eager evaluation, and §8.2's
  "I did not verify" list does not name lazy effects.
**Assessment: the record is accurate about what is measured and about the branch
non-discrimination; the only overstatement is the lazy-effect conflation.**

---

## 4. Single-hash assessment

The record's single hash is the **FREEZE-BUNDLE**
`b664c91cd09ba6b80517e809feca90a7995f68b84b81589126fed525da1a3878`
(`sha256sum` of `evidence/06-freeze-manifest.sha256`, 47 sorted entries).

- **Recomputable: yes** — I recomputed it (row 29) and independently resolved
  all 47 entries: 2 implementation files (candidate + base SwiftExpr), 2 dirty
  load-bearing deps (SwiftArrayBoundary, SwiftDecl), SwiftParameterPlan,
  SwiftRuntime, INTEGRATION.diff, 7 acceptance fixtures, gap Gap.hx + the
  pre-patch generated Gap.swift, all 21 route-fixture files (incl. negatives),
  env.json, the swiftc shim, the governing RECORD.md, the 3 consultation/plan
  documents, HEAD, the dirty count, and the two whole-tree content hashes.
- **Coverage claims accurate**: every item §6 says it covers is in the manifest;
  nothing unverified is silently included. Its exclusions are stated honestly:
  it does not cover the verification reports (p08-behaviour-review etc.), its
  own evidence files, or the stale worktree REPORT.md — the last exclusion is
  good, because that file's stated hash no longer matches (F1).
- **Stronger than the diff hash alone**: it pins the dirty dependencies and the
  whole-tree contents, which the `INTEGRATION.diff` hash cannot.
- **Residuals (self-disclosed, §8.3)**: the two typecheck stderr logs and the
  30-line outputs are excluded (re-derivable from the covered inputs), and the
  bundle does not pin the behaviour-review report the reviews will rely on.

**Assessment: a sound, well-formed single hash with accurate coverage claims.**

---

## 5. Falsification attempts (concrete misleading-citation cases)

1. **Stale-hash case (real, found by recomputation)**: a second gate reviewer
   re-running `sha256sum dc-warn/swc-try-fix-wt/REPORT.md` today gets
   `1778a60d…`, not the record's stated `cd95e27f…` (and live mtime 03:20:48 ≠
   stated 03:04:57). The record flags that file as non-authoritative, so the
   freeze object is not undermined — but the stated number itself is
   irreproducible. (F1)
2. **Lazy-effect case**: a reviewer citing the bundle's coverage of "the 30
   runtime oracle lines" plus §5.3's "single evaluation / lazy effect" mapping
   would conclude lazy evaluation is verified. A backend that evaluates eagerly
   exactly once produces the identical 30 lines — the citation passes, the
   claim is unmeasured. (F3)
3. **Branch case (record is immune, the obligation wording is not)**: the
   obligation's "distinguishes both branches" reading is falsifiable by a
   always-`second` ternary (identical `1:present` outputs — reproduced by me).
   The record explicitly withholds this claim and cites the ruling, so a
   careful citation of the record is not misled; a citation of the OBLIGATION
   alone would be.
4. **Drift case (disclosed)**: the governing RECORD.md drifted from the 367-line
   pin the behaviour review used to the 390-line live revision (verified: live
   hash/line count = record's "MEASURED NOW" values; the behaviour review's
   :30 pin of the 367-line revision is visible in that report). A reviewer
   citing review 1's line numbers against the live record reads shifted text.
   The record discloses the full drift chain.

---

## 6. What I could not determine

1. **Why the worktree REPORT.md hash does not match** (F1): live mtime
   03:20:48 predates the freeze (03:55:40), so a stat at freeze time should have
   seen 03:20:48 — the record's 03:04:57 either comes from a pre-03:20
   measurement, a copied value, or stale fuse attribute reporting. Unresolvable
   from here without the author's raw stat.
2. **Earlier RECORD.md revisions** (131/186/279/362/367-line): the drift chain
   is quoted from the consult/review reports (which I hash-verified); the old
   contents no longer exist, so only the 390-line live state is verifiable.
3. **Full `bun test tests/`**: not run (the known guard-file trap in
   `package-artifacts.test.ts`); scoped suite only, in the /tmp copy; guard file
   intact (5).
4. **`/tmp/p08ir` persistence**: verified while present (row 15); it is
   transient /tmp and correctly excluded from the bundle.

---

## 7. Findings

- **F1 — one stated hash irreproducible**: `swc-try-fix-wt/REPORT.md`
  (record: `cd95e27f…`, mtime 03:04:57; live: `1778a60d…`, mtime 03:20:48,
  7433 B). The record itself marks this file "NOT the record that accepts this
  candidate" and excludes it from the bundle; no effect on the frozen object.
- **F2 — line-citation slip**: the OtherArrayStorage REFUSED row is cited as
  `RECORD.md:58`; it is at line **56** (the quoted text itself is verbatim
  accurate). Minor.
- **F3 — lazy-effect conflation**: "single evaluation / lazy effect" mapped to
  one counter line; single evaluation is measured, lazy effects are not
  (absent from §8.2's non-verification list).
- Everything else — all freeze-load-bearing hashes, both reproduction pipelines,
  gap before/after, route fixtures, the bundle, counts, and quotes — is
  independently reproduced byte-for-byte.

---

## 8. Verdict

**CONFIRMED** — the record's substantive claims are independently reproduced:
identity (rows 1–29), reproduction (all direct exit codes), the W1
two-warning disclosure with correct warning/error distinction, the honest
"obligation 2 fails literal zero diagnostics" statement, the explicit
branch-non-discrimination caveat, and the well-formed single hash with accurate
coverage. The verdict carries three named findings: **F1** (one non-reproducible
hash, on a document the record itself disclaims), **F2** (two-line citation
slip), **F3** (lazy effects unmeasured but implied). None of these affects the
frozen object; all three are the kind of thing the two gate reviews should be
handed explicitly.

---

## Evidence index (`evidence/`, this directory)

| File | Content |
|---|---|
| `xfreeze-search.log` | absence search (early) + re-scan showing the record's appearance |
| `xgit-status-coord.txt` / `xgit-status-worktree.txt` | full `git status --porcelain` (25 vs 26 entries) |
| `xgap-gen-base.log` / `xgap-gen-cand.log` | gap generation rc=0 on pristine base / patched copy |
| `xgap-sw04-typecheck.log` / `xgap-fixed-typecheck.log` | gap typecheck before/after (12 errors → 0 + 2 warnings) |
| `xswitchExplicitReturn-before.txt` / `-after.txt` | byte-identical function (diff rc=0) |
| `xoracle-fresh.log` / `xoracle-stripped.txt` | interpreter oracle, fresh patched copy (byte-identical to record evidence 11) |
| `xgen-acceptance-fresh.log` / `xswiftc-acceptance-fresh.log` | acceptance gen rc=0 / build 0-byte log (zero diagnostics) |
| `xacceptance-runtime-fresh.out` / `.err` | binary run 30 lines / 0-byte stderr (out byte-identical to record evidence 12) |
| `xruntime-stripped.txt` | stripped lines; diff rc=0 vs oracle and both archives |
| `xroute-c1/c2/c3-gen.log` / `-typecheck.log` | route fixture re-runs (all rc=0, 0/0) |
| `xbun-scoped-fresh.log` | scoped bun suite (exit 1 at line 55, pre-existing) |
| `fixture-inputs.sha256` / `dirty-deps.sha256` | fixture input + dirty-dep hashes |
| `xtree-base.sha256` / `xtree-candidate.sha256` (+ `xtree-base2.sha256`) | my whole-tree manifests (outer hashes `3099259c…` incl. `.git` file → corrected `986807b2…` = record; candidate `b75c8c0f…` = record) |
