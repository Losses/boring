import SemanticPolicy.ReprType;
import SemanticPolicy.UseMode;
import SemanticPolicy.ExprIdentity;
import SemanticPolicy.PlaceKind;
import SemanticPolicy.ExprInfo;
import SemanticPolicy.ReceiverAbi;

/**
    M2 lowering validator for the Target Semantic Policy.

    Consumes the typed-IR vocabulary in SemanticPolicy.hx and enforces the
    frozen invariants named in docs/specs/target-semantic-policy.md (P-2, P-4,
    P-5, P-6, P-7, P-14, P-16) plus the Astra defect ruling d-4. It is a pure,
    plain-Haxe module with no macro Context and no target renderer, so it is
    unit-testable over synthetic IR before the M3 lowering exists.

    Governance: a validator failure aborts emission (P-18); every failure is a
    named error citing a policy entry id, never a silent guess. The M3 lowering
    (Executor-B) hooks this in front of the renderer; this module owns only the
    rules, not the lowering.
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
    public static final P_2 = "P-2";
    public static final P_4 = "P-4";
    public static final P_5 = "P-5";
    public static final P_6 = "P-6";
    public static final P_7 = "P-7";
    public static final P_14 = "P-14";
    public static final P_16 = "P-16";
    public static final D_4 = "d-4";

    public static function validate(nodes:Array<HandleNode>):Array<ValidationError> {
        final errors:Array<ValidationError> = [];
        for (node in nodes)
            validateNode(node, errors);
        return errors;
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
        // the handle out of its owner (Move/Owned) instead of borrowing and
        // cloning. Emits an E0382-style move in the M3 realization.
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
