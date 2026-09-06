# Feature spec 58: Interval recognition contract

## Scope

This specification defines the shared shape accepted by the five target interval
recognizers. It records the unified ruling from
`/tmp/dispatch-state/boring-soliv-r1.report.md` and supersedes target-specific
recognition differences for this rule.

## Current verification

| Mechanism | Current verification anchor | Required form |
| --- | --- | --- |
| Shared interval matcher | `packages/compiler/PolicyQueries.hx` (`matchInterval`, `intervalShort`, and `regroupLoops`) | All targets use the same recognition predicate. |
| Parenthesis predicate | `packages/compiler/ExpressionPredicates.hx` (`stripParentheses`) | Recursively removes only `TParenthesis`. |
| Target delegation | `TsExpr.hx`, `SwiftExpr.hx`, `DartExpr.hx`, `RustExpr.hx`, and `KotlinExpr.hx` interval helpers | Delegates without interval capabilities. |
| Boundary examples | `samples/boring/IntervalSurfaceOps.hx` | Covers do-while, nullable start, parentheses, and cast shapes. |

## Semantics ruling

1. **Do-while is never intervalized.** The matcher accepts only
   `TWhile(condition, body, true)`. A `TWhile(..., false)` executes its body at
   least once, while a pre-test range loop can execute zero times when the start
   is greater than or equal to the bound. This agrees with spec 53 ruling 2:
   do-while remains outside the current lowering subset.

2. **The counter must have a non-null initializer.** A declaration of the form
   `TVar(counter, start)` is accepted only when `start != null`. This agrees with
   spec 53 ruling 3: a nullable or uninitialized counter is excluded from
   intervalization unless its initialization and null behavior are modeled.

3. **Only parentheses may be stripped from the bound subject.** For
   `OpLt(left, right)`, the matcher recursively removes `TParenthesis` and then
   requires `TLocal(counter)`. `TCast` and `TMeta` are deliberately not removed.
   Thus parentheses are transparent, while casts and metadata conservatively
   reject interval recognition.

The unified shape is:

```text
counterDecl = TVar(counter, nonNullStart)
whileExpr   = TWhile(cond, body, true)
cond        = TBinop(OpLt, stripParentheses(left), right)
left        = TLocal(counter)
```

## Contract examples

| Shape | Required behavior |
| --- | --- |
| `var i = 1; do { ... } while (i < 0)` | Retain/reject as do-while; never rewrite to a zero-trip interval loop. |
| `var i:Null<Int> = null; while (i < n) { ... }` | Retain while semantics; do not construct an interval with a missing start. |
| `while (((i)) < n) { ... }` | Intervalize after recursively stripping parentheses. |
| `while (cast(i, Int) < n) { ... }` | Retain while; the cast is not assumed to be identity. |
| `while (@:meta i < n) { ... }` | Retain while until metadata lowering effects are established. |

## Non-goals

This specification does not classify identity casts or broaden recognition of
metadata-wrapped expressions. Identity-cast classification remains undetermined:
a future rule needs evidence about type relationships, runtime checks, value
ranges, and representation changes across all five targets. Metadata transparency
also remains undetermined until the compiler's expression metadata and lowering
semantics are audited. This change does not alter `intervalCore`; its potentially
nullable start capture is an observation for a separate ruling.
