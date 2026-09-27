# Feature spec 59: Project driver

## Scope

Two groups of functionality use one compilation. The in-source test runner
(spec 19) compiles the consumer's tests into each target's own test
arrangement; the distribution artifact (specs 24 and 25) writes the manifest
and the install artifact of the tree the compilation emitted. Both are
selected by defines on the same `haxe` invocation, and both are already
implemented by the compiler.

The layer above them lives in the delivered `packages/driver` package. Before
it, consumers had to state their target configurations and toolchain commands
in separate scripts, including boring's own `package.json`. The driver now
reads that information from one project file and runs the sequence.

The package exposes a `boring` command on `PATH`. Its project file names target
configurations, and its recipes provide the build and run commands that Haxe
defines cannot determine. The driver also supplies a common results path,
selects the baseline for comparison, and applies mechanism coverage when the
project provides the coverage file.

## The project file

A project that uses the driver writes `boring.json` at its root. It is one
JSON object. Each entry in `bundles` specifies a translation target plus
optional precision and action settings. This specification calls that entry a
target configuration; the JSON field retains its existing name for compatibility.

| Field | Required | Meaning |
| --- | --- | --- |
| `outRoot` | yes | Directory every generated tree of this project lives under. |
| `resultsDir` | no | Directory the per-configuration results files are written to. Default `out/test-results`. |
| `baseline` | yes | The `id` of a configuration that participates in comparison. |
| `sourceRoots` | yes | Classpaths of the consumer's Haxe sources, passed as `-cp`. |
| `sourceSets` | no | Named source selections. Each value may contain `packages`, `types`, and `discover`; at least one must select a source. |
| `rootsFile` | no | An hxml file listing the root types to compile, passed as an include. |
| `haxeArgs` | no | Extra haxe arguments applied to every configuration. |
| `bundles` | yes | Non-empty array of target configuration objects. The field name remains for compatibility. |

A target configuration object:

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique in the file. It is also the results file stem and the output directory name. |
| `target` | yes | One of `haxe`, `ts`, `kotlin`, `rust`, `swift`, `dart`. |
| `sourceSet` | no | Name of one entry in `sourceSets`; its roots are added to the Haxe invocation when a roots HXML is also present. |
| `precision` | no | `f32`, or absent for binary64. |
| `haxeArgs` | no | Extra haxe arguments for this configuration, appended after the project's. |
| `test` | no | `false` for a generation-only configuration; defaults to `true`. |
| `compare` | no | `false` to test a configuration without comparing its results to the baseline; defaults to the value of `test`. |
| `afterGen` | no | `{ "command": "...", "args": [...], "env": {...} }`, a command run from the project root after generation, including generation performed by `pack`; `command` is required. |
| `build` | no | `{ "args": [...], "env": {...} }`, overriding the recipe's build step. |
| `run` | no | `{ "args": [...], "env": {...} }`, overriding the recipe's run step. |
| `package` | no | `{ "name": "...", "version": "...", "license": "..." }`, the spec 24 and 25 identity. `name` and `version` are required for `pack`; `license` is optional and must be a nonempty string when present. |

A project file that carries an unknown field stops the run and names the
field. A silent ignore turns a misspelled override into a step that appears
to run without it.

A source set selects Haxe modules in three ways. `packages` passes each named
package to `haxe.macro.Compiler.include` with recursion disabled. `types`
passes named modules directly. A `discover` rule scans the direct `.hx` files
under `<root>/<package path>`, selects filenames ending in `suffix`, and sorts
the module names before passing them to Haxe. For example:

    "sourceSets": {
      "tests": {
        "types": ["app.Main"],
        "discover": [{ "root": "src", "packages": ["app.tests"], "suffix": "Test" }]
      }
    }

The example selects `app.Main` and matching modules under
`src/app/tests/`. Each discovery directory must exist and contain a matching
module. The parser rejects invalid module paths, duplicate entries, unknown
source-set names, and discovery roots that are absolute or contain `..`.
For a configuration, the driver first includes its `rootsFile`, or the
project-level `rootsFile` when there is no override. It then adds the selected
source set's package macros and module roots. A configuration can use either
mechanism alone or both together. Boring's own `boring.json` currently uses
`rootsFile` and does not declare `sourceSets`.

