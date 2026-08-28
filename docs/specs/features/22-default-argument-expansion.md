# Feature spec 22: Default argument expansion

## Scope

This specification rules optional function parameters with default values and
the call sites that omit them. The mechanism is a completion pass in the typed
common layer, the same layer as the functional idiom expansion of
`docs/specs/features/21-functional-idiom-expansion.md`: every call that omits
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
5. The pass runs after typing and before the `features/21` expansion pass and
   the `V08` scan, so both later stages see only completed calls.

## Per-target products

After completion, a defaulted function is indistinguishable from a function
that never held defaults. TypeScript and Kotlin accept native default syntax;
the pass completes the calls before them, so neither target emits a default.
Rust holds no default parameter syntax; the completed call sites are the only
form. No target-specific work exists for this feature.

## Oracle standing

The haxe stage-1 side runs haxe's own optional-argument semantics, so the
consistency comparison rests on the haxe standard behavior on one side and the
completed positional calls on the other three targets.

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
