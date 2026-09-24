package dartcompiler;

#if (macro || reflaxe_runtime)

import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;
import PolicyQueries;

using Lambda;

/**
    Statement-level promotion plan for a Dart method body. For every
    statement of the body — nested blocks included, in evaluation order —
    the plan records which nullable locals Dart promotes while that
    statement renders. Built from the typed AST before any rendering, so
    the answer never depends on how many times nested lowering re-renders
    a statement. (BodyUnwrapPlan)
**/
class DartFlowPlan {
    /** Statement pos.min -> promoted var ids. */
    public final promotedAt:Map<Int, Map<Int, Bool>> = new Map();

    public function new() {}

    public static function build(root:TypedExpr):DartFlowPlan {
        final plan = new DartFlowPlan();
        plan.walk(PolicyQueries.statementsOf(root), new Map());
        return plan;
    }

    /** Whether the statement keyed by `stmtKey` renders with `varId`
        promoted. (BodyUnwrapPlan) */
    public function promotesAt(stmtKey:Int, varId:Int):Bool {
        final set = promotedAt.get(stmtKey);
        return set != null && set.exists(varId);
    }

    function walk(stmts:Array<TypedExpr>, promoted:Map<Int, Bool>):Void {
        for (s in stmts) {
            if (s.pos != null)
                promotedAt.set(Context.getPosInfos(s.pos).min, promoted.copy());
            switch (s.expr) {
                case TIf(c, then, els):
                    final adds = headPromotions(c);
                    final negs = headNegations(c);
                    if (adds.length > 0) {
                        // `if (x != null) ...`: x promotes inside the block.
                        // With an else arm both paths reconverge and a path
                        // exists where the head never held, so the promotion
                        // stays inside the branches. Without an else it
                        // persists after the block. (BodyUnwrapPlan)
                        final inner = promoted.copy();
                        for (v in adds)
                            inner.set(v.id, true);
                        walk(PolicyQueries.statementsOf(then), inner);
                        if (els != null) {
                            walk(PolicyQueries.statementsOf(els), promoted.copy());
                            for (v in adds)
                                promoted.set(v.id, true);
                        } else {
                            for (v in adds)
                                promoted.set(v.id, true);
                        }
                    } else if (negs.length > 0) {
                        // `if (x == null) ...`: x promotes from the closing
                        // brace onward only when the block always exits.
                        // (BodyUnwrapPlan)
                        walk(PolicyQueries.statementsOf(then), promoted.copy());
                        if (els != null)
                            walk(PolicyQueries.statementsOf(els), promoted.copy());
                        if (blockAlwaysExits(then))
                            for (v in negs)
                                promoted.set(v.id, true);
                    } else {
                        walk(PolicyQueries.statementsOf(then), promoted.copy());
                        if (els != null)
                            walk(PolicyQueries.statementsOf(els), promoted.copy());
                    }
                case TWhile(c, body, _):
                    final adds = headPromotions(c);
                    final inner = promoted.copy();
                    for (v in adds)
                        inner.set(v.id, true);
                    walk(PolicyQueries.statementsOf(body), inner);
                case TBlock(_):
                    walk(PolicyQueries.statementsOf(s), promoted);
                case TBinop(OpAssign, {expr: TLocal(v)}, rhs):
                    if (nonNullLiteral(rhs))
                        promoted.set(v.id, true);
                case _:
            }
        }
    }

    /** Bare locals the head promotes: `x != null`, `x is T`, and any
        comparison or arithmetic that unwraps a nullable operand runs
        unconditionally in the head. Iterative: guard heads nest deep and
        the interpreter's stack is shallow. (BodyUnwrapPlan) */
    function headPromotions(c:TypedExpr):Array<TVar> {
        final out:Array<TVar> = [];
        final stack:Array<TypedExpr> = [c];
        while (stack.length > 0) {
            final e = strip(stack.pop());
            switch (e.expr) {
                case TBinop(OpNotEq, {expr: TLocal(v)}, {expr: TConst(TNull)}) | TBinop(OpNotEq, {expr: TConst(TNull)}, {expr: TLocal(v)}):
                    out.push(v);
                case TBinop(op, {expr: TLocal(v)}, r) if (unwrappingOp(op) && PolicyQueries.isNullableType(v.t)):
                    out.push(v);
                    stack.push(r);
                case TBinop(op, l, {expr: TLocal(v)}) if (unwrappingOp(op) && PolicyQueries.isNullableType(v.t)):
                    out.push(v);
                    stack.push(l);
                case TBinop(_, l, r):
                    stack.push(l);
                    stack.push(r);
                case TParenthesis(p) | TMeta(_, p):
                    stack.push(p);
                case TIf(c2, t, f):
                    stack.push(c2);
                    if (t != null)
                        stack.push(t);
                    if (f != null)
                        stack.push(f);
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
