# Feature spec 30: Static fields and static assignment

## Scope

This specification rules static fields in every declared form: `static var`
with an initializer, `static final` with an initializer, reads from the
declaring class and from other classes, assignment from the declaring class
and from other classes, and mutation of a static container through its
methods. The ported engine source is the consumer: the trace infrastructure
holds `public static var recorder:Null<TestTraceRecorder> = null` assigned
from the recorder constructor and read through a lookup function, a
`private static final classes:Array<TraceClassState> = []` built by `push`,
and six `static final` scalar and string constants read on every golden
write. A mechanical probe drove every form through all five targets before
this specification; the probe results fix the current state below.

## Current state from the probe

The probe module declares one shape per form: a nullable `static var`
initialized to `null`, a `static final` array initialized to `[]` and
mutated through `push`, and a `static final` scalar initialized to a
literal. Reads, container mutation, and the two assignment forms from the
declaring class and from another class cover the access positions.

| Form | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| `static var x:Null<String> = null` | the declaration is dropped; reads render | the declaration renders with an empty initializer on a `const val` | the declaration is dropped; reads render | the declaration is dropped; the static-only class flattens to functions | the declaration renders with an empty initializer on a `const` |
| Assignment, own class or other class | generation error | generation error | generation error | generation error | generation error |
| `static final` array `= []` with `push` | the declaration is dropped; the call renders | empty initializer on a `const val` | the declaration is dropped; the call renders | the declaration is dropped; the call renders | empty initializer on a `const` |
| `static final` scalar literal | the declaration is dropped | renders correctly as `const val limit: Int = 4096` | the declaration is dropped | the declaration is dropped | renders correctly as `pub const limit: u32 = 4096` |

Every assignment attempt stops generation with
`assignment target has no {target} lowering: TField(..., FStatic(boring.StaticStateOps, current))`
on all five targets. The declaration defects split in two: TypeScript,
Swift, and Dart emit code that compiles while naming a member no
declaration introduced, and Kotlin and Rust emit declarations whose
initializers are empty, which the target parser rejects. The six static
string constants in `samples/tests/EnumQueriesProbes.hx` share the
dropped-declaration defect; no generated call site names them, so the
defect went unobserved before the probe.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust: module-scope `Mutex` statics for mutable and container statics | One lock acquisition per access; the port's mutable statics are trace infrastructure touched once per test class, so the cost is bounded by the test count. | One representation per static; a declared Haxe static maps to one Rust item whatever the access position. | No unsafe blocks enter the generated tree, and stored values are not copied per access beyond the existing move adaptation. | Access positions read a lock guard around the value. |
| Rust: `static mut` with unsafe access blocks | No lock on access; every read and write needs an `unsafe` block, and the generated tree would carry its first unsafe code. | Same single representation. | The unsafe discipline spreads to every accessor the emitter writes. | Readers weigh safety at each access position. |
| Rust: `thread_local!` storage | No lock on access; a per-thread cell allocates lazily per thread. | State becomes per thread while the other four targets hold one instance, so the targets disagree under a threaded test runner. | One cell per thread the program runs. | Access reads a closure-scoped borrow. |
| Swift: `static var` for container statics | Identical access cost. | One spelling for every static field the class declares. | No second binding form to track per container. | The binding reads as mutable while the source declares it final. |
| Swift: `static let` for container statics | Identical access cost. | The binding matches the source declaration. | A second binding form for containers. | Swift arrays hold value semantics, so `append` on a `let` binding fails the Swift compile; the form rejects the mutation the port performs. |
| Dart: flatten static-only classes to top-level variables | Identical access cost. | Matches the flattening the target already applies to static functions. | No empty class remains in the output for the reader to open. | Static state reads as the module-scope state it compiles to. |

## Ruling

1. Every static field declaration renders on every target with its
   declared initializer:

   | Target | `static var`, mutable binding | `static final`, immutable binding |
   | --- | --- | --- |
   | TypeScript | `public static current: string \| null = null;` | `public static readonly limit: number = 4096;` |
   | Kotlin | `var current: String? = null` in the object or companion object | scalar and string literals keep `const val`; arrays and other reference values use `val` with the initializer |
   | Swift | `static var current: String? = nil` | scalars and strings use `static let`; arrays use `static var` per rule 4 |
   | Dart | `static String? current = null;`, or a top-level variable when the declaring class flattens | `static final`, or top-level `final` under flattening |
   | Rust | the module-scope `Mutex` static of rule 3 | scalar and string literals keep the associated `pub const`; arrays use the module-scope `Mutex` static of rule 3 |

   The array initializers follow the target's existing array construction:
   `[]`, `mutableListOf()`, `[]`, `<String>[]`, and `Vec::new()`. Source
   `private` maps to each target's private spelling; Dart's flattening
   renames to the leading underscore as the function flattening already
   does.

