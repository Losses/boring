# boring

boring is a Haxe / Rust / TypeScript mixed-language repository hosting one
binary codec and the shared test vectors that every implementation must
reproduce byte for byte.

The four implementations are independent: TypeScript under bun, Haxe
compiled to JS, Kotlin executed on the JVM, and Rust built with cargo.
All four decode `tests/vectors/roundtrip.bin` to the same records and
encode those records back to the same bytes.

Implementations and test tooling live in separate trees: the languages
implement the codec under `ts/`, `haxe/`, `rust/`, and `kotlin/`; every
test suite and the shared vectors live under `tests/`.

The root `package.json` is the bun workspace (member: `ts`); the root
`Cargo.toml` is the cargo workspace (member: `rust`). The Rust test suite
carries no manifest of its own: `rust/Cargo.toml` wires it in through an
explicit `[[test]]` path into `tests/`.

## Layout

| Path | Content |
| --- | --- |
| `ts/` | `@boring/codec`, the TypeScript codec package |
| `haxe/` | Haxe library sources |
| `rust/` | Rust crate with the codec implementation |
| `kotlin/` | Kotlin codec source tree |
| `tests/` | Test suites per language plus the shared vectors |
| `tools/` | ESLint plugin, doc-style checker, commit tool, git hooks, vector generator |

## Toolchain

The flake fixes the toolchain versions: haxe, bun, nodejs, the Kotlin/JVM
compiler with JDK 21, and a stable rust toolchain from the rust overlay.
The reflaxe compilation-target framework is a pinned flake input
(`SomeRanDev/reflaxe` v3.0.0) registered as a dev haxelib on shell entry.
Enter the environment with:

    nix develop

The Android SDK, browsers, and fonts from the tiqian flake are absent
here; this repository needs none of them.

## Build and test

    nix develop -c bash -c "bun install"
    nix develop -c bash -c "bun run verify"

`verify` runs the TypeScript tests, the Haxe checks, the Rust tests, ESLint,
`tsc`, the documentation style check, and the vector regeneration. See
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
