# Feature spec 23: Float precision switch

## Scope

This specification rules a module-level precision switch for the target
representation of the Haxe `Float` type. One compile-time define,
`-D float-precision=f32`, moves the generated representation of every
`Float` in the compilation from the binary64 family (`f64`, `Double`,
`number`) to the binary32 family (`f32`, `Float`); the absent define (or
`-D float-precision=f64`) keeps the current mapping. The switch is whole-
compilation: no module, field, or expression keeps a different precision,
and the Haxe source declares nothing about it. The downstream motivation
is the engine port: the reference implementation of the consumer carries
its real-number fields as single-precision floats, and the generated
targets must round exactly like that reference to stay byte-comparable
with its recorded expectations.

The mechanism is the transpiler-side equivalent of the Rust
`#[cfg(feature)]`-gated `type Real = f32` alias: the algorithm source
stays written against one abstract real type, and the build selects the
concrete width. boring always translates from source at the consumer's
compilation, so the consumer's `-D` flag reaches the translation the same
way a Gradle source-dependency build reads the consumer's project
properties; no published-coordinate split (the `rapier2d` /
`rapier2d-f64` pattern) exists here because boring publishes no binary
coordinates at all.

The wire format is out of scope and unaffected: `WireF64Be` stays f64 on
every lane (binary spec 01). The precision switch changes the language-
level `Float` representation and the module-boundary rounding of wire
values, nothing else.

## Haxe construct

```haxe
final advanceEm:Float = reader.readF64();
writer.writeF64(advanceEm);
final limit:Float = 2.5;
final broken:Float = Math.NaN;
```

The source names `Float`, float literals, `Math` statics, and the wire
read/write edges. Under `-D float-precision=f32` the same source
generates `f32` fields, `2.5f32` literals, `f32::NAN`, and wire methods
that round the decoded f64 to the module real at the decode point.

## Current translations

| Construct | Rust | TypeScript | Kotlin |
| --- | --- | --- | --- |
| `Float` type | `f64` | `number` | `Double` |
| float literal | `2.5` (`.0` padded) | `2.5` | `2.5` |
| `Math.NaN` | `f64::NAN` | `Number.NaN` | `Double.NaN` |
| `Math.floor(x)` | `f64::floor(x)` | `Math.floor(x)` | `Math.floor(x)` (`java.lang.Math`) |
| `FPHelper.i64ToDouble` | runtime `i64_to_double` (`f64::from_bits`) | runtime `i64ToDouble` | runtime `i64ToDouble` (`Double.fromBits`) |
| `readF64():Float` | hardcoded `-> f64` return | `number` | `Double` |
| test assertion | `equals_f64` / `format_f64` | `formatValue(number)` | `Double` overloads |

## Candidate translations

### Rust Candidate 1: Define-gated type table

The type table, literal suffix, `Math` prefix, constant paths, and the
FPHelper dispatch read one define and emit the f32 spelling (`f32`,
`2.5f32`, `f32::floor`, `f32::NAN`, `i64_to_f32`). Source stays
type-agnostic; each compilation is one width.

- performance: f32 arithmetic uses the hardware single-precision paths
  and stores each field in 32 bits; the generated code is the native
  f32 the consumer asked for, and no emulation layer runs.
- ambiguity: the width is declared once per build, in the same place for
  every field; signatures state `f32` after generation.
- redundancy: one dispatch point per construct family; no per-callsite
  conversion code in the source.
- readability: generated Rust reads as ordinary f32 code.

### Rust Candidate 2: A generic real trait (num-traits `Real` pattern)

The source programs against a trait bound; monomorphization selects the
width.

- performance: monomorphized native code, but the Haxe-side generics
  route every operator through the trait's translation, and JVM targets
  box (see the Kotlin rows).
- ambiguity: the width becomes a type parameter erased from signatures
  in the Haxe layer.
- redundancy: every numeric site carries the bound.
- readability: the algorithm source stops stating `Float` and starts
  stating `Real<T>`; the codec's field types no longer match the wire
  table's fixed spellings.

### Kotlin Candidate 1: Define-gated type table

Same shape as Rust Candidate 1: `Float`, `2.5f` literals, `Float.NaN`,
`kotlin.math` free functions (which carry `Float` overloads), runtime
`i64ToF32`. This is the transpiler-side equivalent of generating a
one-line `typealias Real` source file from a Gradle property: the
algorithm source keeps concrete-type syntax, and operators plus
`kotlin.math` resolve at compile time without generics.

- performance: `Float` is a JVM primitive; no boxing outside nullable
  and generic positions, exactly as `Double` is today.
