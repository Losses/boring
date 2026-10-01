# Cross-module same-name growth fixture (t-muoqr42y-5bu3)

## What it measures

Two Haxe modules, `cma` and `cmb`, each declare an enum `EFault`, an enum `BFault`,
and a throwing class `B`. Only the Haxe package differs, so the emitted Rust types are
distinct (`crate::cma::cross_a::EFault` versus `crate::cmb::cross_b::EFault`) - but the
growth table is keyed by the BARE enum name, so it cannot tell them apart.

Both `cma.CrossA.run` and `cmb.CrossB.run` rethrow `B` by value from a function whose
Result error enum has settled to the LOCAL `EFault`. Each therefore registers a growth
variant named `BFault` on the growth key `"EFault"`; the two land in the same bucket and
the calleeName dedup drops the second.

## Verdict: reachable defect, not an argument

The adversarial audit recorded this shape as a caveat and explicitly marked it
"Não counterexample could be built, so this is an argument, not a measurement"
(in Chinese: could not construct a compiled counterexample). This fixture turns it into
a measurement.

    haxe tests/haxe/growth-cross/gen/rust.hxml -cp packages/compiler \
        -D rust-output=/tmp/gc-out          # gen rc=0
    cd /tmp/gc-out && cargo check           # rc=101

    error[E0308]: mismatched types
      --> cma/cross_a.rs:63
       | return Err(EFault::BFault(Box::new(B::new(f))));
       |                  -------- ^^^^^^^^^ expected `cross_b::B`, found `cross_a::B`
       | note: `cross_a::B` and `cross_b::B` have similar names, but are actually
       |       distinct types

The mechanism is visible in the emitted code: BOTH modules' `EFault` declare

    BFault(Box<crate::cmb::cross_b::B>)

i.e. `cmb` won the shared bucket, so `cma`'s enum carries the OTHER module's payload type
while `cma`'s own throw site constructs `cma`'s `B`.

## It predates this batch

Feeding the same fixture to `05e375b2` (before PIT-281 / TCN-109) gives gen rc=0 and
cargo rc=101 with 3 errors, so this is a pre-existing defect, not a regression introduced
by this session's work - consistent with the audit's own "predates this batch" note.

## How to reproduce the collision deliberately

Both sides must be compilation ROOTS (the driver lists `cma.CrossA` and `cmb.CrossB`). If
only one module is rooted, the other never enters and the bucket cannot collide.
