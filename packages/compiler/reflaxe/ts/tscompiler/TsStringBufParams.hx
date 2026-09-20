package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import PolicyQueries;
import RuntimeResidents;

/**
    Tracks functions whose StringBuf parameters are mutated in the function
    body. The TypeScript target erases std.StringBuf to an immutable
    `string`, so a mutation inside a callee cannot write back through the
    caller's binding. For a function whose StringBuf parameter is mutated,
    the emitter threads the mutated buffer back through the return value:
    the signature returns `string` (the buffer) instead of `void`, the body
    appends `return out;`, and every call site reassigns the argument
    (`out = appendJsonString(out, value)`). This mirrors the mutable
    reference semantics of Kotlin's StringBuilder and Rust's `&mut Vec<u16>`.
**/
class TsStringBufParams {
    /** module::class.field -> set of mutated StringBuf parameter names. */
    static final mutatedParamNames:Map<String, Map<String, Bool>> = [];

    /** module::class.field -> set of mutated StringBuf parameter indices. */
    static final mutatedParamIndices:Map<String, Map<Int, Bool>> = [];

    public static function key(module:String, className:String, fieldName:String):String {
        final mod = module != null && module != "" ? module : className;
        return mod + "::" + className + "." + fieldName;
    }

    public static function hasMutatedStringBufParam(module:String, className:String, fieldName:String):Bool {
        return mutatedParamNames.exists(key(module, className, fieldName));
    }

    public static function isMutatedStringBufParam(module:String, className:String, fieldName:String, paramName:String, paramIndex:Int = -1):Bool {
        final k = key(module, className, fieldName);
        final nameMap = mutatedParamNames.get(k);
        if (nameMap != null && nameMap.exists(paramName)) {
            return true;
        }
        if (paramIndex >= 0) {
            final indexMap = mutatedParamIndices.get(k);
            if (indexMap != null && indexMap.exists(paramIndex)) {
                return true;
            }
        }
        return false;
    }

