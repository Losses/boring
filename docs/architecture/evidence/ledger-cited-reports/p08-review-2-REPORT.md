# P08 second independent review — frozen candidate `c8ae0054`

Reviewer role: **the second of the two independently recorded reviews** P08's acceptance
condition (GATE-LEDGER P08-4) requires. The first review (`dc-warn/out/p08-review-1/REPORT.md`,
VERDICT REJECT) was read **as input to complement, not as evidence**: every finding below is
labelled by my own execution or reading, and where I agree with review-1 I state that I
reached the conclusion independently and how. Scope per the governing ruling: the frozen
object, boundary behaviour, the evidence chain, and ledger consistency. I do **not**
re-expand the implementation scope (so review-1's obligations about the `switchExpression`
destination handoff and the lambda fast path are out of my scope except where the ledger
cites them).

Review performed 2026-09-30, toolchain: Swift 6.2.4 (swift-6.2.4-RELEASE, x86_64-linux),
haxe 4.3.7, `PATH`/`HAXELIB_PATH` from `dc-warn/out/chainA-fixed-rerun/evidence/env.json`
(repo-local `.haxelib`; haxe run with cwd = tree root).

---

## 1. The frozen object is what the record says it is

- `[EXEC]` `git rev-parse c8ae0054d8b1937cf05c0dd849c268807ae19b8f` in
  `boring-wt-architecture` resolves; subject `fix(swift): lambda return contract, with the
  block destination it exposes`, tree `3c5d977e…` (matches REFREEZE §1).
- `[EXEC]` I worked exclusively from a clean `git archive c8ae0054` export into
  `/tmp/p08r2/tree`. This matters and was necessary: `[EXEC]` the live worktree's
  `SwiftExpr.hx` hashes `e79c2fb1…`, which differs from the frozen blob — I reproduced
  review-1's worktree-drift observation by my own hashing.
- `[EXEC]` File identities at the export, all matching REFREEZE §1 exactly:
  | file | sha256 | bytes |
  |---|---|---|
  | `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` | `22fd243c044ca8c3b149c8d7c743476f088fd21cf6c375e79d3d6c3738aceef5` | 333878 |
  | `tests/swift-gap-boundary/gap/Gap.hx` | `150315585b0a4aee5df5d1f9f24e217a2c5f747717aa6161eb1032769b057048` | 4197 |
  | `tests/swift-gap-boundary/swift.hxml` | `87be97b5393eea5bbba9b87d0082c6378c282bc6153b304e047418798fdc7800` | 646 |
  | `tests/swift-gap-boundary/gap-boundary.test.ts` | `8dd13985e410980acaa393634a22cb6202b8361866959db2fca5a7399d04fe40` | 6271 |
- `[EXEC]` Parent chain: `git diff --stat 28820ff5 c8ae0054` = `SwiftExpr.hx` (18 lines) +
  the three gap-fixture files added; `git diff --stat a14345ce 28820ff5` = `RustExpr.hx`
  only (16 lines, the Rust rename). **One REFREEZE inaccuracy found, see §4.**
- `[DOC→DISCREPANCY]` REFREEZE §1 states the candidate "differs from its parent exactly in
  this compiler file (plus the Rust rename in `28820ff5`)". At the file level this is
  **false**: `c8ae0054` also *adds* `tests/swift-gap-boundary/{gap-boundary.test.ts,gap/Gap.hx,swift.hxml}`.
  The claim is true only if read as "the compiler code differs exactly in this file". The
  record should be re-worded; it does not change any verdict.

## 2. Boundary behaviour at the frozen revision

