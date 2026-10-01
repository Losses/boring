# Adversarial audit — session-integration batch (`5a8f19e6..c55aa404`)

Task id: `audit/session-integration`. This is a **review**, not an implementation:
no audited code was modified. Report author did not participate in producing the batch.

- Worktree: `/home/losses/Development/tq-workspace/boring-wt-baseline-audit`
- Branch: `audit/session-integration`, base/HEAD: `c55aa404f8ee3efe8bbcc3df7b0240b7a26e1b86`
- Range audited: `5a8f19e6..c55aa404`, 50 files, +4735/−176 (verified by
  `git diff --stat 5a8f19e6 c55aa404`).
- Environment actually used:
  - nix devShell `.#default` **offline** (cached): `haxe 4.3.7`,
    `rustc 1.98.0 (88d9e12ae 2026-08-18)`, `cargo 1.98.0 (797e8a9bc 2026-08-05)`,
    `node v22.23.3`, `bash 5.3.9`.
  - `which haxe` / `which cargo` are **empty outside the devShell**; all Rust/haxe
    runs below were done with `nix develop --offline -c ...`.
- Method discipline: exit codes were read directly (`cmd > f 2>&1; rc=$?`), never
  through a pipe. Diagnostic counting used shapes
  (`error(\[E[0-9]+\])?:`, `^FAIL`, `omits root module`), never `grep -c 'warning:'`.
- Every number below is marked **[measured]** (I ran it), **[referenced]** (from an
  on-disk artifact produced by another seat; I only opened it) or **[code-reading]**
  (I reasoned from source; no execution).

---

## Verdict table

| # | Item | Verdict |
|---|------|---------|
| 1 | Hardened roots-guard (`b2961407` / `8b32f8a0` / `1cafaa42`) | **partly-confirmed** — core claims true; still admits a well-shaped nonsense reason (guard header discloses it); PASS is devShell-dependent |
| 2 | charCodeAt archive (`0e7e24ac` / `66272b6f`) | **partly-confirmed** — bytes and modes confirmed; `FILES.sha256 -c` is **not** rc=0 from the base repo root (2 dangling `dc-warn/out` paths) |
| 3 | Rust identity registries (`2bde2288`, PIT-281 + TCN-109) | **confirmed** for the compiled claims (independently recompiled); caveats: `throwGrowthKey` is name-only and the absorbed branch bypasses it; **reproducibility gap**: `pkrev` and `runtime` faultnames control are not driven by committed commands |
| 4 | hxml dedup 45 lines (`9c0a403b` / `5a19e271`) | **confirmed** |
| 5 | host-String CLOSURE.md (`c55aa404` / `5360d915`) | **partly-confirmed** — docs-only, but one "not in effect on base" sentence is stale w.r.t. the final base |
| 6 | docs-only `73c33200`, `46b83a20`, `1a486ebd`, `b51f7643` | **confirmed** (docs-only; the checksum deletion makes `sha256sum -c` rc=0) |
| C | tracked/archive of `growth-id` / `payload-key` / `charcodeat` | **confirmed** (6 / 4 / 20) |

---

## 1. Hardened roots-guard

**Files:** `tools/roots-guard/check-roots-guard.sh`, `roots-allowlist.json`,
`roots-baseline.txt` (1650 lines).

### 1.1 Core claim — "delete a real root + reason `because`" — **confirmed**

Setup (in `/tmp`, tree untouched): copied the `5a8f19e6` examples, deleted the real
root `boring.ArithmeticOps` from `kotlin-f32.hxml` (it remains in `kotlin.hxml`), and
added an allowlist entry with `reason:"because"`.

Old guard (`git show 5a8f19e6:tools/roots-guard/check-roots-guard.sh`), **[measured]**:

