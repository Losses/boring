# Classifier contract fixture

Focused compile-time observation of how the source typer and the shared
classification helpers see the container declarations in `contract/`. It is
an observation harness: it changes no compiler decision and renders no
target text.

## Run

    nix develop -c bash tests/haxe/classifier-contract/run.sh

Each invocation allocates a fresh evidence directory
`out/classifier-contract/run-<stamp>-<suffix>/` with `mktemp` and never
reuses or overwrites an existing directory. The retained files are:

- `environment.txt`: toolchain identity (haxe version, haxelib list, git
  head, git status) and the sha256 of the fixture sources and the compiler
  helper sources the probe calls. The hashes identify the actual candidate
  that produced the run.
- `probe-stdout.txt` / `probe-stderr.txt` / `probe-status.txt`: the macro
  probe's separate streams and exit status.
- `compile-stdout.txt` / `compile-stderr.txt` / `compile-status.txt`: the
  ordinary compile's separate streams and exit status.
- `helper-exceptions.txt`: the probe's internal helper exceptions
  (`raised:` records), separated from process/setup status.
- `run-command.txt`: the exact commands, cwd, and sizes.

## Stages observed

Two stages run separately and are recorded separately:

1. **Source typing observation** (the macro probe,
   `classifier-contract.hxml`): the probe runs as a compile-time macro that
   reads the typer's forms from the `contract` declarations through
   `haxe.macro.Context` and calls the shared helpers at their real entry
   points. This is source typing: it establishes how the typer and the
   helpers see the declarations. It does not run Boring generation, a
   target compiler, or a target runtime, and a result here establishes only
   that stage.
2. **Source acceptance** (the ordinary compile,
   `classifier-contract-compile.hxml`): a plain Haxe compile of
   `contract.CompileEntry`, which references the fixture declarations so the
   full typer covers them. It has no macro and no `Sys.exit`, so a type
   error in the fixture makes this command fail.

## Case matrix

The probe records one case per observed form and checks the visited labels
against an independently enumerated expected set, so a missing or
duplicated case is detectable (a failing label check exits nonzero):

- 10 declared static fields of `contract.Fixtures` (plain array, read-only,
  nullable forms, element-nullable, std alias, user-package abstract,
  user-package typedef, empty literal).
- 8 declared instance fields of `contract.Fixtures` (the same forms).
- 2 typed expressions (an alias-annotated and a plain-annotated array
  literal).
- 2 synthetic macro inputs (macro-constructed `Null<ReadOnlyArray<Int>>` and
  `ReadOnlyArray<Null<Int>>`). These forms are built in the macro; the
  typer does not produce them from source. Where a helper rejects a
  synthetic form, the exception is retained as a `raised:` record in the
  case and in `helper-exceptions.txt`; the synthetic form is never labelled
  a compiler-produced container.
- 3 lazy forms: the two constructor types the typer retains as lazy and one
  macro-constructed lazy. The constructed lazy is synthetic; the retained
  lazy forms are source typing.
- 32 comparator rows: `ComparatorPlan.entries` over the 8 instance fields
  under the 4 outer/inner strictness combinations (the real shared caller).

## What this fixture cannot prove

- It does not establish Boring generation, target compilation, or target
  runtime behavior; no target tree is emitted and no target binary runs.
- The `follow` line is one `Context.follow` reading of the raw form. A
  helper verdict and a follow line that disagree show the two paths read
  different facts; the fixture records both without deciding which is
  correct. Defect status for any observed disagreement is unestablished
  without the governing source/caller contract.
- The expected label set is maintained by hand from the fixture source.
  Adding or removing a fixture declaration requires updating
  `EXPECTED_CASE_LABELS` / `INSTANCE_FIELD_NAMES` in `ClassifierProbe.hx`;
  a stale expectation fails the label check.
- The evidence is one pinned toolchain reading (haxe 4.3.7 in the flake
  environment); it is not a cross-version statement.
