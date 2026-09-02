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
throughout. The same audit additionally holds 50 default sites whose
values are not compile-time constants: 42 empty-container defaults and 8
floating-point infinity defaults. Haxe rejects every non-constant default
value at typing, so this specification rules a second sanctioned form,
the coalescing default, that expresses such values within Haxe's
constant-only grammar. A planned extension below widens the sanctioned
expression class of the coalescing default.

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

A value that Haxe cannot write as a constant takes the coalescing default
form: a nullable-optional parameter with no declared constant, normalized by
exactly one null-coalescing site.

```haxe
public function new(?fontFamilies:Array<String>, ?fontSize:Float) {
    this.fontFamilies = fontFamilies == null ? [] : fontFamilies;
    this.fontSize = fontSize == null ? 16.0 : fontSize;
}
```

Call sites omit the parameter exactly as they omit a constant default, and the
omission resolves to the coalescing expression.

## Completion rules

1. A default belongs to one of two sanctioned classes.
   - **Constant default.** A compile-time constant after the compiler
     evaluates constants: a literal, `null`, or an enum constructor without
     arguments. Any other expression in default position is rejected with the
     named error `default argument values accept compile-time constants only`,
     which the `V16 NonConstantDefault` row of
     `docs/specs/style/01-haxe-style-standard.md` records.
   - **Coalescing default.** A nullable-optional parameter (`?p:T`)
     normalized by exactly one coalescing site: the assignment
     `this.p = p == null ? E : p` for a constructor field parameter, or the
     local binding `var v = p == null ? E : p` for a function parameter.
2. The default expression `E` of a coalescing site accepts: primitive-type
   literals; the empty array construction `[]`; the empty map construction
   `new Map()`; `Math.POSITIVE_INFINITY`; `Math.NEGATIVE_INFINITY`; and
   argument-less enum constructors. The class is closed so recognition and
   rejection stay mechanical and every entry evaluates purely at each call.
   Any other expression is rejected with
   `coalesced default expression is not sanctioned`. A parameter consumed by
   more than one expression, or read anywhere outside its single coalescing
   site, is rejected with `coalesced default parameter is consumed more than
   once`.
3. Copying a constant into a call site introduces no evaluation, so completing
   a constant default changes no observable behavior. A coalescing default
   evaluates `E` at every call that omits the parameter and at no other call;
   each target lowering preserves this per-call evaluation, and two omitting
   calls receive distinct container instances. The per-call freshness is an
   observable the consistency run pins.
4. A value-optional parameter (`x:String = "?"`) keeps its declared type in
   the body; after the pass it becomes a plain required parameter. A
   nullable-optional parameter holding a constant default (`?suffix:String`
   completed to `null`) reads as `Null<String>` in the body; after the pass it
   becomes a required parameter of type `Null<String>` and every omitting call
   site receives `null`. A coalescing default parameter keeps its omission
   through the pass on every code target except Rust, per the per-target
   products below.
5. The pass applies to every typed declaration shape: class methods, interface
   methods, static functions, and local functions.
6. The pass runs after typing and before the pipeline expansion pass of `docs/specs/macros/01-functional-idiom-expansion.md` and
   the `V08` scan, so both later stages see only completed calls.

## Per-target products

The two sanctioned classes lower differently.

- **Constant defaults** complete at every omitting call site before any target
  compiler runs. After completion, a constant-defaulted function is
  indistinguishable from a function that never held defaults; no target emits
  an optional parameter or a default initializer for them. This is unchanged
  from the previous ruling of this specification.
