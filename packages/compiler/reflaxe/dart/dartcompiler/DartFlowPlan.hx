package dartcompiler;

#if (macro || reflaxe_runtime)

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;
import PolicyQueries;

/**
    Statement-level promotion plan for a Dart method body. The builder walks
    the typed AST in evaluation order and records, for every subexpression
    node, which nullable locals Dart promotes while that node renders.
    Guards (`!= null`, `is`), a negative `== null` guard whose block always
    exits, and a non-null literal assignment all add promotions; exclusive
    branches keep them local to their arm. The answer never depends on how
    many times nested lowering re-renders a node. (BodyUnwrapPlan)
**/
class DartFlowPlan {
    /** Node pos.min -> promoted var ids while that node renders. */
    public final promotedAt:Map<Int, Map<Int, Bool>> = new Map();

    public function new() {}

    public static function build(root:TypedExpr):DartFlowPlan {
        final plan = new DartFlowPlan();
        plan.visitSeq(PolicyQueries.statementsOf(root), new Map());
        return plan;
    }

    /** Whether the node keyed by `key` renders with `varId` promoted.
        (BodyUnwrapPlan) */
    public function promotesAt(key:Int, varId:Int):Bool {
        final set = promotedAt.get(key);
        return set != null && set.exists(varId);
    }

    function visitSeq(stmts:Array<TypedExpr>, promoted:Map<Int, Bool>):Void {
        for (s in stmts)
            visit(s, promoted);
    }

    function visit(e:TypedExpr, promoted:Map<Int, Bool>):Void {
        if (e == null)
            return;
        final key = posKey(e);
        if (key >= 0)
            promotedAt.set(key, promoted.copy());
        switch (e.expr) {
            case TBinop(OpBoolAnd, l, r):
                final adds = headPromotions(l);
                final inner = promoted.copy();
                for (v in adds)
                    inner.set(v.id, true);
                visit(l, promoted);
                visit(r, inner);
            case TBinop(OpBoolOr, l, r):
                final negs = headNegations(l);
                visit(l, promoted);
                final inner = promoted.copy();
                for (v in negs)
                    inner.set(v.id, true);
                visit(r, inner);
            case TBinop(OpAssign, {expr: TLocal(v)}, rhs):
                visit(rhs, promoted);
                if (nonNullLiteral(rhs))
                    promoted.set(v.id, true);
            case TBinop(_, l, r):
                visit(l, promoted);
                visit(r, promoted);
            case TIf(c, t, f):
                final adds = headPromotions(c);
                final negs = headNegations(c);
                final inner = promoted.copy();
                for (v in adds)
                    inner.set(v.id, true);
                visit(c, promoted);
                visit(t, inner);
                if (f != null) {
                    // An else arm exists: both paths reconverge, so a
                    // promotion earned only on the true path does not
                    // survive past the branches. A negative head works the
                    // other way: its names promote only past the else.
                    visit(f, promoted);
                } else {
                    for (v in negs)
                        if (blockAlwaysExits(t))
                            promoted.set(v.id, true);
                }
            case TWhile(c, body, _):
                final adds = headPromotions(c);
                final inner = promoted.copy();
                for (v in adds)
                    inner.set(v.id, true);
                visit(c, promoted);
                visit(body, inner);
            case TBlock(_):
                visitSeq(PolicyQueries.statementsOf(e), promoted);
            case TCall(fn, args):
                visit(fn, promoted);
                for (a in args)
                    visit(a, promoted);
            case TArray(e1, e2):
                visit(e1, promoted);
                visit(e2, promoted);
            case TNew(_, _, args):
                for (a in args)
                    visit(a, promoted);
            case TField(o, _):
                visit(o, promoted);
            case TParenthesis(p) | TMeta(_, p):
                visit(p, promoted);
            case TVar(v, init) if (init != null):
                visit(init, promoted);
                if (nonNullLiteral(init))
                    promoted.set(v.id, true);
            case _:
        }
    }

    /** Bare locals the head promotes: `x != null`, `x is T`, and any
        comparison or arithmetic that unwraps a nullable operand.
        (BodyUnwrapPlan) */
    function headPromotions(c:TypedExpr):Array<TVar> {
        final out:Array<TVar> = [];
        final stack:Array<TypedExpr> = [c];
        while (stack.length > 0) {
            final e = strip(stack.pop());
            switch (e.expr) {
                case TBinop(OpNotEq, {expr: TLocal(v)}, {expr: TConst(TNull)}) | TBinop(OpNotEq, {expr: TConst(TNull)}, {expr: TLocal(v)}):
                    out.push(v);
                case TBinop(op, {expr: TLocal(v)}, _) if (unwrappingOp(op) && PolicyQueries.isNullableType(v.t)):
                    out.push(v);
                case TBinop(op, _, {expr: TLocal(v)}) if (unwrappingOp(op) && PolicyQueries.isNullableType(v.t)):
                    out.push(v);
                case TBinop(_, l, r):
                    stack.push(l);
                    stack.push(r);
                case TParenthesis(p) | TMeta(_, p):
                    stack.push(p);
                case _:
            }
        }
        return out;
    }

    /** Bare locals an `== null` disjunction head negates: they promote on
        the false path of the whole head. (BodyUnwrapPlan) */
    function headNegations(c:TypedExpr):Array<TVar> {
        final out:Array<TVar> = [];
        final stack:Array<TypedExpr> = [c];
        while (stack.length > 0) {
            final e = strip(stack.pop());
            switch (e.expr) {
                case TBinop(OpEq, {expr: TLocal(v)}, {expr: TConst(TNull)}) | TBinop(OpEq, {expr: TConst(TNull)}, {expr: TLocal(v)}):
                    out.push(v);
                case TBinop(_, l, r):
                    stack.push(l);
                    stack.push(r);
                case TParenthesis(p) | TMeta(_, p):
                    stack.push(p);
                case _:
            }
        }
        return out;
    }

    /** Whether the block opens with an exit statement, which is what makes
        a negative guard promote past its closing brace. (BodyUnwrapPlan) */
    function blockAlwaysExits(block:TypedExpr):Bool {
        final stmts = PolicyQueries.statementsOf(block);
        if (stmts.length == 0)
            return false;
        return switch (stmts[0].expr) {
            case TReturn(_) | TThrow(_): true;
            case _: false;
        };
    }

    /** Comparisons and arithmetic demand a non-null operand: a nullable
        local rendered there is unwrapped, and Dart promotes it from that
        point on. (BodyUnwrapPlan) */
    static function unwrappingOp(op:Binop):Bool {
        return switch (op) {
            case OpLt | OpLte | OpGt | OpGte | OpAdd | OpSub | OpMult | OpDiv | OpMod: true;
            case _: false;
        };
    }

    /** A literal that can never be null. (BodyUnwrapPlan) */
    static function nonNullLiteral(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TConst(TNull): false;
            case TConst(_): true;
            case TArrayDecl(_) | TObjectDecl(_): true;
            case _: false;
        };
    }

    static function posKey(e:TypedExpr):Int {
        return e.pos == null ? -1 : Context.getPosInfos(e.pos).min;
    }

    static function strip(e:TypedExpr):TypedExpr {
        var cur = e;
        while (true) {
            cur = switch (cur.expr) {
                case TParenthesis(p) | TMeta(_, p): p;
                case _: return cur;
            };
        }
    }
}

#end
