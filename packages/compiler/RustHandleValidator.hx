import SemanticPolicy.ReprType;
import SemanticPolicy.UseMode;
import SemanticPolicy.ExprIdentity;
import SemanticPolicy.PlaceKind;
import SemanticPolicy.ExprInfo;
import SemanticPolicy.ReceiverAbi;
import SemanticPolicy.RepresentationRole;
import SemanticPolicy.RepresentationPlan;
import PlacePlan;
import PlacePlan.ProjectionKind;
import PlaceWritePolicy;
import SemanticPolicy.ConversionEdge;
import SemanticPolicy.ModuleContext;

/**
    M2 lowering validator for the Target Semantic Policy.

    Consumes the typed-IR vocabulary in SemanticPolicy.hx and enforces the
    frozen invariants named in docs/specs/target-semantic-policy.md (P-4,
    P-5, P-6, P-7, P-14) plus the Astra defect ruling d-4. P-2 (plain class
    handle) and P-16 (shared handle meta) have no standalone validator site: P-2
    is enforced by SemanticPolicy.roleFor(ClassHandle) + RustAbiProfile.spell +
    the P-22 plan/repr mismatch, and P-16 by the RustAbiProfile.spell sendSync
    two-way split (guarded by a dedicated contract test). It is a pure,
    plain-Haxe module with no macro Context and no target renderer, so it is
    unit-testable over synthetic IR before the M3 lowering exists.

    Governance: a validator failure aborts emission (P-18); every failure is a
    named error citing a policy entry id, never a silent guess. The M3 lowering
    (Executor-B) hooks this in front of the renderer; this module owns only the
    rules.
**/

/** Synthetic lowered-expression node kind for the M2 validator. */
enum HandleNodeKind {
    /** new X(...): the only node allowed to wrap Rc::new(RefCell::new(..)). */
    Construct;
    /** instance method call receiver.method(...). */
    MethodCall;
    /** field read expr.field. */
    FieldRead;
    /** field write expr.field = value. */
    FieldWrite;
    /** a reference to self or to a local binding that holds a handle. */
    HandleRef;
    /** a value/handle cast. */
    Cast;
    /** returning a handle or value. */
    Return;
    /** a closure capture of an enclosing binding. */
    ClosureCapture;
}

/**
    One synthetic IR expression: its ExprInfo (repr/identity/place_kind), its
    resolved use mode, and the structural links a validator invariant needs
    (receiver, operand, cast target, receiver ABI). Defaults keep a node legal
    until a case sets a violating field.
**/
class HandleNode {
    public var id:String;
    public var kind:HandleNodeKind;
    public var info:ExprInfo;
    public var mode:Null<UseMode>;
    public var receiver:Null<HandleNode>;
    public var operand:Null<HandleNode>;
    public var targetInfo:Null<ExprInfo>;
    public var receiverAbi:Null<ReceiverAbi>;
    /** true when the method takes self as &mut (forbidden for plain-class handles). */
    public var mutSelfReceiver:Bool;
    /** true when a Send/Sync bound or Arc/Mutex enters a single-thread slot. */
    public var sendSyncBound:Bool;

    /** The declaration this node belongs to; the validator groups by this for plan-key uniqueness. Null means ungrouped. */
    public var declId:String;

    /** The plan assigned to this node (P-22/P-24). Null means the node was not run through decide(). */
    public var plan:Null<RepresentationPlan>;

    /** The module context the plan was decided under (governance only; the validator checks invariance, never reads it for representation). */
    public var moduleContext:Null<ModuleContext>;

    public function new(id:String, kind:HandleNodeKind, info:ExprInfo, ?mode:UseMode) {
        this.id = id;
        this.kind = kind;
        this.info = info;
        this.mode = mode;
        this.mutSelfReceiver = false;
        this.sendSyncBound = false;
    }
}

/** One named validator failure. The entry id is cited in the task evidence. */
typedef ValidationError = {
    var entry:String;
    var expr_id:String;
    var rule:String;
    var message:String;
};

class RustHandleValidator {
    public static final P_4 = "P-4";
    public static final P_5 = "P-5";
    public static final P_6 = "P-6";
    public static final P_7 = "P-7";
    public static final P_14 = "P-14";
    public static final D_4 = "d-4";
    public static final P_22 = "P-22";
    public static final P_24 = "P-24";
    public static final P_25 = "P-25";

