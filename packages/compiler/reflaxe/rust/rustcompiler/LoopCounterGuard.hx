package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import ExpressionPredicates;
import PolicyQueries;
import StaticFieldHelper;

/**
    Keeps the counter of a counted array loop addressable across the loop.

    The shared pipeline lowering rewrites the (counter declaration, while)
    pair of an array traversal into the interval form with a fresh counter
    and drops the original binding. A loop whose tail still reads or writes
    that binding would then reference a name that no longer exists. The
    guard rewrites the canonical increment of such a pair into the
    equivalent compound assignment, so the pair no longer matches the
    lowering and the emitter keeps the while form with a mutable counter
    binding.
**/
class LoopCounterGuard {
    /** Rewrites the canonical increment of every counted loop whose tail still references the counter. */
    public static function prepare(root:TypedExpr):Void {
        if (root == null)
            return;
        walk(root);
    }

    static function walk(e:TypedExpr):Void {
        switch (e.expr) {
            case TBlock(stmts):
                scanBlock(stmts);
            case _:
        }
        TypedExprTools.iter(e, walk);
    }

    static function scanBlock(stmts:Array<TypedExpr>):Void {
        var i = 0;
        while (i < stmts.length) {
            final stmt = stmts[i];
            if (stmt == null) {
                i++;
                continue;
            }
            final counter = counterDecl(stmt);
            if (counter == null) {
                i++;
                continue;
            }
            if (i + 1 < stmts.length) {
                final pairBody = matchedLoopBody(stmts[i + 1], counter, null);
                if (pairBody != null) {
                    protect(counter, pairBody);
                    i += 2;
                    continue;
                }
                if (i + 2 < stmts.length) {
                    final subject = hoistedArraySubject(stmts[i + 1]);
                    if (subject != null) {
                        final tripleBody = matchedLoopBody(stmts[i + 2], counter, subject);
                        if (tripleBody != null) {
                            protect(counter, tripleBody);
                            i += 3;
                            continue;
                        }
                    }
                }
            }
            i++;
        }
    }

    static function counterDecl(stmt:TypedExpr):Null<TVar> {
        return switch (stmt.expr) {
            case TVar(v, init) if (init != null):
                switch (init.expr) {
                    case TConst(TInt(0)): v;
                    case _: null;
                }
            case _: null;
        }
    }

    static function hoistedArraySubject(stmt:TypedExpr):Null<TVar> {
        return switch (stmt.expr) {
            case TVar(v, init) if (init != null && StaticFieldHelper.isArrayType(v.t)): v;
            case _: null;
        }
    }

    /**
        Returns the loop body statements when the statement is the while
        half of the shape the shared pipeline lowering rewrites. The pair
        form passes a null subject and accepts any array receiver; the
        hoisted form passes the hoisted subject and requires the receiver
        to be that local.
    **/
    static function matchedLoopBody(stmt:TypedExpr, counter:TVar, subject:Null<TVar>):Null<Array<TypedExpr>> {
        final cond = switch (stmt.expr) {
            case TWhile(cond, _, true): cond;
            case _: null;
        }
        if (cond == null)
            return null;
        var recvId = -1;
        switch (ExpressionPredicates.stripWrap(cond).expr) {
            case TBinop(OpLt, left, right):
                switch [left.expr, right.expr] {
                    case [TLocal(c), TField(recv, FInstance(_, _, fl))] if (c.id == counter.id && fl.get().name == "length"):
                        switch (recv.expr) {
                            case TLocal(r) if (StaticFieldHelper.isArrayType(r.t)):
                                if (subject == null || r.id == subject.id)
                                    recvId = r.id;
                            case _:
                        }
                    case _:
                }
            case _:
        }
        if (recvId < 0)
            return null;
        final bodyStmts = switch (stmt.expr) {
            case TWhile(_, body, _):
                switch (body.expr) {
                    case TBlock(s): s;
                    case _: null;
                }
            case _: null;
        }
        if (bodyStmts == null || bodyStmts.length < 2)
            return null;
        switch (bodyStmts[0].expr) {
            case TVar(_, captureInit) if (captureInit != null):
                switch (ExpressionPredicates.stripWrap(captureInit).expr) {
                    case TArray({expr: TLocal(r)}, {expr: TLocal(idx)}) if (r.id == recvId && idx.id == counter.id):
                    case _: return null;
                }
            case _: return null;
        }
        switch (bodyStmts[1].expr) {
            case TUnop(OpIncrement, _, {expr: TLocal(c)}) if (c.id == counter.id):
            case _: return null;
        }
        return bodyStmts;
    }

    /**
        Rewrites the canonical increment when the loop tail still references
        the counter. The compound assignment keeps the increment's meaning
        and stops the pair from matching the shared lowering, so the binding
        survives into the emitted while form.
    **/
    static function protect(counter:TVar, body:Array<TypedExpr>):Void {
        final tail = body.slice(2);
        for (stmt in tail)
            if (PolicyQueries.mentionsLocal(stmt, counter)) {
                rewriteIncrement(body);
                return;
            }
    }

    static function rewriteIncrement(body:Array<TypedExpr>):Void {
        final increment = body[1];
        final subject = switch (increment.expr) {
            case TUnop(_, _, subject): subject;
            case _: null;
        }
        if (subject == null)
            return;
        final one:TypedExpr = {
            expr: TConst(TInt(1)),
            pos: increment.pos,
            t: increment.t
        };
        body[1] = {
            expr: TBinop(OpAssignOp(OpAdd), subject, one),
            pos: increment.pos,
            t: increment.t
        };
    }
}
#end
