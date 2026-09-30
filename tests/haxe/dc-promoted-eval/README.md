# dc-promoted-eval — runtime single-evaluation probe for the promoted switch shape

Runtime counterpart of `tests/haxe/dc-enum-switch-gen` (board task
`t-mum05sop-cbtu`, review `dc-warn/out/enum-switch-xcheck/REVIEW.md` §3).
That fixture established, structurally, that a **statement-position** enum
switch over a non-local subject generates on all five targets with the subject
read once into the synthetic local `_g` — and that it never compiled or ran
anything, so "single evaluation" was a reading of generated text rather than a
measurement. This fixture closes that gap for the four targets whose toolchains
run in the pinned devShell.

**Observation only.** Nothing here edits the compiler.

## The probe

`dcpe.EvalProbe` switches over a side-effecting non-local call in statement
position:

```haxe
public static function promotedOnce():Int {
    var acc:Int = 0;
    switch (nextKind()) {          // statement position → typer promotes the subject
        case Kind.A:      acc = 1;
        case Kind.B(value): acc = value;
        case Kind.C:      acc = 3;
    }
    return acc;
}
```

`nextKind()` increments the static counter `callCount` on every execution and
always returns the same construct `Kind.B(21)`.

* `Kind.B(21)` being constant is deliberate: a subject whose value depended on
  the call ordinal would let a duplicate evaluation change control flow, mixing
  a value mismatch into the counter assertion.
* `callCount` is the observable. A target that renders the scrutinee expression
  in more than one place leaves it at 2 or more after one call, whatever the
  returned value is.

## Assertion

Each target driver resets the counter, calls the probe exactly once, and prints
one line:

```
case=promoted acc=21 callCount=1
```

The runner compares the printed line with that authored expectation. It never
derives the verdict from the exit code, and it reads `callCount` out of the raw
stdout.

## Controls

The assertion is only meaningful if it can see the doubled value, so the run
carries two independent negative controls:

1. **source control** — `dcpe.DoubleEvalControl` writes the same side-effecting
   subject at two source positions, so it must print
   `case=double acc=42 callCount=2`.
2. **generated-tree mutation control** — the runner copies each generated tree,
   inserts exactly one extra evaluation of the subject expression immediately
   after the promoted local's initializer (the hazard is duplicate rendering of
   a single scrutinee), and re-compiles and re-runs. The mutated program must
   print `case=promoted acc=21 callCount=2`. The runner proves the mutation took
   hold by counting the subject call before (1) and after (2) and by comparing
   the file digests; a mutation that does not take hold is a harness defect, not
   a pass.

The same count-before (exactly 1) is also the generated-text evidence that the
unmutated tree renders the subject expression once.

## Structural probe

`probe.hxml` runs `dcpe.SubjectProbe` after `Intercept.run`, over the typed AST
the emitters receive. It prints, per method, how often the class's own
`nextKind()` occurs (`METHOD-PROBE ... calls=N`) and, per statement-position
switch, the preceding statement, the subject shape and the number of subject
calls inside the promoted local's initializer (`BLOCK-PROBE ... initCalls=N`).
Expected: `EvalProbe.promotedOnce calls=1` with one promoted block, `initCalls=1`,
subject `TMeta(:exhaustive)(TEnumIndex(TLocal))`; `DoubleEvalControl.doubleOnce
calls=2` with two such blocks.

## Running

From the worktree root, inside the pinned devShell:

```
XDG_CACHE_HOME=/tmp/promoted-eval-nix-cache \
  nix develop -c bash tests/haxe/dc-promoted-eval/run.sh
```

One invocation allocates one fresh run directory under
`dc-warn/out/promoted-eval/` and never rewrites another one. Every stage records
its NUL-separated argv, its working directory, separate stdout and stderr, and a
numeric exit status; the authored input trees are digested before and after, and
any difference is a harness defect.

`tsc` is not on the devShell `PATH`; the runner uses the repository's own pinned
TypeScript dependency (`package.json`: `typescript ^5.9.0`, resolved 5.9.3) and
records its resolved path and digest.

## Environment notes

* dc-warn is a `fuse.rclone` mount without an execute bit, so the runner cannot
  execute a binary built under the evidence directory (exit 126). The Rust link
  products are therefore built in a temporary directory on an executable
  filesystem and copied into the run directory for retention.
* The pinned `swiftc` wrapper needs user namespaces and fails immediately with
  `bwrap: setting up uid map: Permission denied`, so Swift is recorded as
  environment-not-reached rather than measured.
* The emitted Kotlin tree does not compile as a whole: `runtime/test/Test.kt`
  references `boring.runtime.FPHelper`, which the tree does not carry. The
  library build excludes `runtime/test` and the whole-tree failure is recorded
  as its own observation.
