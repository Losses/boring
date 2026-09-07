package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Binop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import PolicyQueries;

/** Rust-only fusion for locals whose first use is a total match assignment. */
class DeadInitializerMatchFusion {
    public static function fuseDeadInitializerMatch(stmts:Array<TypedExpr>, unwrap:TypedExpr->TypedExpr):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            if (i + 1 < stmts.length) {
                final declaration = stmts[i];
                switch (declaration.expr) {
                    case TVar(v, init) if (init != null && isDiscardableInitializer(unwrap(init))):
                        final following = stmts[i + 1];
                        final assigned = assignmentTo(following, v.id, unwrap);
                        if (assigned != null && !readsLocal(assigned, v.id)) {
                            out.push({expr: TVar(v, assigned), pos: declaration.pos, t: declaration.t});
                            i += 2;
                            continue;
                        }
                        final match = switch (unwrap(following).expr) {
                            case TSwitch(subj, cases, def) if (def == null && !readsLocal(subj, v.id)):
                                final fused = fusedCases(cases, v.id, unwrap);
                                fused == null ? null : {
                                    subj: subj,
                                    cases: fused,
                                    t: v.t,
                                    pos: following.pos
                                };
                            case _: null;
                        };
                        if (match != null) {
                            out.push({
                                expr: TVar(v, {expr: TSwitch(match.subj, match.cases, null), pos: match.pos, t: match.t}),
                                pos: declaration.pos,
                                t: declaration.t
                            });
                            i += 2;
                            continue;
                        }
                    case _:
                }
            }
            out.push(stmts[i]);
            i++;
        }
        return out;
    }

    static function assignmentTo(e:TypedExpr, id:Int, unwrap:TypedExpr->TypedExpr):Null<TypedExpr> {
        return switch (unwrap(e).expr) {
            case TBinop(OpAssign, lhs, rhs):
                switch (unwrap(lhs).expr) {
                    case TLocal(v) if (v.id == id): rhs;
                    case _: null;
                }
            case _: null;
        };
    }

    static function fusedCases(cases:Array<{values:Array<TypedExpr>, expr:TypedExpr}>, id:Int,
            unwrap:TypedExpr->TypedExpr):Null<Array<{values:Array<TypedExpr>, expr:TypedExpr}>> {
        final result:Array<{values:Array<TypedExpr>, expr:TypedExpr}> = [];
        for (c in cases) {
            final payload:Array<TypedExpr> = [];
            var value:Null<TypedExpr> = null;
            var valid = true;
            function visit(s:TypedExpr) {
                switch (s.expr) {
                    case TBlock(stmts):
                        for (inner in stmts)
                            visit(inner);
                    case TMeta(_, inner):
                        visit(inner);
                    case TVar(_, init) if (init != null):
                        switch (unwrap(init).expr) {
                            case TEnumParameter(_, _, _) | TLocal(_): payload.push(s);
                            case _: valid = false;
                        }
                    case _:
                        final assigned = assignmentTo(s, id, unwrap);
                        if (assigned == null || value != null || readsLocal(assigned, id)) {
                            valid = false;
                        } else {
                            value = assigned;
                        }
                }
            }
            visit(c.expr);
            if (!valid || value == null)
                return null;
            final replacement = if (payload.length == 0) value else {
                final replacementBody = payload.concat([{expr: value.expr, pos: value.pos, t: value.t}]);
                {expr: TBlock(replacementBody), pos: c.expr.pos, t: c.expr.t};
            };
            result.push({values: c.values, expr: replacement});
        }
        return result;
    }

    /** Only constant initializers may be dropped. Any other initializer can
        carry observable work or a value that later statements read through
        the local before the match runs. */
    static function isDiscardableInitializer(init:TypedExpr):Bool {
        return switch (init.expr) {
            case TConst(_): true;
            case _: false;
        };
    }

    /** The initializer is dropped by the fusion, so every consumed right
        side must not read the local it initializes. */
    static function readsLocal(e:TypedExpr, id:Int):Bool {
        var found = false;
        function scan(node:TypedExpr) {
            switch (node.expr) {
                case TLocal(v) if (v.id == id):
                    found = true;
                case _:
            }
            if (!found) {
                TypedExprTools.iter(node, scan);
            }
        }
        scan(e);
        return found;
    }
}
#end
