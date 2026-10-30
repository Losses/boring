package;

import SemanticPolicy;
import SemanticPolicy.ReprType;
import SemanticPolicy.UseMode;
import SemanticPolicy.ExprIdentity;
import SemanticPolicy.PlaceKind;
import SemanticPolicy.ExprInfo;
import SemanticPolicy.ReceiverAbi;
import SemanticPolicy.ParamMode;
import SemanticPolicy.Nullability;
import SemanticPolicy.FunctionMutability;
import RustHandleValidator;
import RustHandleTrace;
import RustHandleValidator.HandleNode;
import RustHandleValidator.HandleNodeKind;

/**
    Unit contract for the Target Semantic Policy typed-IR vocabulary.

    Plain-Haxe assertions over the shared contract types. It does not touch the
    macro Context or a target renderer: it proves that the frozen variant sets
    exist, are constructible, and that the policy-entry ids are complete and
    duplicate-free, so the document and the contract stay in step.

    Extended with the M2 validator contract (RustHandleValidator) and the
    machine-readable trace (RustHandleTrace): the validator invariants
    (P-2/P-4/P-5/P-6/P-7/P-14/P-16, d-4), the synthetic positive/negative IR
    cases aligned to the fixture matrix, and the jsonl trace serialization.

    Run: haxe tests/haxe/semantic-policy/contract.hxml
**/
class SemanticPolicyContract {
    static var failures:Int = 0;
    static var checks:Int = 0;

    public static function main():Void {
        checkVersionAndGovernance();
        checkEntryIds();
        checkReprType();
        checkUseMode();
        checkIdentityAndPlace();
        checkExprInfo();
        checkReceiverAbi();
        checkParamMode();
        checkValidator();
        checkValidatorCases();
        checkTrace();

        Sys.println("checks=" + checks + " failures=" + failures);
        Sys.exit(failures == 0 ? 0 : 1);
    }

    static function check(cond:Bool, what:String):Void {
        checks++;
        if (!cond) {
            failures++;
            Sys.println("FAIL: " + what);
        }
    }

    static function checkVersionAndGovernance():Void {
        check(SemanticPolicy.VERSION == "1.0.2", "VERSION is the released version (TL sign-off)");
        check(SemanticPolicy.DOC_PATH == "docs/specs/target-semantic-policy.md", "DOC_PATH names the governing doc");
        check(SemanticPolicy.OWNER == "Executor-B", "owner is the executor");
        check(SemanticPolicy.SIGN_OFF == "TL", "sign-off is the TL");
        check(SemanticPolicy.ARBITRATOR.indexOf("Astra") >= 0, "arbitrator is Astra");
    }

    static function checkEntryIds():Void {
        final ids = SemanticPolicy.entryIds();
        check(ids.length == 21, "exactly 21 policy entries, got " + ids.length);
        final seen = new Map<String, Bool>();
        for (i in 0...ids.length) {
            final id = ids[i];
            check(StringTools.startsWith(id, "P-"), "entry " + i + " uses the P- prefix: " + id);
            check(!seen.exists(id), "entry id unique: " + id);
            seen.set(id, true);
        }
        check(ids[0] == "P-1" && ids[ids.length - 1] == "P-20a", "entry ids run P-1..P-20a");
    }

