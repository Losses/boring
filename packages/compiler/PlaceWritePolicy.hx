#if (macro || reflaxe_runtime)
import SemanticPolicy.ReprType;
import SemanticPolicy.Nullability;
import PlacePlan.AccessIntent;
import PlacePlan.ProjectionKind;
import PlacePlan.PlaceProjection;
import PlacePlan.PlacePlan;

/**
    The write-landing and alias-capability declaration face for PlacePlan
    (policy entries P-26/P-27/P-28, declared in the same rule-id style as
    P-22).

    SemanticPolicy declares the base capability domains (StorageKind,
    CloneRelation, PlaceCapability, NullableProjection, StaticStorage); this
    module states, per (landing storage, access intent), which landings admit a
    write, which landings carry an alias-check obligation, and which projection
    combinations are structurally forbidden. The planner (RustExpr
    planPlaceChain) reads these declarations; it never invents an undeclared
    capability, and an Undeclared ruling fails closed before generation.

    This module declares only rulings over the PlacePlan vocabulary. It does
    not redefine PlacePlan types; it imports them (PlacePlan).

    Governance: mirrors SemanticPolicy - author/owner = Executor-B, sign-off =
    TL, arbitration = Astra. Every ruling cites its policy entry id, never a
    silent guess.
**/

/** The verdict for one write landing (policy entry P-26). */
enum WriteLanding {
    /** the landing is a place; a write reaches the source slot/referent. */
    Writable;
    /** the write is admissible only with complete writeback evidence. */
    WritableWithWriteback;
    /** the write requires an alias proof before it may be emitted. */
    AliasCheckRequired;
    /** the write loses the mutation at this landing; refused. */
    Forbidden;
    /** no declaration covers this landing; fails closed (P-26). */
    Undeclared;
}

/** One named write-landing ruling, citing its policy entry id. */
typedef WriteTargetRuling = {
    var landing:WriteLanding;
    /** true when emitting this write also discharges a P-27 alias obligation. */
    var needsAliasCheck:Bool;
    var policyId:String;
    var reason:String;
}

class PlaceWritePolicy {
    /** Write-landing declaration surface (this module). */
    public static final P_26 = "P-26";
    /** Alias-check obligation (P-27). */
    public static final P_27 = "P-27";
    /** Forbidden projection combination (P-28). */
    public static final P_28 = "P-28";

    /**
        The declared storage kind of a landing repr. This is the composition of
        the SemanticPolicy domains, with no new semantic: Copy/ImmutableValue and
        a Collection backing are owned value storage; a Handle is a shared
        referent; a static slot is StaticSlot; a closure environment is shared
        referent storage (FnMut). Nullable folds into its inner repr, because
        the Option wrapper itself never owns the payload storage (P-26).
    **/
    public static function storageKindFor(repr:ReprType):SemanticPolicy.StorageKind {
        return switch (repr) {
            case ReprType.Copy | ReprType.ImmutableValue | ReprType.Collection(_):
                SemanticPolicy.StorageKind.Value;
            case ReprType.Handle(_, _, _):
                SemanticPolicy.StorageKind.SharedReferent;
            case ReprType.Static(_):
                SemanticPolicy.StorageKind.StaticSlot;
            case ReprType.Nullable(inner):
                storageKindFor(inner);
            case ReprType.Function(_, _, _, _):
                SemanticPolicy.StorageKind.SharedReferent;
        };
    }

