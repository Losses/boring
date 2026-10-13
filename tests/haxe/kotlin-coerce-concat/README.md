# Kotlin String-concatenation coercion fixture

P2.6. The concatenation binop lowers each operand through the coerce layer and
picks the operator from Lowered.storage rather than re-reading the rendered
text. Three operand shapes are pinned:

* leftSafeChain -- nullable receiver read through a safe call: the left
  operand renders as a safe-call chain, so the concatenation uses ?.plus
  (a null receiver propagates null).
* rightNullable -- plain non-null left plus a nullable right: the plain +
  spelling stays, because String.plus(Any?) renders a null argument as "null".
* bothNullable  -- safe-call left plus a nullable right: the left safe chain
  wins, so ?.plus is used again.

The two spellings are semantically different for a null operand (? vs
"null"), so run.sh asserts the exact operator in each position.

## Check

tests/haxe/kotlin-coerce-concat/run.sh generates the fixture and greps the
exact emitted expressions in the generated Kotlin.

kotlin.hxml names packages/compiler on the class path directly instead of
depending on -lib boring, so the fixture always measures the tree it lives in
(PIT-376).
