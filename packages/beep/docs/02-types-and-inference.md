# Type system and inference

## 1. Scope and Wren baseline

This document defines type identity, subtyping, inference, generics, associated types, method resolution, definite assignment, and type diagnostics. All decisions occur before bytecode generation.

Wren stores dynamic values in Value in [wren_value.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_value.h) and obtains runtime classes through [wren_vm.h](https://github.com/wren-lang/wren/blob/99d2f0b8fc2686134b32b18166e037639f7e9f2c/src/vm/wren_vm.h). Beep replaces those operations with the static rules below while retaining Wren class and method syntax.

## 2. Type universe and judgments

Primitive types: Bool, Byte, Int, Float, String, Unit, Never. Nominal types: classes, interfaces, enums, and foreign opaque types. Structural types: tuples and records. Compound types: function types, Array<T>, Map<K,V>, Option<T>, Result<T,E>, and projections T.Associated.

Record identity is the ordered mapping from field names to field types. Identical mappings have identical types. Record fields are immutable. Tuple identity is the ordered element type list. Aliases do not create identity.

There is no null, nullable type, Any, implicit boxing, uninitialized source value, or implicit default. Every local and field read is definitely initialized. Never has no values and is assignable to every expected type.

Gamma |- e:T means e has type T under environment Gamma. T <: U means T is a subtype of U. Every typed expression has one result type before bytecode generation. No inference variable remains except a quantified generic parameter.

## 3. Typing rules

1. Bool literals have type Bool. Integer literals use expected Byte/Int only when they fit; otherwise they use Int if representable.
2. A binding read uses its fixed declared or inferred type. Assignment requires mutable storage and a value subtype of its declared type; the assignment expression has the binding type.
3. Conditions and guards have type Bool.
4. An if or match expression requires a unique least common supertype of reachable branch values. Expected type may constrain branch inference. If no unique type exists, require annotation or explicit conversion.
5. Calls resolve by receiver, visibility, member kind, name, labels, and arity. There is one declaration per name/arity. The checker then validates argument types and generic bounds. Argument types never select an overload.
6. Return values are subtypes of the declared result. Every reachable non-Unit path returns.
7. Patterns are compatible with the scrutinee type. Closed types require exhaustive arms.
8. An is test is legal when declared inheritance/interface relations permit overlap. The true branch narrows to a representable intersection.

Implicit conversions are subtype upcasts, Never, and fitting integer literals. Int/Float conversion, truth conversion, Option extraction, user conversion, and Object boxing are explicit.

## 4. Constraint representation

A type variable has unique id, source origin, kind (ordinary type or projection), level, and constraints. Constraint forms:

- Equality alpha == beta.
- Subtype alpha <: beta.
- Interface bound alpha implements I<args>.
- Projection equality alpha.Assoc == beta.
- Variance use in covariant, contravariant, or invariant position.

The solver stores equalities in union-find with path compression. Each root stores a constructor or unresolved variable plus lower and upper bounds. Substitution is idempotent. An occurs check rejects T = Array<T>; recursive types are outside the language.

## 5. Constraint generation

The checker traverses typed AST nodes in source order and emits constraints without generating target code.

- Literal: concrete primitive type or expected-type fit constraint.
- Local: instantiate quantified type scheme with fresh variables.
- Binding: unify annotation/inferred binding type with initializer type.
- Assignment: value type <: declared storage type.
- Call: resolve one name/arity declaration; instantiate generic parameters; constrain each actual argument <: formal; constrain result against expected type.
- Member call: find declaration in receiver class/interface graph; filter visibility and static/instance kind first.
- If/match: fresh result variable with lower bounds from each reachable arm.
- Array: constrain each element to one T. Empty array requires expected Array<T> or explicit T.
- Map: constrain keys to K and values to V; require K: Eq + Hash.
- Generic bound: emit class/interface constraints and associated equalities.
- Projection: normalize T.Element using the unique conformance for resolved T.

## 6. Constraint solving algorithm

Use this deterministic phase order:

1. Apply explicit annotations and explicit generic arguments as equalities.
2. Unify constructors recursively. Different nominal constructors conflict. Tuple arity mismatch conflicts. Function parameter/result positions follow declared variance.
3. Normalize associated projections through the conformance index. Zero conformances is an unsatisfied bound. More than one conformance is a declaration error independent of use site.
4. Propagate subtype bounds through declared class/interface edges. Structural record subtyping uses field name/type rules and immutable fields.
5. Solve invariant variables by equality. Solve covariant variables to the least type satisfying lower and upper bounds. Solve contravariant variables to the greatest compatible type. If incomparable candidates remain, report ambiguity without declaration-order or target-specific tie-breaking.
6. Apply trailing defaults to still-unresolved variables. Recheck bounds and projections.
7. Validate every constraint after substitution. Any unresolved variable in an executable expression or public signature is a type error.

A solution is principal when every other valid solution is an instance of it. If the solver cannot prove a principal solution under these rules, it reports ambiguous inference and lists variable, bounds, and source origins. Constraint insertion order must not change results; tests permute insertion order.

## 7. Associated types

An interface declares associated types with bounds and optional defaults. A conformance binds each name once. Example:

    interface Sequence {
      type Element
      fn iterator() -> Iterator<Element>
    }
    impl Sequence for Array<T> where Element = T
    fn first<S: Sequence>(items: S) -> Option<S.Element> { ... }

For Array<Byte>, inference binds S=Array<Byte>; its Sequence conformance binds Element=Byte; result is Option<Byte>. Inference may use arguments, expected result, or explicit equality. Conflicting equalities report both origins. An underconstrained projection requires an explicit type argument or equality clause.

Projection identity includes nominal interface conformance id. Equal associated names in unrelated interfaces have distinct identity.

## 8. Generics and variance

Classes, interfaces, enums, records, functions, and methods may declare parameters. Bounds are conjunctive class/interface constraints and associated equalities. The compiler checks each generic body once under declared bounds. Calls instantiate with fresh variables and solve constraints.

Defaults apply to trailing omitted parameters, may reference earlier parameters, and are checked after substitution. Type parameters are invariant by default. out is legal only in covariant positions; in only in contravariant positions. Mutable fields/setters make a parameter invariant. Invalid variance reports declaration and offending use locations.

One concrete type/interface pair has at most one conformance. Conflicting interface defaults require a class implementation. Generic specialization must be bounded; shared generic bytecode and specialized bytecode have identical semantics.

## 9. Definite assignment and flow

Construct a CFG per function. Entry initializes receiver and parameters. Declaration initializes after initializer completion. Assignment initializes after right expression completion. At joins, intersect initialized sets. Loop exit includes zero-iteration path. Break/continue edges participate. Constructor normal exits require all fields initialized.

Statements after Never or unconditional return are unreachable diagnostics. Non-Unit functions return on every reachable exit. Match coverage uses closed constructors; guarded arms count only when guard is literal true.

## 10. Diagnostics and tests

Diagnostics include stable code, source range, expected/actual types, and related declaration/constraint locations. Generic diagnostics list unresolved variables and bounds. Projection errors name interface, associated member, and conformance. Calls report missing name/arity or argument mismatch; Beep has no same-arity overload candidates.

Required tests: subtype transitivity; constraint-order permutations; contradictory equalities; lower/upper conflicts; incomparable bounds; Array<Byte> to Sequence.Element=Byte; missing/conflicting/underconstrained projections; trailing defaults; variance violations in fields/setters/parameters/results; arity dispatch followed by type mismatch; CFG branches/loops/returns/constructors.