    static function checkReprType():Void {
        final copy:ReprType = ReprType.Copy;
        final imm:ReprType = ReprType.ImmutableValue;
        final plain:ReprType = ReprType.Handle("tests.Counter", Nullability.NonNull, false);
        final nullable:ReprType = ReprType.Handle("tests.Counter", Nullability.Nullable, false);
        final shared:ReprType = ReprType.Handle("tests.ISharedCounter", Nullability.NonNull, true);
        final coll:ReprType = ReprType.Collection(ReprType.Copy);
        final nullableValue:ReprType = ReprType.Nullable(ReprType.Copy);
        final fn:ReprType = ReprType.Function(
            [ReprType.Copy],
            ReprType.Copy,
            FunctionMutability.FnMut,
            [ReprType.Handle("tests.Counter", Nullability.NonNull, false)]
        );
        final stat:ReprType = ReprType.Static(ReprType.Handle("tests.Counter", Nullability.NonNull, false));

        check(copy == ReprType.Copy, "Copy variant constructible");
        check(imm == ReprType.ImmutableValue, "ImmutableValue variant constructible");
        switch (plain) {
            case ReprType.Handle(id, n, s):
                check(id == "tests.Counter" && n == Nullability.NonNull && s == false, "plain-class handle fields");
            case _: check(false, "plain-class handle is a Handle");
        }
        switch (nullable) {
            case ReprType.Handle(_, n, _):
                check(n == Nullability.Nullable, "nullable handle folds nullability into Handle");
            case _: check(false, "nullable handle is a Handle");
        }
        switch (shared) {
            case ReprType.Handle(_, _, s):
                check(s == true, "shared handle carries shared=true (alias obligation)");
            case _: check(false, "shared handle is a Handle");
        }
        switch (coll) {
            case ReprType.Collection(e): check(e == ReprType.Copy, "collection carries its element repr");
            case _: check(false, "collection is a Collection");
        }
        switch (nullableValue) {
            case ReprType.Nullable(e): check(e == ReprType.Copy, "nullable value wraps a value repr");
            case _: check(false, "nullable value is a Nullable");
        }
        switch (fn) {
            case ReprType.Function(args, result, mut, caps):
                check(args.length == 1 && args[0] == ReprType.Copy, "function carries parameter reprs");
                check(result == ReprType.Copy, "function carries its result repr");
                check(mut == FunctionMutability.FnMut, "function mutability is FnMut by default");
                check(caps.length == 1, "function carries its captured reprs");
            case _: check(false, "function is a Function{args,result,mutability,captures}");
        }
        check(FunctionMutability.FnMut != FunctionMutability.Fn, "FnMut and Fn mutability are distinct");
        switch (stat) {
            case ReprType.Static(_): check(true, "Static variant constructible");
            case _: check(false, "static state is a Static");
        }
    }

    static function checkUseMode():Void {
        check(UseMode.Owned != UseMode.Move, "Owned and Move are distinct modes");
        check(UseMode.SharedRef != UseMode.HandleClone, "SharedRef and HandleClone are distinct");
        check(UseMode.ReadBorrow != UseMode.WriteBorrow, "ReadBorrow and WriteBorrow are distinct");
        check(UseMode.HandleClone != UseMode.FunctionHandleClone, "HandleClone and FunctionHandleClone are distinct");
        check(UseMode.Call != UseMode.ReadBorrow, "Call is a distinct mode");
        final primitives:Array<String> = [
            "handle_clone", "borrow_read", "borrow_write", "call_receiver",
            "function_handle_clone", "function_call"
        ];
        check(primitives.length == 6, "exactly six render primitives are sanctioned");
    }

    static function checkIdentityAndPlace():Void {
        check(ExprIdentity.SelfHandle != ExprIdentity.FreshObject, "SelfHandle and FreshObject are distinct identities");
        check(ExprIdentity.LocalHandle != ExprIdentity.FieldHandle, "LocalHandle and FieldHandle are distinct");
        check(ExprIdentity.BorrowedProjection != ExprIdentity.FreshObject, "BorrowedProjection and FreshObject are distinct");
        check(PlaceKind.Value != PlaceKind.Field, "Value and Field place kinds are distinct");
        check(PlaceKind.Static != PlaceKind.Local, "Static and Local place kinds are distinct");
    }

    static function checkExprInfo():Void {
        final info:ExprInfo = {
            repr: ReprType.Handle("tests.Counter", Nullability.NonNull, false),
            identity: ExprIdentity.LocalHandle,
            place_kind: PlaceKind.Local
        };
        check(info.repr != null && info.identity == ExprIdentity.LocalHandle && info.place_kind == PlaceKind.Local,
            "ExprInfo composes repr + identity + place_kind");
    }

    static function checkReceiverAbi():Void {
        check(ReceiverAbi.None != ReceiverAbi.SharedHandle, "None and SharedHandle receiver ABIs are distinct");
    }

    static function checkParamMode():Void {
        check(ParamMode.Owned != ParamMode.HandleClone, "Owned and HandleClone param modes are distinct");
        check(ParamMode.SharedRef != ParamMode.MutableRef, "SharedRef and MutableRef param modes are distinct");
    }

