package;

/**
    Float Precision Policy: the executable encoding of the cross-target
    float-precision specification (docs/specs/float-precision-policy.md, FP-n
    entries). A sibling policy to SemanticPolicy, never part of
    RepresentationRole: FP-n and P-n are independent namespaces.

    The policy does not decide Haxe source semantics. It maps "known source
    numeric semantics + target and precision mode + operation context" onto a
    verifiable representation and conversion plan. decide() consumes facts,
    never source text.

    v1 declares mixed precision: Value follows the precision mode, Accumulator
    is always binary64 and narrows exactly once on exit, Wire and NumericHelper
    widths are declared, never mode-derived. A strict-f32 switch rewrites the
    Accumulator rule to ValuePrecision explicitly; it is never a silent
    default and Accumulator never inherits Value behavior by omission.

    This round: types + decide/explain skeleton. The emitter is not wired.
**/

/** The precision mode of the compilation (FP-1). */
enum PrecisionLane {
    /** binary32 Value storage; accumulators stay binary64 under v1 mixed. */
    F32;
    /** binary64 Value storage (the absent-define default). */
    F64;
}

/**
    The six precision roles (FP-1..FP-6). Narrow/Widen are conversion plans
    between roles, never roles themselves. Constructors are prefixed to stay
    disjoint from PrecisionContext constructors (one global enum namespace).
**/
enum PrecisionRole {
    /** FP-1: Float value/field/param/return/container element; the mode decides width. */
    RoleValue;
    /** FP-2: named or identified accumulation state; binary64 under v1 mixed. */
    RoleAccumulator;
    /** FP-3: matching-width unsigned ints and bitcast/NaN bit constants. */
    RoleBits;
    /** FP-4: protocol-fixed width; never mode-derived. */
    RoleWire;
    /** FP-5: parse/format/protocol helpers with their own explicit signatures. */
    RoleNumericHelper;
    /** FP-6: the Haxe Int->Float conversion; its result is a Value (FP-1). */
    RoleIntToFloat;
}

/** The operation a node performs (the request verb). */
enum PrecisionOperation {
    Literal;
    Arithmetic;
    Intrinsic;
    Store;
    Return;
    Parse;
    Format;
    Encode;
    Decode;
    Cast;
}

/** The operation context the request arrives in. */
enum PrecisionContext {
    /** an ordinary value-position site (FP-1). */
    CtxValue;
    /** an accumulation site named or identified upstream (FP-2). */
    CtxAccumulator;
    /** a wire-format site (FP-4). */
    CtxWire;
    /** inside a parse/format/protocol helper (FP-5). */
    CtxNumericHelper;
}

/**
    One registered conversion between two roles (Narrow/Widen/Bitcast/
    Encode/Decode/IntToFloat). Same fail-closed shape as
    SemanticPolicy.ConversionEdge: an edge the validator does not recognize is
    a failure, never a silent guess.
**/
typedef PrecisionConversionEdge = {
    var from:PrecisionRole;
    var to:PrecisionRole;
    /** Narrow | Widen | Bitcast | Encode | Decode | IntToFloat. */
    var kind:String;
    /** the declared rounding behavior; "none" when exact. */
    var rounding:String;
    var policyId:String;
    var provenance:String;
}

/**
    The facts decide() consumes. Every field is produced upstream; decide()
    performs no source-type resolution and never reads source text.
**/
typedef PrecisionRequest = {
    /** target identifier (e.g. "rust", "kotlin", "ts"). Diagnostic only. */
    var target:String;
    var precisionLane:PrecisionLane;
    /** the known source numeric type fact, e.g. "Float", "Int", "u32"; null when unresolved. */
    var sourceType:Null<String>;
    var operation:PrecisionOperation;
    var context:PrecisionContext;
    /** the destination slot description, when known (field/param/return/wire field). */
    var destination:Null<String>;
    /** accumulator identity for FP-2 sites; null elsewhere. */
    var accumulatorId:Null<String>;
    /** the operations an accumulator or helper allows; null when unrestricted. */
    var allowedOps:Null<Array<String>>;
    /** the IR node id this request belongs to (diagnostics + validator join). */
    var nodeId:Null<String>;
}

