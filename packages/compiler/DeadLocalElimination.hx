#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type.TypedExpr;

/**
    Drops local declarations that the Haxe analyzer leaves behind when it
    inlines a read-only array literal into element locals.

    The analyzer rewrites a read-only literal local into one declaration per
    element (`var grid_0_0 = 1; var grid_0_1 = 2; ...`) and substitutes only the
    accessed element. The remaining declarations are initialized but never read
    afterwards, and every target toolchain that reports unused locals (dart
    analyze) flags them.

    "Never read" means never read by the statements that FOLLOW the declaration
    in the list handed in, which is the local's whole scope - but only when that
    list is the complete statement scope. The emitter renders slices of a body
    (a loop lowered through a fusion plan renders the loop minus the statement
    the plan moved, an element loop renders the body minus its head), and a read
    outside the slice would be invisible here. The caller therefore opts in
    through `blockLines(..., scopeComplete: true)`.

    A declaration that a later statement writes is kept even when it is never
    read: the write names the variable, so dropping the declaration would leave
    a write to a variable that no longer exists (dart reports a missing setter).
    The write guard is deliberately conservative; removing the writes as well
    would change more of the statement tree than the dead declaration alone.

    A dead binding whose initializer may have effects keeps its evaluation as an
    expression statement: dart flags an unused local and ignores a bare
    expression statement, and renaming cannot silence it (a leading underscore
    is not exempt). An initializer with no expression-position lowering keeps its
    declaration through `keepDeclaration`.
**/
class DeadLocalElimination {
    /**
        Returns `stmts` (a complete statement scope) without its unread local
        declarations. A declaration without an initializer is always kept: it is
        the definite-assignment form, and dropping it would leave later writes
        naming a variable that no longer exists. A declaration with an
        initializer is kept for the same reason when a later statement writes
        the variable.
    **/
    public static function filterStmts(stmts:Array<TypedExpr>, ?keepDeclaration:TypedExpr->Bool):Array<TypedExpr> {
        if (stmts == null || stmts.length == 0)
            return stmts;
        final writeGuard = writeGuardEnabled();
        final out:Array<TypedExpr> = [];
        for (i in 0...stmts.length) {
            final stmt = stmts[i];
            switch (stmt.expr) {
                case TVar(v, init):
                    var reads = 0;
                    var writes = 0;
                    for (j in i + 1...stmts.length) {
                        reads += countReads(stmts[j], v.id);
                        if (writeGuard)
                            writes += countWrites(stmts[j], v.id);
                    }
                    if (init == null || reads > 0 || writes > 0) {
                        out.push(stmt);
                        continue;
                    }
                    if (isSideEffectFree(init))
                        continue;
                    // The binding is dead but the initializer may have effects:
                    // keep the evaluation, drop the name.
                    if (keepDeclaration != null && keepDeclaration(init)) {
                        out.push(stmt);
                        continue;
                    }
                    out.push(init);
                case _:
                    out.push(stmt);
            }
        }
        return out;
    }

    /**
        Whether the later-write guard applies. -D dart_dead_local_ablate=WriteGuard
        disables it, which reproduces the dropped-declaration output for the
        GP-ABLATE arm of the regression fixture.
    **/
    static function writeGuardEnabled():Bool {
        return Context.definedValue("dart_dead_local_ablate") != "WriteGuard";
    }

    /**
        Read count of one local inside an expression. A plain-assignment target
        is a write and reads nothing; everything else counts, including the receiver
        and index of an indexed write target and the body of a closure.
    **/
    static function countReads(e:TypedExpr, id:Int):Int {
        if (e == null)
            return 0;
        var count = 0;
        switch (e.expr) {
            case TLocal(v) if (v.id == id):
                count = 1;
            case TVar(v, init):
                if (v.id != id && init != null)
                    count += countReads(init, id);
            case TBinop(OpAssign, t, val):
                count += countReads(val, id);
                count += isLocalTarget(t, id) ? 0 : countReads(t, id);
                return count;
            case TBinop(OpAssignOp(_), t, val):
                count += countReads(val, id);
                count += countReads(t, id);
                return count;
            case TUnop(OpIncrement, _, t) | TUnop(OpDecrement, _, t):
                count += countReads(t, id);
                return count;
            default:
                haxe.macro.TypedExprTools.iter(e, child -> count += countReads(child, id));
        }
        return count;
    }

    /**
        Write count of one local inside an expression, the symmetric partner of
        countReads. A plain-assignment target is a write; a compound assignment
        and an increment or decrement write their target too. A write nested in
        a value or in a closure body counts: the closure may run later.
    **/
    static function countWrites(e:TypedExpr, id:Int):Int {
        if (e == null)
            return 0;
        var count = 0;
        switch (e.expr) {
            case TBinop(OpAssign, t, val):
                count += isLocalTarget(t, id) ? 1 : countWrites(t, id);
                count += countWrites(val, id);
                return count;
            case TBinop(OpAssignOp(_), t, val):
                count += isLocalTarget(t, id) ? 1 : countWrites(t, id);
                count += countWrites(val, id);
                return count;
            case TUnop(OpIncrement, _, t) | TUnop(OpDecrement, _, t):
                count += isLocalTarget(t, id) ? 1 : countWrites(t, id);
                return count;
            case TVar(v, init):
                if (v.id != id && init != null)
                    count += countWrites(init, id);
            default:
                haxe.macro.TypedExprTools.iter(e, child -> count += countWrites(child, id));
        }
        return count;
    }

    static function isLocalTarget(t:TypedExpr, id:Int):Bool {
        return switch (t.expr) {
            case TLocal(v): v.id == id;
            case _: false;
        };
    }

    /**
        Whether evaluating this expression can have no effect beyond producing a
        value. A closure literal and a plain read are pure; a constructor, a
        call, an assignment, a throw, a loop or a switch is not, so their
        declaration keeps its evaluation.
    **/
    static function isSideEffectFree(e:TypedExpr):Bool {
        if (e == null)
            return true;
        return switch (e.expr) {
            case TConst(_): true;
            case TLocal(_): true;
            case TTypeExpr(_): true;
            case TFunction(_): true;
            case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _):
                isSideEffectFree(inner);
            case TField(subj, _):
                isSideEffectFree(subj);
            case TArray(subj, idx):
                isSideEffectFree(subj) && isSideEffectFree(idx);
            case TBlock(stmts):
                [for (s in stmts) if (!isSideEffectFree(s)) false].length == 0;
            case TVar(_, init):
                init == null || isSideEffectFree(init);
            case TArrayDecl(elems):
                [for (x in elems) if (!isSideEffectFree(x)) false].length == 0;
            case TObjectDecl(fields):
                [for (f in fields) if (!isSideEffectFree(f.expr)) false].length == 0;
            case _: false;
        };
    }
}
#end
