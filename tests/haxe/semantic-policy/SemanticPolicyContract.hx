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

/**
    Unit contract for the Target Semantic Policy typed-IR vocabulary.

    Plain-Haxe assertions over the shared contract types. It does not touch the
    macro Context or a target renderer: it proves that the frozen variant sets
    exist, are constructible, and that the policy-entry ids are complete and
    duplicate-free, so the document and the contract stay in step.

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
        check(SemanticPolicy.VERSION == "1.0.0", "VERSION is the released version (TL sign-off)");
        check(SemanticPolicy.DOC_PATH == "docs/specs/target-semantic-policy.md", "DOC_PATH names the governing doc");
        check(SemanticPolicy.OWNER == "Executor-B", "owner is the executor");
        check(SemanticPolicy.SIGN_OFF == "TL", "sign-off is the TL");
        check(SemanticPolicy.ARBITRATOR.indexOf("Astra") >= 0, "arbitrator is Astra");
    }

    static function checkEntryIds():Void {
        final ids = SemanticPolicy.entryIds();
        check(ids.length == 20, "exactly 20 policy entries, got " + ids.length);
        final seen = new Map<String, Bool>();
        for (i in 0...ids.length) {
            final id = ids[i];
            check(StringTools.startsWith(id, "P-"), "entry " + i + " uses the P- prefix: " + id);
            check(!seen.exists(id), "entry id unique: " + id);
            seen.set(id, true);
        }
        check(ids[0] == "P-1" && ids[ids.length - 1] == "P-20", "entry ids run P-1..P-20");
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
}

