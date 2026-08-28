# Language design audit (2026-08-28)

## Scope and method

This audit runs the four tests of `docs/specs/design-principles.md` over the
specification set and the generators that implement it. The tests are:

- **T1 provision**: each banned or restricted construct has a sanctioned path
  for the legitimate need it blocks.
- **T2 content**: no operation's meaning is defined by a platform's storage
  or by the oracle's incidental behavior.
- **T3 cost symmetry**: no ruling imposes emulation, transcoding, or a higher
  complexity class on one target without a reason naming a principle.
- **T4 motive**: with implementation cost zeroed, every ruling still stands.

The audit looks for one failure shape above all: a rule whose truth depends
on a global property of the current program set (all std symbols are
runtime-backed, all fallible functions share one name list, every function
throws one error enum), which reads as cheap on the current samples and
breaks when the program shape grows. Two such rules were already fixed in
the changes this audit accompanies (`aed22ca`, `ae08f65`); the findings
below are what remains.

## Verdict table

| item | state | test failed | disposition |
| --- | --- | --- | --- |
| Rust lane maps every `Int` to `u32` (`RustType.hx`) | defect | T1, T2 vs `features/07`, `features/14` | redesign: signed `i32` outside wire positions, guarded named conversions at wire boundaries |
| Typed `try`/`catch` has no lowering in any generator | defect | T1 vs `style/01` rule 4, `features/06` | ruling added to `features/06` (catch-site lowering, 2026-08-28); implementation queued |
| `stdlib/06` says no std module reaches target output; `std.UStringException` and `std.UStringFault` now emit as compiled files | stale ruling | none yet; latent contradiction | amended: `stdlib/06` names both std classes (2026-08-28) |
| `StringBuf.addChar` replaces an unpaired surrogate with U+FFFD on Rust and keeps the unit on TypeScript and Kotlin | divergence written into the contract | T2 | ruling added to `stdlib/08` (`UnpairedSurrogate` fault on every target, Rust buffer becomes `Vec<u16>`, 2026-08-28); implementation queued |
| Kotlin `Long` promotion for declared ranges above `0x7FFFFFFF` (`features/14`) has no implementation mechanism | gap | none today (no declared field exceeds the range) | recorded in `features/14` (2026-08-28); implement when such a field is declared |
| Three rustc warnings in generated code (`in_range` needless `mut`, `copy_multiple` unused parameter) | cosmetic | none | fix in the generator |
| String key order is UTF-16 code-unit order (`stdlib/07`, ruled 2026-08-27) | upheld | recorded T3 trade | keep; reason already cited (three targets compare natively, Rust adds one branch) |
| `StringBuf.length` counts UTF-16 code units (`stdlib/08`) | upheld | none | keep; meaning is uniform across targets, and Principle 1 lets storage set only the cost tier while the meaning stays fixed |
| Rust global single-error-enum resolution and fallibility by name list | fixed in `aed22ca` | was T1/T4 | per-function resolution plus a preScan call-edge fixpoint |
| ASCII-bounded string indexing with no replacement API | fixed in `ae08f65` | was T1 | `std.UString` provides code-point semantics on four targets |
| Blanket `usize` for enum payload `Int`s; unconditional `x < 0` rewrite on unsigned operands | fixed in `aed22ca` | was T2 | payload fields are name-typed; the rewrite fires only on unsigned operands |
| TypeScript `std.*` blanket import skip | fixed in `aed22ca` | was T1 | named runtime-provided module list; compiled std modules import as files |

## Findings

### F1: the Rust lane redefines `Int` as a non-negative domain

`docs/specs/features/14-type-system-mapping.md` maps `Int` to "`i32` or
`u32` selected by wire width", and `docs/specs/features/07-numeric-tower.md`
states "Haxe `Int` is 32-bit signed on every supported target". The
implementation (`RustType.of`) maps every `Int` to `u32`, tree-wide. The
consequences:

- A negative literal fails to compile on the Rust lane (`-1` rendered into a
  `u32` position is a rustc error), so subtraction underflow, negative
  sentinels, and `indexOf`-style not-found results have no sanctioned path.
  T1 fails: the restriction is not recorded in any specification and no
  replacement API exists.
- The domain-check rewrite (`x < 0` lowered to `x > 2147483647`) exists only
  to recover sign checks over values that arrive as wrapped `u32`; with
  signed locals it would be unnecessary.
