#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;

/** Shared validation and normalization for expression-position blocks. */
class ExpressionBlockNorm {
    public static function normalize(stmts:Array<TypedExpr>, fail:(Null<TypedExpr>, String)->Void,
            valueMessage:(Null<TypedExpr>)->String, declarationMessage:String):Array<TypedExpr> {
        var normalized = stmts;
        var wrapped = true;
        while (wrapped && normalized.length > 0) {
            wrapped = switch (normalized[normalized.length - 1].expr) {
                case TBlock(inner):
                    normalized = normalized.slice(0, normalized.length - 1).concat(inner);
                    true;
                case _:
                    false;
            };
        }
        if (normalized.length == 0) {
            fail(null, valueMessage(null));
            return normalized;
        }
        for (i in 0...normalized.length - 1)
            switch (normalized[i].expr) {
                case TVar(_, _):
                case _:
                    fail(normalized[i], declarationMessage);
                    return normalized;
            }
        switch (normalized[normalized.length - 1].expr) {
            case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TFor(_, _, _) |
                TSwitch(_, _, _) | TTry(_, _) | TBlock(_) | TBreak | TContinue |
                TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _):
                fail(normalized[normalized.length - 1], valueMessage(normalized[normalized.length - 1]));
            case _:
        }
        return normalized;
    }
}
#end
