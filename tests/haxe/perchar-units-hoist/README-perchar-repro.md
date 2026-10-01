# Per-character `units` quadratic defect: reproducible probe

This probe takes the **generated code verbatim** (Tiqian `org/tiqian/test/trace/test_trace_render.rs`'s
`test_trace_render_expand_scientific` + `test_trace_render_scientific_match`,
extracted byte-for-byte from the two generated trees before and after `fix/rust-perchar-units-for-loop`) and packages it into a self-contained
crate, replacing only `crate::runtime::*` with a minimal implementation of the same names and semantics, to measure this path's timing and
`units()` call count. It depends on no downstream checkout, so it can be run directly here.

## Three variants (same body, differing only in hoist placement)

| File | Meaning |
|---|---|
| `perchar-cost-repro.rs` | **Post-fix shape**: `units`/`unit_count` hoisted to the function entry once; the inner function reuses the `&[u16]` passed by the caller |
| `perchar-cost-control.rs` | **Pre-fix shape**: the inner function re-runs `u_string::units(&s)` to make its own copy on every entry (the dead hoist the fix removed) |
| `perchar-cost-unitsfree.rs` | **Attribution control**: loop body and call count unchanged, only `units()` swapped for an O(1) stand-in |

## How to run

```sh
RUSTC=$(command -v rustc)          # 1.98.0
for v in repro control unitsfree; do
  $RUSTC -O --edition 2021 --crate-type bin -o /tmp/perchar-$v perchar-cost-$v.rs
  for n in 100000 200000 400000; do /tmp/perchar-$v $n; done
done
```

## Measurements (release, -O)

```
repro     bytes=100002 walk_units_calls=33335  walk_ms=4934
repro     bytes=200001 walk_units_calls=66668  walk_ms=19165
repro     bytes=400002 walk_units_calls=133335 walk_ms=88794
control   bytes=100002 walk_units_calls=66669  walk_ms=17422
control   bytes=200001 walk_units_calls=133335 walk_ms=53648
control   bytes=400002 walk_units_calls=266669 walk_ms=232117
unitsfree bytes=100002 walk_units_calls=0      walk_ms=0
unitsfree bytes=200001 walk_units_calls=0      walk_ms=2
unitsfree bytes=400002 walk_units_calls=0      walk_ms=3
```

How to read: `walk_units_calls` is proportional to the input (≈ n/3, once per character), and the time ×4s with each doubling of the input
(4.9→19.2→88.8 s), i.e. **O(n²) `units()` allocation/copy**; swapping `units()` for O(1)
drops the same loop to 0/2/3 milliseconds (linear), showing the cost is **entirely** from this hoist, not the loop itself.
`control`'s call count is exactly double `repro`'s: before the fix, the inner function hoisted one extra copy on every entry.

A same-direction reading at the generated-tree level: in `org/tiqian/test/trace/test_trace_render.rs`
`u_string::units(` occurrences go **13 → 7**, and the whole-tree `diff -rq` shows **22 files differ**.
