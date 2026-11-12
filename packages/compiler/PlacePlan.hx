#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;

/**
    The single access-intent contract for a mutation or value read.

    The three axes of a write are kept separate: storage representation
    (RepresentationPlan), receiver ABI, and place/access intent. PlacePlan is
    orthogonal to RepresentationPlan; it never introduces a role that
    conflicts with ClassHandle.

    AccessIntent distinguishes a value read from a slot assignment from a
    referent mutation, so a planner can pass the target intent down the
    projection chain, with no re-derivation from rendered text.
    (PlacePlan)
**/
enum AccessIntent {
    /** The access reads the value at the place; the final projection may
        clone a non-Copy value so the read owns its copy. */
    ReadValue;
    /** The access writes a new value into the storage slot at the place;
        every intermediate projection must stay a place. */
    AssignSlot;
    /** The access mutates the object the place refers to (a method call);
        the referent identity must be preserved. */
    MutateReferent;
}

/**
    The classification of one projection step in a place chain.

    - PreserveLocation: the step keeps the storage location (a field slot, an
      array element position). Writing through it reaches the original slot.
    - PreserveReferentIdentity: the step keeps the identity of the object the
      place refers to (Rc::clone, borrow()); a copy points at the same object,
      so mutating the referent is correct.
    - DetachedValueWithWriteback: the step produced a detached value that no
      longer aliases the original storage; it is only valid if the plan carries
      complete writeback evidence.
**/
enum ProjectionKind {
    PreserveLocation;
    PreserveReferentIdentity;
    DetachedValueWithWriteback;
}

/** One projection step of a place chain, with its rendered text. */
typedef PlaceProjection = {
    var kind:ProjectionKind;
    var text:String;
}

/**
    A resolved place: a storage location (root plus projections) or an object
    identity, with the access intent and the evidence that every projection
    preserves the required relationship.
**/
typedef PlacePlan = {
    /** The rendered root expression (a local, self, static, field base). */
    var root:String;
    /** The ordered projection steps applied to the root. */
    var projections:Array<PlaceProjection>;
    /** The access intent this plan serves. */
    var intent:AccessIntent;
    /** True when the whole chain is a place: no DetachedCopy without writeback. */
    var isPlace:Bool;
    /** Writeback evidence for any DetachedValueWithWriteback step, or null. */
    var writeback:Null<String>;
    /** True when the plan has been verified against the source semantics. */
    var verified:Bool;
}

/**
    A mutation plan: the target place plus the intent and any writeback.
    A mutation is only valid when the target is a place (or carries complete
    writeback) and the intent matches the source semantics.
**/
typedef MutationPlan = {
    var target:PlacePlan;
    var intent:AccessIntent;
    var writeback:Null<String>;
    var verified:Bool;
}
#end