    public static function validate(nodes:Array<HandleNode>):Array<ValidationError> {
        final errors:Array<ValidationError> = [];
        for (node in nodes)
            validateNode(node, errors);
        return errors;
    }

    /**
        Plan-level fail-closed validation (policy entries P-22/P-24/P-25).

        Checks, in addition to the per-node invariants above:
          - missing plan: a grouped handle node with no RepresentationPlan.
          - plan/repr mismatch: the plan role disagrees with the node repr.
          - plan-key uniqueness: one declaration resolves to exactly one planKey.
          - test-module invariance: cfg(test) must not change planKey or repr.
          - adapter edge legality: every edge the plan cites must be registered.

        Every failure is a named error citing a policy entry id, never a silent
        guess. The validator never infers representation from rendered text, a
        module name, or cfg(test); it only checks that the plan agrees with the
        already-resolved representation.
    **/
    public static function validatePlans(nodes:Array<HandleNode>, ?registeredEdges:Array<ConversionEdge>):Array<ValidationError> {
        final errors:Array<ValidationError> = [];
        if (registeredEdges == null)
            registeredEdges = [];

        for (node in nodes) {
            // missing plan
            if (node.declId != null && node.plan == null && isHandle(node.info.repr))
                errors.push(planError(P_22, node, "missing plan", "a grouped handle node has no RepresentationPlan"));
            if (node.plan == null)
                continue;

            // adapter-handle escape invariant (P-22): AdapterHandle is a coercion
            // transient and must never resolve an emitted occurrence's plan.
            if (node.plan.role == RepresentationRole.AdapterHandle)
                errors.push(planError(P_22, node, "adapter handle escaped", "AdapterHandle is a coercion transient and must not appear at an emitted occurrence"));

            // plan/repr mismatch
            if (node.plan.failureReason == "") {
                final reprIsHandle = isHandle(node.info.repr);
                switch (node.plan.role) {
                    case RepresentationRole.ClassHandle | RepresentationRole.TraitHandle | RepresentationRole.TraitHandleAdapter:
                        if (!reprIsHandle)
                            errors.push(planError(P_22, node, "plan/repr mismatch", "plan role " + SemanticPolicy.roleToString(node.plan.role) + " requires a handle but the node repr is a value"));
                    case RepresentationRole.Value:
                        if (reprIsHandle)
                            errors.push(planError(P_22, node, "plan/repr mismatch", "plan role is Value but the node repr is a handle"));
                    case _: // ReadBorrow/WriteBorrow are use-mode refinements
                }
            }

            // adapter edge legality: every cited edge must be registered
            for (edge in node.plan.conversionEdges)
                if (!edgeRegistered(edge, registeredEdges))
                    errors.push(planError(P_25, node, "unregistered adapter edge", "the plan cites an unregistered conversion edge (" + edge.adapter + ")"));
        }

        // plan-key uniqueness + test-module invariance, grouped by declaration
        final byDecl = new Map<String, Array<HandleNode>>();
        for (node in nodes) {
            if (node.declId == null)
                continue;
            if (!byDecl.exists(node.declId))
                byDecl.set(node.declId, []);
            byDecl.get(node.declId).push(node);
        }
        for (declId in byDecl.keys()) {
            final group = byDecl.get(declId);
            var baseKey:String = null;
            for (node in group) {
                if (node.plan == null)
                    continue;
                if (baseKey == null) {
                    baseKey = node.plan.planKey;
                    continue;
                }
                if (node.plan.planKey != baseKey) {
                    final isCfgTest = node.moduleContext != null && node.moduleContext.isCfgTest;
                    if (isCfgTest)
                        errors.push(planError(P_24, node, "test-module invariance", "cfg(test) changed planKey for declaration " + declId + ": " + baseKey + " vs " + node.plan.planKey));
                    else
                        errors.push(planError(P_24, node, "plan-key mismatch", "declaration " + declId + " resolved to more than one planKey: " + baseKey + " vs " + node.plan.planKey));
                }
            }
        }

        return errors;
    }

    static function edgeRegistered(edge:ConversionEdge, registered:Array<ConversionEdge>):Bool {
        for (reg in registered)
            if (reg.adapter == edge.adapter && SemanticPolicy.reprEquals(reg.from, edge.from))
                return true;
        return false;
    }

