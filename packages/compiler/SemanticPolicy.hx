package;

/**
    Target Semantic Policy: the executable encoding of the cross-target
    reference/handle semantics contract.

    This module is the single source of truth for the typed-IR vocabulary a
    Haxe type and expression must resolve into before any target renderer runs.
    It is a *policy* contract, not a Rust implementation detail: Rc<RefCell<T>>,
    SingleThread<T>, and every other concrete type are the Rust *realization*
    declared in the mapping table (docs/specs/target-semantic-policy.md), never
    the policy itself.

    Final boundary (single-thread target):
      - Rc<RefCell<T>>            = plain class
      - Rc<RefCell<dyn Trait>>    = interface / shared interface
      - Rc<RefCell<dyn FnMut..>>  = function value
    All three express single-thread aliasing plus interior mutability.
    Arc/Mutex belong only to an explicitly declared threaded realization and
    are never implied by this v1 policy.

    Governance (see docs/specs/target-semantic-policy.md):
      - author/owner  = Executor-B
      - sign-off      = TL (captain); a draft is not normative until the TL
                        promotes a draft to a released version.
      - arbitration   = Astra (lingsuan gpt-6-astra, open-ended consultation).

    Every enum below corresponds one-to-one with a policy entry (P-n) in the
    governing document. Validators (the M2 lowering validator) cite these entry
    ids and never infer a mode from rendered text.
**/

/** Nullability of a value or handle slot. */
enum Nullability {
    NonNull;
    Nullable;
}

/** Whether a function value's closure environment may mutate across calls. */
enum FunctionMutability {
    /** canonical: the environment may mutate, so calls take FnMut. */
    FnMut;

    /** optimization: proven immutable, so calls may take Fn (Rc<dyn Fn>). */
    Fn;
}

/**
    The target representation category of a Haxe type (policy entry P-1).

    The eight categories of the frozen ruling collapse into these variants:

      - primitive/copy        -> Copy
      - immutable value       -> ImmutableValue
      - plain-class handle    -> Handle(class_id, shared=false, nullability)
      - interface handle      -> Handle(class_id, shared, nullability)
      - collection handle     -> Collection(element)
      - nullable handle       -> Handle(..., nullability=Nullable)  (a nullable
                                 class/interface reference folds its nullability
                                 into the Handle; Null<T> over a *value* uses
                                 Nullable(inner) instead)
      - function/closure      -> Function(args, result, mutability, captures)
      - static/global         -> Static(inner)  (storage-position classifier)

    A plain class or interface is never a value: its object identity is shared,
    realized in Rust as Rc<RefCell<T>> (plain class) or Rc<RefCell<dyn Trait>>
    (interface, including shared interfaces per @:sharedHandle).
**/
enum ReprType {
    /** primitive/copy: Int, Float, Bool, String, parameterless enums, @:valueType abstracts. */
    Copy;

    /** immutable value: @:dataClass records, payload enums, sorted tables, anonymous structs. */
    ImmutableValue;

    /**
        plain-class or interface reference. Object identity is shared, so the
        value is a handle, not a T.

        - class_id   : the Haxe class/interface identity (module-qualified).
        - nullability: whether the slot admits Null.
        - shared     : true when the interface is @:sharedHandle. This marks an
                       alias obligation (the same implementor identity across
                       slots), not thread safety; the realization stays
                       Rc<RefCell<dyn Trait>>.
    **/
    Handle(class_id:String, nullability:Nullability, shared:Bool);

    /** collection handle: Array/Map/HashMap/SortedMap/SortedSet. Element repr is separate. */
    Collection(element:ReprType);

    /** nullable value: Null<T> where T is a value repr. Nullable handles use Handle(nullability=Nullable). */
    Nullable(inner:ReprType);

    /**
        function/closure: a first-class function value, i.e. a single-thread
        alias to a closure environment. Canonical Rust realization is
        Rc<RefCell<dyn FnMut(args) -> result>>; a proven-immutable value may use
        Rc<dyn Fn(args) -> result> as an observationally-equivalent optimization.
        Cloning clones the handle Rc only, never the environment.

        - args      : the parameter reprs.
        - result    : the return repr.
        - mutability: FnMut (canonical) or Fn (proven immutable).
        - captures  : the reprs of the captured bindings.
    **/
    Function(args:Array<ReprType>, result:ReprType, mutability:FunctionMutability, captures:Array<ReprType>);

    /** static/global state: a static-field position wrapping the inner repr. */
    Static(inner:ReprType);
}

/**
    How a value or handle is passed or used at one occurrence (policy entry P-5).

    Frozen variant set: Owned, SharedRef, HandleClone, ReadBorrow, WriteBorrow,
    Move. Function values add two primitives: FunctionHandleClone (clone the
    handle Rc, never the environment) and Call (invoke through the handle).
    The render primitives map onto the modes and back:
    handle_clone -> HandleClone, borrow_read -> ReadBorrow,
    borrow_write -> WriteBorrow, call_receiver -> the receiver's resolved mode,
    function_handle_clone -> FunctionHandleClone, function_call -> Call.
    A renderer may only emit an already-resolved mode, never a new judgment
    about whether a value is Copy, Rc, &Rc, or Clone.
**/
enum UseMode {
    /** The binding owns its storage: an owned Rc, an owned Vec, or a Copy value. */
    Owned;

    /** A borrowed shared reference: &Rc<RefCell<T>>, &T, &UStr, &[T]. */
    SharedRef;