/**
    The single float-precision decision for one node. A renderer may only print
    an already-resolved plan, never re-decide a width.
**/
typedef PrecisionPlan = {
    var role:PrecisionRole;
    var storageType:String;
    var computeType:String;
    var bitsType:String;
    var literalSuffix:String;
    var conversionEdges:Array<PrecisionConversionEdge>;
    /** the single rounding point the plan declares, or "none". */
    var roundingPoint:String;
    /** human-readable allowance line; empty when unrestricted. */
    var operationAllowance:String;
    var ruleIds:Array<String>;
    var provenance:String;
    var planKey:String;
    /** non-empty when no plan could be produced (fail closed). */
    var failureReason:String;
}

/** The result of one decide() call: a plan, or a named failure. */
typedef PrecisionPlanResult = {
    var ok:Bool;
    var plan:Null<PrecisionPlan>;
    /** the failure reason when ok is false; "" otherwise. */
    var failureReason:String;
}

class FloatPrecisionPolicy {
    /** Normative version 1.0.0 draft (Astra design; TL sign-off pending). */
    public static final VERSION:String = "1.0.0";

    /** Governing document, repository-relative. */
    public static final DOC_PATH:String = "docs/specs/float-precision-policy.md";

    /** Policy entry ids in DOC_PATH, in document order. */
    public static final ENTRY_VALUE:String = "FP-1";
    public static final ENTRY_ACCUMULATOR:String = "FP-2";
    public static final ENTRY_BITS:String = "FP-3";
    public static final ENTRY_WIRE:String = "FP-4";
    public static final ENTRY_NUMERIC_HELPER:String = "FP-5";
    public static final ENTRY_INT_TO_FLOAT:String = "FP-6";

    /** Every policy entry id in document order. */
    public static function entryIds():Array<String> {
        return [
            ENTRY_VALUE,
            ENTRY_ACCUMULATOR,
            ENTRY_BITS,
            ENTRY_WIRE,
            ENTRY_NUMERIC_HELPER,
            ENTRY_INT_TO_FLOAT
        ];
    }

    /**
        The single float-precision decision for one node.

        Skeleton judgment order:
          1. completeness: unresolved facts fail closed (UnknownInput).
          2. context routes the role: Accumulator > Wire > NumericHelper > Value.
          3. the precision mode decides Value width; Accumulator is binary64 under v1 mixed.
          4. the operation + source fact add the IntToFloat / wire edges.
          5. the accumulator exit is exactly one Narrow (validator-enforced).

        Conflict priority: declared accumulator identity > context > precision mode >
        operation. A conflict is a failure reason, never a silent tie-break.
    **/
    public static function decide(request:PrecisionRequest):PrecisionPlanResult {
        if (request == null || request.precisionLane == null || request.operation == null || request.context == null) {
            return fail("UnknownInput: request facts incomplete");
        }
        if (request.context == PrecisionContext.CtxAccumulator && (request.accumulatorId == null || request.accumulatorId == "")) {
            return fail("UnknownInput: accumulator context without accumulatorId (FP-2)");
        }
        final plan = basePlan();
        switch (request.context) {
            case PrecisionContext.CtxAccumulator:
                // FP-2: binary64 under v1 mixed, never mode-derived.
                plan.role = PrecisionRole.RoleAccumulator;
                plan.storageType = "f64";
                plan.computeType = "f64";
                plan.bitsType = "u64";
                plan.ruleIds = [ENTRY_ACCUMULATOR];
                plan.operationAllowance = "binary64 accumulation only; exactly one Narrow on exit";
                plan.roundingPoint = "exit Narrow (round-to-nearest)";
            case PrecisionContext.CtxWire:
                // FP-4: the protocol declares the width; the precision mode never changes it.
                plan.role = PrecisionRole.RoleWire;
                plan.storageType = "wire-f32"; // TODO: protocol-declared width input, never a default guess
                plan.computeType = plan.storageType;
                plan.bitsType = "u32";
                plan.ruleIds = [ENTRY_WIRE];
                plan.operationAllowance = "encode/decode at declared width only";
                plan.roundingPoint = "encode of f32 (round-to-nearest)";
            case PrecisionContext.CtxNumericHelper:
                // FP-5: the helper explicit signature decides; never the caller's precision mode.
                plan.role = PrecisionRole.RoleNumericHelper;
                plan.storageType = ""; // TODO: helper signature input
                plan.computeType = plan.storageType;
                plan.bitsType = "";
                plan.ruleIds = [ENTRY_NUMERIC_HELPER];
                plan.operationAllowance = "declared parse/format/encode/decode only";
                plan.roundingPoint = "as declared by the helper signature";
            case PrecisionContext.CtxValue:
                // FP-1: the precision mode decides Value width; compute at storage width.
                final isF32 = request.precisionLane == PrecisionLane.F32;
                plan.role = PrecisionRole.RoleValue;
                plan.storageType = isF32 ? "f32" : "f64";
                plan.computeType = plan.storageType;
                plan.bitsType = isF32 ? "u32" : "u64";
                plan.ruleIds = [ENTRY_VALUE];
                plan.operationAllowance = "arithmetic/comparison/storage at storage width only";
                plan.roundingPoint = "none";
        }
        // Conversion edges derived from the operation + source fact.
        switch (request.operation) {
            case PrecisionOperation.Cast:
                if (request.sourceType == "Int") {
                    // FP-6: exact Int->Float; the result is a Value at the mode's width.
                    plan.conversionEdges.push({
                        from: PrecisionRole.RoleValue,
                        to: PrecisionRole.RoleIntToFloat,
                        kind: "IntToFloat",
                        rounding: "none",
                        policyId: ENTRY_INT_TO_FLOAT,
                        provenance: provenance()
                    });
                    plan.role = PrecisionRole.RoleValue;
                    plan.ruleIds = dedupe(plan.ruleIds.concat([ENTRY_INT_TO_FLOAT]));
                }
            case PrecisionOperation.Encode | PrecisionOperation.Decode:
                plan.ruleIds = dedupe(plan.ruleIds.concat([ENTRY_WIRE]));
            case _:
        }
        plan.planKey = "fp-plan:" + roleToString(plan.role) + ":" + plan.storageType;
        return {ok: true, plan: plan, failureReason: ""};
    }

