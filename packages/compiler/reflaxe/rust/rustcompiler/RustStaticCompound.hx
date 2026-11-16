package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Position;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import ExpressionPredicates;

/** The static path a write reaches, plus the index expressions on the way. */
typedef WriteTarget = {
    path:String,
    extras:Array<TypedExpr>
};

/** Tainted locals per static path: a local whose value derives from a read. */
typedef AuditState = {
    tainted:Map<String, Map<Int, Bool>>
};

/**
    Rejects a compound operation on a shared static (policy P-1a).

    A ThreadSafeShared static is emitted as Mutex<T> or LazyLock<Mutex<T>>,
    and every access takes the lock on its own. A function that reads a value
    out of such a static and then writes a value derived from that read back
    into it has two separate lock acquisitions with user work between them, so
    another thread can interleave the read and the write. The stored entries
    then stop matching their indices, a length check no longer holds at the
    index read, and the corruption stays in the process.

    The audit runs on one function body and names the required form: build the
    new value once and publish it with one assignment, or move the read into a
    separate function. A whole-value assignment whose value does not read the
    static is accepted, because two threads then publish equal complete tables
    and a reader observes one of them.

    Scope and limits:

    - Only a value derived from a read of the same static is rejected. A write
      whose value and element index are independent of the static stays legal,
      even when a stale read chose the branch that reaches it. That branch
      can choose a different assignment but cannot corrupt aligned data.
    - The audit covers one function body. A read in one function and a write
      in another are separate operations by construction and are not paired.
    - A nested function literal is a separate body. Its reads and writes are
      not paired with the enclosing body.
**/
class RustStaticCompound {
    /** Member names whose call on a static receiver writes through the lock. */
    static final MUTATING_MEMBERS:Array<String> = [
        "add",
        "addByte",
        "addChar",
        "blit",
        "clear",
        "fill",
        "finish",
        "getBytes",
        "insert",
        "pop",
        "push",
        "remove",
        "removeAt",
        "resize",
        "reverse",
        "set",
        "shift",
        "sort",
        "splice",
        "unshift",
        "writeAscii"
    ];

    /**
        Audits one function body. isShared answers whether a static field is a
        ThreadSafeShared realization: the emitted item carries a Mutex and the
        function accesses it across threads. The caller supplies the
        realization check so this audit and the item renderer cannot disagree.
    **/
    public static function audit(body:TypedExpr, isShared:ClassType->ClassField->Bool):Void {
        if (body == null)
            return;
        final state:AuditState = {tainted: new Map<String, Map<Int, Bool>>()};
        walk(body, state, isShared);
    }

    static function walk(e:TypedExpr, state:AuditState, isShared:ClassType->ClassField->Bool):Void {
        if (e == null)
            return;
        final node = ExpressionPredicates.stripWrap(e);
        switch (node.expr) {
            case TFunction(nested):
                // A nested body is a separate function. Audit its own read and
                // write sites with a fresh state; they are not paired with this
                // body.
                if (nested.expr != null) {
                    final nestedState:AuditState = {tainted: new Map<String, Map<Int, Bool>>()};
                    walk(nested.expr, nestedState, isShared);
                }
                return;
            case TVar(v, init):
                if (init != null) {
                    taint(v.id, init, state, isShared);
                    walk(init, state, isShared);
                }
            case TBinop(OpAssign, lhs, rhs):
                final target = writeTarget(lhs, isShared);
                if (target != null) {
                    checkWrite(target.path, [rhs].concat(target.extras), lhs.pos, state, isShared);
                } else {
                    switch (ExpressionPredicates.stripWrap(lhs).expr) {
                        case TLocal(v):
                            taint(v.id, rhs, state, isShared);
                        case _:
                    }
                }
                walk(lhs, state, isShared);
                walk(rhs, state, isShared);
            case TBinop(OpAssignOp(_), lhs, rhs):
                // The lock covers the read and the store of a compound
                // assignment, so the store itself is one operation. A value
                // expression that reads the same static still holds a second
                // guard and stays rejected.
                final target = writeTarget(lhs, isShared);
                if (target != null)
                    checkWrite(target.path, [rhs].concat(target.extras), lhs.pos, state, isShared);
                walk(lhs, state, isShared);
                walk(rhs, state, isShared);
            case TCall(fn, args):
                final receiver = mutatingReceiver(fn);
                if (receiver != null) {
                    final target = writeTarget(receiver, isShared);
                    if (target != null)
                        checkWrite(target.path, args.concat(target.extras), node.pos, state, isShared);
                }
                walk(fn, state, isShared);
                for (arg in args)
                    walk(arg, state, isShared);
            case TIf(condition, ifBody, elseBody):
                walk(condition, state, isShared);
                walk(ifBody, state, isShared);
                if (elseBody != null)
                    walk(elseBody, state, isShared);
            case TWhile(condition, body, _):
                walk(condition, state, isShared);
                walk(body, state, isShared);
            case TFor(_, iterator, body):
                walk(iterator, state, isShared);
                walk(body, state, isShared);
            case TBlock(statements):
                for (statement in statements)
                    walk(statement, state, isShared);
            case TSwitch(subject, cases, defaultCase):
                walk(subject, state, isShared);
                for (branch in cases) {
                    for (value in branch.values)
                        walk(value, state, isShared);
                    walk(branch.expr, state, isShared);
                }
                if (defaultCase != null)
                    walk(defaultCase, state, isShared);
            case TTry(tryBody, catches):
                walk(tryBody, state, isShared);
                for (caught in catches)
                    walk(caught.expr, state, isShared);
            case TReturn(value):
                if (value != null)
                    walk(value, state, isShared);
            case TThrow(value):
                walk(value, state, isShared);
            case TMeta(_, inner):
                walk(inner, state, isShared);
            case _:
                TypedExprTools.iter(node, function(child) walk(child, state, isShared));
        }
    }

