# Standard library spec 06: std modules and the runtime package

## Scope

This specification rules the shape of the subset's own standard library
(`samples/std/`), the namespaces the toolchain reserves, and how every
target references and materializes the runtime package that backs it.
It governs `src/RuntimeConfig.hx`, the
`runtime-import` and `runtime-emit` defines read from
`examples/ts.hxml` and `examples/kotlin.hxml`, the import
tables `src/reflaxe/ts/tscompiler/TsImports.hx` and
`src/reflaxe/kotlin/kotlincompiler/KotlinImports.hx`, and the shim
sources in `src/reflaxe/kotlin/kotlincompiler/KotlinRuntime.hx`.

## Reserved namespaces

Two namespaces are reserved on the compile-input side:

- `haxe.*`: the modules of the Haxe standard library the subset
  translates (`haxe.io.Bytes`, `haxe.io.BytesBuffer`, `haxe.io.FPHelper`,
  `haxe.Exception`, `haxe.Int64`).
- `std.*`: the subset's own modules declared in `samples/std/`
  (`std.ReadOnlyArray`, `std.Console`, `std.Process`).

The compiler treats both like compiler-recognized namespaces: modules in
them may be entry points, and references to them route through the
std import tables.

`haxe.*` never reaches any target's output: every `haxe.*` module lowers
to a runtime-package declaration or a platform-native mapping. `std.*`
splits into two classes, decided per target by a named list in that
target's import table:

- **Runtime-backed std modules** never emit a file. Their backing lives
  in the runtime package (`std.ReadOnlyArray`, `std.StringBuf`,
  `std.UString`, `std.Graphemes`, `std.SortedMap` and its relatives,
  `std.Test`, and the internal `std.Functional`, `std.UStringRT`) or in
  a platform-native mapping where the target provides one. TypeScript
  names the class in `TsImports.runtimeProvidedModules`; Kotlin names
  its shim-emitted subset in `KotlinImports.SHIM_MODULES` and
  constructs the remaining runtime-package references in the expression
  compilers.
- **Compiled std modules** emit like any other module under the target's
  std directory. `std.UStringException` and `std.UStringFault` are this
  class (`reference/ts/gen/std/UStringException.ts`,
  `reference/kotlin/gen/std/UStringException.kt`); a reference from a
  compiled module to another compiled module is an ordinary
  cross-package file import.

Class membership is a named list, and the safe direction is explicit: a
module absent from the list emits as a compiled module, which compiles
and runs; the reverse shape, a runtime-backed module silently treated
as compiled, would leave the target without its backing. Adding a
runtime-backed module therefore means adding its name to each target's
list, and this specification is amended together with that change.

`reference/kotlin/gen/boring/BinaryWriter.kt` importing `haxe.io.BytesBuffer` and
TypeScript files importing a runtime module by a path that walks out of
their package directory were both defects of this rule and are removed.

## The runtime package

Every compilation's output references at most one runtime package. The
package holds the target-language backing of the std modules: the
TypeScript `runtime.ts` (byte buffer sink, IEEE-754 conversions) and the
Kotlin shim declarations (`BytesBuffer`, `Int64Halves`, `FPHelper`,
`Console`, `Process`). Platform-native mappings (`haxe.Exception` to
`RuntimeException`, `std.Process.exit` to `kotlin.system.exitProcess`)
are not runtime-package declarations; the target toolchain provides them.

Resident modules are Haxe sources under `src/runtime/` that every target
compiles into the runtime package (`runtime.UString`,
`runtime.Graphemes`, `runtime.SortedTable`, `runtime.TestCore`). A
resident is the single implementation of its std face: each target
lowers references to the face onto the resident's output, no
per-target copy exists, and the resident's emission gates on the
faces being used. The sorted faces (`std.SortedMap`, `std.SortedSet`,
and their builders) lower onto `runtime.SortedTable` (spec 07).

## Identity from defines

The runtime package's identity enters through configuration; the
compilers hold none of it:

- `runtime-import=<name>`: how generated code references the package.
  TypeScript renders the name verbatim as a module specifier
  (`import { BytesBuffer } from "@boring/runtime"`); Kotlin renders it
  as a dotted package (`import boring.runtime.BytesBuffer`); a future
  Rust target takes its crate name from the same define. The
  `runtime-import` value for a four-package consumer names one shared
  runtime package; `boring.std` and `tiqian.boring.std` are both wrong
  shapes because `std` is a source-side identity that does not appear
  in output.
- `runtime-emit=<dir>`: `none` (or absent) writes references only,
  which is the bring-your-own mode; any other value writes the runtime
  files under that directory, relative to the target's output root.

No default exists for `runtime-import`. The name has no source inside
the compilation: the typed AST and the source module paths cannot
derive the consumer's package identity. A compilation that references
a runtime declaration without the define stops with
`runtime-import define is required to reference the runtime package`.
Baking a default name in would be the compiler assuming the consumer,
which the toolchain rejects elsewhere for the compiled sources.

## Entry points

The runtime package exposes two entry points.

- **General entry**: `@boring/runtime` on TypeScript, package
  `boring.runtime` on Kotlin, the runtime crate root on Rust. It holds
  every runtime declaration a program in a browser can load. Contract:
  no `node:` import specifier and no host process API anywhere in the
  entry. `tests/ts/runtime-entry.test.ts` scans the emitted file each
  test run.
- **Test entry**: `@boring/runtime/test`, package
  `boring.runtime.test`, module `crate::runtime::test`. It holds the
  test helper's result writer, which needs the host file system.
  Generated business code never imports it; generated test code
  imports it for `std.Test`. The assertion resident `runtime.TestCore`
  compiles into this entry beside the handwritten host of each target;
  its emission gates on `std.Test` usage, so the two always appear
  together.

The Kotlin and Rust targets have no import-time execution, so their
layout keeps the test entry as a separate compilation unit inside the
one emitted tree (directory `test/` under the runtime root). The
TypeScript target needs the split at module resolution: a browser that
imports the general entry must never transitively resolve `node:fs`.

## Error contract

Two failure sites, each inside its own visibility:

1. The define is missing while a runtime declaration is referenced: the
   Haxe compilation errors, because the import statement cannot be
   written.
2. The define is present and the target-side package is absent: the
   Haxe compilation succeeds, and the target toolchain reports the
   missing package precise to the declaration (tsc
   `Cannot find module`, kotlinc `unresolved reference`). The Haxe
   compiler cannot see target-side package resolution and does not
   pretend to.

The second site is sound because every runtime reference flows through
the import tables (`TsImports.runtime`, `KotlinImports.requireType`
over the shim-module table); no generated file references a runtime
declaration outside its import block.

## Emission

Runtime files are emitted on demand. A compilation writes a runtime
file only when its generated modules referenced the corresponding
declarations, and only under `runtime-emit`'s directory; shim sources carry
no package line, and the emitter prefixes the configured package
directive. The test entry emits under a `test/` subdirectory of the
runtime root when any generated test code referenced `std.Test`. A
consumer generating four packages runs one compilation
that contains only the std modules with `runtime-emit` pointing
at the runtime package's root, then compiles the four business
packages with `runtime-emit=none` against the same `runtime-import`
name.

The compiler distribution always carries the runtime sources
(`TsRuntime.hx`, `KotlinRuntime.hx`); `runtime-emit` decides disk
writes only. No mode produces output that runs without the runtime
package.

## Test hooks

- `tests/ts/compiler-scope.test.ts` scans the compiler directories
  (including `src`) for sample-source names; the configuration
  carries the identities, so the compilers carry no sample names.
- `tests/reference/ts/generated-tree.test.ts` imports the generated tree through
  the `@boring/runtime` specifier resolved by `tsconfig.json` `paths`,
  which is the same wiring a bring-your-own consumer uses.
- `tests/ts/runtime-entry.test.ts` enforces the entry-point contract:
  the emitted general entry contains no `node:` specifier and no test
  helper, the test entry owns both, business code imports only the
  general entry, and test code imports `Test` only from the test entry.
- `package.json` `test:kotlin` compiles `reference/kotlin/gen` together with
  `reference/kotlin/gen/runtime`, where the shims are written under `package
  boring.runtime`.
