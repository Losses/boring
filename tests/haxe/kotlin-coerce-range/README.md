# Kotlin RangeBound coercion fixture

P2.2. loopBound extracts the upper bound of a `for (i in 0 ... bound)` loop.
Two bound shapes render nullable, so the endpoint must be hardened to Int:

* for (i in 0...items.length) where items is a nullable array field --
  the safe-call form items?.size has Kotlin type Int?, so the emitter
  appends !! (items?.size!!).
* for (i in 0...limit()) where limit() returns Null<Int> -- the call
  limit() has Kotlin type Int?, so the emitter appends !! (limit()!!).

Without the coercion, kotlinc rejects both endpoints:

    type mismatch: inferred type is Int? but Int was expected

## Check

tests/haxe/kotlin-coerce-range/run.sh drives both arms. The positive arm
generates and compiles the normal tree (kotlinc must exit zero). The
ablation arm regenerates with -D kotlin_coerce_ablate=RangeBound, which
skips the RangeBound coercion and leaves the nullable endpoint bare; kotlinc
must then exit nonzero with the type mismatch diagnostic. The two arms must
differ (GP-ABLATE).

kotlin.hxml names packages/compiler on the class path directly instead of
depending on -lib boring, so the fixture always measures the tree it lives
in rather than whatever the workspace haxelib projection points at
(PIT-376).