```
$ bash /tmp/audit-exploit-old/tools/roots-guard/check-roots-guard.sh /tmp/audit-exploit-old/examples
EXEMPT: kotlin-f32.hxml may omit boring.ArithmeticOps -- because
EXEMPT: kotlin-f32.hxml may omit registry.Main -- registry.Main is the binary64 ...
...
roots guard: PASS (4 exemption(s) in force)
$ echo rc=$?
rc=0
```

New guard (`c55aa404`), same tampered tree + `ROOTS_GUARD_ALLOWLIST` pointing at the
tampered allowlist, **[measured]**:

```
$ ROOTS_GUARD_ALLOWLIST=/tmp/audit-exploit-old/tools/roots-guard/roots-allowlist.json \
    bash tools/roots-guard/check-roots-guard.sh /tmp/audit-exploit-old/examples
FAIL: allowlist: exempt[3].module boring.ArithmeticOps: reason is too short to be an exemption sentence (1 word(s): "because"); need >= 4 words
roots guard: FAILED
$ echo rc=$?
rc=1
```

So the exact one-word reason is closed. Blank / tiny / placeholder / documented
minimal-bypass negative controls all stay `rc=1` — **[measured]** matrix (reason →
rc, with the deleted root still present):

| reason | rc | diagnostic (first) |
|---|---|---|
| `""` | 1 | blank/whitespace-only reason |
| `because` | 1 | too short (1 word) |
| `todo` | 1 | too short (1 word) |
| `fix flaky now` | 1 | too short (3 words) |
| `aaaa bbbb cccc dddxxxxxx` | 1 | padded/gibberish token `"aaaa"` |
| `alpha beta gamma deltaaa` | 1 | padded/gibberish token `"deltaaa"` |
| `the the the the the the the` | 1 | repeated-token spam |
| `qwer asdf zxcv uioplkjh` | 1 | too short (23 chars) |

### 1.2 "pre-fix hxml: exactly 111 FAIL, 41/33/37" — **confirmed**

Materialised `git show e1c65975:examples/*.hxml` into `/tmp/audit-pre/examples` and
ran the **new** guard against it (in devShell, `--repo-root` at the shared tree’s
`.haxelib`), **[measured]**:

```
$ grep -cE '^FAIL.*omits root module' /tmp/guard-prefix.out
111
$ grep -E '^FAIL' /tmp/guard-prefix.out | grep 'omits root module' | awk '{print $2}' | sort | uniq -c
     41 kotlin-f32.hxml
     33 rust-f32.hxml
     37 swift-f32.hxml
```

All 111 FAILs are pair-omit FAILs; no other FAIL kind. The same run reports
`SUMMARY: 45 duplicate root line(s)` — i.e. the pre-fix hxml already carried the 45
duplicates that claim 4 removes.

### 1.3 "still rc=0, duplicate count 0" — **confirmed, with an environment caveat**

In-tree, inside the devShell (`.haxelib/` present), **[measured]**:

```
$ bash tools/roots-guard/check-roots-guard.sh; echo rc=$?
roots guard: PASS (3 exemption(s) in force; 6 declared unrooted @:test module(s); 0 duplicate root line(s) reported; 1650 pinned root(s) in root-floor)
rc=0
```

`--strict-duplicates` is also rc=0. `--print-baseline` round-trips the committed
floor exactly, **[measured]**:

```
$ bash tools/roots-guard/check-roots-guard.sh --print-baseline > /tmp/printed-baseline.txt
$ diff tools/roots-guard/roots-baseline.txt /tmp/printed-baseline.txt; echo diff_rc=$?
diff_rc=0        # 0 lines
```

**Caveat (environment-dependent PASS).** `.haxelib/` is gitignored
(`.gitignore:8`) and only exists after the devShell shell hook runs. In a *fresh*
worktree with no `.haxelib`, the same guard is `rc=1`, **[measured]**:

```
$ bash tools/roots-guard/check-roots-guard.sh; echo rc=$?
FAIL: kotlin.hxml:...:60 root module runtime.Graphemes does not resolve to any .hx ...
...
roots guard: FAILED
rc=1
```

