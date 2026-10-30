# Target Semantic Policy

Status: **v1.0.0**

| Role | Party |
| --- | --- |
| Author / owner | Executor-B |
| Sign-off / version | TL (captain); the draft is not normative until the TL promotes it to v1.0.0 |
| Architecture arbitration | Astra (lingsuan gpt-6-astra, open-ended consultation) |

## Purpose

This document is the single cross-target semantic contract for Haxe reference
and handle semantics. It converges every prior ruling (Rc/RefCell handle,
receiver ABI, interface traits without Send+Sync, @:sharedHandle,
SingleThread/OnceLock static state, parameter/return/field/closure passing, and
the forbidden patterns) into one authoritative policy, so that no backend,
renderer template, fixture, or patch record re-decides the same question by
syntax position or by a compiler error message.

The executable encoding of this policy is
`packages/compiler/SemanticPolicy.hx`. The typed IR it defines
(ReprType, UseMode, ExprInfo, ReceiverAbi, ParamMode) is the policy's runnable
form; the validator (landed in the follow-up IR task) is its enforcement; and
`Rc<RefCell<T>>`, `SingleThread<T>`, and all other concrete Rust types are
only the Rust target's *realization* of the policy, never the policy itself.

## Layering

| Layer | Owns | Where |
| --- | --- | --- |
| Policy (this document) | The cross-target semantic rules | `docs/specs/target-semantic-policy.md` |
| Typed IR contract | The executable encoding of the rules | `packages/compiler/SemanticPolicy.hx` |
| Validator | Enforcement of the rules (M2) | follow-up IR task, cites entry ids P-n |
| Target realization | The concrete representation per target | Rust mapped here; TS/Kotlin/Swift/Dart left as TODO interfaces |
| Renderer | Prints only already-resolved modes | follow-up IR task; consumes the typed IR |

A target realization must not be mistaken for a cross-target rule. `Rc<RefCell<T>>`
is how the Rust target realizes "plain-class handle", not a global policy that
the other four targets must copy.

## Final boundary

This policy describes Haxe's single-threaded identity and aliasing semantics.
Rust must not smuggle Arc/Mutex in to prepare for a possible future threaded
host. In the single-thread Rust realization:

- `Rc<RefCell<T>>` = plain class
- `Rc<RefCell<dyn Trait>>` = interface / shared interface
- `Rc<RefCell<dyn FnMut(..) -> R>>` = function value

All three express single-thread aliasing plus interior mutability. Arc and Mutex
belong only to an explicitly declared threaded realization, never to this v1
policy. A future threaded host is a separate threaded target policy; v1 does not
implicitly promise it.

## Typed IR vocabulary

Defined in `packages/compiler/SemanticPolicy.hx`; one-to-one with the entries
below.

- `ReprType` — the representation category of a Haxe type:
  `Copy`, `ImmutableValue`, `Handle(class_id, nullability, shared)`,
  `Collection(element)`, `Nullable(inner)`,
  `Function(args, result, mutability, captures)`, `Static(inner)`.
- `UseMode` — how a value/handle is used at one occurrence:
  `Owned`, `SharedRef`, `HandleClone`, `ReadBorrow`, `WriteBorrow`,
  `Move`, plus the function primitives `FunctionHandleClone` and `Call`.
- `ExprInfo` — `{ repr, identity, place_kind }`; `identity` is one of
  `SelfHandle`, `LocalHandle`, `FieldHandle`, `FreshObject`,
  `BorrowedProjection`; `place_kind` is one of `Value`, `Local`,
  `Field`, `Index`, `Static`.
- `ReceiverAbi` — `None` (static) or `SharedHandle` (instance:
  `&Rc<RefCell<Self>>` in Rust).
- `ParamMode` — `Owned`, `SharedRef`, `MutableRef`, `HandleClone`.
- `FunctionMutability` — `FnMut` (canonical) or `Fn` (proven immutable).

### UseMode naming consolidation

The earlier ruling named six modes MoveOwned, CloneHandle, BorrowShared,
BorrowMutInterior, DerefRead, DerefWrite. They consolidate into the frozen six
used here:

| Frozen (this document) | Earlier name |
| --- | --- |
| Owned | MoveOwned / the owned-Rc owner position |
| SharedRef | BorrowShared |
| HandleClone | CloneHandle |
| ReadBorrow | DerefRead |
| WriteBorrow | BorrowMutInterior / DerefWrite |
| Move | by-value transfer of an owned value or handle |

