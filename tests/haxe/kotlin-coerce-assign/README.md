# Kotlin Assignment coercion fixture

P2.3. A Null<Int> value assigned to a non-null Int target must be hardened
with !!. Three targets are measured, all through the Assignment coercion role:

* a non-null local declaration, the extractAtDecl path (role "local");
* a non-null array element write (assignValueText, role "array");
* a non-null field write (assignValueText, role "field").

The positive tree emits (this.nullableInt())!! on every target and kotlinc
accepts it. Without the coercion the bare nullable value survives and kotlinc
rejects it with a type mismatch.

kotlin-coerce-assign.test.ts drives both arms (GP-ABLATE): the positive arm
generates and compiles; the ablation arm regenerates with
-D kotlin_coerce_ablate=Assignment, asserts the !! is gone, and requires
kotlinc to fail with the type-mismatch diagnostic. The fixture is collected by
bun run test (WBS 0.5).

kotlin.hxml names packages/compiler on the class path directly instead of
depending on -lib boring, so the fixture always measures the tree it lives in
rather than whatever the workspace haxelib projection points at (PIT-376).
