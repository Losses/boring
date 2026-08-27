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
std import tables. Neither namespace reaches any target's output.
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
directive. A consumer generating four packages runs one compilation
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
- `package.json` `test:kotlin` compiles `reference/kotlin/gen` together with
  `reference/kotlin/gen/runtime`, where the shims are written under `package
  boring.runtime`.