    /**
        The static path a write reaches, or null when the left side is not a
        static or an element of one. An element write carries its index
        expressions, which are part of the value the operation stores.
    **/
    static function writeTarget(e:TypedExpr, isShared:ClassType->ClassField->Bool):Null<WriteTarget> {
        final node = ExpressionPredicates.stripWrap(e);
        return switch (node.expr) {
            case TField(_, FStatic(c, cf)) if (isShared(c.get(), cf.get())):
                {path: staticKey(c.get(), cf.get()), extras: []};
            case TArray(container, index):
                final root = staticRoot(container, isShared);
                if (root == null) null else {path: root.path, extras: [index].concat(root.extras)};
            case TField(subject, FInstance(_, _, _)):
                // An element field write (table[i].field = value) mutates the
                // element inside the static collection.
                staticRoot(subject, isShared);
            case _:
                null;
        }
    }

    /** The static path a value expression roots at, with its index expressions. */
    static function staticRoot(e:TypedExpr, isShared:ClassType->ClassField->Bool):Null<WriteTarget> {
        final node = ExpressionPredicates.stripWrap(e);
        return switch (node.expr) {
            case TField(_, FStatic(c, cf)) if (isShared(c.get(), cf.get())):
                {path: staticKey(c.get(), cf.get()), extras: []};
            case TArray(container, index):
                final inner = staticRoot(container, isShared);
                if (inner == null) null else {path: inner.path, extras: [index].concat(inner.extras)};
            case _:
                null;
        };
    }

    /** The receiver of a call whose member writes through the lock. */
    static function mutatingReceiver(fn:TypedExpr):Null<TypedExpr> {
        final node = ExpressionPredicates.stripWrap(fn);
        return switch (node.expr) {
            case TField(receiver, FInstance(_, _, cf)) if (MUTATING_MEMBERS.indexOf(cf.get().name) >= 0):
                receiver;
            case TField(receiver, FAnon(cf)) if (MUTATING_MEMBERS.indexOf(cf.get().name) >= 0):
                receiver;
            case TField(receiver, FDynamic(name)) if (MUTATING_MEMBERS.indexOf(name) >= 0):
                receiver;
            case _:
                null;
        };
    }

    /** Records that the local's value derives from a read of these statics. */
    static function taint(id:Int, value:TypedExpr, state:AuditState, isShared:ClassType->ClassField->Bool):Void {
        if (value == null)
            return;
        for (path in pathsReadBy(value, state, isShared).keys()) {
            var locals = state.tainted.get(path);
            if (locals == null) {
                locals = new Map<Int, Bool>();
                state.tainted.set(path, locals);
            }
            locals.set(id, true);
        }
    }

    /** Rejects a write whose stored value or index derives from a read of it. */
    static function checkWrite(path:String, values:Array<TypedExpr>, pos:Position, state:AuditState,
            isShared:ClassType->ClassField->Bool):Void {
        for (value in values) {
            if (value == null)
                continue;
            if (pathsReadBy(value, state, isShared).exists(path)) {
                Context.error(ruleText(path), pos);
                return;
            }
        }
    }

    /**
        The static paths a value expression reads, including locals tainted by
        an earlier read. A mutating call is one atomic operation, so its return
        value is not counted as a read that a later write could pair with.
    **/
    static function pathsReadBy(e:TypedExpr, state:AuditState, isShared:ClassType->ClassField->Bool):Map<String, Bool> {
        final out = new Map<String, Bool>();
        collectReads(e, out, state, isShared);
        return out;
    }

    static function collectReads(e:TypedExpr, out:Map<String, Bool>, state:AuditState,
            isShared:ClassType->ClassField->Bool):Void {
        if (e == null)
            return;
        final node = ExpressionPredicates.stripWrap(e);
        switch (node.expr) {
            case TFunction(_):
                return;
            case TField(_, FStatic(c, cf)):
                if (isShared(c.get(), cf.get()))
                    out.set(staticKey(c.get(), cf.get()), true);
            case TLocal(v):
                for (path => locals in state.tainted)
                    if (locals.exists(v.id))
                        out.set(path, true);
            case TCall(fn, args):
                if (mutatingReceiver(fn) != null) {
                    for (arg in args)
                        collectReads(arg, out, state, isShared);
                    return;
                }
                collectReads(fn, out, state, isShared);
                for (arg in args)
                    collectReads(arg, out, state, isShared);
            case _:
                TypedExprTools.iter(node, function(child) collectReads(child, out, state, isShared));
        }
    }

    static function staticKey(cls:ClassType, field:ClassField):String {
        return cls.module + "." + field.name;
    }

    /** The diagnostic text: what happened, why it is unsafe, and the fix. */
    public static function ruleText(label:String):String {
        return "static " + label
            + " is shared through a Mutex and this function writes a value derived from a read of it. Each access takes the lock on its own, so the read and the write are separate operations and another thread can interleave them. Build the new value once and assign the static in a single write, or move the read into a separate function. (P-1a compound operation)";
    }
}
#end
