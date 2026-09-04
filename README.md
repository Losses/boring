# boring

boring is a Haxe package that exposes the transpilation toolchain to
tiqian. tiqian provides the original Haxe sources and translates them to
each platform through the reflaxe targets under `packages/compiler/reflaxe/`.

Every file under `samples/` demonstrates language capabilities of the
translatable subset. The sample set debugs each language feature of the
targets; it grows as the accepted construct set grows.

The trees under `reference/ts/src/`, `reference/kotlin/src/`, and
`reference/rust/src/` are hand-written reference translations.
Every tree decodes `tests/vectors/roundtrip.bin` to the same records and
encodes those records back to the same bytes; the generated trees
(`reference/ts/gen/`, `reference/kotlin/gen/`, `reference/rust-gen/src/`)
must reproduce that behavior against the same vectors. Reference
translations and test tooling live in separate trees; every test suite
and the shared vectors live under `tests/`.

The root `package.json` is the bun workspace (member:
`reference/ts`); the root `Cargo.toml` is the cargo workspace (members:
`reference/rust`, `reference/rust-gen`). The Rust test suite carries no
manifest of its own: `reference/rust/Cargo.toml` wires it in through an
explicit `[[test]]` path into `tests/`.

## Layout

| Path | Content |
| --- | --- |
| `packages/compiler/` | the transpilation toolchain: the interception pass, the runtime-package configuration, and the reflaxe targets (`packages/compiler/reflaxe/ts/`, `packages/compiler/reflaxe/kotlin/`, `packages/compiler/reflaxe/rust/`); exposed as the `boring` haxelib package through `haxelib.json`, `extraParams.hxml`, and `defines.json` |
| `samples/` | Haxe capability samples for the translatable subset, including the subset standard library `samples/std/` |
| `examples/` | generation entries (`ts.hxml`, `kotlin.hxml`, `rust.hxml`) and the reflaxe smoke file; each entry demonstrates package consumption |
| `reference/ts/` | hand-written TypeScript reference translation (package `@boring/codec`); `reference/ts/gen/` is the gitignored reflaxe-generated tree |
| `reference/rust/` | hand-written Rust reference translation; `reference/rust-gen/` holds the reflaxe-generated Rust crate (gitignored sources) |
| `reference/kotlin/` | hand-written Kotlin reference translation; `reference/kotlin/gen/` is the gitignored reflaxe-generated tree |
| `tests/` | Test suites per language plus the shared vectors |
| `tools/` | ESLint plugin, doc-style checker, commit tool, git hooks, vector generator |

## Toolchain

The flake fixes the toolchain versions: haxe, bun, nodejs, the Kotlin/JVM
compiler with JDK 21, and a stable rust toolchain from the rust overlay.
The reflaxe compilation-target framework is a pinned flake input
(`SomeRanDev/reflaxe` v3.0.0) registered as a dev haxelib on shell
entry; the repository itself is registered the same way, so `-lib
boring` resolves inside the shell. Enter the environment with:

    nix develop

The Android SDK, browsers, and fonts from the tiqian flake are absent
here; this repository needs none of them.

## Build and test

    nix develop -c bash -c "bun install"
    nix develop -c bash -c "bun run verify"

`verify` regenerates the gitignored `reference/ts/gen`,
`reference/kotlin/gen`, and `reference/rust-gen/src` trees through the
reflaxe targets, then runs the TypeScript tests, the Haxe checks, the
Kotlin checks, the interception suite, the Rust tests, ESLint, `tsc`,
the documentation style check, the vector regeneration, and the reflaxe
smoke compile. See
`AGENT.md` for the individual commands and the repository rules.

## Data comparison and commits

Comparing outputs across languages uses the AST (the Haxe implementation
is the reference) or direct comparison of the binary sequences; no
implementation writes its own JSON serializer. Commits follow Conventional
Commits 1.0.0 through `bun run commit`; git hooks installed by
`bun run install:hooks` enforce the documentation style and message
checks. `AGENT.md` states the full rules.

## Vector format

`tests/vectors/roundtrip.bin` holds a magic marker `BRG1`, a big-endian `u32`
record count, then that many 44-byte records. Each record holds a
big-endian `u32` code point followed by five big-endian `f64` values:
`advanceEm` and the four `bounds` fields `xMin`, `yMin`, `xMax`, `yMax`.
Test values are dyadic rationals so every language writes the exact same
bit pattern.

## License

MIT. See [LICENSE](LICENSE).
