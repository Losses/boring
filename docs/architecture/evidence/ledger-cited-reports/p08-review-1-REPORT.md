# P08 REVIEW 1 — verdict on the FROZEN revision `c8ae0054`

Reviewer role: **the first of the two independently recorded reviews** P08's acceptance condition
requires. Target: the revision pinned by `docs/architecture/REFREEZE.md` (`fc89d5d8`), **not** a
scratch tree and **not** the superseded `dc-warn/out/p08-candidate-freeze/FREEZE.md`.

Labels: **[EXEC]** I ran it; **[CODE]** I read the source; **[DOC]** a document asserts it;
**[UNVERIFIED]** cannot be established, blocker named.

Prior reviews (`dc-warn/out/p08-behaviour-review/`, `dc-warn/out/p08-implementation-review/`) are
treated as **inputs, never as acceptance evidence**. Both targeted *earlier* states (the behaviour
review an uncommitted worktree; the implementation review a scratch tree whose `SwiftExpr.hx` was
`bf7dde2c…` / 7041 lines). This review targets `c8ae0054`, where `SwiftExpr.hx` is `7bc3ba92…` /
7072 lines.

**VERDICT: REJECT.** Reasons and exact conditions in §5.

---

## 1. Revision pin — I am reviewing `c8ae0054` [EXEC]

```
$ git rev-parse c8ae0054
c8ae0054d8b1937cf05c0dd849c268807ae19b8f
$ git rev-parse c8ae0054^{tree}
3c5d977eb1657cf8e29f50da8b700bea44701c15
$ git rev-parse c8ae0054:packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx
7bc3ba92f15373604e442d23e464e55595c4f95d
```

All four file identities of `REFREEZE.md` §1 reproduce **byte-exactly** on my export [EXEC]:

| file | REFREEZE §1 sha256 | mine |
|---|---|---|
| `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` | `22fd243c…8aceef5` | identical |
| `tests/swift-gap-boundary/gap/Gap.hx` | `15031558…b057048` | identical |
| `tests/swift-gap-boundary/swift.hxml` | `87be97b5…fdc7800` | identical |
| `tests/swift-gap-boundary/gap-boundary.test.ts` | `8dd13985…d09fe40` | identical |

All work was done on `git archive c8ae0054` extracted to `/tmp/rev1-c8ae0054`. This was necessary and
not ceremonial: during this session the live worktree's `SwiftExpr.hx` had blob `56164add…`, **not**
the frozen `7bc3ba92…` [EXEC]. That difference is decisive for obligation 1 (§3.1).

**Repository untouched by me**, with one instructed exception: another seat's run of
`tests/ts/package-artifacts.test.ts` clobbered the tracked `samples/boring/MathNaNTestSupport.hx`
(`grep -c 'Test.equals'` fell **5 → 0**); per the dispatch's trap note I restored it with
`git checkout HEAD -- samples/boring/MathNaNTestSupport.hx`, verified back at **5** [EXEC]. I wrote
nothing else in the repository and no test. `dc-warn/out/p08-review-1/evidence/` holds the raw logs.

---

## 2. Obligation 2 — "zero diagnostics on the same candidate inputs" — **FAIL** (not softened)

### 2.1 Generation and identity [EXEC]

`haxe /tmp/rev1-run/swift-frozen.hxml` (cwd = frozen export root) → **rc=0, stdout 0 B, stderr 0 B**.
Generated `gap/Gap.swift` sha256 **`8f66594fb51263aee633ee6769cb91d043ffc05398eab489b066410d624b1bc0`** —
identical to `REFREEZE.md` §2. Runtime files `a24d5fa3…` / `ca9b2487…` / `36499cfb…` also identical.

### 2.2 The measurement — `swiftc -c -whole-module-optimization` [EXEC]

