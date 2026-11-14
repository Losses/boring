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

    A local that is written after its declaration and never read is dead with
    its writes: a plain assignment to a local nothing reads has no effect of its
    own. The declaration goes, and the write goes with it; a side-effecting
    value survives as an expression statement, the same shape the TypeScript
    target's dropDeadLocals uses. A write the emitter cannot rewrite (expression
    position, or a closure body it may render as an expression) keeps the
    declaration instead: dropping it would leave the write naming a variable
    that no longer exists (dart reports a missing setter). The write guard is the
    safe net; the rewrite is the case that removes the warning.

    A dead binding whose initializer may have effects keeps its evaluation as an
    expression statement: dart flags an unused local and ignores a bare
    expression statement, and renaming cannot silence it (a leading underscore
    is not exempt). An initializer with no expression-position lowering keeps its
    declaration through `keepDeclaration`.
**/
class DeadLocalElimination {
    /**
        Locals whose declaration this pass dropped and whose later plain
        assignments it must strip. The declaration's statement list is rendered
        before the nested lists that hold its writes, and Haxe gives every local
        a unique id, so one compilation-wide set is enough. The ablation define
        never adds to it, which restores the dropped-declaration-only output.
    **/
    static final writeOnlyLocals:Map<Int, Bool> = [];

    /**
        Returns `stmts` (a complete statement scope) without its unread local
        declarations. A declaration without an initializer is always kept: it is
        the definite-assignment form, and dropping it would leave later writes
        naming a variable that no longer exists. A declaration with an
        initializer is dropped together with its later writes when every write
        is a plain assignment this pass can rewrite; otherwise it is kept for the
        same reason.
    **/
    public static function filterStmts(stmts:Array<TypedExpr>, ?keepDeclaration:TypedExpr->Bool):Array<TypedExpr> {
        if (stmts == null || stmts.length == 0)
            return stmts;
        final writeGuard = writeGuardEnabled();
        final out:Array<TypedExpr> = [];
        for (i in 0...stmts.length) {
            final stmt = stmts[i];
            if (writeGuard) {
                final write = writeOnlyAssignment(stmt);
                if (write != null) {
                    // A write to a dead local: drop the assignment and keep a
                    // side-effecting value so its effect survives.
                    if (!isSideEffectFree(write))
                        out.push(write);
                    continue;
                }
            }
            switch (stmt.expr) {
                case TVar(v, init):
                    var reads = 0;
                    var writes = 0;
                    for (j in i + 1...stmts.length) {
                        reads += countReads(stmts[j], v.id);
                        if (writeGuard)
                            writes += countWrites(stmts[j], v.id);
                    }
                    if (init == null || reads > 0) {
                        out.push(stmt);
                        continue;
                    }
                    if (writes > 0 && !allWritesRewritable(stmts, i + 1, v.id)) {
                        out.push(stmt);
                        continue;
                    }
                    if (!isSideEffectFree(init)) {
                        if (keepDeclaration != null && keepDeclaration(init)) {
                            out.push(stmt);
                            continue;
                        }
                        out.push(init);
                    }
                    if (writes > 0)
                        writeOnlyLocals.set(v.id, true);
                case _:
                    out.push(stmt);
            }
        }
        return out;
    }

    /**
        Whether the later-write rewrite applies. -D dart_dead_local_ablate=WriteGuard
        disables it, which leaves the declaration dropped and its writes in place
        for the GP-ABLATE arm of the regression fixture.
    **/
    static function writeGuardEnabled():Bool {
        return Context.definedValue("dart_dead_local_ablate") != "WriteGuard";
    }

    /**
        The value of a plain assignment to a dropped write-only local, or null.
    **/
    static function writeOnlyAssignment(stmt:TypedExpr):Null<TypedExpr> {
        return switch (stripWrap(stmt).expr) {
            case TBinop(OpAssign, t, val):
                switch (stripWrap(t).expr) {
                    case TLocal(v) if (writeOnlyLocals.exists(v.id) && countWrites(val, v.id) == 0):
                        val;
                    case _:
                        null;
                }
            case _:
                null;
        }
    }

    /**
        Whether every write to `id` after `from` is a plain assignment in
        statement position, so the list that renders it can strip the write.
    **/
    static function allWritesRewritable(stmts:Array<TypedExpr>, from:Int, id:Int):Bool {
        for (j in from...stmts.length)
            if (!statementWritesRewritable(stmts[j], id))
                return false;
        return true;
    }

    /**
        Whether the writes to `id` inside one statement are all plain
        assignments in statement position. A write under a condition, an
        argument, a return value or a closure body is not rewritable here.
    **/
    static function statementWritesRewritable(stmt:TypedExpr, id:Int):Bool {
        if (stmt == null)
            return true;
        return switch (stripWrap(stmt).expr) {
            case TBinop(OpAssign, t, val) if (isLocalTarget(t, id)):
                countWrites(val, id) == 0;
            case TBlock(stmts):
                [for (s in stmts) if (!statementWritesRewritable(s, id)) false].length == 0;
            case TIf(cond, eif, eelse):
                countWrites(cond, id) == 0 && statementWritesRewritable(eif, id)
                    && (eelse == null || statementWritesRewritable(eelse, id));
            case TWhile(cond, body, _):
                countWrites(cond, id) == 0 && statementWritesRewritable(body, id);
            case TFor(_, it, body):
                countWrites(it, id) == 0 && statementWritesRewritable(body, id);
            case TSwitch(subject, cases, edef):
                countWrites(subject, id) == 0
                    && [for (c in cases) if (!([for (value in c.values) if (countWrites(value, id) > 0) false].length == 0
                        && statementWritesRewritable(c.expr, id))) false].length == 0
                    && (edef == null || statementWritesRewritable(edef, id));
            case TTry(body, catches):
                statementWritesRewritable(body, id)
                    && [for (c in catches) if (!statementWritesRewritable(c.expr, id)) false].length == 0;
            case _:
                countWrites(stmt, id) == 0;
        };
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
        return switch (stripWrap(t).expr) {
            case TLocal(v): v.id == id;
            case _: false;
        };
    }

    static function stripWrap(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TMeta(_, inner) | TParenthesis(inner): stripWrap(inner);
            case _: e;
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
