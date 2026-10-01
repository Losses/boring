# throwing-default: Observing the function failure domain of a throwable call in a default argument

Task `t-mum0wts5-jh3m` (branch `audit/default-arg-throwing-domain`, base `e8648488`).
This directory is an isolated observation fixture: the default expression E of a coalescing default is a throwable static call, triggered by omitting the argument, comparing the function failure domain, call markers, and try region absorption between Rust and Swift.
This is a measurement task, not a target fix: all readings live in `out/throwing-default/<attempt>/` (gitignored).

## 1. Admission determination (before any observation)

The B/D cross-review (board timeline seq 2/3) worried that spec 22 V16 restricts default expressions to pure-constant / closed coalescing classes, so a throwable call might fall outside the accepted source domain. Measured conclusion: **split in two**.

| Source shape | Verdict | Raw output (att-20261001T000709Z) |
|---|---|---|
| Calling directly in default position `p:Int = g(2)` | **Rejected**, rc=1 | `PDefaultPosition.hx:15: characters 30-34 : default argument values accept compile-time constants only` |
| Throwable call inside coalescing default (`?value` + `value == null ? throwingFallback(seed) : value`) | **Accepted**, rc=0, empty output | `stages/admit-coalescing-throwing/status` = 0 |

Clause basis (document citation, not measured):

- `docs/specs/features/22-default-argument-expansion.md` L68-74 (rule 1): the default position accepts only constants, "Any other expression in default position is rejected with the named error `default argument values accept compile-time constants only`".
- Same file L173-188 (Extension Stage A grammar): the closed grammar of coalescing E **includes** the static call / instance method call roots, and the grammar determination carries no fallibility condition; `packages/compiler/DefaultArgExpander.hx` L695-750 (`validateCoalescingGrammar` rule 6) is measured to be pure grammar matching, not checking whether the called function is throwable.
- `docs/specs/style/01-haxe-style-standard.md` L65 (the V16 NonConstantDefault row).

So the reviewer's concern holds only for the **default position**; the coalescing shape this task asks about is within the source domain, the task premise holds, and the line does not shrink. Acceptance itself does not prove the site is registered as a coalescing default (a plain ternary is also legal); registration is proven by the generated artifacts (the `unwrap_or_else` / `= nil` + body normalization in §3 are all products of the registration machinery).

## 2. Fixture structure

`throwdef/ThrowingDefaultOps.hx`:

- `throwingFallback(seed)`: throwable callee (throws `ThrowingDefaultException(OverThreshold(seed))` when seed>10).
- `resolve(seed, ?value)`: coalescing default, E = `throwingFallback(seed)` (reads the earlier argument).
- raw call layer (failure-domain observation subjects, not called by the harness): `callOmittedSafe`=`resolve(5)`, `callOmittedThrowing`=`resolve(20)`, `callExplicit`=`resolve(5, 9)`.
- probe layer (region absorption surface returning a uniform `String`, harness entry point): three `final outcome = try { "ok:"+… } catch (error:ThrowingDefaultException) { "caught:"+… }`.

Two call shapes: **omitted argument** (default evaluated, the throwable call actually executes) and **explicit argument** (default not evaluated, the throwable call does not execute). Explicit null materialization (feature 51) is not in this line, untested.

Haxe oracle (plain Haxe 4.3.7, no Intercept, spec 22 "Oracle standing"):

```
omittedSafe=ok:10
omittedThrowing=caught:OverThreshold:20
explicit=ok:9
```

## 3. Observation matrix (two shapes × two targets, all measured)

Generated-artifact line references are taken from the evidence copy `out/throwing-default/att-20261001T000709Z/` inside `rust-throwing-default-ops.rs` / `swift-ThrowingDefaultOps.swift` (byte-for-byte identical to the `rust/gen/throwdef/`, `swift/gen/throwdef/` generated trees, with tree hashes in `rust-tree.sha256` / `swift-tree.sha256`).

| Dimension | Rust | Swift |
|---|---|---|
| Generation rc | 0 | 0 |
| `throwingFallback` failure domain | `Result<u32, ThrowingDefaultFault>` (L25) | `throws` (L25) |
| `resolve` failure domain | `Result<u32, ThrowingDefaultFault>` (L32); **but the failure on the default path is a panic**: L33 `value.unwrap_or_else(\|\| …throwing_fallback(seed).unwrap())`, the `.unwrap()` inside the closure | `throws` (L32); the failure on the default path is a **normal error**: L33 `(value == nil ? try throwingFallback(seed) : value!)`, `try` inside the ternary |
| Omitted shape (not throwing) | `resolve(5, None)?` (L39), default evaluated → 10 | `try resolve(5)` (L39), default evaluated → 10 |
| Omitted shape (throwing) | **panic**: the `.unwrap()` at `throwing_default_ops.rs:33:110`, process rc=101, stdout truncated to 1/3 line | thrown → absorbed by the probe's `do/catch` → `caught:OverThreshold:20` |
| Explicit shape | `resolve(5, Some(9))?` (L47), default not evaluated → 9 | `try resolve(5, 9)` (L47), default not evaluated → 9 |
| Call markers | call-site `?` (L39/43/47): **ineffective** on the default path (panic does not go through `?`) | call-site `try` + `try` inside the default expression (L33): both levels present |
| region absorption | region lowered to `match (\|\| -> Result<…>)()` (L59-64): **Result matching cannot absorb a panic**, probe_omitted_throwing crashes | region lowered to `do/catch let error as ThrowingDefaultException` + bare catch rethrow (L74-84): **absorption succeeds**, all three lines hit the oracle |
| Native compile rc | 0 (all 4 warnings come from pre-existing runtime/u_string.rs code, 0 in the fixture file) | 0 (1 generated-artifact warning, see §5) |
| Native run rc | **101** (panic) | **0** |
| Comparison with oracle | **divergent** (diff non-empty: lines 2/3 missing) | **matches** (3/3 lines) |

