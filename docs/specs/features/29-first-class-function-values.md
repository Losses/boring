# Feature spec 29: First-class function values

## Scope

This specification rules function-typed values in every storage position:
instance fields, static fields, parameters, return types, and local
bindings, together with the construction and invocation of stored values
and interface-typed fields. The ported engine source is the consumer:
the annotation cache declares constructor fields of function type
(`styleAt: (Int) -> TextStyle` with sibling fontSize and fontWeight
fields in `WidthIndependentAnnotationCache.kt`), the planning stage holds
the same shape, the punctuation ledger passes generic function
parameters, and the profile resolver is a single-method interface stored
in a field and invoked through it. A mechanical probe drove every
position through all five targets before this specification; the probe
results fix the current state below.

## Current state from the probe

The probe module declares one shape per position: a function-typed
constructor field stored and invoked, an interface-typed field invoked
through a single-method interface, a function-typed parameter, a generic
function-typed parameter, a local function value, a function value
returned from a function, and a static function-typed field with a
capture-free initializer.

| Position | TypeScript | Kotlin | Swift | Dart | Rust |
| --- | --- | --- | --- | --- | --- |
| Instance function field, stored and invoked | renders and runs | renders | renders | renders | renders a `fn` pointer field |
| Interface-typed field invoked | renders and runs | renders | renders | renders | renders a bare trait as the field type |
| Function parameter invoked | renders and runs | renders | renders | renders | renders a `fn` pointer parameter |
| Generic function parameter | renders and runs | renders | renders | renders | renders a generic `fn` pointer parameter |
| Local function value | renders and runs | renders | renders | renders | renders a closure |
| Function value returned | renders and runs | renders | renders | renders | returns a capturing closure typed as a `fn` pointer |
| Static function field with initializer | the field is dropped | the declaration renders without the initializer | the field is dropped | the field is dropped | the field renders on the instance struct without the initializer |

The probe tests make the defects observable: the TypeScript run
reports 136 passing tests and one failure, `FnValuesOps.defaultTag is
not a function`, because the call site renders while the field does
not. The Rust crate fails compilation with five errors: a trait used as
a type twice (the field and the constructor parameter), a missing
`default_tag` field in the constructor initializer, a `usize` argument
passed to a `u32` function parameter at an indirect invocation, and a
capturing closure returned where a `fn` pointer is declared. The
Kotlin, Swift, and Dart defects are the same dropped or uninitialized
static field, observable at each target's compile step.

## Judgment

| Candidate | performance | ambiguity | redundancy | readability |
| --- | --- | --- | --- | --- |
| Rust: `Box<dyn Fn>` storage for every function-typed field, parameter, and return | One allocation per closure construction and one indirect call per invocation; the engine constructs such closures per paragraph, so the cost is bounded by construction count. | One representation per position; the declared Haxe type maps to one Rust type whatever the construction site. | No per-site inference between pointer and boxed forms. | Signatures read one function type; invocation reads as a call on the value. |
| Rust: `fn` pointers where a literal is provably capture-free, boxing otherwise | Capture-free forms hold no allocation, but the struct and function signatures change with the set of construction sites. | Two representations for one Haxe type; a new capturing construction site changes an unrelated struct's layout. | The capture analysis must stay in sync with every construction form. | Readers track which positions hold pointers and which hold boxes. |
| Rust: generic `<F: Fn(...)>` parameters and fields | Monomorphization removes the indirect call and the allocation per instantiation, at one specialization per closure site. | Generics propagate into every consumer signature and struct. | One copy of each consumer per closure. | Engine consumer signatures grow type parameters that name no engine concept. |
| Static function fields: per-target static storage with the initializer | The initializer runs once per program; invocation is one call. | Each target holds one native spelling of a static function value. | No helper or lazy machinery. | The declaration reads as the target's own static. |
| Static function fields: a factory function constructing the value per call | No static storage, but every invocation allocates a closure that the program already holds once. | The value's identity changes per call; nothing observes it, so the shape misleads. | The initializer moves into a function that no source declares. | Readers see a factory where the source declares a constant. |

## Ruling

1. The products the probe verified stay: instance function-typed
   fields, parameters, return types, and local values render in the
   target's function-type spelling, construction renders as a function
   literal, and invocation of a stored value renders as a call on the
   value. The literal forms follow the target tables below. This
   section pins verified behavior; no implementation change is needed
   for these positions on TypeScript, Kotlin, Swift, and Dart.

2. Rust lowers every function-typed field, parameter, and return type
   as `Box<dyn Fn(Args) -> Ret>`, wraps each construction site in
   `Box::new`, and invokes stored values as calls on the box. The one
   representation per position removes the pointer-or-box inference of
   the second judgment candidate: a declared Haxe function type maps to
   one Rust type whatever the construction sites hold, and the engine's
   per-paragraph closures bound the allocation cost. The `usize` to
   `u32` argument adaptation of direct calls, the `buf.len() as u32`
   convention the emitted string buffer already uses, extends to
   indirect invocations through the function type's declared parameter
   types.

3. An interface used as a field, parameter, or return type on Rust
   lowers as `Box<dyn InterfaceName>` with the same `Box::new` wrapping
   at construction, following rule 2. The probe's bare trait field and
   bare trait parameter are the two compile errors this removes.

4. A static function-typed field renders as static storage carrying the
   initializer:

   | Target | Declaration |
   | --- | --- |
   | TypeScript | `public static defaultTag: (id: number) => string = <literal>;` |
   | Kotlin | the companion object holds `val defaultTag: (Int) -> String = <literal>` |
   | Swift | `static let defaultTag: (Int32) -> String = <literal>` |
   | Dart | `static final String Function(int) defaultTag = <literal>;` |
   | Rust | `static DEFAULT_TAG: fn(i32) -> String = <literal>;` |

   The Rust form holds a function pointer, so the sanctioned initializers
   of a static function field are capture-free literals; a literal that
   reads an outer variable stops the compilation with
   `static function fields accept capture-free initializers only`. The
   engine port holds no capturing static function field; when one
   appears, a planned extension rules lazy boxing for it.

5. No position allocates beyond the ruled products: the four
   non-Rust targets hold the function value as the literal itself, and
   Rust holds one box per construction and one static pointer per
   static field. Invocation adds no wrapper beyond the target's own
   call syntax.

## Samples and tests

- `samples/boring/FnValuesOps.hx` declares the probe shapes: the
  function-typed constructor field and its invocation, the
  single-method interface with an object implementor stored in a field
  and invoked through it, the function parameter, the generic function
  parameter, the local function value, the function-returning function,
  and the static function field with a capture-free initializer. One
  constructor argument is a capturing literal, so the Rust boxing of
  rule 2 is exercised by the run.
- `samples/tests/FnValuesTests.hx` asserts the observable results of
  every shape; the consistency run compares the rows across kotlin
  (baseline), haxe, ts, rust, swift, and dart.
- Both modules are entered in all eight generation hxml files.
- Tree assertions in `tests/ts/fn-values.test.ts`: the Kotlin tree
  carries the companion static with its initializer; the TypeScript,
  Swift, and Dart trees carry the static field with its initializer;
  the Rust tree carries `Box<dyn Fn` in the field, parameter, and
  return positions, `Box::new` at each construction site,
  `Box<dyn NameResolver` for the interface field, and the
  `static DEFAULT_TAG: fn` declaration; the `as u32` adaptation appears
  at the indirect invocation.
- Mutation checks: a capturing literal as a static function field
  initializer triggers
  `static function fields accept capture-free initializers only`; the
  absence of a bare trait in Rust field positions is pinned by the tree
  assertions, and no error probe exists for it.