Function values add two primitives beyond the six value modes:
`FunctionHandleClone` (clone the handle Rc, never the environment) and
`Call` (invoke through the handle). The render primitives map onto the modes
and back: `handle_clone` -> `HandleClone`, `borrow_read` -> `ReadBorrow`,
`borrow_write` -> `WriteBorrow`, `call_receiver` -> the receiver's
resolved mode, `function_handle_clone` -> `FunctionHandleClone`,
`function_call` -> `Call`. A renderer emits only these resolved primitives;
it never re-derives whether a value is Copy, Rc, &Rc, or Clone.

## Policy entries

Each entry carries the six required elements:

1. **Haxe semantics** — the source behavior the entry rules.
2. **Target mapping** — per-target representation (Rust is filled; the other
   four are TODO interfaces).
3. **Typed IR encoding** — the exact `SemanticPolicy.hx` fields.
4. **Validator invariant** — the assertion the M2 validator enforces.
5. **Fixtures** — positive/negative fixture hooks (Executor-A matrix ids).
6. **Version rule** — see the shared rule at the end of this section.

### P-1 Representation classification

1. Every Haxe type is classified into one of eight categories: primitive/copy,
   immutable value, plain-class handle, interface handle, collection handle,
   nullable handle, function/closure, static/global.
2. Rust: Int/Float/Bool/String/parameterless-enums/@:valueType -> the native
   scalar or a Copy/Clone struct; @:dataClass/payload-enums/sorted-tables ->
   an owned value with Clone/PartialEq derives; plain class -> Rc<RefCell<T>>;
   interface -> Rc<RefCell<dyn Trait>>; collection -> Vec / HashMap / sorted
   table; nullable -> Option<inner>; function -> Rc<RefCell<dyn FnMut>>;
   static/global -> a LazyLock/Mutex/single-thread wrapper. TS, Kotlin, Swift,
   Dart: TODO interface.
3. `ReprType` (all variants).
4. Every Haxe type handed to a renderer must carry a non-empty `ReprType`; an
   unclassified type is a lowering error.
5. Positive: `FX-representation-classes`. Negative: none (classification is
   total on the accepted subset).
6. (shared rule)

### P-2 Plain-class handle

1. A plain class value is not a T: its object identity is shared, so every
   binding names the same object.
2. Rust: `Rc<RefCell<T>>`. TS/Kotlin/Swift/Dart: TODO interface.
3. `ReprType.Handle(class_id, NonNull, false)`.
4. A plain-class slot that renders as a bare T (an owned move of the struct) is
   rejected.
5. Positive: `FX-new-self-receiver`, `FX-alias-identity`. Negative:
   `NEG-self-rewrap`.
6. (shared rule)

### P-3 Interface handle

1. An interface value is an aliasing handle to an implementor, never an owned
   copy. Interface handle identity is preserved across slots.
2. Rust: canonical single-thread realization is `Rc<RefCell<dyn Trait>>`, the
   same as a plain interface handle; the trait has no Send/Sync supertraits.
   Arc<Mutex<dyn Trait>> is not policy. TS/Kotlin/Swift/Dart: TODO interface.
3. `ReprType.Handle(class_id, nullability, shared)`.
4. A generated trait that adds `Send` or `Sync` is rejected
   (`NEG-send-sync`); an interface slot that re-wraps the implementor into a
   fresh handle is rejected (`NEG-self-rewrap`).
5. Positive: `FX-interface-dispatch`. Negative: `NEG-send-sync`.
6. (shared rule)

### P-4 Receiver ABI

1. An instance method's receiver is the method's own object (Haxe `self`).
2. Rust: every instance method uniformly receives `&Rc<RefCell<Self>>`; the
   call receiver is an existing handle's borrow, never a rebuilt handle. TS,
   Kotlin, Swift, Dart: TODO interface.
3. `ReceiverAbi.SharedHandle` for instance methods, `ReceiverAbi.None` for
   statics.
4. A method call whose receiver is not a HandleExpr is rejected; `&mut self`
   receivers are rejected (`NEG-mut-self-receiver`).
5. Positive: `FX-new-self-receiver`, `FX-chain-call`. Negative:
   `NEG-self-rewrap`, `NEG-mut-self-receiver`.
6. (shared rule)

### P-5 UseMode