So "the guard PASSes" is not a property of the tracked tree alone; a reader must run
it inside the devShell. This is not a logic bug (the `-lib boring`/`-lib reflaxe`
classpaths genuinely live outside the repo), but it belongs in any "clone →
reproduce" claim.

### 1.4 Adversarial search for a residual hole

| attack | result | note |
|---|---|---|
| one-word reason (above) | rc=1 | closed |
| blank/tiny/gibberish/repeated | rc=1 | closed (matrix) |
| **well-shaped nonsense reason** | **rc=0, root stays omitted** | **still open — but the guard header discloses it** |
| two files both delete a pinned root | rc=1 (`root-floor` FAIL) | floor backstops it |
| add a new root to both files | rc=0 | floor does *not* false-positive on additions |
| non-`include` `--macro` line | ignored (`-*` branch) | header explicitly out of scope |
| `ROOTS_GUARD_ALLOWLIST` / `ROOTS_GUARD_REPO_ROOT` | full redirect | header explicitly lists these as bypass surfaces |

The residual hole, **[measured]** — deleting the same real root and supplying the
24-char, 5-word reason `qwer asdf zxcv qwer tyui` yields:

```
$ ... bash tools/roots-guard/check-roots-guard.sh /tmp/audit-exploit-old/examples
EXEMPT: kotlin-f32.hxml omits root module boring.ArithmeticOps (base-only, at .../kotlin.hxml:128); declared in allowlist: qwer asdf zxcv qwer tyui
...
roots guard: PASS (4 exemption(s) in force; ...)
rc=0
```

This is **not** a contradiction of the batch’s own claim, because the script’s header
says so verbatim (quoting `check-roots-guard.sh:66-69`):

> `#      A well-shaped but meaningless reason (e.g. "alpha beta gamma delta`
> `#      oxen") still passes: a script cannot verify that prose is`
> `#      meaningful, so a reviewer has to read the reason. ...`

I therefore rate claim 1 **partly-confirmed**: the specific defeated shape is closed,
the broader "a semantically empty reason can still exempt a real regression" shape
remains open **by documented design**.

### 1.5 Does the 1650-line `roots-baseline.txt` falsely block legit additions?

**[measured]** Adding a real, resolvable, non-`@:test` module as a new root to *both*
kotlin files passes:

```
$ cp -r examples /tmp/audit-add; printf 'std.UString\n' >> /tmp/audit-add/kotlin.hxml; printf 'std.UString\n' >> /tmp/audit-add/kotlin-f32.hxml
$ ... check-roots-guard.sh /tmp/audit-add; echo rc=$?
roots guard: PASS (...)
rc=0
```

Basis **[code-reading]**: the floor check (script §(5)) is one-directional — for each
pinned `(target, module)` it asserts the module is still a root of base-or-f32. It
never asserts `root-set ⊆ floor`, so a new `@:test` module + a root line in both
files cannot be blocked by the floor. (Adding a *previously-orphan* `@:test` module as
a root does trip a **different** check: the now-stale `unrootedTestModules` entry
fails until dropped — a friction, not a false regression signal.)

The known floor gap (a root added after the last refresh, then removed from both
files, is invisible) is disclosed in the header §(5) and requires refresh discipline;
I did not count it against the batch.

---

## 2. charCodeAt fixture archive

**Claim:** 20 files, byte-identical to the original detached worktree;
`FILES.sha256` one command from the repo root is rc=0.

- **20 tracked, all mode `100644`**, **[measured]**:
  `git ls-files -s tests/haxe/charcodeat | awk '{print $1}' | sort | uniq -c` → `20 100644`.
- **[measured]** `git archive HEAD` extract is byte-identical to the worktree for the
  whole family (20 files, `diff -r` clean).
