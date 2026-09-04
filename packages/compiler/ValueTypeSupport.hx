package;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;

/** The one representation kind accepted by `@:valueType`. */
enum ValueTypeOperator {
    Binary(op:Binop);
    Unary(op:Unop);
}

/** Resolved information for a marked abstract implementation class. */
typedef ValueTypeInfo = {
    var abstractType:AbstractType;
    var implementation:ClassType;
    var name:String;
    var representation:Type;
}

/**
    Shared macro-side recognition for value wrappers.

    Haxe stores the executable side of an abstract in a synthetic
    `KAbstractImpl` class. Keeping the recognition here means all five
    targets validate exactly the same source contract and keep ordinary
    abstracts on their existing erasure path.
**/
class ValueTypeSupport {
    public static inline final MARKER = ":valueType";
    public static inline final ERROR = "value type markers accept single-field abstracts over a primitive representation only";

    public static function isMarkedAbstract(abs:AbstractType):Bool {
        return abs.meta.has(MARKER);
    }

    public static function markedAbstractOfClass(cls:ClassType):Null<AbstractType> {
        return switch (cls.kind) {
            case KAbstractImpl(ref) if (isMarkedAbstract(ref.get())): ref.get();
            case _: null;
        };
    }

    public static function infoOfClass(cls:ClassType):Null<ValueTypeInfo> {
        final abs = markedAbstractOfClass(cls);
        return abs == null ? null : {
            abstractType: abs,
            implementation: cls,
            name: abs.name,
            representation: abs.type
        };
    }

    /**
        Runs once from each target's after-typing hook. Non-abstract uses of
        the marker are rejected before declaration lowering can silently drop
        them with the ordinary synthetic-class filters.
    **/
    public static function validateModules(modules:Array<ModuleType>):Void {
        for (module in modules) {
            switch (module) {
                case TAbstract(ref):
                    final abs = ref.get();
                    if (isMarkedAbstract(abs) && !isValidAbstract(abs)) {
                        Context.error(ERROR, abs.pos);
                    }
                case TClassDecl(ref):
                    final cls = ref.get();
                    if (cls.meta.has(MARKER)) {
                        Context.error(ERROR, cls.pos);
                    }
                case TEnumDecl(ref):
                    final en = ref.get();
                    if (en.meta.has(MARKER)) {
                        Context.error(ERROR, en.pos);
                    }
                case TTypeDecl(ref):
                    final def = ref.get();
                    if (def.meta.has(MARKER)) {
                        Context.error(ERROR, def.pos);
                    }
            }
        }
    }

    public static function isValidAbstract(abs:AbstractType):Bool {
        return abs.params.length == 0 && primitiveRepresentation(abs.type);
    }

    /** The marker's closed representation set; aliases do not widen it. */
    public static function primitiveRepresentation(t:Type):Bool {
        return switch (t) {
            case TAbstract(ref, params): final abs = ref.get(); params.length == 0 && (abs.name == "Int" || abs.name == "Float" || abs.name == "Bool");
            case TInst(ref, params): final cls = ref.get(); params.length == 0 && cls.name == "String" && cls.pack.length == 0;
            case _: false;
        };
    }

    public static function isFloatRepresentation(abs:AbstractType):Bool {
        return switch (abs.type) {
            case TAbstract(ref, params): params.length == 0 && ref.get().name == "Float";
            case _: false;
        };
    }

    /** Finds a marked wrapper directly, or through `Null<Wrapper>`. */
    public static function markedAbstractOfType(t:Null<Type>):Null<AbstractType> {
        if (t == null)
            return null;
        return switch (t) {
            case TAbstract(ref, params):
                final abs = ref.get();
                if (isMarkedAbstract(abs)) abs else if (abs.name == "Null" && params.length == 1) markedAbstractOfType(params[0]) else null;
            case _: null;
        };
    }

    public static function sameAbstract(a:AbstractType, b:AbstractType):Bool {
        return a.name == b.name && a.module == b.module;
    }

    public static function operatorOf(abs:AbstractType, field:ClassField):Null<ValueTypeOperator> {
        for (entry in abs.binops) {
            if (entry.field.name == field.name)
                return Binary(entry.op);
        }
        for (entry in abs.unops) {
            if (entry.field.name == field.name)
                return Unary(entry.op);
        }
        return null;
    }

    public static function binaryOperatorField(abs:AbstractType, op:Binop):Null<ClassField> {
        for (entry in abs.binops) {
            if (entry.op == op)
                return entry.field;
        }
        return null;
    }

    public static function unaryOperatorField(abs:AbstractType, op:Unop):Null<ClassField> {
        for (entry in abs.unops) {
            if (entry.op == op)
                return entry.field;
        }
        return null;
    }

