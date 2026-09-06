#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import PolicyQueries;

/**
    Shared analysis for the fill-loop fusion: recognizes `var arr =
    new Array<T>()` whose loop body only stores into `arr[index]` or
    pushes to `arr`, and hands each target's emitter one ordered step
    list. The acceptance rules reproduce the two per-target copies
    exactly: a store to another array or index, a push to another
    array, a second store, a second push, a push after a store, or any
    other statement mentioning the array all reject. `readsIndex`
    reproduces the Rust second scan (whether the loop variable is
    mentioned outside the store index); the Kotlin emitter ignores it.
**/
class FusionPlan {
    /**
        The allocation statement at `stmts[i]`: `new Array<T>()` with no
        constructor arguments. Returns null when `i + 1` is past the end
        or the statement is not such an allocation.
    **/
    public static function allocOf(stmts:Array<TypedExpr>, i:Int):Null<{arr:TVar, elem:Type}> {
        if (i + 1 >= stmts.length) {
            return null;
        }
        return switch (stmts[i].expr) {
            case TVar(v, init) if (init != null):
                switch (init.expr) {
                    case TNew(c, params, args) if (args.length == 0):
                        final cls = c.get();
                        if (cls.pack.join(".") != "" || cls.name != "Array" || params.length != 1) {
                            null;
                        } else {
                            {arr: v, elem: params[0]};
                        }
                    case _: null;
                }
            case _: null;
        }
    }

    /**
        One ordered walk over the loop body replacing both copies' two
        scans: the first scan's acceptance rules and the batched step
        order of the second (non-store statements batch up to the next
        store or push line, then flush).
    **/
    public static function plan(alloc:{arr:TVar, elem:Type}, loop:LoopInterval):Null<Plan> {
        var storeValue:Null<TypedExpr> = null;
        var pushArg:Null<TypedExpr> = null;
        final steps:Array<FusionStep> = [];
        final pending:Array<TypedExpr> = [];
        var readsIndex = false;
        for (s in loop.body) {
            final store = PolicyQueries.indexedStoreOf(s);
            if (store != null) {
                if (store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
                    if (storeValue != null) {
                        return null;
                    }
                    flush(steps, pending);
                    steps.push(StoreValue(store.value));
                    storeValue = store.value;
                    if (PolicyQueries.mentionsLocal(store.value, loop.index)) {
                        readsIndex = true;
                    }
                } else {
                    return null;
                }
                continue;
            }
            final push = PolicyQueries.pushOf(s);
            if (push != null) {
                if (push.arr.id == alloc.arr.id) {
                    if (pushArg != null || storeValue != null) {
                        return null;
                    }
                    flush(steps, pending);
                    steps.push(PushValue(push.arg));
                    pushArg = push.arg;
                    if (PolicyQueries.mentionsLocal(push.arg, loop.index)) {
                        readsIndex = true;
                    }
                } else {
                    return null;
                }
                continue;
            }
            if (PolicyQueries.mentionsLocal(s, alloc.arr)) {
                return null;
            }
            if (PolicyQueries.mentionsLocal(s, loop.index)) {
                readsIndex = true;
            }
            pending.push(s);
        }
        if (storeValue == null && pushArg == null) {
            return null;
        }
        flush(steps, pending);
        return {
            arr: alloc.arr,
            loop: loop,
            steps: steps,
            readsIndex: readsIndex
        };
    }

    static function flush(steps:Array<FusionStep>, pending:Array<TypedExpr>):Void {
        if (pending.length == 0) {
            return;
        }
        steps.push(NonStoreBatch(pending.copy()));
        pending.resize(0);
    }
}

enum FusionStep {
    NonStoreBatch(stmts:Array<TypedExpr>);
    StoreValue(value:TypedExpr);
    PushValue(arg:TypedExpr);
}

typedef LoopInterval = {
    index:TVar,
    start:TypedExpr,
    bound:TypedExpr,
    body:Array<TypedExpr>
};

typedef Plan = {
    arr:TVar,
    loop:LoopInterval,
    steps:Array<FusionStep>,
    readsIndex:Bool
};
#end
