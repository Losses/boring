# float-hash-nullable

Regression contract for the nullable-float hashCode defect (board
`t-mvzn8ckw-vh3s`). Commit `86c33fc3e` added the P-13 float-canonical
hashCode path but did not handle nullable floats: a `@:dataClass` with a
`Null<Float>` field generated `Float?.toBits()` on Kotlin and passed a
`double?` into `haxeFloatHashBits(double)` on Dart, so the generated tree did
not compile.

## What it asserts

The oracle `floathashnullable/FloatHashNullableContract.hx` defines a
`@:dataClass` `NullableFloatRecord` with a `Null<Float>` field and returns the
observations the native harnesses assert:

- **compiles**: the generated Kotlin (f32 and f64) and Dart trees compile
  with `kotlinc` / `dart analyze` + `dart compile` (exit 0);
- **hashCode stable**: `hashCode(null) == hashCode(+0.0) == hashCode(-0.0)`
  (null hashes to 0, matching Haxe `hashCode(null) = 0`, and a signed zero
  hashes to zero bits under P-13 canonical), and `hashCode(NaN)` is stable;
- **equals unchanged**: `null == null`, `null != +0.0`, `+0.0 == -0.0`.

The absolute hashCode value is target-dependent (each target folds the field
terms with its own seed and multiplier), so the contract asserts stability
and equality between observations, never an absolute number.

## Run

From the repository root inside the pinned toolchain:

    nix develop -c bash tests/haxe/float-hash-nullable/run.sh

The runner allocates a fresh run directory under
`out/float-hash-nullable/runs`, generates and compiles each target, runs the
native harness assertions, and exits nonzero on any failure.

## Layout

- `floathashnullable/FloatHashNullableContract.hx` — oracle source
- `hxml/kotlin.hxml`, `hxml/dart.hxml` — focused generation entries
- `native/Main.kt`, `native/main.dart` — assertion harnesses
- `run.sh` — durable runner