    /** Human-readable explanation of one plan, citing entry ids. */
    public static function explain(request:PrecisionRequest, plan:Null<PrecisionPlan>):String {
        if (plan == null) {
            return "no PrecisionPlan produced";
        }
        if (plan.failureReason != "") {
            return "[" + plan.ruleIds.join(",") + "] " + plan.failureReason;
        }
        final node = (request != null && request.nodeId != null) ? " node=" + request.nodeId : "";
        return "[" + plan.ruleIds.join(",") + "]" + node
            + " role=" + roleToString(plan.role)
            + " storage=" + plan.storageType
            + " compute=" + plan.computeType
            + " bits=" + plan.bitsType
            + " edges=" + plan.conversionEdges.length
            + " rounding=" + plan.roundingPoint;
    }

    public static function roleToString(role:PrecisionRole):String {
        return switch (role) {
            case PrecisionRole.RoleValue: "Value";
            case PrecisionRole.RoleAccumulator: "Accumulator";
            case PrecisionRole.RoleBits: "Bits";
            case PrecisionRole.RoleWire: "Wire";
            case PrecisionRole.RoleNumericHelper: "NumericHelper";
            case PrecisionRole.RoleIntToFloat: "IntToFloat";
        };
    }

    static function basePlan():PrecisionPlan {
        return {
            role: PrecisionRole.RoleValue,
            storageType: "",
            computeType: "",
            bitsType: "",
            literalSuffix: "", // TODO: target profile fills this; decide() skips it
            conversionEdges: [],
            roundingPoint: "none",
            operationAllowance: "",
            ruleIds: [],
            provenance: provenance(),
            planKey: "",
            failureReason: ""
        };
    }

    static function fail(reason:String):PrecisionPlanResult {
        final plan = basePlan();
        plan.failureReason = reason;
        return {ok: false, plan: plan, failureReason: reason};
    }

    static function provenance():String {
        return "FloatPrecisionPolicy.decide@" + VERSION;
    }

    static function dedupe(ids:Array<String>):Array<String> {
        final out:Array<String> = [];
        for (id in ids) {
            if (out.indexOf(id) == -1) {
                out.push(id);
            }
        }
        return out;
    }
}