1. Every occurrence of a value/handle is passed or used in exactly one mode.
2. Rust: Owned -> owned Rc/Vec/value; SharedRef -> &Rc<RefCell<T>> / &T /
   &UStr / &[T]; HandleClone -> Rc::clone; ReadBorrow -> RefCell::borrow;
   WriteBorrow -> RefCell::borrow_mut; Move -> by-value transfer;
   FunctionHandleClone -> Rc::clone of a function handle (never the
   environment); Call -> invoke through the handle.
3. `UseMode` (six value modes plus `FunctionHandleClone` and `Call`).
4. An unresolved mode is a lowering error, never a silent guess.
5. Positive: `FX-owned-borrowed-param`, `FX-chain-call`. Negative:
   `NEG-unresolved-mode`.
6. (shared rule)

### P-6 ExprInfo

1. Every lowered expression carries its static representation, its handle
   identity, and its place kind.
2. Rust: the identity drives which binding text a receiver/call renders;
   place_kind drives clone-vs-borrow at read sites. TS/Kotlin/Swift/Dart: TODO
   interface.
3. `ExprInfo{ repr, identity, place_kind }` with `ExprIdentity` (five
   variants) and `PlaceKind` (five variants).
4. An expression missing any of repr/identity/place_kind is rejected; identity
   and place_kind must be consistent with the node kind.
5. Positive: `FX-alias-identity`. Negative: none.
6. (shared rule)

### P-7 Object construction

1. `new X(...)` constructs one object.
2. Rust: construction enters Rc exactly once. `Rc::new(RefCell::new(..))` is
   legal only at a new-object node whose operand is not `self` and not an
   existing class handle. TS/Kotlin/Swift/Dart: TODO interface.
3. `ExprIdentity.FreshObject`.
4. `Rc::new(RefCell::new(..))` appearing outside a FreshObject node, or whose
   operand is self/an existing handle, is rejected
   (`NEG-self-rewrap`).
5. Positive: `FX-new-self-receiver`. Negative: `NEG-self-rewrap`.
6. (shared rule)

### P-8 Parameter passing

1. A function parameter declares its passing contract; the caller satisfies it.
2. Rust: a plain-class parameter arrives as `&Rc<RefCell<T>>` (borrowed
   shared handle) or an owned Rc when the callee takes ownership; a callee that
   accepts a shared handle must not receive an owned Rc argument; value and
   array parameters follow their value/collection representation. TS, Kotlin,
   Swift, Dart: TODO interface.
3. `ParamMode` (Owned / SharedRef / MutableRef / HandleClone).
4. A call site whose argument UseMode does not satisfy the declared ParamMode
   is rejected.
5. Positive: `FX-owned-borrowed-param`. Negative: `NEG-owned-for-shared`.
6. (shared rule)

### P-9 Return

1. A method may return a value or a handle.
2. Rust: a returned handle is a cloned Rc (the caller owns the clone); a
   returned value is moved or cloned per its value representation. TS, Kotlin,
   Swift, Dart: TODO interface.
3. The return position carries a `ReprType` + `UseMode` (typically
   HandleClone for handles).
4. A returned handle that renders as a bare T or a re-wrap of `self` is
   rejected.
5. Positive: `FX-return-handle`. Negative: `NEG-self-rewrap`.
6. (shared rule)

### P-10 Field access

1. Reading/writing a field on a handle observes the shared object.
2. Rust: a field read through an owned local/param borrows (`borrow`/`borrow_mut`)
   and clones only when the value escapes; a handle-typed field read is a
   HandleClone. TS, Kotlin, Swift, Dart: TODO interface.
3. `PlaceKind.Field` + the field's `ReprType` + `UseMode`.
4. A field expression that re-materializes a handle from `self` is rejected.
5. Positive: `FX-handle-field-rw`. Negative: `NEG-self-rewrap`.
6. (shared rule)

### P-11 Closure capture

1. A closure captures bindings from its enclosing scope.
2. Rust: a captured handle is cloned (Rc::clone) into the closure; a captured
   value follows its value representation; the closure never re-wraps `self`.
   TS, Kotlin, Swift, Dart: TODO interface.
3. The capture list carries `UseMode` per captured binding.
4. A capture that re-wraps `self` or that moves a borrowed receiver is
   rejected.
5. Positive: `FX-closure`. Negative: `NEG-self-rewrap`.
6. (shared rule)

### P-12 Nullable

1. `Null<T>` admits absence.
2. Rust: `Option<inner>`. A nullable plain-class handle is
   `Option<Rc<RefCell<T>>>`; its nullability folds into the Handle
   (`Handle(class_id, Nullable, shared)`), while `Null<T>` over a value uses
   `Nullable(inner)`. TS, Kotlin, Swift, Dart: TODO interface.