- **Coalescing defaults** survive omission into the targets that can lower
  the expression as a native default, complete to `None` on Rust, and lower
  the site itself on Dart:
  - Kotlin, TypeScript, Swift: the parameter lowers with the native default
    `p: T = E` and the coalescing site is dropped. A constructor field
    parameter stays the primary field of
    `docs/specs/features/27-class-members-and-records.md`, so record equality
    and copy keep the field; the declaration is indistinguishable from a
    hand-written defaulted field.
  - Dart: default parameters accept compile-time constants only, and a const
    collection is immutable and canonicalized, so a native container default
    cannot preserve the per-call freshness of rule 3. Every coalescing
    default on Dart lowers the coalescing site itself: the parameter stays
    nullable and the site renders as body normalization,
    `this.p = p ?? E;` with `E` in expression position, which evaluates `E`
    at each omitting call and yields a fresh mutable container.
  - Rust: Rust holds no default parameter syntax. The parameter lowers as the
    `Option<T>` of the existing `Null<T>` convention, omitting call sites
    complete to `None` through the pass, and the coalescing site lowers at the
    function entry as `let p = p.unwrap_or_else(|| E);`, whose closure
    evaluates `E` only in the `None` arm.
  - Haxe stage 1: the coalescing site is the semantics itself; the oracle
    needs no adaptation.

## Extension Stage A: coalescing defaults that read parameters

Status: implemented this round. Stage A covers the parameter-reading grammar
below; static-field reads are deferred to Stage B.

The rules below amend rule 2 and the per-target products for the coalescing
default. The engine port sources
hold coalescing sites whose default expression reads earlier parameters or
static fields of the compilation: a constructor parameter defaulting to an
earlier parameter (`displayText = text`), a field of an earlier parameter
(`adjustedClusters.size`), a method call on an earlier parameter
(`text.substring(range.start, range.end)`), a static call over an earlier
parameter (`PunctuationGluePlacement.forRegion(region)`), a conditional over
an earlier parameter (the locale normalization of `RubySpan`), and static
field reads (`Ic.Zero`, `DefaultCoalesceRepeatablePunctuation`). Rule 2 as
implemented rejects every such expression with `coalesced default
expression is not sanctioned`.

### Extension grammar

The sanctioned class of rule 2 grows from closed constants to a closed
recursive grammar over two roots: the existing closed value leaves of
rule 2 and a reference to a parameter of the same function declared strictly
before the defaulted parameter. Over these
roots the grammar accepts field access chains over parameter references,
instance method calls whose receiver and arguments are grammar
expressions, static calls whose arguments are grammar expressions,
conditionals whose condition and both arms are grammar expressions, and
binary operators over grammar expressions. Every other node rejects as
today with `coalesced default expression is not sanctioned`, except a
reference to the defaulted parameter itself, which keeps the existing
`coalesced default parameter is consumed more than once`, and a reference
to a later parameter, which rejects with the new named error `coalesced
default expression may reference earlier parameters only`.

### Evaluation ordering

A default expression that reads an earlier parameter reads its normalized
value, the value after that parameter's own constant completion or
coalescing site. The coalescing sites of one function emit in parameter
order, so a later site observes the earlier site's result and never the
raw nullable binding of an earlier coalesced parameter. A read of an
earlier parameter inside the default expression of a later parameter is a
sanctioned use; the consumed-more-than-once rejection keeps governing the
defaulted parameter of each site alone, and a read located inside the
default expression of another registered site of the same function does
not count toward that rejection. Kotlin and TypeScript native
defaults provide the same ordering from the language semantics of default
expressions. The dependence is observable: two omitting calls whose
earlier arguments differ resolve their defaulted parameter differently,
and the consistency run pins this. When every parameter of such a chain
is omitted at one call, the later parameter resolves through the earlier
parameter's own default; the consistency run pins this corner too.

On Haxe stage 1 the body reads the raw nullable binding of the earlier
parameter, so the registration pass rewrites each read of an earlier
coalesced parameter inside a later site's default expression into the
inline normalization `p == null ? E : p`, with `E` a copy of the earlier
site's default expression. The rewrite touches only the
default-expression subtrees inside the sites, leaves the registered
values unchanged, and therefore changes no generated target output.

### Per-target deltas

- Kotlin, TypeScript: the native default `p: T = E` carries the
  expression. Both languages let a default expression read earlier
  parameters, and the Kotlin regeneration reproduces the ported engine
  source unchanged.