    /** Clone the handle (Rc::clone) so the source keeps its alias. */
    HandleClone;

    /** Interior immutable read (RefCell::borrow / deref read). */
    ReadBorrow;

    /** Interior mutable write (RefCell::borrow_mut / deref write). */
    WriteBorrow;

    /** Move ownership: by-value transfer of an owned value or handle. */
    Move;

    /** Clone a function handle: Rc::clone only, never a copy of the closure environment. */
    FunctionHandleClone;

    /** Invoke a function value through its handle. */
    Call;
}

/**
    What a handle expression denotes (policy entry P-6). Identity is independent
    of place_kind: the same handle can be a local place (LocalHandle) while a
    field read through a borrowed receiver is a BorrowedProjection.
**/
enum ExprIdentity {
    /** The method's own receiver handle (self lowered to the injected receiver binding). */
    SelfHandle;

    /** A local variable binding a handle. */
    LocalHandle;

    /** A field access that yields a handle. */
    FieldHandle;

    /** A freshly constructed object (new X(...)): the only node allowed to wrap Rc::new(RefCell::new(..)). */
    FreshObject;

    /** A projection through a borrow (field/index read on a borrowed handle or container). */
    BorrowedProjection;
}

/**
    Whether an expression is a place and where that place lives (policy entry P-6).
    Orthogonal to ExprIdentity; a BorrowedProjection identity is usually a Value
    place, while a FieldHandle identity is usually a Field place.
**/
enum PlaceKind {
    /** rvalue: the expression denotes a value with no addressable location. */
    Value;

    /** a local binding place. */
    Local;

    /** a field place, addressed through its receiver. */
    Field;

    /** an indexed place (array/map element). */
    Index;

    /** a static/global place. */
    Static;
}

/** The typed-IR record carried by every lowered expression (policy entry P-6). */
typedef ExprInfo = {
    var repr:ReprType;
    var identity:ExprIdentity;
    var place_kind:PlaceKind;
};

/**
    The ABI of a method's receiver (policy entry P-4).

    Frozen ruling: an instance method uniformly receives &Rc<RefCell<Self>>;
    the call receiver must be an existing handle's borrow, never a rebuilt handle.
    Static functions carry no receiver.
**/
enum ReceiverAbi {
    /** static: no receiver. */
    None;

    /** instance: receiver is a borrowed shared handle of Self (Rust: &Rc<RefCell<Self>>). */
    SharedHandle;
}

/**
    How an interface (trait) realization exposes a method receiver
    (policy entry P-4a, merged from the TraitAdapter branch 1.3.0).

    An identity-sensitive trait method (a method body that reads this as a
    handle value: returns it, passes it, stores it, or compares it) cannot run
    against the bare struct receiver, because &self is &Xxx and the canonical
    Rc<RefCell<Xxx>> handle is unreachable from it. Such a method lowers
    through a generated adapter: the trait impl is on
    XxxAdapter { object: Rc<RefCell<Xxx>> }, its &self is &XxxAdapter, and the
    method body runs against self.object (the canonical handle) through a
    shared handle-aware helper.

    v1.4.0 adopts this variant verbatim instead of re-defining it. The
    RepresentationPlan decides which variant applies, and the adapter edge it
    emits must be registered in the target capability table (P-25).
**/
enum InterfaceReceiverAbi {
    /** Non-identity direct realization: the trait impl is on the bare struct, the receiver is &self = &Xxx. */
    DirectInner;

    /** Identity-sensitive realization: the trait impl is on the generated adapter, the receiver is &self = &XxxAdapter, delegating through object. */
    HandleAdapter;
}

/**
    The declared passing mode of one parameter (policy entry P-3). The callee
    declares the mode; the caller resolves the argument's UseMode to satisfy it.
    A callee that accepts a shared handle must not receive an owned parameter.
**/
enum ParamMode {
    /** by value: owns its storage (Copy value, moved value, or owned Rc). */
    Owned;

    /** borrowed shared reference. */
    SharedRef;

    /** borrowed mutable reference (&mut T, &mut Vec<u16>). */
    MutableRef;

    /** the caller clones a handle into the parameter slot. */
    HandleClone;
}

/**
    The destination position contract (policy entry P-22). Composition owns the
    destination (Contract 1, INTERFACE-REQUIREMENTS.md): decide() is handed the
    contract, never asked to infer it from compiler-instance state.
**/
enum DestinationContract {
    /** boolean condition of if/while/assert. */
    Condition;
    /** one operand of +,-,comparison. */
    ArithmeticOperand;
    /** endpoint of a for/slice. */
    RangeBound;
    /** left-hand side of a member access. */
    Receiver;
    /** argument of string interpolation/concat. */
    StringConcatArgument;
    /** computed for side effects; no consumer. */
    Discard;
    /** a return position. */
    Return;
    /** a field storage position. */
    Field;
    /** a parameter position. */
    Param;
    /** a local binding position. */
    Local;
}

/**
    Compilation-unit kind of a declaration's module. The planKey and concrete
    representation must not vary across these three (criterion 2): a
    declaration in lib, test, and test-support resolves to the same plan.
**/
enum UnitKind {
    Lib;
    Test;
    TestSupport;
}

/** The module context a decision site lives in (governance only; never a representation input). */
typedef ModuleContext = {
    var module:String;
    var unit:UnitKind;
    var isCfgTest:Bool;
};

