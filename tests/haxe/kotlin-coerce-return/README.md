# Kotlin Return coercion fixture

P2.7. A returned value that must satisfy a non-null return-type contract is
hardened with !!. The destination admitsAbsence follows the current
function/lambda return type — the P1 rebound type — so one source is measured
twice:

* the enclosing non-null String return extracts a nullable call with !!;
* the same nullable source returned from inside a Null<String>-returning
  lambda stays bare, because the lambda's own return type admits absence.

The positive tree emits `return f()!!` at the outer return and a bare
`return _gthis.nullableString()` inside the lambda; kotlinc accepts it.
Without the lambda's own return type being respected the bare body would
harden to `return _gthis.nullableString()!!` (wrong: the lambda is allowed
to return null).

kotlin-coerce-return.test.ts drives both arms (GP-ABLATE): the positive arm
generates and compiles and asserts both emitted forms (bare inside, !! on the
outer return); the ablation arm regenerates with -D kotlin_coerce_ablate=Return,
asserts the outer !! is gone, and requires kotlinc to fail with the
type-mismatch diagnostic. The fixture is collected by bun run test (WBS 0.5).

kotlin.hxml names packages/compiler on the class path directly instead of
depending on -lib boring, so the fixture always measures the tree it lives in
rather than whatever the workspace haxelib projection points at (PIT-376).
