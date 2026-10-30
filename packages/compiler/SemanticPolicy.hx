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
    The single cross-target Target Semantic Policy contract.

    Holds the governing version, governance identity, and the policy-entry ids
    (P-n) that validators cite. Every entry id names exactly one section in
    docs/specs/target-semantic-policy.md, and every IR type above maps onto one
    or more entries, so the document and the typed contract cannot drift.
**/
class SemanticPolicy {
    /** Normative version, promoted to v1.0.0 under TL sign-off. */
    public static final VERSION:String = "1.0.0";

    /** Governing document, repository-relative. */
    public static final DOC_PATH:String = "docs/specs/target-semantic-policy.md";

    /** Governance: author/owner, sign-off, and arbitration. */
    public static final OWNER:String = "Executor-B";
    public static final SIGN_OFF:String = "TL";
    public static final ARBITRATOR:String = "Astra (lingsuan gpt-6-astra)";

    /** Policy entry ids in DOC_PATH, in document order. */
    public static final ENTRY_REPRESENTATION:String = "P-1";
    public static final ENTRY_PLAIN_CLASS_HANDLE:String = "P-2";
    public static final ENTRY_INTERFACE_HANDLE:String = "P-3";
    public static final ENTRY_RECEIVER_ABI:String = "P-4";
    public static final ENTRY_USE_MODE:String = "P-5";
    public static final ENTRY_EXPR_IDENTITY:String = "P-6";
    public static final ENTRY_CONSTRUCTION:String = "P-7";
    public static final ENTRY_PARAM_PASSING:String = "P-8";
    public static final ENTRY_RETURN:String = "P-9";
    public static final ENTRY_FIELD_ACCESS:String = "P-10";
    public static final ENTRY_CLOSURE_CAPTURE:String = "P-11";
    public static final ENTRY_NULLABLE:String = "P-12";
    public static final ENTRY_COLLECTION:String = "P-13";
    public static final ENTRY_FUNCTION:String = "P-14";
    public static final ENTRY_STATIC_STATE:String = "P-15";
    public static final ENTRY_SHARED_HANDLE_META:String = "P-16";
    public static final ENTRY_FORBIDDEN_PATTERNS:String = "P-17";
    public static final ENTRY_VALIDATOR:String = "P-18";
    public static final ENTRY_TRACE:String = "P-19";
    public static final ENTRY_WORKFLOW:String = "P-20";

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
            ENTRY_WORKFLOW
        ];
    }
}