    static function planError(entry:String, node:HandleNode, rule:String, message:String):ValidationError {
        return { entry: entry, expr_id: node.id, rule: rule, message: message };
    }

    /**
        Check every place plan against the mutation contract. A plan that cannot
        prove its write reaches the source location yields one error, so the
        target refuses to emit code for it, so no text patch happens later.
    **/
    public static function validatePlacePlans(plans:Array<PlacePlan>):Array<ValidationError> {
        final errors:Array<ValidationError> = [];
        for (plan in plans) {
            final failure = placePlanFailure(plan);
            if (failure != null)
                errors.push({
                    entry: "place-plan",
                    expr_id: plan.root,
                    rule: P_22,
                    message: failure,
                });
        }
        return errors;
    }

    /**
        Return the first unmet obligation of one place plan, or null when the
        plan proves that its write reaches the source location.
    **/
    public static function placePlanFailure(plan:PlacePlan):Null<String> {
        if (!plan.verified)
            return "place plan is not verified against the source semantics";
        if (!plan.isPlace && (plan.writeback == null || plan.writeback.length == 0))
            return "plan detaches a value without writeback evidence";
        for (step in plan.projections) {
            if (step.kind == DetachedValueWithWriteback && (plan.writeback == null || plan.writeback.length == 0))
                return "detached projection has no writeback evidence";
        }
        final combo = PlaceWritePolicy.forbiddenProjectionCombo(plan);
        if (combo != null)
            return combo;
        return null;
    }

    public static function hasError(errors:Array<ValidationError>, entry:String):Bool {
        for (e in errors)
            if (e.entry == entry)
                return true;
        return false;
    }

    public static function hasErrorFor(errors:Array<ValidationError>, entry:String, exprId:String):Bool {
        for (e in errors)
            if (e.entry == entry && e.expr_id == exprId)
                return true;
        return false;
    }

    /**
        Fail-closed plan access for a renderer site. Reads node.plan and throws
        with the declaration id and the site when the plan is not yet decided, so
        an ordering bug (a site reading the plan before collectHandleNode ran
        decide) surfaces as an explicit "plan not decided" error with the context,
        never a bare null dereference. This is the renderer-side counterpart of
        the validator's P-22 "missing plan" gate.
    **/
    public static function requirePlan(node:HandleNode, site:String):RepresentationPlan {
        if (node == null || node.plan == null)
            throw "plan not decided for " + (node != null ? node.declId : "<null>") + " at " + site + "; collectHandleNode must run decide before render";
        return node.plan;
    }

    public static function isHandle(r:ReprType):Bool {
        return switch (r) {
            case ReprType.Handle(_, _, _): true;
            case _: false;
        };
    }

    static function validateNode(node:HandleNode, errors:Array<ValidationError>):Void {
        checkCompleteExprInfo(node, errors);
        if (node.info == null)
            return;
        checkResolvedMode(node, errors);
        if (node.receiver != null)
            validateNode(node.receiver, errors);
        if (node.operand != null)
            validateNode(node.operand, errors);
        switch (node.kind) {
            case Construct: checkConstruction(node, errors);
            case MethodCall: checkMethodCall(node, errors);
            case FieldRead: checkFieldRead(node, errors);
            case FieldWrite: checkFieldWrite(node, errors);
            case Cast: checkCast(node, errors);
            case Return: checkReturn(node, errors);
            case ClosureCapture: checkClosureCapture(node, errors);
            case HandleRef: // no extra invariant
        }
        if (node.sendSyncBound)
            errors.push(error(P_14, node, "Send + Sync bound", "Send/Sync trait bound or Arc/Mutex introduced in a single-thread slot"));
    }

    static function checkCompleteExprInfo(node:HandleNode, errors:Array<ValidationError>):Void {
        if (node.info == null || node.info.repr == null || node.info.identity == null || node.info.place_kind == null)
            errors.push(error(P_6, node, "incomplete ExprInfo", "expression missing repr/identity/place_kind"));
    }

    static function checkResolvedMode(node:HandleNode, errors:Array<ValidationError>):Void {
        if (node.mode == null)
            errors.push(error(P_5, node, "unresolved mode", "use mode is unresolved"));
    }

