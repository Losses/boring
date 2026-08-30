# Feature spec 24: Package shell emission

## Scope

This specification rules the package manifest each target compiler writes
next to the generated source. One compilation produces one source tree
per target; under this specification the tree is also a loadable package
of its ecosystem: a `Cargo.toml` for Rust, a `package.json` for
TypeScript, a `Package.swift` for Swift, a `pubspec.yaml` for Dart, and
a `build.gradle.kts` for Kotlin. The manifest states the identity of the
tree and the paths the generator itself wrote, nothing else.

The responsibility split is the scope boundary. The generator owns what
is derivable from the compilation: the package identity passed as
defines, the library entry path, the fact that the translatable subset
references no external library, and the toolchain dialect floor the
generated code needs. The consumer's build owns everything else:
workspace membership, publication coordinates, repositories, and any
dependency graph beyond the tree itself. A manifest field with no source
inside the compilation does not exist in this specification.

Before this specification the shells were hand-written where a build
needed them: `reference/rust-gen/Cargo.toml` and
`reference/rust-f32-gen/Cargo.toml` wrapped the generated Rust crates,
and `reference/ts/package.json` wraps the hand-written `@boring/codec`
oracle tree (a different tree from the generated one). Hand shells drift
when the generator renames files, moves the runtime, or adds an emitted
entry; the drift appears as downstream build failures. The emission
moves that maintenance from every consumer to the generator.

## Defines

- `package-shell=emit|none`: `emit` (the default when the define is
  absent) writes the manifest; `none` writes source only. Any other
  value stops the compilation with `package-shell accepts emit or none`.
- `package-name=<string>`: the package name in the manifest. Default
  `generated`, a neutral value: the compiler assumes no repository or
  package identity of the sources it compiles. Each ecosystem validates
  names at build time; the emitter passes the value through.
- `package-version=<string>`: the version field. Default `0.1.0`.
- `package-license=<string>`: optional. The license field appears only
  when the define is present; the generator does not guess a consumer's
  license.
- `package-test=<name>:<path>`: Rust only, optional. Emits one `[[test]]`
  integration-test block. This is the one field that carries repository
  geometry (boring keeps its integration tests outside the crate
  directories), so it exists only through this explicit define.

## Emitted artifacts

| Target | File | Content |
| --- | --- | --- |
| Rust | `Cargo.toml` | `[package]` name, version, license when given; `edition = "2024"`; `autotests = false`; `[lib] path = "lib.rs"`; zero dependencies; one `[[test]]` block per `package-test` define |
| TypeScript | `package.json` | name, version, license when given; `private: true`; `type: "module"`; `exports` map over the emitted top-level entries plus the runtime entry; `devDependencies` with `typescript ^5.9.0` |
| Swift | `Package.swift` | `swift-tools-version:5.9`; one library target with `path: "."` and a `sources` list of the emitted top-level entries; no license field, because PackageDescription carries none |
| Dart | `pubspec.yaml` | name, version, license when given; `environment.sdk ^3.0.0` |
| Kotlin | `build.gradle.kts` | `kotlin("jvm") version "2.4.10"`; `repositories { mavenCentral() }`; main source set `srcDir "."` |

## Candidate translations

### Candidate 1: Emit by default, opt out through the define

Every compilation writes the manifest into the main output directory.
Consumers that maintain their own manifest pass `package-shell=none`
once.

- performance: no runtime cost; the manifest is build-time text.
- ambiguity: the tree and the manifest cannot disagree, because one
  compilation produces both.
- redundancy: the hand-maintained copies retire; the f32 lanes stop
  duplicating shells.
- readability: the manifest reads as an ordinary file of its ecosystem.

### Candidate 2: Emit only on request

The manifest appears when the consumer passes an explicit enable.

- performance: as Candidate 1.
- ambiguity: as Candidate 1 for the trees that carry a manifest.
- redundancy: consumers that want a shell and forget the define keep
  hand shells, so both maintenance modes persist.
- readability: as Candidate 1.

### Candidate 3: Keep the status quo

The generator writes source only; every consumer builds and maintains
the shell.

- performance: no runtime cost.
- ambiguity: shell-tree drift is unbounded; nothing relates a manifest
  to the compilation that produced the tree it wraps.
- redundancy: every consumer repeats the same fields.
- readability: no generated manifest exists to read.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| C1 default emission | no runtime cost | tree and manifest share one producer | hand copies retire | ordinary manifest text |
| C2 opt-in emission | no runtime cost | as C1 where enabled | both modes persist | as C1 |
| C3 status quo | no runtime cost | drift unbounded | repeated per consumer | n/a |

## Ruling

1. **Default on, overwrite, one-line opt-out.** The manifest is written
   whenever `package-shell` is absent or `emit`. Regeneration overwrites
   the manifest at its path; the output directory belongs to the
   generator. A consumer maintaining its own manifest passes
   `package-shell=none`, and that define is the whole takeover
   ceremony.
2. **Identity from defines.** Name defaults to `generated`, version to
   `0.1.0`; the license field appears only under `package-license`. The
   neutral name default keeps the compiler free of the compiled
   repository's identity, the same boundary the compiler-scope scan
   enforces. The emitter adds no fields beyond the table above.
3. **Location.** The manifest is written into the main output directory (the
   `*-output` define). Test-output trees receive no manifest: a test
   tree is not a package.