```
$ swiftc -c -whole-module-optimization gap/Gap.swift Runtime.swift \
      std/UStringException.swift std/UStringFault.swift -o gap.o
rc = 0            gap.o = 278288 bytes
stderr = 255 bytes, containing EXACTLY ONE code diagnostic:

gap/Gap.swift:117:9: warning: will never be executed
115 |                 return ReadOnlyArray(Gap.sourceSecond())
116 |         }
117 |         return ReadOnlyArray(Gap.sourceFirst())
    |         `- warning: will never be executed
118 |     }
119 | }
```

- Rigorous count (leading-column `file:line:col: severity`): **1** [EXEC].
- Naive `grep -c 'warning:'`: **2** — the dispatch's warned over-count, caused by the repeated caret
  line. I recorded both so the count cannot be disputed by counting method.

**One diagnostic is not zero. Obligation 2 is FAIL.**

This reproduces `REFREEZE.md` §3 exactly (same line, same column, same object size, same revision).

### 2.3 The two traps the dispatch named, both confirmed [EXEC]

| invocation | result |
|---|---|
| `swiftc -c G.swift Runtime.swift std/….swift -o trap.o` (no `-WMO`) | **rc=1**, `error: cannot specify -o when generating multiple output files`, **no object file** — a fixture that used this form would have measured *nothing* and could still have "passed" |
| `swiftc -typecheck <same 4 files>` | **rc=0, stderr 0 bytes → 0 diagnostics** |

The `-typecheck` row is the recorded trap and it is live here: **on the frozen candidate, `-typecheck`
alone reports zero diagnostics while `-c` reports one.** Any acceptance based on `-typecheck` would
have passed a revision that fails the stated criterion. I did not accept on `-typecheck`.

### 2.4 The acceptance fixture is clean under `-c`; the gap fixture is not [EXEC]

| fixture | gen | `swiftc -o` build | `swiftc -c -WMO` | run |
|---|---|---|---|---|
| `tests/swift-readonly-boundary` | rc=0 | rc=0, **0 diagnostics** | rc=0, **0 diagnostics** | rc=0, 30 lines |
| gap counterexample | rc=0 | rc=0, **1 diagnostic** | rc=0, **1 diagnostic** | (see §4.2) |

So the failure is specific and reproducible: exactly the one site the `REFREEZE` record names,
W1's unreachable trailing `return` — the faithful rendering of a Haxe statement that is dead in the
source (both arms of `GapExplicitReturn.switchExplicitReturn` return) [CODE].

### 2.5 The repository's own collector for this fixture **cannot see the defect** [EXEC + CODE]

At the frozen revision, `tests/swift-gap-boundary/gap-boundary.test.ts` invokes **only**
`swiftc -typecheck` (line 65). It contains **no `swiftc -c` invocation at all** (the only `-c`
occurrences are inside the comment at lines 57/62/75). Its `pendingBuildWarning` (line 78) is
computed from the *typecheck* stderr — which is empty — so the collector prints

```
  recorded 0 pending build-phase diagnostic(s) - see pending-build-warnings.log
