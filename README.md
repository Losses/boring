# boring

boring provides a Haxe transpilation package and a project driver package to
tiqian. The compiler translates tiqian's Haxe sources through the reflaxe
targets under `packages/compiler/reflaxe/`. The driver runs project generation,
tests, comparison, and packaging through the `boring` command.

Every file under `samples/` demonstrates language capabilities of the
translatable subset. The sample set debugs each language feature of the
targets; it grows as the accepted construct set grows.

The trees under `reference/ts/src/`, `reference/kotlin/src/`, and
`reference/rust/src/` are hand-written reference translations.
Every tree decodes `tests/vectors/roundtrip.bin` to the same records and
encodes those records back to the same bytes; the generated trees
(`reference/ts/gen/`, `reference/kotlin/gen/`, `reference/rust/gen/`)
must reproduce that behavior against the same vectors. Reference
translations and test tooling live in separate trees; every test suite
and the shared vectors live under `tests/`.

The root `package.json` is the bun workspace (member:
`reference/ts`); the root `Cargo.toml` is the cargo workspace (members:
`reference/rust`, `reference/rust/gen`). The Rust test suite carries no
manifest of its own: `reference/rust/Cargo.toml` wires it in through an
explicit `[[test]]` path into `tests/`.

## Layout

| Path | Content |
| --- | --- |
| `packages/compiler/` | the transpilation toolchain: the interception pass, the runtime-package configuration, and the reflaxe targets (`packages/compiler/reflaxe/ts/`, `packages/compiler/reflaxe/kotlin/`, `packages/compiler/reflaxe/rust/`); exposed as the `boring` haxelib package through `haxelib.json`, `extraParams.hxml`, and `defines.json` |
| `packages/driver/` | the delivered project driver package; its `boring` command reads a consumer's `boring.json` and runs generation, tests, comparison, and packaging |
| `samples/` | Haxe capability samples for the translatable subset, including the subset standard library `samples/std/` |
| `examples/` | generation entries (`ts.hxml`, `kotlin.hxml`, `rust.hxml`) and the reflaxe smoke file; each entry demonstrates package consumption |
| `reference/ts/` | hand-written TypeScript reference translation (package `@boring/codec`); `reference/ts/gen/` is the gitignored reflaxe-generated tree |
| `reference/rust/` | hand-written Rust reference translation; `reference/rust/gen/` holds the reflaxe-generated Rust crate (gitignored sources) |
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

### When `nix develop` cannot run (recorded 2026-10-01)

The two commands below are the documented path and should be used when they work.
In a sandboxed environment they may not, and the failure is **not** obvious — so
what still works is recorded here rather than left to be rediscovered:

    $ nix develop -c echo ok
    error: ... attempt to write a readonly database
      (in '/home/losses/.cache/nix/fetcher-cache-v4.sqlite')

The cache file is mode 644 and owner-writable; the denial is the sandbox refusing
writes **outside the workspace**, so `nix develop` — and therefore `bun run
verify` and every `tests/haxe/**/run.sh` that insists on a pinned shell — cannot
run. Of the tools the flake provides, only what is already on `PATH` is usable:

| Tool | On `PATH` |
|---|---|
| `bun`, `nix` | yes |
| `haxe`, `cargo`, `kotlinc`, `swiftc`, `boring` | **no** |

**All four sandbox limits, in one place** (each re-checked 2026-10-01; the
underlying measurements are recorded in `docs/architecture/ARCHITECTURAL-CONTRACTS.md`, `docs/architecture/LAYERED-VERIFICATION.md`, and the CI baseline wiring in `.github/workflows/ci.yml`, not duplicated here):

| # | Limit | Blocks |
|---|---|---|
| 1 | `nix develop` — writes to `~/.cache/nix` denied | `bun run verify`, and every `tests/haxe/**/run.sh` |
| 2 | `swiftc` — 13 libs missing, and its wrapper needs user namespaces denied | the whole Swift lane |
| 3 | `haxe`/`cargo`/`kotlinc` off the default `PATH` | 56 tests, which then read as failures |

All three are **why results must be read carefully**. None is a defect in this
repository.

**A fourth was listed here and removed the same session, because it was wrong.**
It said writes to the Tiqian checkout's `.git` blocked obtaining the pinned
revision. That conflated two questions: *"can that existing checkout be updated"*
(no) and *"can the revision be obtained"* (**yes** — clone into the workspace,
which is writable). The probe verified `8504d230` and
`engine-haxe/tests/compile.hxml` in the clone before the entry was deleted. The superseded reasoning is retained in the wb record (task t-musjpp6r-k39m
migration notes) rather than quietly replaced.

**What still works without the flake** — the tests invoke `haxe`/`cargo`/`kotlinc`
by name and do not locate them themselves, so the toolchains must be on `PATH`
however you arrange that (the flake normally does it):

    bun test tests/                    # the collected suite
    bun test tests/ts/loop-structure.test.ts

**What does not**, and why it matters for reading results:

- `bun test tests/` **without** `haxe` on `PATH` reports **61 failures (1000
  pass)**; with it on `PATH`, **5 failures (1075 pass)**. Those 56 are
  toolchain-absent, not defects — the CI baseline step in `.github/workflows/ci.yml`
  measures the class by running both ways rather than inferring it from a marker;
- the Swift lane cannot run at all here (`swiftc` needs 13 missing libraries, and
  its wrapper needs user namespaces the sandbox denies), which is why the
  residual 5 also cannot be cleared;
- 35 fixtures under `tests/haxe/` are uncollected **and** unrunnable here, so
  they are neither known-passing nor known-failing. See the CI baseline step in
  `.github/workflows/ci.yml` and `docs/architecture/LAYERED-VERIFICATION.md`.

## Build and test

    nix develop -c bash -c "bun install"
    nix develop -c bash -c "bun run verify"

`bun run verify` first runs `boring verify` over this repository's
`boring.json`. That command generates all ten target configurations, tests
them, and compares the six binary64 configurations with Kotlin as the
baseline. The four f32 configurations run tests but have `compare: false`.
Generated code goes under the gitignored `reference/<id>/gen` and
`reference/<id>/gen-tests` directories. The script then runs repository
tests, cross-target driver checks, linting, type checking, documentation
checks, vector regeneration, and a reflaxe smoke compile. See `AGENT.md`
for the individual commands and repository rules.

The `boring` command also supports `gen <id>`, `test <id>`, `compare`,
`pack <id>`, and `roots <sourceSet> --output <file>`. The [project driver
tutorial](docs/tutorial.md) explains the inputs and results of each command.

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