- `FILES.sha256` lives **outside** the repo:
  `/home/losses/Development/tq-workspace/dc-warn/out/charcodeat/FILES.sha256`
  (22 lines: 20 fixture lines + `dc-warn/out/charcodeat/PATCH.diff` and `REPORT.md`).

The claim’s "from the repo root rc=0" is **not** true from the base/audit repo root,
**[measured]**:

```
$ (cd boring-wt-baseline-audit && sha256sum -c /home/losses/.../dc-warn/out/charcodeat/FILES.sha256)
sha256sum: dc-warn/out/charcodeat/PATCH.diff: No such file or directory
sha256sum: dc-warn/out/charcodeat/REPORT.md: No such file or directory
... all 20 tests/haxe/charcodeat/... : OK
sha256sum: WARNING: 2 listed files could not be read
rc=1
```

It **is** rc=0 from a root that contains both `tests/` and `dc-warn/`, which is the
worktree the task was done in (`boring-wt-charcodeat`), reproduced here with a
symlink farm, **[measured]**:

```
$ (cd /tmp/sha-root && sha256sum -c /home/losses/.../dc-warn/out/charcodeat/FILES.sha256); echo rc=$?
... 22 : OK
rc=0
```

Verdict: **partly-confirmed**. The 20 archived fixtures are byte-confirmed against the
recorded manifest (all 20 lines `OK`), but the manifest is not self-contained in the
repo, and the exact "one command from the repo root" wording is only true from a root
that also has a `dc-warn/` sibling. A base-only clone cannot run the anchor as stated.

---

## 3. Rust identity-keyed registries (PIT-281 + TCN-109)

I did **not** rely on the committed evidence for the compiled claims: I regenerated
every fixture with haxe 4.3.7 and rebuilt every generated crate with cargo 1.98.0,
using fresh output dirs. Pre-fix trees were `/tmp` worktrees at `c55aa404` with only
the fix’s non-test source files reverted to the fix’s parent.

### 3.1 Growth-id parity (TCN-109) — **confirmed**

| fixture | pre-fix (reverted) | post-fix |
|---|---|---|
| `gi` (A then E) | `cargo rc=101`, `error[E0599]: no variant ... EFault ... for enum AFault` | `cargo rc=0`, `Finished dev profile` |
| `girev` (E then A) | `cargo rc=101`, same `E0599` | `cargo rc=0`, `Finished dev profile` |
| `nameshape` | `cargo rc=101`, `error[E0428]: the name EFault is defined multiple times` | `cargo rc=101`, `error[E0533]: expected value, found struct variant EFault::EFault` |

All four pre/post runs had `haxe rc=0` (generation is silent; the failure is in cargo).
This matches the commit bodies, including the **disclosed** nameshape residual
(`E0428` gone, fallback-shape `E0533` remains, recorded as PIT-340 / `t-muongey9-ddn9`).

**Count nuance (the "2×E0599" wording).** Per declaration order I measured **one**
`error[E0599]` line; the raw string `E0599` appears **twice** per log because rustc
appends `For more information about this error, try rustc --explain E0599`. So "2×"
is almost certainly the raw-string count, i.e. exactly the counting trap this project
has hit before. The task statement’s "各 2×E0599" is **not** accurate per order; the
substantive claim (E0599 pre, none post) is accurate.

Revert reproduction **[measured]**: reverting the two source files re-broke both
orders (`rc=101`, identical E0599), matching the batch’s revert claim. The on-disk
revert evidence (`dc-warn/out/rust-growth-id/evidence/revert/*.cargo.stderr`) also
shows the same E0599 **[referenced]**.

`corpus/ref.diff` at
`dc-warn/out/rust-growth-id/evidence/corpus/ref.diff` is **0 bytes** **[measured]**
(`wc -c` → `0`), matching the batch.

### 3.2 Payload-key collision (PIT-281) — **confirmed**

