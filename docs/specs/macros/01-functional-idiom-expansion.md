# Macro spec 01: Functional idiom expansion

## Scope

This specification rules the recognition and expansion of a closed list of
collection pipeline idioms into the loop forms already ruled in
`docs/specs/features/09-iterators.md` and `docs/specs/stdlib/04-haxe-ds-vector.md`.
The expansion runs once, in the typed common layer before target emission,
so the three target compilers receive only loop statements they already
translate. The downstream motivation is the engine port audit: `map` 58,
`filter` 78, `forEach` 69, `associate` 19, and `sortedBy` 8 uses, all with
lambdas that never become values. `let` / `also` / `apply` (81 uses) stay
hand-rewritten into local bindings; they have no standard-library oracle on
any target, so recognition would buy no independent evidence. `groupBy`
(7 uses) is excluded because its product is a `Map<K, Array<V>>` and no
ordered multimap contract is ruled.

This spec amends `docs/specs/features/09-iterators.md` (functional iteration
ban), `docs/specs/style/01-haxe-style-standard.md` (`V02`), and
`docs/specs/features/17-sorting.md` (generated comparator path) in the same
change; those amendments are quoted in their files.

## Closed list and accepted shapes

The receiver is `Array<T>` in every case. The argument is exactly one inline
function literal (arrow or `function` expression) written at the call site,
with exactly one parameter. Point-free calls (`arr.map(namedFn)`) and
multi-parameter lambdas are rejected.

| Idiom | Accepted source | Product |
| --- | --- | --- |
| `map` | `arr.map(item -> body)` | Pre-allocated fill per `stdlib/04`: `new Array<T>(count)` with indexed stores on TypeScript, `Array(count) { index -> ... }` on Kotlin, `Vec::with_capacity` with `push` on Rust. |
| `filter` | `arr.filter(item -> pred)` | Compact loop with push: fresh `[]` on TypeScript, `ArrayList` with `add` on Kotlin, `Vec` with `push` on Rust. |
| `forEach` | `arr.forEach(item -> body)` | The `features/09` loop form of each target. Statement position only; the call has no value. |
| `associate` | `arr.associate(entry -> { key: ..., value: ... })` | Loop over the receiver plus `SortedMapBuilder` `put` and `build()` per `stdlib/07`. The lambda body must be a structure literal with exactly the fields `key` and `value`, declared through a named typedef. The key obeys the `stdlib/07` key domain gate; duplicate keys follow last-wins. |
| `sortedBy` | `arr.sortedBy(key -> expr)` | Copy of the receiver, then a stable ascending sort by the key expression. Per platform: Kotlin emits the platform stable key sort, TypeScript emits a copy plus `Array.prototype.sort` with a comparator generated from the key expression, Rust emits `sort_by_key` with the key expression inlined. The comparator never exists as a source value; the `features/17` amendment sanctions this as the one generated-comparator path. The sort is stable on every platform including the haxe stage-1 shim. |

`map` and `filter` are Haxe `Array` standard methods, so the haxe stage-1
side runs the real standard library implementations; the consistency
comparison rests on two independent implementations. `forEach`,
`associate`, and `sortedBy` do not exist on Haxe `Array`. They are declared
as static extensions in `samples/std/` (following the `SortedMap` extern
pattern), and the haxe stage-1 side runs implementations injected in the
`TestCollector` bootstrap shim. Those shim bodies are handwritten
straight-line code, the same evidence tier as the sorted-table shims; the
specification records that this tier is weaker than a standard-library
oracle.

Chains (`arr.map(...).filter(...)`) expand when the whole chain sits in a
direct position per the position rule below; the stages expand in source
order and each stage reads the previous stage's temporary.

## Recognition rules

1. The argument must be a function literal written at the call site. Any
   other argument shape is rejected with
   `collection pipeline methods accept inline function literals only`.
2. The body may reference its parameter, the names visible at the expansion
   point, and may make ordinary calls and field reads. The body must not
   declare a nested function literal and must not be recursive.
3. The call must sit in a direct position per the position rule below.
   Otherwise it is rejected with
   `collection pipeline calls expand in direct statement positions only`.