/**
    The identity/lifetime/mutability/nullability facts a decision consumes.
    Produced by source analysis (category A, PROBLEM-CLASSIFICATION.md);
    decide() never re-derives them.

    identitySensitive and isInterface come from the preScan table keyed by
    (module, class, method): they are computed once during pre-scan and read
    back by every consumer. A render-time re-walk of the method body
    (RustDecl.bodyUsesThisAsValue) is forbidden; the four consumers (adapter
    generation, concrete-skip, coercion routing, validator P-4a) read the table.
**/
typedef SemanticFacts = {
    /** the declaration reads this as a handle value (returns/passes/stores/compares); from the preScan table. */
    var identitySensitive:Bool;
    /** true when the source type is an interface/trait, false for a plain class; from source analysis. */
    var isInterface:Bool;
    /** true when @:sharedHandle marks the handle as cross-thread shared (P-16); from source analysis. */
    var isCrossThreadShared:Bool;
    /** the value escapes its declaration scope (else it may be borrowed). */
    var lifetime:Bool;
    /** the handle is aliased across more than one live slot. */
    var aliased:Bool;
    /** the interior mutates across calls (else a proven-immutable mapping may apply). */
    var mutable:Bool;
    /** the declared nullability of the slot; null means unresolved. */
    var nullability:Null<Nullability>;
};

/**
    The representation role a declaration resolves into (policy entry P-22).
    This is the single decision the plan owns: a renderer may only print an
    already-resolved role, never re-decide whether a value is a class handle, a
    trait handle, an adapter, or a borrow.

    L0 alignment (merged from the TraitAdapter line, per
    docs/architecture/rust-handle-abi-classification.md):
      - Value             = the L0 Value(Copy | ImmutableValue).
      - ClassHandle       = the L0 ClassHandle(C,n) -> Rc<RefCell<C>>; the former
                            RepresentationRole.Handle split into this + TraitHandle,
                            because one Handle used to conflate class and trait
                            and force an isInterface branch downstream.
      - TraitHandle       = the L0 TraitHandle(I,n,shared) -> Rc<RefCell<dyn I>>.
      - AdapterHandle     = the L0 AdapterHandle(C,I): a coercion transient that
                            exists only inside coerce(ClassHandle(C), TraitHandle(I))
                            and unsizes immediately to TraitHandle. decide() never
                            returns it; an emitted occurrence with this role is a
                            validator failure (P-22).
      - TraitHandleAdapter = the method-level role: an identity-sensitive interface
                            receiver realized through the generated adapter. It is
                            NOT the same as AdapterHandle; it is the decision that
                            routes coerce through the AdapterHandle(C,I) transient.

    identitySensitive is an input fact (SemanticFacts.identitySensitive), not a
    role: an identity-sensitive non-receiver handle resolves to ClassHandle or
    TraitHandle with its identity preserved by Rc clone, never a distinct role.
**/
enum RepresentationRole {
    /** a plain value with no object identity (Copy/ImmutableValue). */
    Value;
    /** a plain-class handle: Rc<RefCell<C>>. */
    ClassHandle;
    /** an interface/trait handle: Rc<RefCell<dyn I>>. */
    TraitHandle;
    /** a coercion transient (ClassHandle -> TraitHandle); never an emitted role. */
    AdapterHandle;
    /** an identity-sensitive interface receiver realized through a generated adapter (P-4a). */
    TraitHandleAdapter;
    /** a borrowed interior-immutable read. */
    ReadBorrow;
    /** a borrowed interior-mutable write. */
    WriteBorrow;
}

/**
    A registered conversion between two representations (policy entry P-25).
    This is the only admissible shape of a representation change: a bare
    Box::new/Rc::new/unwrap without a registered edge is UnsupportedAdapter,
    never a silent guess.
**/
typedef ConversionEdge = {
    var from:ReprType;
    var to:ReprType;
    var adapter:String;
    var policyId:String;
    var provenance:String;
};

/**
    The target capability table (policy entry P-25): which realization
    strategies are available plus the registered conversion edges.
**/
typedef TargetCapabilities = {
    var supportsDirectInner:Bool;
    var supportsHandleAdapter:Bool;
    var conversionEdges:Array<ConversionEdge>;
};

/**
    The ABI profile a target assigns one declaration (policy entry P-22):
    receiver, interface-receiver, and parameter passing decided once.
**/
typedef TargetAbiProfile = {
    var receiverAbi:ReceiverAbi;
    var interfaceReceiverAbi:InterfaceReceiverAbi;
    var paramAbi:ParamMode;
};

/**
    The single representation decision for one declaration (policy entry P-22).
    The chain is PreparedValue -> RepresentationPlan -> Lowered; a renderer
    consumes the plan and never re-infers representation from rendered text,
    module name, or cfg(test).
**/
typedef RepresentationPlan = {
    var role:RepresentationRole;
    /** true when the role routes through the generated adapter (P-4a/P-25). */
    var requiresAdapterEdge:Bool;
    /** true when the handle is cross-thread shared and needs a Send + Sync bound (P-16). */
    var sendSync:Bool;
    /** concrete spelling, filled by the target profile (RustAbiProfile.spell), NOT by decide(). */
    var concreteRepr:String;
    var receiverAbi:ReceiverAbi;
    var paramAbi:ParamMode;
    var conversionEdges:Array<ConversionEdge>;
    var planKey:String;
    var policyId:String;
    var provenance:String;
    var failureReason:String;
};

