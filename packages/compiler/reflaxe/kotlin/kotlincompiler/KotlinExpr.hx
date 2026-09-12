package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import ExpressionPredicates;
import PolicyQueries;
import ExpressionBlockNorm;
import AssignTargetPlan;
import AssignTargetPlan.AssignTargetFieldKind;
import PolicyQueries.StdStringCategory;
import PolicyQueries.Int64Op;
import PolicyQueries.VariantArmStep;
import PolicyQueries.EnumQueryStep;
import FusionPlan;
import FusionPlan.FusionStep;
import VarFusionPlan;
import ValueTypeSupport;
import ValueTypePlan;
import ValueTypeSupport.ValueTypeOperator;

/**
    Statement and expression lowering from the Haxe typed AST to Kotlin.
**/
class KotlinExpr {
    // EnumCycleDetector classification is shared by PolicyQueries.
    final imports:KotlinImports;
    final types:KotlinType;
    final state:KotlinEmissionState;

    /** True while emitting a function whose return type is ReadOnlyArray. */
    var decodeBoundary:Bool = false;

    /** True while rendering an expression used to initialize a writable array. */
    var mutableArrayAccess:Bool = false;

    /** Locals whose array values are modified through indexed assignment. */
    final mutableArrayLocals:Map<Int, Bool> = [];
    /** True while lowering a value position that expects a function type. */
    var functionTypeExpected:Bool = false;

    /** Enum-capture locals mapped to the payload expression they stand for. */
    final subst:Map<Int, String> = [];

    /** Catch variables of the region being lowered; features/06 catch-site lowering. */
    final catchVars:Map<Int, Bool> = [];

    /** Locals reassigned after their declaration; emitted with var. */
    final mutated:Map<Int, Bool> = [];

    /** Fill arrays returning as asList() when decodeBoundary holds. */
    final asListReturn:Map<Int, String> = [];

    /** Locals backed by the FPHelper high/low boundary object. */
    final fpInt64Halves:Map<Int, Bool> = [];

    /** Names used by parameters and locals; generated names avoid them. */
    final usedNames:Map<String, Bool> = [];

    final hiddenNames:Map<Int, String> = [];

    /** Rendered local names already assigned in the current function. */
    final localNames:Map<Int, String> = [];
    final emittedLocalNames:Map<String, Int> = [];

    /** Active runtime renderers for cyclic enum stringification. */
    final enumStringNaming:EnumStringHelperNaming = new EnumStringHelperNaming();

    /** Locals whose control-flow or normalization initializer proves non-null. */
    final nonNullLocals:Map<Int, Bool> = [];

    /** Locals initialized from null retain nullable access semantics. */
    final nullInitializedLocals:Map<Int, Bool> = [];

    /** Locals whose inferred Kotlin initializer remains nullable. */
    final nullableRenderedLocals:Map<Int, Bool> = [];

    /** Locals compared with null somewhere in the currently emitted statement block. */
    var activeNullGuardLocals:Map<Int, Bool> = [];

    /** Null comparisons in the current statement block, keyed by local id and source position. */
    var activeNullGuardPositions:Map<Int, Array<{file:String, min:Int, max:Int}>> = [];

    static final nullInitializedFields:Map<String, Bool> = [];

    public static function registerNullInitializedField(key:String):Void {
        nullInitializedFields.set(key, true);
    }

    /** Field reads proven non-null by a dominating null check. */
    final nonNullFields:Map<String, Bool> = [];

    /** Enum locals narrowed to a constructor by the active switch arm. */
    final enumVariants:Map<Int, String> = [];

    final enumVariantExpressions:Map<String, String> = [];

    var hiddenCounter:Int = 0;

    /** Fresh names for the trailing-unit reads of stdlib/08 checks. */
    var stringBufTailCounter:Int = 0;

    /** Constructor parameter name -> rendered argument, for coalescing defaults that read an earlier parameter. */
    var constructorParameterValues:Null<Map<String, String>> = null;

    /** Function context used to distinguish a sanctioned coalescing site. */
    var currentClass:Null<ClassType> = null;

    var currentField:Null<String> = null;
    var currentLocalName:Null<String> = null;

    /** Return type of the function currently being lowered; null outside function context. */
    var currentReturnType:Null<Type> = null;

    /** Whether bare returns are being lowered inside the synthesized test runner lambda. */
    var inTestRunnerLambda:Bool = false;

    public function new(imports:KotlinImports, types:KotlinType, state:KotlinEmissionState) {
        this.imports = imports;
        this.types = types;
        this.state = state;
    }

    public function setTestRunnerLambda(enabled:Bool):Void {
        inTestRunnerLambda = enabled;
    }

    public function reserveName(name:String):Void {
        usedNames.set(name, true);
    }

    /** Binds a local to a rendered name; pattern captures adopt the payload argument name this way. */
    public function bindLocalName(v:TVar, name:String):Void {
        subst.set(v.id, name);
    }

    /** The rendered name of a local, if a binding was recorded. */
    public function boundNameOf(v:TVar):Null<String> {
        return subst.get(v.id);
    }

    public function resetLocalNames():Void {
        hiddenNames.clear();
        localNames.clear();
        emittedLocalNames.clear();
    }

    public function setDecodeBoundary(value:Bool):Void {
        decodeBoundary = value;
    }

    public function setFunctionTypeExpected(value:Bool):Void {
        functionTypeExpected = value;
    }

    public function expressionOf(e:TypedExpr):String {
        return expr(e);
    }

    public function topLevelStatements(e:TypedExpr):String {
        scanLocals(e);
        return blockLines(statementsOf(e), 0).join("\n");
    }

    public function rawExpression(e:TypedExpr):String {
        return expr(e);
    }

    public function rawArrayExpression(e:TypedExpr, wrapper:String):String {
        return switch (stripWrap(e).expr) {
            case TArrayDecl(elements): wrapper + "(" + [for (x in elements) expr(x)].join(", ") + ")";
            case _: rawExpression(e);
        };
    }

