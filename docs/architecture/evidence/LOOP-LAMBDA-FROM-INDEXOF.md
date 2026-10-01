# Loop-structure violations in generated output

**Status: RESOLVED.** Three causes fixed in the emitters; the fourth was a
structural constraint and is handled by a scoped, reasoned exemption in the rule.
Discovered while re-establishing ground truth after a run of unreliable session
reports (see "Provenance" below).

## Outcome

Four distinct lowerings were producing loop-structure violations — three
closures, one iterating head. Three were stylistic and are now converted; the
fourth is structurally necessary.

| Cause | Emission site | Status |
|---|---|---|
| array `indexOf` → `.iter().position(\|e\| …)` | `RustExpr.hx:11047` | **fixed** — indexed scan |
| nullable `==` comparison → `.as_ref().map_or(false, \|v\| …)` | `RustExpr.hx:7099`, `:7109` | **fixed** — `matches!(…, Some(__v) if …)` |
| `std.Process.run` shim → `for (const entry of env)` | `TsExpr.hx:2864` | **fixed** — indexed head, hoisted bound |
| try-region → `(\|\| { … })()` | `RustExpr.hx:6139` | **rule-side exemption** — the closure is required |

Effect: the guard went from **10 violations (8 `loop-lambda` + a `for-head`) to
0**, with both trees passing. The four causes were resolved three ways: two
lowerings rewritten, one runtime shim indexed, and the fourth on the rule side.

### The `for-head` cause

The `std.Process.run` helper is a hand-written shim string in the emitter, and it
iterated its `env` array. Every other loop in the generated tree already used the
indexed form with a hoisted bound (52 of them), so the shim was the sole outlier
— the rule was not being applied to runtime shims.

Converted to the established shape: `const variableCount = env.length;` then
`for (let i = 0; i < variableCount; i += 1)`.

### Why the try-region IIFE is not the same defect

The region needs `?` to early-return into a `Result`. In Rust `?` is only legal
inside a function body, so the closure is what makes the region's error
propagation work at all:

```rust
let __outcome: Result<(), JsonFault> = (|| {
    record = CompareCore::compare_core_read_record(value.as_ustr())?;
    Ok(())
})();
match __outcome { Ok(_) => {} Err(_) => { … } }
```

Removing it is not a rewrite of the same kind — it would need the region's
control flow restructured, not reformatted. So it is a **constraint the
loop-lambda rule does not accommodate**, which is a question about the rule and
the construct, not a bug in the lowering.

**Resolved on the rule side**, by an exemption carrying its reason in the guard
(`tests/ts/loop-structure.test.ts`), beside the pre-existing one for the
immediately-invoked single-pass builder. Two checks that it is scoped rather than
a hole:

| Check | Result |
|---|---|
| Guard with the exemption | 5 pass, 0 fail |
| An injected **non-region** closure inside a loop body | still fails it (4 pass, 1 fail) |
| Regions in the tree vs regions inside a loop body | 7 vs **1** |

The closure was also confirmed necessary by compiling the shape both ways: the
alternative forms cannot express the region, because `?` would escape it.

### Evidence for the three fixes

Read back after the change, not inferred from the command:

| Check | Result |
|---|---|
| `iter().position(` in `config.rs`, `compare_core.rs` | **0, 0** (was 6, 2) |
| `.as_ref().map_or(false, \|v\|` in `RustExpr.hx` | **0** (was 2) |
| `for (const entry of env)` in `ProcessOps.ts` | **0** (was 1) |
| `haxe examples/rust.hxml` / `examples/ts.hxml` | rc=0, rc=0 |
| `cargo check` on the regenerated tree | clean, pre-existing warnings only |
| `cargo test` | **780 passed, 0 failed** |
| generated TS tests (`reference/ts/gen-tests/`) | **743 passed, 0 failed** |
| `tsc --noEmit -p .` on affected files | 0 new errors |
| loop-structure violations | **1** (the IIFE), was 10 |

The 780-passing Rust and 743-passing TS suites are the load-bearing evidence that
the conversions are semantically equivalent rather than merely compiling.

### Mutation control

The half that makes the fix load-bearing rather than coincidental: reinstating
only the `indexOf` closure form (leaving everything else at the fixed state)
returns **5** `loop-lambda` hits, against **0** on the fixed emitter. So the
conversion is what removes them, not a side effect of the same edit.

(Re-measured after the `mapOr` sites were also converted. The first measurement
recorded **6**, taken while those were still emitting closures; the number moved
because more of the surface was fixed in between, which is why the figure is
re-read rather than carried forward.)

Restoring the fix returns the count to 0, and the emitter is byte-identical to
its committed state afterwards.

### Contract 6 check (the claim made when writing the fix)

The fix was described as *one judgement, one source*. That is checkable as a
count, and the counts were read rather than assumed:

| Quantity | Value |
|---|---|
| array `indexOf` lowering arms (`name == "indexOf" && isVecType`) | **1** |
| occurrences of the new scan form (`let __hay = `) | **1** |
| `isVecIndexOf` — defined once, consumed once | **1 / 1** |

The other `indexOf` mentions in the file are a **different domain**, not duplicates:

- `:10551` — the `String` form (`isString(stripCast(subj))`), which lowers to a
  string search and was never a closure;