4. **Rust.** The manifest declares the crate the compiler already
   emitted: `[lib] path` is the compiler's crate root file, dependencies
   are empty (the subset references no external crate), and `edition`
   pins the dialect the current tree uses. The generated `tests/`
   directory is a `#[cfg(test)]` module tree of the library, so test
   autodiscovery is off; without `autotests = false` cargo would
   compile those module files as standalone integration tests where the
   `crate::` paths no longer resolve. `package-test=name:path` appends
   one `[[test]]` block for repositories that keep integration tests
   outside the crate; the path is interpreted by cargo; the emitter does
   not validate it.
5. **TypeScript.** The tree is TypeScript source, so the manifest
   carries `type: "module"` and a `typescript` devDependency for
   consumers that typecheck; the version follows the repository's own
   floor (`^5.9.0`). The `exports` map exposes what the compilation
   emitted into the main tree: one directory wildcard per emitted
   top-level package directory (`"./boring/*": "./boring/*.ts"`), one
   file entry per top-level file module, and `"./runtime"` pointing at
   the emitted runtime entry when the compilation used the runtime.
   The map holds no root entry: a generated tree has no single entry
   module, so a consumer imports a module path
   (`generated/boring/Fp32`), and the wildcard `*` matches nested
   paths because the exports pattern substitution is a string
   replacement. Test modules compile into the test-output tree and
   receive no entry; a module that stays in the main tree under a
   `tests` path (the shared test fixtures) is main-tree code and gets
   the entry of its directory, because the emitter applies no naming
   conventions beyond the routing the compilation already decided.
   The runtime test entry (`runtime/test.ts`) stays unexposed for the
   same reason: it is test-tree code emitted beside the main tree.
   Keys sort, so the map is a pure function of the module set.
   `private: true` is
   emitted because a generated source tree is consumed by a build, and
   publishing is an explicit downstream act that starts with taking
   over the shell. The validity condition is a relative runtime
   import: generated files reference the runtime through the
   `runtime-import` define, and a by-name import such as
   `@boring/runtime` names a package coordinate that does not exist, so
   a compilation combining a by-name runtime import with an emitted
   manifest stops with `package shell requires a relative runtime
   import: a by-name runtime import names a package the manifest cannot
   declare; pass runtime-import a relative specifier or package-shell
   none`. When `runtime-import` carries a relative specifier, the
   compiler computes the per-file relative path to the runtime entry,
   the same computation the test imports already use.
6. **Swift.** The manifest declares one target over the output
   directory. The `sources` list names the emitted top-level entries
   (every directory and file except the manifest and
   `_GeneratedFiles.txt`), computed from the module set of the
   compilation, so the list tracks the tree by construction.
   `package-license` has no field to fill on this lane: PackageDescription
   carries no license declaration, so the define is not read.
7. **Dart.** The generated tree already sits under `lib/`, the layout
   the Dart toolchain requires; the manifest names the package and the
   SDK floor. Imports inside the tree are relative sibling paths, so no
   package-name coupling exists.
8. **Kotlin.** The manifest is a plain JVM module: the Kotlin plugin at
   the repository's compiler version, `mavenCentral`, and the main
   source set pointing at the output directory. Including the module in
   a build stays a `settings.gradle.kts` act on the consumer side; the
   manifest compiles standalone inside any Gradle build that includes
   it.
9. **Dialect floors stay conservative.** `edition 2024`,
   `swift-tools-version 5.9`, `sdk ^3.0.0`, and the Kotlin plugin
   version state the oldest dialect the current toolchain verified. A
   floor moves only when generated code needs a newer feature; package
   managers keep backward compatibility, so the floors age slowly.
10. **Verification split follows the toolchain.** The cargo workspace
    points its members at the emitted manifests and `cargo test` builds
    them; the npm manifest is exercised by a consumer program run under
    bun from a generated temp tree; the Dart manifest is checked with
    `dart analyze`. This toolchain carries `swiftc` without `swift
    build` and no Gradle, so the Swift and Gradle manifests are pinned
    byte for byte by test and validated by downstream builds. The split
    follows from this repository's toolchain; the specification itself
    requires none.
11. **Determinism.** Manifest bytes are a pure function of the defines
    and the emitted module set: no timestamps, no absolute paths, no
    environment probes. Two identical compilations produce identical
    manifests.

## Test hooks

- `tests/ts/package-shell.test.ts`: generates into a temp directory and
  asserts the default emission (field values, the `exports` map, a
  consumer program run under bun against the temp tree, and a second
  consumer that imports through a symlinked `node_modules` entry by
  package name), the `none` opt-out (no manifest file), the
  invalid-value rejection, the by-name runtime-import rejection, and
  the pinned Swift and Gradle manifest bytes.
- The root `Cargo.toml` workspace declares the generated crates at
  `reference/rust-gen/src` and `reference/rust-f32-gen/src`; their
  emitted `Cargo.toml` files are the crate manifests `cargo test` uses.
- `test:dart` appends `dart analyze --no-fatal-warnings` over the
  generated package: the step validates that the manifest loads and the
  tree carries no errors. Warnings stay non-fatal because the generator
  emits defensive `!` operators where Dart flow promotion makes them
  redundant (`unnecessary_non_null_assertion` on
  `default_args_ops.dart` and `pipeline_ops.dart`); modeling promotion
  in the generator is separate work.
- `examples/rust.hxml` and `examples/rust-f32.hxml` carry the identity
  and `package-test` defines; `examples/ts.hxml` keeps
  `package-shell=none` because the repository resolves the runtime by
  name through `tsconfig.json` paths, and `examples/kotlin.hxml`,
  `examples/swift.hxml`, and `examples/dart.hxml` emit with the default
  identity.