- Arithmetic helpers (`coerceAtLeast` and friends) cannot express a negative
  bound on the Rust lane even though the same source compiles on TypeScript,
  Kotlin, and the stage-one oracle.

Redesign: `Int` outside wire-typed positions lowers to `i32`; wire reads and
writes keep their width-fixed types; conversions at those boundaries go
through named functions guarded by the existing `CountOverflow` domain
(`u32::try_from` paths already exist for length conversions). The
`x < 0` rewrite and the unsigned-operand predicate are then removed.

### F2: typed `try`/`catch` is sanctioned but not translated

`docs/specs/style/01-haxe-style-standard.md` rule 4 permits catch clauses
that name the exception type (V14 rejects only `Dynamic` catches), and
`docs/specs/features/06-errors-and-results.md` rules the TypeScript catch
shape (`instanceof` narrowing followed by discriminant branching). No
generator implements `TTry`: all three lanes fall into their catch-all
compile error. A construct the front half of the pipeline accepts cannot
be untranslatable at the back half. TypeScript and Kotlin lower to native
`try`/`catch`; Rust lowers the try body into a closure returning
`Result` and matches the outcome, mirroring the statement-level
restructuring already ruled in `features/15`.

### F3: two classes of std modules, one ruling

`docs/specs/stdlib/06-std-modules.md` states that neither reserved
namespace reaches any target's output. `std.UStringException` and
`std.UStringFault` are compiled std modules and emit as files under the
target's `std` directory (for example
`reference/ts/gen/std/UStringException.ts`). The ruling predates the
second class. Amend `stdlib/06` to name both classes: runtime-backed std
modules (the list now encoded in `TsImports.runtimeProvidedModules` and
its Kotlin counterpart) never emit and resolve through the runtime
package; compiled std modules emit like any other module. The class list
is the import table, so the spec and the tables cannot drift apart again.

### F4: `StringBuf.addChar` diverges on unpaired surrogates

`docs/specs/stdlib/08-string-buffer.md` rules that `addChar` maps an
unpaired surrogate to `char::REPLACEMENT_CHARACTER` on Rust, while
TypeScript and Kotlin append the unit verbatim. The same input sequence
produces different string content on different targets; a cross-target
assertion on the buffer's `toString` would fail. `std.UString` already
defines the domain answer (`UStringFault.InvalidCodePoint` for unpaired
units); the buffer should share it: `addChar` accepts a unit that is not a
surrogate, or a lead unit completed by the immediately following `addChar`,
and throws the domain fault otherwise, on every target.

### F5: Kotlin `Long` promotion is ruled but unimplemented

`features/14` and `features/07` state that a field whose declared range
exceeds `0x7FFFFFFF` carries `Long` on Kotlin. No schema range mechanism
exists in the generator, so the rule has no implementation path. No current
field exceeds the range (the wire counts are bounded by `CountOverflow` at
`2^31`, and code points by `0x10FFFF`), so no divergence is reachable
today. Record the gap in `features/14` and implement the promotion when a
field with such a range is declared.

### F6: generated-code warnings

Three rustc warnings exist on committed `main` output: `let mut` emitted
for parameters never reassigned (`in_range`), and an unused parameter in
the record-copy lowering (`copy_multiple`). Both are generator output
quality; neither affects behavior.

## Disposition record

Amendments recorded with this audit (2026-08-28):

- F3: `docs/specs/stdlib/06-std-modules.md` names the two std classes
  and the named-list rule.
- F5: `docs/specs/features/14-type-system-mapping.md` records the
  Kotlin `Long` promotion gap and the condition for implementing it.
- F2: `docs/specs/features/06-errors-and-results.md` rules the
  catch-site lowering per target, the two named rejections, and the
  fallibility absorption rule.
- F4: `docs/specs/stdlib/08-string-buffer.md` rules the uniform
  `UnpairedSurrogate` fault, the `Vec<u16>` Rust buffer with
  constant-time `length`, and the stage-1 wrapper checks.

Implementation work queued after this audit: F2 (TTry lowering on three
targets plus the fixpoint absorption), F4 (fault variant plus four
buffer lanes plus fault-exercising samples), F1 (signed `i32` outside
wire positions with named boundary conversions), F6 (mutability
diagnosis for typer-created inline temporaries).