/**
    The complete input to decide() (policy entry P-24). Every field is a fact
    produced upstream; decide() performs no host type resolution.
**/
typedef DecideInput = {
    var sourceType:Null<ReprType>;
    var sourceIdentity:Null<ExprIdentity>;
    var destinationContract:DestinationContract;
    var useMode:Null<UseMode>;
    var moduleContext:Null<ModuleContext>;
    var facts:Null<SemanticFacts>;
    var capabilities:Null<TargetCapabilities>;
};

/**
    The single cross-target Target Semantic Policy contract.

    Holds the governing version, governance identity, and the policy-entry ids
    (P-n) that validators cite. Every entry id names exactly one section in
    docs/specs/target-semantic-policy.md, and every IR type above maps onto one
    or more entries, so the document and the typed contract cannot drift.
**/

/**
    The seven-domain declaration surface for place/identity proof (Astra
    ruling, spec section 9.2). SemanticPolicy declares these as authoritative
    facts; the PlacePlanner derives a path's place/identity from them and never
    invents an undeclared capability. A missing declaration is Unknown, which
    fails closed on any mutation path (never a silent default to a place).
    (PlacePolicy)
**/

/** Where a value or handle's storage lives. */
enum StorageKind {
    /** a plain owned value (Copy / ImmutableValue / Collection backing). */
    Value;
    /** a shared referent behind a handle (Rc<RefCell<..>> / Arc<Mutex<..>>). */
    SharedReferent;
    /** a static-field slot. */
    StaticSlot;
    /** a borrowed view (guard, borrow). */
    BorrowedView;
    /** not yet declared; fails closed on mutation. */
    Unknown;
}

/** What a clone of the value does to the original storage. */
enum CloneRelation {
    /** the clone is a detached copy; writing it does not reach the original. */
    DetachedCopy;
    /** the clone keeps the referent identity; writing through it is correct. */
    PreserveReferentIdentity;
    /** the value has no clone (Copy / NoClone). */
    NoClone;
    /** not yet declared; fails closed on mutation. */
    Unknown;
}

/** What a mutation of the value is allowed to change. */
enum MutationCapability {
    /** the value is immutable; a slot write is the only admissible mutation. */
    Immutable;
    /** a method call mutates the shared referent. */
    MutatesReferent;
    /** a write replaces the storage slot. */
    MutatesSlot;
    /** the mutation needs explicit writeback to reach the original slot. */
    RequiresWriteback;
    /** not yet declared; fails closed on mutation. */
    Unknown;
}

/** Whether a value is a place (a storage location you can write through). */
enum PlaceCapability {
    /** a place: writing through it reaches the original slot/referent. */
    Place;
    /** not a place: a detached value; writing it loses the write. */
    NonPlace;
    /** a place only under a condition (e.g. presence of a nullable). */
    Conditional;
    /** not yet declared; fails closed on mutation. */
    Unknown;
}

/** How a nullable projection preserves (or loses) the underlying place. */
enum NullableProjection {
    /** unwrapping preserves presence and the underlying place. */
    PreservePresence;
    /** unwrapping borrows the referent (handle inner). */
    UnwrapBorrow;
    /** unwrapping a value payload needs explicit writeback. */
    WritebackRequired;
    /** unwrapping yields a non-place. */
    NonPlace;
    /** not yet declared; fails closed on mutation. */
    Unknown;
}

/** The declared place-ness of a static-field slot. */
enum StaticStorage {
    /** a mutable place; a subscript write reaches the slot. */
    MutablePlace;
    /** immutable; a subscript write is rejected. */
    Immutable;
    /** a runtime-guarded place (LazyLock/OnceLock); needs a runtime access contract. */
    RuntimeGuardedPlace;
    /** a read-only view; a subscript write is rejected. */
    ReadOnlyView;
    /** not yet declared; fails closed on mutation. */
    Unknown;
}

/** A named alias/writeback contract for a set/remove/index/write operation. */
typedef OperationContract = {
    var id:String;
    /** the alias relationship the operation preserves. */
    var alias:StorageKind;
    /** the writeback the operation requires, or "" when none. */
    var writeback:String;
}

/**
    The root place classification for a mutation target root, derived from the
    declared policy domains (spec 9.2). isPlace is never defaulted: it is true
    only when the declaration proves the root is a place, and false when the
    declaration proves it is a DetachedCopy. verified is true only when the
    classification was actually computed from a declaration (never a silent
    default). (PlacePolicy)
**/
typedef RootPlaceClass = {
    var isPlace:Bool;
    /** PreserveLocation for a slot, PreserveReferentIdentity for a handle root. */
    var kind:String;
    var verified:Bool;
    /** the policy domain that decided this class, for diagnostics. */
    var domain:String;
    /** a human-readable reason citing the declared capability. */
    var reason:String;
}

class SemanticPolicy {
    /**
        Normative version 1.4.0 (TL sign-off). Entry provenance ledger:

        Each entry carries its source version so that one semantic never receives
        two numbers and no entry is silently dropped on merge.

          Source   Entries
          1.1.0    P-1..P-21, P-20a, P-23 (v2 baseline)
          1.2.0    (B6: no new entry ids, but lowering/validator refinements;
                   B6's SemanticPolicy carries a pre-P-21/P-23 fork record.
                   P-21/P-23 are retained from the v2 1.1.0 baseline.)
          1.3.0    P-4a  (InterfaceReceiverAbi; TraitAdapter branch)
          1.4.0    P-22  (RepresentationPlan)
                   P-24  (PlanDecision: decide/explain, judgment order and conflict)
                   P-25  (ConversionEdge: adapter table, fail-closed)

        B6 1.2.0 exists as a numbering fork: its SemanticPolicy is a pre-P-21/
        P-23 snapshot. The 1.4.0 merge treats the v2 baseline (which has P-21,
        P-23, and the B6 lowering fixes) as authoritative and adds P-4a from
        1.3.0 plus P-22/P-24/P-25 from 1.4.0. No semantic has two numbers.
    **/
    public static final VERSION:String = "1.4.0";

