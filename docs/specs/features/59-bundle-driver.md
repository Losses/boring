# Feature spec 59: Bundle driver

## Scope

Two groups of functionality ride one compilation. The in-source test bundle
(spec 19) compiles the consumer's tests into each target's own test
arrangement; the distribution artifact (specs 24 and 25) writes the manifest
and the install artifact of the tree the compilation emitted. Both are
selected by defines on the same `haxe` invocation, and both are already
implemented by the compiler.

The layer above them does not exist. No file states which bundles a project
has; no table holds the toolchain invocation each target needs; no entry point
runs the sequence. Every consumer writes that layer by hand, and boring's own
`package.json` is such a hand-written layer: nine `gen:*` scripts and fifteen
`test:*` scripts, chained one by one in `verify`, with the toolchain command
repeated in each and the results path written three different ways.

This specification rules that layer. It defines one project file that names
the bundles, one recipe per target that holds what the defines cannot derive,
one driver with a fixed action set, and the three contract changes the driver
depends on (the results sink on every target, a parameterized baseline, and a
scoped mechanism-coverage check).

## The project file

A project that uses the driver writes `boring.json` at its root. It is one
JSON object.

| Field | Required | Meaning |
| --- | --- | --- |
| `outRoot` | yes | Directory every generated tree of this project lives under. |
| `resultsDir` | no | Directory the per-bundle results files are written to. Default `out/test-results`. |
| `baseline` | yes | The `id` of the bundle the comparison treats as the baseline. |
| `sourceRoots` | yes | Classpaths of the consumer's Haxe sources, passed as `-cp`. |
| `rootsFile` | no | An hxml file listing the root types to compile, passed as an include. |
| `haxeArgs` | no | Extra haxe arguments applied to every bundle. |
| `bundles` | yes | Non-empty array of bundle objects. |

A bundle object:

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique in the file. It is also the results file stem and the output directory name. |
| `target` | yes | One of `haxe`, `ts`, `kotlin`, `rust`, `swift`, `dart`. |
| `precision` | no | `f32`, or absent for binary64. |
| `haxeArgs` | no | Extra haxe arguments for this bundle, appended after the project's. |
| `build` | no | `{ "args": [...], "env": {...} }`, overriding the recipe's build step. |
| `run` | no | `{ "args": [...], "env": {...} }`, overriding the recipe's run step. |
| `package` | no | `{ "name": "...", "version": "..." }`, the spec 24 and 25 identity. Required by the `pack` action. |

A project file that carries an unknown field stops the run and names the
field. A silent ignore turns a misspelled override into a step that appears
to run without it.

## What the driver derives

- **Output directories.** One pattern for every target and every bundle:
  `<outRoot>/<id>/gen` and `<outRoot>/<id>/gen-tests`. A project file may not
  name them. Two sources for one path produce a compilation that writes to one
  directory and a build that reads another, and the failure surfaces as a
  compile of a stale tree rather than as a configuration error.
- **Generation defines.** `<target>-output` and `<target>-test-output` from
  the two directories above; `float-precision=f32` when `precision` is `f32`;
  the target's runtime defines at their documented defaults, overridable
  through `haxeArgs`.
- **Manifest and artifact defines.** From `package`: `package-name`,
  `package-version`, `package-shell=emit`. On the `pack` action only, in
  addition: `package-artifacts=emit`, and `package-tsc=<executable>` on the
  `ts` target or `package-kotlinc=<executable>` on the `kotlin` target, each
  resolved from the environment or from `PATH`.
- **The results path.** `<resultsDir>/<id>.jsonl` for every bundle.

## The recipe

One entry per target, in boring's own source, not in the project file. The
recipe holds the parts the defines cannot express: the build command, the run
command, and whether `pack` spawns a host toolchain.

| Target | Build | Run | Pack spawns |
| --- | --- | --- | --- |
| `haxe` | `haxe` over the reference entry | `bun` on the emitted js | nothing |
| `ts` | none; `bun` transpiles | `bun test <gen-tests>` | `tsc` |
| `kotlin` | `kotlinc`: library jar from `<gen>`, then a tests jar against it | `java -cp <both jars> TestMainKt` | `kotlinc` |
| `rust` | `cargo test` in the crate root | `cargo test` | nothing |
| `swift` | `swiftc`: library, then the test executable against it | the executable | nothing |
| `dart` | none | `dart <gen-tests>/main.dart` | nothing |

