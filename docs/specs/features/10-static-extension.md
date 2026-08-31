# Feature spec 10: Top-level and extension functions

## Scope

This specification rules how a static function marked as a top-level
function or an extension function translates to the five targets. The
engine port is the consumer that fixes the required shape: the
handwritten Kotlin engine declares top-level functions and top-level extension functions
in file facades (`engine/src/commonMain/kotlin/org/tiqian/layout/
LayoutQueries.kt` declares `fun LayoutResult.getTextForCopy(...)`,
`SourceInteractionBoundaries.kt` declares `internal fun
String.coerceToInteractionBoundary(...)`), platform consumers call
them (`platforms/compose/.../CjkTextLayoutNode.kt` calls
`positionedClusters`), and the swap program generates Kotlin that must
compose with unswapped callers, so the generated Kotlin must spell the
same top-level declarations. The port keeps every such function as a
static function of a class named after the Kotlin file, receiver as
the first parameter, and marks the declaration; the port's call sites
stay plain static calls.

Two facts force a declaration-side contract. Haxe typing rewrites the
member-call syntax `e.method(a, b)` of a `using` static extension into
the plain static call `Module.method(e, a, b)` before the generator
runs, so extension-ness is not recoverable at the typed call site. And
a statics-only Haxe class is ambiguous between a Kotlin `object` and a
Kotlin file facade (`UnicodeNumber` is a real object;
`SourceInteractionBoundaries` is a file facade), so flattening cannot
be inferred from shape.

## Source-side contract

The markers are metadata on static function declarations:

- `@:topLevel`: the static function emits as a top-level function on
  every target; its class contributes nothing to its emission.
- `@:extension`: the static function emits as an extension of its
  first parameter's type; the first parameter is the receiver. The
  class contributes nothing to its emission.

A class may mix marked and unmarked statics; the unmarked statics keep
their current namespace shapes and the marked ones extract.

A marker on an instance function, an `@:extension` whose first
parameter is a type parameter, and an `@:extension` on a function
without parameters stop the compilation with `top-level markers accept
static functions with a concrete receiver only`.

Private marked statics keep the privacy of a top-level
declaration: the declaration emits
with the target's module-file-private visibility and no import.

## Current translations

| Target | State |
| --- | --- |
| TypeScript | Every static renders as a class static (`TsDecl.hx:110`, `export class X { static ... }`); marked functions do not extract. |
| Kotlin | Statics-only classes render as `object X { fun ... }` (`KotlinDecl.hx:100-115`); mixed classes put statics in a `companion object` (`KotlinDecl.hx:213-224`). No top-level emission exists. |
| Swift | Statics-only classes render as case-less `enum X { static ... }` namespaces (`SwiftDecl.hx:72-84`); `targets/swift.md` rules the call form. No global-function or extension emission exists. |
| Dart | Statics-only classes already flatten to top-level library functions (`DartDecl.hx:86-114`), unconditionally and including classes that mean objects on other targets. No extension emission exists. |
| Rust | Statics-only classes render as `pub struct X;` + `impl X { pub fn ... }` associated functions (`RustDecl.hx:99-115`). No free-function extraction driven by a marker exists. |

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Marked extraction to each target's native top-level and extension forms | Extensions resolve statically on every target: a Kotlin extension compiles to a static function with the receiver first, a Swift extension dispatches statically, a Dart extension resolves at compile time, a TypeScript function and an inherent Rust method are direct calls. Zero indirection, zero allocation, no boxing. | The marker states the intent at the declaration; the receiver is the declared first parameter, stated at the declaration. | One declaration serves every target; no wrapper objects or companion indirection. | Every target reads the construct in its own native spelling, which is what the handwritten Kotlin already spells. |
| Flatten every statics-only class | Dart already does this; the other four targets would follow. | A statics-only class is ambiguous between an object and a file facade (`UnicodeNumber` versus `SourceInteractionBoundaries`), so shape cannot decide. | The same flattening rule re-decided per target. | Kotlin consumers import either an object or a file function; only the marker keeps the two apart. |
| Keep the namespace shapes on all targets | No compiler work. | Cross-file callers in the port resolve the emitted object members as extensions and fail; public platform consumers call extensions. | Every ported file facade drifts from the handwritten Kotlin shape. | Platform consumers see a different API than the handwritten engine. |
| Call-site detection of extension syntax (`using`) | No declaration marker needed. | Haxe typing erases the syntax into a plain static call before the generator runs, so the information does not reach the generator. | Would need pre-typing interception, a second compilation stage. | No candidate exists to read. |

## Ruling

1. `@:topLevel` and `@:extension` are the only source-side forms; both
   ship in one change on all five targets.

