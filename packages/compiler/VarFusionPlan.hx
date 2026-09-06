#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.Expr.Binop;

/**
    Shared analysis for fusing an uninitialized local with its first assignment.
    The acceptance rules reproduce all five target copies exactly: a `TVar(v,
    null)` is paired with the first later `TBinop(OpAssign, lhs, rhs)` whose
    unwrapped lhs is `TLocal` with the same id; declarations without such a
    pair are unchanged. Dart supplies its stripWrap operation, while Kotlin,
    Rust, Swift, and TypeScript supply stripCast. The plan contains only
    analysis results; each emitter performs the replacement and deletion and
    retains its own post-fusion mutation bookkeeping.
**/
class VarFusionPlan {
    /** Build ordered declaration/assignment pairs without mutating `stmts`. */
    public static function plan(stmts:Array<TypedExpr>, unwrap:TypedExpr->TypedExpr):Array<VarFusionPlanEntry> {
        final plans:Array<VarFusionPlanEntry> = [];
        final removed = new Map<Int, Bool>();
        for (i in 0...stmts.length) {
            if (removed.exists(i))
                continue;
            switch (stmts[i].expr) {
                case TVar(v, init) if (init == null):
                    var assignIdx = -1;
                    var rhs:Null<TypedExpr> = null;
                    for (j in (i + 1)...stmts.length) {
                        if (removed.exists(j))
                            continue;
                        switch (unwrap(stmts[j]).expr) {
                            case TBinop(OpAssign, lhs, value):
                                switch (unwrap(lhs).expr) {
                                    case TLocal(assigned) if (assigned.id == v.id):
                                        assignIdx = j;
                                        rhs = value;
                                    case _:
                                }
                            case _:
                        }
                        if (assignIdx != -1)
                            break;
                    }
                    if (assignIdx != -1 && rhs != null) {
                        plans.push({declIdx: i, assignIdx: assignIdx, varId: v.id, rhs: rhs});
                        removed.set(assignIdx, true);
                    }
                case _:
            }
        }
        return plans;
    }
}

typedef VarFusionPlanEntry = {
    declIdx:Int,
    assignIdx:Int,
    varId:Int,
    rhs:TypedExpr
};
#end