The recipe is data. A project changes a command by adding arguments through
`build.args` and `run.args`, and the environment through `build.env` and
`run.env`, because the flags a site needs — a compiler wrapper, a library
path, a memory bound — are not derivable from the compilation.

## The actions

    boring gen <id>...
    boring test <id>...
    boring pack <id>...
    boring compare
    boring verify [--with-pack]

- `gen` compiles each named bundle's sources through the target's generation
  defines and leaves the two directories.
- `test` runs each named bundle's `gen` output through the recipe's build and
  run steps and leaves `<resultsDir>/<id>.jsonl`.
- `pack` runs each named bundle's generation with the artifact defines, and
  requires `package` on every named bundle.
- `compare` reads `<resultsDir>/<id>.jsonl` for every bundle, passes the
  baseline's id as the baseline, and applies spec 19's comparison rules.
- `verify` is `gen` for every bundle, then `test` for every bundle, then
  `compare`, in that order, stopping at the first action that fails.
  `--with-pack` appends `pack` for every bundle.
- Exit status is 0 when every action the invocation ran succeeded. A failure
  names the bundle and the action.

## Results sink on every target

Spec 19's location rule names `haxe`, `ts`, `kotlin` and `rust` as the values
of `<target>`. The emitter today matches that list: `KotlinRuntime.hx`,
`RustRuntime.hx` and `TsRuntime.hx` read `BORING_TEST_RESULTS`, while the
`dart` and `swift` bundles print their records to standard output and rely on
the caller redirecting it. That is why boring's own `test:dart` and
`test:swift` scripts carry a shell redirection and why a driver cannot collect
results through one contract.

Under this specification every target reads `BORING_TEST_RESULTS` and falls
back to `out/test-results/<target>.jsonl`. The `dart` and `swift` emitters are
brought into that rule. The default path keeps spec 19's `<target>` value; the
driver always sets the variable, so the default is only a fallback for a
hand-run bundle.

## The baseline is a parameter

The consistency manager fixes the baseline target name to `kotlin` and accepts
the target list through `--targets`. A project whose baseline bundle is named
`kotlin-f32` therefore cannot hand its results file to the manager without
renaming it, and two bundles of one target (a `kotlin-f32` and a `kotlin-f64`)
cannot both be compared in one run.

`--baseline=<name>` joins `--dir` and `--targets`, defaulting to `kotlin`. The
driver passes the project's `baseline`.

## Mechanism coverage is scoped to the project that declares it

Spec 19's manager ends every run with the mechanism-coverage check, which
reads `tools/test-consistency/mechanism-coverage.json` relative to the working
directory and requires every listed boring mechanism to be probed by a test id
of the run. A consumer project's ids do not carry boring's probe names, so the
manager exits nonzero with zero divergences: the exit status no longer means
what spec 19 says it means.

Under this specification the check runs when the project file declares
`mechanisms`, and is skipped otherwise. Boring's own project file declares it,
so boring keeps the gate; a consumer's `compare` result is carried by the
divergence list alone.

## Acceptance

- A project file with one bundle per target drives `gen`, `test` and `compare`;
  `verify` exits 0 on a consistent project and, when one bundle's verdict is
  perturbed, exits nonzero naming that bundle and the id.
- Adding a bundle is one array entry: no file outside the project file changes,
  and the two derived directories appear under `<outRoot>/<id>/`.
- `boring pack` on a `ts` bundle writes `dist` with `.js` and `.d.ts` and the
  `.tgz`; on a `kotlin` bundle it writes the Maven directory with the jar, the
  pom and the `.sha1` files.
- Each of `dart` and `swift`, run by the driver, leaves a non-empty
  `<resultsDir>/<id>.jsonl`.
- `boring compare` exits 0 for a consistent project and reads every bundle's
  results file; a missing file is a failure that names the bundle.
- The driver runs boring's own corpus through one `boring.json`, and `verify`
  is green, so `package.json` no longer chains the per-target scripts by hand.