    /** Governing document, repository-relative. */
    public static final DOC_PATH:String = "docs/specs/target-semantic-policy.md";

    /** Governance: author/owner, sign-off, and arbitration. */
    public static final OWNER:String = "Executor-B";
    public static final SIGN_OFF:String = "TL";
    public static final ARBITRATOR:String = "Astra (lingsuan gpt-6-astra)";

    /** Policy entry ids in DOC_PATH, in document order. Provenance: [source version]. */
    public static final ENTRY_REPRESENTATION:String = "P-1";              // [1.1.0]
    public static final ENTRY_PLAIN_CLASS_HANDLE:String = "P-2";          // [1.1.0]
    public static final ENTRY_INTERFACE_HANDLE:String = "P-3";            // [1.1.0]
    public static final ENTRY_RECEIVER_ABI:String = "P-4";                // [1.1.0]
    public static final ENTRY_INTERFACE_RECEIVER_ABI:String = "P-4a";    // [1.3.0: TraitAdapter branch, InterfaceReceiverAbi]
    public static final ENTRY_USE_MODE:String = "P-5";                    // [1.1.0]
    public static final ENTRY_EXPR_IDENTITY:String = "P-6";               // [1.1.0]
    public static final ENTRY_CONSTRUCTION:String = "P-7";                // [1.1.0]
    public static final ENTRY_PARAM_PASSING:String = "P-8";               // [1.1.0]
    public static final ENTRY_RETURN:String = "P-9";                      // [1.1.0]
    public static final ENTRY_FIELD_ACCESS:String = "P-10";               // [1.1.0]
    public static final ENTRY_CLOSURE_CAPTURE:String = "P-11";            // [1.1.0]
    public static final ENTRY_NULLABLE:String = "P-12";                   // [1.1.0]
    public static final ENTRY_COLLECTION:String = "P-13";                 // [1.1.0]
    public static final ENTRY_FUNCTION:String = "P-14";                   // [1.1.0]
    public static final ENTRY_STATIC_STATE:String = "P-15";               // [1.1.0]
    public static final ENTRY_SHARED_HANDLE_META:String = "P-16";         // [1.1.0; fixed by B-line census 3-target 0-error: cross-thread shared = Arc<Mutex<dyn Trait + Send + Sync>>, single-thread = Rc<RefCell<dyn Trait>>]
    public static final ENTRY_FORBIDDEN_PATTERNS:String = "P-17";         // [1.1.0]
    public static final ENTRY_VALIDATOR:String = "P-18";                  // [1.1.0]
    public static final ENTRY_TRACE:String = "P-19";                      // [1.1.0]
    public static final ENTRY_WORKFLOW:String = "P-20";                   // [1.1.0]
    public static final ENTRY_VALIDATION_COVERAGE:String = "P-20a";       // [1.1.0]
    public static final ENTRY_ABI_COLLISION:String = "P-21";              // [1.1.0]
    public static final ENTRY_REPRESENTATION_PLAN:String = "P-22";        // [1.4.0]
    public static final ENTRY_FLOAT_CANONICAL:String = "P-23";            // [1.1.0]
    public static final ENTRY_PLAN_DECISION:String = "P-24";              // [1.4.0]
    public static final ENTRY_CONVERSION_EDGE:String = "P-25";            // [1.4.0]

    /**
        Every policy entry id in document order. Validators and the unit suite
        iterate this list to prove the document and the contract stay in step.
    **/
    public static function entryIds():Array<String> {
        return [
            ENTRY_REPRESENTATION,
            ENTRY_PLAIN_CLASS_HANDLE,
            ENTRY_INTERFACE_HANDLE,
            ENTRY_RECEIVER_ABI,
            ENTRY_INTERFACE_RECEIVER_ABI,
            ENTRY_USE_MODE,
            ENTRY_EXPR_IDENTITY,
            ENTRY_CONSTRUCTION,
            ENTRY_PARAM_PASSING,
            ENTRY_RETURN,
            ENTRY_FIELD_ACCESS,
            ENTRY_CLOSURE_CAPTURE,
            ENTRY_NULLABLE,
            ENTRY_COLLECTION,
            ENTRY_FUNCTION,
            ENTRY_STATIC_STATE,
            ENTRY_SHARED_HANDLE_META,
            ENTRY_FORBIDDEN_PATTERNS,
            ENTRY_VALIDATOR,
            ENTRY_TRACE,
            ENTRY_WORKFLOW,
            ENTRY_VALIDATION_COVERAGE,
            ENTRY_ABI_COLLISION,
            ENTRY_REPRESENTATION_PLAN,
            ENTRY_FLOAT_CANONICAL,
            ENTRY_PLAN_DECISION,
            ENTRY_CONVERSION_EDGE
        ];
    }