2. Declaration emission:

   | Target | `@:topLevel fun f(a: A): R` | `@:extension fun f(r: Receiver, a: A): R` |
   | --- | --- | --- |
   | TypeScript | `export function f(a: A): R` in the module file | `export function f(r: Receiver, a: A): R` in the module file |
   | Kotlin | `fun f(a: A): R` in the file facade named after the module, package from the module path | `fun Receiver.f(a: A): R` in the same facade |
   | Swift | `func f(a: A) -> R` at file scope | `extension Receiver { func f(a: A) -> R }` at file scope |
   | Dart | top-level library function | `extension <Receiver>Extension on Receiver { ... }` (named extension) in the library |
   | Rust | `pub fn f(a: A) -> R` in the module | crate-owned receiver type: `impl Receiver { pub fn f(&self, a: A) -> R }`; foreign receiver type (a standard-library type or a type from another module family): the `@:topLevel` free-function form with the receiver first |

3. Call-site emission: the port's call sites are plain static calls
   `Module.f(x, a)` after Haxe typing. When the callee is marked, the
   first argument moves to the receiver position on the
   extension-spelling targets and the class qualifier disappears:

   | Target | `@:topLevel` call | `@:extension` call |
   | --- | --- | --- |
   | TypeScript | `f(x, a)` with a function import | `f(x, a)` with a function import (receiver stays the first argument) |
   | Kotlin | `f(x, a)` with a same- or cross-package function import as needed | `x.f(a)` with a function import as needed |
   | Swift | `f(x, a)` | `x.f(a)` |
   | Dart | `f(x, a)` | `x.f(a)` |
   | Rust | `f(&x, a)` or the borrow the parameter rules already render | crate-owned receiver: `x.f(a)`; foreign receiver: `f(&x, a)` |

   Dart extensions carry a name derived from the receiver type (the
   rendered type with characters outside identifiers dropped, then
   `Extension` appended). Unnamed Dart extensions resolve only inside
   their declaring library, so the cross-library consumer calls of the
   call-site table cannot resolve an unnamed extension; a name keeps the
   declaration usable from every importer. The import stays unprefixed:
   a library import brings named extensions into scope for member
   resolution.

4. The Kotlin facade file for a module named `m` in package `p` is the
   generated file for the module's path, spelled so that cross-package
   imports of a single function name resolve
   (`import p.f`). Same-package call sites render unqualified.

5. Privacy: a private marked static emits as private on Kotlin
   (`private fun`), unexported on TypeScript, `private` on Swift,
   library-private (`_`-prefixed or `private`) on Dart following the
   target's existing private-member spelling, and un-`pub` on Rust.
   Private declarations never render an import.

6. The Rust receiver borrow follows the existing parameter borrow rules
   of the Rust lane; extension extraction introduces no new borrow
   policy.

7. A marked function never also emits in its class's namespace; when
   every static of a class is marked, the class emits nothing on every
   target, and the Dart unconditional flattening of statics-only
   classes no longer applies to a fully extracted class.

## Samples and tests

- `samples/boring/FileLevelOps.hx`: a class holding `@:topLevel`
  statics (one public, one private) consumed from another module in
  the sample tree; rows assert the rendered results and the private
  row asserts within the declaring module only.
- `samples/boring/ExtensionOps.hx`: `@:extension` statics over a
  sample-declared enum (crate-owned shape), over `String` (foreign
  shape), one private extension, and one cross-module consumer module
  calling each; every call site spells the plain static call and the
  rendered results assert the extension behavior.
- Both modules and their consumer enter all eight generation hxml
  files; `samples/tests/` gain `@:test` functions and probe modules
  gain the named error as ordinary statics following the
  `ValueRecordProbes` pattern: a marker on an instance function, an
  `@:extension` whose first parameter is a type parameter, and an
  `@:extension` without parameters.
- Tree assertions in `tests/ts/`: the Kotlin tree renders
  `fun Receiver.f(` and `private fun`, with no `object` for a fully
  extracted class; the TypeScript tree renders
  `export function f(receiver: Receiver` with the receiver first; the
  Swift tree renders `extension Receiver {` and a file-scope `func`
  for `@:topLevel`; the Dart tree renders `extension on Receiver {`
  and a top-level function; the Rust tree renders `impl Receiver {`
  for the owned receiver and a free `pub fn` for the `String`
  receiver. No lane renders the declaring class name at any marked
  call site.
- Lanes: the full `bun run verify` chain; the consistency manager must
  report identical identifiers and verdicts across kotlin (baseline),
  haxe, ts, rust, swift, and dart.
- The mutation checks for this feature live in the dispatch task file
  and are part of the completion criteria.