    function coalescingSiteFor(e:TypedExpr):Null<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> {
        if (currentClass == null || currentField == null)
            return null;
        final site = DefaultArgExpander.coalescingSite(e);
        final value = currentLocalName != null ? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName,
            site == null ? "" : site.parameter) : DefaultArgExpander.coalescingDefaultForParam(currentClass, currentField, site == null ? "" : site.parameter);
        if (site == null)
            return null;
        if (value == null && !DefaultArgExpander.isNormalizationSource(site.defaultExpr.pos))
            return null;
        return site;
    }

    public function defaultArgText(value:DefaultArgExpander.DefaultArgValue, targetType:Type):String {
        return switch (value) {
            case VInt(v): isFloatExpectedType(targetType) ? intToFloatText(Std.string(v)) : Std.string(v);
            case VFloat(s): floatLiteral(s);
            case VString(s): quoteString(s);
            case VBool(b): b ? "true" : "false";
            case VNull: "null";
            case VEnum(enumRef, enumField): types.of(Type.TEnum(enumRef, [])) + "." + enumField.name;
            case VCoalescing(coalescing): coalescingDefaultText(coalescing, targetType);
        };
    }

    public function coalescingDefaultText(value:DefaultArgExpander.CoalescingDefaultValue, targetType:Type):String {
        return switch (value) {
            case CInt(v): isFloatExpectedType(targetType) ? intToFloatText(Std.string(v)) : Std.string(v);
            case CFloat(s): floatLiteral(s);
            case CString(s): quoteString(s);
            case CBool(b): b ? "true" : "false";
            case CNull: "null";
            case CEmptyArray:
                final element = switch (Context.follow(DefaultArgExpander.withoutNull(targetType))) {
                    case TInst(_, params) if (params.length > 0): types.of(params[0]);
                    case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length > 0): types.of(params[0]);
                    case _: "Nothing";
                };
                "mutableListOf<" + element + ">()";
            case CEmptyMap: "mutableMapOf()";
            case CPositiveInfinity: FloatPrecision.isF32() ? "Float.POSITIVE_INFINITY" : "Double.POSITIVE_INFINITY";
            case CNegativeInfinity: FloatPrecision.isF32() ? "Float.NEGATIVE_INFINITY" : "Double.NEGATIVE_INFINITY";
            case CEnum(enumRef, enumField): types.of(Type.TEnum(enumRef, [])) + "." + enumField.name;
            case CParameterRead(name): constructorParameterValues != null && constructorParameterValues.exists(name) ? constructorParameterValues.get(name) : KotlinNameEscape.escape(name);
            case CInstanceFieldRead(name): "this." + KotlinNameEscape.escape(name);
            case CLocalRead(name): KotlinNameEscape.escape(name);
            case CFieldAccess(CParameterRead(staticPath), ""): constructorParameterValues != null && constructorParameterValues.exists(staticPath) ? constructorParameterValues.get(staticPath) : coalescingStaticFieldText(staticPath);
            case CFieldAccess(receiver, fieldName): coalescingDefaultText(receiver, targetType)
                + "."
                + KotlinNameEscape.escape(fieldName == "length" ? "size" : fieldName);
            case CMethodCall(receiver, methodName, args):
                coalescingDefaultText(receiver, targetType)
                + "."
                + KotlinNameEscape.escape(kotlinMethodName(methodName))
                + "("
                + [for (a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
            case CStaticCall(modulePath, className, methodName, args):
                coalescingStaticCallText(modulePath, className, methodName, args, targetType);
            case CConditional(c, t, f):
                "if ("
                + coalescingDefaultText(c, targetType)
                + ") "
                + coalescingDefaultText(t, targetType)
                + " else "
                + coalescingDefaultText(f, targetType);
            case CBinaryOp(op, left, right):
                coalescingDefaultText(left, targetType)
                + " "
                + opStr(op)
                + " "
                + coalescingDefaultText(right, targetType);
            case CConstructorCall(modulePath, name, args):
                imports.requireType(modulePath, name);
                name + "(" + [for (a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
        };
    }

    function coalescingStaticCallText(modulePath:String, className:String, methodName:String, args:Array<DefaultArgExpander.CoalescingDefaultValue>,
            targetType:Type):String {
        final rendered = [for (a in args) coalescingDefaultText(a, targetType)].join(", ");
        if (modulePath == "std.SortedMap" && methodName == "builder") {
            final key = switch (Context.follow(DefaultArgExpander.withoutNull(targetType))) {
                case TInst(_, params) if (params.length > 0): params[0];
                case _: null;
            };
            final value = switch (Context.follow(DefaultArgExpander.withoutNull(targetType))) {
                case TInst(_, params) if (params.length > 1): params[1];
                case _: null;
            };
            imports.requireType("std.SortedMap", "SortedTable");
            return "SortedTable.mapBuilder<"
                + types.of(key)
                + ", "
                + types.of(value)
                + ">("
                + sortedComparator("std.SortedMap", key, Context.currentPos())
                + ")";
        }
        if (modulePath == "std.SortedSet" && methodName == "builder") {
            final key = switch (Context.follow(DefaultArgExpander.withoutNull(targetType))) {
                case TInst(_, params) if (params.length > 0): params[0];
                case _: null;
            };
            imports.requireType("std.SortedSet", "SortedTable");
            return "SortedTable.setBuilder<" + types.of(key) + ">(" + sortedComparator("std.SortedSet", key, Context.currentPos()) + ")";
        }
        imports.requireType(modulePath, className);
        return className + "." + methodName + "(" + rendered + ")";
    }

    /**
        Renders a sanctioned coalescing default in a constructor-call context,
        resolving reads of earlier constructor parameters against the actual
        call arguments (mirrors Dart's constructorCoalescingText). A bare
        parameter read like `kind` in `locale = if (kind == Bopomofo) ...`
        is only in scope inside the class, so the call site substitutes
        the argument actually passed for that parameter.
     */
    function constructorCoalescingText(value:DefaultArgExpander.CoalescingDefaultValue, targetType:Type, cls:ClassType, args:Array<TypedExpr>):String {
        return switch (value) {
            case CParameterRead(name):
                final parameterIndex = switch (cls.constructor == null ? null : Context.follow(cls.constructor.get().type)) {
                    case TFun(values, _):
                        var found = -1;
                        for (i in 0...values.length)
                            if (values[i].name == name) found = i;
                        found;
                    case _: -1;
                };
                parameterIndex >= 0 && parameterIndex < args.length ? expr(args[parameterIndex]) : KotlinNameEscape.escape(name);
            case CConditional(c, ifTrue, ifFalse):
                "if ("
                + constructorCoalescingText(c, targetType, cls, args)
                + ") "
                + constructorCoalescingText(ifTrue, targetType, cls, args)
                + " else "
                + constructorCoalescingText(ifFalse, targetType, cls, args);
            case CFieldAccess(CParameterRead(staticPath), ""):
                coalescingStaticFieldText(staticPath);
            case CFieldAccess(receiver, fieldName):
                final renderedReceiver = constructorCoalescingText(receiver, targetType, cls, args);
                fieldName.length == 0 ? renderedReceiver : renderedReceiver + "." + KotlinNameEscape.escape(fieldName == "length" ? "size" : fieldName);
            case CMethodCall(receiver, methodName, callArgs):
                constructorCoalescingText(receiver, targetType, cls, args)
                + "."
                + KotlinNameEscape.escape(kotlinMethodName(methodName))
                + "("
                + [for (a in callArgs) constructorCoalescingText(a, targetType, cls, args)].join(", ")
                + ")";
            case CBinaryOp(op, left, right):
                constructorCoalescingText(left, targetType, cls, args)
                + " "
                + opStr(op)
                + " "
                + constructorCoalescingText(right, targetType, cls, args);
            case CConstructorCall(modulePath, name, callArgs):
                imports.requireType(modulePath, name);
                name + "(" + [for (a in callArgs) constructorCoalescingText(a, targetType, cls, args)].join(", ") + ")";
            case CStaticCall(modulePath, className, methodName, callArgs):
                constructorStaticCallText(modulePath, className, methodName, callArgs, targetType, cls, args);
            default: coalescingDefaultText(value, targetType);
        };
    }

    function constructorDefaultText(value:DefaultArgExpander.DefaultArgValue, targetType:Type, cls:ClassType, args:Array<TypedExpr>):String {
        return switch (value) {
            case VCoalescing(coalescing): constructorCoalescingText(coalescing, targetType, cls, args);
            default: defaultArgText(value, targetType);
        };
    }

    function coalescingStaticFieldText(path:String):String {
        final parts = path.split(".");
        if (parts.length < 2)
            return path;
        final fieldName = parts[parts.length - 1];
        final typePath = parts.slice(0, parts.length - 1).join(".");
        try {
            switch (Context.getType(typePath)) {
                case TInst(clsRef, _):
                    return staticRef(clsRef.get(), fieldName);
                default:
            }
        } catch (_:Dynamic) {}
        return path;
    }

    /**
        Static-call rendering inside a constructor coalescing default. Mirrors
        coalescingStaticCallText but resolves the call's own arguments through
        constructorCoalescingText so a parameter read (e.g. `region` in
        `PunctuationGluePlacements.forRegion(region)`) substitutes the actual
        constructor argument.
     */
    function constructorStaticCallText(modulePath:String, className:String, methodName:String, args:Array<DefaultArgExpander.CoalescingDefaultValue>,
            targetType:Type, cls:ClassType, ctorArgs:Array<TypedExpr>):String {
        final rendered = [for (a in args) constructorCoalescingText(a, targetType, cls, ctorArgs)].join(", ");
        if (modulePath == "std.SortedMap" && methodName == "builder") {
            final key = switch (Context.follow(DefaultArgExpander.withoutNull(targetType))) {
                case TInst(_, params) if (params.length > 0): params[0];
                case _: null;
            };
            final value = switch (Context.follow(DefaultArgExpander.withoutNull(targetType))) {
                case TInst(_, params) if (params.length > 1): params[1];
                case _: null;
            };
            imports.requireType("std.SortedMap", "SortedTable");
            return "SortedTable.mapBuilder<"
                + types.of(key)
                + ", "
                + types.of(value)
                + ">("
                + sortedComparator("std.SortedMap", key, Context.currentPos())
                + ")";
        }
        if (modulePath == "std.SortedSet" && methodName == "builder") {
            final key = switch (Context.follow(DefaultArgExpander.withoutNull(targetType))) {
                case TInst(_, params) if (params.length > 0): params[0];
                case _: null;
            };
            imports.requireType("std.SortedSet", "SortedTable");
            return "SortedTable.setBuilder<" + types.of(key) + ">(" + sortedComparator("std.SortedSet", key, Context.currentPos()) + ")";
        }
        imports.requireType(modulePath, className);
        return className + "." + methodName + "(" + rendered + ")";
    }

    static function kotlinMethodName(name:String):String {
        return switch (name) {
            case "toUpperCase": "uppercase";
            case "toLowerCase": "lowercase";
            default: name;
        };
    }

    static function opStr(op:Binop):String {
        return switch (op) {
            case OpAdd: "+";
            case OpMult: "*";
            case OpDiv: "/";
            case OpMod: "%";
            case OpEq: "==";
            case OpNotEq: "!=";
            case OpLt: "<";
            case OpLte: "<=";
            case OpGt: ">";
            case OpGte: ">=";
            case OpBoolAnd: "&&";
            case OpBoolOr: "||";
            case OpShl: "shl";
            case OpShr: "shr";
            case OpXor: "xor";
            case OpAssign: "=";
            case _: "?";
        };
    }

    // ------------------------------------------------------------------
    // Function bodies
    // ------------------------------------------------------------------

    public function functionBody(cls:ClassType, f:ClassFuncData):Array<String> {
        if (f.expr == null) {
            Context.error("function field has no body to lower", f.field.pos);
        }
        DefaultArgExpander.completeRootExprForKotlin(cls, f.field.name, f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentField = f.field.name;
        currentLocalName = null;
        currentReturnType = switch (Context.follow(f.field.type)) {
            case TFun(_, ret): ret;
            case _: null;
        };
        nonNullLocals.clear();
        nullInitializedLocals.clear();
        nullableRenderedLocals.clear();
        nonNullFields.clear();
        enumVariants.clear();
        registerNonNullDefaultParams(cls, f);
        // Fuse declaration-plus-assignment pairs before the mutation scan.
        // The typer lowers abstract-inline receiver bindings as `TVar(v,
        // null)` followed by an assignment; the fused initializer is the
        // declaration's own initialization, so the scan must not read it as
        // a reassignment.
        final fusedRoot = fuseWithin(f.expr);
        f.expr.expr = fusedRoot.expr;
        scanLocals(f.expr);
        final result = blockLines(statementsOf(f.expr), 1);
        currentReturnType = null;
        return result;
    }

    /** Body lowering for members declared on a value wrapper. */
    public function valueTypeFunctionBody(cls:ClassType, f:ClassFuncData, fieldName:String):Array<String> {
        final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
        if (valueType != null && ValueTypeSupport.operatorOf(valueType, f.field) != null) {
            if (f.args.length > 0)
                bindLocalName(f.args[0].tvar, fieldName);
            if (f.args.length > 1)
                bindLocalName(f.args[1].tvar, "other");
        } else if (ValueTypeSupport.hasReceiver(f.field) && f.args.length > 0) {
            bindLocalName(f.args[0].tvar, fieldName);
        }
        return functionBody(cls, f);
    }

    /** Drops the representation assignment from a validating wrapper init. */
    public function valueTypeConstructorBody(cls:ClassType, f:ClassFuncData):Array<String> {
        if (f.expr == null)
            Context.error("value type constructor has no body to lower", f.field.pos);
        DefaultArgExpander.completeRootExprForKotlin(cls, f.field.name, f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentField = f.field.name;
        currentLocalName = null;
        for (a in f.args)
            reserveName(a.name);
        scanLocals(f.expr);
        final out:Array<String> = [];
        for (stmt in statementsOf(f.expr)) {
            if (ValueTypeSupport.isThisDeclaration(stmt) || ValueTypeSupport.isThisAssignment(stmt) || ValueTypeSupport.isThisReturn(stmt))
                continue;
            for (line in stmtLines(stmt, 2))
                out.push(line);
        }
        return out;
    }

    /**
        The constructor body's init-block lines and the fields it
        initializes (feature spec 27): every statement renders at
        init-block depth, except `this.f = f` where f is a constructor
        parameter, which the primary constructor already performs. An
        assignment to a field the constructor does not receive as a
        parameter is that field's initialization; its name joins
        `assigned` so the declaration drops its synthetic initializer. An
        assignment to a parameter field from any other expression stops
        the compilation.
    **/
    public function initBlockStatements(cls:ClassType, f:ClassFuncData):{lines:Array<String>, assigned:Array<String>, superDelegation:Null<String>} {
        if (f.expr == null) {
            return {lines: [], assigned: [], superDelegation: null};
        }
        DefaultArgExpander.completeRootExprForKotlin(cls, f.field.name, f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        for (a in f.args) {
            reserveName(a.name);
            if (a.tvar != null)
                localName(a.tvar);
        }
        currentClass = cls;
        currentField = f.field.name;
        currentLocalName = null;
        nonNullLocals.clear();
        nullInitializedLocals.clear();
        nullableRenderedLocals.clear();
        nonNullFields.clear();
        enumVariants.clear();
        registerNonNullDefaultParams(cls, f);
        scanLocals(f.expr);
        final out:Array<String> = [];
        final assigned:Array<String> = [];
        final renderable:Array<TypedExpr> = [];
        var superDelegation:Null<String> = null;
        for (s in statementsOf(f.expr)) {
            final info = ctorStmtInfo(s, f);
            if (info.render) {
                // Detect super() calls and extract delegation args instead
                // of rendering them as init-block statements.  Kotlin
                // requires constructor delegation in the class header, not
                // in the init block.
                switch (s.expr) {
                    case TCall({expr: TConst(TSuper)}, args) if (superDelegation == null):
                        final renderedArgs = [for (a in args) expr(a)];
                        superDelegation = "(" + renderedArgs.join(", ") + ")";
                        continue;
                    case _:
                }
                renderable.push(s);
            }
            if (info.initialized != null && assigned.indexOf(info.initialized) < 0) {
                assigned.push(info.initialized);
            }
        }
        for (l in blockLines(renderable, 1))
            out.push(l);
        return {lines: out, assigned: assigned, superDelegation: superDelegation};
    }

    /**
        Per-statement decision behind initBlockStatements: `render` says
        whether the statement reaches the init block, `initialized` names
        the field a non-parameter assignment initializes.
    **/
    function ctorStmtInfo(s:TypedExpr, f:ClassFuncData):{render:Bool, initialized:Null<String>} {
        switch (s.expr) {
            case TBinop(OpAssign, target, value):
                switch (target.expr) {
                    case TField({expr: TConst(TThis)}, FInstance(_, _, cf)):
                        final name = cf.get().name;
                        if (Lambda.exists(f.args, a -> a.name == name)) {
                            final coalescing = coalescingSiteFor(value);
                            if (coalescing != null && coalescing.parameter == name) {
                                return {render: false, initialized: null};
                            }
                            final registered = DefaultArgExpander.coalescingDefaultForParam(currentClass, f.field.name, name);
                            if (registered != null) {
                                return {render: false, initialized: null};
                            }
                            final directCoalescing = switch (value.expr) {
                                case TIf(_, t, f) if (t != null || f != null):
                                    switch (t.expr) {
                                        case TLocal(v) if (v.name == name): true;
                                        case _: switch (f.expr) {
                                                case TLocal(v) if (v.name == name): true;
                                                case _: false;
                                            }
                                    }
                                case _: false;
                            };
                            if (directCoalescing && !requiredNullableConstructorField(currentClass, f, name)) {
                                return {render: false, initialized: null};
                            }
                            if (directCoalescing) {
                                return {render: true, initialized: name};
                            }
                            final fromParam = switch (value.expr) {
                                case TLocal(v): v.name == name;
                                case _: false;
                            };
                            if (!fromParam) {
                                Context.error("constructor assigns "
                                    + name
                                    + " from another expression; assign the constructor parameter "
                                    + name
                                    + " directly", s.pos);
                            }
                            // The primary constructor performs this
                            // initialization from its parameter.
                            return {render: false, initialized: null};
                        }
                        return {render: true, initialized: name};
                    case _:
                }
            case _:
        }
        return {render: true, initialized: null};
    }

    function requiredNullableConstructorField(cls:ClassType, f:ClassFuncData, name:String):Bool {
        final arg = Lambda.find(f.args, a -> a.name == name);
        if (arg == null || !isNullType(arg.type))
            return false;
        for (field in cls.fields.get())
            if (field.name == name)
                return !isNullType(field.type) && DefaultArgExpander.defaultAt(cls, f.field.name, arg.index) == null;
        return false;
    }

    // ------------------------------------------------------------------
    // Statements
    // ------------------------------------------------------------------

    public function statementsOf(e:TypedExpr):Array<TypedExpr> {
        return PolicyQueries.statementsOf(e);
    }

    function stmtLines(e:TypedExpr, depth:Int):Array<String> {
        switch (e.expr) {
            case TVar(v, init) if (init != null && isTryRegion(init)):
                final parts = tryRegionParts(init);
                if (regionTailValue(statementsOf(parts.body)) == null) {
                    return fail(init, "try region body has no value");
                }
                return tryLines(parts.body, parts.c, depth, 'val ${localName(v)} = ');
            case TVar(v, init) if (init != null && isStringBufToStringCall(init)):
                return stringBufToStringBindingLines(v, stripWrap(init), depth);
            case TVar(v, init) if (init != null):
                final kw = mutated.exists(v.id) ? "var" : "val";
                switch (stripWrap(init).expr) {
                    case TLocal(origV) if (asListReturn.exists(origV.id)):
                        asListReturn.set(v.id, asListReturn.get(origV.id));
                    default:
                }
                final nullInitialized = switch (stripWrap(init).expr) {
                    case TConst(TNull): !isNullType(v.t) && isNullableReferenceType(v.t);
                    default: false;
                };
                if (nullInitialized)
                    nullInitializedLocals.set(v.id, true);
                final typeAnn = switch (stripWrap(init).expr) {
                    case TConst(TNull) if (nullInitialized): ": " + types.of(v.t) + "?";
                    case TConst(TNull): ": " + types.of(v.t);
                    default: "";
                };
                var initText = switch (init.expr) {
                    case TFunction(fn): functionLiteralNamed(v.name, fn);
                    default:
                        final previousMutableArrayAccess = mutableArrayAccess;
                        final wasFunctionTypeExpected = functionTypeExpected;
                        mutableArrayAccess = mutableArrayLocals.exists(v.id);
                        functionTypeExpected = PolicyQueries.isFunctionType(v.t);
                        final rendered = expr(init);
                        functionTypeExpected = wasFunctionTypeExpected;
                        mutableArrayAccess = previousMutableArrayAccess;
                        rendered;
                };
                // Haxe unifies Int and Float; widen Int initializers to Float
                // when the variable's declared type is Float.
                if (isIntOrLongType(emittedType(init)) && isFloatType(v.t))
                    initText = intToFloatText(initText);
                // Haxe permits binding a non-null local from a Null<T>
                // initializer (an unsound assignment); Kotlin infers the
                // initializer's nullable type, so the declaration extracts
                // once. The null-literal case keeps its declared-nullable
                // annotation above.
                final extractsAtDecl = !isNullType(v.t) && isNullType(init.t) && !activeNullGuardLocals.exists(v.id) && switch (stripWrap(init).expr) {
                    case TConst(TNull): false;
                    case _: true;
                };
                // A non-null local whose initializer renders nullable (e.g. a
                // field read off a nullable receiver) is inferred nullable by
                // Kotlin; extract once at the declaration so later accesses
                // use a plain dot. Computed before initText so the proof
                // state still reflects the scope preceding the binding.
                final initRendersNullable = rendersNullable(init);
                final extractRenderedNullable = !isNullType(v.t) && !isNullType(init.t) && initRendersNullable;
                if (initRendersNullable && !extractsAtDecl && !extractRenderedNullable)
                    nullableRenderedLocals.set(v.id, true);
                else
                    nullableRenderedLocals.remove(v.id);
                updateLocalProof(v, init);
                return [
                    indent(depth) + '$kw ${localName(v)}$typeAnn = $initText' + (extractsAtDecl || extractRenderedNullable ? "!!" : "")
                ];
            case TVar(v, init) if (init == null):
                // Deferred local declarations are initialized by later assignments;
                // Kotlin's definite-assignment analysis checks every read.
                return [indent(depth) + "var " + localName(v) + ": " + types.of(v.t)];
            case TBlock(stmts):
                final out = [indent(depth) + "run {"];
                for (l in blockLines(stmts, depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                return out;
            case TIf(c, t, f):
                final condition = expr(c) + (rendersNullable(c) ? " == true" : "");
                final base = proofSnapshot();
                addProofs(conditionProofs(c).thenPath);
                final out = [indent(depth) + "if (" + condition + ") {"];
                for (l in blockLines(statementsOf(t), depth + 1))
                    out.push(l);
                final afterThen = proofSnapshot();
                restoreProofs(base);
                final afterElse = if (f != null) {
                    addProofs(conditionProofs(c).elsePath);
                    out.push(indent(depth) + "} else {");
                    for (l in blockLines(statementsOf(f), depth + 1))
                        out.push(l);
                    proofSnapshot();
                } else {
                    addProofs(conditionProofs(c).elsePath);
                    proofSnapshot();
                };
                // A branch whose block terminates (return/throw) contributes no
                // survivors, so the merged state is the other branch alone.
                final thenTerminates = blockTerminates(t);
                final elseTerminates = f != null && blockTerminates(f);
                restoreProofs(if (thenTerminates != elseTerminates) (thenTerminates ? afterElse : afterThen) else intersectProofs(base, afterThen, afterElse));
                out.push(indent(depth) + "}");
                return out;
            case TWhile(c, b, true):
                final out = [indent(depth) + "while (" + expr(c) + ") {"];
                for (l in blockLines(statementsOf(b), depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                return out;
            case TWhile(_, _, false):
                return fail(e, "do-while has no lowering in the subset");
            case TReturn(ret) if (ret != null && isTryRegion(ret)):
                final parts = tryRegionParts(ret);
                if (regionTailValue(statementsOf(parts.body)) == null) {
                    return fail(ret, "try region body has no value");
                }
                return tryLines(parts.body, parts.c, depth, "return ");
            case TReturn(ret) if (ret == null):
                return [indent(depth) + (inTestRunnerLambda ? "return@run" : "return")];
            case TReturn(ret) if (isStringBufToStringCall(ret)):
                return stringBufToStringReturnLines(stripWrap(ret), depth);
            case TReturn(ret) if (isVariantSwitch(ret)):
                return whenReturnLines(stripWrap(ret), depth);
            case TReturn(ret):
                final inner = stripWrap(ret);
                switch (inner.expr) {
                    case TLocal(v) if (asListReturn.exists(v.id)):
                        return [indent(depth) + "return " + localName(v) + "." + asListReturn.get(v.id)];
                    case _:
                        final wasFunctionTypeExpected = functionTypeExpected;
                        functionTypeExpected = PolicyQueries.isFunctionType(currentReturnType);
                        var retText = expr(ret);
                        functionTypeExpected = wasFunctionTypeExpected;
                        if (rendersNullable(ret) && !isNullType(currentReturnType))
                            retText += "!!";
                        // Haxe unifies Int and Float; widen Int return values to
                        // Float when the function's return type is Float.
                        // Use emittedType because the typed AST type is Float
                        // (unified) while the generator emits Int text.
                        if (isIntOrLongType(emittedType(ret)) && isFloatType(currentReturnType))
                            retText = intToFloatText(retText);
                        return [indent(depth) + "return " + retText];
                }
            case TThrow(x):
                return [indent(depth) + "throw " + throwExpr(x)];
            case TTry(body, catches) if (catches.length == 1):
                return tryLines(body, catches[0], depth, "");
            case TTry(_, _):
                return fail(e, "try region handles exactly one exception domain");
            case TBreak:
                return [indent(depth) + "break"];
            case TContinue:
                return [indent(depth) + "continue"];
            case TCall(fn, args) if (stringBufMutationParts(fn) != null):
                return stringBufMutationLines(fn, args, depth);
            case TMeta(_, inner):
                return stmtLines(inner, depth);
            case _:
                return [indent(depth) + expr(e)];
        }
    }

    function throwExpr(x:TypedExpr):String {
        final inner = stripWrap(x);
        switch (inner.expr) {
            case TNew(c, _, args) if (args.length == 1 && KotlinDecl.isMessageOnlyException(c.get())):
                imports.requireType(c.get().module, c.get().name);
                return c.get().name + "(" + expr(args[0]) + ")";
            case TNew(c, _, args) if (args.length == 1 && state.exceptionPayloads.exists(c.get().module)):
                return exceptionVariant(c.get(), args[0]);
            case _:
        }
        return expr(x);
    }

    /**
        stdlib/08 string-buffer checks (Kotlin): every checked operation
        reads the trailing UTF-16 unit, and the fault constructs the
        sealed UnpairedSurrogate variant of std.UStringException. A throw
        is an expression here, so the checked operations stay usable in
        expression position; statements take the flat form below.
    **/
    function stringBufMutationParts(fn:TypedExpr):Null<{name:String, subj:TypedExpr}> {
        return PolicyQueries.stringBufMutationParts(fn);
    }

    function stringBufTailRead(subj:TypedExpr):String {
        return expr(subj) + ".lastOrNull()?.code ?: -1";
    }

    function isStringBufToStringCall(e:TypedExpr):Bool {
        return PolicyQueries.isStringBufToStringCall(e);
    }

    function stringBufToStringSubject(call:TypedExpr):TypedExpr {
        return PolicyQueries.stringBufToStringSubject(call);
    }

    /** Flat check for binding and return positions: one bound tail read, then the fault. */
    function stringBufToStringCheckLines(subj:TypedExpr, depth:Int):Array<String> {
        final tail = freshTailName();
        final lines = [indent(depth) + "val " + tail + " = " + stringBufTailRead(subj)];
        lines.push(indent(depth) + "if (" + stringBufLeadCond(tail) + ") {");
        lines.push(indent(depth + 1) + "throw " + stringBufFaultConstructor(tail));
        lines.push(indent(depth) + "}");
        return lines;
    }

    function stringBufToStringBindingLines(v:TVar, call:TypedExpr, depth:Int):Array<String> {
        final subj = stringBufToStringSubject(call);
        final lines = stringBufToStringCheckLines(subj, depth);
        final kw = mutated.exists(v.id) ? "var" : "val";
        lines.push(indent(depth) + kw + " " + localName(v) + " = " + expr(subj) + ".toString()");
        return lines;
    }

    function stringBufToStringReturnLines(call:TypedExpr, depth:Int):Array<String> {
        final subj = stringBufToStringSubject(call);
        final lines = stringBufToStringCheckLines(subj, depth);
        lines.push(indent(depth) + "return " + expr(subj) + ".toString()");
        return lines;
    }

    function stringBufLeadCond(x:String):String {
        return x + " >= 55296 && " + x + " <= 56319";
    }

    function stringBufTrailCond(x:String):String {
        return x + " >= 56320 && " + x + " <= 57343";
    }

    function stringBufAddFaultCond(subj:TypedExpr, partArg:TypedExpr):String {
        final part = expr(partArg);
        return stringBufLeadCond(stringBufTailRead(subj)) + " && " + part + ".length > 0" + " && !(" + part + "[0].code >= 56320 && " + part
            + "[0].code <= 57343)";
    }

    function stringBufAddCharFaultCond(subj:TypedExpr, unitArg:TypedExpr):String {
        return "(" + stringBufTrailCond(expr(unitArg)) + ") != (" + stringBufLeadCond(stringBufTailRead(subj)) + ")";
    }

    function stringBufDanglingCond(subj:TypedExpr):String {
        return stringBufLeadCond(stringBufTailRead(subj));
    }

    function stringBufFaultConstructor(unit:String):String {
        imports.requireType("std.UStringException", "UStringException");
        return "UStringException.UnpairedSurrogate(" + unit + ")";
    }

    function freshTailName():String {
        stringBufTailCounter += 1;
        return PolicyQueries.freshTailName(stringBufTailCounter);
    }

    /** Statement lowering: one bound tail read, the check, then the op. */
    function stringBufMutationLines(fn:TypedExpr, args:Array<TypedExpr>, depth:Int):Array<String> {
        final parts = stringBufMutationParts(fn);
        if (parts == null) {
            return [fail(fn, "not a string buffer mutation")];
        }
        final buf = expr(parts.subj);
        final tail = freshTailName();
        final lines = [indent(depth) + "val " + tail + " = " + stringBufTailRead(parts.subj)];
        if (parts.name == "add") {
            final part = stringBufPartText(args[0]);
            lines.push(indent(depth) + "if (" + stringBufLeadCond(tail) + " && " + part + ".length > 0" + " && !(" + part + "[0].code >= 56320 && " + part
                + "[0].code <= 57343)) {");
            lines.push(indent(depth + 1) + "throw " + stringBufFaultConstructor(tail));
            lines.push(indent(depth) + "}");
            lines.push(indent(depth) + buf + ".append(" + part + ")");
        } else {
            final u = expr(args[0]);
            lines.push(indent(depth) + "if (" + stringBufTrailCond(u) + ") {");
            lines.push(indent(depth + 1) + "if (!(" + stringBufLeadCond(tail) + ")) {");
            lines.push(indent(depth + 2) + "throw " + stringBufFaultConstructor(u));
            lines.push(indent(depth + 1) + "}");
            lines.push(indent(depth) + "} else if (" + stringBufLeadCond(tail) + ") {");
            lines.push(indent(depth + 1) + "throw " + stringBufFaultConstructor(tail));
            lines.push(indent(depth) + "}");
            lines.push(indent(depth) + buf + ".append((" + u + ").toChar())");
        }
        return lines;
    }

    function stringBufPartText(part:TypedExpr):String {
        final rendered = expr(part);
        return switch (stripWrap(part).expr) {
            case TLocal(_) | TConst(_): rendered;
            case _: "(" + rendered + ")";
        };
    }

    /** Renders `Owner.Variant` or `Owner.Variant(args)` for an exception construction over its payload enum. */
    function exceptionVariant(cls:ClassType, payloadArg:TypedExpr):String {
        final owner = state.payloadEnumOwners.get(state.exceptionPayloads.get(cls.module));
        // The variant renders as a member of the exception class, so a
        // cross-package construction site needs the class import.
        imports.requireType(cls.module, cls.name);
        final arg = stripWrap(payloadArg);
        switch (arg.expr) {
            case TField(_, FEnum(_, ef)):
                return owner + "." + ef.name;
            case TCall(fn, callArgs):
                switch (stripWrap(fn).expr) {
                    case TField(_, FEnum(_, ef)):
                        return owner + "." + ef.name + "(" + [for (a in callArgs) expr(a)].join(", ") + ")";
                    case _:
                }
            case _:
        }
        // Any other payload expression already carries the folded enum
        // type, which renders as the owner's sealed type; the value is the
        // variant itself, so no construction wraps it.
        return expr(payloadArg);
    }

    function fuseWithin(e:TypedExpr):TypedExpr {
        if (ValueTypeSupport.markedAbstractOfType(e.t) != null) {
            switch (e.expr) {
                case TBlock(_):
                    return e;
                case _:
            }
        }
        return switch (e.expr) {
            case TBlock(stmts):
                final fused = fuseUninitializedVars([for (s in stmts) fuseWithin(s)]);
                {expr: TBlock(fused), pos: e.pos, t: e.t};
            case _:
                TypedExprTools.map(e, fuseWithin);
        }
    }

    function fuseUninitializedVars(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final byDecl = new Map<Int, VarFusionPlan.VarFusionPlanEntry>();
        final removed = new Map<Int, Bool>();
        for (step in VarFusionPlan.plan(stmts, stripCast)) {
            byDecl.set(step.declIdx, step);
            removed.set(step.assignIdx, true);
        }
        final remaining = [for (i in 0...stmts.length) if (!removed.exists(i)) stmts[i]];
        final out:Array<TypedExpr> = [];
        for (i in 0...stmts.length) {
            if (removed.exists(i))
                continue;
            final step = byDecl.get(i);
            if (step == null) {
                out.push(stmts[i]);
                continue;
            }
            switch (stmts[i].expr) {
                case TVar(v, _):
                    out.push({expr: TVar(v, step.rhs), pos: stmts[i].pos, t: stmts[i].t});
                case _:
                    out.push(stmts[i]);
            }
        }
        return out;
    }

    /** Expression-position block lowering (features/43). */
    function blockExpression(stmts:Array<TypedExpr>):String {
        stmts = ExpressionBlockNorm.normalize(stmts, (e, message) -> fail(e, message), _ -> "expression block must end in a value statement (features/43)",
            "expression block allows only declarations before its value statement (features/43)");
        final out = ["run {"];
        for (line in blockLines(stmts, 1))
            out.push(line);
        out.push("}");
        return out.join("\n");
    }

    function blockLines(stmts:Array<TypedExpr>, depth:Int):Array<String> {
        stmts = fuseUninitializedVars(stmts);
        stmts = regroupLoops(stmts);
        final out:Array<String> = [];
        final previousNullGuards = activeNullGuardLocals;
        final previousNullGuardPositions = activeNullGuardPositions;
        final localNullGuards = nullGuardLocalsInBlock(stmts);
        activeNullGuardLocals = [];
        for (k in previousNullGuards.keys())
            activeNullGuardLocals.set(k, true);
        for (k in localNullGuards.keys())
            activeNullGuardLocals.set(k, true);
        final localNullGuardPositions = nullGuardPositionsInBlock(stmts);
        activeNullGuardPositions = [];
        for (k in previousNullGuardPositions.keys())
            activeNullGuardPositions.set(k, previousNullGuardPositions.get(k).copy());
        for (k in localNullGuardPositions.keys()) {
            var entries = activeNullGuardPositions.get(k);
            if (entries == null) {
                entries = [];
                activeNullGuardPositions.set(k, entries);
            }
            for (entry in localNullGuardPositions.get(k))
                entries.push(entry);
        }

        var i = 0;
        while (i < stmts.length) {
            final fused = fillFusion(stmts, i, depth);
            if (fused != null) {
                for (l in fused)
                    out.push(l);
                i += 2;
                continue;
            }
            final loop = matchInterval(stmts[i]);
            if (loop != null) {
                for (l in loopLines(loop, depth))
                    out.push(l);
                i += 1;
                continue;
            }
            for (l in stmtLines(stmts[i], depth))
                out.push(l);
            i += 1;
        }
        activeNullGuardLocals = previousNullGuards;
        activeNullGuardPositions = previousNullGuardPositions;
        return out;
    }

    /** Finds locals whose nullable state is deliberately tested in this block.
        Such locals must remain nullable at their declaration so the generated
        null guard can observe the original Haxe value. */
    function nullGuardLocalsInBlock(stmts:Array<TypedExpr>):Map<Int, Bool> {
        final result:Map<Int, Bool> = [];
        for (stmt in stmts) {
            TypedExprTools.iter(stmt, function(node:TypedExpr):Void {
                switch (stripWrap(node).expr) {
                    case TBinop(OpEq, l, r) | TBinop(OpNotEq, l, r):
                        final subject = isNullExpr(l) ? r : (isNullExpr(r) ? l : null);
                        if (subject != null)
                            switch (stripWrap(subject).expr) {
                                case TLocal(v): result.set(v.id, true);
                                case _:
                            }
                    case _:
                }
            });
        }
        return result;
    }

    /** Records the source ranges of null comparisons for order-sensitive use-site proofs. */
    function nullGuardPositionsInBlock(stmts:Array<TypedExpr>):Map<Int, Array<{file:String, min:Int, max:Int}>> {
        final result:Map<Int, Array<{file:String, min:Int, max:Int}>> = [];
        for (stmt in stmts) {
            TypedExprTools.iter(stmt, function(node:TypedExpr):Void {
                switch (stripWrap(node).expr) {
                    case TBinop(OpEq, l, r) | TBinop(OpNotEq, l, r):
                        final subject = isNullExpr(l) ? r : (isNullExpr(r) ? l : null);
                        if (subject != null)
                            switch (stripWrap(subject).expr) {
                                case TLocal(v):
                                    final p = Context.getPosInfos(node.pos);
                                    var entries = result.get(v.id);
                                    if (entries == null) {
                                        entries = [];
                                        result.set(v.id, entries);
                                    }
                                    entries.push({file: p.file, min: p.min, max: p.max});
                                case _:
                            }
                    case _:
                }
            });
        }
        return result;
    }

    // ------------------------------------------------------------------
    // Counted loops
    // ------------------------------------------------------------------
    function regroupLoops(stmts:Array<TypedExpr>):Array<TypedExpr> {
        return PolicyQueries.regroupLoops(stmts);
    }

    function intervalCore(counterDecl:TypedExpr, boundDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        return PolicyQueries.intervalCore(counterDecl, boundDecl, whileExpr);
    }

    function matchInterval(e:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        return PolicyQueries.matchInterval(e);
    }

    function intervalShort(counterDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        return PolicyQueries.intervalShort(counterDecl, whileExpr);
    }

    function loopLines(loop, depth:Int):Array<String> {
        // Counted ArrayIteration lowering: recover the original element loop.
        if (loop.body.length > 0)
            switch [loop.bound.expr, loop.body[0].expr] {
                case [TField(array, fa), TVar(item, init)] if (fieldName(fa) == "length" && init != null):
                    switch (stripWrap(init).expr) {
                        case TArray(_, {expr: TLocal(index)}) if (index.id == loop.index.id):
                            // The element loop drops the index binding, so it is
                            // valid only when the counter starts at zero and the
                            // remaining body never reads the counter.
                            if (switch (loop.start.expr) {
                                    case TConst(TInt(0)): true;
                                    case _: false;
                                }) {
                                var readsIndex = false;
                                for (s in loop.body.slice(1)) {
                                    if (mentionsLocal(s, loop.index)) {
                                        readsIndex = true;
                                        break;
                                    }
                                }
                                if (!readsIndex) {
                                    final out = [indent(depth) + "for (" + localName(item) + " in " + expr(array) + ") {"];
                                    for (l in blockLines(loop.body.slice(1), depth + 1))
                                        out.push(l);
                                    out.push(indent(depth) + "}");
                                    return out;
                                }
                                }
                        default:
                    }
                default:
            }

        final name = localName(loop.index);
        final startStr = expr(loop.start);
        final boundStr = loopBound(loop.bound);
        final out = [
            indent(depth) + "for (" + name + " in " + startStr + " until " + boundStr + ") {"
        ];
        for (l in blockLines(loop.body, depth + 1))
            out.push(l);
        out.push(indent(depth) + "}");
        return out;
    }

    function loopBound(bound:TypedExpr):String {
        final inner = stripWrap(bound);
        switch (inner.expr) {
            case TField(subj, fa) if (fieldName(fa) == "length"):
                final enumCollection = EnumQueryExpander.collectionEnum(subj);
                if (enumCollection != null)
                    return Std.string(EnumQueryExpander.constructorCount(enumCollection));
                // The subject may render nullable (e.g. a field read off a
                // nullable receiver or a nullable local); choose the suffix
                // from the rendered nullability so safe-navigation is emitted
                // when the value is nullable.
                final suffix = isString(subj) ? "length" : "size";
                if (isNullType(subj.t) && !provenNonNull(subj) && !guardProofBefore(subj)) {
                    return expr(subj) + "?." + suffix;
                }
                if (nullableChainHop(subj) && !guardProofBefore(subj)) {
                    return expr(subj) + "?." + suffix;
                }
                return expr(subj) + "." + suffix;
            case _:
                return expr(bound);
        }
    }

    // ------------------------------------------------------------------
    // Counted fill (Array(count) { ... })
    // ------------------------------------------------------------------

    function fillFusion(stmts:Array<TypedExpr>, i:Int, depth:Int):Null<Array<String>> {
        final alloc = FusionPlan.allocOf(stmts, i);
        if (alloc == null) {
            return null;
        }
        final loop = matchInterval(stmts[i + 1]);
        if (loop == null) {
            return null;
        }
        final plan = FusionPlan.plan(alloc, loop);
        if (plan == null) {
            return null;
        }

        final arrName = localName(plan.arr);
        final boundStr = loopBound(plan.loop.bound);
        final out:Array<String> = [];
        out.push(indent(depth) + "val " + arrName + " = Array(" + boundStr + ") { " + localName(plan.loop.index) + " ->");
        for (step in plan.steps) {
            switch (step) {
                case NonStoreBatch(batch):
                    for (l in blockLines(batch, depth + 1))
                        out.push(l);
                case StoreValue(value):
                    out.push(indent(depth + 1) + expr(value));
                case PushValue(arg):
                    out.push(indent(depth + 1) + expr(arg));
            }
        }
        if (decodeBoundary) {
            out.push(indent(depth) + "}");
            asListReturn.set(plan.arr.id, "asList()");
        } else {
            out.push(indent(depth) + "}.toMutableList()");
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Expressions
    // ------------------------------------------------------------------

    function floatLiteral(source:String, addWidth:Bool = true):String {
        var s = source;
        final dot = s.indexOf(".");
        if (dot >= 0 && dot + 1 < s.length) {
            final next = s.charAt(dot + 1);
            if (next == "e" || next == "E")
                s = s.substring(0, dot + 1) + "0" + s.substring(dot + 1);
        } else if (dot == s.length - 1) {
            s += "0";
        } else if (dot < 0 && s.indexOf("e") < 0 && s.indexOf("E") < 0) {
            s += ".0";
        }
        return FloatPrecision.isF32() && addWidth ? s + "f" : s;
    }

    function expr(e:TypedExpr):String {
        final int64Expr = int64Expression(e);
        if (int64Expr != null)
            return int64Expr;
        final wrapperValue = ValueTypeSupport.syntheticValue(e);
        if (wrapperValue != null)
            return valueTypeSynthetic(e, wrapperValue);
        final query = enumQuery(e);
        if (query != null)
            return query;
        switch (e.expr) {
            case TConst(c):
                switch (c) {
                    case TInt(v): return Std.string(v);
                    case TFloat(f):
                        final s = Std.string(f);
                        return floatLiteral(s);
                    case TString(s): return quoteString(s);
                    case TBool(b): return b ? "true" : "false";
                    case TNull: return "null";
                    case TThis: return "this";
                    case TSuper: return "super";
                    case _: return fail(e, "constant has no Kotlin lowering");
                }
            case TLocal(v):
                if (subst.exists(v.id)) {
                    return subst.get(v.id);
                }
                return localName(v);
            case TArray(arr, idx):
                final mapReceiver = mapBackingReceiver(arr);
                // The array receiver may render nullable (e.g. a local bound
                // from a nullable expression); emit safe array access when it
                // is, and plain element access otherwise.
                final receiver = mapReceiver == null ? arr : mapReceiver;
                if (isNullType(receiver.t) && !provenNonNull(receiver) && !guardProofBefore(receiver)) {
                    return expr(receiver) + "?.get(" + expr(idx) + ")";
                }
                if (nullableChainHop(receiver) && !guardProofBefore(receiver)) {
                    return expr(receiver) + "?.get(" + expr(idx) + ")";
                }
                return expr(receiver) + "[" + expr(idx) + "]";
            case TBinop(op, l, r):
                return binop(e, op, l, r);
            case TUnop(op, post, subj):
                return unop(e, op, post, subj);
            case TField(subj, fa):
                return field(subj, fa);
            case TTypeExpr(t):
                return typeExpr(t);
            case TParenthesis(inner):
                return "(" + expr(inner) + ")";
            case TObjectDecl(fields):
                return objectLiteral(e, fields);
            case TArrayDecl(elems):
                final typeArg = switch (e.t) {
                    case TInst(c, params) if (c.get().name == "Array" && params.length > 0):
                        "<" + types.of(params[0]) + ">";
                    case _: "";
                };
                // Haxe unifies Int and Float; widen Int elements to Float when
                // the array's element type is Float.
                final elemType = switch (e.t) {
                    case TInst(_, params) if (params.length > 0): params[0];
                    case _: null;
                };
                final elemFloat = isFloatType(elemType);
                final renderedElems = [
                    for (x in elems) {
                        var t = expr(x);
                        if (elemFloat && isIntOrLongType(emittedType(x))) t = intToFloatText(t);
                        t;
                    }
                ];
                return "mutableListOf" + typeArg + "(" + renderedElems.join(", ") + ")";
            case TCall(fn, args):
                return call(fn, args);
            case TNew(c, params, args):
                return newExpr(c, params, args);
            case TMeta(_, inner):
                return expr(inner);
            case TCast(inner, _):
                return expr(inner);
            case TEnumParameter(se, ef, index):
                // A collapsed single-case switch reads the payload outside
                // any `when` arm; the cast names the variant, and a
                // single-variant domain keeps the cast total.
                final en = switch (Context.follow(se.t)) {
                    case TEnum(r, _): r.get();
                    case _: return fail(e, "payload read subject is not a variant value");
                };
                if (Lambda.count(en.constructs) != 1) {
                    return fail(e, "payload read of a multi-variant enum lowers inside a when arm only");
                }
                final owner = state.payloadEnumOwners.get(en.module);
                final variant = switch (stripWrap(se).expr) {
                    case TLocal(v): enumVariants.get(v.id);
                    case _: null;
                };
                final narrowed = variant == ef.name || enumVariantKey(se) != null && enumVariantExpressions.exists(enumVariantKey(se));
                if (owner != null) {
                    imports.requireType(en.pack.concat([owner]).join("."), owner);
                    return (narrowed ? expr(se) : "(" + expr(se) + " as " + owner + "." + ef.name + ")") + "." + payloadName(ef, index);
                }
                imports.requireType(en.module, en.name);
                return (narrowed ? expr(se) : "(" + expr(se) + " as " + en.name + "." + ef.name + ")") + "." + payloadName(ef, index);
            case TEnumIndex(_):
                return fail(e, "enum index only lowers inside a variant switch");
            case TFunction(f):
                return functionLiteral(f);
            case TIf(c, t, f) if (f != null):
                final coalescing = coalescingSiteFor(e);
                if (coalescing != null) {
                    if (currentLocalName != null && currentClass != null && currentField != null) {
                        final value = DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, currentLocalName, coalescing.parameter);
                        if (value != null)
                            return expr(coalescing.valueExpr) + " ?: " + coalescingDefaultText(value, coalescing.valueExpr.t);
                    }
                    if (DefaultArgExpander.isNormalizationSource(coalescing.defaultExpr.pos))
                        return expr(coalescing.valueExpr) + " ?: " + expr(coalescing.defaultExpr);
                    return expr(coalescing.valueExpr);
                }
                final condition = expr(c);
                final base = proofSnapshot();
                addProofs(conditionProofs(c).thenPath);
                final thenText = expr(t);
                final afterThen = proofSnapshot();
                restoreProofs(base);
                addProofs(conditionProofs(c).elsePath);
                final elseText = expr(f);
                final afterElse = proofSnapshot();
                restoreProofs(intersectProofs(base, afterThen, afterElse));
                // Haxe promotes nullable Float branches with integer literals
                // to Float. Kotlin otherwise infers their common type as
                // Number & Comparable<*>, which cannot satisfy a Float result.
                final branchThen = isFloatType(e.t) && isIntOrLongType(emittedType(t)) ? intToFloatText(thenText) : thenText;
                final branchElse = isFloatType(e.t) && isIntOrLongType(emittedType(f)) ? intToFloatText(elseText) : elseText;
                return "(if (" + condition + ") " + branchThen + " else " + branchElse + ")";
            case TSwitch(_, _, _):
                return switchExpression(e);
            case TTry(body, catches) if (catches.length == 1):
                return tryExpression(body, catches[0]);
            case TTry(_, _):
                return fail(e, "try region handles exactly one exception domain");
            case TBlock(stmts):
                return blockExpression(stmts);
            case _:
                return fail(e, "expression has no Kotlin lowering in the subset: " + Std.string(e.expr));
        }
    }

    /** Lowers an abstract implementation block to a Kotlin value wrapper. */
    function valueTypeSynthetic(wrapper:TypedExpr, value:TypedExpr):String {
        final plan = ValueTypePlan.planValueTypeSynthetic(wrapper, value, {
            markedAbstractOfType: ValueTypeSupport.markedAbstractOfType,
            localValues: valueTypeLocalValues,
            activeAbstract: () -> currentClass == null ? null : ValueTypeSupport.markedAbstractOfClass(currentClass),
            activeField: (a, n) -> n == null ? null : ValueTypeSupport.memberField(a, n),
            activeFieldName: () -> currentField,
            stripValue: stripWrap,
            wrapNative: true
        });
        final abs = plan.abstractType;
        if (abs == null)
            return expr(value);
        imports.requireType(abs.module, abs.name);
        final locals = plan.locals;
        final nativeOperator = plan.nativeOperator;
        return switch (plan.kind) {
            case ValueTypeBinary(op, left, right):
                final field = plan.field;
                if (field == null) expr(value) else {
                    final asRepresentation = nativeOperator && field.name == currentField;
                    final rendered = valueTypeOperand(left, locals, abs, asRepresentation) + " " + opStr(op) + " "
                        + valueTypeOperand(right, locals, abs, asRepresentation);
                    nativeOperator
                    && field.name == currentField ? abs.name + "(" + rendered + ")" : rendered;
                }
            case ValueTypeUnary(op, subject):
                final field = plan.field;
                if (field == null) expr(value) else {
                    final asRepresentation = nativeOperator && field.name == currentField;
                    final rendered = "-" + valueTypeOperand(subject, locals, abs, asRepresentation);
                    nativeOperator
                    && field.name == currentField ? abs.name + "(" + rendered + ")" : rendered;
                }
            case _: abs.name + "(" + valueTypeOperand(value, locals, abs) + ")";
            case _:
                // The inline constructor expansion assigns the argument to a
                // synthetic local named after the constructor parameter; the
                // plan's locals map resolves that local back to the original
                // argument expression (features/23 value-type lowering).
                final fallbackValue = switch (stripWrap(value).expr) {
                    case TLocal(v) if (locals.exists(v.id)): locals.get(v.id);
                    case _: value;
                };
                abs.name + "(" + expr(fallbackValue) + ")";
        };
    }

    function valueTypeLocalValues(wrapper:TypedExpr):Map<Int, TypedExpr> {
        return PolicyQueries.valueTypeLocalValues(wrapper);
    }

    function valueTypeOperand(value:TypedExpr, locals:Map<Int, TypedExpr>, ?abs:AbstractType, asRepresentation:Bool = false):String {
        var source = value;
        var wrapperOperand = false;
        var decorated = true;
        while (decorated) {
            if (abs != null) {
                final sourceAbs = ValueTypeSupport.markedAbstractOfType(source.t);
                if (sourceAbs != null && ValueTypeSupport.sameAbstract(sourceAbs, abs))
                    wrapperOperand = true;
            }
            switch (source.expr) {
                case TCast(inner, _):
                    source = inner;
                case TMeta(_, inner):
                    source = inner;
                case _:
                    decorated = false;
            }
        }
        switch (stripWrap(value).expr) {
            case TLocal(v) if (locals.exists(v.id)):
                return expr(locals.get(v.id));
            case _:
        }
        final rendered = expr(value);
        final fieldName = abs == null ? "" : ValueTypeSupport.representationFieldName(abs);
        final alreadyRepresentation = switch (stripWrap(value).expr) {
            case TLocal(v) if (subst.exists(v.id) && subst.get(v.id) == fieldName): true;
            case _: false;
        };
        return asRepresentation && wrapperOperand && !alreadyRepresentation ? rendered + "." + fieldName : rendered;
    }

    function enumQuery(e:TypedExpr):Null<String> {
        return switch (PolicyQueries.enumQueryPlan(e)) {
            case null: null;
            case LengthCount(count): Std.string(count);
            case AliasIndex(subj, index): expr(subj) + "[" + expr(index) + "]";
            case EntryIndex(en, index):
                imports.requireType(en.module, en.name);
                en.name + ".entries[" + expr(index) + "]";
            case EnumKindQuery(kind, en, args):
                imports.requireType(en.module, en.name);
                switch (kind) {
                    case QCollection: en.name + ".entries";
                    case QName:
                        // The argument may render nullable (e.g. Type.enumConstructor
                        // of a nullable expression); choose the separator from the
                        // rendered nullability.
                        final arg = args[0];
                        final argText = expr(arg);
                        final nullable = rendersNullable(arg)
                            || (isNullType(arg.t) && !provenNonNull(arg) && !guardProofBefore(arg))
                            || (nullableChainHop(arg) && !guardProofBefore(arg))
                            || (StringTools.endsWith(argText, "}") && argText.indexOf("firstOrNull {") >= 0);
                        argText + (nullable ? "?.name" : ".name");
                    case QLookup: en.name + ".entries.firstOrNull { it.name == " + expr(args[1]) + " }";
                }
        }
    }

    function functionLiteral(f:TFunc):String {
        for (a in f.args) {
            reserveName(a.v.name);
            localNames.set(a.v.id, KotlinNameEscape.escape(a.v.name));
        }
        final params = [for (a in f.args) '${localName(a.v)}: ${types.of(a.v.t)}'].join(", ");
        final ret = types.of(f.t);
        final retStr = ret == "Unit" ? "" : ": " + ret;
        return 'fun($params)$retStr {\n' + blockLines(statementsOf(f.expr), 1).join("\n") + '\n}';
    }

    // ------------------------------------------------------------------
    // Variant switches and try regions (features/01, features/06)
    // ------------------------------------------------------------------

    /**
        Renders an enum switch as a `when` expression. The typer hands the
        switch over with the subject wrapped in TEnumIndex and case values
        as construct-index constants; payload captures arrive as TEnumParameter
        initializations in the arm block and bind to property reads on the
        subject, which the `is` arm smart-casts to the variant type.
    **/
    function switchExpression(sw:TypedExpr):String {
        final parts = switch (sw.expr) {
            case TSwitch(subj, cases, def): {subj: subj, cases: cases, def: def};
            case _: return fail(sw, "not a switch");
        }
        if (parts.def != null) {
            return fail(sw, "variant switch carries a default arm (V15)");
        }
        final subj = stripWrap(parts.subj);
        final se = switch (subj.expr) {
            case TEnumIndex(inner): inner;
            case _: return fail(sw, "switch subject is not a variant index");
        }
        final subjStr = expr(se);
        final en = switch (se.t) {
            case TEnum(enumRef, _): enumRef.get();
            case _: return fail(sw, "variant switch subject is not a variant value");
        }
        final owner = state.payloadEnumOwners.get(en.module);
        final receiver = owner != null ? owner : en.name;
        if (owner != null) {
            imports.requireType(en.pack.concat([owner]).join("."), owner);
        } else {
            imports.requireType(en.module, en.name);
        }
        final table = new Map<Int, EnumField>();
        for (name => ef in en.constructs) {
            table.set(ef.index, ef);
        }
        final out = ["when (" + subjStr + ") {"];
        for (c in parts.cases) {
            final fields:Array<EnumField> = [];
            for (value in c.values) {
                final index = switch (value.expr) {
                    case TConst(TInt(v)): v;
                    case _: return fail(sw, "variant switch case is not a constant index");
                }
                final ef = table.get(index);
                if (ef == null) {
                    return fail(sw, "variant switch case index has no construct");
                }
                fields.push(ef);
                switch (stripWrap(se).expr) {
                    case TLocal(v):
                        enumVariants.set(v.id, ef.name);
                    case _:
                }
                final variantKey = enumVariantKey(se);
                if (variantKey != null)
                    enumVariantExpressions.set(variantKey, ef.name);
            }
            final arm = armLines(c.expr, sw.t);
            // The `is` pattern smart-casts the subject to the variant, so
            // payload captures read as properties on it. Arms separate by
            // newline; Kotlin `when` takes no comma between arms.
            final patterns = [for (ef in fields) (isValueEnum(en) ? "" : "is ") + receiver + "." + ef.name];
            out.push("    " + patterns.join(", ") + " -> " + arm[0]);
            for (i in 1...arm.length) {
                out.push("    " + arm[i]);
            }
        }
        out.push("}");
        return out.join("\n");
    }

    static function isValueEnum(en:EnumType):Bool {
        return PolicyQueries.isValueEnum(en);
    }

    /**
        Renders one switch arm. Payload captures fold into property reads on
        the subject; other declarations stay; the trailing statement is the
        arm value. A single-expression arm renders inline, anything longer
        renders as a block.
    **/
    function armLines(e:TypedExpr, switchType:Null<Type>):Array<String> {
        final decls:Array<String> = [];
        var value:Null<String> = null;
        var valueExpr:Null<TypedExpr> = null;
        for (step in PolicyQueries.variantArmPlan(e)) {
            switch (step) {
                case PayloadCapture(v, subject, ef, index):
                    subst.set(v.id, expr(subject) + "." + payloadName(ef, index));
                case ForwardOrDecl(v, init, source):
                    if (subst.exists(source.id)) {
                        subst.set(v.id, subst.get(source.id));
                    } else {
                        decls.push("val " + localName(v) + " = " + expr(init));
                    }
                case PlainDecl(v, init):
                    decls.push("val " + localName(v) + " = " + expr(init));
                case OtherStatement(s, _, _):
                    value = expr(s);
                    valueExpr = s;
                case MissingInit(s):
                    Context.error("kotlin target: declaration without initializer has no lowering", s.pos);
            }
        }
        if (value == null) {
            return [fail(e, "variant switch arm has no value")];
        }
        // Haxe unifies Int and Float; widen Int arm values to Float when the
        // switch's unified type is Float, or when the enclosing function
        // expects a Float return.
        final effectiveType = isFloatType(switchType) ? switchType : currentReturnType;
        if (isFloatType(effectiveType) && valueExpr != null && isIntOrLongType(emittedType(valueExpr)))
            value = intToFloatText(value);
        if (decls.length == 0) {
            return [value];
        }
        final out = ["{"];
        for (d in decls) {
            out.push("    " + d);
        }
        out.push("    " + value);
        out.push("}");
        return out;
    }

    /**
        Renders a try region. Kotlin `try` is an expression, so statement and
        expression positions share one shape; the catch variable is typed with
        the exception class and registered so payload access on it lowers to
        the variable itself (features/06 catch-site lowering). `prefix`
        carries the binding or return the region produces its value for.
    **/
    function tryLines(body:TypedExpr, c:{v:TVar, expr:TypedExpr}, depth:Int, prefix:String):Array<String> {
        final varName = localName(c.v);
        final varType = types.of(c.v.t);
        final out = [indent(depth) + prefix + "try {"];
        for (l in blockLines(statementsOf(body), depth + 1)) {
            out.push(l);
        }
        out.push(indent(depth) + "} catch (" + varName + ": " + varType + ") {");
        catchVars.set(c.v.id, true);
        final handler = blockLines(statementsOf(c.expr), depth + 1);
        catchVars.remove(c.v.id);
        for (l in handler) {
            out.push(l);
        }
        out.push(indent(depth) + "}");
        return out;
    }

    function tryExpression(body:TypedExpr, c:{v:TVar, expr:TypedExpr}):String {
        return tryLines(body, c, 0, "").join("\n");
    }

    /** True when the expression is an enum switch over variant indices. */
    function isVariantSwitch(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TSwitch(_, _, _): true;
            case _: false;
        };
    }

    /** Return-position variant switch: the when value returns through the function edge. */
    function whenReturnLines(sw:TypedExpr, depth:Int):Array<String> {
        final lines = switchExpression(sw).split("\n");
        final out = [indent(depth) + "return " + lines[0]];
        for (i in 1...lines.length) {
            out.push(indent(depth) + lines[i]);
        }
        return out;
    }

    function isTryRegion(e:TypedExpr):Bool {
        return PolicyQueries.isTryRegion(e);
    }

    /**
        The trailing value of a region body: an expression statement whose
        value leaves the region. Declarations, control flow, assignments,
        and blocks never carry the tail value.
    **/
    function regionTailValue(stmts:Array<TypedExpr>):Null<TypedExpr> {
        if (stmts.length == 0) {
            return null;
        }
        final last = stmts[stmts.length - 1];
        return switch (last.expr) {
            case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TFor(_, _, _) | TBlock(_) | TBreak | TContinue |
                TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _):
                null;
            case _:
                last;
        };
    }

    function tryRegionParts(e:TypedExpr):{body:TypedExpr, c:{v:TVar, expr:TypedExpr}} {
        return PolicyQueries.tryRegionParts(e);
    }

    /**
        On a catch variable, the payload field of the exception class (the
        enum-typed field whose enum the region catches) reads as the variable
        itself: the folded tree makes the variable the variant value
        (features/06 catch-site lowering).
    **/
    /**
        A `message` or `get_message` read on a folded exception: the sealed
        class overrides `Throwable.message` with a non-null String, so any
        read maps to the native property whether or not the value sits in a
        catch-variable position. Without this, a read outside a catch emits
        the runtime-dependent `get_message()` accessor, which kotlinc
        rejects (features/06 message lowering).
    **/
    function foldedExceptionMessage(subj:TypedExpr):Null<String> {
        switch (Context.follow(subj.t)) {
            case TInst(c, _):
                final cls = c.get();
                if (KotlinDecl.isExceptionSubclass(cls)) {
                    return expr(subj) + ".message";
                }
                // The bare haxe.Exception base maps to RuntimeException, whose
                // platform message is nullable. Haxe's message is a non-null
                // String, so a null platform message realizes as the empty
                // string (features/06 message lowering).
                if (cls.pack.join(".") == "haxe" && cls.name == "Exception") {
                    return "(" + expr(subj) + ".message ?: \"\")";
                }
                return null;
            case _:
                return null;
        }
    }

    function catchPayloadAccess(subj:TypedExpr, name:String):Null<String> {
        switch (stripWrap(subj).expr) {
            case TLocal(v) if (catchVars.exists(v.id)):
                switch (Context.follow(v.t)) {
                    case TInst(c, _):
                        final cls = c.get();
                        final enumModule = state.exceptionPayloads.get(cls.module);
                        if (enumModule != null) {
                            for (f in cls.fields.get()) {
                                if (f.name == name) {
                                    switch (f.type) {
                                        case TEnum(en, _):
                                            if (en.get().module == enumModule) {
                                                return localName(v);
                                            }
                                        case _:
                                    }
                                }
                            }
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    function binop(e:TypedExpr, op:Binop, l:TypedExpr, r:TypedExpr):String {
        switch (op) {
            case OpAssign:
                final map = mapAssignment(l);
                final wasFunctionTypeExpected = functionTypeExpected;
                functionTypeExpected = PolicyQueries.isFunctionType(l.t);
                var value = expr(r);
                functionTypeExpected = wasFunctionTypeExpected;
                // Haxe unifies Int and Float; widen Int assignment values to
                // Float when the target's type is Float.
                if (map == null && isIntOrLongType(emittedType(r)) && isFloatType(l.t))
                    value = intToFloatText(value);
                if (map == null) {
                    final previous = mutableArrayAccess;
                    mutableArrayAccess = switch (stripWrap(l).expr) {
                        case TArray(arr, _): switch (stripWrap(arr).expr) {
                            case TLocal(v): mutableArrayLocals.exists(v.id);
                            case _: false;
                        }
                        case _: false;
                    };
                    final target = assignTarget(l);
                    mutableArrayAccess = previous;
                    return target + " = " + value;
                }
                return expr(map.receiver) + ".put(" + expr(map.key) + ", " + value + ")";
            case OpAssignOp(inner):
                switch (inner) {
                    case OpAdd | OpSub | OpMult | OpDiv | OpMod:
                        var appliedValue = expr(r);
                        if (isIntOrLongType(emittedType(r)) && isFloatType(l.t))
                            appliedValue = intToFloatText(appliedValue);
                        return assignTarget(l) + " " + symbolOf(inner) + "= " + appliedValue;
                    case _:
                        return assignTarget(l) + " = " + binopCore(inner, l, r);
                }
            case _:
                return binopCore(op, l, r);
        }
    }

    function addProofExpr(e:TypedExpr):Void {
        switch (stripWrap(e).expr) {
            case TLocal(v):
                nonNullLocals.set(v.id, true);
            case TField(_, _):
                final key = fieldAccessKey(e);
                if (key != null)
                    nonNullFields.set(key, true);
            case _:
        }
    }

    function updateLocalProof(v:TVar, init:TypedExpr):Void {
        if (!isNullType(v.t))
            return;
        // The initializer proves the local when its own type is non-null,
        // when it reads an already-proven local or field, or when it is a
        // null-guard coalescing whose default branch is non-null (the
        // rendered elvis then has a non-null right side).
        if (!isNullType(init.t) || provenNonNull(init) || isNonNullNormalization(init))
            nonNullLocals.set(v.id, true);
        else
            nonNullLocals.remove(v.id);
    }

    function updateLocalProofTarget(target:TypedExpr, value:TypedExpr):Void {
        switch (stripWrap(target).expr) {
            case TLocal(v) if (isNullType(target.t)):
                if (!isNullType(value.t))
                    nonNullLocals.set(v.id, true);
                else
                    nonNullLocals.remove(v.id);
            case _:
        }
    }

    function proofSnapshot():{locals:Map<Int, Bool>, fields:Map<String, Bool>} {
        final l:Map<Int, Bool> = [], f:Map<String, Bool> = [];
        for (k in nonNullLocals.keys())
            l.set(k, true);
        for (k in nonNullFields.keys())
            f.set(k, true);
        return {locals: l, fields: f};
    }

    function restoreProofs(s:{locals:Map<Int, Bool>, fields:Map<String, Bool>}):Void {
        nonNullLocals.clear();
        nonNullFields.clear();
        for (k in s.locals.keys())
            nonNullLocals.set(k, true);
        for (k in s.fields.keys())
            nonNullFields.set(k, true);
    }

    function addProofs(p:{locals:Array<Int>, fields:Array<String>}):Void {
        for (k in p.locals)
            nonNullLocals.set(k, true);
        for (k in p.fields)
            nonNullFields.set(k, true);
    }

    function intersectProofs(base:{locals:Map<Int, Bool>, fields:Map<String, Bool>}, a:{locals:Map<Int, Bool>, fields:Map<String, Bool>},
            b:{locals:Map<Int, Bool>, fields:Map<String, Bool>}):{locals:Map<Int, Bool>, fields:Map<String, Bool>} {
        final result = proofSnapshot();
        result.locals.clear();
        result.fields.clear();
        for (k in a.locals.keys())
            if (b.locals.exists(k))
                result.locals.set(k, true);
        for (k in a.fields.keys())
            if (b.fields.exists(k))
                result.fields.set(k, true);
        return result;
    }

    function conditionProofs(e:Null<TypedExpr>):{thenPath:{locals:Array<Int>, fields:Array<String>}, elsePath:{locals:Array<Int>, fields:Array<String>}} {
        final empty = function() return {locals: [], fields: []};
        if (e == null)
            return {thenPath: empty(), elsePath: empty()};
        switch (stripWrap(e).expr) {
            case TBinop(OpBoolAnd, l, r):
                final lp = conditionProofs(l), rp = conditionProofs(r);
                return {
                    thenPath: {locals: lp.thenPath.locals.concat(rp.thenPath.locals), fields: lp.thenPath.fields.concat(rp.thenPath.fields)},
                    elsePath: empty()
                };
            case TBinop(OpBoolOr, l, r):
                final lp = conditionProofs(l), rp = conditionProofs(r);
                return {
                    thenPath: intersectProofArrays(lp.thenPath, rp.thenPath),
                    elsePath: {locals: lp.elsePath.locals.concat(rp.elsePath.locals), fields: lp.elsePath.fields.concat(rp.elsePath.fields)}
                };
            case TBinop(OpEq, l, r) | TBinop(OpNotEq, l, r):
                final leftNull = isNullExpr(l), rightNull = isNullExpr(r);
                final subject = leftNull ? r : (rightNull ? l : null);
                if (subject != null) {
                    final p = proofFor(subject);
                    return switch (stripWrap(e).expr) {
                        case TBinop(OpNotEq, _, _): {thenPath: p, elsePath: empty()};
                        case _: {thenPath: empty(), elsePath: p};
                    };
                }
                final literalSubject = switch (stripWrap(l).expr) {
                    case TLocal(_) | TField(_, _): switch (stripWrap(r).expr) {
                            case TConst(_): l;
                            default: null;
                        };
                    case _: switch (stripWrap(r).expr) {
                            case TLocal(_) | TField(_, _): switch (stripWrap(l).expr) {
                                    case TConst(_): r;
                                    default: null;
                                };
                            case _: null;
                        }
                };
                return literalSubject == null ? {thenPath: empty(), elsePath: empty()} : {thenPath: proofFor(literalSubject), elsePath: empty()};
            case _:
                return {thenPath: empty(), elsePath: empty()};
        }
    }

    function intersectProofArrays(a:{locals:Array<Int>, fields:Array<String>},
            b:{locals:Array<Int>, fields:Array<String>}):{locals:Array<Int>, fields:Array<String>} {
        return {locals: [for (x in a.locals) if (b.locals.indexOf(x) >= 0) x], fields: [for (x in a.fields) if (b.fields.indexOf(x) >= 0) x]};
    }

    function proofFor(e:TypedExpr):{locals:Array<Int>, fields:Array<String>} {
        return switch (stripWrap(e).expr) {
            case TLocal(v): {locals: [v.id], fields: []};
            case TField(_, _):
                final key = fieldAccessKey(e);
                key == null ? {locals: [], fields: []} : {locals: [], fields: [key]};
            case _: {locals: [], fields: []};
        };
    }

    function isNullInitialized(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): nullInitializedLocals.exists(v.id) || nullableRenderedLocals.exists(v.id);
            case TField(_, FStatic(c, cf)): nullInitializedFields.exists(c.get().module + ":" + cf.get().name);
            case _: false;
        };
    }

    /**
        The member-access separator rendered after a subject. A subject
        whose Haxe type is nullable takes `?.` until a dominating proof
        narrows it. A null-initialized subject declares a non-null Haxe
        type, so the program keeps the value present at every use and the
        extraction uses `!!`; its result stays non-null for the enclosing
        expression, which `?.` would widen into a type error inside
        arithmetic and assignment contexts. A proven subject takes `.`.
    **/
    function nullableAccess(subj:TypedExpr):String {
        if (isNullInitialized(subj))
            return "!!.";
        // The typer wraps an implicit Null<T> unwrap in TCast; the cast's
        // own type is the non-null target, so look through it before
        // deciding.
        switch (subj.expr) {
            case TCast(inner, _) if (isNullType(inner.t) && !provenNonNull(inner)):
                return "!!.";
            case _:
        }
        if (isNullType(subj.t) && !provenNonNull(subj) && !guardProofBefore(subj))
            return "?.";
        // A safe-navigation hop widens the value produced by the whole
        // receiver chain.  The typed AST records that widened intermediate
        // field as non-null, so inspect the chain root as well; otherwise a
        // later hop would incorrectly use a plain dot.
        if (nullableChainHop(subj) && !guardProofBefore(subj))
            return "?.";
        if (isNullType(subj.t))
            return "!!.";
        return ".";
    }

    function nullableChainHop(e:TypedExpr):Bool {
        var current = stripWrap(e);
        while (true) {
            switch (current.expr) {
                case TField(subject, _):
                    if (isNullType(subject.t)) {
                        // A dominating condition can prove the chain root even
                        // when the intermediate field remains nullable in the
                        // typed AST.  Do not replace that proof with ?. on a
                        // later hop.
                        return !provenNonNull(subject) && !guardProofBefore(subject);
                    }
                    current = stripWrap(subject);
                case _:
                    return false;
            }
        }
    }

    function isNullableReferenceType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(_, _): true;
            case TAbstract(a, _) if (a.get().name != "Null" && a.get().name != "Int" && a.get().name != "Float" && a.get().name != "Bool"): true;
            case _: false;
        };
    }

    /**
        True when rendering `e` yields a Kotlin expression whose inferred type
        is nullable even though the Haxe AST may type it non-null. This happens
        when a sub-expression renders nullable (a nullable-typed arm of a
        ternary, a field access on a nullable receiver, ...) and the enclosing
        context does not widen it back to non-null.
    **/
    function rendersNullable(e:TypedExpr):Bool {
        if (isNullType(e.t) && !provenNonNull(e) && !guardProofBefore(e))
            return true;
        if (isNullInitialized(e))
            return true;
        final inner = stripWrap(e);
        // A cast/wrap may hide a nullable-typed inner expression; check the
        // unwrapped type too.
        if (inner != e && isNullType(inner.t) && !provenNonNull(inner) && !guardProofBefore(inner))
            return true;
        switch (inner.expr) {
            case TIf(_, t, f):
                return rendersNullable(t) || (f != null && rendersNullable(f));
            case TField(subj, _):
                return rendersNullable(subj);
            case TParenthesis(pinner) | TCast(pinner, _):
                return rendersNullable(pinner);
            case _:
                return false;
        }
    }

    /** True when any return statement calls a method on an unproven nullable
        receiver, whose kotlin rendering is the safe-call form and therefore
        produces a nullable value. */
    public function bodyUsesSafeCallReturns(f:ClassFuncData):Bool {
        if (f.expr == null)
            return false;
        // The body renderer proves a local non-null when its initializer is
        // non-null and the local is never reassigned. Reproduce that proof
        // here so a final local bound to a non-null value does not widen the
        // rendered return type. scanLocals fills the mutation set the renderer
        // relies on; the later functionBody call re-scans harmlessly.
        scanLocals(f.expr);
        final saved = proofSnapshot();
        function collect(e:TypedExpr):Void {
            switch (e.expr) {
                case TVar(v, init) if (init != null && !mutated.exists(v.id) && (!isNullType(init.t) || isNonNullNormalization(init))):
                    nonNullLocals.set(v.id, true);
                case _:
            }
            TypedExprTools.iter(e, collect);
        }
        collect(f.expr);
        var found = false;
        function scan(e:TypedExpr):Void {
            if (found)
                return;
            var scanChildren = true;
            switch (e.expr) {
                case TReturn(inner):
                    if (inner != null) {
                        switch (stripWrap(inner).expr) {
                            case TCall(subj, _):
                                if (isNullType(receiverBase(subj).t) && !provenNonNull(receiverBase(subj)))
                                    found = true;
                            case TBinop(OpAdd, l, r):
                                if ((isStringType(l.t) || isStringType(r.t)) && isNullType(receiverBase(l).t) && !provenNonNull(receiverBase(l)))
                                    found = true;
                            case _:
                        }
                    }
                case TFunction(_):
                    // Nested returns belong to the nested function and cannot
                    // widen the declaration currently being analyzed.
                    scanChildren = false;
                case _:
            }
            if (!found && scanChildren)
                TypedExprTools.iter(e, scan);
        }
        scan(f.expr);
        restoreProofs(saved);
        return found;
    }

    function receiverBase(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TField(subj, _) | TCall(subj, _): receiverBase(subj);
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): receiverBase(inner);
            case _: e;
        };
    }

    function isNullType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (t) {
            case TAbstract(a, _): a.get().name == "Null";
            case TLazy(f): isNullType(f());
            case _: false;
        };
    }

    function isNonNullNormalization(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TIf(c, t, f) if (f != null): final guard = nullGuardLocal(c); // A proven guard decides the condition statically: the
                // rendered branch is the guard itself (or a non-null
                // default), so the ternary yields a non-null value.
                guard != null && (nonNullLocals.exists(guard.id) || !isNullType(t.t) || provenNonNull(branchValue(t)));
            case _: false;
        };
    }

    /** The value a branch contributes: a block stands for its last statement. */
    function branchValue(e:TypedExpr):TypedExpr {
        return switch (stripWrap(e).expr) {
            case TBlock(stmts) if (stmts.length > 0): branchValue(stmts[stmts.length - 1]);
            case _: e;
        };
    }

    /** True when the block's last statement always exits (return/throw). */
    function blockTerminates(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TBlock(stmts): stmts.length > 0 && stmtTerminates(stmts[stmts.length - 1]);
            case _: stmtTerminates(e);
        }
    }

    function stmtTerminates(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TReturn(_) | TThrow(_): true;
            case TBlock(stmts): stmts.length > 0 && stmtTerminates(stmts[stmts.length - 1]);
            case _: false;
        }
    }

    /**
        Parameters whose Kotlin signature renders a non-null type while the
        Haxe type is nullable (a registered default argument lifts the
        `x == null ? D : x` pattern into `x: T = D`) are never null at body
        start, so they join the proof set before the body renders.
    **/
    function registerNonNullDefaultParams(cls:ClassType, f:ClassFuncData):Void {
        for (a in f.args) {
            final registered = DefaultArgExpander.defaultAt(cls, f.field.name, a.index);
            if (registered == null || !isNullType(a.type) || isNullType(DefaultArgExpander.defaultParameterType(registered, a.type)))
                continue;
            if (a.tvar != null)
                nonNullLocals.set(a.tvar.id, true);
        }
    }

    function nullGuardLocal(e:Null<TypedExpr>):Null<TVar> {
        if (e == null)
            return null;
        return switch (stripWrap(e).expr) {
            case TBinop(OpEq, l, r) | TBinop(OpNotEq, l, r):
                switch (stripWrap(r).expr) {
                    case TConst(TNull): switch (stripWrap(l).expr) {
                            case TLocal(v): v;
                            case _: null;
                        }
                    case _: switch (stripWrap(l).expr) {
                            case TConst(TNull): switch (stripWrap(r).expr) {
                                    case TLocal(v): v;
                                    case _: null;
                                };
                            case _: null;
                        }
                }
            case _: null;
        };
    }

    function provenNonNull(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): nonNullLocals.exists(v.id);
            case TField(_, _): final key = fieldAccessKey(e); key != null && nonNullFields.exists(key);
            case _: false;
        };
    }

    /** True when a local (or access rooted at it) follows a null comparison in this block. */
    function guardProofBefore(e:TypedExpr):Bool {
        var local:Null<TVar> = null;
        var root = stripWrap(e);
        while (true) {
            switch (root.expr) {
                case TLocal(v):
                    local = v;
                case TField(subject, _):
                    root = stripWrap(subject);
                    continue;
                case _:
            }
            break;
        }
        if (local == null)
            return false;
        final entries = activeNullGuardPositions.get(local.id);
        if (entries == null)
            return false;
        final use = Context.getPosInfos(e.pos);
        for (entry in entries)
            if (entry.file == use.file && entry.max <= use.min)
                return true;
        return false;
    }

    function nullGuardFields(e:Null<TypedExpr>):Array<String> {
        if (e == null)
            return [];
        return switch (stripWrap(e).expr) {
            case TBinop(OpNotEq, l, r):
                final value = isNullExpr(l) ? r : (isNullExpr(r) ? l : null);
                final key = value == null ? null : fieldAccessKey(value);
                key == null ? [] : [key];
            case TBinop(OpBoolAnd, l, r):
                final left = nullGuardFields(l);
                final right = nullGuardFields(r);
                left.concat(right);
            case _: [];
        };
    }

    function isCompleteNullGuard(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TBinop(OpNotEq, l, r) | TBinop(OpEq, l, r): final value = isNullExpr(l) ? r : (isNullExpr(r) ? l : null); value != null && fieldAccessKey(value) != null;
            case TBinop(OpBoolAnd, l, r): isCompleteNullGuard(l) && isCompleteNullGuard(r);
            case _: false;
        };
    }

    function saveNonNullFields(keys:Array<String>):Map<String, Bool> {
        final saved:Map<String, Bool> = [];
        for (key in keys) {
            saved.set(key, nonNullFields.exists(key) && nonNullFields.get(key));
            nonNullFields.set(key, true);
        }
        return saved;
    }

    function restoreNonNullFields(saved:Map<String, Bool>):Void {
        for (key in saved.keys()) {
            if (saved.get(key))
                nonNullFields.set(key, true);
            else
                nonNullFields.remove(key);
        }
    }

    function enumVariantKey(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TLocal(v): "local:" + localName(v);
            case TField(_, _):
                final key = fieldAccessKey(e);
                key == null ? null : "field:" + key;
            case _: null;
        };
    }

    function fieldAccessKey(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TField(receiver, FInstance(_, _, _)) | TField(receiver, FAnon(_)):
                switch (stripWrap(receiver).expr) {
                    case TLocal(_) | TConst(TThis): "field:" + expr(e);
                    case _: null;
                }
            case _: null;
        };
    }

    function isStringType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().name == "String";
            case _: false;
        };
    }

    function binopCore(op:Binop, l:TypedExpr, r:TypedExpr):String {
        switch (op) {
            case OpAdd if (isStringType(l.t) || isStringType(r.t)):
                final leftStd = stdStringArg(l);
                final rightStd = stdStringArg(r);
                // The typer types Std.string(x) as String while the
                // rendered operand decides whether Kotlin's + resolves:
                // only String carries plus. A non-String argument
                // therefore renders through its standalone conversion
                // spelling (inConcat false), which is itself a String
                // expression; a bare inConcat spelling would leave
                // Enum + String or Int + String unresolved.
                final leftText = leftStd == null ? operand(l, op, false) : stdString(leftStd, isStringType(leftStd.t));
                final rightText = rightStd == null ? operand(r, op, true) : stdString(rightStd, true);
                // A nullable safe-call left operand propagates null through
                // the concatenation: plus on the nullable receiver yields
                // null; a plain + would coerce to the "null" string.
                if ((isStringType(l.t) || isStringType(r.t)) && isNullType(receiverBase(l).t) && !provenNonNull(receiverBase(l))) {
                    return leftText + "?.plus(" + rightText + ")";
                }
                if (!isStringType(l.t)) {
                    return "(" + leftText + ").toString() + " + rightText;
                }
                return leftText + " + " + rightText;
            case OpBoolAnd:
                final leftText = operand(l, op, false);
                final saved = proofSnapshot();
                addProofs(conditionProofs(l).thenPath);
                final rightText = operand(r, op, true);
                restoreProofs(saved);
                return leftText + " && " + rightText;
            case OpGt | OpGte | OpLt | OpLte:
                final leftText = operand(l, op, false);
                final saved = proofSnapshot();
                addProofExpr(l);
                addProofExpr(r);
                final rightText = operand(r, op, true);
                restoreProofs(saved);
                final leftFinal = isIntOrLongType(emittedType(l)) && isFloatType(emittedType(r)) ? intToFloatText(leftText) : leftText;
                final rightFinal = isIntOrLongType(emittedType(r)) && isFloatType(emittedType(l)) ? intToFloatText(rightText) : rightText;
                return leftFinal + " " + symbolOf(op) + " " + rightFinal;
            case OpAdd | OpSub | OpMult | OpDiv | OpMod | OpEq | OpNotEq:
                final leftText = operand(l, op, false);
                final rightText = operand(r, op, true);
                final leftFinal = isIntOrLongType(emittedType(l)) && isFloatType(emittedType(r)) ? intToFloatText(leftText) : leftText;
                final rightFinal = isIntOrLongType(emittedType(r)) && isFloatType(emittedType(l)) ? intToFloatText(rightText) : rightText;
                return leftFinal + " " + symbolOf(op) + " " + rightFinal;
            case OpBoolOr:
                // Kotlin's flow analysis treats a evaluated-false left
                // operand as establishing the left null guard's else path,
                // so the right operand renders under that proof.
                final leftText = operand(l, op, false);
                final saved = proofSnapshot();
                addProofs(conditionProofs(l).elsePath);
                final rightText = operand(r, op, true);
                restoreProofs(saved);
                return leftText + " || " + rightText;
            case OpShl:
                return "((" + operand(l, op, false) + ") shl (" + operand(r, op, true) + "))";
            case OpShr:
                return "((" + operand(l, op, false) + ") shr (" + operand(r, op, true) + "))";
            case OpUShr:
                return "((" + operand(l, op, false) + ") ushr (" + operand(r, op, true) + "))";
            case OpAnd:
                return "((" + operand(l, op, false) + ") and (" + operand(r, op, true) + "))";
            case OpOr:
                return "((" + operand(l, op, false) + ") or (" + operand(r, op, true) + "))";
            case OpXor:
                return "((" + operand(l, op, false) + ") xor (" + operand(r, op, true) + "))";
            case _:
                return fail(null, "unsupported binary operator: " + Std.string(op));
        }
    }

    function operand(e:TypedExpr, parent:Binop, isRight:Bool):String {
        var rendered = expr(e);
        // Nullable values still need extraction unless the Haxe expression
        // has already been normalized, or control flow proved the local is
        // non-null. Kotlin's smart casts then make `!!` redundant. A
        // null-initialized local carries a non-null Haxe type as a program
        // invariant: it extracts on every use and never joins the proof
        // set, because render-order proofs misjudge assignments inside
        // loops and branches.
        final proven = provenNonNull(e) || guardProofBefore(e);
        final nullInit = isNullInitialized(e);
        if (((isNullType(e.t) && !proven) || nullInit || rendersNullable(e)) && parent != OpEq && parent != OpNotEq) {
            rendered += "!!";
            if (!nullInit)
                addProofExpr(e);
        }
        switch (e.expr) {
            case TBinop(op, _, _):
                final cp = precedenceOf(op);
                final pp = precedenceOf(parent);
                var parens = cp < pp || (cp == pp && isRight && !associative(op));
                return parens ? "(" + rendered + ")" : rendered;
            case _:
                return rendered;
        }
    }

    function unop(e:TypedExpr, op:Unop, post:Bool, subj:TypedExpr):String {
        final inner = expr(subj);
        switch (op) {
            case OpNot:
                return "!" + inner;
            case OpNegBits:
                return inner + ".inv()";
            case OpNeg:
                return "-" + inner;
            case OpIncrement:
                return post ? inner + "++" : "++" + inner;
            case OpDecrement:
                return post ? inner + "--" : "--" + inner;
            case _:
                return fail(e, "unary operator has no lowering: " + Std.string(op));
        }
    }

    function int64Expression(e:TypedExpr):Null<String> {
        return switch (e.expr) {
            case TCall(fn, args): int64Call(fn, args);
            case _: null;
        };
    }

    function int64LongOperand(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(value)): Std.string(value) + "L";
            case _: "(" + expr(e) + ").toLong()";
        };
    }

    function int64Operand(e:TypedExpr, parentPrec:Int, isRight:Bool, parentAssociative:Bool):String {
        final rendered = expr(e);
        final ownPrec = switch (stripWrap(e).expr) {
            case TBinop(op, _, _): precedenceOf(op);
            case TCall(callFn, _): int64CallPrecedence(callFn);
            case _: 100;
        };
        return ownPrec < parentPrec || (ownPrec == parentPrec && isRight && !parentAssociative) ? "(" + rendered + ")" : rendered;
    }

    function int64CallPrecedence(fn:TypedExpr):Int {
        return switch (stripWrap(fn).expr) {
            case TField(_, FStatic(c, f)) if (c.get().module == "haxe.Int64" && c.get().name == "Int64_Impl_"):
                switch (f.get().name) {
                    case "eq" | "neq": 4;
                    case "lt" | "gt" | "lte" | "gte": 5;
                    case "add" | "sub": 7;
                    case "mul" | "mulInt": 8;
                    case _: 100;
                };
            case _: 100;
        };
    }

    function int64Call(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        return switch (PolicyQueries.int64OpOf(fn, args)) {
            case Make(high, low): "((" + int64LongOperand(high) + " shl 32) or (" + int64LongOperand(low) + " and 0xFFFFFFFFL))";
            case OfInt(value): expr(value) + ".toLong()";
            case GetHigh(value): if (isFpHelperInt64Halves(value)) expr(value) + ".high" else "(" + expr(value) + " shr 32).toInt()";
            case GetLow(value): if (isFpHelperInt64Halves(value)) expr(value) + ".low" else expr(value) + ".toInt()";
            case Add(l, r): int64Operand(l, 7, false, true) + " + " + int64Operand(r, 7, true, true);
            case Sub(l, r): int64Operand(l, 7, false, false) + " - " + int64Operand(r, 7, true, false);
            case Mul(l, r): int64Operand(l, 8, false, true) + " * " + int64Operand(r, 8, true, true);
            case MulInt(l, r): int64Operand(l, 8, false, true) + " * (" + int64Operand(r, 100, false, true) + ").toLong()";
            case And(l, r): "((" + expr(l) + ") and (" + expr(r) + "))";
            case Or(l, r): "((" + expr(l) + ") or (" + expr(r) + "))";
            case Xor(l, r): "((" + expr(l) + ") xor (" + expr(r) + "))";
            case Complement(value): "(" + expr(value) + ").inv()";
            case Shl(l, r): "((" + expr(l) + ") shl ((" + expr(r) + ") and 63))";
            case Shr(l, r): "((" + expr(l) + ") shr ((" + expr(r) + ") and 63))";
            case Ushr(l, r): "((" + expr(l) + ") ushr ((" + expr(r) + ") and 63))";
            case Eq(l, r): int64Operand(l, 4, false, false) + " == " + int64Operand(r, 4, true, false);
            case Neq(l, r): int64Operand(l, 4, false, false) + " != " + int64Operand(r, 4, true, false);
            case Lt(l, r): int64Operand(l, 5, false, false) + " < " + int64Operand(r, 5, true, false);
            case Gt(l, r): int64Operand(l, 5, false, false) + " > " + int64Operand(r, 5, true, false);
            case Lte(l, r): int64Operand(l, 5, false, false) + " <= " + int64Operand(r, 5, true, false);
            case Gte(l, r): int64Operand(l, 5, false, false) + " >= " + int64Operand(r, 5, true, false);
            case null: null;
        };
    }

    function isFpHelperInt64Halves(e:TypedExpr):Bool {
        return PolicyQueries.isFpHelperInt64Halves(e, fpInt64Halves);
    }

    function isFpHelperInt64Call(fn:TypedExpr):Bool {
        return PolicyQueries.isFpHelperInt64Call(fn);
    }

    function field(subj:TypedExpr, fa:FieldAccess):String {
        switch (fa) {
            case FStatic(c, cf):
                final cls = c.get();
                final field = cf.get();
                final rendered = staticRef(cls, field.name);
                if (DataTableHelper.isDataTableField(field))
                    return rendered + ".toMutableList()";
                // Static methods referenced as function values need a Kotlin
                // callable reference (::); kotlinc rejects property-access (.)
                // with "function invocation 'X' expected". Static vars (FVar)
                // keep dot access; only methods become references.
                if (functionTypeExpected && !field.kind.match(FVar(_, _)))
                    return referencePath(rendered);
                return rendered;
            case FEnum(e, ef):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                if (owner != null) {
                    imports.requireType(en.pack.concat([owner]).join("."), owner);
                    return owner + "." + ef.name;
                }
                imports.requireType(en.module, en.name);
                return en.name + "." + ef.name;
            case FInstance(owner, _, cf):
                final name = cf.get().name;
                final getterProperty = getterOnlyPropertyName(owner.get(), name);
                if (getterProperty != null)
                    return expr(subj) + nullableAccess(subj) + KotlinNameEscape.escape(getterProperty);
                return instanceField(subj, name, cf);
            case FAnon(cf):
                return instanceField(subj, cf.get().name, cf);
            case FDynamic(name):
                if ((name == "length" || name == "get_length") && isStringBuf(subj)) {
                    return expr(subj) + ".length";
                }
                return fail(subj, "dynamic field access has no lowering");
            case FClosure(_):
                return fail(subj, "closure has no lowering");
        }
    }

    function instanceField(subj:TypedExpr, name:String, cf:Null<Ref<ClassField>> = null):String {
        {
            final bound = catchPayloadAccess(subj, name);
            if (bound != null)
                return bound;
        }
        if (name == "message" || name == "get_message") {
            final folded = foldedExceptionMessage(subj);
            if (folded != null)
                return folded;
        }
        if (name == "length") {
            final receiver = expr(subj) + nullableAccess(subj);
            return receiver + (isString(subj) ? "length" : "size");
        }
        // A nullable subject accessing a non-null field needs `!!. ` (not `?.`)
        // so the result type stays non-null; Haxe's typed AST types the field
        // read as non-null even when the receiver is Null<T>.
        final fieldType = cf != null ? cf.get().type : null;
        final access = if (fieldType != null && !isNullType(fieldType) && isNullType(subj.t) && !provenNonNull(subj) && !guardProofBefore(subj)) {
            "!!.";
        } else {
            nullableAccess(subj);
        };
        return expr(subj) + access + KotlinNameEscape.escape(name);
    }

    function getterOnlyPropertyName(owner:ClassType, accessorName:String):Null<String> {
        if (!StringTools.startsWith(accessorName, "get_"))
            return null;
        final propertyName = accessorName.substring("get_".length);
        for (field in owner.fields.get()) {
            if (field.name == propertyName && PolicyQueries.isGetterOnlyProperty(field))
                return field.name;
        }
        return null;
    }

    function staticRef(cls:ClassType, name:String):String {
        final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
        if (valueType != null) {
            // Static members of a synthetic abstract implementation are
            // emitted on the value class, so the class reference targets
            // the value class module that declares them.
            imports.requireType(cls.module, valueType.name);
            return valueType.name + "." + name;
        }
        final markedField = findStaticField(cls, name);
        if (markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
            return imports.functionRef(cls.module, name, markedField.isPublic);
        }
        final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
        switch (path) {
            case "String":
                return "String." + name;
            case "haxe.io.FPHelper":
                // The f32 configuration uses the two value-edge calls for
                // binary32; the 8-byte wire layout retains its f64 shape on
                // both configurations (feature spec 23).
                imports.requireType(cls.module, cls.name);
                if (FloatPrecision.isF32()) {
                    if (name == "i64ToDouble")
                        return "FPHelper.i64ToF32";
                    if (name == "doubleToI64")
                        return "FPHelper.f32ToI64";
                }
                return "FPHelper." + name;
            case "Math":
                // The f32 configuration reads every Math static from the Float family;
                // kotlin.math free functions carry Float overloads, so the
                // java.lang.Math (Double-only) reference is never emitted
                // under the switch (feature spec 23).
                if (FloatPrecision.isF32()) {
                    if (name == "NaN")
                        return "Float.NaN";
                    if (name == "POSITIVE_INFINITY")
                        return "Float.POSITIVE_INFINITY";
                    if (name == "NEGATIVE_INFINITY")
                        return "Float.NEGATIVE_INFINITY";
                    return "kotlin.math." + name;
                }
                if (name == "NaN")
                    return "Double.NaN";
                if (name == "POSITIVE_INFINITY")
                    return "Double.POSITIVE_INFINITY";
                if (name == "NEGATIVE_INFINITY")
                    return "Double.NEGATIVE_INFINITY";
                return "Math." + name;
            case _ if (KotlinTestBinding.isTestExtern(cls)):
                final runtimePackage = RuntimeConfig.requireImportName("module test extern");
                state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                imports.require(runtimePackage + ".test.Test");
                return "Test." + name;
            case "std.SortedMap":
                // The sorted resident owns the factory functions; the
                // extern's `builder` maps onto the map flavor.
                imports.requireType("std.SortedMap", "SortedTable");
                return "SortedTable." + (name == "builder" ? "mapBuilder" : name);
            case "std.SortedSet":
                imports.requireType("std.SortedSet", "SortedTable");
                return "SortedTable." + (name == "builder" ? "setBuilder" : name);
            case "std.UStringRT":
                final runtimePackage = RuntimeConfig.requireImportName("module std.UStringRT");
                state.shimsUsed.set("std.UStringRT", true);
                imports.require(runtimePackage + ".UString");
                return "UString." + name;
            case "StringTools":
                // StringTools statics without a native Kotlin lowering
                // (lpad, rpad, ltrim, rtrim, replace, ...) route into the
                // runtime module, avoiding an unresolvable top-level
                // StringTools reference. The inline-lowered ones (hex,
                // trim, startsWith, endsWith) are handled before staticRef.
                // The call renders fully qualified so no bare `StringTools.`
                // identifier leaks into a generated tree (docs/specs
                // stdlib/06: StringTools conversions stay inline-lowered).
                final strToolsPackage = RuntimeConfig.requireImportName("module StringTools");
                state.shimsUsed.set("StringTools", true);
                return strToolsPackage + ".StringTools." + name;
            case "std.Graphemes":
                final graphemesPackage = RuntimeConfig.requireImportName("module std.Graphemes");
                state.shimsUsed.set("std.Graphemes", true);
                imports.require(graphemesPackage + ".Graphemes");
                return "Graphemes." + name;
            case _:
                if (KotlinTestBinding.isTestExtern(cls)) {
                    final runtimePackage = RuntimeConfig.requireImportName("module test extern");
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    imports.require(runtimePackage + ".test.Test");
                    return "Test." + name;
                }
                if (cls.module == "std.SortedMap") {
                    imports.requireType("std.SortedMap", "SortedTable");
                    return "SortedTable." + (name == "builder" ? "mapBuilder" : name);
                }
                if (cls.module == "std.SortedSet") {
                    imports.requireType("std.SortedSet", "SortedTable");
                    return "SortedTable." + (name == "builder" ? "setBuilder" : name);
                }
                if (cls.module == "std.UStringRT") {
                    final runtimePackage = RuntimeConfig.requireImportName("module std.UStringRT");
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require(runtimePackage + ".UString");
                    return "UString." + name;
                }
                if (cls.module == "std.Graphemes") {
                    final graphemesPackage = RuntimeConfig.requireImportName("module std.Graphemes");
                    state.shimsUsed.set("std.Graphemes", true);
                    imports.require(graphemesPackage + ".Graphemes");
                    return "Graphemes." + name;
                }
                if (cls.module == "std.Fs" || cls.module == "std.Env") {
                    Context.error("std.Fs and std.Env statics lower at their call site; a bare reference has no lowering", Context.currentPos());
                }
                if (cls.module != "" && StringTools.endsWith(cls.name, "_Impl_")) {
                    // A sub-type abstract's non-inline static (for example
                    // `FontId.of`) lowers to the synthetic implementation's
                    // `_Impl_` companion. The call site names that object, so
                    // compileClassImpl must not drop the referenced `_Impl_`
                    // even though ordinary synthetic impls never emit.
                    state.referencedImpls.set(cls.module, true);
                }
                imports.requireType(cls.module, cls.name);
                return cls.name + "." + name;
        }
    }

    function findStaticField(cls:ClassType, name:String):Null<ClassField> {
        return PolicyQueries.findStaticField(cls, name);
    }

    /** Converts a dot-separated class reference into a Kotlin callable reference. */
    function referencePath(rendered:String):String {
        final dotIdx = rendered.lastIndexOf(".");
        return dotIdx >= 0 ? rendered.substring(0, dotIdx) + "::" + rendered.substring(dotIdx + 1) : "::" + rendered;
    }

    function typeExpr(t:ModuleType):String {
        switch (t) {
            case TClassDecl(c):
                final cls = c.get();
                if (cls.pack.length == 0 && (cls.name == "String" || cls.name == "Math")) {
                    return cls.name;
                }
                if (KotlinTestBinding.isTestExtern(cls)) {
                    final runtimePackage = RuntimeConfig.requireImportName("module test extern");
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    imports.require(runtimePackage + ".test.Test");
                    return "Test";
                }
                imports.requireType(cls.module, cls.name);
                return cls.name;
            case TEnumDecl(e):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                if (owner != null) {
                    return owner;
                }
                imports.requireType(en.module, en.name);
                return en.name;
            case _:
                Context.error("type expression has no value lowering", Context.currentPos());
                return null;
        }
    }

    function stdString(arg:TypedExpr, inConcat:Bool):String {
        final fromSource = PolicyQueries.inSourceScope(arg.pos);
        final nullable = PolicyQueries.isNullableType(arg.t);
        if (fromSource && nullable) {
            Context.error("Std.string does not accept Null<T> operands; compare against null first", arg.pos);
        }
        return stdStringType(arg.t, !fromSource && nullable ? "(" + expr(arg) + ")!!" : expr(arg), inConcat, arg);
    }

    function stdIsOfType(args:Array<TypedExpr>):String {
        final target = TypeCheckHelper.classOfTypeExpr(args[1]);
        if (target == null) {
            Context.error("Std.isOfType requires a class type expression", args[1].pos);
            return "false";
        }
        final known = TypeCheckHelper.knownIsOfType(args[0], target);
        return known != null ? (known ? "true" : "false") : expr(args[0]) + " is " + expr(args[1]);
    }

    function stdStringType(t:Type, value:String, inConcat:Bool, origin:TypedExpr, depth:Int = 0):String {
        return switch (PolicyQueries.stdStringCategory(t)) {
            case IsString: value;
            case IsArray(element):
                final index = depth == 0 ? "i" : "i" + depth;
                final item = stdStringType(element, value + "[" + index + "]", true, origin, depth + 1);
                'run { val sb = StringBuilder(); sb.append(\'[\'); val n = ${value}.size; var ${index} = 0; while (${index} < n) { if (${index} > 0) { sb.append(", "); }; sb.append(${item}); ${index} += 1; }; sb.append(\']\'); sb.toString() }';
            case IsSortedSet(element):
                final index = depth == 0 ? "i" : "i" + depth;
                final item = stdStringType(element, value + ".at(" + index + ")", true, origin, depth + 1);
                'run { val sb = StringBuilder(); sb.append(\'[\'); val n = ${value}.size(); var ${index} = 0; while (${index} < n) { if (${index} > 0) { sb.append(", "); }; sb.append(${item}); ${index} += 1; }; sb.append(\']\'); sb.toString() }';
            case IsSortedMap(key, val):
                final index = depth == 0 ? "i" : "i" + depth;
                final itemKey = stdStringType(key, value + ".keyAt(" + index + ")", true, origin, depth + 1);
                final itemVal = stdStringType(val, value + ".valueAt(" + index + ")", true, origin, depth + 1);
                'run { val sb = StringBuilder(); sb.append(\'{\'); val n = ${value}.size(); var ${index} = 0; while (${index} < n) { if (${index} > 0) { sb.append(", "); }; sb.append(${itemKey}); sb.append("="); sb.append(${itemVal}); ${index} += 1; }; sb.append(\'}\'); sb.toString() }';
            case IsRecordLike: value + ".toString()";
            case IsInstanceToString: value + ".toString()";
            case IsMarkedAbstract(abs):
                if (ValueTypeSupport.memberField(abs, "toString") != null) {
                    value + ".toString()";
                } else {
                    final representation = value + "." + ValueTypeSupport.representationFieldName(abs);
                    inConcat ? representation : "(" + representation + ").toString()";
                }
            case IsFloat:
                final runtimePackage = RuntimeConfig.requireImportName("module haxe.io.FPHelper");
                imports.require(runtimePackage + ".FPHelper");
                state.shimsUsed.set("haxe.io.FPHelper", true);
                runtimePackage
                + ".FPHelper.formatFloat("
                + value
                + ")";
            case IsInt | IsBool:
                inConcat ? value : "(" + value + ").toString()";
            case IsTypeParameter:
                inConcat ? value + ".toString()" : "(" + value + ").toString()";
            case IsReadOnlyArray(underlying):
                stdStringType(underlying, value, inConcat, origin, depth);
            case IsParameterlessEnum(en):
                // The rendered value may itself be nullable (e.g. Std.string of
                // a field read off a nullable receiver); choose the suffix
                // from the rendered nullability so safe-navigation is emitted
                // when the value is nullable. An extracted value ends in "!!".
                final suffix = if (StringTools.endsWith(value, "!!")) ".name" else nullableAccessEnumName(origin);
                value + (inConcat ? "" : suffix);
            case IsCyclicEnum(en): cyclicEnumString(en, value, inConcat, origin);
            case IsPayloadEnum(_): inConcat ? value : value + ".toString()";
            case IsNull | IsUnsupported:
                Context.error("Std.string accepts scalars, enum values, records, and arrays of them only", origin.pos);
                null;
        };
    }

    /** Suffix for reading a parameterless enum value's name: ".name" when the
        value is non-null, "?." prefixed otherwise. Mirrors nullableAccess but
        emits the field name too. **/
    function nullableAccessEnumName(subj:TypedExpr):String {
        if (isNullType(subj.t) && !provenNonNull(subj) && !guardProofBefore(subj))
            return "?.name";
        if (nullableChainHop(subj) && !guardProofBefore(subj))
            return "?.name";
        return ".name";
    }

    function hasInstanceToString(cls:ClassType):Bool {
        return PolicyQueries.hasInstanceToString(cls);
    }

    function cyclicEnumString(en:EnumType, value:String, inConcat:Bool, origin:TypedExpr):String {
        final existing = enumStringNaming.existing(en);
        if (existing != null)
            return existing + "(" + value + ")";
        final name = enumStringNaming.open(en, "stdString" + en.name);
        final arms:Array<String> = [];
        for (ef in en.constructs) {
            final args = switch (ef.type) {
                case TFun(a, _): a;
                case _: [];
            };
            if (args.length == 0) {
                arms.push(en.name + "." + ef.name + " -> \"" + ef.name + "\"");
            } else {
                final pieces = [
                    for (a in args)
                        "\"" + a.name + "=\" + (" + stdStringType(a.t, "v." + a.name, true, origin) + ")"
                ];
                arms.push("is " + en.name + "." + ef.name + " -> \"" + ef.name + "(\" + " + pieces.join(" + \", \" + ") + " + \")\"");
            }
        }
        enumStringNaming.close(en);
        return "run { fun "
            + name
            + "(v: "
            + en.name
            + "): String { return when (v) { "
            + arms.join("\n")
            + " } }; "
            + name
            + "("
            + value
            + ") }";
    }

    function isParameterlessEnum(en:EnumType):Bool {
        return PolicyQueries.isParameterlessEnum(en);
    }

    function stdStringArg(e:TypedExpr):Null<TypedExpr> {
        return PolicyQueries.stdStringArg(e);
    }

    function stringToolsHex(args:Array<TypedExpr>):String {
        final validated = PolicyQueries.stringToolsHexArgs(args);
        final value = validated.value;
        final digits = validated.digits;
        final valueText = "(" + expr(value) + ")";
        final hex = valueText + ".toUInt().toString(16).uppercase()";
        return digits == null ? hex : hex + ".padStart(" + expr(digits) + ", '0')";
    }

    function isNegativeIntLiteral(e:TypedExpr):Bool {
        return ExpressionPredicates.isNegativeIntLiteral(e);
    }

    function isNullExpr(e:TypedExpr):Bool {
        return ExpressionPredicates.isNullExpr(e);
    }

    /** Routes calls on a marked abstract implementation to value members. */
    function valueTypeCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        switch (stripWrap(fn).expr) {
            case TField(_, FStatic(c, cf)):
                final abs = ValueTypeSupport.markedAbstractOfClass(c.get());
                if (abs == null)
                    return null;
                final field = cf.get();
                if (field.name == "_new") {
                    if (args.length == 0)
                        return abs.name;
                    var argText = expr(args[0]);
                    // Haxe unifies Int and Float; widen Int arguments to Float
                    // when the value type's representation is Float.
                    if (isIntOrLongType(emittedType(args[0])) && ValueTypeSupport.isFloatRepresentation(abs))
                        argText = intToFloatText(argText);
                    return abs.name + "(" + argText + ")";
                }
                final op = ValueTypeSupport.operatorOf(abs, field);
                if (op != null) {
                    return switch (op) {
                        case Binary(_): args.length >= 2 ? expr(args[0]) + " " + opStrForValue(op) + " " + expr(args[1]) : abs.name;
                        case Unary(_): args.length > 0 ? "-" + expr(args[0]) : abs.name;
                    };
                }
                if (ValueTypeSupport.hasReceiver(field) && args.length > 0) {
                    final tail = [for (i in 1...args.length) expr(args[i])].join(", ");
                    return expr(args[0]) + "." + kotlinMethodName(field.name) + "(" + tail + ")";
                }
                return abs.name + "." + field.name + "(" + [for (a in args) expr(a)].join(", ") + ")";
            case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
                final abs = ValueTypeSupport.markedAbstractOfType(subj.t);
                if (abs == null)
                    return null;
                return expr(subj) + "." + kotlinMethodName(cf.get().name) + "(" + [for (a in args) expr(a)].join(", ") + ")";
            case _:
        }
        return null;
    }

    function opStrForValue(op:ValueTypeOperator):String {
        return switch (op) {
            case Binary(binary): opStr(binary);
            case Unary(_): "-";
        };
    }

    /**
        Call shapes that render their argument text themselves (so they must
        not let localCallArgs register proofs for discarded renderings). The
        fromCharCode template appends its own `!!` for unproven nullable
        arguments and registers the proof, matching renderCallArgs.
    **/
    function selfRenderedCallText(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        switch (fn.expr) {
            case TField(subj, FInstance(owner, _, cf))
                if (cf.get().name == "indexOf" && args.length == 2 && isNullLiteral(args[1]) && owner.get().pack.length == 0 && owner.get().name == "Array"):
                // The haxe typer passes a synthesized null for the
                // omitted ?fromIndex; the platform indexOf takes only
                // the element, and a null fromIndex searches from the
                // start like the omitted call (features/08 ruling 8),
                // so the null argument is dropped from the rendered
                // call. Rendering the element argument here keeps
                // localCallArgs from registering a proof for the
                // discarded null rendering.
                final elementArg = renderCallArgs([args[0]], paramsForCall(fn), owner.get(), cf.get().name)[0];
                return expr(subj) + nullableAccess(subj) + "indexOf(" + elementArg + ")";
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "alloc" && args.length == 1):
                return "ByteArray(" + expr(args[0]) + ")";
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "ofString" && args.length == 1):
                return expr(args[0]) + ".toByteArray(Charsets.UTF_8)";
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "concat" && args.length == 2):
                return expr(args[0]) + " + " + expr(args[1]);
            case TField(_, FStatic(c, cf)) if (c.get().pack.length == 0 && c.get().name == "String" && cf.get().name == "fromCharCode" && args.length == 1):
                final code = expr(args[0]);
                final assertNeeded = isNullType(args[0].t) && !provenNonNull(args[0]) && !guardProofBefore(args[0]);
                if (assertNeeded)
                    addProofExpr(args[0]);
                return "((" + code + (assertNeeded ? ")!!" : ")") + ".toChar()).toString()";
            case _:
                return null;
        }
    }

    /** A StringTools receiver argument renders with a null extraction when
        its Haxe type is nullable, mirroring renderCallArgs. */
    function nullableFirstArg(a:TypedExpr):String {
        final rendered = expr(a);
        if (isNullType(a.t) && !provenNonNull(a) && !guardProofBefore(a)) {
            addProofExpr(a);
            return rendered + "!!";
        }
        return rendered;
    }

    function call(fn:TypedExpr, args:Array<TypedExpr>):String {
        final int64CallText = int64Call(fn, args);
        if (int64CallText != null)
            return int64CallText;
        final wrapperCall = valueTypeCall(fn, args);
        if (wrapperCall != null)
            return wrapperCall;
        switch (fn.expr) {
            case TField(_, FStatic(c, cf)) if (c.get().module == "Std" && cf.get().name == "string" && args.length == 1):
                return stdString(args[0], false);
            case TField(_, FStatic(c, cf)) if (c.get().module == "Std" && cf.get().name == "isOfType" && args.length == 2):
                return stdIsOfType(args);
            case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "get_message" && args.length == 0):
                final folded = foldedExceptionMessage(subj);
                if (folded != null) {
                    return folded;
                }
            case TField(subj, FStatic(c, cf)):
                final cls = c.get();
                final name = cf.get().name;
                if (cls.module == "org.tiqian.test.trace.TestTracePlatform" && cls.name == "NodeFileSystem") {
                    // The node:fs extern has no JVM face; the test-trace
                    // golden writer lowers to java.nio.file so the generated
                    // Kotlin compiles and keeps writing trace files.
                    if (name == "mkdirSync" && args.length >= 1) {
                        return "java.nio.file.Files.createDirectories(java.nio.file.Paths.get(" + expr(args[0]) + "))";
                    }
                    if (name == "writeFileSync" && args.length >= 2) {
                        return "java.nio.file.Files.writeString(java.nio.file.Paths.get(" + expr(args[0]) + "), " + expr(args[1]) + ")";
                    }
                }
                if (cls.pack.length == 0 && cls.name == "StringTools" && name == "hex") {
                    return stringToolsHex(args);
                }
                if (cls.pack.length == 0 && cls.name == "StringTools" && name == "trim" && args.length == 1) {
                    return nullableFirstArg(args[0]) + ".trim()";
                }
                if (cls.pack.length == 0
                    && cls.name == "StringTools"
                    && (name == "startsWith" || name == "endsWith")
                    && args.length == 2) {
                    // nullableFirstArg only appends "!!" for a null-typed
                    // argument; a non-null-typed argument can still render
                    // nullable (e.g. a field read off a nullable receiver), so
                    // choose the separator from the argument's nullability.
                    final firstArg = args[0];
                    final nullable = (isNullType(firstArg.t) && !provenNonNull(firstArg) && !guardProofBefore(firstArg))
                        || (nullableChainHop(firstArg) && !guardProofBefore(firstArg));
                    return expr(firstArg) + (nullable ? "?." : ".") + name + "(" + expr(args[1]) + ")";
                }
                if (cls.pack.length == 0 && cls.name == "Lambda" && name == "has" && args.length == 2) {
                    return expr(args[0]) + ".contains(" + expr(args[1]) + ")";
                }
                if (cls.module == "Math" && name == "isNaN")
                    return "(" + kotlinMathFloatArg(args[0]) + ").isNaN()";
                if (cls.module == "Math" && name == "isFinite")
                    return "(" + kotlinMathFloatArg(args[0]) + ").isFinite()";
                if (cls.module == "Math" && name == "pow" && args.length == 2) {
                    imports.require("kotlin.math.pow");
                    return "(" + kotlinMathFloatArg(args[0]) + ").pow(" + kotlinMathFloatArg(args[1]) + ")";
                }
                if (cls.module == "Math" && name == "sqrt")
                    return "kotlin.math.sqrt(" + kotlinMathFloatArg(args[0]) + ")";
                if (cls.module == "Math" && (name == "floor" || name == "ceil" || name == "round")) {
                    // Haxe types floor, ceil, and round as Int. floor and
                    // ceil convert through kotlin.math (Float and Double
                    // overloads); round reads java.lang.Math.round, whose
                    // half-up ties match the TS Math.round exactly, while
                    // kotlin.math.round sends ties toward zero.
                    if (name == "round")
                        return FloatPrecision.isF32() ? "Math.round(" + expr(args[0]) + ")" : "Math.round(" + expr(args[0]) + ").toInt()";
                    return "(kotlin.math." + name + "(" + kotlinMathFloatArg(args[0]) + ")).toInt()";
                }
                if (cls.module == "Std" && (name == "parseFloat" || name == "parseInt") && args.length == 1) {
                    final s = expr(args[0]);
                    final real = FloatPrecision.isF32() ? "Float" : "Double";
                    final nan = FloatPrecision.isF32() ? "Float.NaN" : "Double.NaN";
                    if (name == "parseFloat")
                        return "run { val s = "
                            + s
                            +
                            "; val t = s.trim(' ', '\\t', '\\n', '\\r', '\\u000B', '\\u000C'); var i = 0; if (i < t.length && (t[i] == '+' || t[i] == '-')) i++; val before = i; while (i < t.length && t[i] in '0'..'9') i++; val hasBefore = i > before; var hasAfter = false; if (i < t.length && t[i] == '.') { i++; val start = i; while (i < t.length && t[i] in '0'..'9') i++; hasAfter = i > start } else if (!hasBefore) return@run "
                            + nan
                            + "; if (!hasBefore && !hasAfter) return@run "
                            + nan
                            +
                            "; if (i < t.length && (t[i] == 'e' || t[i] == 'E')) { i++; if (i < t.length && (t[i] == '+' || t[i] == '-')) i++; val start = i; while (i < t.length && t[i] in '0'..'9') i++; if (i == start) return@run "
                            + nan
                            + " }; if (i != t.length) "
                            + nan
                            + " else t."
                            + (FloatPrecision.isF32() ? "toFloatOrNull() ?: Float.NaN" : "toDoubleOrNull() ?: Double.NaN")
                            + " }";
                    return "run { val s = "
                        + s
                        +
                        "; val t = s.trim(' ', '\\t', '\\n', '\\r', '\\u000B', '\\u000C'); val neg = t.startsWith(\"-\"); val sign = if (neg || t.startsWith(\"+\")) 1 else 0; val hex = t.startsWith(\"0x\", sign) || t.startsWith(\"0X\", sign); val d = if (hex) t.substring(sign + 2) else t.substring(sign); if (!hex) { var i = sign; val start = i; while (i < t.length && t[i] in '0'..'9') i++; if (i != t.length || i == start) null else t.toIntOrNull() } else { var i = 0; while (i < d.length && d[i] in '0'..'9' || i < d.length && d[i] in 'a'..'f' || i < d.length && d[i] in 'A'..'F') i++; if (i != d.length || d.isEmpty()) null else { val n = d.toLongOrNull(16); if (n == null) null else { val v = if (neg) -n else n; if (v >= -2147483648L && v <= 2147483647L) v.toInt() else null } } } }";
                }
                final markedField = findStaticField(cls, name);
                if (markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
                    final nativeName = staticRef(cls, name);
                    final rendered = [for (a in args) expr(a)];
                    if (StaticFunctionMarkers.isExtension(markedField)) {
                        return expr(args[0]) + "." + nativeName + "(" + rendered.slice(1).join(", ") + ")";
                    }
                    return nativeName + "(" + rendered.join(", ") + ")";
                }
                if (cls.module == "std.UStringPlatform") {
                    // Cursor primitives of the resident UString walk, inlined
                    // per call: a cursor is a UTF-16 unit index here, so end
                    // is the unit length and codePointAt combines surrogate
                    // pairs. Business code never reaches these; it calls
                    // std.UString.
                    switch (name) {
                        case "end":
                            return expr(args[0]) + ".length";
                        case "codeAt":
                            return expr(args[0]) + ".codePointAt(" + expr(args[1]) + ")";
                        case "advance":
                            return "(" + expr(args[1]) + " + Character.charCount(" + expr(args[0]) + ".codePointAt(" + expr(args[1]) + ")))";
                        case "substringBetween":
                            return expr(args[0]) + ".substring(" + expr(args[1]) + ", " + expr(args[2]) + ")";
                        case "fromCodePoint":
                            return "String(Character.toChars(" + expr(args[0]) + "))";
                        case _:
                    }
                }
                if (cls.module == "std.Fs") {
                    return fsCall(name, args, fn);
                }
                if (cls.module == "std.Env") {
                    return envCall(name, args, fn);
                }
                if (cls.module == "std.Process" && name == "args") {
                    return processArgs(fn);
                }
                if (KotlinTestBinding.isTestPlatformExtern(cls.module)) {
                    // Host edges of the resident runtime.TestCore, inlined
                    // per call: raising is an AssertionError, the running
                    // test id lives in the Test host of this same package,
                    // and plain numbers render through toString. Marking the
                    // test extern shim used keeps that host emitted beside this
                    // resident. Business code never reaches these; it calls
                    // test extern.
                    if (!imports.selfResident) {
                        Context.error("test platform extern is a resident runtime primitive; business code calls test extern", fn.pos);
                    }
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    switch (name) {
                        case "raise":
                            return "throw AssertionError(" + expr(args[0]) + ")";
                        case "currentTestId":
                            return "Test.currentTestIdState()";
                        case "intToString":
                            return "(" + expr(args[0]) + ").toString()";
                        case "floatToString":
                            return "(" + expr(args[0]) + ").toString().replace(\"E\", \"e\").replace(\".0e\", \"e\")";
                        case _:
                    }
                }
                if ((cls.name == "Functional"
                    || cls.name == "__functional_shim"
                    || cls.module == "std.Functional"
                    || cls.pack.join(".") + "." + cls.name == "std.Functional")) {
                    final receiver = args[0];
                    if (name == "sortedBy") {
                        final lambda = args[1];
                        final func = unwrapLambda(lambda);
                        if (func != null && func.args.length == 1) {
                            final paramName = KotlinNameEscape.escape(func.args[0].v.name);
                            final keyExpr = expr(lambdaBody(func.expr));
                            return expr(receiver) + ".toMutableList().apply { sortBy { " + paramName + " -> " + keyExpr + " } }";
                        }
                    }
                    if (name == "sumOfFloat") {
                        final func = unwrapLambda(args[1]);
                        if (func != null && func.args.length == 1) {
                            final paramName = KotlinNameEscape.escape(func.args[0].v.name);
                            final valueExpr = expr(lambdaBody(func.expr));
                            return expr(receiver) + ".sumOf { " + paramName + " -> (" + valueExpr + ").toDouble() }.toFloat()";
                        }
                        return fail(fn, "sumOfFloat requires a one-argument lambda");
                    }
                    if (name == "forEach") {
                        return expr(receiver) + ".forEach(" + expr(args[1]) + ")";
                    }
                }
            case _:
        }
        final inlineMapCall = mapHasOwnPropertyCall(fn, args);
        if (inlineMapCall != null) {
            return inlineMapCall;
        }
        // Branches that render their own argument text must run before
        // localCallArgs: renderCallArgs registers a non-null proof for every
        // `!!` it appends, so a rendering whose text is then discarded would
        // leave a phantom proof that later emissions trust.
        final selfRendered = selfRenderedCallText(fn, args);
        if (selfRendered != null) {
            return selfRendered;
        }
        final renderedArgs = localCallArgs(fn, args);
        switch (fn.expr) {
            case TCast(inner, _):
                return call(inner, args);
            case TField(subj, FDynamic(name)) if ((name == "length" || name == "get_length") && isStringBuf(subj)):
                return expr(subj) + ".length";
            case TField(subj, FInstance(owner, _, cf)):
                final name = cf.get().name;
                final getterProperty = getterOnlyPropertyName(owner.get(), name);
                if (getterProperty != null && args.length == 0)
                    return expr(subj) + nullableAccess(subj) + KotlinNameEscape.escape(getterProperty);
                if (isString(subj)) {
                    if (name == "toLowerCase")
                        return expr(subj) + ".lowercase()";
                    if (name == "toUpperCase")
                        return expr(subj) + ".uppercase()";
                }
                if (name == "toChar" && isNullType(subj.t))
                    return "(" + expr(subj) + ")!!.toChar()";
                if (isMapType(subj.t)) {
                    if (name == "exists" && args.length == 1)
                        return expr(subj) + ".containsKey(" + expr(args[0]) + ")";
                    if (name == "get" && args.length == 1)
                        return expr(subj) + "[" + expr(args[0]) + "]";
                    if (name == "set" && args.length == 2)
                        return expr(subj) + ".put(" + expr(args[0]) + ", " + expr(args[1]) + ")";
                }
                if (name == "toChar" && isNullType(subj.t))
                    return "(" + expr(subj) + ")!!.toChar()";
                if (isStringBuf(subj)) {
                    // stdlib/08: a Kotlin throw is an expression, so the
                    // checked operations stay expression-capable; the
                    // statement form below emits the flat check + op pair.
                    if (name == "add") {
                        return "if (" + stringBufAddFaultCond(subj, args[0]) + ") throw " + stringBufFaultConstructor(stringBufTailRead(subj)) + " else "
                            + expr(subj) + ".append(" + expr(args[0]) + ")";
                    }
                    if (name == "addChar") {
                        final u = expr(args[0]);
                        final unit = "if (" + stringBufTrailCond(u) + ") " + u + " else " + stringBufTailRead(subj);
                        return "if (" + stringBufAddCharFaultCond(subj, args[0]) + ") throw " + stringBufFaultConstructor(unit) + " else " + expr(subj)
                            + ".append((" + u + ").toChar())";
                    }
                    if (name == "toString") {
                        return "if (" + stringBufDanglingCond(subj) + ") throw " + stringBufFaultConstructor(stringBufTailRead(subj)) + " else "
                            + expr(subj) + ".toString()";
                    }
                    if (name == "get_length" || name == "length") {
                        return expr(subj) + ".length";
                    }
                }
                if (name == "get" && isBytes(stripCast(subj))) {
                    return "(( " + expr(subj) + "[" + expr(args[0]) + "].toInt() and 0xFF ))";
                }
                if (name == "set" && args.length == 2 && isBytes(stripCast(subj))) {
                    return expr(subj) + "[" + expr(args[0]) + "] = " + expr(args[1]) + ".toByte()";
                }
                if (name == "blit" && args.length == 4 && isBytes(stripCast(subj))) {
                    return "(" + expr(args[1]) + ").copyInto(" + expr(subj) + ", " + expr(args[0]) + ", " + expr(args[2]) + ", " + expr(args[2]) + " + "
                        + expr(args[3]) + ")";
                }
                if (name == "fill" && args.length == 3 && isBytes(stripCast(subj))) {
                    return expr(subj)
                        + ".fill("
                        + expr(args[2])
                        + ".toByte(), "
                        + expr(args[0])
                        + ", "
                        + expr(args[0])
                        + " + "
                        + expr(args[1])
                        + ")";
                }
                if (name == "sub" && args.length == 2 && isBytes(stripCast(subj))) {
                    return expr(subj) + ".copyOfRange(" + expr(args[0]) + ", " + expr(args[0]) + " + " + expr(args[1]) + ")";
                }
                if (name == "getString" && args.length == 2 && isBytes(stripCast(subj))) {
                    return "String(" + expr(subj) + ", " + expr(args[0]) + ", " + expr(args[1]) + ", Charsets.UTF_8)";
                }
                if (name == "charAt" && isString(stripCast(subj))) {
                    return expr(subj) + "[" + expr(args[0]) + "].toString()";
                }
                if (name == "charCodeAt" && (isString(stripCast(subj)) || isNullStringReceiver(subj))) {
                    // stdlib/15: capture both operands once, then make the
                    // platform bounds check explicit so the result is Null<Int>.
                    // A Null<String> receiver renders with a forced unwrap so
                    // the captured `_s` is a plain String.
                    final receiver = expr(subj) + (isNullStringReceiver(subj) ? "!!" : "");
                    return "run { val _s = "
                        + receiver
                        + "; val _i = "
                        + expr(args[0])
                        + "; if (_i >= 0 && _i < _s.length) _s[_i].code else null }";
                }
                if (name == "charCodeAt") {
                    // Fallback: treat charCodeAt on any receiver the same way
                    // when the type-checking didn't recognise a String type.
                    final receiver = expr(subj) + (rendersNullable(subj) ? "!!" : "");
                    return "run { val _s = "
                        + receiver
                        + "; val _i = "
                        + expr(args[0])
                        + "; if (_i >= 0 && _i < _s.length) _s[_i].code else null }";
                }
                if (name == "indexOf" && isString(stripCast(subj)) && args.length >= 1) {
                    return expr(subj) + ".indexOf(" + expr(args[0]) + ")";
                }
                if (name == "lastIndexOf" && isString(stripCast(subj)) && args.length >= 1) {
                    return expr(subj) + ".lastIndexOf(" + expr(args[0]) + ")";
                }
                if (name == "substring" && isString(stripCast(subj))) {
                    // The haxe typer passes a synthesized null for an
                    // omitted ?endIndex; the platform one-argument
                    // overload is the suffix call, so the null argument
                    // is omitted from the rendered call.
                    final endOmitted = args.length < 2 || switch (stripWrap(args[1]).expr) {
                        case TConst(TNull): true;
                        case _: false;
                    };
                    if (endOmitted) {
                        return "run { val _s = "
                            + expr(subj)
                            + "; val _from = "
                            + expr(args[0])
                            + "; val _start = if (_from < 0) 0 else if (_from > _s.length) _s.length else _from; _s.substring(_start) }";
                    }
                    return "run { val _s = "
                        + expr(subj)
                        + "; val _from = "
                        + expr(args[0])
                        + "; val _to = "
                        + expr(args[1])
                        + "; val _start = if (_from < 0) 0 else if (_from > _s.length) _s.length else _from"
                        + "; val _end = if (_to < 0) 0 else if (_to > _s.length) _s.length else _to"
                        + "; if (_start > _end) _s.substring(_end, _start) else _s.substring(_start, _end) }";
                }
                if (name == "substr" && isString(stripCast(subj))) {
                    // The haxe typer passes a synthesized null for an
                    // omitted ?len; the native call is index-based, so
                    // the length converts to an end bound after the pos
                    // clamping, and a negative len yields the empty
                    // string like the JavaScript target.
                    final lenOmitted = args.length < 2 || switch (stripWrap(args[1]).expr) {
                        case TConst(TNull): true;
                        case _: false;
                    };
                    if (lenOmitted) {
                        return "run { val _s = "
                            + expr(subj)
                            + "; val _pos = "
                            + expr(args[0])
                            + "; val _start = if (_pos < 0) maxOf(0, _s.length + _pos) else minOf(_pos, _s.length); _s.substring(_start) }";
                    }
                    return "run { val _s = "
                        + expr(subj)
                        + "; val _pos = "
                        + expr(args[0])
                        + "; val _len = "
                        + expr(args[1])
                        + "; val _start = if (_pos < 0) maxOf(0, _s.length + _pos) else minOf(_pos, _s.length)"
                        + "; if (_len < 0) \"\" else { val _end = minOf(_s.length, _start + _len); _s.substring(_start, _end) } }";
                }
                final arrayReceiver = switch (Context.follow(subj.t)) {
                    case TInst(c, _): c.get().name == "Array";
                    case _: false;
                };
                if (arrayReceiver) {
                    switch (name) {
                        case "push": return expr(subj) + ".add(" + renderedArgs + ")";
                        case "join": return expr(subj) + ".joinToString(" + renderedArgs + ")";
                        case "concat": return "(" + expr(subj) + " + " + renderedArgs + ").toMutableList()";
                        case "copy": return expr(subj) + ".toMutableList()";
                        case "pop": return "if (" + expr(subj) + ".isEmpty()) null else " + expr(subj) + ".removeAt(" + expr(subj) + ".lastIndex)";
                        case "shift": return "if (" + expr(subj) + ".isEmpty()) null else " + expr(subj) + ".removeAt(0)";
                        case "unshift": return expr(subj) + ".add(0, " + renderedArgs + ")";
                        case "insert": return expr(subj) + ".add(" + expr(args[0]) + ", " + expr(args[1]) + ")";
                        case "splice": return "run { val _a = "
                                + expr(subj)
                                + "; val _i = "
                                + expr(args[0])
                                + "; val _n = "
                                + expr(args[1])
                                + "; val _r = _a.subList(_i, _i + _n).toMutableList(); _a.subList(_i, _i + _n).clear(); _r }";
                        case "get_length" | "length": return expr(subj) + ".size";
                        case _:
                    }
                }
                if (name == "push") {
                    return expr(subj) + ".add(" + renderedArgs + ")";
                }
                if (name == "join") {
                    // The receiver may render nullable (e.g. a Map.get result);
                    // emit safe call when it is nullable.
                    return expr(subj) + (rendersNullable(subj) ? "?." : ".") + "joinToString(" + renderedArgs + ")";
                }
                if (name == "slice" && args.length == 2 && owner.get().pack.length == 0 && owner.get().name == "Array") {
                    // The haxe slice bounds are end-exclusive, so the
                    // platform range overload receives the half-open
                    // interval, like the Swift and Dart lowerings.
                    return expr(subj) + nullableAccess(subj) + name + "(" + expr(args[0]) + " until " + expr(args[1]) + ")";
                }
                if (name == "split" && mutableArrayAccess && isString(stripCast(subj)))
                    return expr(subj) + ".split(" + renderedArgs + ").toMutableList()";
                return expr(subj) + nullableAccess(subj) + name + "(" + renderedArgs + ")";
            case TField(_, FStatic(c, cf)):
                final cls = c.get();
                final name = cf.get().name;
                if (cls.pack.join(".") == "std" && cls.name == "Process" && name == "exit") {
                    imports.require("kotlin.system.exitProcess");
                }
                if (KotlinTestBinding.isTestExtern(cls)) {
                    if (name == "equals") {
                        final renderedTestArgs = renderCallArgs(args, paramsForCall(fn));
                        final expectedArg = renderedTestArgs[0];
                        final actualArg = renderedTestArgs[1];
                        final msgArg = args.length > 2 ? renderedTestArgs[2] : null;
                        if (isScalarType(args[0].t)) {
                            final runtimePackage = RuntimeConfig.requireImportName("module test extern");
                            state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                            imports.require(runtimePackage + ".test.Test");
                            return "Test.equals(" + expectedArg + ", " + actualArg + (msgArg != null ? ", " + msgArg : "") + ")";
                        } else {
                            recordAggregateType(args[0].t);
                            imports.require("tests.TestHelper");
                            return "TestHelper.assertEquals(" + expectedArg + ", " + actualArg + (msgArg != null ? ", " + msgArg : "") + ")";
                        }
                    }
                }
                if (cls.pack.length == 0 && cls.name == "Math" && name == "isNaN") {
                    return "(" + kotlinMathFloatArg(args[0]) + ").isNaN()";
                }
                if (cls.pack.length == 0 && cls.name == "Math" && name == "isFinite") {
                    return "(" + kotlinMathFloatArg(args[0]) + ").isFinite()";
                }
                if (cls.pack.length == 0 && cls.name == "Std" && name == "int") {
                    // toInt on an Int expression is the identity; the
                    // Kotlin compiler reports the call as redundant.
                    // Haxe types Int/Int division as Float, but Kotlin
                    // renders it as Int division, which already
                    // truncates.
                    if (isIntType(args[0].t)) {
                        return expr(args[0]);
                    }
                    if (isIntDivision(args[0])) {
                        return "(" + expr(args[0]) + ")";
                    }
                    return "(" + expr(args[0]) + ").toInt()";
                }
                if (cls.pack.join(".") == "std" && cls.name == "SortedMap" && name == "builder") {
                    final kType = switch (fn.t) {
                        case TFun(_, TInst(_, params)) if (params.length > 0): params[0];
                        case _: null;
                    };
                    final vType = switch (fn.t) {
                        case TFun(_, TInst(_, params)) if (params.length > 1): params[1];
                        case _: null;
                    };
                    return "SortedTable.mapBuilder<" + types.of(kType) + ", " + types.of(vType) + ">(" + sortedComparator("std.SortedMap", kType, fn.pos) + ")";
                }
                if (cls.module == "runtime.SortedTable" && name == "mapBuilder") {
                    final kType = switch (fn.t) {
                        case TFun(_, TInst(_, params)) if (params.length > 0): params[0];
                        case _: null;
                    };
                    final vType = switch (fn.t) {
                        case TFun(_, TInst(_, params)) if (params.length > 1): params[1];
                        case _: null;
                    };
                    return "SortedTable.mapBuilder<" + types.of(kType) + ", " + types.of(vType) + ">(" + sortedComparator("std.SortedMap", kType, fn.pos) + ")";
                }
                if (cls.pack.join(".") == "std" && cls.name == "SortedSet" && name == "builder") {
                    final kType = switch (fn.t) {
                        case TFun(_, TInst(_, params)) if (params.length > 0): params[0];
                        case _: null;
                    };
                    return "SortedTable.setBuilder<" + types.of(kType) + ">(" + sortedComparator("std.SortedSet", kType, fn.pos) + ")";
                }
                return staticRef(cls, name) + "(" + renderedArgs + ")";
            case TField(subj, FEnum(e, ef)):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                if (owner != null) {
                    imports.requireType(en.pack.concat([owner]).join("."), owner);
                    return owner + "." + ef.name + "(" + renderedArgs + ")";
                }
                imports.requireType(en.module, en.name);
                return isValueEnum(en) ? en.name + "." + ef.name : en.name + "." + ef.name + "(" + renderedArgs + ")";
            case TConst(TSuper):
                return "super(" + renderedArgs + ")";
            case _:
                return expr(fn) + "(" + renderedArgs + ")";
        }
    }

    function renderCallArgs(args:Array<TypedExpr>, params:Array<Type>, owner:Null<ClassType> = null, fieldName:Null<String> = null):Array<String> {
        return [for (i in 0...args.length) renderCallArg(args[i], i, params, owner, fieldName)];
    }

    function renderCallArg(a:TypedExpr, i:Int, params:Array<Type>, owner:Null<ClassType>, fieldName:Null<String>):String {
        final expected = i < params.length ? params[i] : null;
        final registered = owner != null && fieldName != null ? DefaultArgExpander.defaultAt(owner, fieldName, i) : null;
        final wasFunctionTypeExpected = functionTypeExpected;
        functionTypeExpected = PolicyQueries.isFunctionType(expected);
        final text = expr(a);
        functionTypeExpected = wasFunctionTypeExpected;
        if (registered != null && expected != null && isNullLiteral(a)) {
            return defaultArgText(registered, expected);
        } else if (registered != null && expected != null && isNullType(a.t)) {
            return "(" + text + " ?: " + defaultArgText(registered, expected) + ")";
        } else if (expected != null && !isNullType(expected) &&
            ((isNullType(a.t) && !provenNonNull(a) && !guardProofBefore(a)) || (PolicyQueries.isNullableType(a.t) && !provenNonNull(a) && !guardProofBefore(a)) || isNullInitialized(a) || nullableChainHop(a))) {
                addProofExpr(a);
            if (provenNonNull(a) || guardProofBefore(a))
                return text + "!!";
            else
                return text + " ?: throw IllegalArgumentException(\"argument is null\")";
        } else if (isIntOrLongType(emittedType(a)) && isFloatExpectedType(expected)) return intToFloatText(text); else return text;
    }

    /**
        Constructor-call argument renderer. Identical to renderCallArgs except
        that a coalescing default which reads an earlier constructor parameter
        (e.g. `locale = if (kind == Bopomofo) "zh-TW" else null`) resolves the
        read against the argument actually passed for that parameter. The bare
        parameter name is out of scope at the call site.
     */
    function renderConstructorArgs(cls:ClassType, args:Array<TypedExpr>):Array<String> {
        final params = constructorParams(cls);
        return [
            for (i in 0...args.length) {
                final a = args[i];
                final expected = i < params.length ? params[i] : null;
                final registered = DefaultArgExpander.defaultAt(cls, "new", i);
                final wasFunctionTypeExpected = functionTypeExpected;
                functionTypeExpected = PolicyQueries.isFunctionType(expected);
                final text = expr(a);
                functionTypeExpected = wasFunctionTypeExpected;
                if (registered != null && expected != null && isNullLiteral(a)) {
                    constructorDefaultText(registered, expected, cls, args);
                } else if (registered != null && expected != null && isNullType(a.t)) {
                    "(" + text + " ?: " + constructorDefaultText(registered, expected, cls, args) + ")";
                } else if (expected != null && !isNullType(expected) &&
                    ((isNullType(a.t) && !provenNonNull(a) && !guardProofBefore(a)) || (PolicyQueries.isNullableType(a.t) && !provenNonNull(a) && !guardProofBefore(a)) || isNullInitialized(a) || nullableChainHop(a))) {
                        addProofExpr(a);
                    if (provenNonNull(a) || guardProofBefore(a))
                        text + "!!";
                    else
                        text + " ?: throw IllegalArgumentException(\"argument is null\")";
                } else if (isIntOrLongType(emittedType(a)) && isFloatExpectedType(expected)) intToFloatText(text); else text;
            }
        ];
    }

    function isNullLiteral(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TNull): true;
            case _: false;
        };
    }

    function isFloatExpectedType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        final followed = Context.follow(t);
        final base = isNullType(followed) ? switch (followed) {
            case TAbstract(_, params) if (params.length == 1): params[0];
            case _: followed;
        } : followed;
        return switch (Context.follow(base)) {
            case TAbstract(a, _): a.get().name == "Float";
            case _: false;
        };
    }

    function localCallArgs(fn:TypedExpr, args:Array<TypedExpr>):String {
        final target = switch (fn.expr) {
            case TField(_, FInstance(c, _, cf)): {owner: c.get(), field: cf.get().name};
            case TField(_, FStatic(c, cf)): {owner: c.get(), field: cf.get().name};
            default: null;
        };
        final rendered = renderCallArgs(args, paramsForCall(fn), target == null ? null : target.owner, target == null ? null : target.field);
        switch (fn.expr) {
            case TLocal(v) if (currentClass != null && currentField != null):
                final params = switch (Context.follow(fn.t)) {
                    case TFun(values, _): values;
                    case _: [];
                };
                for (i in args.length...params.length) {
                    if (DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentField, v.name, params[i].name) != null) {
                        rendered.push("null");
                    }
                }
            default:
        }
        return rendered.join(", ");
    }

    function paramsForCall(fn:TypedExpr):Array<Type> {
        final fieldParams = switch (fn.expr) {
            case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
                switch (Context.follow(cf.get().type)) {
                    case TFun(values, _): [for (v in values) v.t];
                    case _: [];
                }
            case _: [];
        };
        if (fieldParams.length > 0)
            return fieldParams;
        return switch (Context.follow(fn.t)) {
            case TFun(values, _): [for (v in values) v.t];
            case _: [];
        };
    }

    function constructorParams(cls:ClassType):Array<Type> {
        if (cls.constructor != null)
            return switch (Context.follow(cls.constructor.get().type)) {
                case TFun(values, _): [for (v in values) v.t];
                case _: [];
            };
        if (cls.init != null)
            return switch (Context.follow(cls.init.t)) {
                case TFun(values, _): [for (v in values) v.t];
                case _: [];
            };
        return [];
    }

    function functionLiteralNamed(name:String, f:TFunc):String {
        final previous = currentLocalName;
        currentLocalName = name;
        final result = functionLiteral(f);
        currentLocalName = previous;
        return result;
    }

    function newExpr(c:Ref<ClassType>, params:Array<Type>, args:Array<TypedExpr>):String {
        final cls = c.get();
        final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
        if (valueType != null) {
            if (args.length == 0)
                return valueType.name;
            var argText = expr(args[0]);
            // Haxe unifies Int and Float; widen Int arguments to Float when
            // the value type's representation is Float.
            final emType = emittedType(args[0]);
            final isFloat = ValueTypeSupport.isFloatRepresentation(valueType);
            if (isIntOrLongType(emType) && isFloat)
                argText = intToFloatText(argText);
            return valueType.name + "(" + argText + ")";
        }
        final renderedArgsText = renderConstructorArgs(cls, args).join(", ");
        final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
        switch (path) {
            case "std.StringBuf" | "StringBuf":
                return "StringBuilder()";
            case "haxe.ds._Map.Map_Impl_":
                return "mutableMapOf()";
            case "haxe.io.BytesBuffer":
                imports.requireType(path, "BytesBuffer");
                return "BytesBuffer(" + renderedArgsText + ")";
            case "Array":
                // The declared Kotlin type for Haxe Array is MutableList<T>;
                // a zero-arg construction must also be MutableList so later
                // assignments of MutableList results type-check. Sized
                // construction (new Array(n)) keeps ArrayList, which is the
                // only Kotlin shape carrying an initial capacity.
                if (args.length == 0)
                    return "mutableListOf<" + types.of(params[0]) + ">()";
                imports.require("java.util.ArrayList");
                return "ArrayList<" + types.of(params[0]) + ">(" + renderedArgsText + ")";
            case _:
                if (args.length == 1 && state.exceptionPayloads.exists(cls.module)) {
                    return exceptionVariant(cls, args[0]);
                }
                imports.requireType(cls.module, cls.name);
                return cls.name + "(" + renderedArgsText + ")";
        }
    }

    function isMapType(t:Type):Bool {
        return PolicyQueries.isMapType(t);
    }

    function isMapImplementation(cls:ClassType):Bool {
        return PolicyQueries.isMapImplementation(cls);
    }

    function mapBackingReceiver(e:TypedExpr):Null<TypedExpr> {
        return PolicyQueries.mapBackingReceiver(e);
    }

    function isMapBackingType(t:Type):Bool {
        return PolicyQueries.isMapBackingType(t);
    }

    function mapAssignment(e:TypedExpr):Null<{receiver:TypedExpr, key:TypedExpr}> {
        return PolicyQueries.mapAssignment(e);
    }

    function isHasOwnPropertyValue(e:TypedExpr):Bool {
        return PolicyQueries.isHasOwnPropertyValue(e);
    }

    function mapHasOwnPropertyCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        if (args.length != 2)
            return null;
        return switch (stripWrap(fn).expr) {
            case TField(subject, FInstance(_, _, cf)) if (cf.get().name == "call" && isHasOwnPropertyValue(subject)):
                final receiver = mapBackingReceiver(args[0]);
                receiver == null ? null : expr(receiver)
                + ".containsKey("
                + expr(args[1])
                + ")";
            case _: null;
        };
    }

    function assignTarget(e:TypedExpr):String {
        return AssignTargetPlan.assignTarget(e, (arr, idx) -> expr(arr) + "[" + expr(idx) + "]", e -> switch (e.expr) {
            case TField(_, FStatic(c, cf)): staticRef(c.get(), cf.get().name);
            case _: fail(e, "assignment target has no Kotlin lowering");
        }, (subj, kind, _) -> switch (kind) {
            case Instance(_, cf) | Anonymous(cf): expr(subj) + "." + KotlinNameEscape.escape(cf.get().name);
        }, v -> localName(v),
            (e, _) -> fail(e, "assignment target has no Kotlin lowering: " + Std.string(e.expr)));
    }

    function objectLiteral(e:TypedExpr, fields:Array<{name:String, expr:TypedExpr}>):String {
        final typeName = resolveTypeName(e.t);
        final parts = [for (f in fields) f.name + " = " + expr(f.expr)];
        return typeName + "(" + parts.join(", ") + ")";
    }

    function resolveTypeName(t:Type):String {
        return switch (t) {
            case TType(def, _):
                final d = def.get();
                imports.requireType(d.module, d.name);
                d.name;
            case TAnonymous(anon):
                final match = state.structTypedefs.get(KotlinDecl.structureSignature(anon));
                if (match == null) {
                    Context.error("anonymous structure literal has no matching named typedef", Context.currentPos());
                    null;
                } else {
                    imports.requireType(match.module, match.name);
                    match.name;
                }
            case _:
                Context.error("object literal must be typed by a named typedef before translation", Context.currentPos());
                null;
        }
    }

    // ------------------------------------------------------------------
    // Local analysis
    // ------------------------------------------------------------------

    function scanLocals(e:TypedExpr):Void {
        switch (e.expr) {
            case TVar(v, init):
                PolicyQueries.noteDeclaredLocalName(v, usedNames, true);
                PolicyQueries.noteFpInt64Init(v, init, fpInt64Halves);
            case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
                switch (t.expr) {
                    case TLocal(v): mutated.set(v.id, true);
                    case TArray(arr, _):
                        switch (stripWrap(arr).expr) {
                            case TLocal(v): mutableArrayLocals.set(v.id, true);
                            case _: 
                        }
                    case _:
                }
            // An increment or decrement reassigns the local, so the
            // declaration needs var even without a plain assignment.
            case TUnop(OpIncrement, _, t) | TUnop(OpDecrement, _, t):
                switch (t.expr) {
                    case TLocal(v): mutated.set(v.id, true);
                    case _:
                }
            case _:
        }
        TypedExprTools.iter(e, scanLocals);
    }

    function mentionsLocal(e:TypedExpr, v:TVar):Bool {
        return PolicyQueries.mentionsLocal(e, v);
    }

    public function localName(v:TVar):String {
        // Kotlin gates a `_` local behind the experimental
        // UnnamedLocalVariables flag. Haxe treats `_` as a readable
        // identifier, so it goes through the same generated-name path
        // as the compiler's ` temporaries.
        if (localNames.exists(v.id)) {
            return localNames.get(v.id);
        }
        if (v.name != "`" && !~/^_+$/.match(v.name)) {
            var name = KotlinNameEscape.escape(v.name);
            if (emittedLocalNames.exists(name) && emittedLocalNames.get(name) != v.id) {
                var suffix = 2;
                final base = name;
                while (emittedLocalNames.exists(name)) {
                    name = base + "_" + suffix;
                    suffix += 1;
                }
            }
            localNames.set(v.id, name);
            emittedLocalNames.set(name, v.id);
            return name;
        }
        if (hiddenNames.exists(v.id)) {
            return hiddenNames.get(v.id);
        }
        final candidates = ["i", "j", "k", "n", "m", "index", "write", "read"];
        final taken:Map<String, Bool> = [];
        for (name in hiddenNames)
            taken.set(name, true);
        for (c in candidates) {
            if (!usedNames.exists(c) && !taken.exists(c)) {
                hiddenNames.set(v.id, c);
                localNames.set(v.id, c);
                emittedLocalNames.set(c, v.id);
                return c;
            }
        }
        hiddenCounter += 1;
        final generated = "t" + hiddenCounter;
        hiddenNames.set(v.id, generated);
        localNames.set(v.id, generated);
        emittedLocalNames.set(generated, v.id);
        return generated;
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    function symbolOf(op:Binop):String {
        return switch (op) {
            case OpAdd: "+";
            case OpMult: "*";
            case OpDiv: "/";
            case OpSub: "-";
            case OpEq: "==";
            case OpNotEq: "!=";
            case OpGt: ">";
            case OpGte: ">=";
            case OpLt: "<";
            case OpLte: "<=";
            case OpBoolAnd: "&&";
            case OpBoolOr: "||";
            case OpMod: "%";
            case _: fail(null, "operator symbol has no Kotlin lowering: " + Std.string(op));
        }
    }

    function precedenceOf(op:Binop):Int {
        return switch (op) {
            case OpBoolOr: 1;
            case OpBoolAnd: 2;
            case OpOr | OpXor | OpAnd: 3;
            case OpEq | OpNotEq: 4;
            case OpLt | OpLte | OpGt | OpGte: 5;
            case OpShl | OpShr | OpUShr: 6;
            case OpAdd | OpSub: 7;
            case OpMult | OpDiv | OpMod: 8;
            case _: 0;
        }
    }

    function associative(op:Binop):Bool {
        return switch (op) {
            case OpBoolAnd | OpBoolOr | OpAdd | OpMult: true;
            case _: false;
        }
    }

    function fieldName(fa:FieldAccess):String {
        return switch (fa) {
            case FInstance(_, _, cf): cf.get().name;
            case FStatic(_, cf): cf.get().name;
            case FAnon(cf): cf.get().name;
            case FDynamic(n): n;
            case FClosure(_, cf): cf.get().name;
            case FEnum(_, ef): ef.name;
        }
    }

    /** The declared argument name of an enum constructor's payload. */
    public function payloadName(ef:EnumField, index:Int):String {
        return switch (ef.type) {
            case TFun(args, _) if (index < args.length): args[index].name;
            case _: "v" + index;
        }
    }

    function isBytes(e:TypedExpr):Bool {
        return switch (e.t) {
            case TInst(c, _): final cls = c.get(); cls.pack.join(".") == "haxe.io" && cls.name == "Bytes";
            case _: false;
        }
    }

    function isString(e:TypedExpr):Bool {
        return switch (e.t) {
            case TInst(c, _): final cls = c.get(); cls.pack.join(".") == "" && cls.name == "String";
            case _: false;
        }
    }

    /** True when the expression's type is `Null<String>` (or `String`). */
    function isNullStringReceiver(e:TypedExpr):Bool {
        return switch (Context.follow(e.t)) {
            case TInst(c, _): final cls = c.get(); cls.pack.join(".") == "" && cls.name == "String";
            case _: false;
        }
    }

    function unwrapLambda(e:TypedExpr):Null<TFunc> {
        return PolicyQueries.unwrapLambda(e);
    }

    function lambdaBody(e:TypedExpr):TypedExpr {
        return PolicyQueries.lambdaBody(e);
    }

    function stripCast(e:TypedExpr):TypedExpr {
        return ExpressionPredicates.stripCast(e);
    }

    function stripWrap(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripWrap(inner);
            case _: e;
        }
    }

    function quoteString(s:String):String {
        final b = new StringBuf();
        b.addChar('"'.code);
        for (i in 0...s.length) {
            switch (s.charCodeAt(i)) {
                case 34:
                    b.add('\\"');
                case 92:
                    b.add('\\\\');
                case 10:
                    b.add('\\n');
                case 13:
                    b.add('\\r');
                case 9:
                    b.add('\\t');
                case 36:
                    b.add('\\$');
                case c:
                    b.addChar(c);
            }
        }
        b.addChar('"'.code);
        return b.toString();
    }

    function indent(depth:Int):String {
        final b = new StringBuf();
        for (i in 0...depth) {
            b.add("    ");
        }
        return b.toString();
    }

    function isScalarType(t:Type):Bool {
        final followed = Context.follow(t);
        return switch (followed) {
            case TAbstract(a, _): final name = a.get().name; name == "Bool" || name == "Int" || name == "Float";
            case TInst(c, _):
                c.get().name == "String";
            case _: false;
        };
    }

    function kotlinMathFloatArg(a:TypedExpr):String {
        if (!isIntOrLongType(a.t))
            return expr(a);
        return intToFloatText(expr(a));
    }

    function isIntType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Int";
            case _: false;
        };
    }

    /** Whether the type is a 32-bit or 64-bit integer (Int or haxe.Int64),
        unwrapping Null<T> to inspect the inner type. */
    public function isIntOrLongType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        final followed = Context.follow(t);
        final base = isNullType(followed) ? switch (followed) {
            case TAbstract(_, params) if (params.length == 1): params[0];
            case _: followed;
        } : followed;
        return switch (Context.follow(base)) {
            case TAbstract(a, _): final n = a.get().name; n == "Int" || n == "Int64";
            case _: false;
        };
    }

    /** Whether the type is Float (the unified Haxe Float abstract),
        unwrapping Null<T> to inspect the inner type. */
    public function isFloatType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        final followed = Context.follow(t);
        final base = isNullType(followed) ? switch (followed) {
            case TAbstract(_, params) if (params.length == 1): params[0];
            case _: followed;
        } : followed;
        return switch (Context.follow(base)) {
            case TAbstract(a, _): a.get().name == "Float";
            case _: false;
        };
    }

    /** Convert an integer expression text to Float/Double when the target expects Float. */
    function intToFloatText(text:String):String {
        return "(" + text + ")." + (FloatPrecision.isF32() ? "toFloat()" : "toDouble()");
    }

    /** Emit an integer literal as a Float/Double literal for const val initializers,
        where (x).toDouble() is not a compile-time constant. */
    public function constValFloatLiteral(text:String):String {
        return text + (FloatPrecision.isF32() ? ".0f" : ".0");
    }

    /**
        The "emitted" type of an expression: the type of the value the
        generator will actually emit as text. For most expressions this is
        the same as the typed AST type, but Haxe unification types Int-as-Float
        contexts (return positions, comparisons, arithmetic) as Float while the
        generator still emits Int text for the original Int sub-expression.
        This walks the expression to find the type the generated text carries.
     */
    function emittedType(e:TypedExpr):Null<Type> {
        switch (stripWrap(e).expr) {
            case TConst(TInt(_)):
                // An Int literal always emits Int text, even when the typer
                // types it as Float due to unification. Tag it with the Int
                // type so callers can widen it to Float.
                return Context.getType("Int");
            case TIf(_, t, f):
                final tt = emittedType(t);
                return tt != null ? tt : emittedType(f);
            case TBinop(op, l, r):
                switch (op) {
                    case OpAdd | OpSub | OpMult | OpDiv | OpMod:
                        final lt = emittedType(l);
                        if (lt != null && isIntOrLongType(lt))
                            return lt;
                        return emittedType(r);
                    case OpEq | OpNotEq | OpGt | OpGte | OpLt | OpLte:
                        final lt = emittedType(l);
                        if (lt != null)
                            return lt;
                        return emittedType(r);
                    case _:
                }
            case TLocal(v):
                return e.t;
            case TField(_, _):
                return e.t;
            case TCall(_, _):
                return e.t;
            case TParenthesis(inner):
                return emittedType(inner);
            case TCast(inner, _):
                return emittedType(inner);
            case _:
        }
        return e.t;
    }

    /** Whether both operands of a division carry Int, so Kotlin
        renders it as truncating Int division. */
    function isIntDivision(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TBinop(OpDiv, l, r): isIntType(l.t) && isIntType(r.t);
            case _: false;
        };
    }

    function isStringBuf(e:TypedExpr):Bool {
        return PolicyQueries.isStringBuf(e);
    }

    function recordAggregateType(t:Type):Void {
        switch (t) {
            case TInst(c, params) if (c.get().name == "Array"):
                final key = "Array_" + formatTypeKey(params[0]);
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
                    recordAggregateType(params[0]);
                }
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray"
                || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
                final key = "Array_" + formatTypeKey(params[0]);
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
                    recordAggregateType(params[0]);
                }
            case TType(def, params):
                final d = def.get();
                final key = d.module + "." + d.name;
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
                    switch (d.type) {
                        case TAnonymous(anon):
                            for (f in anon.get().fields) {
                                recordAggregateType(f.type);
                            }
                        case _:
                    }
                }
            case TEnum(e, params):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                final typeName = owner != null ? en.pack.concat([owner]).join(".") : en.module + "." + en.name;
                final key = typeName;
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
                    for (ef in en.constructs) {
                        switch (Context.follow(ef.type)) {
                            case TFun(args, _):
                                for (a in args)
                                    recordAggregateType(a.t);
                            case _:
                        }
                    }
                }
            case _:
        }
    }

    function formatTypeKey(t:Type):String {
        return switch (t) {
            case TAbstract(a, params):
                if (a.get().name == "ReadOnlyArray" || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")) "Array_"
                    + formatTypeKey(params[0]) else a.get().name;
            case TInst(c, params):
                final cls = c.get();
                if (cls.name == "Array") "Array_" + formatTypeKey(params[0]); else if (cls.name == "Bytes"
                    || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) "Bytes"; else cls.module + "." + cls.name;
            case TType(def, params): def.get().module + "." + def.get().name;
            case TEnum(e, params):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                owner != null ? en.pack.concat([owner]).join(".") : en.module + "." + en.name;
            case _: "Unknown";
        };
    }

    /**
        The comparator a sorted builder binds at creation, per key domain
        (stdlib/07): integers take the resident comparator reference,
        strings compare with the platform operator (the ruled UTF-16
        code-unit order), structures take the per-type generated
        comparison. The explicit type arguments at the call site make the
        reference and lambda parameter types resolve.
    **/
    function sortedComparator(externModule:String, kType:Null<Type>, pos:haxe.macro.Expr.Position):String {
        if (kType == null) {
            Context.error("sorted builder requires an explicit key type", pos);
        }
        imports.requireType(externModule, "SortedTable");
        return switch (KotlinType.classifyKey(kType, pos)) {
            case IntKey: "SortedTable::compareInts";
            case StringKey: "SortedTable::compareStrings";
            case StructKey(def, _):
                imports.requireType(def.module, "compare");
                "::compare";
            case DataClassKey(cls, _):
                imports.requireType(cls.module, "compare" + cls.name);
                "::compare" + cls.name;
            case EnumKey(en): "{ a, b -> a.ordinal - b.ordinal }";
        };
    }

    function fail(e:Null<TypedExpr>, message:String):Dynamic {
        final pos = e != null ? e.pos : Context.currentPos();
        Context.error("kotlin target: " + message, pos);
        return null;
    }

    // ------------------------------------------------------------------
    // Platform modules (docs/specs/stdlib/17-platform-modules.md)
    // ------------------------------------------------------------------

    /**
        A std.Fs static call (stdlib/17). The java.nio.file calls lower
        inline at the call site; no runtime module implements std.Fs. Host
        failures raise the native exception, which the target's exception
        mapping carries.

        A NodeFileSystem extern static call (the consumer test harness's
        node:fs binding). The Kotlin/JVM target has no node runtime, so the
        two members lower to java.nio.file calls: mkdirSync creates the
        directory tree and writeFileSync writes UTF-8 text.
    **/
    function nodeFsCall(name:String, args:Array<TypedExpr>, fn:TypedExpr):String {
        imports.require("java.nio.file.Files");
        imports.require("java.nio.file.Paths");
        return switch (name) {
            case "mkdirSync":
                "Files.createDirectories(Paths.get(" + expr(args[0]) + "))";
            case "writeFileSync":
                "Files.writeString(Paths.get(" + expr(args[0]) + "), " + expr(args[1]) + ", Charsets.UTF_8)";
            case _:
                Context.error("NodeFileSystem has no lowering for member " + name, fn.pos);
                "null";
        }
    }

    function fsCall(name:String, args:Array<TypedExpr>, fn:TypedExpr):String {
        imports.require("java.nio.file.Files");
        imports.require("java.nio.file.Paths");
        final p = expr(args[0]);
        return switch (name) {
            case "exists":
                "Files.exists(Paths.get(" + p + "))";
            case "readText":
                "Files.readString(Paths.get(" + p + "))";
            case "writeText":
                "Files.writeString(Paths.get(" + p + "), " + expr(args[1]) + ")";
            case "appendText":
                imports.require("java.nio.file.StandardOpenOption");
                "Files.writeString(Paths.get("
                + p
                + "), "
                + expr(args[1])
                + ", StandardOpenOption.CREATE, StandardOpenOption.APPEND)";
            case "makeDirs":
                "Files.createDirectories(Paths.get(" + p + "))";
            case "readDir":
                "Files.newDirectoryStream(Paths.get(" + p + ")).use { s -> s.map { it.fileName.toString() }.toMutableList() }";
            case "isDirectory":
                "Files.isDirectory(Paths.get(" + p + "))";
            case _:
                Context.error("std.Fs has no lowering for member " + name, fn.pos);
                "null";
        }
    }

    /**
        A std.Env static call (stdlib/17). The JVM exposes the process
        environment read-only, so get, set, and remove route through the
        process-local overlay shim, which records writes and falls back to
        the host for keys it has never seen.
    **/
    function envCall(name:String, args:Array<TypedExpr>, fn:TypedExpr):String {
        final runtimePackage = RuntimeConfig.requireImportName("module std.Env");
        state.shimsUsed.set("std.Env", true);
        imports.require(runtimePackage + ".Env");
        return switch (name) {
            case "get":
                "Env.get(" + expr(args[0]) + ")";
            case "set":
                "Env.set(" + expr(args[0]) + ", " + expr(args[1]) + ")";
            case "remove":
                "Env.remove(" + expr(args[0]) + ")";
            case _:
                Context.error("std.Env has no lowering for member " + name, fn.pos);
                "null";
        }
    }

    /** std.Process.args() reads the arguments the test entry stored (stdlib/17). */
    function processArgs(fn:TypedExpr):String {
        final runtimePackage = RuntimeConfig.requireImportName("module std.Process");
        state.shimsUsed.set("std.Process", true);
        imports.require(runtimePackage + ".Process");
        state.processArgsReferenced = true;
        return "Process.args()";
    }
}
#end