## What the driver derives

- **Output directories.** One pattern for every translated target
  configuration: `<outRoot>/<id>/gen` and `<outRoot>/<id>/gen-tests`. A
  project file may not name them. The stock Haxe target is an exception:
  its roots HXML owns the `-js` output path and any generated test paths.
  Changing a Haxe configuration's `id` or `outRoot` requires updating that
  HXML as well.
- **Generation defines.** `<target>-output` and `<target>-test-output` from
  the two directories above for translated targets; `float-precision=f32` when `precision` is `f32`;
  the target's runtime defines at their documented defaults, overridable
  through `haxeArgs`.
- **Manifest and artifact defines.** On `pack`, the driver passes
  `package-name` and `package-version` from `package`, plus
  `package-license` when `package.license` is present. It also passes
  `package-shell=emit`, `package-artifacts=emit`, and `package-tsc=<executable>` on the
  `ts` target or `package-kotlinc=<executable>` on the `kotlin` target, each
  resolved from the environment or from `PATH`. It does not infer a
  consumer's license from boring's own repository license. A roots HXML
  that sets `package-license` should agree with `package.license` to avoid
  contradictory metadata in direct generation and driver packaging.
- **The results path.** `<resultsDir>/<id>.jsonl` for each configuration with
  `test: true`; `compare` reads only configurations with `compare: true`.

## The recipe

One entry per target, written in boring's own source; the project file
does not hold it. The
recipe holds the parts the defines cannot express: the build command, the run
command, and whether `pack` spawns a host toolchain.

| Target | Build | Run | Pack spawns |
| --- | --- | --- | --- |
| `haxe` | `haxe` compiles generated test sources to JavaScript | `bun` runs the emitted JavaScript | nothing |
| `ts` | none; `bun` transpiles | `bun test <gen-tests>` | `tsc` |
| `kotlin` | `kotlinc`: library jar from `<gen>`, then a tests jar against it | `java -cp <both jars> TestMainKt` | `kotlinc` |
| `rust` | `cargo test` in the crate root | `cargo test` | nothing |
| `swift` | `swiftc`: library, then the test executable against it | the executable | nothing |
| `dart` | none | `dart <gen-tests>/main.dart` | nothing |

The recipe is data. A project changes a command by adding arguments through
`build.args` and `run.args`, and the environment through `build.env` and
`run.env`, because the flags a site needs (a compiler wrapper, a library
path, a memory bound) are not derivable from the compilation.

## Package boundary and platform consistency

`packages/driver` is a consumer-facing package. The `boring` executable and
the code that reads project files, selects configurations, derives paths,
plans commands, and reports errors belong to that package. `tools/` remains
for commands used to develop this repository. A consumer invokes the
packaged command without compiling a driver from source.

The package's portable logic must compile for each supported target. Given
the same `boring.json`, command and working directory, each target must select
the same configurations, derive the same output and results paths, and produce
the same planned commands and diagnostics. Host process execution needs
platform-specific adapters; integration tests exercise the delivered command
on Linux and macOS. A test that checks only process exit status does not
establish agreement of the planned commands or results. The current command
uses a JavaScript host adapter in the Nix-delivered executable. Independent
entrypoints under `packages/driver/` also compile the command to TypeScript,
Kotlin, Rust, Swift, and Dart. Cross-target probes compare configuration,
complete command plans, diagnostics, and comparison rules; a CLI fixture runs
`compare` and `verify --with-pack` through every translated entrypoint with
the same inputs. Real toolchain execution on each translated entrypoint
remains to be verified beyond that fixture.

## Commands and their results

    boring gen <id>...
    boring test <id>...
    boring pack <id>...
    boring compare
    boring verify [--with-pack]
    boring roots <sourceSet> --output <file>

`gen` takes one or more configuration ids. It runs Haxe with the selected
roots and target defines, writing translated code to
`<outRoot>/<id>/gen` and generated tests to `<outRoot>/<id>/gen-tests`.
For `target: haxe`, the roots HXML selects the JavaScript output. If the
configuration has `afterGen`, `gen` runs that command from the project root
after Haxe succeeds. A failed `afterGen` fails `gen`.

