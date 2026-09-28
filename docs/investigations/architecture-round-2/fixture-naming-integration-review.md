# Fixture naming integration review

The coordinator checked the renamed fixture entry points on Boring revision
`268a9262`. These focused runs test path wiring after the terminology commit.
They retain their existing semantic limits; a runner's zero exit records its
own procedure outcome.

| Fixture | Observed outcome | Retained attempt |
| --- | --- | --- |
| Classifier | Probe and compile exit zero | `out/classifier/run-20260928-182808-HZBVFR` |
| Local presence | 167 observed rows match 167 authored rows | Direct Haxe output; no attempt directory |
| TypeScript source origin | Final runner exit zero; output bytes and negative occurrence control checked | `out/ts-source-origin/attempt-eqWyaax1` |
| Enum comparison | Runner exit zero; five findings remain recorded for Rust and TypeScript | `out/enum-comparison/runs/enum-comparison-d0iJH7` |
| Place | Runner exit zero with explicitly retained Rust compile failures and dependent stages that were not reached | `out/place/runs/place-XmOVg3` |
| View lifetime | Oracle, Swift generation, compilation, execution, and comparison succeed | `out/view-lifetime/runs/view-4RnyR4ZP` |
| Flow replay | 110 agreements, two declared target observations, zero unexpected failures | `out/flow/replay-1790633272107-2059670` |

The TypeScript source-origin runner's direct Nix-shell entry stopped at
`tsc: command not found` with status 127. The same runner exited zero when
the installed workspace TypeScript executable was added to PATH:

~~~sh
nix develop -c sh -c 'PATH="$PWD/node_modules/.bin:$PATH" bash tests/haxe/ts-source-origin/run.sh'
~~~

The runner should select or require that executable explicitly and record
its identity. Its current direct entry message omits this environment
precondition. The rerun establishes the fixture's behavior with TypeScript
5.9.3; it does not repair the entry command.

The enum and place attempts retain actual target failures as findings or
stages that were not reached. Their zero runner statuses do not establish
target-language conformance. These focused runs also do not replace the
fixed Boring and Tiqian candidate matrix.