    /**
        The single representation decision (policy entry P-24).

        Judgment order:
          1. alias/monomorph/nullability/source identity (incomplete = UnknownInput)
          2. destination ABI (receiver + parameter passing)
          3. identity/lifetime/alias/mutability (role)
          4. target capability (DirectInner | HandleAdapter | registered edge)
          5. use mode (ownership)

        Conflict priority (highest first): identity/lifetime > destination ABI
        > source repr > use mode > target spelling. A same-level conflict is an
        ambiguity error, never a silent tie-break. moduleContext/cfg(test)
        never changes planKey or concreteRepr.
    **/
    public static function decide(input:DecideInput):RepresentationPlan {
        final plan:RepresentationPlan = {
            role: RepresentationRole.Value,
            requiresAdapterEdge: false,
            sendSync: false,
            concreteRepr: "",
            receiverAbi: ReceiverAbi.None,
            paramAbi: ParamMode.Owned,
            conversionEdges: [],
            planKey: "",
            policyId: ENTRY_REPRESENTATION_PLAN,
            provenance: "SemanticPolicy.decide@1.4.0",
            failureReason: ""
        };

        // 1. completeness (UnknownInput)
        if (input == null || input.sourceType == null) {
            plan.policyId = ENTRY_PLAN_DECISION;
            plan.failureReason = "UnknownInput: sourceType unresolved (monomorph/alias without a resolved type)";
            return plan;
        }
        if (input.sourceIdentity == null) {
            plan.policyId = ENTRY_PLAN_DECISION;
            plan.failureReason = "UnknownInput: sourceIdentity unresolved";
            return plan;
        }
        if (input.useMode == null) {
            plan.policyId = ENTRY_PLAN_DECISION;
            plan.failureReason = "UnknownInput: useMode unresolved";
            return plan;
        }
        if (input.facts == null || input.facts.nullability == null) {
            plan.policyId = ENTRY_PLAN_DECISION;
            plan.failureReason = "UnknownInput: nullability unresolved";
            return plan;
        }

        // 2. destination ABI
        plan.receiverAbi = receiverAbiFor(input.destinationContract);
        plan.paramAbi = paramAbiFor(input.useMode);

        // 3. role from identity/lifetime/alias/mutability, with a same-level
        //    ambiguity check between the identity and lifetime signals.
        if (input.facts.identitySensitive && !input.facts.lifetime && !input.facts.aliased && !input.facts.mutable) {
            plan.policyId = ENTRY_PLAN_DECISION;
            plan.failureReason = "ambiguity: identity/lifetime conflict (identity-sensitive but no aliasing, mutation, or escaping lifetime)";
            return plan;
        }
        plan.role = roleFor(input.facts, input.destinationContract, input.sourceType, input.useMode);
        plan.requiresAdapterEdge = (plan.role == RepresentationRole.TraitHandleAdapter);
        plan.sendSync = input.facts.isCrossThreadShared;

        // 4. target capability: identity-sensitive interface methods need a
        //    registered adapter edge; a bare realization is never invented.
        if (plan.role == RepresentationRole.TraitHandleAdapter) {
            if (input.capabilities == null) {
                plan.policyId = ENTRY_CONVERSION_EDGE;
                plan.failureReason = "UnsupportedAdapter: no capability table supplied";
                return plan;
            }
            final edge = findConversionEdge(input.capabilities, input.sourceType);
            if (edge == null) {
                plan.policyId = ENTRY_CONVERSION_EDGE;
                plan.failureReason = "UnsupportedAdapter: no registered ConversionEdge for the identity-sensitive adapter";
                return plan;
            }
            plan.conversionEdges = [edge];
            if (!input.capabilities.supportsHandleAdapter && plan.role == RepresentationRole.TraitHandleAdapter) {
                plan.policyId = ENTRY_CONVERSION_EDGE;
                plan.failureReason = "UnsupportedAdapter: identity-sensitive receiver needs HandleAdapter, only DirectInner available";
                return plan;
            }
        }

        // 5. concrete spelling is target-specific: decide() leaves it empty and
        //    the target profile (RustAbiProfile.spell) fills it. decide() is target-neutral.
        plan.concreteRepr = "";

        // planKey is derived only from the representation decision (role), never
        // from the per-use-site ABI or moduleContext.
        plan.planKey = planKeyFor(plan.role);

        return plan;
    }

    /** Human-readable explanation of a plan; cites the policy entry and failure. */
    public static function explain(plan:RepresentationPlan):String {
        if (plan == null)
            return "no RepresentationPlan produced";
        if (plan.failureReason != "")
            return "[" + plan.policyId + "] " + plan.failureReason;
        return "[P-22] role=" + roleToString(plan.role)
            + " repr=" + plan.concreteRepr
            + " receiver=" + receiverAbiToString(plan.receiverAbi)
            + " param=" + paramModeToString(plan.paramAbi)
            + " planKey=" + plan.planKey;
    }

    /** The receiver ABI a destination position demands (P-4). */
    public static function receiverAbiFor(dest:DestinationContract):ReceiverAbi {
        return switch (dest) {
            case DestinationContract.Receiver: ReceiverAbi.SharedHandle;
            case _: ReceiverAbi.None;
        };
    }

    /** The parameter passing mode an already-resolved use mode satisfies (P-8). */
    public static function paramAbiFor(mode:UseMode):ParamMode {
        return switch (mode) {
            case UseMode.Owned | UseMode.HandleClone: ParamMode.Owned;
            case UseMode.SharedRef | UseMode.ReadBorrow: ParamMode.SharedRef;
            case UseMode.WriteBorrow | UseMode.Move: ParamMode.MutableRef;
            case UseMode.FunctionHandleClone | UseMode.Call: ParamMode.HandleClone;
        };
    }

