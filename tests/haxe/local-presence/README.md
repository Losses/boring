# Local presence fixture

Focused compile-time observation of `SourceLocalPresenceAnalysis`. The
fixtures observe source facts only: they assert no target storage, extraction,
promotion, or declaration decision, and they change no compiler file outside
the assigned batch.

## Check

`run.hxml` compiles `lpc.Main` and invokes `lpc.Checker.run` as the compile's
own macro-time step, so the check's streams and exit status are the compiler
process's own. Run from the repository root, with the output path supplied per
attempt:

```
nix develop -c haxe tests/haxe/local-presence/run.hxml \
  > out/local-presence/<run>/check-stdout.txt \
  2> out/local-presence/<run>/check-stderr.txt
```

The exit status carries the verdict. A nonzero status is a failed check.

`lpc.Cases` holds one authored static function per case. A call to its `use`
marker marks a read the checker records; the marker's argument is the observed
expression. The checker prepares every case through the production analysis,
walks the prepared body in traversal order, and records four row kinds:

| Kind | Observable |
| --- | --- |
| `use` | The facts of one marker argument. |
| `guardSubject` | The facts of the subject read of one null comparison. |
| `bodyExit` | The body's reachable exits, in a fixed order. |
| `ambiguousCount` | Physical nodes the walk met on several paths. |

A function literal is its own prepared body, so rows inside one carry a `#n`
case suffix and come from that body's facts.

`lpc.Checker` holds the expectation table. Every expectation was written from
the source rules, independently of the analyzer's answers. The comparison
checks that every expectation has exactly one row, that every row has an
expectation, and that every matched pair agrees. A coverage defect is a
failure, so an unobserved case cannot pass silently.

## Cases

The cases name the fixture's independent requirements: a guard in a branch
that can be skipped, guards inside loop bodies before and after a repeated
use, a comparison inside call arguments, an assignment after a guard, joins of
arms that write different values, a writing right operand of a short-circuit
condition, a left operand whose value decides the branch, a call that may run
a closure which assigns a captured binding, a nullable field behind a present
root, a protected region whose writes the handler cannot assume, a return that
removes one path from a join, nested bodies over mutable and immutable
captures, one producer rule per recognized case, an explicit null through
a non-null annotation, an arm that throws, a test that cannot hold, a
post-tested loop, a nested assignment to null, indexed reads, calls in
conditions, a Boolean value whose two reachable outcomes disagree about one
binding on either operator, a protected body that only returns, the identity
boundary of one physical node at three positions, and a plain and a compound
assignment whose right side may run a captured writer.

## Limits

- The check observes one stage: the analysis over a typed body. It runs no
  Boring generation, no target compiler, and no runtime, and a result here
  establishes only that stage.
- The analyzer answers facts on paths whose dereference the source does not
  define. No case asserts a runtime outcome.
- The consumer boundary in the Kotlin target is unchanged by this batch, so
  no generated output is compared here.
- Nine mutations of the analysis were run against the table; eight were
  detected: a short-circuit right operand evaluated although its controlling
  exit is unreachable, construction presence stated for a plain property read,
  a Boolean value carrying only its false outcome, a no-normal continuation
  still yielding an available value, a catch arm joined as a normal path when
  the protected body cannot throw, an ambiguity marker revived by a third visit
  to one physical node, an or-value carrying only its true outcome, and an
  assignment destination written into the lvalue environment, discarding the
  right side's environment. The rule refusing a one-sided fact at a reachable
  join is not distinguishable by this fixture, because lexical scope removal
  removes the only one-sided entries the current cases can build.
- A marker call clears captured bindings by rule, so a read that follows a
  marker call observes the call's effects and cannot discriminate an earlier
  transfer. The assignment cases therefore observe their captured local through
  a compared read that sits directly after the assignment, before any marker
  call.
- A throw edge carries no thrown type, and no source rule in this batch states
  thrown-type and catch matching. A protected body's throw exits are therefore
  kept unchanged: an unknown call's escape stays possible, and a definitely
  matching explicit throw is still reported as a reachable throw exit.
- No legal source expression puts a throw or a return inside an array or object
  literal, because the element type must unify, so the abrupt-literal case is
  a typed shape built by the checker itself. It observes the assembly rule
  directly and is not authored source.
