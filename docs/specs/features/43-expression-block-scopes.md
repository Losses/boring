# Expression-Position Block Scopes

## Accepted subset

An expression-position `TBlock` is accepted consistently by all five targets. Every statement before the final statement must be a declaration (`TVar`), with or without an initializer. The final statement must be a value expression. Empty blocks, declarations in the tail position, and tails which are assignments, `return`, `break`, `continue`, `throw`, `if`, `while`, `for`, nested blocks, `switch`, or `try` are rejected. These diagnostics include `features/43`.

The restriction deliberately excludes non-local control flow and other statement forms. Such control flow cannot be represented consistently when an expression-position block is embedded in an operand or initializer, so the common subset is narrowed to declarations followed by a value.

## Target emission

| Target | Expression-position `TBlock` |
| --- | --- |
| Kotlin | `run { decls; value }` |
| TypeScript | `(() => { decls; return value; })()` |
| Rust | `{ decls; value }` (with the emitter's existing operand-parenthesizing convention) |
| Dart | `(() { decls; return value; })()` |
| Swift | `({ () -> T in decls; return value })()` where `T` is the block type, adapted to SwiftExpr's existing closure conventions |

Declarations use the target's ordinary statement lowering. The tail is rendered as an expression; TypeScript, Dart, and Swift emit it as `return` inside their IIFE or closure.

## Boundary with statement blocks

The existing statement-position `TBlock` arms and their priority remain unchanged. This feature adds only an expression-position arm before the expression fallback. Blocks wrapped in `TParenthesis`, `TCast`, or `TMeta` reach the new arm through the existing unwrapping behavior.

The expression-position rule is distinct from `docs/specs/features/41-statement-block-scopes.md`: feature 41 continues to own statement blocks, including their existing non-local control-flow behavior and target-specific forms. No existing statement lowering is changed.

## Rejection rationale

Non-local control flow crossing an expression-position block has no uniform representable shape across the five targets. Restricting the block to declarations plus a value gives every target a scoped expression form without changing control-flow semantics.