```

while `swiftc -c` emits exactly one. **The automated assertion is a false negative on the very
diagnostic that fails obligation 2.** This confirms `REFREEZE.md` §5's caveat with my own reading and
run; the repaired `-c` assertion is on a *later* commit than the frozen one and is therefore not
evidence about `c8ae0054`.

The fixture's comment is honest about this (it says the warning is "under `swiftc -c`"), but honesty in
a comment is not a collector. Obligation 2's verdict cannot be taken from this fixture's output.

---

## 3. Obligation 1 — fact-and-requirement handoffs

The candidate's entire `SwiftExpr.hx` change is **two hunks** [EXEC, `evidence/01-candidate-swiftexpr.patch`]:

- `blockExpression` (`:1202-1221`): the read of `currentReturnType` is removed; the value is now
  rendered by bare `expr(value)` (`:1220`).
- `functionLiteral` (`:2343-2356`): `currentReturnType = Context.follow(f.t)` is seeded (`:2351`) and
  restored (`:2353`) around `functionLiteralInner`.

For each site the dispatch names, what fact it uses, who owns it, and whether the code **enforces**
it or merely **happens to be right**:

### 3.1 `switchExpression` — fact is `sw.t`, and the code does NOT own it

| question | answer |
|---|---|
| fact used | `sw.t`, the switch expression's **own AST type**, used for *both* the emitted closure result type (`types.of(sw.t)`) and the arm destination (`switchReturn(sw, 1, false, sw.t)`, `:5566`) |
| who owns it | **the Haxe typer**, via expected-type propagation into the `TSwitch`. It is *not* the owning contract |
| enforced? | **No — incidental.** `switchBindingLines` (`:5526-5530`) calls `switchExpression(sw)` at `:5528` and never passes `v.t`; the argument route never passes the callee parameter. The emitted local carries no annotation (`let view = ({…})()`, confirmed in generated `Gap.swift:39`) |

[CODE] the frozen signature is literally `function switchExpression(sw:TypedExpr):String` (`:5562`) —
**there is no destination parameter**. The converter and the closure header are printed from the same
type, so they cannot disagree *with each other*; nothing makes that type the binding's declared type.

**The gate ledger is wrong about this revision.** `GATE-LEDGER.md` P08-1 credits the frozen candidate
with: *"`switchExpression` takes an explicit destination (`out/switchexpr-land/` — 4 hunks,
byte-identical trees)"*. That change is **not in `c8ae0054`**. It exists only as **uncommitted edits in
the live worktree**: the worktree blob `56164add…` adds `switchExpression(sw, destination:Null<Type>)`,
passes `v.t` from `switchBindingLines`, and adds `switchArgText` on the argument route; the frozen blob
`7bc3ba92…` has none of it [EXEC]. `dc-warn/out/switchexpr-land/` confirms the form of the change and
that it was landed as a *patch*, not as a commit reachable from the candidate.

This is the implementation review's **condition 3, still UNMET at the frozen revision**. A review
targets the revision it is given; I cannot credit the candidate with work that is not on it.

On divergence, I keep the distinction the prior review insisted on: the prior review observed **no
divergence** in 11 instrumented generations; I did not falsify that either. That is **"no divergence
observed", not "divergence impossible"** — the guarantee still rests on Haxe's expected-type
propagation, which this backend does not enforce and does not test.

### 3.2 `blockExpression` — removal is real; the consumer half is not enforced

| question | answer |
|---|---|
| fact used | its **own result type** `types.of(stmts[last].t)` (the IIFE header, `:1206`); the value is now bare `expr(value)` with no conversion (`:1220`) |
| who owns it | the **consumer** of the IIFE, which must apply the boundary around the whole closure |
| enforced? | the *removal* is enforced (the block reads no enclosing contract); the **"reached only from argument position"** premise is **incidental** — it is a property of Haxe's typer, asserted in the commit message and nowhere enforced in the backend. The only route to it is `expr(e)`'s `case TBlock` → `:2012` |

I tested the premise directly [EXEC]:

| probe | generated Swift | `swiftc -c -WMO` |
|---|---|---|
| expression block as **argument** at `ReadOnlyArray` | `consume(ReadOnlyArray(({ () -> TiqianArray<Int32> in _ = 1; return Blk.src() })()))` — consumer wraps the whole IIFE, header and value agree | **rc=0, 0 diagnostics** |
| expression block in **return** position | `_ = 1; return ReadOnlyArray(Blk.src())` — **no IIFE at all** (typer flattened it) | **rc=0, 0 diagnostics** |
| expression block as **initializer** | `let view: ReadOnlyArray<Int32> = ReadOnlyArray(Blk.src())` — no IIFE | **rc=0, 0 diagnostics** |

So on the three shapes I could build, the claim holds and the repair is correct. It is still an
**assumption about the input language, not a property the code enforces**; if a `TBlock` ever survives
into a position whose consumer does not wrap, the value renders unconverted. I report that as a
requirement-not-enforced, **not** as a demonstrated defect.

### 3.3 The lambda return sites — the reseed IS enforced, but the fast path drops the destination

| question | answer |
|---|---|
| fact used | `currentReturnType`, read at `:810` (return-position switch), `:5308`/`:5322` (try arms) and `:5688` (`armLines` fallback) |
| who owns it | **now the lambda's own `TFunc.t`** — `functionLiteral` seeds `Context.follow(f.t)` at `:2351` and restores at `:2353`; the only route to a lambda body is `expr`'s `case TFunction` → `functionLiteral` (`:1978`) |
| enforced? | **Yes, structurally** — a save/restore spanning exactly `functionLiteralInner`. This is a genuine composition-supplied handoff and it discharges the *shape* of the implementation review's condition 2 |

Measured, and it works [EXEC]:

```swift
// probe P-LAM-MULTI: var local = flag ? src() : src2(); return local;
public static func multiReturn(_ flag: Bool) -> Int32 {
    return Lam.use({ () -> ReadOnlyArray<Int32> in
    let local = (flag ? Lam.src() : Lam.src2())
    return ReadOnlyArray(local)      // <- the reseeded contract converted the value
})
}
```

**But a live defect remains, and it is measured, not speculative.** `functionLiteralInner` has a
single-statement fast path (`:2372`) that emits `head + tryKw + expr(r)` with **no boundary
conversion**:

```haxe
// P-LAM-SINGLE — ordinary accepted Haxe
public static function singleReturn(flag:Bool):Int {
    return use(function():ReadOnlyArray<Int> { return flag ? src() : src2(); });
}
```

generates

```swift
return Lam.use({ () -> ReadOnlyArray<Int32> in (flag ? Lam.src() : Lam.src2()) })
```

and `swiftc -c -whole-module-optimization` returns **rc=1 with exactly 1 error** [EXEC]:

```
lam/Lam.swift:17:32: error: declared closure result 'ReadOnlyArray<Int32>' is incompatible
                                      with return type 'TiqianArray<Int32>'
