# P08 IMPLEMENTATION review — Swift ordinary read-only array boundary

Reviewer role: **IMPLEMENTATION reviewer**, the second of the two separately recorded reviews that
the P08 acceptance condition requires. The first review (behaviour, `dc-warn/out/p08-behaviour-review/REPORT.md`)
is treated here as an *input whose coverage I deliberately complement*, never as evidence for
acceptance. My questions are the ones SOL2 and ASTRA wrote into obligation 1: **what fact does each
changed site use, who owns that fact for that route, and is in-scope reconstruction removed** — plus
my own re-measurement of obligation 2 and the behaviour-review blind spots the task names.

Method labels:

- **[EXEC]** — I executed the cited command on a host-local copy and quote its measured result.
- **[CODE]** — I read the cited source and verified the statement myself.
- **[DOC]** — a document asserts it; I did not re-verify.
- **[UNVERIFIED]** — could not be established; blocker named in §7.

Nothing in the coordination tree or in the scratch worktree was modified; no test was edited. All
runs used host-local copies (`/tmp/p08ir/cand` = candidate, `/tmp/p08ir/base` = pristine
`boring-wt-architecture`), restored to the exact hashes in §0 after two instrumented sweeps.

---

## 0. Anchors

| artifact | anchor measured by me |
|---|---|
| candidate worktree | `dc-warn/swc-try-fix-wt/wt/` |
| candidate `SwiftExpr.hx` | sha256 `bf7dde2cec3b89464738019c733eb6f1d8e666bbc976176bf30cc77007be6078`, 7041 lines |
| baseline `SwiftExpr.hx` | sha256 `0a9bed91ef91ca68b75a2e7e4e2482d2743a16fe5caf4150018686c2131e33f0`, 7001 lines |
| `SwiftArrayBoundary.hx` (both trees, identical) | `b522865c…f6575` — **unchanged by the candidate** |
| `SwiftDecl.hx` (both trees, identical) | `0210d207…4f973` — **unchanged by the candidate** |
| `PATCH.diff` | verified **equal** to `diff(boring-wt-architecture, wt)` for `SwiftExpr.hx` (only the `---`/`+++` header lines differ) **[EXEC]** |
| whole-tree difference | outside `out/`, `node_modules/`, `.git/`, **`SwiftExpr.hx` is the only differing file** (`diff -rq`, rc 0) **[EXEC]** |
| coordination tree | `boring-wt-architecture` was **not written to** by this review (every write went to `/tmp/p08ir` or to my own output directory); `git status --porcelain` = 25 entries, md5 `2ddbdbeeb8188cb362a4f88e534829ee`, measured after all runs **[EXEC]** |
| `samples/boring/MathNaNTestSupport.hx` | intact in both trees (`grep -c 'Test.equals'` = **5**) before and after every run **[EXEC]** |
| toolchain | haxe 4.3.7; swiftc 6.2.4 via `p09-chainA-work/swift-shim-bin` (PATH from `chainA-fixed-rerun/evidence/env.json`) |
| full identity list | `evidence/identity.txt` |

So the object under review is a **single-file patch of 9 hunks**, and the two trees agree everywhere
else. That is the whole candidate; there is no second hidden change to attribute.

---

## 1. Changed-site inventory, with the fact-source authority for each

Every hunk is in `packages/compiler/reflaxe/swift/swiftcompiler/SwiftExpr.hx` (candidate line numbers).

