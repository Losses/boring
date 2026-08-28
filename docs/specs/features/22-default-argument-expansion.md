# Feature spec 22: Default argument expansion

## Scope

This specification rules optional function parameters with default values and
the call sites that omit them. The mechanism is a completion pass in the typed
common layer, the same layer as the functional idiom expansion of
`docs/specs/macros/01-functional-idiom-expansion.md`: every call that omits
trailing defaulted parameters receives the default values as explicit
arguments, and the declarations lose their defaults, before any target
compiler runs. The three target compilers receive only full positional calls
over required parameters, so no target emits an optional parameter or a
default. The downstream motivation is the engine port audit: 462
default-parameter sites across 39 files, with omission at call sites
throughout.

Haxe holds no named call arguments, so every call in the pipeline is
positional and omission is trailing only. The pass fills omitted trailing
parameters and performs no argument reordering.

## Haxe construct

```haxe
public function glyphName(codePoint:Int, fallback:String = "?", suffix:Null<String> = null):String
```

Call sites:

```haxe
glyphName(0x4E00);
glyphName(0x4E00, "CJK");
glyphName(0x4E00, "CJK", "-x");
```

After completion the declaration carries three required parameters and every
call passes three arguments.

## Completion rules

1. A default value must be a compile-time constant from the sanctioned class:
   a literal, `null`, or an enum constructor without arguments. The check runs
   on the typed declaration after the compiler evaluates constants. Any other
   default expression is rejected with the named error
   `default argument values accept compile-time constants only`, which the
   `V16 NonConstantDefault` row of `docs/specs/style/01-haxe-style-standard.md`
   records.
2. Copying a constant into a call site introduces no evaluation, so the
   completion changes no observable behavior. This is why the sanctioned class
   stops at constants.
3. A value-optional parameter (`x:String = "?"`) keeps its declared type in
   the body; after the pass it becomes a plain required parameter. A
   nullable-optional parameter (`?suffix:String`) reads as `Null<String>` in
   the body; after the pass it becomes a required parameter of type
   `Null<String>` and every omitting call site receives `null`.
4. The pass applies to every typed declaration shape: class methods, interface
   methods, static functions, and local functions.
5. The pass runs after typing and before the pipeline expansion pass of `docs/specs/macros/01-functional-idiom-expansion.md` and
   the `V08` scan, so both later stages see only completed calls.

## Per-target products

After completion, a defaulted function is indistinguishable from a function
that never held defaults. TypeScript and Kotlin accept native default syntax;
the pass completes the calls before them, so neither target emits a default.
Rust holds no default parameter syntax; the completed call sites are the only
form. No target-specific work exists for this feature.

## Emission rulings recorded at implementation

The declaration side holds: no target emits optional syntax or default
initializers. The sample shapes introduced by this feature appear in the sample
tree for the first time, and the general emitter gaps they exposed were
filled as target-level rules:

- A local function used as a value lowers as a typed arrow function on
  TypeScript, a local `fun` expression on Kotlin, and a closure with
  snake-case parameter names on Rust.
- Enum equality against a bare constructor lowers through the runtime
  discriminant on TypeScript (`left.kind === "Name"`), because enum values
  are emitted as object literals carrying `kind`.
- Rust call sites that pass into a `Null<T>` parameter wrap non-null
  arguments in `Some(...)` (string literals gain `to_string()`), a null
  message argument renders `None`, and `Null<String>` operands in string
  concatenation render `as_deref().unwrap_or("")`. Rust references and
  TypeScript and Kotlin equality follow the same null-model rules already
  recorded for earlier features.
- Interfaces lower as traits with `impl Trait for Struct` blocks on Rust,
  `interface` declarations with `override` members and `companion object`
  routing for mixed static and instance members on Kotlin, and named
  function type aliases with `readonly` members on TypeScript, because the
  repository lint rule rejects interface methods in emitted TypeScript.
  Classes that hold only static members keep the existing `object` form on
  Kotlin; the companion routing applies to mixed classes only.
- Completion applies to every defaulted function visible to the
  compilers, including the assertion APIs declared before this feature. The `std.Test` assertion methods carry a defaulted
  `message` parameter, so every historical two-argument assertion call now
  materializes an explicit `null` third argument in the TypeScript and
  Kotlin trees; the Rust side already rendered an absent message as
  `None`, so its trees do not change. The completion is
  behavior-preserving on all four sides.

## Oracle standing

The haxe stage-1 side runs haxe's own optional-argument semantics, so the
consistency comparison rests on the haxe standard behavior on one side and the
completed positional calls on the other three targets.

## Name resolution rules

The completion pass correlates each call site with the registration entry of
its callee. The correlation keys are exact: class methods resolve through the
declaring class plus the method name, and local functions resolve through the
enclosing class, the enclosing method, and the local variable name. A bare
name serves as a fallback only when exactly one registration under that name
exists in the whole compilation; when several registrations share a name and
no exact key matches, the compiler stops with
`default argument lookup is ambiguous for <kind> <name>` and completes
nothing. Local functions with the same name in different methods therefore keep
their own default values; the sample tree pins this with two same-named
local functions holding distinct defaults.

## Test hooks

- A new sample module declares defaulted functions at several arities, covers
  the value-optional and nullable-optional forms, and calls them with zero,
  one, and two omitted trailing arguments.
- `samples/tests/` asserts the observable results; the four-side consistency
  run of `docs/specs/features/19-testing.md` compares the jsonl output.
- `tests/ts/` tree assertions pin the products: the generated trees contain
  no optional parameters, no default initializers in emitted signatures, and
  every generated call passes the full arity.
- The mutation checks for this feature live in the dispatch task file and are
  part of the completion criteria.