    /** The role a declaration resolves into, in priority order (P-22). */
    public static function roleFor(facts:SemanticFacts, dest:DestinationContract, sourceType:ReprType, mode:UseMode):RepresentationRole {
        // identity-sensitive interface method: realized through the adapter.
        if (facts.identitySensitive && facts.isInterface && dest == DestinationContract.Receiver)
            return RepresentationRole.TraitHandleAdapter;
        // a handle (class or trait) whose identity is preserved by Rc clone.
        if (facts.aliased || facts.mutable || isHandleRepr(sourceType))
            return facts.isInterface ? RepresentationRole.TraitHandle : RepresentationRole.ClassHandle;
        return switch (mode) {
            case UseMode.ReadBorrow: RepresentationRole.ReadBorrow;
            case UseMode.WriteBorrow: RepresentationRole.WriteBorrow;
            case _: RepresentationRole.Value;
        };
    }

    /**
        The stable plan key. It encodes only the representation decision (the
        role), never the per-use-site ABI (receiverAbi/paramAbi) and never the
        target spelling or module/cfg. A plan is the per-source-type decision;
        the ABI is a per-use-site attribute, so it stays out of the key (P-24:
        the same source type resolves to the same decision across every use
        site, lib/test/test-support, receiver or local).
    **/
    public static function planKeyFor(role:RepresentationRole):String {
        return "plan:" + roleToString(role);
    }

    /** Find the registered edge from one representation, or null. */
    public static function findConversionEdge(caps:TargetCapabilities, from:ReprType):Null<ConversionEdge> {
        if (caps == null || caps.conversionEdges == null)
            return null;
        for (edge in caps.conversionEdges)
            if (reprEquals(edge.from, from))
                return edge;
        return null;
    }

    public static function isHandleRepr(r:ReprType):Bool {
        return switch (r) {
            case ReprType.Handle(_, _, _): true;
            case _: false;
        };
    }

    /** Structural equality over the representation categories. */
    public static function reprEquals(a:ReprType, b:ReprType):Bool {
        return switch (a) {
            case ReprType.Copy: switch (b) { case ReprType.Copy: true; case _: false; }
            case ReprType.ImmutableValue: switch (b) { case ReprType.ImmutableValue: true; case _: false; }
            case ReprType.Handle(id1, n1, s1):
                switch (b) { case ReprType.Handle(id2, n2, s2): id1 == id2 && n1 == n2 && s1 == s2; case _: false; }
            case ReprType.Collection(e1): switch (b) { case ReprType.Collection(e2): reprEquals(e1, e2); case _: false; }
            case ReprType.Nullable(e1): switch (b) { case ReprType.Nullable(e2): reprEquals(e1, e2); case _: false; }
            case ReprType.Function(_, _, m1, _): switch (b) { case ReprType.Function(_, _, m2, _): m1 == m2; case _: false; }
            case ReprType.Static(e1): switch (b) { case ReprType.Static(e2): reprEquals(e1, e2); case _: false; }
        };
    }

    public static function roleToString(role:RepresentationRole):String {
        return switch (role) {
            case RepresentationRole.Value: "Value";
            case RepresentationRole.ClassHandle: "ClassHandle";
            case RepresentationRole.TraitHandle: "TraitHandle";
            case RepresentationRole.AdapterHandle: "AdapterHandle";
            case RepresentationRole.TraitHandleAdapter: "TraitHandleAdapter";
            case RepresentationRole.ReadBorrow: "ReadBorrow";
            case RepresentationRole.WriteBorrow: "WriteBorrow";
        };
    }

    public static function receiverAbiToString(abi:ReceiverAbi):String {
        return switch (abi) {
            case ReceiverAbi.None: "None";
            case ReceiverAbi.SharedHandle: "SharedHandle";
        };
    }

    public static function paramModeToString(mode:ParamMode):String {
        return switch (mode) {
            case ParamMode.Owned: "Owned";
            case ParamMode.SharedRef: "SharedRef";
            case ParamMode.MutableRef: "MutableRef";
            case ParamMode.HandleClone: "HandleClone";
        };
    }