| fixture | pre-fix (reverted) | post-fix |
|---|---|---|
| `pk` | `cargo rc=101` `{E0277,E0433,E0599}` | `cargo rc=0` |
| `pkrev` | `cargo rc=101` `{E0277,E0433,E0599}` | `cargo rc=0` |

Both declaration orders compile clean post-fix. (`pkrev` was driven with a `/tmp`
copy of `rust.hxml` whose only change is the root module — see §3.4.)

### 3.3 `throwGrowthKey` uniqueness and the identity contract

- **[measured]** `grep -rn 'function throwGrowthKey' --include='*.hx' .` → exactly
  **one** definition (`RustEmissionState.hx:39`). Confirmed.
- **[code-reading]** For the *unabsorbed* rethrow arm, registration and lookup
  genuinely share one key source: the walk stores `key = funcKey(cls.module, field.name,
  isStatic)`; registration later reads `state.funcErrorTypes.get(item.key)` and calls
  `throwGrowthKey(fnError, cls.name)`; the emitter seeds `errorTypeName` from
  `RustDecl.resolveErrorOwner`, which reads `state.funcErrorTypes.get(funcKey(
  f.classType.module, f.field.name, f.isStatic))`. Same map, same key.
- **Scope caveat A [code-reading]:** the *absorbed* arm does **not** call the
  predicate — it sets `growthKey = enumName` inline
  (`Compiler.hx:2585-2587`). So "`throwGrowthKey` is the *only* identity predicate" is
  overstated; it is the single predicate for the unabsorbed arm only. The commit body
  itself describes the two arms, so this is an over-claim in the task summary, not a
  hidden defect.
- **Scope caveat B [code-reading]:** `registerFaultConversion`/`enumGrowthFor` key
  the growth table by the **bare enum name**, not by module-qualified identity
  (`RustEmissionState.hx:251-266`; callers pass `pair.name` / `growthKey`, both names).
  Two modules declaring same-named `*Fault` enums would share one growth bucket. This
  predates the batch and I could not construct a compiled counterexample in the time
  budget, so it is recorded as a wording/robustness caveat, not a confirmed regression.
- Contract "returns null exactly when the lookup side would not consult the growth
  table" is consistent for the *predicate’s own inputs* (`fnError`, `memberName`); the
  lookup additionally short-circuits on `member == null` and on
  `syntheticErrorVariant(...) != null`, neither of which the predicate can see
  [code-reading]. For the `TNew(...,1 arg)` value-shape that reaches registration,
  `member` is non-null (falls back to the class name), so I found no reachable
  violation through that path, but I did not exhaustively prove the synthetic-enum path.

### 3.4 **Reproducibility gap (PIT-330)** — new finding

The claimed "both declaration orders" and the rename control are **not reproducible
from the repo**:

- **[measured]** `tests/haxe/payload-key/pkrev/PayloadKeyProbe.hx` is tracked, but no
  tracked `gen/*.hxml` roots `pkrev.PayloadKeyProbe`
  (`git grep -n 'pkrev'` → only its own `package pkrev;` line).
- **[measured]** `tests/haxe/payload-key/gen/rust-faultnames.hxml` references
  `-cp tests/haxe/payload-key-faultnames`, `--macro Intercept.run([... 'tests/haxe/payload-key-faultnames'])`
  and root `pkf.FaultNameProbe`; none of those exist in the repo
  (`git grep -n 'FaultNameProbe\|payload-key-faultnames\|pkf\.'` → only the hxml).
  The fixture file exists only untracked in the sibling
  `boring-wt-payloadkey` worktree.

So a clone can regenerate `pk` (and the growth-id family) but **cannot** regenerate
`pkrev` or the faultnames control with a committed command. This weakens claim 3’s
"reproducible from clone" standing even though the fixtures it does ship verify.

---

## 4. hxml dedup (45 lines) — **confirmed**