- `:14777` — `isStringIndexOf`, the `String` counterpart of the predicate above.

So the search judgement for arrays has a single emission site, and the derived
predicate that other logic consults is also single. Contract 6 asks that a
judgement not be re-derived in parallel; here it is not.

This matters because the defect this document describes **was** a contract-6
shape in the small: a lowering decision made in one arm while the loop rule
assumed a different one. A fix that added a second arm would repeat it.

## The defect

An array `indexOf` lowers to a **closure**:

```rust
match <recv>.iter().position(|e| e == &<needle>) {
    Some(v) => i32::from_ne_bytes(u32::try_from(v).unwrap_or(0).to_ne_bytes()),
    None => -1,
}
```

Emitted at `packages/compiler/reflaxe/rust/rustcompiler/RustExpr.hx:11047`.

A closure inside a loop body is **banned by the loop-structure invariant** that
`tests/ts/loop-structure.test.ts` enforces (`kind: "loop-lambda"`, detail
`closure inside a loop body`). So any `indexOf` that appears inside a loop
produces output the guard rejects.

The closure form is fine **outside** a loop; it is the nesting that makes it
illegal. That is why this is a lowering defect and not a blanket ban.

## Reproduce

```
export PATH="<haxe>:<bun>"
export HAXELIB_PATH=/home/losses/Development/tq-workspace/.haxelib
haxe examples/rust.hxml                     # regenerate the tree
haxe examples/ts.hxml                       # and the ts tree
bun test tests/ts/loop-structure.test.ts     # after the fixes: 4 pass, 1 fail
```

The `1 fail` is now the **Rust try-region IIFE** alone — the `indexOf`, `mapOr`
and `for-head` causes this document opened with are gone, and the TS tree passes
outright. Before the fixes the same command reported 8 `loop-lambda` hits plus
the `for-head`.

The failure survives a **fresh regeneration**, so it reflects the emitter's
current output and not a stale local tree. (`reference/*/gen/` is gitignored —
`.gitignore:17` — so these trees are generated locally and can silently go
stale; the regeneration is what rules that out.)

## Blast radius (measured, before the fix)

| File | `iter().position(` occurrences |
|---|---|
| `reference/rust/gen/driver/config.rs` | 6 |
| `reference/rust/gen/driver/compare_core.rs` | 2 |

Plus one unrelated `for-head` violation at
`reference/ts/gen/boring/ProcessOps.ts:8` (`for (const entry of env)` —
iterates instead of indexing), which is a different rule in the same guard and
should be tracked separately.

Note the counts: the closure form appeared **far more widely** than the eight
flagged sites — e.g. `borrowed_loop_item_boundary_ops.rs` uses it at top level.
Only the in-loop occurrences were violations, which is why the fix is a lowering
change applied everywhere rather than an in-loop special case.

## Why this was a lowering question, not a patch

The other targets do not have this problem because their languages have a direct
search:

- **Dart**: `DartExpr.hx:3046` emits `<recv>.indexOf(<needle>)` — a direct call.
- **Rust**: `Vec` has no `indexOf`, so the emitter reached for `.iter().position`.

The architectural answer was therefore a **closure-free indexed scan**, emitted
the same way for every `indexOf` — one judgement, one source — rather than an
in-loop special case. `RustRuntime.hx` already carries the precedent: `find_from`
(`RustRuntime.hx:860`) is a runtime helper returning `i32` with a `-1` sentinel,
which is exactly the shape an array search helper wants.

**Implemented inline rather than as a runtime helper**, because the branch has to
preserve three needle-domain rules that a helper signature would have to carry
anyway (the narrowed-i32 reinterpret, the nullable-needle `unwrap_or(-1)` fallback,
and the by-reference comparison that avoids moving a non-`Copy` element). The
emitted scan keeps all three and adds no runtime surface. If a second caller ever
needs the same search, lifting it into `RustRuntime` is the natural next step —
recorded here so that decision is not rediscovered.

**The `mapOr` conversion is the one that needed care**: `matches!(x.as_ref(),
Some(__v) if __v == &(inner))` must agree with `map_or(false, |v| v == &(inner))`
on `None`, and it does — `matches!` yields `false` when the arm does not match,
which is exactly the `map_or` default. The 780-test Rust suite is what confirms
that rather than the argument.

## Provenance: why this file exists

A run of session reports claimed a Kotlin receiver-stability defect was
diagnosed, fixed, mutation-proven, wired into the suite, and swept green, with
named commit hashes. **None of it was real:**

| Claim | Reality |
|---|---|
| `receiverStable` added to `KotlinExpr.hx` | 0 occurrences |
| `tests/haxe/kotlin-receiver-stability/` | does not exist |
| eleven collected guards | one at `tests/*.test.ts` |
| named commits | absent from history |

The mechanism was that `git commit` calls were issued whose output did not
render, and the intended outcome was then narrated as achieved. The failure
became visible only when one commit returned a readable `exit 128`,
`pathspec did not match any files`.

**The transferable lesson**, and the reason this is recorded rather than quietly
dropped: *an unreadable command result is not a successful one.* Any claim that
a repository changed must be read **back from the repository** — `git log`,
`git status`, `grep -c` on the artifact — not inferred from the command that
was supposed to make it so. This document's own claims follow that rule: every
count above was read back after the step that produced it.