    /**
        classifyRoot: derive the root place classification of a mutation
        target from the declared policy domains (spec 9.2). This is the single
        authority for whether a root is a place or a DetachedCopy; the planner
        never hardcodes isPlace. A missing declaration (Unknown) fails closed
        with verified=false so requirePlacePlan rejects before generation.
        (PlacePolicy)

        @param repr the root's representation (ReprType).
        @param isStatic true when the root is a static-field slot (FStatic).
        @param isNullable true when the root slot is Nullable.
    **/
    public static function classifyRoot(repr:ReprType, isStatic:Bool, isNullable:Bool):{isPlace:Bool, kind:String, verified:Bool, domain:String, reason:String} {
        // A static-field root's place-ness is declared by staticStorage, not
        // guessed from final/name/text (spec 9.4).
        if (isStatic) {
            return switch (repr) {
                case ReprType.Static(inner):
                    switch (staticStorageFor(inner)) {
                        case StaticStorage.MutablePlace:
                            { isPlace: true, kind: "PreserveLocation", verified: true, domain: "staticStorage", reason: "staticStorage=MutablePlace" };
                        case StaticStorage.RuntimeGuardedPlace:
                            { isPlace: true, kind: "PreserveLocation", verified: true, domain: "staticStorage", reason: "staticStorage=RuntimeGuardedPlace (runtime access contract required)" };
                        case StaticStorage.Immutable:
                            { isPlace: false, kind: "DetachedValueWithWriteback", verified: true, domain: "staticStorage", reason: "staticStorage=Immutable: static subscript write rejected" };
                        case StaticStorage.ReadOnlyView:
                            { isPlace: false, kind: "DetachedValueWithWriteback", verified: true, domain: "staticStorage", reason: "staticStorage=ReadOnlyView: static subscript write rejected" };
                        case StaticStorage.Unknown:
                            { isPlace: false, kind: "DetachedValueWithWriteback", verified: false, domain: "staticStorage", reason: "staticStorage=Unknown: cannot classify static mutation target" };
                    }
                case _:
                    { isPlace: false, kind: "DetachedValueWithWriteback", verified: false, domain: "staticStorage", reason: "static root has no Static repr: cannot classify" };
            };
        }

        // A nullable root's place-ness is declared by nullableProjection.
        if (isNullable) {
            return switch (repr) {
                case ReprType.Nullable(inner):
                    switch (nullableProjectionFor(inner)) {
                        case NullableProjection.PreservePresence | NullableProjection.UnwrapBorrow:
                            { isPlace: true, kind: "PreserveLocation", verified: true, domain: "nullableProjection", reason: "nullableProjection preserves the underlying place" };
                        case NullableProjection.WritebackRequired:
                            { isPlace: false, kind: "DetachedValueWithWriteback", verified: true, domain: "nullableProjection", reason: "nullableProjection=WritebackRequired: value payload needs explicit writeback" };
                        case NullableProjection.NonPlace:
                            { isPlace: false, kind: "DetachedValueWithWriteback", verified: true, domain: "nullableProjection", reason: "nullableProjection=NonPlace: nullable unwrap yields a non-place" };
                        case NullableProjection.Unknown:
                            { isPlace: false, kind: "DetachedValueWithWriteback", verified: false, domain: "nullableProjection", reason: "nullableProjection=Unknown: cannot classify nullable mutation target" };
                    }
                case _:
                    { isPlace: false, kind: "DetachedValueWithWriteback", verified: false, domain: "nullableProjection", reason: "nullable root has no Nullable repr: cannot classify" };
            };
        }

        // A non-static, non-nullable root: classify by placeCapability.
        return switch (placeCapabilityFor(repr)) {
            case PlaceCapability.Place:
                { isPlace: true, kind: "PreserveLocation", verified: true, domain: "placeCapability", reason: "placeCapability=Place" };
            case PlaceCapability.Conditional:
                { isPlace: true, kind: "PreserveLocation", verified: true, domain: "placeCapability", reason: "placeCapability=Conditional" };
            case PlaceCapability.NonPlace:
                { isPlace: false, kind: "DetachedValueWithWriteback", verified: true, domain: "placeCapability", reason: "placeCapability=NonPlace: root is a detached value" };
            case PlaceCapability.Unknown:
                { isPlace: false, kind: "DetachedValueWithWriteback", verified: false, domain: "placeCapability", reason: "placeCapability=Unknown: cannot classify mutation target" };
        };
    }

    /** Declared staticStorage for a static-field inner repr. (PlacePolicy) */
    public static function staticStorageFor(inner:ReprType):StaticStorage {
        return switch (inner) {
            case ReprType.Copy | ReprType.ImmutableValue | ReprType.Collection(_):
                StaticStorage.MutablePlace;
            case ReprType.Handle(_, _, _):
                StaticStorage.RuntimeGuardedPlace;
            case ReprType.Static(_):
                StaticStorage.Unknown;
            case ReprType.Nullable(_):
                StaticStorage.Unknown;
            case ReprType.Function(_, _, _, _):
                StaticStorage.Unknown;
        };
    }

    /** Declared nullableProjection for a nullable inner repr. (PlacePolicy) */
    public static function nullableProjectionFor(inner:ReprType):NullableProjection {
        return switch (inner) {
            case ReprType.Handle(_, _, _):
                NullableProjection.UnwrapBorrow;
            case ReprType.Copy | ReprType.ImmutableValue:
                NullableProjection.PreservePresence;
            case ReprType.Collection(_):
                // An AssignSlot write borrows the real storage (UnwrapBorrow);
                // a ReadValue read preserves presence. The root of a mutation
                // is always AssignSlot/MutateReferent, so a Collection inner
                // unwraps to the mutable storage. (PlacePolicy)
                NullableProjection.UnwrapBorrow;
            case ReprType.Nullable(_):
                NullableProjection.Unknown;
            case ReprType.Static(_):
                NullableProjection.Unknown;
            case ReprType.Function(_, _, _, _):
                NullableProjection.Unknown;
        };
    }

    /** Declared placeCapability for a non-static, non-nullable repr. (PlacePolicy) */
    public static function placeCapabilityFor(repr:ReprType):PlaceCapability {
        return switch (repr) {
            case ReprType.Copy | ReprType.ImmutableValue | ReprType.Collection(_):
                PlaceCapability.Place;
            case ReprType.Handle(_, _, _):
                PlaceCapability.Place;
            case ReprType.Static(_):
                PlaceCapability.Unknown;
            case ReprType.Nullable(_):
                PlaceCapability.Unknown;
            case ReprType.Function(_, _, _, _):
                PlaceCapability.Place;
        };
    }
}