| # | site | change | fact now used | producer of that fact | authoritative *for that route*? |
|---|---|---|---|---|---|
| 1 | `stmtLines`, `TReturn`+`TSwitch` `:805-810` | add 4th arg `destination = currentReturnType` | "the return contract being satisfied" | `currentReturnType`, set once per **member** at `:544` from `Context.follow(f.field.type)` | **only when the return belongs to the member function.** `functionLiteral` `:2338-2358` does **not** rebind it (it saves/restores only `currentFuncReturnsOptional`), so inside a lambda it is the enclosing member's type. **Not authoritative** for a lambda body — see §4.1 |
| 2 | new helper `destinationValueText` `:2580-2587` | convert iff `isReadOnlyArrayType(dest) && isBoundary(value.t, dest)`, else return the caller's already-rendered text | destination `Type` (read-only face) | the caller | caller-dependent; handles **only** mutable→read-only (see §4.3) |
| 3 | `lowerArrayConditionalBoundary` nil-merge target arm `:2646` | `destinationOptionalOverride` → `true` (SW04) | "the target arm crosses an **optional intermediate** destination" | composed here from the approved J2 rule | **yes** — the fallback arm keeps the real override at `:2647` and the outer `prepare` `:2625` re-validates the joined result **[CODE]**, and the class-level xcheck in `dc-warn/sw04-xcheck/REPORT.md` could not falsify it |
| 4 | `tryBindingLines` body arm `:5253`, handler arm `:5267` | arms convert via `destinationValueText(expr, v.t, rendered)` | the **binding's declared type** `v.t` — the same type the emitted declaration `kw + name + ": " + types.of(v.t)` promises | the declaration selection (`TVar v`) at that site | **yes** — verified by execution inside a lambda (§4.1) where the member return type differs |
| 5 | `tryReturnLines` body arm `:5296`, handler arm `:5310` | arms convert against `currentReturnType` | "the return contract being satisfied" | same `currentReturnType` as row 1 | **not in general** — same lambda defect; the candidate's REPORT §3 claim "the return contract being satisfied → currentReturnType" is false for any return whose contract is not the member's. **Residual failure measured** (§4.1) |
| 6 | `switchAssign` `:5536-5546` | `switchReturn(sw, depth, true, target.t)` | the **assignment place's** type `target.t` | the `TBinop(OpAssign, target, …)` dispatch at `:819-820` | **yes** for locals and fields, including nullable read-only targets (`isReadOnlyArrayType` matches the face and ignores the wrapper — `SourceContainerAnalysis`): `h.slot = ReadOnlyArray(…)` measured **[EXEC]** |
| 7 | `switchExpression` `:5554-5559` | `switchReturn(sw, 1, false, sw.t)`; closure still declares `types.of(sw.t)` | the switch expression's **own** AST type | the typer's expected-type propagation into the `TSwitch` | **self-consistent but derived**: the owning contract at the binding call site is `v.t`, at an argument it is the parameter type. It works today because Haxe propagates the expected type; the declaration `let <name> = <closure>()` carries **no annotation** (`:5516`), so nothing else enforces it. See §4.2 (sweep: no divergence observed) |
| 8 | `switchReturn` `:5604` | new `destination:Null<Type> = null` parameter threaded to `armLines` `:5638` | — | — | the interface extension SOL2 called sufficient ("a small explicit interface") |
| 9 | `armLines` `:5649-5684` | `OtherStatement(s, returnValue, isLast)`: explicit-return arms use `boundaryDestination = destination ?? currentReturnType` `:5675`; the **last plain** arm converts only when `destination != null` `:5680-5683` | row-6/7 destination, else `currentReturnType` | caller / member return type | same split as rows 5–7 |
| — | `switchStatement` `:5520-5533` | **unchanged**: still `switchReturn(sw, depth, true)` with no destination | `currentReturnType` via the fallback in `armLines` | — | statement-position plain arms are deliberately not converted; their `return ` lines are still stripped by string surgery `:5523` |

### Sites where a destination is still **derived**, not obtained from the owning contract

1. **`switchExpression` `:5559` / `armLines` rows 7 & 9 — `sw.t`.** The destination is read off the
   switch expression's AST type while the closure declaration is printed from the *same* type. The
   converter and the declaration therefore cannot disagree with each other, but neither is the
   owning contract. `switchBindingLines` `:5514-5517` (call at `:5516`) is the concrete route: it initialises a local
   of declared type `v.t` and never mentions `v.t`. This is the same class of derivation the
   behaviour review listed as conflation #2; the candidate keeps it, and at this route it is the
   *only* thing standing between a correctly-typed closure and a broken one.