- ambiguity: same as Rust Candidate 1.
- redundancy: same as Rust Candidate 1.
- readability: generated Kotlin reads as ordinary `Float` code.

### Kotlin Candidate 2: expect/actual typealias

A KMP build could declare `expect typealias Real` and provide `actual`
per target source set. boring performs a single translation, and a
multiplatform build never occurs, so there is no target-source-set
boundary for the actual to live on. The mechanism has no counterpart
here.

### Kotlin Candidate 3: Generic real interface

Serves the scenario where both widths coexist in one artifact. The JVM
erases type parameters, so `Float` and `Double` arguments box at every
generic call, a standing cost the define-gated table avoids because it
uses primitives directly. The both-widths scenario has no consumer; the
port needs one width per compilation.

### TypeScript Candidate 1: Reject the define

`number` is binary64; the language has no f32 value type. A compilation
that sets `float-precision=f32` and activates the TypeScript compiler
stops with an error at compiler startup, before any type is rendered.

- performance: no emulation layer runs at all.
- ambiguity: the error states the incompatibility; no f64-semantics
  code is silently produced under an f32 flag.
- redundancy: none.
- readability: the consumer learns the constraint at build time.

### TypeScript Candidate 2: `Math.fround`-wrapped operations

Every arithmetic operation could be wrapped to round to binary32,
emulating f32 on binary64 storage.

- performance: one extra runtime call per operation on the hot path;
  this is exactly the cross-storage emulation design principle 3 bans.
- ambiguity: values are binary64 between operations; intermediate
  results keep more precision than the declared width, so the emulation
  does not even reproduce f32 semantics exactly.
- redundancy: every operation site is rewritten.
- readability: the generated code no longer reads as plain arithmetic.

### TypeScript Candidate 3: `Float32Array` storage

Fields could live in `Float32Array` so storage rounds to binary32.

- performance: storage rounds, but every arithmetic operation still
  loads to `number` (binary64) and rounds on store; the cost of the
  emulation moves, it does not leave.
- ambiguity: aliasing and equality semantics of array-backed fields
  differ from value fields.
- redundancy: every field access becomes an indexed access.
- readability: field syntax is gone.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust C1 define table | native f32, no layer | width stated once per build | one dispatch per family | plain f32 code |
| Rust C2 real trait | native after monomorphization; boxed on JVM lanes | width becomes a parameter | bound at every site | algorithm stops stating Float |
| Kotlin C1 define table | JVM primitive, no boxing | as Rust C1 | as Rust C1 | plain Float code |
| Kotlin C2 expect/actual | not applicable: no multiplatform build boundary exists | n/a | n/a | n/a |
| Kotlin C3 generic interface | boxes at every call | as Rust C2 | as Rust C2 | as Rust C2 |
| TS C1 reject define | no emulation | failure is explicit | none | constraint stated at build |
| TS C2 fround wrap | emulation on the hot path (principle 3) | binary64 intermediates | every site rewritten | not plain arithmetic |
| TS C3 Float32Array | emulation moved to stores | aliasing semantics change | every field indexed | field syntax gone |

## Ruling

1. **The define.** `float-precision` takes `f64` (the default when the
   define is absent) or `f32`. Any other value stops the compilation
   with `float-precision accepts f64 or f32`. The define is read through
   `Context.definedValue` in a shared config module beside
   `RuntimeConfig`, because every target compiler consumes it.
2. **Type table.** With `f32`, the language-level `Float` maps to `f32`
   on Rust and `Float` on Kotlin. `Int` mappings, wire types, and every
   non-float construct are untouched. The wire table of feature spec 07
   keeps `WireF64Be` at `f64`: the switch selects the module's real
   number width, never the wire width, so the single-precision ban in
   feature spec 07's wire-path list is unaffected by this
   specification.
3. **TypeScript rejects the switch.** Activating the TypeScript
   compiler under `float-precision=f32` stops the compilation at
   compiler startup with `float-precision=f32 is not available on the
   TypeScript target: number is binary64; compile without the define
   for f64 semantics`. The rejection happens before any type is
   rendered, so no partial f64-semantics output is produced under an
   f32 flag. Principle 3 (no cross-storage emulation) and principle 4
   (the ruling stands even though fround wrapping is implementable)
   select the rejection; the sanctioned path for TypeScript consumers
   is the default f64 lane.
4. **Literals.** With `f32`, a float literal renders with the target's
   f32 marker: `2.5f32` on Rust (the `.0` padding rule applies first:
   `5` becomes `5.0f32`), `2.5f` on Kotlin (`5` becomes `5.0f`). The
   suffix is unconditional, so the literal never relies on inference
   context for its width.