    public static function collect(mtypes:Array<ModuleType>):Void {
        for (k in mutatedParamNames.keys())
            mutatedParamNames.remove(k);
        for (k in mutatedParamIndices.keys())
            mutatedParamIndices.remove(k);

        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c):
                    final cls = c.get();
                    final resident = RuntimeResidents.isResident(cls.module);
                    if (cls.isExtern || (!resident && !PolicyQueries.inSourceScope(cls.pos))) {
                        continue;
                    }
                    for (field in cls.statics.get()) {
                        scanField(cls.module, cls.name, field);
                    }
                    for (field in cls.fields.get()) {
                        scanField(cls.module, cls.name, field);
                    }
                    final ctor = cls.constructor;
                    if (ctor != null) {
                        scanField(cls.module, cls.name, ctor.get());
                    }
                case _:
            }
        }
    }

    static function isStringBufType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(c, _):
                final cls = c.get();
                (cls.pack.join(".") == "std" && cls.name == "StringBuf") || (cls.pack.length == 0 && cls.name == "StringBuf");
            case _: false;
        };
    }

    static function scanField(module:String, className:String, field:ClassField):Void {
        switch (field.kind) {
            case FMethod(_):
                final e = field.expr();
                if (e == null)
                    return;
                switch (e.expr) {
                    case TFunction(tfunc):
                        final bufParams:Map<Int, {name:String, index:Int}> = [];
                        for (i in 0...tfunc.args.length) {
                            final arg = tfunc.args[i];
                            if (isStringBufType(arg.v.t)) {
                                bufParams.set(arg.v.id, {name: arg.v.name, index: i});
                            }
                        }
                        if (bufParams.keys().hasNext() == false)
                            return;

                        final mutatedNames:Map<String, Bool> = [];
                        final mutatedIndices:Map<Int, Bool> = [];
                        scanExprForMutations(tfunc.expr, bufParams, mutatedNames, mutatedIndices);

                        if (mutatedNames.keys().hasNext()) {
                            final k = key(module, className, field.name);
                            mutatedParamNames.set(k, mutatedNames);
                            mutatedParamIndices.set(k, mutatedIndices);
                        }
                    case _:
                }
            case _:
        }
    }

    static function stripWrap(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripWrap(inner);
            case _: e;
        };
    }

    static function rootIsParam(e:TypedExpr, bufParams:Map<Int, {name:String, index:Int}>):Null<{name:String, index:Int}> {
        return switch (stripWrap(e).expr) {
            case TLocal(v) if (bufParams.exists(v.id)): bufParams.get(v.id);
            case TField(s, _): rootIsParam(s, bufParams);
            case TArray(s, _): rootIsParam(s, bufParams);
            case TParenthesis(s): rootIsParam(s, bufParams);
            case TMeta(_, s): rootIsParam(s, bufParams);
            case _: null;
        };
    }

    static function scanExprForMutations(
        e:TypedExpr,
        bufParams:Map<Int, {name:String, index:Int}>,
        mutatedNames:Map<String, Bool>,
        mutatedIndices:Map<Int, Bool>
    ):Void {
        switch (e.expr) {
            case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
                final info = rootIsParam(t, bufParams);
                if (info != null) {
                    mutatedNames.set(info.name, true);
                    mutatedIndices.set(info.index, true);
                }
            case TCall(fn, args):
                switch (stripWrap(fn).expr) {
                    case TField(subj, FInstance(_, _, cf) | FAnon(cf)):
                        final n = cf.get().name;
                        if (n == "add" || n == "addChar") {
                            final info = rootIsParam(subj, bufParams);
                            if (info != null) {
                                mutatedNames.set(info.name, true);
                                mutatedIndices.set(info.index, true);
                            }
                        }
                    case _:
                }
                // A call to a helper that mutates a StringBuf argument
                // mutates the corresponding caller argument as well.
                switch (stripWrap(fn).expr) {
                    case TField(_, FStatic(_, cf)) | TField(_, FInstance(_, _, cf)) | TField(_, FAnon(cf)):
                        final calleeArgs = switch (Context.follow(cf.get().type)) {
                            case TFun(ps, _): ps;
                            case _: [];
                        };
                        for (i in 0...args.length) {
                            if (i >= calleeArgs.length)
                                continue;
                            final info = rootIsParam(args[i], bufParams);
                            if (info == null)
                                continue;
                            final p = calleeArgs[i];
                            if (isStringBufType(p.t)) {
                                final calleeBody = cf.get().expr();
                                if (calleeBody != null && calleeMutatesStringBuf(calleeBody, p.name)) {
                                    mutatedNames.set(info.name, true);
                                    mutatedIndices.set(info.index, true);
                                }
                            }
                        }
                    case _:
                }
            case _:
        }
        TypedExprTools.iter(e, x -> scanExprForMutations(x, bufParams, mutatedNames, mutatedIndices));
    }

    /** Whether a callee body mutates a StringBuf parameter by name. */
    static function calleeMutatesStringBuf(body:TypedExpr, paramName:String):Bool {
        var found = false;
        function root(x:TypedExpr):Bool {
            return switch (stripWrap(x).expr) {
                case TLocal(v): v.name == paramName;
                case TField(s, _): root(s);
                case TArray(s, _): root(s);
                case TParenthesis(s): root(s);
                case TMeta(_, s): root(s);
                case _: false;
            };
        }
        function walk(x:TypedExpr) {
            if (found)
                return;
            switch (x.expr) {
                case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
                    if (root(t))
                        found = true;
                case TCall(fn, _):
                    switch (stripWrap(fn).expr) {
                        case TField(s, FInstance(_, _, cf) | FAnon(cf)):
                            if (root(s) && (cf.get().name == "add" || cf.get().name == "addChar"))
                                found = true;
                        case _:
                    }
                case _:
            }
            if (!found)
                TypedExprTools.iter(x, walk);
        }
        walk(body);
        return found;
    }
}
#end