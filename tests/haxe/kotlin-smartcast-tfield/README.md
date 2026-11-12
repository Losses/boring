# Kotlin TField smart-cast receiver stability fixture

PIT-388. Kotlin smart-casts a read `recv.field` only when **both** conditions
hold: the field renders as a `val`, and the receiver chain's root local is a
value Kotlin treats as stable. The flow proof an emitter derives from the
guard `recv.field != null` supplies neither condition on its own. An emitter
that answered the question from the guard alone therefore emitted a plain dot
and let kotlinc reject the tree.

## Shapes

`casee.CaseEOps` holds five functions. The field is `final` in
`casee.Holder` and a Kotlin `var` in `casee.MutableHolder`, so the two
conditions can be tested separately.

| Function | Conditions | Expected |
| --- | --- | --- |
| `betweenWrite` | final field, root local rebound between guard and use | negative control |
| `closureWrite` | final field, root local written from a capturing closure | negative control |
| `varField` | Kotlin `var` property, stable root | negative control |
| `stableFinal` | final field, never-reassigned root | over-reach control |
| `writeBeforeGuard` | final field, root written only *before* the guard | over-reach control |

The three negative controls are the shapes kotlinc rejects. The two over-reach
controls are shapes Kotlin's own data flow still proves: the plain dot must stay
there, because hardening them would replace the error with an
`unnecessary non-null assertion (!!)` warning, and acceptance counts warnings.

## Check

`bun test tests/kotlin/smartcast-tfield.test.ts` (collected by the
`collected-suite` job as part of `bun test tests/`). The driver generates the
fixture with the tree's own emitter, compiles every generated Kotlin file with
`kotlinc`, and asserts zero errors **and** zero warnings -- the warning half is
what holds the over-reach controls. It records the Haxe and kotlinc identity,
the generated-file hashes, and the argv/cwd/status/both-streams of each
subprocess under its scratch directory.

The mutation negative control then writes the pre-fix predicate's output back
into a copy of the generated tree -- the bare dot in place of the hardened
access -- and asserts kotlinc rejects that copy with the smart-cast errors.
Without it the driver would only show that the current output compiles; with it
the driver shows the kotlinc gate detects the exact regression it guards.

`kotlin.hxml` names `packages/compiler` on the class path directly, with no
`-lib boring` dependency, so the fixture always measures the tree it lives in,
independent of the workspace haxelib projection (PIT-376).