2. Sanctioned initializers are `null`, Bool, Int, and Float literals,
   String literals, and the empty array `[]`. Any other initializer stops
   generation with
   `static field initializers accept null, literal, and empty array forms only`.
   Every static in the port's trace infrastructure sits inside the
   sanctioned set.

3. Rust lowers a mutable or container static as a static at module scope
   named after the field, holding `Mutex<NativeType>` with `Option` inside
   for a nullable declaration, initialized by `Mutex::new` over the
   sanctioned initializer translated to its Rust value. Each class owns one
   module, so the field name is unique at module scope, and cross-class
   access qualifies through the module path. A read renders the
   lock-protected access `current.lock().unwrap_or_else(|e| e.into_inner())`, borrowing or cloning
   the value per the emitter's existing move adaptation; an assignment
   renders `*current.lock().unwrap_or_else(|e| e.into_inner()) = Some(value);` for a nullable
   declaration and `*current.lock().unwrap_or_else(|e| e.into_inner()) = value;` otherwise; a
   container mutation renders through the same guard, for example
   `classes.lock().unwrap_or_else(|e| e.into_inner()).push(...)`. The item carries
   `#[allow(non_upper_case_globals)]` so the field-name spelling matches
   the const form the target already emits.
   The lock recovery follows the Rust paradigm ruling:
   `unwrap_or_else(|e| e.into_inner())` returns the guarded value when
   the mutex reports poisoning, and the emission contains no `unwrap`
   call.

4. Swift holds a `static final` array as `static var`. Swift arrays carry
   value semantics, so a `static let` binding rejects `append` at the Swift
   compile step, and the source binding is immutable while the object it
   names is mutable. The named deviation: Swift container statics lower as
   `static var`, and the binding immutability of the source declaration is
   not expressible for a value-semantics container.

5. Assignment to a static field lowers on every target. TypeScript renders
   `StaticStateOps.current = value;`, Kotlin renders
   `StaticStateOps.current = value`, Swift renders
   `StaticStateOps.current = value`, and Dart renders
   `StaticStateOps.current = value;` or the bare top-level form
   `current = value;` when the declaring class flattened, matching how
   flattened calls already render. Rust renders rule 3's guarded form. The
   `assignment target has no {target} lowering` error for `FStatic`
   targets disappears.

6. Scalar and string `static final` constants keep the forms that already
   render on Kotlin and Rust and gain their declarations on TypeScript,
   Swift, and Dart through rule 1's table. Reads of constants stay direct
   references on all five targets; no lock or wrapper applies to the const
   form.

## Samples and tests

- `samples/boring/StaticStateOps.hx` graduates with both assignment forms
  restored: `StaticStateClient.install` assigns
  `StaticStateOps.current = value;` from another class, `setCurrent`
  assigns `current = value;` inside the declaring class, the array carries
  `push` mutation, and a scalar and a string constant cover the const form.
  The read functions expose observable results for every form.
- `samples/tests/StaticStateTests.hx` asserts the assignment round trip
  through both forms, the container growth through `record`,
  `sectionCount`, and `firstSection`, and both constants.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/static-state.test.ts`: the TypeScript tree
  carries `static current: string | null = null` and `static readonly`;
  the Kotlin tree carries `var current: String? = null` and the `val`
  container with `mutableListOf`; the Swift tree carries
  `static var current: String? = nil` and `static var sections`; the Dart
  tree carries the flattened variable declarations with the underscore
  rename; the Rust tree carries `Mutex<Option<String>>`, `Mutex::new`,
  `lock().unwrap_or_else(|e| e.into_inner())` at the read and assignment positions, and `Some(` at
  the nullable assignment.
- Mutation checks: a static initializer outside the sanctioned set, for
  example `static var seed:Int = computeBase();`, stops generation with
  `static field initializers accept null, literal, and empty array forms only`.
