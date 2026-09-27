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

This specification defines the package's contract.
The package exposes a `boring` command on `PATH`. It defines one project file
that names target configurations, one recipe per target that holds what the
defines cannot derive, one driver with a fixed action set, and the three contract changes the driver
depends on (the results sink on every target, a parameterized baseline, and a
scoped mechanism-coverage check).

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
| `sourceSet` | no | Name of one entry in `sourceSets`; its roots are added to the roots HXML when both are present. |
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

A source set has the form `{ "packages": ["app.core"], "types":
["app.Main"], "discover": [{ "root": "src", "packages": ["app.tests"],
"suffix": "Test" }] }`. Each package is passed through
`haxe.macro.Compiler.include` with recursion disabled and strict package
checking. Each type is passed as a Haxe module root. A discovery rule scans
only the named package directories directly beneath its project-relative
`root`, selects `.hx` modules whose names end in `suffix`, and passes the
resulting roots in sorted order. The directory must exist and contain at
least one matching module. Empty names,
invalid Haxe paths, duplicate entries, unknown source-set references, and
parent or absolute discovery paths are errors. `rootsFile` remains accepted;
its roots and the source set's roots are combined.

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
- **The results path.** `<resultsDir>/<id>.jsonl` for each testable configuration.

## The recipe

One entry per target, written in boring's own source; the project file
does not hold it. The
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

## The actions

    boring gen <id>...
    boring test <id>...
    boring pack <id>...
    boring compare
    boring verify [--with-pack]

- `gen` compiles each named configuration's sources through the target's generation
  defines and leaves the two directories. It then runs `afterGen`, if set;
  a failed command fails `gen`.
- `test` runs each named testable configuration's `gen` output through the
  recipe's build and run steps and leaves `<resultsDir>/<id>.jsonl`. An explicit
  request for a configuration with `test: false` fails and names its id.
- `pack` runs each named configuration's generation with the artifact defines,
  runs `afterGen` if set, and requires `package` on every named configuration.
- `compare` reads `<resultsDir>/<id>.jsonl` for each comparison-enabled configuration, passes the
  baseline's id as the baseline, and applies spec 19's comparison rules.
- `verify` is `gen` for every configuration, then `test` for testable
  configurations, then `compare`, in that order, stopping at the first action
  that fails. `--with-pack` appends `pack` for configurations with `package`.
- The `baseline` id must name a testable, comparison-enabled configuration.
  `compare: true` requires `test: true`. A configuration with `compare: false`
  still runs `gen` and `test` but is excluded from `compare`.
  Boring's four f32 configurations currently use this setting because their
  test applicability and ID sets differ from the binary64 baseline. Their
  results remain available for separate review until those tests converge.
- Exit status is 0 when every action the invocation ran succeeded. A failure
  names the configuration and the action.
- `boring roots <sourceSet> --project <file> --output <path>` writes the
  same package macros and module roots as an HXML include. It replaces the
  output through a sibling temporary file and rename. Projects with direct
  HXML entry points can generate one roots include from `boring.json`.

## Results sink on every target

Spec 19's location rule names `haxe`, `ts`, `kotlin` and `rust` as the values
of `<target>`. The emitter today matches that list: `KotlinRuntime.hx`,
`RustRuntime.hx` and `TsRuntime.hx` read `BORING_TEST_RESULTS`, while the
`dart` and `swift` configurations print their records to standard output and rely on
the caller redirecting it. That is why boring's own `test:dart` and
`test:swift` scripts carry a shell redirection and why a driver cannot collect
results through one contract.

Under this specification every target reads `BORING_TEST_RESULTS` and falls
back to `out/test-results/<target>.jsonl`. The `dart` and `swift` emitters are
brought into that rule. The default path keeps spec 19's `<target>` value; the
driver always sets the variable, so the default is only a fallback for a
  hand-run target configuration.

## The baseline is a parameter

The consistency manager fixes the baseline target name to `kotlin` and accepts
the target list through `--targets`. A project whose baseline configuration is named
`kotlin-f32` therefore cannot hand its results file to the manager without
renaming it, and two configurations of one target (a `kotlin-f32` and a `kotlin-f64`)
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
- Adding a configuration is one array entry: no file outside the project file changes,
  and the two derived directories appear under `<outRoot>/<id>/`.
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