    public static function memberField(abs:AbstractType, name:String):Null<ClassField> {
        if (abs.impl == null)
            return null;
        for (field in abs.impl.get().statics.get()) {
            if (field.name == name)
                return field;
        }
        return null;
    }

    public static function constructorName(abs:AbstractType):String {
        return "make" + upperFirst(abs.name);
    }

    public static function upperFirst(value:String):String {
        return value.length == 0 ? value : value.charAt(0).toUpperCase() + value.substr(1);
    }

    public static function constructorField(abs:AbstractType):Null<ClassField> {
        if (abs.impl == null)
            return null;
        for (field in abs.impl.get().statics.get()) {
            if (field.name == "_new")
                return field;
        }
        return null;
    }

    public static function constructorThrows(abs:AbstractType):Bool {
        final ctor = constructorField(abs);
        return ctor != null && expressionContainsThrow(ctor.expr());
    }

    /** The stored field name used by each target's wrapper declaration. */
    public static function representationFieldName(abs:AbstractType):String {
        final ctor = constructorField(abs);
        if (ctor != null) {
            final first = firstArgument(ctor);
            if (first != null)
                return first.name;
        }
        return "value";
    }

    public static function functionArgs(field:ClassField):Array<{name:String, type:Type, opt:Bool}> {
        return switch (field.type) {
            case TFun(args, _): [for (a in args) {name: a.name, type: a.t, opt: a.opt}];
            case _: [];
        };
    }

    public static function functionReturn(field:ClassField):Null<Type> {
        return switch (field.type) {
            case TFun(_, ret): ret;
            case _: null;
        };
    }

    public static function firstArgument(field:ClassField):Null<{name:String, type:Type}> {
        final args = functionArgs(field);
        return args.length == 0 ? null : {name: args[0].name, type: args[0].type};
    }

    public static function hasReceiver(field:ClassField):Bool {
        final first = firstArgument(field);
        return first != null && first.name == "this";
    }

    public static function isWrapperField(field:ClassField, abs:AbstractType):Bool {
        return switch (markedAbstractOfType(field.type)) {
            case null: false;
            case other: sameAbstract(other, abs);
        };
    }

    /** Private inline helpers are compile-time implementation details. */
    public static function isInlineHelper(field:ClassField):Bool {
        if (field.isPublic)
            return false;
        return switch (field.kind) {
            case FMethod(MethInline) | FMethod(MethMacro): true;
            case _: false;
        };
    }

    /** The value assigned to Haxe's synthetic `this` in an inline wrapper. */
    public static function syntheticValue(e:Null<TypedExpr>):Null<TypedExpr> {
        if (e == null || markedAbstractOfType(e.t) == null)
            return null;
        return switch (e.expr) {
            case TBlock(stmts):
                var result:Null<TypedExpr> = null;
                final syntheticLocals:Map<Int, TypedExpr> = [];
                for (stmt in stmts) {
                    switch (stmt.expr) {
                        case TVar(v, init) if (init != null && isSyntheticThisName(v.name)):
                            syntheticLocals.set(v.id, init);
                            result = init;
                        case TBinop(OpAssign, lhs, rhs) if (isThisLocal(lhs)): result = rhs;
                        case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
                            switch (unwrapDecorations(inner).expr) {
                                case TLocal(v) if (syntheticLocals.exists(v.id)): result = syntheticLocals.get(v.id);
                                case _:
                            }
                        case _:
                    }
                }
                result;
            case _: null;
        };
    }

    public static function isThisDeclaration(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TVar(v, _) if (isSyntheticThisName(v.name)): true;
            case _: false;
        };
    }

    public static function isThisAssignment(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TBinop(OpAssign, lhs, _): isThisLocal(lhs);
            case _: false;
        };
    }

    public static function isThisReturn(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TReturn(value) if (value != null): isThisLocal(value);
            case _: false;
        };
    }

    public static function unwrapDecorations(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): unwrapDecorations(inner);
            case _: e;
        };
    }

    public static function expressionContainsThrow(e:Null<TypedExpr>):Bool {
        if (e == null)
            return false;
        var found = false;
        function walk(node:TypedExpr):Void {
            if (found)
                return;
            switch (node.expr) {
                case TThrow(_):
                    found = true;
                case _:
                    TypedExprTools.iter(node, walk);
            }
        }
        walk(e);
        return found;
    }

    static function isThisLocal(e:TypedExpr):Bool {
        return switch (unwrapDecorations(e).expr) {
            case TLocal(v): isSyntheticThisName(v.name);
            case _: false;
        };
    }

    static function isSyntheticThisName(name:String):Bool {
        return name == "this" || StringTools.startsWith(name, "this");
    }
}
#end