    /**
        The declared write-landing ruling for one (repr, intent) pair (P-26).

        Rulings, fail-closed:
          - AssignSlot over Value storage: Writable (placeCapability=Place).
          - AssignSlot over a Collection backing: WritableWithWriteback
            (cloneRelation=DetachedCopy; the read detaches, so the write needs
            complete writeback evidence or a place-preserving receiver).
          - AssignSlot over a SharedReferent: AliasCheckRequired (other aliases
            observe the slot write; P-27 obligation attached).
          - AssignSlot over a StaticSlot: Undeclared here; the planner must
            decide via SemanticPolicy.classifyRoot/staticStorageFor, which owns
            the isStaticFinal fact this face does not carry.
          - AssignSlot over a closure environment: Forbidden.
          - MutateReferent over a SharedReferent: Writable (handle clone keeps
            the referent identity; spec section 4).
          - MutateReferent over Value or Collection storage: WritableWithWriteback
            (the read detaches the backing value; only an operation contract
            with writeback reaches the original - spec section 5, operationContractId).
          - MutateReferent over a Nullable value payload: Forbidden (the payload
            identity is lost; NullableProjection=WritebackRequired/NonPlace).
          - ReadValue never writes: Undeclared with an explicit reason.
          - any Unknown-landing storage combination: Undeclared (fail closed;
            spec section 9.3 forbids defaulting to a place).
    **/
    public static function writeTargetFor(repr:ReprType, intent:AccessIntent):WriteTargetRuling {
        return switch (intent) {
            case AccessIntent.ReadValue:
                { landing: Undeclared, needsAliasCheck: false, policyId: P_26,
                  reason: "ReadValue never writes; no write-landing ruling applies" };
            case AccessIntent.AssignSlot:
                switch (storageKindFor(repr)) {
                    case SemanticPolicy.StorageKind.Value:
                        switch (repr) {
                            case ReprType.Collection(_):
                                { landing: WritableWithWriteback, needsAliasCheck: false, policyId: P_26,
                                  reason: "collection backing reads as DetachedCopy; AssignSlot needs writeback evidence or a place-preserving receiver" };
                            case _:
                                { landing: Writable, needsAliasCheck: false, policyId: P_26,
                                  reason: "value storage is a place (placeCapability=Place); the slot write reaches the source" };
                        }
                    case SemanticPolicy.StorageKind.SharedReferent:
                        { landing: AliasCheckRequired, needsAliasCheck: true, policyId: P_26,
                          reason: "AssignSlot over a shared referent replaces the slot; every alias observes it (P-27 obligation)" };
                    case SemanticPolicy.StorageKind.StaticSlot:
                        { landing: Undeclared, needsAliasCheck: false, policyId: P_26,
                          reason: "static landing is decided by SemanticPolicy.staticStorageFor, not by this face" };
                    case SemanticPolicy.StorageKind.BorrowedView:
                        { landing: WritableWithWriteback, needsAliasCheck: false, policyId: P_26,
                          reason: "AssignSlot over a borrowed view needs writeback to reach the lender storage" };
                    case SemanticPolicy.StorageKind.Unknown:
                        { landing: Undeclared, needsAliasCheck: false, policyId: P_26,
                          reason: "storage kind undeclared; fails closed (spec 9.3)" };
                }
            case AccessIntent.MutateReferent:
                switch (repr) {
                    case ReprType.Handle(_, _, _):
                        { landing: Writable, needsAliasCheck: false, policyId: P_26,
                          reason: "handle clone keeps the referent identity (cloneRelation=PreserveReferentIdentity); mutating the referent is correct" };
                    case ReprType.Function(_, _, _, _):
                        { landing: Writable, needsAliasCheck: false, policyId: P_26,
                          reason: "closure environment is shared referent storage (FnMut); mutating it is correct" };
                    case ReprType.Copy | ReprType.ImmutableValue | ReprType.Collection(_):
                        { landing: WritableWithWriteback, needsAliasCheck: false, policyId: P_26,
                          reason: "value/container read detaches the backing storage; only an operation contract with writeback reaches the original" };
                    case ReprType.Nullable(inner):
                        switch (inner) {
                            case ReprType.Handle(_, _, _):
                                { landing: Writable, needsAliasCheck: false, policyId: P_26,
                                  reason: "nullable handle unwrap preserves presence and the referent place (NullableProjection=PreservePresence)" };
                            case _:
                                { landing: Forbidden, needsAliasCheck: false, policyId: P_26,
                                  reason: "nullable value payload loses identity on unwrap (NullableProjection=WritebackRequired/NonPlace)" };
                        }
                    case ReprType.Static(_):
                        { landing: Undeclared, needsAliasCheck: false, policyId: P_26,
                          reason: "static landing is decided by SemanticPolicy.staticStorageFor, not by this face" };
                }
        };
    }

    /**
        The declared alias-check obligation for one (repr, intent) pair (P-27).
        True when the write is observable through a second alias the planner
        must name and prove: slot writes over shared referent storage, and
        referent mutations whose clone relation preserves identity. An unknown
        repr obliges the check too (fail closed): missing facts are unknown,
        not immutable (spec 9.3).
    **/
    public static function aliasCheckRequiredFor(repr:ReprType, intent:AccessIntent):Bool {
        return switch (intent) {
            case AccessIntent.ReadValue: false;
            case AccessIntent.AssignSlot:
                switch (storageKindFor(repr)) {
                    case SemanticPolicy.StorageKind.SharedReferent: true;
                    case SemanticPolicy.StorageKind.Unknown: true;
                    case _: false;
                }
            case AccessIntent.MutateReferent:
                switch (SemanticPolicy.cloneRelationFor(repr)) {
                    case SemanticPolicy.CloneRelation.PreserveReferentIdentity: true;
                    case SemanticPolicy.CloneRelation.Unknown: true;
                    case _: false;
                }
        };
    }

    /**
        The first forbidden projection combination in a place plan (P-28), or
        null when the chain is structurally admissible. Structural rules:

          F1: a DetachedValueWithWriteback step followed by any further
              projection step - a detached value cannot regain the source
              location or identity downstream, whatever its writeback claims.
          F2: a MutateReferent intent whose final step is Detached - the
              referent identity is lost, so the mutation never reaches the
              source object.

        These are structural contradictions over the declared projection kinds;
        the writeback-evidence gate itself stays in P-22 (placePlanFailure).
    **/
    public static function forbiddenProjectionCombo(plan:PlacePlan):Null<String> {
        final steps = plan.projections;
        for (i in 0...steps.length) {
            if (steps[i].kind == ProjectionKind.DetachedValueWithWriteback) {
                if (i + 1 < steps.length)
                    return P_28 + "/F1: projection " + steps[i + 1].text + " follows a detached step (" + steps[i].text + "); a detached value cannot regain the source location downstream";
                if (plan.intent == AccessIntent.MutateReferent)
                    return P_28 + "/F2: MutateReferent ends at a detached step (" + steps[i].text + "); the referent identity is lost and the mutation never reaches the source object";
            }
        }
        return null;
    }
}
#end
