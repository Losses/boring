#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
    Shared control-termination analysis for target emitters. Keeping this
    mechanism in the compiler layer prevents per-target copies from drifting;
    the user ruling of 2026-09-05 places cross-target semantic mechanisms here.
**/
class TerminationAnalysis {
    /** Whether control never falls through an expression. */
    public static function alwaysTerminates(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TReturn(_) | TThrow(_) | TBreak | TContinue: true;
            case TBlock(stmts): blockTerminates(stmts);
            case TIf(_, t, f) if (f != null): alwaysTerminates(t) && alwaysTerminates(f);
            case _: false;
        };
    }

    /** Whether one of the statements ends control before the block ends. */
    public static function blockTerminates(stmts:Array<TypedExpr>):Bool {
        for (s in stmts) {
            if (alwaysTerminates(s))
                return true;
        }
        return false;
    }

    static function stripWrap(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): stripWrap(inner);
            case _: e;
        };
    }
}
#end
