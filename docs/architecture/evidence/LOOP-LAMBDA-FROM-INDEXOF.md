# Closures lowered inside loop bodies

**Status: two of three causes FIXED; one is a structural constraint, not a defect.**
Discovered while re-establishing ground truth after a run of unreliable session
reports (see "Provenance" below).

## Outcome

Three distinct lowerings were producing closures inside loop bodies. Two were
stylistic and are now converted; the third is structurally necessary.

| Cause | Emission site | Status |
|---|---|---|
| array `indexOf` → `.iter().position(\|e\| …)` | `RustExpr.hx:11047` | **fixed** — indexed scan |
| nullable `==` comparison → `.as_ref().map_or(false, \|v\| …)` | `RustExpr.hx:7099`, `:7109` | **fixed** — `matches!(…, Some(__v) if …)` |
| try-region → `(\|\| { … })()` | `RustExpr.hx:6139` | **not a defect** — see below |

Effect: loop-structure `loop-lambda` violations went **8 → 1** and the remaining
one is the try-region IIFE.

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
control flow restructured, not reformatted. So it is recorded as a **constraint
the loop-lambda rule does not currently accommodate**, which is a question about
the rule and the construct, not a bug in the lowering.

### Evidence for the two fixes

Read back after the change, not inferred from the command:

| Check | Result |
|---|---|
| `iter().position(` in `config.rs`, `compare_core.rs` | **0, 0** (was 6, 2) |
| `.as_ref().map_or(false, \|v\|` in `RustExpr.hx` | **0** (was 2) |
| `haxe examples/rust.hxml` | rc=0 |
| `cargo check` on the regenerated tree | clean, pre-existing warnings only |
| `cargo test` | **780 passed, 0 failed** |
| loop-structure `loop-lambda` hits | **1** (the IIFE) |

The 780-passing Rust suite is the load-bearing evidence that the two conversions
are semantically equivalent rather than merely compiling.

### Mutation control

The half that makes the fix load-bearing rather than coincidental: reinstating
only the `indexOf` closure form (leaving everything else at the fixed state)
returns **6** `loop-lambda` hits, against **1** on the fixed emitter. So the
conversion is what removes them, not a side effect of the same edit.

Restoring the fix returns the count to 1, and the emitter is byte-identical to
its committed state afterwards.

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
bun test tests/ts/loop-structure.test.ts     # after the fixes: 3 pass, 2 fail
```

The `2 fail` is now the **try-region IIFE** plus the unrelated `for-head` in the
TS tree — not the `indexOf`/`mapOr` causes this document opened with. Before the
fixes the same command reported 8 `loop-lambda` hits.

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