Generated fresh from the clean export (`haxe tests/swift-gap-boundary/swift.hxml -D
swift-output=… -D swift-test-output=…` — the archived driver `swift-archived.hxml` lacks
`-D swift-output` and fails; the frozen fixture's own driver is the correct one):

- `[EXEC]` Generation rc=0, stdout and stderr both 0 bytes.
- `[EXEC]` Generated identities (`evidence/generated-identities.sha256`):
  `gap/Gap.swift` `8f66594fb51263aee633ee6769cb91d043ffc05398eab489b066410d624b1bc0`,
  `Runtime.swift` `a24d5fa3…`, `std/UStringException.swift` `ca9b2487…`,
  `std/UStringFault.swift` `36499cfb…` — byte-identical to the archived identities cited in
  REFREEZE §2 (I recomputed them, not inherited).
- `[EXEC]` **W1 warnings gone**: `swiftc -typecheck` over the 4 generated files → rc=0,
  stderr 0 bytes (0 errors, 0 warnings); `grep -c '#no-usage'` on `Gap.swift` = 0.
- `[EXEC]` **`swiftc -c -whole-module-optimization`**: rc=0, object produced
  (`gap.o`, 278 288 bytes, sha256 `c66e48c3…`), and **exactly one diagnostic**:
  ```
  gen/gap/Gap.swift:117:9: warning: will never be executed
  ```
  Counted as diagnostics (`grep -c ': warning:'` = 1, `': error:'` = 0), not caret
  substrings. Full stderr in `evidence/swiftc-c.stderr`. **I do not soften this: the count
  is 1, not 0.**
- `[EXEC]` Both recorded traps reproduced: plain multi-file `swiftc -c … -o gap.o` →
  rc=1, `error: cannot specify -o when generating multiple output files`
  (`evidence/trap-multi-o.stderr`); `-typecheck` returns 0 diagnostics for a shape that
  genuinely fails under `-c`. The `-WMO` form is the only valid reading.
- `[EXEC]` At the frozen revision `gap-boundary.test.ts` contains **no `swiftc -c`
  invocation** (`grep -c '"-c"'` = 0; it typechecks and records the `-c` deviation in a
  comment only) — confirming REFREEZE §5's caveat: the working automated `-c` assertion
  belongs to the later `d14231a6`, not to `c8ae0054`.

## 3. Evidence chain — claim by claim

| REFREEZE / ledger claim | Status |
|---|---|
| Revision pin + file identities (§1) | `[EXEC]` reproduced, exact match |
| Generation rc=0, empty stderr at clean export (§2) | `[EXEC]` reproduced |
| W1 `[#no-usage]` warnings gone; `-typecheck` 0/0 (§2) | `[EXEC]` reproduced — my own clean-export run is an independent confirmation, not inherited from the three retained sessions |
| One remaining `-c` diagnostic at `Gap.swift:117`, rc=0, 278 288-byte object (§3) | `[EXEC]` reproduced exactly (same line, same object size) |
| Generated identities equal archived FREEZE §3.1 identities (§2) | `[EXEC]` recomputed and matched |
| Three retained prior 0/0 sessions (`w1-fix`, collection seat, fixture-repair seat) (§2) | `[DOC]` — I read the retained run summaries in `p08-refreeze/evidence/06-fixture-runs.txt` but did not re-execute those sessions; my own measurement supersedes the need |
| Fixture has no automated `-c` at `c8ae0054`; repaired form landed at `d14231a6` (§5) | `[EXEC]` grep = 0 at frozen revision; `[DOC]` for the `d14231a6` side (successor, out of scope) |
| Ledger P08-1: `blockExpression` no longer reads `currentReturnType`; lambda contract seeded/restored in `functionLiteral` (HEAD ledger) | `[CODE]` — read at the frozen export: `blockExpression` derives its destination from `stmts[last].t` only; `functionLiteral` seeds `currentReturnType = Context.follow(f.t)` with save/restore |
| Ledger P08-1 correction: `switchExpression(sw:TypedExpr):String` at `:5562` calling `switchReturn(sw, 1, false, sw.t)` at `:5566`, `switchBindingLines` calling it without `v.t` at `:5528`; explicit-destination form landed later as `71a60c7d` | `[EXEC]` — all three line numbers verified verbatim in the frozen blob; `git show 71a60c7d` shows exactly that signature change (`switchExpression(sw, v.t)`, `switchReturn(sw, 1, false, dest)`), i.e. **not** in `c8ae0054`. The correction (`ab20a8af`) is accurate |

## 4. Ledger consistency (against the frozen bytes)

Checked current `docs/architecture/GATE-LEDGER.md` (HEAD, post-correction `ab20a8af`) row by row:

- **P08-1** — `[EXEC]` the corrected cell is now fully supported by the frozen bytes
  (signatures and line numbers verified above). The earlier false credit to
  `switchExpression` is gone. Consistent.
- **P08-2 (FAIL)** — `[EXEC]` consistent with my measurement: W1's two warnings are gone;
  what fails is one build-phase diagnostic under `-c`, which per the round-145 gate-owner
  ruling (recorded in the frozen fixture's comment, `[CODE]`) counts against
  `02-translator-implementation-standard.md:78/:80`. Consistent.
- **P08-3 (PARTIAL)** — `[DOC]` for its content (laziness measured by p08-review-1 and the
  behaviour-matrix seat). Those are retained reports I did not re-execute; the row labels
  them honestly and they are outside my scope. No contradiction with frozen bytes.
- **P08-4 (FAIL)** — `[DOC]` accurate at the time of writing; this report is the second
  review it awaited.
- **"What changed" table** — `[EXEC]` all cited commits resolve (`71a60c7d`, `d36e6d3f`,
  `99ba67fd`, `28820ff5`, `ac4099ea`, `50a95377`, `a80690f1`, `695940e8`, `40e94772`,
  `d1180768`, `d14231a6`). `71a60c7d` is correctly attributed to a **successor** revision,
  not to `c8ae0054`; no row any longer credits the frozen revision with successor work.
  `[UNVERIFIED]` the table's *content* claims about successors (e.g. `71a60c7d` "swiftc -c
  green including full link + 30/30-line run") — I did not measure `71a60c7d`; it is not
  the frozen object.
- **I searched for further claims the frozen bytes do not support and found none** in the
  P08 rows. One inaccuracy sits in `REFREEZE.md` §1, not the ledger (§1 above): "differs
  from its parent exactly in this compiler file" ignores the three fixture files the same
  commit adds.

## 5. VERDICT — **REJECT**

I reject the frozen candidate **`c8ae0054d8b1937cf05c0dd849c268807ae19b8f`** for P08
acceptance, on one in-scope condition. I reached this independently of review-1: my own
clean `git archive` export, my own generation, my own `swiftc` runs (§2), counted as
diagnostics.

**Exact condition (the only one within my scope):**

1. **Zero build-phase diagnostics is not met.** On the candidate's own counterexample
   inputs, `swiftc -c -whole-module-optimization` emits **exactly 1** diagnostic:
   `gap/Gap.swift:117:9: warning: will never be executed`. Required by
   `02-translator-implementation-standard.md:78/:80` ("the count is zero") and by the
   round-145 gate-owner ruling that a build-phase diagnostic counts: **zero**. Discharge by
   either (a) clearing the unreachable trailing `return` at `Gap.swift:117` and re-freezing
   the candidate, or (b) a **written gate-owner ruling** that a build-phase diagnostic does
   not count against `:78/:80`. **A reviewer cannot waive an obligation, and I do not:**
   `-typecheck` cleanliness (which I measured, 0/0) is not the stated goal; the goal is zero
   under `-c`.

An acceptance of any successor revision must name: the revision hash, the measured
`swiftc -c -WMO` diagnostic count of **0**, and the revision on which the fixture's own
automated `-c` assertion exists and passes.

I expressly do **not** rule on review-1's out-of-scope implementation conditions
(`switchExpression` destination handoff, lambda fast-path boundary): those belong to the
implementation scope, and my narrower mandate does not re-expand it. They remain whoever's
obligation they were.

## 6. Not-verified list

1. The three prior 0/0 sessions' *execution* — retained logs read only (`[DOC]`); my own
   fourth measurement at the frozen revision covers the same claim.
2. Anything at successor revisions (`71a60c7d` green `-c` + link + 30/30 run claims,
   `d14231a6`'s fixture correctness) — not the frozen object; not measured.
3. Other targets (Kotlin/Rust/TS/Dart), the acceptance fixture (`tests/swift-readonly-boundary/`),
   route fixtures, and the compiler's own suite at this revision — not run (out of the
   narrow mandate; REFREEZE §7.2 records the same limit).
4. Lazy-effects / single-evaluation behaviour — not measured here; ledger P08-3 rests on
   `[DOC]` reports I did not re-execute.
5. `REFREEZE.md` §2's seat attribution ("three independent sessions … [MINE + 2 seats]")
   quoting `GATE-LEDGER.md:19` — attribution wording inherited, not audited.
6. Swift versions other than 6.2.4 / other flag sets beyond `-WMO` and `-typecheck`.

## 7. Process notes

- No repository file, worktree, frozen revision, or test was modified by me. I ran no
  `bun`/`bun test`.
- **Pre-existing trap state found and repaired per standing instruction**: at review start,
  `grep -c 'Test.equals' samples/boring/MathNaNTestSupport.hx` in the live worktree was
  **0** (the tracked file had been left rewritten by an earlier seat's run — I ran no bun
  process myself). Restored with `git checkout HEAD -- samples/boring/MathNaNTestSupport.hx`;
  post-restore count = 5, `git status` clean for that file. (`[EXEC]`, before/after.)
- No `pkill -f` used; no exit codes measured through pipes.

## 8. Evidence index (`evidence/`)

| file | what it is |
|---|---|
| `revision-pins.txt` | pin, tree, subject, parent diff-stats |
| `gen.{rc,stdout,stderr}` | fixture generation at the clean export (rc=0, empty) |
| `generated-identities.sha256` | sha256 of the 4 generated Swift files + Package.swift |
| `typecheck.{rc,stdout,stderr}` | `-typecheck`: rc=0, 0 diagnostics |
| `swiftc-c.{rc,stdout,stderr}` | `swiftc -c -whole-module-optimization`: rc=0, **exactly 1 warning** at `Gap.swift:117:9` |
| `gap-o.sha256` | 278 288-byte object identity |
| `trap-multi-o.stderr`, `trap.rc` | the plain multi-file `-c -o` trap (rc=1) |

*(End of report.)*
