import SemanticPolicy.ReprType;
import SemanticPolicy.UseMode;
import SemanticPolicy.ExprIdentity;
import SemanticPolicy.PlaceKind;
import SemanticPolicy.ExprInfo;
import SemanticPolicy.Nullability;
import SemanticPolicy.FunctionMutability;

/**
    Machine-readable trace for the Target Semantic Policy (P-19).

    One jsonl record per lowered expression: { expr_id, repr, mode, identity,
    place_kind }. The trace is target-neutral text over the typed IR, never
    rendered Rust. An expression with no trace record is a lowering error
    (P-19). The M3 lowering emits one record per expression; this module owns
    the record shape and serialization, not the lowering.
**/

typedef TraceRecord = {
    var expr_id:String;
    var repr:String;
    var mode:String;
    var identity:String;
    var place_kind:String;
};

class RustHandleTrace {
    /** Build the trace record for one expression from its ExprInfo + mode. */
    public static function fromExpr(exprId:String, info:ExprInfo, mode:Null<UseMode>):TraceRecord {
        return {
            expr_id: exprId,
            repr: reprToString(info.repr),
            mode: modeToString(mode),
            identity: identityToString(info.identity),
            place_kind: placeKindToString(info.place_kind)
        };
    }

    /** Serialize records to jsonl (one JSON object per line, canonical field order). */
    public static function formatJsonl(records:Array<TraceRecord>):String {
        final buf = new StringBuf();
        for (i in 0...records.length) {
            if (i > 0)
                buf.add("\n");
            buf.add(recordJson(records[i]));
        }
        return buf.toString();
    }

    public static function reprToString(r:ReprType):String {
        return switch (r) {
            case ReprType.Copy: "Copy";
            case ReprType.ImmutableValue: "ImmutableValue";
            case ReprType.Handle(id, n, s): "Handle(" + id + "," + (n == Nullability.Nullable ? "Nullable" : "NonNull") + "," + (s ? "shared" : "plain") + ")";
            case ReprType.Collection(e): "Collection(" + reprToString(e) + ")";
            case ReprType.Nullable(e): "Nullable(" + reprToString(e) + ")";
            case ReprType.Function(args, result, mut, caps): "Function(" + reprsToString(args) + "->" + reprToString(result) + "," + (mut == FunctionMutability.Fn ? "Fn" : "FnMut") + "," + reprsToString(caps) + ")";
            case ReprType.Static(e): "Static(" + reprToString(e) + ")";
        };
    }

    public static function modeToString(m:Null<UseMode>):String {
        if (m == null)
            return "unresolved";
        return switch (m) {
            case UseMode.Owned: "Owned";
            case UseMode.SharedRef: "SharedRef";
            case UseMode.HandleClone: "HandleClone";
            case UseMode.ReadBorrow: "ReadBorrow";
            case UseMode.WriteBorrow: "WriteBorrow";
            case UseMode.Move: "Move";
            case UseMode.FunctionHandleClone: "FunctionHandleClone";
            case UseMode.Call: "Call";
        };
    }

    public static function identityToString(i:Null<ExprIdentity>):String {
        if (i == null)
            return "missing";
        return switch (i) {
            case ExprIdentity.SelfHandle: "SelfHandle";
            case ExprIdentity.LocalHandle: "LocalHandle";
            case ExprIdentity.FieldHandle: "FieldHandle";
            case ExprIdentity.FreshObject: "FreshObject";
            case ExprIdentity.BorrowedProjection: "BorrowedProjection";
        };
    }

    public static function placeKindToString(p:Null<PlaceKind>):String {
        if (p == null)
            return "missing";
        return switch (p) {
            case PlaceKind.Value: "Value";
            case PlaceKind.Local: "Local";
            case PlaceKind.Field: "Field";
            case PlaceKind.Index: "Index";
            case PlaceKind.Static: "Static";
        };
    }

    static function reprsToString(list:Array<ReprType>):String {
        return "[" + [for (r in list) reprToString(r)].join(",") + "]";
    }

    static function recordJson(r:TraceRecord):String {
        return "{\"expr_id\":" + haxe.Json.stringify(r.expr_id)
            + ",\"repr\":" + haxe.Json.stringify(r.repr)
            + ",\"mode\":" + haxe.Json.stringify(r.mode)
            + ",\"identity\":" + haxe.Json.stringify(r.identity)
            + ",\"place_kind\":" + haxe.Json.stringify(r.place_kind) + "}";
    }
}