`test` takes one or more ids whose `test` field is true. It uses code from a
prior `gen`, runs the target's build and test commands, and writes
`<resultsDir>/<id>.jsonl`. It removes an old result before running. An
explicit `test` request for `test: false` fails with the id named.

`compare` reads existing result files for configurations with `compare: true`
and checks their test IDs, outcomes, and failure messages against `baseline`
using spec 19's rules. The baseline must have `test: true` and
`compare: true`; a configuration cannot set `compare: true` with
`test: false`. A missing result file fails comparison. Boring's four f32
configurations currently use `compare: false` because their test IDs and
applicability differ from the binary64 baseline. Their tests still run.

`verify` runs `gen` for every configuration, then `test` for those with
`test: true`, then `compare`. It stops at the first failure. With
`--with-pack`, it also runs `pack` for configurations that declare `package`
after comparison succeeds.

`pack` takes one or more ids with `package.name` and `package.version`. It
reruns generation with packaging defines and runs `afterGen` when configured.
An explicit request for a configuration without `package` fails before any
generation starts. The compiler writes the target's distribution artifacts.

`roots` takes one source-set name and `--output <file>`. It writes that set's
package macros and module roots as an HXML include, replacing the requested
file through a sibling temporary file. It does not add a configuration's
`rootsFile` or run Haxe. The command is for direct HXML entry points that
need the same source selection as `boring.json`.

Paths in the project file and `--output` resolve from the directory containing
`boring.json`. The CLI defaults to `./boring.json` and also accepts
`--project <file>` or `--project=<file>`. Successful commands exit 0;
generation, execution, comparison, and configuration errors exit nonzero.

## Results sink on every target

The generated test runners read `BORING_TEST_RESULTS` to select the JSON Lines
file they write. The driver sets it to `<resultsDir>/<id>.jsonl` for each
`test` invocation. A runner started outside the driver uses
`out/test-results/<target>.jsonl` when the variable is unset. A configuration
with `test: false` does not produce a test results file.

## The baseline is a parameter

The `baseline` field names a configuration that has both tests and comparison
enabled. The driver compares the results files by configuration id, so a
project can include two precision settings for one translation target without
renaming their files. The standalone consistency manager also accepts
`--baseline=<name>` alongside `--dir` and `--targets`; its default is `kotlin`.

## Mechanism coverage is scoped to the project that declares it

The comparison code searches the results directory and its parent directories
for `tools/test-consistency/mechanism-coverage.json`. It runs the coverage
check when it finds that file and skips the check otherwise. Boring's results
directory sits inside the boring repository and finds its coverage file. A
consumer's results directory outside that repository is judged by the
divergence list alone.

## Acceptance

- A project file with one testable configuration per target drives `gen`, `test`
  and `compare`; `verify` exits 0 on a consistent project and, when one
  configuration's verdict is perturbed, exits nonzero naming that id.
- A configuration using a shared `sourceSet` can be added through one array
  entry. A configuration with a distinct `rootsFile` also needs that HXML.
  Translated targets write derived directories under `<outRoot>/<id>/`.
- `boring pack` on a `ts` configuration writes `dist` with `.js` and `.d.ts` and the
  `.tgz`; on a `kotlin` configuration it writes the Maven directory with the jar, the
  pom and the `.sha1` files.
- Each of `dart` and `swift`, run by the driver, leaves a non-empty
  `<resultsDir>/<id>.jsonl`.
- `boring compare` exits 0 for a consistent project and reads every comparison-enabled
  configuration's results file; a missing file is a failure that names its id.
- A configuration with `test: false` participates in `gen` and is excluded
  from `test` and `compare`; explicit `test` rejects it.
- A configuration with `compare: false` participates in `gen` and `test` but
  is excluded from `compare`; the baseline cannot use this setting.
- A generation-only configuration with `afterGen` produces its declared
  artifact during `gen`; `verify` runs that step without creating a test result.
- The portable driver logic compiles to every supported target and produces
  identical command plans and diagnostics for the same project input. Linux
  and macOS integration tests invoke the delivered `boring` executable.
- The driver runs boring's own sample set through one `boring.json`, and `verify`
  is green, so `package.json` no longer chains the per-target scripts by hand.
