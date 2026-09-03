# Statement-Position Block Scopes

## Typer expansion

Haxe expands `for` loops over literal arrays when all elements are constants and the body has no `break` or `continue`. The typer copies the body into adjacent `TBlock` segments, each beginning with a distinct loop-variable declaration. A body containing `break` or `continue` remains a counted-loop lowering. A body containing `return` is still expanded and carries the non-local return in its copied segment.

## Target emission

| Target | Statement-position `TBlock` |
| --- | --- |
| TypeScript | `{ ... }` |
| Rust | `{ ... }` |
| Dart | `{ ... }` |
| Swift | `do { ... }` |
| Kotlin | `run { ... }` |

Each block is emitted at one greater indentation depth and is separate from the target-specific rendering of function bodies, branches, and loops.

Swift uses `do {}` because a bare brace block is not a statement. Kotlin uses the inline standard-library `run {}` because a bare lambda block requires a receiver context and `run` preserves non-local returns. This statement-position rule is distinct from the functional-expansion restriction in `docs/specs/macros/01-functional-idiom-expansion.md` §3: it does not rewrite pipeline expansion as `run` or an IIFE.

## Regression boundaries

Control-structure block rendering remains owned by its existing renderers. `blockLines` continues to run `matchInterval` before individual statement emission, so counted-loop lowering retains priority over the statement-position block arm.

Fixture: `samples/tests/BlockScopeUnrollTests.hx` (`tests.BlockScopeUnrollTests`) covers literal scopes, name reuse, non-local return, and the break/continue counted-loop path.