## 4. Failure-domain conclusion and mechanism

**Rust expels the failure of a throwable call inside a coalescing default from the function's declared failure domain.**
`resolve`'s `Result` signature comes from the fallibility scan (TCall infection at the coalescing site in the typed body, `packages/compiler/reflaxe/rust/rustcompiler/Compiler.hx` L1244-1340; when the call site omits the argument, the call inside the default is additionally recorded as a propagation edge, L1279-1340), but the rendering-side `RustExpr.defaultErrorSuffix` (`packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx` L2675-2689) returns `".unwrap()"` for the `inClosure` case: the closure must return a concrete value, `?` cannot propagate, so the implementation chose unwrap (panic). Result: the declared Err path is unreachable for the default failure, the `?` marker is ineffective, and the try region (Result matching) cannot absorb the panic. On the throwing omitted shape this **diverges across targets** from Haxe stage-1 semantics (exception propagation, region catching).

**Swift leaves it inside the function's throws domain.** `SwiftParameterPlan.coalescingDefaultThrows` (`packages/compiler/reflaxe/swift/swiftcompiler/SwiftParameterPlan.hx` L98-109) recognizes the throwable default, the parameter is lowered to `T? = nil` + entry body normalization; `SwiftDecl` L986-989 / `SwiftExpr.throwingCoalescingText` (L356-358) place `try` on the true arm of the ternary (the `??` right operand is a non-throwing autoclosure, so an explicit conditional is used). The fallibility scan (`SwiftFallibility.scanExpr`, L153-172) makes the region absorb exactly the class its catch names. The "Swift misses `try`" worry from B/D is **measured to not hold**: both the `try` inside the default expression and the call-site `try` are present.

Effect of try region absorption on the failure domain (measured + mechanism citation): Swift's region absorption makes the probe-layer function not throw for the caught domain (only the bare catch rethrows the unknown domain, so the signature is still `throws`); Rust's region is Result matching, which absorbs only Err, while the default failure travels the panic channel, outside that mechanism, and a failed absorption crashes the process. The two targets' region-absorption semantics are not equivalent on the "throwable default" source shape.

## 5. Diagnostics (recorded separately from the failure domain)

Swift native compilation has 1 **generated-artifact** warning (att directory `swift-redundant-try-warning-count.txt`):

```
throwdef/ThrowingDefaultOps.swift:34:33: warning: no calls to throwing functions occur within 'try' expression
```

That is, the redundant `try` on `let normalized: Int32 = try value` (`SwiftExpr` L352-354 self-described comment: "a `try` marker the statement pipeline adds over the same call is legal and stays"). Per the ruling criteria in `docs/architecture/rulings/BUILD-PHASE-DIAGNOSTIC-RULING.md`, this is a build-phase diagnostic, **a separate matter**, not counted in the failure-domain conclusion; it is recorded here only as a reading. On the Rust side all 4 warnings come from pre-existing `runtime/u_string.rs` code, unrelated to this fixture.

## 6. Reproduction

```
nix develop -c bash tests/haxe/throwing-default/run.sh
```

One invocation allocates `out/throwing-default/att-<utc>/` (append-only, never overwrites), 15 stages (admission×2, oracle×3, rust×5, swift×5) each recording argv/cwd/split stdout+stderr/status; `identity/` records tool versions and the sha256 of all fixture inputs; the generated trees have a per-file hash manifest. The authored expectation is pinned to base `e8648488`: Swift reproduces the oracle's three lines; Rust panics on the throwing omitted shape (rc=101) and truncates output. Any deviation (e.g. Rust no longer panics, or Swift no longer matches) is recorded as observed-differences to preserve evidence; only an admission flip or an oracle-anchor break causes a non-zero exit.

## 7. Measured vs document citations

- Measured: §1's two probes' rc and output; all cells of §3 (generation, compile, run, comparison, diagnostics); §5's warning text.
- Document/code citations (the code itself was not run, only the text was read): §1's clause line numbers, §4's emitter mechanism line numbers, §5's ruling file.
- Untested: the explicit null materialization path (feature 51); the null-provided branch of `recordDefaultCallEdges` (Compiler.hx L1326-1339): this fixture has no explicit null call site.
