# `indexOf` lowers to a closure, which is illegal inside a loop body

**Status: reproduced, NOT fixed.** Discovered while re-establishing ground truth
after a run of unreliable session reports (see "Provenance" below).

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
bun test tests/ts/loop-structure.test.ts     # 3 pass, 2 fail
```

The failure survives a **fresh regeneration**, so it is the emitter's current
output and not a stale local tree. (`reference/*/gen/` is gitignored —
`.gitignore:17` — so these trees are generated locally and can silently go
stale; the regeneration is what rules that out.)

## Current blast radius

| File | `iter().position(` occurrences |
|---|---|
| `reference/rust/gen/driver/config.rs` | 6 |
| `reference/rust/gen/driver/compare_core.rs` | 2 |

Plus one unrelated `for-head` violation at
`reference/ts/gen/boring/ProcessOps.ts:8` (`for (const entry of env)` —
iterates instead of indexing), which is a different rule in the same guard and
should be tracked separately.

Note the counts: the closure form appears **far more widely** than the eight
flagged sites — e.g. `borrowed_loop_item_boundary_ops.rs` uses it at top level.
Only the in-loop occurrences are violations.

## Why this is a lowering question, not a patch

The other targets do not have this problem because their languages have a direct
search:

- **Dart**: `DartExpr.hx:3046` emits `<recv>.indexOf(<needle>)` — a direct call.
- **Rust**: `Vec` has no `indexOf`, so the emitter reached for `.iter().position`.

The architectural answer is therefore a **closure-free indexed scan**, emitted
the same way for every `indexOf` — one judgement, one source — rather than an
in-loop special case. `RustRuntime.hx` already carries the precedent: `find_from`
(`RustRuntime.hx:860`) is a runtime helper returning `i32` with a `-1` sentinel,
which is exactly the shape an array search helper wants.

**Not done in this pass**, deliberately: it changes how every Rust `indexOf`
lowers, so it needs the same four-axis evidence the receiver-stability work
would have needed — fixes the case, is load-bearing under mutation, does not
disturb the corpus, does not disturb the suite. Writing it on one reading is the
mistake this document's provenance section exists to warn about.

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
