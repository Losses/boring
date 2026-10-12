# kotlin-smartcast-drop

Ablation fixture for the smart-cast clause table in
`KotlinExpr.smartCastableSubject` (GP-ABLATE, WBS §0.3).

`smartCastableSubject` is a conjunction of six clauses. Each is gated by
`-D kotlin_smartcast_drop=<clause>`, so dropping one re-emits the unhardened
spelling and kotlinc surfaces the exact error the clause prevents. The driver
`tests/kotlin/smartcast-drop.test.ts` asserts both directions of each clause
with error-text fragments, and writes `rc-table.md` into the scratch output.

| clause        | direction | expected rc | error fragment (drop)                                  |
|---------------|-----------|-------------|---------------------------------------------------------|
| val           | both      | 0 / !=0     | "mutable property that could be mutated concurrently"    |
| closurewrite  | both      | 0 / !=0     | "mutated in a capturing closure"                         |
| rebind        | both      | 0 / !=0     | "only safe (?.) ... calls are allowed on a nullable receiver" |
| open          | vacuous   | 0 / 0       | --                                                       |
| getter        | vacuous   | 0 / 0       | --                                                       |

`sameunit` is deferred: its negative direction needs two-stage cross-module
compilation (Tests jar, then Main jar on `-cp`), which is a separate
follow-up.