```

The candidate's own commit message names this hole — *"a single-return lambda fast path that never
applies a boundary conversion"* — and leaves it "not measured for this change". It is now measured,
and it fails. So a **lambda return site still does not carry its destination** on a reachable shape.

### 3.4 Obligation 1 net position

The two named reconstructions were aimed at, and the `blockExpression`/`functionLiteral` halves are
real improvements. But: `switchExpression`'s destination is still owned by the typer and not supplied
by its composition (and the ledger credits a fix that is absent from this revision), and a lambda
return site still fails to convert. **Obligation 1 is at best PARTIAL on `c8ae0054`, and the ledger's
"improved" reading is overstated for this revision.** In-scope reconstruction is *reduced*, not
removed: the other derivation sites the implementation review listed (`lowerArrayBoundary`'s
`sourceType: target` overwrite at `:2615`, `nilMergeChainNonOptional`, `platformModuleCall`,
`SwiftDecl`'s second planner entry) are still present [CODE]; I did not re-audit them by execution.

---

## 4. Obligation 3 — preserved source behaviour

### 4.1 Acceptance fixture, re-measured at the frozen revision [EXEC]

| step | result |
|---|---|
| generation | rc=0, stderr 0 B |
| `swiftc -o` full build (incl. tracked `ReadOnlyBoundaryRuntimeTests.swift`) | rc=0, **0 diagnostics** |
| binary run | rc=0, **30 lines** |
| vs Haxe `--interp` oracle (after stripping the oracle's `file:line:` prefix) | `diff` **empty — 30/30 byte-identical** |
| vs the **tracked expectations** in `readonly-boundary.test.ts:30-54` | **30/30 MATCH** |

The stale-expectation defect the implementation review flagged as its condition 4 is **repaired** at
this revision (`branch-true=1:1:present` / `branch-false=1:2:present` now match) [EXEC]. Note the
tracked `oracle.hxml` needs `-lib reflaxe` added or it aborts with `Type not found :
reflaxe.data.ClassFuncData` — a fixture defect I worked around rather than edited [EXEC].

### 4.2 The routes the candidate actually changed — measured by me, not by the fixture [EXEC]

The gap fixture ships **no oracle and no runtime runner** (its collector only typechecks), so the
behaviour of the changed routes was unmeasured by any repo command. I built my own harness
(`evidence/gaprt-main.swift`) plus a Haxe `--interp` oracle (`evidence/GapOracle.hx`) covering
switch-initializer, try-initializer, switch-return-position, switch-argument, switch-assign,
try-return, switch-statement, try-statement-assign, the static field, and the W1 explicit-return case:

**23/23 lines byte-identical to the Haxe oracle** (`evidence/gaprt.diff` is 0 bytes).

That is direct evidence for:

- **branch selection observable — YES.** `switchLocal-one=2` / `switchLocal-two=1`;
  `switchReturnPosition-one=2` / `switchReturnPosition-two=1`; `switchArgument-one=2` /
  `switchArgument-two=1`.
- **control exits — YES.** `switchExplicitReturn-one=2` / **`switchExplicitReturn-two=1`** — the W1
  swallowed-return defect does not reappear; `.two` yields the single-element array, not the
  pre-fix `[1,2]`.
- **single evaluation — YES on this fixture.** The oracle's `effect=1:8:1` line (producer called
  exactly once) matches the generated runtime.

### 4.3 Laziness — the ledger says "never measured"; **I measured it** [EXEC]

No repository fixture measures it: `grep -rn 'lazy\|Lazy'` over `tests/swift-readonly-boundary`,
`tests/swift-gap-boundary` and `samples/std/ReadOnlyArray.hx` returns **nothing** [CODE]. The label
`F3` is cited only by `REFREEZE.md:190` ("Lazy effects never measured (GATE-LEDGER P08-03, F3)"); I
could **not locate any definition of what F3 requires** in the documents reachable to me
[UNVERIFIED]. I therefore mapped it to the observable it must at least include — *an arm or operand
that Haxe would not evaluate must not be evaluated by the generated Swift* — and measured it with a
side-effecting probe at `ReadOnlyArray` destinations on four routes
(`evidence/probe-laz-Laz.hx`):

| observation | Haxe `--interp` | generated Swift |
|---|---|---|
| `bySwitch-A` | `1:a:1` | `1:a:1` |
| `bySwitch-B` | `1:b:1` | `1:b:1` |
| `byTry-true` | `1:b:1` | `1:b:1` |
| `byTry-false` | `1:a:1` | `1:a:1` |
| `byTernary-true` / `-false` | `1:a:1` / `1:b:1` | identical |
| `byBlockArg` | `1:a:1` | `1:a:1` |

**7/7 byte-identical**, and each line shows exactly **one** arm's effect ran (`log` holds one letter)
with **one** producer call (`calls=1`); `swiftc -c -WMO` on the same tree gives **0 diagnostics**.
So on switch / try / ternary / expression-block-argument routes at read-only destinations, **laziness
and single evaluation are preserved and are now measured**.

**What this does not establish** is stated plainly: it is *my* probe, collected by no repo command; it
covers four routes, not the whole language (no generic or abstract destinations, no `@:native` arrays,
no read-only→mutable direction, no nested-collection element destination); and if `F3` means something
narrower than side-effect non-evaluation, my probe does not discharge it.

### 4.4 Obligation 3 verdict

**Better than the ledger records, but not fully established.** Branch selection, control exits, alias
mutation, lifetime, single evaluation and laziness are all now backed by execution on the frozen
revision — the strongest parts of this candidate, and the parts where it genuinely fixed the W1
defect. What remains **NOT ESTABLISHED**: alias mutation and lifetime on the *changed* gap routes
(the fixture has no such case); laziness outside the four routes I probed; and any behaviour evidence
that is *collected* rather than hand-run, since the gap fixture still has no runner and the acceptance
fixture is not exercised by CI [DOC: behaviour review §Q5, which I read but did not re-verify].

---

## 5. VERDICT — **REJECT**

I reject the frozen candidate `c8ae0054d8b1937cf05c0dd849c268807ae19b8f` for P08 acceptance.

### Exact conditions

1. **Obligation 2 — FAIL, condition not met.** On the frozen candidate's own inputs,
   `swiftc -c -whole-module-optimization` emits **exactly one** diagnostic,
   `gap/Gap.swift:117:9: warning: will never be executed`. Required: **zero**. Either clear it
   (W1's unreachable trailing `return`) or obtain a **written gate-owner ruling** that a build-phase
   diagnostic does not count against
   `docs/specs/style/02-translator-implementation-standard.md:78/:80`. **A reviewer cannot waive an
   obligation and I do not:** `-typecheck` is clean, `-c` is not, and only the `-c` reading is
   relevant because the goal is stated as zero diagnostics under `-c`.
   *Ancillary, but it should be part of the same ruling:* the repo's own collector for this fixture
   typechecks only, so it reports "0 pending build-phase diagnostic(s)" against a real count of 1. It
   cannot gate this criterion until a `-c` step is on the frozen revision.
2. **Obligation 1 — `switchExpression` does not take its destination from its composition.**
   Required at the frozen revision: an explicit destination supplied by the owning contract — `v.t`
   from `switchBindingLines` (`:5528`) and the callee parameter on the argument route — with
   `types.of(sw.t)` retained only as the no-contract fallback. The change exists **uncommitted in the
   worktree**, not in `c8ae0054`; it must be committed and the revision re-frozen (or the review
   target changed). **`GATE-LEDGER.md` P08-1 must be corrected regardless**: it currently credits
   this revision with a fix that is not on it.
3. **Obligation 1 — the lambda single-statement fast path drops the boundary conversion.**
   `functionLiteralInner:2372` emits `expr(r)` with no destination conversion. Measured
   counterexample: `P-LAM-SINGLE` → `swiftc -c -WMO` rc=1,
   `declared closure result 'ReadOnlyArray<Int32>' is incompatible with return type
   'TiqianArray<Int32>'`. Required: apply the boundary conversion on that path, or demonstrate the
   shape is unreachable from accepted source. The candidate's own commit message already concedes it
   is unmeasured; it is now measured and it fails.
4. **Ledger correction — `GATE-LEDGER.md` P08-3.** The row must record that laziness was measured on
   `c8ae0054` by this review (7/7 on four routes), replacing "lazy effects were never measured", and
   should publish what `F3` requires so it can be discharged rather than inherited.

### What an acceptance would have to name (for the record)

I accept **nothing**. If a later review accepts, it must name the revision hash, the exact
`swiftc -c` diagnostic count of zero, and the revision on which the `switchExpression` destination
handoff and the lambda fast-path repair are both present. On `c8ae0054` none of those three hold
together.

### What would NOT change this verdict

More green runs of the acceptance fixture (already 30/30 on this revision, and already green when the
implementation review rejected); the prior reviews' agreement (both are inputs and one is a REJECT);
or `-typecheck` cleanliness, which is the recorded trap and is clean while `-c` is not.

---

## 6. Not-verified list

1. **The repository's own test suite and CI at this revision — not run.** Blocker: not needed to judge
   the three obligations, and running `bun test` would have re-triggered the `MathNaNTestSupport.hx`
   trap deliberately. The acceptance fixture's steps were executed by hand instead.
2. **Other targets and the compiler's own suite (Kotlin/Rust/TS/Dart) — not verified.** Out of P08's
   scope; `REFREEZE.md` §7.2 records the same limit.
3. **`@:native`-typed arrays and `SwiftExpr`-bypassing intrinsics — not verified.** Blocker: declared
   out of scope by `RECORD.md`, and no fixture exercises them.
4. **The read-only→mutable direction, generic/abstract destinations, nested-collection element
   destinations — not probed.** Blocker: budget; the implementation review argued the
   read-only→mutable route is rejected by Haxe typing at these routes, which I did not re-test.
5. **Whether `sw.t` can ever differ from the declared binding type — not falsified, not proven
   impossible.** I report "no divergence observed", and I did not rerun the prior review's 11-generation
   instrumented sweep; my statement rests on [CODE] plus the prior review's [EXEC] input.
6. **The `F3` definition — not locatable.** Blocker: only `REFREEZE.md:190` cites the label; no
   definition was reachable. My laziness measurement therefore answers my own construction of the
   observable, not necessarily the programme's.
7. **The `will never be executed` diagnostic under other Swift versions or flags — not verified.**
   Single toolchain: Swift 6.2.4 (swift-6.2.4-RELEASE), x86_64-unknown-linux-gnu; haxe 4.3.7;
   `HAXELIB_PATH` per `chainA-fixed-rerun/evidence/env.json`. The host-side `libc not found` line is a
   shim/SDK message, not a diagnostic about generated code.
8. **Whether the fixture's `-c` assertion at the later commit `d14231a6` is correct — not verified.**
   Blocker: that revision is not the frozen one, so it is not evidence about `c8ae0054`.
9. **Full re-audit of all nine derivation sites in obligation 1 — not done.** I read the frozen diff
   and the three sites the dispatch names; the remaining sites are reported as still present by [CODE]
   reading only.

---

## 7. Evidence index (`evidence/`)

| file | what it is |
|---|---|
| `00-revision-pin.txt` | `git rev-parse` output for the commit, its tree, the `SwiftExpr.hx` blob, plus worktree status |
| `01-candidate-swiftexpr.patch` | the complete `SwiftExpr.hx` change in `c8ae0054` (two hunks) |
| `02-generated-identities.sha256` | sha256 of the four generated Swift files |
| `gen.{stdout,stderr,rc}` | gap-fixture generation on the frozen export |
| `swiftc-c.{stdout,stderr,rc}` | **obligation 2**: the 1-diagnostic `-c -WMO` measurement |
| `swiftc-c-trap.{stdout,stderr,rc}` | the plain multi-file `-c -o` trap (rc=1, no object) |
| `typecheck.{stdout,stderr,rc}` | the recorded `-typecheck` trap (rc=0, 0 diagnostics) |
| `acc.*` | acceptance fixture: generation, build, run, `-c` diagnostics, oracle, normalized diff |
| `gaprt.*` | my runtime harness for the **changed** gap routes vs the Haxe oracle (23/23) |
| `probe-lam*` | the single-statement lambda counterexample (1 error) + multi-statement control |
| `probe-blk*` | the `blockExpression` argument/return/initializer probes (0 diagnostics) |
| `probe-laz*`, `laz.*` | the laziness / single-evaluation probe vs the Haxe oracle (7/7) |
| `GapOracle.hx`, `gaprt-main.swift`, `probe-*.hx`, `probe-laz-main.swift` | verbatim probe and oracle sources |
| `generated-Gap.swift`, `probe-*-generated-*.swift` | the generated Swift the claims are made about |
| `swift-frozen.hxml`, `acc.hxml`, `oracle-with-reflaxe.hxml` | the drivers used |
| `03-trap-restore.txt` | the `MathNaNTestSupport.hx` trap: before/after readings and the instructed restore (I wrote no repository file) |

*(End of report.)*
