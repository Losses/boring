#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;

/** Shared expression predicates and constant analyses. */
class ExpressionPredicates {
    static function stripWrap(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripWrap(inner);
            case _: e;
        };
    }

    static function stripCast(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TCast(inner, _): stripCast(inner);
            case _: e;
        };
    }

    public static function isNegativeIntLiteral(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(value)): value < 0;
            case TUnop(OpNeg, _, inner):
                switch (stripWrap(inner).expr) {
                    case TConst(TInt(value)): value > 0;
                    case _: false;
                }
            case _: false;
        };
    }

    public static function isNullExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TNull): true;
            case _: false;
        };
    }

    public static function isVarAssigned(e:TypedExpr, varId:Int):Bool {
        var found = false;
        function walk(x:TypedExpr) {
            switch (x.expr) {
                case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
                    switch (stripCast(t).expr) {
                        case TLocal(v) if (v.id == varId): found = true;
                        case _:
                    }
                // An increment or decrement reassigns the local, so the
                // declaration needs var even without a plain assignment.
                case TUnop(OpIncrement, _, t) | TUnop(OpDecrement, _, t):
                    switch (stripCast(t).expr) {
                        case TLocal(v) if (v.id == varId): found = true;
                        case _:
                    }
                case _:
            }
            TypedExprTools.iter(x, walk);
        }
        walk(e);
        return found;
    }

    public static function asciiFoldWord(name:String, args:Array<TypedExpr>):Null<{word:Int, method:String, digits:Int}> {
        if (name != "writeAscii" || args.length != 1) {
            return null;
        }
        final s = switch (args[0].expr) {
            case TConst(TString(v)): v;
            case _: return null;
        }
        if (s.length != 4 && s.length != 2) {
            return null;
        }
        var word = 0;
        for (i in 0...s.length) {
            final code = s.charCodeAt(i);
            if (code > 255) {
                return null;
            }
            word = word * 256 + code;
        }
        return {word: word, method: s.length == 4 ? "writeU32" : "writeU16", digits: s.length == 4 ? 8 : 4};
    }
}
#end