    static function checkConstruction(node:HandleNode, errors:Array<ValidationError>):Void {
        // P-7: Rc::new(RefCell::new(..)) only at a FreshObject node.
        if (node.info.identity != ExprIdentity.FreshObject)
            errors.push(error(P_7, node, "Rc::new(RefCell::new(..))", "construction outside a FreshObject node"));
        // P-7: the operand is neither self nor an existing class handle.
        if (node.operand != null && node.operand.info != null) {
            switch (node.operand.info.identity) {
                case ExprIdentity.SelfHandle:
                    errors.push(error(P_7, node, "self rewrap", "construction operand is self"));
                case ExprIdentity.LocalHandle | ExprIdentity.FieldHandle | ExprIdentity.BorrowedProjection:
                    errors.push(error(P_7, node, "self rewrap", "construction operand is an existing handle"));
                case _: // FreshObject or null identity
            }
        }
        // d-4: Rc-wrapped Value - a Construct whose repr is not a Handle.
        switch (node.info.repr) {
            case ReprType.Handle(_, _, _):
            case _:
                errors.push(error(D_4, node, "Rc-wrapped Value", "construction repr is not a Handle"));
        }
    }

    static function checkMethodCall(node:HandleNode, errors:Array<ValidationError>):Void {
        if (node.receiver == null) {
            errors.push(error(P_4, node, "receiver ABI", "instance method call has no receiver"));
            return;
        }
        final recv = node.receiver;
        if (recv.info != null) {
            switch (recv.info.identity) {
                case ExprIdentity.FreshObject:
                    errors.push(error(P_4, node, "receiver ABI", "method receiver is a fresh object (rebuilt handle)"));
                case ExprIdentity.SelfHandle | ExprIdentity.LocalHandle | ExprIdentity.FieldHandle | ExprIdentity.BorrowedProjection:
                    switch (recv.info.repr) {
                        case ReprType.Handle(_, _, _):
                        case _:
                            errors.push(error(P_4, node, "receiver ABI", "method receiver is not a handle"));
                    }
                case _: // null identity is already a P-6 error
            }
        }
        // P-4: &mut self receivers are rejected.
        if (node.mutSelfReceiver)
            errors.push(error(P_4, node, "&mut self receiver", "mutable self receiver is forbidden"));
    }

    static function checkFieldRead(node:HandleNode, errors:Array<ValidationError>):Void {
        // d-4: unborrowed handle field - a handle-typed field read that moves
        // the handle out of its owner (Move/Owned). Emits an E0382-style move
        // in the M3 realization.
        switch (node.info.repr) {
            case ReprType.Handle(_, _, _):
                if (node.mode == UseMode.Move || node.mode == UseMode.Owned)
                    errors.push(error(D_4, node, "unborrowed handle field", "handle-typed field read moves the handle instead of borrowing"));
            case _:
        }
    }

    static function checkFieldWrite(node:HandleNode, errors:Array<ValidationError>):Void {
        // A handle field write that re-wraps self is caught on the operand's
        // Construct node (P-7); nothing extra is needed at the write site.
    }

    static function checkCast(node:HandleNode, errors:Array<ValidationError>):Void {
        if (node.operand == null || node.operand.info == null || node.targetInfo == null) {
            errors.push(error(D_4, node, "Value cast", "cast node missing operand or target repr"));
            return;
        }
        final srcHandle = isHandle(node.operand.info.repr);
        final dstHandle = isHandle(node.targetInfo.repr);
        if (srcHandle != dstHandle)
            errors.push(error(D_4, node, "Value cast", "cast across the handle/value boundary is forbidden"));
    }

    static function checkReturn(node:HandleNode, errors:Array<ValidationError>):Void {
        if (node.operand != null && node.operand.info != null) {
            switch (node.operand.info.identity) {
                case ExprIdentity.SelfHandle:
                    errors.push(error(P_7, node, "self rewrap", "returned handle re-wraps self"));
                case _:
            }
        }
    }

    static function checkClosureCapture(node:HandleNode, errors:Array<ValidationError>):Void {
        if (node.operand != null && node.operand.info != null) {
            switch (node.operand.info.identity) {
                case ExprIdentity.SelfHandle:
                    errors.push(error(P_7, node, "self rewrap", "closure capture re-wraps self"));
                case _:
            }
        }
    }

    static function error(entry:String, node:HandleNode, rule:String, message:String):ValidationError {
        return { entry: entry, expr_id: node.id, rule: rule, message: message };
    }
}