3. `ReprType.Handle(.., nullability=Nullable, ..)` or
   `ReprType.Nullable(inner)`.
4. A nullable handle rendered as a bare non-Option Rc is rejected.
5. Positive: `FX-nullable`. Negative: none.
6. (shared rule)

### P-13 Collection

1. Array and the map families are collections of elements.
2. Rust: Array -> Vec<T> (borrowed &[T] / &mut Vec<T> at parameter sites);
   HashMap -> HashMap<K,V>; SortedMap/SortedSet -> the resident sorted tables.
   TS, Kotlin, Swift, Dart: TODO interface.
3. `ReprType.Collection(element)`.
4. A collection whose element repr is unresolved is rejected.
5. Positive: `FX-collection`. Negative: none.
6. (shared rule)

### P-14 Function / closure value

1. A function value is a single-thread alias to a closure environment. Cloning
   a function value clones the handle and preserves one environment, never
   copies the environment. The Haxe closure environment can be mutated by a
   call, so FnMut is the robust base model.
2. Rust: canonical realization is `Rc<RefCell<dyn FnMut(Args) -> R>>`. A
   proven-immutable value may use `Rc<dyn Fn(Args) -> R>` as an
   observationally-equivalent optimization; it must not change the policy-level
   type. No Send/Sync bounds, ever. A function value crossing a shared-interface
   slot is not cross-thread: shared-slot function parameters/returns still use
   the same function handle, never Arc or Fn+Send+Sync. TS, Kotlin, Swift,
   Dart: TODO interface.
3. `ReprType.Function(args, result, mutability, captures)` with
   `FunctionMutability.FnMut` (canonical) or `FunctionMutability.Fn`
   (proven immutable); clone via `UseMode.FunctionHandleClone`; invoke via
   `UseMode.Call`.
4. The validator forbids copying a closure environment, forbids a function
   value entering a Send/Sync-bound API, and checks that a shared-slot function
   type stays consistent (same function handle, no Arc).
5. Positive: `FX-closure`. Negative: `NEG-send-sync`.
6. (shared rule)

### P-15 Static / global state

1. A static field is process/global state.
2. Rust: a static whose storage is !Send (an Rc handle, a trait object, an
   Rc-backed function value) is wrapped so the type is not required to be
   Send+Sync: `LazyLock<SingleThread<T>>`, `LazyLock<Mutex<SingleThread<T>>>`
   for a mutable container, and `thread_local! RefCell<T>` for the trait-object
   form. TS, Kotlin, Swift, Dart: TODO interface.
3. `ReprType.Static(inner)` + `PlaceKind.Static`.
4. A static field that renders as a bare `static T` while T is !Send is
   rejected.
5. Positive: `FX-static-mutable`. Negative: `NEG-send-sync`.
6. (shared rule)

### P-16 @:sharedHandle metadata

1. `@:sharedHandle` marks an interface handle whose slots must alias the same
   implementor identity. It changes classification and alias obligations, not
   thread-safety or storage primitive.
2. Rust: the single-thread realization remains `Rc<RefCell<dyn Trait>>`;
   metadata is the only source of shared classification, never a class-name
   whitelist. Each slot passes the same Rc; the object is never re-wrapped into
   multiple handles; Rc::clone is a handle clone, not an object clone. TS,
   Kotlin, Swift, Dart: TODO interface.
3. `ReprType.Handle(class_id, nullability, shared=true)`.
4. The validator rejects fresh wrappers that break identity and rejects
   Arc/Mutex unless a separately declared threaded realization is selected.
5. Positive: `FX-interface-dispatch` (shared interface). Negative:
   `NEG-class-name-whitelist`.
6. (shared rule)

### P-17 Forbidden patterns

The frozen stop-list is normative. These are rejected, never worked around:

- patching clones by source line number;
- turning an Rc into an owned parameter to eliminate a borrow;
- wrapping `self.clone()` in `Rc` to fabricate a receiver;
- restoring Send+Sync on interface traits or function values;
- classifying `shared` by a class-name whitelist;
- introducing Arc/Mutex into a single-thread slot without a separately declared
  threaded realization;
- judging convergence by total error count alone;
- treating an old fixture as an Rc-migrated baseline without a semantic diff.