5. **Constants.** `Math.NaN`, `Math.POSITIVE_INFINITY`, and
   `Math.NEGATIVE_INFINITY`, and the remaining `Math` statics, render
   from the f32 family: `f32::NAN` and `f32::INFINITY` on Rust,
   `Float.NaN` and `Float.POSITIVE_INFINITY` on Kotlin.
6. **Math functions.** With `f32`, Rust renders `Math.<name>(x)` as
   `f32::<name>(x)`; the argument is already `f32` under the type
   table. Kotlin renders `kotlin.math.<name>(x)` fully qualified; the
   `kotlin.math` free functions carry `Float` overloads, so no import
   is added and `java.lang.Math` (Double-only) is never referenced
   under `f32`. On the default lane both compilers keep their current
   `f64::` / `java.lang.Math` renderings.
7. **FPHelper and the wire boundary.** The FPHelper runtime keeps its
   64-bit bit-layout contract: `i64_to_double` and `double_to_i64` (and
   their Kotlin and TypeScript forms) stay f64. Under `f32` the call
   dispatch translates `FPHelper.i64ToDouble(low, high)` to the runtime
   variant `i64_to_f32(low, high)`, which decodes the same 8 wire bytes
   and then converts the value to the module real with round-to-
   nearest-even; `FPHelper.doubleToI64(v)` translates to `f32_to_i64`,
   which widens the module real to f64 losslessly before the bit
   conversion. The 8-byte wire layout is identical on both lanes. The
   Haxe source of `BinaryReader.readF64` and `BinaryWriter.writeF64`
   changes nothing: the boundary rounding is the decode's definition
   under the switch, and the source performs no implicit narrowing.
   Principle 1 applies: the meaning of `readF64` is defined over wire
   values and the module's declared real width, with no dependence on
   one platform's storage.
8. **`readF64` return type.** The Rust compiler's hardcoded
   `readF64 -> f64` return joins the type table, so the read and write
   edges follow the switch symmetrically.
9. **Mixed Int/Float arithmetic.** The Int side of a float-typed
   `+ - * /` renders its conversion against the module real (`as f32`
   on Rust under the switch); the Float-to-Int truncation paths
   (`as i32`, `toInt()`) are width-agnostic and change nothing.
10. **Test apparatus.** The generated Rust assertion helpers become
    `equals_f32`, `format_f32`, `assert_equals_f32` (the aggregate
    helpers derive their names through the type table and follow
    automatically); the generated Kotlin helper overloads become
    `Float`. The canonical float text of feature spec 19 is, under
    `f32`, the shortest decimal string that parses back to the same
    binary32 value (`Display for f32`, `Float.toString`); the special
    values keep their words. The committed wire vector
    `roundtrip.bin` and its expected records are shared by both lanes:
    every vector value is an f32-exact dyadic rational, the f32 lane
    widens each losslessly on encode, and both lanes produce identical
    wire bytes.
11. **Test-vector discipline on the f32 lane.** Float test values on
    the f32 lane are f32-exact dyadic rationals (the binary spec 01
    dyadic rule restricted to the binary32 grid), or non-dyadic
    literals used only in comparison position or passed through
    unchanged, where the comparison direction and the round-trip text
    are width-independent. This is the sanctioned path (design
    principle 2) for the restriction the switch introduces: a test
    whose expectation depends on binary64 intermediate precision
    belongs on the default lane.
12. **Module-level only.** The define selects one width for the whole
    compilation. Per-module or per-field mixing has no sanctioned path
    in this specification; a consumer needing both widths in one
    artifact compiles the single-precision part as a separate
    compilation, exactly as a Rust workspace consumes `rapier2d` and
    `rapier2d-f64` as separate coordinates.

## Test hooks

- `examples/rust-f32.hxml`, `examples/kotlin-f32.hxml`: full-library
  generation under `-D float-precision=f32` (verify lanes
  `gen:rust-f32`, `gen:kotlin-f32`, `test:rust-f32`, `test:kotlin-f32`).
- `tests/ts/precision-switch.test.ts`: activates the TypeScript
  compiler under `float-precision=f32` and asserts the startup error
  and its text, proving the rejection fires before output.
- The shared suites (`tests.VectorCodecTests` and neighbors) run
  unmodified on the f32 lanes under ruling 11's vector discipline.
- `docs/specs/features/07-numeric-tower.md` links here from its wire
  ban; `docs/specs/features/19-testing.md` carries the binary32 text
  clause of ruling 10.
