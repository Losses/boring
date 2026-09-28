# Source container fact fixtures

Focused evidence for `SourceContainerAnalysis` and the three container
queries it feeds. The fixtures observe source classification only; they
assert no target storage, presence, permission, or compatibility decision,
and they change no compiler file outside the assigned batch.

## Source fact check

`run.hxml` compiles `scp.Main`, whose expectation table is authored
independently of the analyzer. The macro `SourceObserver.observeCases` reads
the compiler-typed types of the declared cases in declaration order, before
any other probe follows them, and records the answers of the three legacy
adapters next to the analyzer's typed result. It never exits the compiler.

Run from the repository root, with the output path supplied per attempt:

```
nix develop -c haxe tests/haxe/source-container-policy/run.hxml \
  -js out/source-container-policy/<run>/check.js
nix develop -c bun out/source-container-policy/<run>/check.js
```

Cases: direct and aliased arrays, a generic alias with substituted
arguments, twelve and eighty hop alias chains, outer and element `Null`, foreign
declarations sharing the built-in names, scalars, and labelled synthetic
handles (lazy resolution, a failing lazy, a non-progressing lazy, a pending
and a forced monomorph, and a null input).

## Caller generation and native evidence

`gen/run.sh` allocates one fresh run directory and copies the compiler inputs
into frozen candidate and baseline trees. The baseline is copied from the
candidate, then restores `StaticFieldHelper.hx` from the base revision and
removes `SourceContainerAnalysis.hx`. Both trees and every fixture/runner
input are hashed before and after the attempt. Usage:

```
nix develop -c bash tests/haxe/source-container-policy/gen/run.sh
```

Per command it records argv, cwd, separated streams, and numeric status.
Verbose Haxe paths verify that generation uses the frozen compiler copies,
and the baseline-to-candidate diff must contain only the two declared
analyzer files. Generated trees are digested so a native result traces to its
artifact. A failed
baseline preparation is a harness defect and every later stage is recorded
as not reached through it. A generation failure is an observation: the
native stage that depends on the missing tree is recorded as not reached,
never as a semantic difference.

The generated entry is `scp.CallerCases` (direct written forms). Alias
spellings live in `scp.CallerAliasBoundary` and are generated separately on
both frozen compiler trees. The runner accepts a boundary observation only
when the candidate reports that target's unsupported-lowering diagnostic.
The baseline expectation is its actual `V01 IteratorLoop` source rejection;
this is recorded as an earlier source-phase failure and gives no evidence
about baseline target lowering. A different source-typing failure satisfies
neither expectation.

## Native stages

Every target gets four native stages per run: compile and run for the
candidate tree and for the baseline tree, each with its own streams and
status. Native scripts hash their authored harness and generated inputs
before compiling. A successful run is compared against
`native/expected/CallerCases.txt`. Its `sumReadOnlyDirect=0` value follows
from `CallerCases.run` passing the empty `directTable` to that function; this
does not establish iteration over a nonempty read-only array.

## Limits

- The source probe runs during macro expansion with `SourceCases` already
  available as a typed class. It is not a measurement taken by the global
  `Context.onAfterTyping` callback.
- A compiler-created monomorph is observed while pending and again after
  unification with `Array<Int>`. The two rows check distinct resolution states.
- Swift and Dart native compiles of the small generated trees fail because
  the emitted runtime faces are incomplete for this fixture's generation
  set (`TiqianArray` has no declaration; `std.Console` has no Dart body).
  Both failures are recorded with their exact commands and streams; they are
  identical on the baseline and candidate sides and are not repaired here.