4. Everything outside the closed list keeps the `V02` rejection unchanged,
   including `Lambda` module calls, `reduce`, `flatMap`, `fold`, comparator
   `sort`, and every method not named in the table above.

The `V02` interception in `src/Intercept.hx` exempts the closed-list calls
whose argument is syntactically a function literal; the exemption is
syntactic because the check runs in the untyped pass. The typed expansion
pass runs after typing, after the default-argument completion of
`docs/specs/features/22-default-argument-expansion.md`, and before the `V08`
scan, so the loop-body closure rule sees the expanded loops and needs no
wording change. A call that
passes `V02` but fails the typed shape checks is rejected with the named
errors above; no path lowers a functional call to the targets.

## Scope hygiene

The expansion inserts its statements immediately before the enclosing
statement, in the innermost block. The expression position keeps only the
result temporary.

1. **Mint rule.** Every generated name (result temporaries and auxiliary
   bindings) is minted in the common layer and must be fresh against the
   names visible at the expansion point: enclosing function parameters and
   locals, the lambda parameter, the free names referenced inside the
   lambda body, and names minted earlier in the same block. The minting
   appends a numeric suffix until the name is fresh, and the same name
   flows to all three targets. This prevents two failure classes: a
   temporary capturing a name the lambda body references (silent semantic
   change), and two expansions in one block colliding (a hard redeclaration
   error on Kotlin).
2. **Parameter reuse.** The lambda parameter name is reused verbatim as the
   element binding. Source shadowing maps to output shadowing, and block
   scoping holds on all four sides: the TypeScript output uses `const` and
   `let` (no `var` hoisting), the Kotlin loop and body bindings are
   per-iteration, the Rust `for` binding is per-iteration, and the haxe
   stage-1 loop variable is block scoped. No renaming pass runs and no
   `TLocal` rewrite happens.
3. **No block-expression wrappers.** The expansion emits no `run {}`, no
   IIFE, and no function value the source did not contain. The one
   sanctioned exception is the `sortedBy` comparator, which is generated
   code under the `features/17` amendment. Loop bodies carry braces on
   every target, so declarations inside the loop body stay inside.
4. **Per-iteration state.** When the expansion site sits inside an outer
   loop, the inserted statements and temporaries are placed inside that
   outer loop body; each outer iteration rebuilds them.

## Position rule (evaluation order)

Hoisting moves the pipeline computation to the front of the enclosing
statement. If a sibling sub-expression that evaluates later in source order
has side effects, the reorder changes observable behavior, so the expansion
accepts only positions where no reorder is observable:

1. The direct positions are: an expression statement, the initializer of a
   `final` / `var` / `val` declaration, and the expression of a `return`
   statement.
2. A call in any other position is accepted only when every sibling
   sub-expression of the enclosing statement falls in the recognized
   side-effect-free class: literals, reads of locals, field reads, and the
   pure operators over those. Calls, writes, and allocations outside the
   pipeline itself are not in the class.
3. Rejection uses the named error of recognition rule 3.

## Test hooks

- A new sample module demonstrates every idiom, chains included, with a
  `describe`-style function per idiom for the assertion suites.
- `samples/tests/` additions cover: element order, capture of enclosing
  locals (mint-rule guard), shadowing (a lambda parameter named like an
  outer local), nested loops (per-iteration temporaries), `associate`
  duplicate-key last-wins, and `sortedBy` stability on equal keys.
- `tests/ts/` tree assertions pin the products: the generated trees contain
  the fill, push-loop, and sort forms and contain no `.map(`, `.filter(`,
  `.forEach(`, `.associate(`, or `.sortedBy(` call site; the sample source
  keeps the closed-list forms. `tests/ts/loop-structure.test.ts` narrows
  its samples scan to the methods outside the closed list and keeps the
  absolute ban over the generated trees.
- The mutation checks for this feature live in the dispatch task file
  and are part of the completion criteria.

The interception fixtures `v02` (functional-iteration, lambda-static) and
`v08` (loop-body closure) narrow from rejecting the form to rejecting the
non-literal and non-expanded forms, per the recognition rules.
