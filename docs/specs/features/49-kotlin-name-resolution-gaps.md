# Feature spec 49: name resolution gaps in the reflaxe pipelines

This specification records the name-resolution gaps closed across the five
generated targets. Each class below names the Haxe shape that produced an
unresolved reference in generated code, the mechanism behind the gap, and the
rule that resolves it. Every class is anchored by a sample in `samples/boring`
and a stage-1 test in `samples/tests`, registered in all five
`examples/*.hxml` manifests so no target drifts from the others.

## Scope

The gaps span module boundaries and the synthetic classes and runtime modules
Haxe introduces during typing. A cross-module reference is one where the
definition and the call site live in different Haxe modules (and therefore
different emitted files). Kotlin, TypeScript, Rust, Swift, and Dart each lower
these references; the classes below were fixed per-target as the registering
samples exposed them.

## Class 1: cross-module implements clause

### Mechanism

A class that implements an interface declared in a different module emits an
`implements`/`impl`/`conformance` clause naming that interface. The Kotlin
target emitted the interface name without recording an import for the
interface type, so `class InkTextShaper : TextShaper` failed to resolve
`TextShaper` when the interface lived in another package.

### Rule

Each target records the interface type on the `imports`/`imports`-equivalent
when it lowers the implements clause. Same-module interfaces still emit no
import; the clause names the interface unqualified. Runtime resident
interfaces route through the same tables the resident runtime uses.

### Worked example

`samples/boring/InkTextShaper.hx` declares an interface in `std.RenderShape`
and implements it from the `boring` package. `PosterShapeTests` drives the
instance through the interface parameter; generated code before the fix named
`TextShaper`/`RenderShape` with no import, so the implementing class's
conformance clause pointed at an unresolved trait. The fix records the import
at the implements clause, so the generated `impl TextShaper for InkTextShaper`
resolves.

## Class 2: single-variant exception fold

### Mechanism

A `haxe.Exception` subclass whose payload enum has exactly one variant folds
into a sealed hierarchy. The Kotlin target kept a separate penalty object for
the single-variant payload; the fix preserves the fold so the message text
stays on the emitted variant, with no runtime-dependent accessor.

### Rule

A payload enum with exactly one constructor emits as the sealed hierarchy's
single `data object` carrying the exception's message text. The fold applies
to every target on the same sealed shape.

### Worked example

`samples/boring/NoSuchElementFaultException.hx` wraps a one-variant
`NoSuchElementFault` enum. Generated Kotlin is `data object Missing :
NoSuchElementFaultException("no such element")`; the `catch` site reads the
message from the folded value.

## Class 3: folded exception message read outside a catch

### Mechanism

Reading `.message`/`get_message` on an exception value was lowered to the
native message property only when the value sat in a catch-variable position.
A message read outside a catch (a plain parameter or a field) emitted the
runtime-dependent `get_message()` accessor, which the folded sealed class
lacks.

### Rule

A `message` or `get_message` read maps to the native message property
whenever the subject's type resolves to a folded exception subclass, whether
or not the value is a catch variable. Each target follows the subject type
and routes the read to the property, never the accessor.

### Worked example

`samples/boring/NoSuchElementMessageReader.hx` reads `error.message` from a
plain parameter position. Generated Kotlin/Swift/TS read `error.message`
(property), Rust renders `format!("{}", error)` through the variant's
`Display`, and Dart reads the field directly. Without the fix the read emitted
`error.get_message()`, which the folded type does not define.

## Class 4: StringTools static routing to a runtime module

### Mechanism

`StringTools` statics without a native `String`-equivalent inline lowering
(`lpad`, `rpad`, `ltrim`, `rtrim`, `replace`) lowered to a bare top-level
`StringTools.<name>` reference. No target's runtime provided that module, so
the generated call was unresolved whenever a sample used one of those statics.

### Rule

The non-inline `StringTools` statics route into a resident
`runtime.StringTools` module. Each target rewrites the call at the reference
site to the runtime module and forces the resident module at registration so
its generated body is emitted. The inline-lowered statics (`hex`, `trim`,
`startsWith`, `endsWith`) keep their per-call inline forms.

### Worked example

`samples/boring/StringToolsOps.hx` drives `lpad`, `ltrim`, `rtrim`, and
`replace`. Generated Kotlin calls `StringTools.lpad(...)` on the compiled
`runtime.StringTools`, TS imports it from `@boring/runtime`, Dart and Swift
route through their runtime residents, and Rust references
`string_tools::StringTools::lpad(...)`.

## Class 5: referenced abstract `Impl_` companions

### Mechanism

A sub-type abstract's non-inline static (for example `FontId.of`) lowers to a
call on the synthetic `FontId_Impl_` implementation class. Every target
skipped synthetic `*_Impl_` classes during declaration lowering, so the
referenced `_Impl_` object was never emitted and the cross-module call site
stayed unresolved. Fully-inline integrated abstracts (whose calls inline
before any reference survives) were correctly dropped alongside the
unreferenced impls.

### Rule

A synthetic `*_Impl_` class emits when a generated reference names its
statics (`Name_Impl_.<field>`). Each target records the referenced module at
the reference site and lets `compileClassImpl` emit the `_Impl_` body
(companion declarations for its referenced statics) in place of dropping it.
Unreferenced synthetic impls, and fully-inline abstracts whose calls never
name the module, still emit nothing.

### Worked example

`samples/boring/FontId.hx` declares `abstract FontId(String)` with a
non-inline `static function of`. `FontIdConsumer.hx` in the same package
calls `FontId.of(...)`. Generated Kotlin emits
`object FontId_Impl_ { fun of(...) }`, TS the `FontId_Impl_` class, Rust the
`FontId_Impl_` struct, Swift the `FontId_Impl_` enum, and Dart the top-level
`of` function in `font_id.dart`. The call site references resolve against that
emitted object.

## Class 6: cross-module data-class comparators

### Mechanism

A `@:dataClass` record whose field is a `std.ReadOnlyArray` of another
`@:dataClass` (or that holds one directly) generates a comparator that calls
the element record's `compare_*`/`compare<Name>` function. Rust and Dart
emitted that reference unqualified across module boundaries: the element
comparator lives at module level in its own file and library, so the caller
could not resolve it. Direct `arr[i].<field>` reads already resolve; the gap
was the comparator the record generates over those element arrays.

### Rule

A `@:dataClass` comparator reference to another data class's compare function
resolves through the target's import tables. Rust imports the element
comparator function of that module; Dart qualifies the call through the
element library prefix. Same-module comparators stay unqualified.

### Worked example

`samples/boring/GlyphCluster.hx` declares a `@:dataClass` record and
`samples/boring/GlyphClusterHolder.hx` a record whose field is
`ReadOnlyArray<GlyphCluster>`. `GlyphClusterReader.hx` reads
`arr[i].clusterRange` directly. Generated Rust calls
`compare_glyph_cluster(...)` with an import from `glyph_cluster.rs`; generated
Dart calls `glyph_cluster.compareGlyphCluster(...)` through the element
library. `GlyphClusterTests` drives the reads on all five targets.

## Tests

Each class has a named stage-1 test in `samples/tests`: the class-1 and -2
cases live in `PosterShapeTests`/`ShapeTextTests` and `NoSuchElementTests`,
class 3 in `NoSuchElementTests.messageRead`, class 4 in `StringToolsTests`,
class 5 in `FontIdTests`, and class 6 in `GlyphClusterTests`. Every test module
is registered in all five `examples/*.hxml` manifests; `test:consistency`
asserts all six targets agree on the full test id set.