- Swift: a default argument expression cannot reference other parameters
  of the same function. When `E` reads a parameter through the grammar,
  the parameter lowers as body normalization: `p: T? = nil` in the
  signature and `p = p ?? E;` at the entry, with constructor field
  parameters keeping the feature 27 primary field and the entry
  assignment writing the field. When `E` reads static fields and closed
  constants only, the native default stays, because those expressions are
  valid Swift default arguments.
- Dart: the site stays the body normalization `p ?? E;` from the base
  ruling. When `E` reads an earlier parameter that itself holds a
  coalescing default, the parameter binding in the body is still the raw
  nullable one, so the read renders as `(q ?? Eq)`, the earlier
  parameter's name wrapped in its own default; the wrap applies
  recursively when the earlier default reads a coalesced parameter in
  turn.
- Rust: unchanged. The entry binding `let p = p.unwrap_or_else(|| E);`
  holds; the closure reads earlier parameters, which the
  parameter-ordered entries have already unwrapped.
- Haxe stage 1: the site is the semantics itself. A site whose default
  reads an earlier coalesced parameter additionally receives the inline
  normalization rewrite of the Evaluation ordering section, because plain
  Haxe execution would otherwise read the raw nullable binding.

### Extension test hooks

- A new sample section covers each grammar root over one shape drawn from
  the engine port: the bare earlier-parameter read, the field access, the
  method call, the static call with a parameter argument, the conditional
  over a parameter, and the static-field read.
- A dependence assertion calls the same function twice with the same
  omission and different earlier arguments and observes different
  resolved values.
- A chain sample holds two coalescing parameters whose later default
  reads the earlier one, and call helpers omit both arguments, omit only
  the later argument, and pass both; the observable values pin the
  both-omitted corner, where the later parameter resolves through the
  earlier parameter's default. A constructor sample holds the same chain
  over two field parameters of one class.
- Tree assertions: the TypeScript and Kotlin trees carry the native
  default with the expression; the Swift tree carries the
  body-normalization form for parameter-reading expressions and the
  native default for static-field-only expressions; the Rust tree
  carries the entry closure reading the earlier unwrapped parameter; the
  Dart tree of the chain sample carries the `(q ?? Eq)` wrap at the read
  of the earlier coalescing parameter.
- Mutation checks: rewriting an expression to read a later parameter
  triggers `coalesced default expression may reference earlier parameters
  only`; inserting an unrecognized node keeps `coalesced default
  expression is not sanctioned`.

## Extension Stage B: static-field roots

Status: implemented. This stage adds static-field reads, the Swift delta
that retains a native default for static-field-only expressions, and the
`staticFieldSample` sample and tree assertions. It depended on features/30
emitting static field declarations for every target, which features/30 and
its construction-initializer extension (spec 35) now provide.

## Emission rulings recorded at implementation

The declaration side holds for constant defaults: no target emits optional
syntax or default initializers. Coalescing defaults emit their native default
on the targets that hold the syntax, per the per-target products above. The
sample shapes introduced by this feature appear in the sample
tree for the first time, and the general emitter gaps they exposed were
filled as rules for each target:

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
- A Dart instance field that a constructor initializes through a
  coalescing body site declares `late` (`late final` on final fields).
  Dart's definite-assignment analysis credits field formals and
  initializer-list entries only, so a body assignment is the one shape
  that needs the modifier; direct assignments still lower through the
  initializer list and their fields stay unmodified.

## Oracle standing

The haxe stage-1 side runs haxe's own optional-argument semantics, so the
consistency comparison rests on the haxe standard behavior on one side and the
completed positional calls on the other targets. Coalescing defaults run the
haxe coalescing site on the stage-1 side and the native defaults on the code
targets; the comparison covers their observable results, including the
per-call freshness of container defaults.

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
- The same module covers the coalescing default at both shapes: a constructor
  field parameter defaulting to `[]`, a function parameter defaulting to
  `Math.POSITIVE_INFINITY`, and a map-valued parameter defaulting to
  `new Map()`, each with omission sites.
- Coalescing samples assert per-call freshness: two omitting calls return
  distinct container instances, pinned by mutating one result and observing
  the other unchanged.