**[measured]**, comparing `5a8f19e6` to `HEAD` (only `5a19e271` touched `examples/`):

```
$ git diff --numstat 5a8f19e6 HEAD -- examples/kotlin.hxml examples/kotlin-f32.hxml \
    examples/rust.hxml examples/rust-f32.hxml examples/swift.hxml examples/swift-f32.hxml
0	8	examples/kotlin-f32.hxml
0	8	examples/kotlin.hxml
0	5	examples/rust-f32.hxml
0	8	examples/rust.hxml
0	6	examples/swift-f32.hxml
0	10	examples/swift.hxml
```

→ total **45 deleted / 0 added**. For each of the six files, `sort -u` of the bare
module lines is **EQUAL** pre vs post (module set unchanged). The guard now reports
`0 duplicate root line(s)` and `rc=0` (§1.3). Each deleted line’s module still occurs
in the same file post-dedup (implied by set equality and by the duplicate count
dropping to 0).

---

## 5. host-String family CLOSURE.md — **partly-confirmed (stale sentence)**

Docs-only: `5360d915` adds exactly
`docs/architecture/evidence/rust-string-expectation-family/CLOSURE.md` (+50), **[measured]**.

One factual sentence is stale w.r.t. the final assembled base. The doc states
(quoted; the branch name is elided with `…`):

> `- 该预算修复（420_000 等）是 ... 提交 9905949e/36e7540e/e8a4c3bb/4c292c64——`
> `**分支态，未生效于 base**（merge-base --is-ancestor 4 者对 arch 行头全为 false，已逐个核）。`

**[measured]:**

```
$ for c in 9905949e 36e7540e e8a4c3bb 4c292c64; do
    git merge-base --is-ancestor $c c55aa404 && echo "$c ANCESTOR" || echo "$c not";
  done
9905949e ANCESTOR
36e7540e ANCESTOR
e8a4c3bb ANCESTOR
4c292c64 ANCESTOR
```

i.e. all four **are** ancestors of the final base `c55aa404`; they are *not* ancestors
of `05e375b2` (the doc’s own declared base). The sentence is internally consistent
with "base = `05e375b2`" but misleading to a reader of the delivered base. Other
anchors check out: `40cf0ad0`, `9c9548ef`, `d1180768` are ancestors of `c55aa404`;
`f1eb7498` is a descendant of `05e375b2` [measured]. The rest of the closure is
evidence-referenced to `dc-warn/out/rust-string-expectations/` and was not re-run here.

---

## 6. Other docs-only commits — **confirmed**

**[measured]** each touches exactly one docs file:

- `73c33200` → `docs/architecture/GATE-LEDGER.md` (+65)
- `46b83a20` → `docs/architecture/MANAGEMENT-RULING-137.md` (+38)
- `1a486ebd` → `docs/architecture/rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md` (+251; path corrected 2026-10-01, R1 residual cleanup: the original text wrote `docs/architecture/evidence/rulings/…`, a directory that has never existed in this repository's history)
- `b51f7643` → `docs/architecture/evidence/entry-gate-r2r3/SHA256SUMS.txt` (−1, removes
  the self-referential `SHA256SUMS.txt` line)

The checksum fix is real, **[measured]**:

```
$ (cd docs/architecture/evidence/entry-gate-r2r3 && sha256sum -c SHA256SUMS.txt); echo rc=$?
2aadcb69.export.tar.sha256: OK
...
README.md: OK
rc=0
```

I did not independently audit the prose rulings’ substantive claims.

---

## C. tracked + `git archive HEAD` consistency — **confirmed**

**[measured]**

| dir | tracked files | `git archive HEAD` extract | archive vs worktree |
|---|---|---|---|
| `tests/haxe/growth-id` | **6** | 6 | IDENTICAL |
| `tests/haxe/payload-key` | **4** | 4 | IDENTICAL |
| `tests/haxe/charcodeat` | **20** | 20 | IDENTICAL |

(`git archive HEAD | tar -x -C /tmp/archivetest; diff -r` per dir.) Mode check:
all 30 files `100644`.

---

## Findings, ranked

1. **Residual exemption hole (guard, disclosed):** a `>=4`-word `>=24`-char
   semantically empty reason (e.g. `qwer asdf zxcv qwer tyui`) still exempts a real
   root deletion at `rc=0`. The guard header documents this, so it is a *residual
   limitation*, not an over-claim.
2. **Reproducibility gap (claim 3):** `pkrev/PayloadKeyProbe.hx` has no committed gen
   driver and `gen/rust-faultnames.hxml` points at an untracked
   `tests/haxe/payload-key-faultnames/` tree. From a clone, two of the three
   PIT-281/TCN-109 reproduction shapes cannot be regenerated.
3. **`FILES.sha256` context (claim 2):** `sha256sum -c` is `rc=1` from the base repo
   root (2 dangling `dc-warn/out` lines); the "one command rc=0" claim only holds from
   a root that also contains `dc-warn/`.
4. **Guard PASS is devShell-dependent:** without `.haxelib` the guard is `rc=1`; "the
   guard PASSes" is not a property of the tracked tree alone.
5. **Stale CLOSURE sentence (claim 5):** four commits called "not in effect on base"
   are ancestors of the final base.
6. **"2×E0599" count wording** vs one E0599 error line per order (raw-string double
   count).
7. **Over-claim wording (claim 3):** `throwGrowthKey` is the single predicate for the
   *unabsorbed* arm; the absorbed arm computes its target inline, and the growth table
   is keyed by bare enum name, not module-qualified identity.

## What I measured vs what I referenced

- **Measured (ran here):** guard old/new on the tampered tree; guard reason matrix;
  guard negative controls; guard in-tree PASS and no-`.haxelib` FAIL; `--print-baseline`
  round-trip; 111 FAIL grouping; pre/post guard on `e1c65975` hxml; all haxe generations
  and cargo builds for `gi`/`girev`/`nameshape`/`pk`/`pkrev`; dedup numstat and module
  sets; tracked counts and `git archive` diffs; `sha256sum -c` outcomes; `ref.diff`
  size; `pkrev`/faultnames reference searches; docs-only commit stats; `SHA256SUMS`
  verification; ancestry checks.
- **Referenced (opened, not re-run):** `dc-warn/out/rust-growth-id/evidence/**`
  (pre/post/revert cargo logs, corpus `ref.diff`); `dc-warn/out/charcodeat/FILES.sha256`
  and `PATCH.diff`/`REPORT.md`; the closure report’s cited
  `dc-warn/out/rust-string-expectations/`.
- **Code-reading (not executed):** the `throwGrowthKey` contract analysis, the
  absorbed-arm bypass, the name-only `enumGrowth` key, and the floor
  one-directionality used to answer §1.5.

## Limitations / not verified here

- The charCodeAt `run.sh` (native ts/kotlin/rust/swift/dart stages) was **not** run;
  it needs the full devShell plus native toolchains and is an observation fixture, not
  a pass/fail gate. `not-verifiable-here` for its runtime output.
- No compiled counterexample was built for the name-only `enumGrowth` key; that
  remains an argument, not a measurement.
- The prose rulings (`GATE-LEDGER.md`, `MANAGEMENT-RULING-137.md`,
  `BUILD-PHASE-DIAGNOSTIC-RULING.md`) were checked for being docs-only, not for the
  truth of their narrative claims.

## PIT note

No `wb_note_add` tool (and no `wb`/`but` CLI) is present in this session, so no PIT was
filed. The most reusable trap, if one is filed later: **"grep-counting `E0599`/`error`
raw strings double-counts because rustc prints one error line plus an
`--explain` hint; count `^error(\[E[0-9]+\])?:` instead."**