    // ==== M2 validator + trace (RustHandleValidator / RustHandleTrace) ====

    static function mk(id:String, kind:HandleNodeKind, repr:ReprType, identity:ExprIdentity, place:PlaceKind, mode:Null<UseMode>):HandleNode {
        return new HandleNode(id, kind, { repr: repr, identity: identity, place_kind: place }, mode);
    }

    static function checkValidator():Void {
        final missingIdentity = mk("v-missing-identity", HandleNodeKind.HandleRef, ReprType.Copy, null, PlaceKind.Value, UseMode.Owned);
        check(RustHandleValidator.hasError(RustHandleValidator.validate([missingIdentity]), "P-6"), "validator P-6: missing identity rejected");

        final unresolved = mk("v-unresolved", HandleNodeKind.HandleRef, ReprType.Copy, ExprIdentity.LocalHandle, PlaceKind.Local, null);
        check(RustHandleValidator.hasError(RustHandleValidator.validate([unresolved]), "P-5"), "validator P-5: unresolved mode rejected");

        final rewrap = mk("v-rewrap", HandleNodeKind.Construct, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.Owned);
        check(RustHandleValidator.hasError(RustHandleValidator.validate([rewrap]), "P-7"), "validator P-7: Construct outside FreshObject rejected");

        final selfOperand = mk("v-self-operand", HandleNodeKind.Construct, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.FreshObject, PlaceKind.Value, UseMode.Owned);
        final selfRef = mk("v-self", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.SelfHandle, PlaceKind.Local, UseMode.SharedRef);
        selfOperand.operand = selfRef;
        check(RustHandleValidator.hasError(RustHandleValidator.validate([selfOperand]), "P-7"), "validator P-7: self rewrap operand rejected");

        final nonHandleReceiver = mk("v-non-handle-receiver", HandleNodeKind.MethodCall, ReprType.Copy, ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.Call);
        final copyReceiver = mk("v-copy-receiver", HandleNodeKind.HandleRef, ReprType.Copy, ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        nonHandleReceiver.receiver = copyReceiver;
        check(RustHandleValidator.hasError(RustHandleValidator.validate([nonHandleReceiver]), "P-4"), "validator P-4: non-handle receiver rejected");

        final freshReceiver = mk("v-fresh-receiver", HandleNodeKind.MethodCall, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.Call);
        final freshObj = mk("v-fresh-obj", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.FreshObject, PlaceKind.Value, UseMode.Owned);
        freshReceiver.receiver = freshObj;
        check(RustHandleValidator.hasError(RustHandleValidator.validate([freshReceiver]), "P-4"), "validator P-4: fresh-object receiver rejected");

        final mutSelf = mk("v-mut-self", HandleNodeKind.MethodCall, ReprType.Copy, ExprIdentity.SelfHandle, PlaceKind.Value, UseMode.Call);
        final selfReceiver = mk("v-self-receiver", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.SelfHandle, PlaceKind.Local, UseMode.SharedRef);
        mutSelf.receiver = selfReceiver;
        mutSelf.mutSelfReceiver = true;
        check(RustHandleValidator.hasError(RustHandleValidator.validate([mutSelf]), "P-4"), "validator P-4: &mut self receiver rejected");

        final rcValue = mk("v-rc-value", HandleNodeKind.Construct, ReprType.Copy, ExprIdentity.FreshObject, PlaceKind.Value, UseMode.Owned);
        check(RustHandleValidator.hasError(RustHandleValidator.validate([rcValue]), "d-4"), "validator d-4: Rc-wrapped Value rejected");

        final valueCast = mk("v-value-cast", HandleNodeKind.Cast, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.HandleClone);
        final castSource = mk("v-cast-source", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        valueCast.operand = castSource;
        valueCast.targetInfo = { repr: ReprType.Copy, identity: ExprIdentity.BorrowedProjection, place_kind: PlaceKind.Value };
        check(RustHandleValidator.hasError(RustHandleValidator.validate([valueCast]), "d-4"), "validator d-4: Value cast rejected");

        final unborrowed = mk("v-unborrowed", HandleNodeKind.FieldRead, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.FieldHandle, PlaceKind.Field, UseMode.Move);
        check(RustHandleValidator.hasError(RustHandleValidator.validate([unborrowed]), "d-4"), "validator d-4: unborrowed handle field rejected");

        final sendSync = mk("v-send-sync", HandleNodeKind.HandleRef, ReprType.Handle("tests.IShared", Nullability.NonNull, true), ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        sendSync.sendSyncBound = true;
        check(RustHandleValidator.hasError(RustHandleValidator.validate([sendSync]), "P-14"), "validator P-14: Send/Sync bound rejected");
    }

    static function checkValidatorCases():Void {
        final freshConstruct = mk("p-fresh", HandleNodeKind.Construct, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.FreshObject, PlaceKind.Value, UseMode.Owned);
        check(RustHandleValidator.validate([freshConstruct]).length == 0, "positive: FreshObject Construct valid");

        final selfCall = mk("p-self-call", HandleNodeKind.MethodCall, ReprType.Copy, ExprIdentity.SelfHandle, PlaceKind.Value, UseMode.Call);
        selfCall.receiver = mk("p-self-recv", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.SelfHandle, PlaceKind.Local, UseMode.SharedRef);
        check(RustHandleValidator.validate([selfCall]).length == 0, "positive: self receiver method call valid");

        final localCall = mk("p-local-call", HandleNodeKind.MethodCall, ReprType.Copy, ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.Call);
        localCall.receiver = mk("p-local-recv", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        check(RustHandleValidator.validate([localCall]).length == 0, "positive: local receiver method call valid");

        final fieldClone = mk("p-field-clone", HandleNodeKind.FieldRead, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.FieldHandle, PlaceKind.Field, UseMode.HandleClone);
        check(RustHandleValidator.validate([fieldClone]).length == 0, "positive: handle field HandleClone valid");

        final handleCast = mk("p-handle-cast", HandleNodeKind.Cast, ReprType.Handle("tests.Speaker", Nullability.NonNull, true), ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.HandleClone);
        handleCast.operand = mk("p-handle-cast-src", HandleNodeKind.HandleRef, ReprType.Handle("tests.Speaker", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        handleCast.targetInfo = { repr: ReprType.Handle("tests.Speaker", Nullability.NonNull, true), identity: ExprIdentity.LocalHandle, place_kind: PlaceKind.Value };
        check(RustHandleValidator.validate([handleCast]).length == 0, "positive: handle-to-handle cast valid");

        final localRef = mk("p-local-ref", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        check(RustHandleValidator.validate([localRef]).length == 0, "positive: local handle reference valid");

        check(RustHandleValidator.hasError(RustHandleValidator.validate([rewrapCase()]), "P-7"), "negative: NEG-self-rewrap -> P-7");
        check(RustHandleValidator.hasError(RustHandleValidator.validate([sendSyncCase()]), "P-14"), "negative: NEG-send-sync -> P-14");
        check(RustHandleValidator.hasError(RustHandleValidator.validate([mutSelfReceiverCase()]), "P-4"), "negative: NEG-mut-self-receiver -> P-4");
        check(RustHandleValidator.hasError(RustHandleValidator.validate([rcValueCase()]), "d-4"), "negative: Rc-wrapped Value -> d-4");
        check(RustHandleValidator.hasError(RustHandleValidator.validate([valueCastCase()]), "d-4"), "negative: Value cast -> d-4");
        check(RustHandleValidator.hasError(RustHandleValidator.validate([unborrowedFieldCase()]), "d-4"), "negative: unborrowed handle field -> d-4");
        check(RustHandleValidator.hasError(RustHandleValidator.validate([unresolvedCase()]), "P-5"), "negative: unresolved mode -> P-5");
        check(RustHandleValidator.hasError(RustHandleValidator.validate([incompleteInfoCase()]), "P-6"), "negative: incomplete ExprInfo -> P-6");
    }

    static function rewrapCase():HandleNode {
        return mk("n-rewrap", HandleNodeKind.Construct, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.Owned);
    }

    static function sendSyncCase():HandleNode {
        final n = mk("n-send-sync", HandleNodeKind.HandleRef, ReprType.Handle("tests.IShared", Nullability.NonNull, true), ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        n.sendSyncBound = true;
        return n;
    }

    static function mutSelfReceiverCase():HandleNode {
        final n = mk("n-mut-self", HandleNodeKind.MethodCall, ReprType.Copy, ExprIdentity.SelfHandle, PlaceKind.Value, UseMode.Call);
        n.receiver = mk("n-mut-self-recv", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.SelfHandle, PlaceKind.Local, UseMode.SharedRef);
        n.mutSelfReceiver = true;
        return n;
    }

    static function rcValueCase():HandleNode {
        return mk("n-rc-value", HandleNodeKind.Construct, ReprType.Copy, ExprIdentity.FreshObject, PlaceKind.Value, UseMode.Owned);
    }

    static function valueCastCase():HandleNode {
        final n = mk("n-value-cast", HandleNodeKind.Cast, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Value, UseMode.HandleClone);
        n.operand = mk("n-value-cast-src", HandleNodeKind.HandleRef, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.LocalHandle, PlaceKind.Local, UseMode.SharedRef);
        n.targetInfo = { repr: ReprType.Copy, identity: ExprIdentity.BorrowedProjection, place_kind: PlaceKind.Value };
        return n;
    }

    static function unborrowedFieldCase():HandleNode {
        return mk("n-unborrowed", HandleNodeKind.FieldRead, ReprType.Handle("tests.Counter", Nullability.NonNull, false), ExprIdentity.FieldHandle, PlaceKind.Field, UseMode.Move);
    }

    static function unresolvedCase():HandleNode {
        return mk("n-unresolved", HandleNodeKind.HandleRef, ReprType.Copy, ExprIdentity.LocalHandle, PlaceKind.Local, null);
    }

    static function incompleteInfoCase():HandleNode {
        return mk("n-incomplete", HandleNodeKind.HandleRef, ReprType.Copy, null, PlaceKind.Value, UseMode.Owned);
    }

    static function checkTrace():Void {
        final info:ExprInfo = { repr: ReprType.Handle("tests.Counter", Nullability.NonNull, false), identity: ExprIdentity.LocalHandle, place_kind: PlaceKind.Local };
        final rec = RustHandleTrace.fromExpr("e1", info, UseMode.HandleClone);
        check(rec.expr_id == "e1", "trace: expr_id recorded");
        check(rec.repr == "Handle(tests.Counter,NonNull,plain)", "trace: repr serialized");
        check(rec.mode == "HandleClone", "trace: mode serialized");
        check(rec.identity == "LocalHandle", "trace: identity serialized");
        check(rec.place_kind == "Local", "trace: place_kind serialized");

        final copyInfo:ExprInfo = { repr: ReprType.Copy, identity: ExprIdentity.BorrowedProjection, place_kind: PlaceKind.Value };
        final copyRec = RustHandleTrace.fromExpr("e2", copyInfo, UseMode.ReadBorrow);
        check(copyRec.repr == "Copy" && copyRec.mode == "ReadBorrow", "trace: Copy/ReadBorrow serialized");

        final fnInfo:ExprInfo = { repr: ReprType.Function([ReprType.Copy], ReprType.Copy, FunctionMutability.FnMut, [ReprType.Handle("tests.Counter", Nullability.NonNull, false)]), identity: ExprIdentity.LocalHandle, place_kind: PlaceKind.Local };
        final fnRec = RustHandleTrace.fromExpr("e3", fnInfo, UseMode.Call);
        check(fnRec.repr == "Function([Copy]->Copy,FnMut,[Handle(tests.Counter,NonNull,plain)])", "trace: Function repr serialized");
        check(fnRec.mode == "Call", "trace: Call mode serialized");

        final jsonl = RustHandleTrace.formatJsonl([rec, copyRec]);
        final lines = jsonl.split("\n");
        check(lines.length == 2, "trace: jsonl emits one line per record");
        check(lines[0].indexOf("expr_id") >= 0 && lines[0].indexOf("e1") >= 0, "trace: jsonl first line carries expr_id");
        check(lines[1].indexOf("place_kind") >= 0 && lines[1].indexOf("Value") >= 0, "trace: jsonl second line carries place_kind");
    }
}