- `tests/ts/` tree assertions extend to the coalescing products: the
  TypeScript tree carries the native default syntax on these parameters and
  no materialized argument at their omission sites; the constant-default
  assertions of no optional parameters and full-arity calls still hold for
  constant-defaulted functions.
- `samples/tests/` asserts the observable results; the four-side consistency
  run of `docs/specs/features/19-testing.md` compares the jsonl output.
- `tests/ts/` tree assertions pin the products: the generated trees contain
  no optional parameters, no default initializers in emitted signatures, and
  every generated call passes the full arity.
- The mutation checks for this feature live in the dispatch task file and are
  part of the completion criteria.

## Extension Stage C: normalization bindings and constructor defaults

Status: implemented 2026-09-01.

Two shapes from the engine port sources stay rejected by rule 2 as
implemented:

1. A statement-level coalescing over a parameter that holds no default at
   all: `var f = fs == null ? em : fs;`. The engine sources hold 56 elvis
   statement bindings; the port inlines each expression into a call
   argument to fit the argument-position grammar (314 inline
   `== null ?` sites in the current port tree).
2. A default expression that constructs a class: the engine source declares
   a constructor default `AdjustmentStylePolicy()` (Kotlin
   `ClreqProfile.kt`), and the port forces every call site to pass the
   arguments explicitly (`ClreqProfile.hx:90`, `:103`, `:116`).

### Grammar additions

- Rule 2's recursive grammar grows one leaf: a constructor invocation
  `new C(a1 ... an)` over a class `C` visible at the site, whose arguments
  are rule-2 grammar expressions. The Stage-A parameter-reference rules
  govern the arguments unchanged.
- One new sanctioned position: the normalization binding
  `var v = p == null ? E : p;` where `p` is a nullable-typed parameter of
  the enclosing function and `E` is a rule-2 grammar expression, the
  constructor leaf included. The parameter holds no default registration
  and may be read elsewhere in the body; the binding is recognized by its
  shape, and `E` obeys the closed grammar. Every other statement-level
  coalescing expression keeps the named rejection
  `coalesced default expression is not sanctioned`.

### Evaluation and per-target deltas

- A normalization binding evaluates `E` exactly when `p` is null. A
  constructor leaf in default position evaluates at every omitting call;
  two omitting calls receive distinct instances, and the consistency run
  pins this freshness.
- Kotlin, TypeScript: a normalization binding renders through the native
  null-coalescing operator (`val f = fs ?: em`; `const f = fs ?? em`). A
  constructor leaf in default position lowers as the native default
  `p: T = C(...)`; both languages evaluate default expressions at each
  omitting call.
- Swift: a constructor leaf in default position takes the Stage-A body
  normalization (`p: T? = nil` with `p = p ?? C(...)` at entry). A
  normalization binding renders `let v = p ?? E`.
- Dart: body normalization for both shapes, per the base ruling
  (`p ?? E` with `E` in expression position).
- Rust: a normalization binding lowers as the existing conditional
  lowering over `Null<T>`; a constructor leaf lowers inside the
  `unwrap_or_else` closure of the base ruling.
- Haxe stage 1: the source ternary is the semantics. The registration pass
  performs no rewrite for a normalization binding, because `p` is read
  elsewhere in the body by design.

The `V16 NonConstantDefault` row of the style standard updates in the same
commit: the sanctioned classes grow by the constructor leaf and the
normalization-binding position, and the rejection keeps governing every
other coalescing shape.

### Test hooks

- Samples: a normalization binding over a required nullable parameter that
  the body also reads elsewhere; a constructor default omitted at two
  calls with a distinct-instance assertion; a chain holding both shapes.
- Tree assertions: the Kotlin and TypeScript native operator and default
  forms; the Swift body normalization for the constructor default; the
  Dart `??` sites; the Rust conditional and closure forms.
- Mutation: a normalization binding whose `E` falls outside the grammar
  keeps the named rejection; a later-parameter reference inside `E` keeps
  `coalesced default expression may reference earlier parameters only`.