2. **`tryReturnLines` / `stmtLines`-return / `armLines` fallback — `currentReturnType`.** A member-level
   field, not the return contract of the function actually being returned from (lambdas). §4.1
   measures the resulting failure on the candidate.
3. **`lowerArrayBoundary` `:2634` `sourceType: target`** — the returned operand's source meaning is
   overwritten with the destination (behaviour review's conflation #5). Untouched; no consumer reads
   it today **[CODE]**.
4. **`platformModuleCall` `:4373`** — `arrayRuntimeText("TiqianArray(" + text + ")")` fabricates a
   target representation from an AST return type. Untouched; not on P08's inputs.
5. **closure result types from `types.of(<AST type>)`** at `:1205` (`blockExpression`), `:1968`
   (`TEnumParameter`), `:5559` (`switchExpression`). Untouched except row 7.
6. **`nilMergeChainNonOptional` `:2050-2055`** parses `" ?? "` out of a *rendered string*, consumed at
   `:4795` (`callArgTexts`) and `:4898` (constructor args). Untouched — §3 measures its reachability.
7. **`switchAssign` `:5541` / `switchStatement` `:5523`** move an already-printed line by string
   surgery (`startsWith(indent + "return ")`, `indexOf("return ")`). Untouched; the candidate only
   ensures the spliced text is now correctly converted.
8. **`SwiftDecl.hx:581-605`** — the **second planner entry point**: the static read-only field
   initializer hand-builds a `SwiftArrayPreparedOperand` (`:590-598`, stamping `LiteralProvenPresent`
   at `:597` on *any* non-null initializer) and calls `SwiftArrayBoundary.prepare`/`render` directly
   (`:599`, `:604`) instead of `SwiftExpr.lowerArrayBoundary`. The candidate did not unify the two
   entry points. §4.4 measures the input domain that keeps them from competing today.

---

## 2. Obligation 2 measured myself (exit codes captured directly, never through a pipe)

All commands: `cmd > log 2>&1; echo $? > log.rc`. Raw logs in `evidence/`.

**Acceptance fixture** (`tests/swift-readonly-boundary/swift.hxml`, cwd = candidate copy):

| step | result |
|---|---|
| generation | **rc=0** (`gen-acceptance-cand.log` empty, `.rc` = 0) |
| `swiftc -typecheck` over **all 6** generated `.swift` files (incl. `Test.swift`) | **rc=0**, `: error:` = **0**, `: warning:` = **0** (`typecheck-acceptance-cand.log`) |

**Gap fixture** (`gap-fixture-archive/fixture/swift-archived.hxml`, fresh absolute `-D swift-output`, cwd = candidate copy):

| step | result |
|---|---|
| generation | **rc=0** (`gen-gap-cand.log` empty) |
| `swiftc -typecheck` over the 4 emitted files | **rc=0**, `: error:` = **0**, `: warning:` = **2** |
| emitted `Gap.swift` | sha256 `2be5e102d695146439d3fdab3c1aeee7f8096d7d1460b92fd9535055c70c02ab`, byte-identical to the candidate's own `gen-gap-fixed/gap/Gap.swift` **[EXEC]** |

**Obligation 2 as written is therefore not satisfied, and not only formally.** SOL2's table requires
"native compilation succeeds with **zero diagnostics** on those same candidate inputs"; ASTRA's
requires "`swiftc` exits zero and **required diagnostics are empty**". `swiftc` exits zero on the gap
fixture but prints **two diagnostics**, and those two are not cosmetic: they mark a **swallowed
control exit**, and I measured the wrong result by execution:

```
candidate generated Swift, executed:
  explicitReturn(one).count=2
  explicitReturn(two).count=2          <- wrong
Haxe eval oracle (haxe --interp, evidence/oracle-gap-haxe.out):
  explicitReturn(one).length=2
  explicitReturn(two).length=1
```

`GapExplicitReturn.switchExplicitReturn` drops the arm `return` (statement-position switch strips
every `return ` at `:5523`) and then always executes the trailing `return Gap.sourceFirst()`; so
`.two` yields `[1,2]` rather than `[3]`. The archive's own `README.md:149-151,181-182` already warns
that "zero errors" is too weak for exactly this case and asks the owner to decide between zero
diagnostics and an allowlist; the candidate's REPORT §4 declares the two warnings "pre-existing …
out of scope" without obtaining that ruling.

**Attribution is clear and in the candidate's favour as a *regression* question** — the whole
`GapExplicitReturn` block is byte-identical in base and candidate (`evidence/gap-base-vs-cand.diff`
changes exactly the 7 switch/try value sites and nothing else) — but an obligation stated as a
property of the frozen candidate is not discharged by showing the defect is old. It is a gate-owner
ruling, not a reviewer's waiver.

**Obligation 3 on the acceptance fixture, measured by execution (my own, not the first review's):**

| step | result |
|---|---|
| native build of `Runtime.swift`, `Test.swift`, both `std/…`, `boring/ReadOnlyBoundaryOps.swift` + `tests/swift-readonly-boundary/ReadOnlyBoundaryRuntimeTests.swift` | **rc=0, 0 diagnostics** (`build-acceptance-runtime.log` empty) |
| binary run | rc=0, 30 lines |
| vs Haxe oracle *actual* output (`haxe tests/swift-readonly-boundary/oracle.hxml`, rc=0) | `diff` **empty — byte-identical** |

So the *acceptance* fixture preserves the source behaviour (alias sharing, lifetime, single
evaluation, null/default outcomes, both branches) on this candidate. The gap fixture's control-exit
case does not.

---

## 3. Reconstruction audit

The consultation requires the implementation review to report whether in-scope reconstruction is
removed. It is not. Nine derivation sites exist (§1); the candidate removes **none** of them and adds
one more typed handoff. What I can add to the first review is *which* of them the patch actually
touches on a live path:

| beyond-fixture risk named in the dispatch | verdict | how established |
|---|---|---|
| the `" ?? "` parser (`nilMergeChainNonOptional`) | **left in place; not on P08's path** | instrumented both trees to print every invocation; **0 invocations** across 8 generations (gap, acceptance, probes A/B/D, 5 repo Swift fixtures); traces identical **[EXEC]** |
| `switchExpression`'s `sw.t` (AST-derived closure type + arm destination) | **on a path the candidate newly exercises, and now load-bearing** | `switchExpression` is reached from `expr(TSwitch)` `:1857` for *every* switch in expression position; the candidate made `sw.t` both the printed closure type and the conversion destination, so the two can no longer disagree — but `switchBindingLines` still prints no annotation (`:5516`). Sweep in §4.2 **[EXEC]** |
| `switchAssign` / `switchStatement` string surgery | **left in place; newly fed converted text** | the spliced text is still located by `startsWith(indent + "return ")` `:5541` / `indexOf("return ")` `:5523`; measured correct on all exercised inputs because every conversion the candidate can emit is single-line (`render` `:254-260`, `lowerArrayConditionalBoundary` `:2669`) **[CODE]** |
| duplicated planner ownership (`SwiftDecl.hx:599/604`) | **left in place; input domain gates it** | §4.4 **[EXEC]** |
| `sourceType: target` overwrite, `platformModuleCall` fabrication, `TEnumParameter` closure type | **left in place; no P08 input reaches them** | `[CODE]`; no consumer of `operand.sourceType` exists |

The new interface is exactly what the consultation said would be sufficient — a `Null<Type>`
destination parameter, no target IR. The problem is not its size; it is that **three of the four new
call sites supply a type the route does not own** (rows 5, 7, 9 in §1).

---

## 4. What a behaviour review would not catch

### 4.1 The return contract is not the route's destination for a lambda — measured failure that survives the patch

`functionLiteral` `:2338-2345` saves and restores `currentFuncReturnsOptional` only;
`currentReturnType` is written **once per member** at `:544` and cleared at `:563`. A `return` inside
a lambda therefore satisfies the *member's* return type, not the lambda's `f.t` — even though
`functionLiteralInner` prints the closure head from `f.t` `:2347-2349`.

Probe (plain accepted Haxe; `evidence/probes/probeE/`), member returns `Int`, lambda returns `ReadOnlyArray<Int>`:

```haxe
public static function lambdaTryReturn(flag:Bool):Int {
    var f = function(flag:Bool):ReadOnlyArray<Int> {
        if (flag) throw new PEError();
        return try { PESources.arr1(); } catch (e:PEError) { PESources.arr2(); }
    }
    return PESources.consume(f(flag));
}
```

Measured with the candidate compiler **[EXEC]**:

```swift
let f = { (flag: Bool) -> ReadOnlyArray<Int32> in
    ...
    do { return PESources.arr1() } catch is PEError { return PESources.arr2() } ...
}
```
`swiftc -typecheck` → **rc=1, 1 error**: `PE.swift:33:26: cannot convert value of type
'TiqianArray<Int32>' to closure result type 'ReadOnlyArray<Int32>'` (base: the same error plus the
sibling). The **same probe's `tryBindingLines` case, which is handed `v.t`, converts correctly**
(`view = ReadOnlyArray(PESources.arr1())`; base 2 errors → candidate 0). That isolates the fact
source: `v.t` is authoritative, `currentReturnType` is not.

This is not a regression (base fails identically) but it is a **counterexample to the candidate's own
claim** that every value-producing route now carries its actual destination, and it is the exact
failure mode SOL2/ASTRA named ("a local initializer cannot borrow the enclosing function's unrelated
return type") reproduced one level out, on `tryReturnLines`, the return-position switch `:810`, and
the `armLines` fallback `:5675`.

### 4.2 `switchBindingLines` relies on the switch's own AST type — sweep, no divergence observed

I instrumented `switchBindingLines` (`#if p08trace`, my copy only) to warn whenever
`types.of(sw.t) != types.of(v.t)` — i.e. whenever the derived destination is *not* the declared one —
and regenerated: acceptance, gap, probes A/B/C/D, and 5 repo Swift fixtures
(`readonly-alias`, `view-lifetime`, `source-container-policy`, `try-tail`, `swift-rt-probe`).
**Zero divergences** (`evidence/sweep-switchbinding.log`). Two wrapper shapes that defeat
expected-type propagation in other compilers — `{ switch … }` and `( switch … )` — also kept
`sw.t == v.t` on the candidate **[EXEC]** (`probeC`).

Verdict: **accidentally right today.** The route is correct only because Haxe propagates the
expected type into the `TSwitch`; nothing in the emitted declaration enforces it. If an unrelated
signature/typing change stops that propagation, `switchBindingLines` silently emits
`let view = ({ () -> TiqianArray<Int32> in … })()` and the failure moves downstream. I could not
falsify it on the exercised corpus, so I report it as a required-by-obligation-1 change, not as a
demonstrated defect — and I distinguish the two explicitly.

### 4.3 The read-only→mutable direction is not converted at any new site — reachability ruled out

`destinationValueText` `:2583` and the new `armLines` plain-arm branch `:5680-5682` both gate on
`isReadOnlyArrayType(destination)`. The reverse crossing (`ReadOnlyArray` → `Array`) is handled
elsewhere (`SwiftArrayBoundary.prepare` `destMutable`, `.toMutableArray()`). I tried to build the
route (`probeB`, `var out:Array<Int> = try { ro1(); } …` and the switch equivalent): **Haxe rejects
it** — `std.ReadOnlyArray<Int> should be Array<Int>` — because `samples/std/ReadOnlyArray.hx`
declares only `from Array<T>`, no `to`. The asymmetry is therefore **not reachable from accepted
source** at these routes, and I do **not** report it as a defect. (It remains reachable through an
explicit typed cast, which is a different route.)

### 4.4 The second planner entry point cannot disagree today — because its input domain is gated

`SwiftDecl.hx:581-605` builds its operand by hand and stamps `LiteralProvenPresent` on *any*
non-null initializer. I tried to reach it with the shapes that would expose the over-claim:

| static read-only field initializer | result |
|---|---|
| `= switch (PCChoice.One) { … }` | generation **rc=1** — `static field initializers accept null, literal, array, and construction forms only` |
| `= maybe == null ? [] : maybe` (nil-merge) | generation **rc=1** — same policy rejection |

So the duplicate authority is real but confined to sanctioned literal/construction forms; it cannot
today consume a switch/try value and double-convert. The behaviour review's open item "can
`LiteralProvenPresent` on a non-literal produce a bad emission" stays [UNVERIFIED], but the policy
gate is the reason no accepted source reaches it — a stronger statement than "no counterexample found".

### 4.5 Two route facts that sharpen the inventory

1. **`try` regions cannot end in a ternary, switch, assignment, `var`, `return` or `while`**:
   `PolicyQueries.blockValueParts` returns `value = null` for all of them, and
   `tryBindingLines` `:5243` then fails with `try region body has no value`. Measured on **both**
   trees (`probeD`: a nil-merge-tailed try body; `probeE`: a switch-tailed one). Consequence: the
   `destinationValueText` nil-merge path can never be exercised at a try site, and the "try route
   now carries its destination" repair covers a narrower tail shape than reading the patch suggests.
   Pre-existing, but it bounds the claim.
2. **Statement-position assignment arms are converted by `assignmentValue`, not by `armLines`.**
   `GapPaths2.switchStatementPath` and `probeA.switchStmtAssignField` are byte-identical in base and
   candidate **[EXEC]** — the assignment route was already right. The candidate's new `armLines`
   destination is therefore not the only authority on an assignment-shaped arm, which is worth
   knowing before anyone treats `armLines` as the single consumption point.

### 4.6 The focused harness cannot produce the candidate's own obligation-2 evidence

`bun test tests/swift-readonly-boundary/` in my copy: **rc=1 at
`readonly-boundary.test.ts:55`** — the oracle-step expectation — before generation, before `swiftc`,
before the runtime comparison (`evidence/bun-readonly-boundary-cand.log`). The tracked expectation
says `branch-true=1:1` / `branch-false=2:1`; the tracked oracle prints, in **both** trees and
byte-identically, `branch-true=1:present` / `branch-false=1:present`
(`evidence/oracle-readonly-{base,cand}.raw`). The current ops return
`view.length + ":present|:empty"` (`ReadOnlyBoundaryOps.hx:229-231`), so the expectation predates the
current helper. **This is a stale expectation in a tracked test; I did not edit it**, and I flag it
because until the owner rules it, the repo's own collector red-lights at a step that has nothing to
do with the patch — which is precisely how a passing scratch run can leave the guard absent.

---

## 5. Claim ledger — verified by execution vs read in source

| claim | status |
|---|---|
| `PATCH.diff` == the real single-file diff; `SwiftExpr.hx` is the only differing file | **[EXEC]** |
| obligation 2 · acceptance fixture: gen rc=0, swiftc rc=0, 0 diagnostics | **[EXEC]** |
| obligation 2 · gap fixture: gen rc=0, swiftc rc=0, **2 warnings**, wrong `.two` control exit | **[EXEC]** |
| obligation 3 · acceptance fixture: 0-diagnostic build, runtime == oracle byte-for-byte (30 lines) | **[EXEC]** |
| 7 gap sites converted, W1 block untouched | **[EXEC]** `gap-base-vs-cand.diff` |
| probeA/B/D: 8, 2, 2 base errors → 0 candidate errors (catch-bound var, nullable field target, empty-literal arm, nil-merge arm, effectful try) | **[EXEC]** |
| probeE: `tryBindingLines` in a lambda correct; `tryReturnLines` in a lambda still wrong | **[EXEC]** |
| `currentReturnType` is member-scoped and not rebound by `functionLiteral` | **[CODE]** |
| `sw.t == v.t` at every exercised `switchBindingLines` site (11 generations) | **[EXEC]** |
| read-only→mutable at try/switch routes rejected by Haxe typing | **[EXEC]** |
| switch/nil-merge static initializers rejected by policy | **[EXEC]** |
| `nilMergeChainNonOptional` invoked 0× on both trees across 8 generations | **[EXEC]** |
| try regions with TIf/TBlock/assign tails abort identically on both trees | **[EXEC]** |
| `LiteralProvenPresent` over-claim harmful in principle | **[UNVERIFIED]** — blocked by the initializer-form policy |
| double-conversion / repeated-render corruption in the new `destinationValueText` path | **not observed**; a second render does occur (`blockValueLines` renders, then `arrayBoundaryText` re-renders), but names are memoised and every probe output is correct **[EXEC + CODE]**, not proven impossible |

---

## 6. Verdict — **REJECT** the candidate for P08 acceptance

The candidate is a genuine, well-aimed improvement: it converts 7 previously-unconverted switch/try
value sites, it generalises to shapes the fixture does not contain (8/2/2-error probes → 0), it fixes
a lambda switch and a nullable field target, and it keeps the acceptance fixture's runtime
byte-identical to the oracle. It is nonetheless **not acceptable against the three obligations as
the two consultations wrote them**, for two independent reasons — one measured, one structural.

**REJECT, with these exact conditions.**

1. **Obligation 2 (legal generated output — zero diagnostics).** On the candidate's own gap-fixture
   input, `swiftc -typecheck` prints **2 diagnostics**, and the same two sites are a wrong control
   exit (`switchExplicitReturn(.two)` → `2`, oracle `1`). Fix or obtain a written gate ruling:
   - either stop `switchStatement` `:5520-5533` from stripping `return ` out of arms that were
     emitted *as* returns (the explicit-return arm in `armLines` is distinguishable: the value came
     from `OtherStatement(s, returnValue != null, …)`), so the arms keep their exits;
   - or have the gate owner record an explicit warning allowlist for the two `[#no-usage]`
     diagnostics, in writing, as the archive's `README.md:181-182` asks. A reviewer cannot waive an
     obligation; only the owner can.

2. **Obligation 1 (correct fact-and-requirement handoffs — actual destinations; in-scope
   reconstruction removed).** `currentReturnType` is the **member's** return type, written once at
   `:544` and not rebound by `functionLiteral` `:2338-2345`. Therefore the sites the candidate
   repaired with it — `tryReturnLines` `:5296/:5310`, the return-position switch `:810`, the
   `armLines` fallback `:5675` — still borrow the enclosing function's unrelated return type whenever
   the return contract belongs to a lambda. Required change: carry the **actual return contract**
   (seeded from `f.t` for a literal, saved/restored around `functionLiteralInner`) and use it at
   `:810`, `:5296`, `:5310`, `:5675`. Acceptance evidence: `probeE`-shaped input typechecks with 0
   diagnostics, plus the existing fixtures.

3. **Obligation 1 (remove in-scope reconstruction).** `switchExpression` `:5559` /
   `switchBindingLines` `:5514-5517` (call at `:5516`) still derive both the closure result type and the arm
   destination from the switch's own AST type, and the emitted local carries no annotation. Required
   change: give `switchExpression` an explicit destination parameter supplied by the owning contract
   (`v.t` for the binding route, the callee parameter at argument routes), keeping `types.of(sw.t)`
   only as the fallback for expression positions that genuinely have no contract. I observed **no
   divergence** in 11 instrumented generations (§4.2); this condition rests on obligation 1's
   "in-scope reconstruction is removed" wording, not on a demonstrated failure, and I state that
   distinction rather than dress it as a defect.

4. **Not a condition on the patch, but on the delivery:** the repo's own collector
   (`tests/swift-readonly-boundary/readonly-boundary.test.ts:55`) is red on a **stale expectation**
   in both trees, so no repo command currently exercises the candidate's generation/`swiftc`/runtime
   claims; the gap fixture has no collector at all. The stale expectation needs an owner ruling (I
   did not touch it), and the two focused observations need to enter a routine command before the
   delivery can claim "durable collection".

**What would not change my verdict.** More passing runs of the acceptance fixture (already green),
or the first behaviour review's agreement (it explicitly forecast that either axis alone would be
read as closure — §Q5). Both of my rejection reasons are outside that review's scope: it read
`currentReturnType` as "the return contract" too and did not test a lambda, and it recorded the W1
warnings without connecting them to obligation 2's "zero diagnostics".

**Ancillary finding (report, do not edit):** the tracked expectation vs tracked oracle mismatch above
is a real defect in the test asset, reproducible in the pristine tree, independent of this patch.

---

## 7. What I could NOT verify

1. **`LiteralProvenPresent` on a non-literal static read-only initializer — not verified.** Blocker:
   the initializer-form policy rejects every non-sanctioned form before `SwiftDecl.hx:581-605` runs
   (two rejections measured). I can say no *accepted* source reaches the over-claim; I cannot say the
   over-claim is sound if the policy is widened.
2. **Double conversion / repeated-render corruption in `destinationValueText` — not verified as
   impossible.** A second render does occur; all 5 probes are correct; `localName` is memoised and
   `expr` has other stateful paths (e.g. `constructorParameterValues`, fresh-name counters) that I
   did not exhaustively test.
3. **Whether `sw.t` can ever differ from the declared binding type — not falsified, not proven
   impossible.** 11 instrumented generations show none; the property rests on Haxe's expected-type
   propagation, which is not a contract this backend enforces.
4. **The gap fixture's runtime behaviour as a whole — not verified.** I executed the W1 function
   only; the fixture ships no oracle or test runner (`tests-gap` is never created).
5. **CI collection of either focused fixture — not verified.** I confirmed the repo test is red and
   read the CI finding second-hand; I did not run CI.

---

## 8. Evidence index

| file | what it is |
|---|---|
| `identity.txt` | hashes/line counts of both trees, PATCH equivalence, toolchain |
| `gen-acceptance-cand.{log,rc}`, `typecheck-acceptance-cand.{log,rc}`, `typecheck-acceptance-filelist.txt` | obligation 2, acceptance fixture |
| `gen-gap-cand.{log,rc}`, `gen-gap-base.log`, `typecheck-gap-cand.{log,rc}`, `gap-base-vs-cand.diff` | obligation 2, gap fixture + attribution |
| `build-acceptance-runtime.{log,rc}`, `run-acceptance-runtime.{out,err}`, `oracle-readonly-{cand,base}.raw`, `oracle-readonly-normalized.txt` | obligation 3, acceptance fixture, by execution |
| `oracle-gap-haxe.{out,rc}`, `OracleMain.hx`, `main.swift`, `build-gapdemo.{log,rc}`, `run-gapdemo.out` | Haxe oracle vs candidate Swift for W1 |
| `gen-probe{A..E}-{cand,base}.{log,rc}`, `typecheck-probe{A..E}-{cand,base}.{log,rc}` | my route probes (§4.1–4.5) |
| `probeA-base-vs-cand.diff` | exactly which sites the candidate changes on probeA |
| `sweep-switchbinding.log` | instrumented `sw.t` vs `v.t` sweep (11 generations, 0 divergences) |
| `nmc-trace{,2}-{cand,base}.txt` | instrumented `nilMergeChainNonOptional` reachability (0 invocations) |
| `bun-readonly-boundary-cand.{log,rc}` | the focused harness aborting at the oracle step |
| `probes/` | verbatim copies of every probe fixture + its hxml |