3. (no dedicated type; each item is an invariant elsewhere in P-1..P-16 and P-18).
4. Each forbidden pattern has a negative fixture that must stay red-absent.
5. Negative: `NEG-self-rewrap`, `NEG-send-sync`, `NEG-mut-self-receiver`,
   `NEG-class-name-whitelist`.
6. (shared rule)

### P-18 Validator invariants

The M2 lowering validator enforces, and reports as errors (never silent
guesses):

- `Rc::new(RefCell::new(..))` only at a new-object node, and its operand is
  neither `self` nor an existing class handle (P-7).
- an instance-method call whose receiver is not a HandleExpr is rejected (P-4).
- an unresolved mode is a lowering error (P-5).
- every expression carries a complete `ExprInfo` (P-6).
- a function value is never cloned by copying its environment, never enters a
  Send/Sync-bound API, and stays a consistent handle across shared slots (P-14).
- a shared interface slot never re-wraps the implementor, and never uses
  Arc/Mutex without a threaded realization (P-16).

3. `SemanticPolicy.hx` is the vocabulary the validator consumes.
4. The validator runs before the renderer; a validator failure aborts emission.
5. Positive: every positive fixture passes validation. Negative: each negative
   fixture fails validation with the named invariant.
6. (shared rule)

### P-19 Machine-readable trace

1. (governance) Lowering records, per expression, the resolved repr, mode, and
   identity.
2. Rust: the trace is target-neutral text over the typed IR (repr/mode/identity),
   not rendered Rust. TS, Kotlin, Swift, Dart: TODO interface.
3. One trace record per expression: `{ expr_id, repr, mode, identity, place_kind }`.
4. The trace is emitted for every lowered expression; an expression with no
   trace record is a lowering error.
5. Positive: `FX-trace-repr-mode-identity`. Negative: none.
6. (shared rule)

### P-20 Workflow rules

1. (governance) The compiler workflow is: policy/IR contract first, then
   backend; a rule is never derived back from a cargo/rustc error.
2. Rust: no realization change lands without a policy/IR edit in the same
   commit. TS, Kotlin, Swift, Dart: TODO interface.
3. `SemanticPolicy.VERSION` and `entryIds()` are the contract's change ledger.
4. A backend-only change with no policy/IR edit fails review.
5. Positive: every fixture. Negative: none.
6. (shared rule)

### Shared version rule (element 6 of every entry)

An entry changes only by editing this document in the same commit as the code
that implements the change. Changing a realization without a policy edit, or
reverting a frozen decision, requires an Astra ruling (open-ended consultation).
A version bump is required when a frozen entry's semantics change; a realization
fill-in (TODO -> concrete) does not bump the policy version.

## Realization mapping (five targets)

| Haxe semantic | Rust (this round) | TypeScript | Kotlin | Swift | Dart |
| --- | --- | --- | --- | --- | --- |
| primitive/copy | u32/i32, f32/f64, bool, UString | TODO | TODO | TODO | TODO |
| immutable value | owned struct + Clone/PartialEq | TODO | TODO | TODO | TODO |
| plain-class handle | Rc<RefCell<T>> | TODO | TODO | TODO | TODO |
| interface handle | Rc<RefCell<dyn Trait>> | TODO | TODO | TODO | TODO |
| shared interface handle | Rc<RefCell<dyn Trait>> (alias obligation) | TODO | TODO | TODO | TODO |
| collection (Array) | Vec<T> / &[T] / &mut Vec<T> | TODO | TODO | TODO | TODO |
| collection (Map) | HashMap<K,V> / sorted table | TODO | TODO | TODO | TODO |
| nullable value | Option<inner> | TODO | TODO | TODO | TODO |
| function/closure | Rc<RefCell<dyn FnMut(..) -> R>> (no Send/Sync); Rc<dyn Fn(..) -> R> as optimization | TODO | TODO | TODO | TODO |
| static/global | LazyLock<SingleThread<T>> / Mutex / thread_local RefCell | TODO | TODO | TODO | TODO |

The four TODO columns are declared interfaces only; this round implements the
Rust realization and leaves the others untouched.

## Design principles

This policy upholds the repository design principles (design-principles.md):
content-defined semantics (P-1, P-2), restrict-and-provide-in-one-change (P-17
names the sanctioned path), cost tiers (P-15), transpiler effort is not a
design input (P-20), and the stage-one oracle verifies rather than defines
(P-19). The audit tests T1-T4 are exercised by the positive/negative fixture
hooks above.

