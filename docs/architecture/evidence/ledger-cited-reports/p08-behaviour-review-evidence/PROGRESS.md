# P08 BEHAVIOUR review — progress (staged, updated 2026-09-30T02:28-04:00)

Reviewer role: BEHAVIOUR reviewer (one of the two separately recorded reviews required
by the P08 acceptance condition, `docs/architecture-work-plan.md:216`).
No repository file modified. All executed evidence under `evidence/`.

## Anchors (measured by me, not quoted)

| artifact | anchor |
|---|---|
| coordination tree | `boring-wt-architecture`, HEAD `e1c6597514634fd347d392709793cc19bd96c9a2`, dirty (11 M + 8 ?? entries; `evidence/repo-status-before.txt`) |
| code under review | `SwiftArrayBoundary.hx` 264 lines; `SwiftExpr.hx` 7001; `SwiftDecl.hx` 1207; `SwiftParameterPlan.hx` 169 |
| `boundary-policy-record/RECORD.md` | **367 lines, sha256 `4d34899236b9db0d84cc97637f13930d42c299435fd57c3ca01a82223cb63dd7`**, mtime shown 2026-09-30 02:10 |
| `switch-try-gap-verify/REPORT.md` | 260 lines |
| gap fixture | `gap-fixture-archive/fixture/gap/Gap.hx` sha256 in `evidence/fixture-hash.txt` |

**Anchor warning (for the dispatcher).** The dispatch quoted RECORD.md at **sha `e20cf625…`**.
I could not reproduce that hash: at my measurement the file is **367 lines / `4d348992…`**.
It also changed *during* this session (my first read returned 362 lines with the old
`switchReturn` misattribution; the 367-line revision has line 184 and CORRECTION 3
(:255-261) fixed and now names its provenance, `boundary-review-glm/REPORT.md:19` ->
`external-consult-xcheck/REPORT.md`). All my RECORD citations are pinned to
`4d348992…` / 367 lines. **Any review that quotes the record must pin a hash; the file
is not frozen.**

## Six-question status

| Q | topic | status | evidence state |
|---|---|---|---|
| 1 | source semantic rule + forms in scope | **ANSWERED** | code-verified: shared-storage wrap / copy rules, `SwiftRuntime.hx:384` vs `:486`, `:500`; classifier `SourceContainerAnalysis.hx:44-126`, `SourceContainerAnalysisFace` 237-242 |
| 2 | fact required per boundary, producer, lifetime, invalidator | **ANSWERED** | code-verified; the "one producer per fact" claim is **false** (I count >=6 `sourceStorage` producers, 2 optionality producers, 5 presence producers); only one recorded/lifetime fact exists, `localArrayBindingStorages` (`SwiftExpr.hx:160`, written `6173-6175`, read `2683`) |
| 3 | consumption at every producer/consumer path (own census) | **ANSWERED** | own census in `evidence/census.txt` (mechanical grep, 99 lines); record omissions and two record-internal contradictions identified |
| 4 | source meaning / target representation / operation result / printed syntax distinct | **ANSWERED** | code-verified: distinct *inside* `SwiftArrayBoundary.hx`; >=5 live conflations outside it (2048 text-parse, 1203/1966/5525 AST-typed closures, 4349-4355 AST-typed wrap, 5492-5515 text re-targeting) |
| 5 | discriminating observation for the single-axis trap | **ANSWERED, with executed evidence** | two-axis formulation; both axis-isolating checks named and their run-status verified (one is collected by nothing in the repo) |
| 6 | unknown / intentionally-unsupported set | **ANSWERED** | decision-vs-omission classification per item |

## Extra executed evidence obtained (beyond the dispatch's "known" list)

1. **Reproduced the gap fixture myself**: generation rc=0, `Gap.swift` sha256
   `01cbbb8193f73c095eb05a24c8874e7366399194e8bd607ec9e50073779b227b` (byte-identical to
   the archive), `swiftc -typecheck` **rc=1, 12 errors / 2 warnings**
   (`evidence/swiftc-gap.log`, `evidence/gap-swift-hash.txt`, `evidence/tree-diff-vs-archive.txt`).
2. **Localised the `SwiftExpr.hx:2609` blocker** that the dispatch called "a known separate
   blocker" — it is **not separate**. Instrumented shadow (`-cp` last-wins, shadow only in my
   out dir) prints: `class=ReadOnlyBoundaryOps field=coalescedBoundary ret=String
   local=values#36447 dest=ReadOnlyArray<Int32> srctype=TiqianArray<Int32>?
   storage=MutableArrayWrapper opt=OptionalOperand presence=NoPresenceProof`
   (`evidence/gen-ro-probe6.log`). Neutralising that one function makes generation
   **rc=0** (`evidence/gen-bisect-coalesced2.log`). Cause = the record's **REFUSED** cell
   `MutableArrayWrapper x read-only x optional source -> required dest`
   (`SwiftArrayBoundary.hx:203` -> null plan -> `SwiftExpr.hx:2608-2609`) — i.e. the repo's
   own acceptance fixture demands a cell the mechanism refuses, and its plan-check macro
   never tests that sub-cell (it only tests the nullable-destination variant,
   `SwiftBoundaryPlanChecks.hx:76-88`).
3. Repo-untouched proof: `evidence/repo-status-before.txt` == `evidence/repo-status-after.txt`
   (`evidence/repo-status-diff.txt` empty, diff rc=0).

4. **CI does not collect the acceptance fixture at all.** [CODE] `.github/workflows/ci.yml`
   invokes only `test:*` scripts (`:35`, `:135`, `:199`) and never `bun run test`; the fixture is
   collected only by `package.json:9` (`"test": "bun test tests/ packages/registry/tests/"`), and
   it appears in no SwiftPM target path (`Package.swift:47,54,61,68,75,82,92`). The archive's
   claim that CI runs `bun test tests/` (`gap-fixture-archive/README.md:163-167`) is contradicted
   by the CI file. So **both** Q5 observations are currently unenforced in CI.

## Status

- `REPORT.md` **written** (six answers, own census, Q5 two-axis observation, Q6 decision-vs-omission
  set, §8 "what I could not determine", §9 claim ledger).
- All six questions answered.
