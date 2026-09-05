package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.FieldAccess;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import TerminationAnalysis;
import ValueTypeSupport;
import ValueTypeSupport.ValueTypeOperator;

/**
    Statement and expression lowering from the Haxe typed AST to Rust.
**/
class RustExpr {
    // Runtime shim parameters that take i32 where the haxe declaration
    // says Int. slice clamps with bounds that may be negative, so its
    // bound parameters are signed in the Rust runtime; the compiler
    // cannot read a Rust signature, so the signed positions are listed
    // here and the call sites cast into them. Resident runtime modules
    // take their signed positions from the resident ABI rule at every
    // call, so they carry no entry here.
    static final SIGNED_SHIM_PARAMS:Map<String, Array<Int>> = ["u_string.slice" => [1, 2]];

    final imports:RustImports;
    final types:RustType;
    final state:RustEmissionState;

    var isFallible:Bool = false;
    var countOverflowVariant:Null<String> = null;
    var errorTypeName:Null<String> = null;
    var returnUnsigned:Bool = false;
    var returnTypeName:Null<String> = null;
    var currentReturnType:Null<Type> = null;
    var inTryClosure:Bool = false;

    final subst:Map<Int, String> = [];

    /** Catch variables of the region being lowered; features/06 catch-site lowering. */
    final catchVars:Map<Int, Bool> = [];

    // Locals declared outside a try closure need mutable, initialized storage
    // when the closure assigns them.
    final tryCapturedAssignments:Map<Int, Bool> = [];
    final mutated:Map<Int, Bool> = [];
    final deferredLocals:Map<Int, Bool> = [];
    final usedNames:Map<String, Bool> = [];

    /** Active runtime renderers for cyclic enum stringification. */
    final enumStringHelpers:Map<String, String> = [];

    var enumStringHelperCounter:Int = 0;

    final hiddenNames:Map<Int, String> = [];
    final rangeLoopVars:Map<Int, Bool> = [];
    final argTypes:Map<String, String> = [];
    final paramVarIds:Map<Int, Bool> = [];
    final genericParamIds:Map<Int, Bool> = [];
    final closureParamIds:Map<Int, Bool> = [];
    var inGenericFunction:Bool = false;
    final borrowedLoopVarIds:Map<Int, Bool> = [];
    final provenNonNullVarIds:Map<Int, Bool> = [];
    final readsAfterDeclaration:Map<Int, Bool> = [];
    final unsignedLocals:Map<Int, Bool> = [];
    // Locals initialized from charCodeAt are collapsed from Option<u32> to a scalar.
    final nullableCollapsedLocals:Map<Int, Bool> = [];
    // String.indexOf lowers to an expression that always yields i32; a local
    // initialized from it keeps that domain even where Int maps to u32.
    final i32Locals:Map<Int, Bool> = [];
    // True while rendering the initializer of an i32-domain local, so the
    // wrapping arithmetic in it picks the i32 domain and the binding infers
    // i32; wrapping arithmetic is bit-identical on both domains, so the
    // choice is safe anywhere inside the initializer.
    var i32ComparisonTarget = false;
    var i32InitializerTarget = false;
    // Downward loops the renderer shifts to an unsigned guard
    // (transformCountdownLoops): their variable keeps the u32 domain.
    final countdownShiftedVars:Map<Int, Bool> = [];
    // Keep Option when Haxe code observes null separately from code point zero.
    final nullableSensitiveLocals:Map<Int, Bool> = [];
    final fpInt64Halves:Map<Int, Bool> = [];
    var hiddenCounter:Int = 0;

    public function new(imports:RustImports, types:RustType, state:RustEmissionState) {
        this.imports = imports;
        this.types = types;
        this.state = state;
    }

    public function setArgType(name:String, typeName:String):Void {
        argTypes.set(name, typeName);
    }

    public function setReturnUnsigned(value:Bool):Void {
        this.returnUnsigned = value;
    }

    public function setReturnTypeName(value:Null<String>):Void {
        this.returnTypeName = value;
    }

    public function setReturnType(value:Null<Type>):Void {
        this.currentReturnType = value;
    }

    public function reserveName(name:String):Void {
        usedNames.set(name, true);
    }

    public function bindLocalName(v:TVar, name:String):Void {
        subst.set(v.id, name);
    }

    public function boundNameOf(v:TVar):Null<String> {
        return subst.get(v.id);
    }

    public function setFallible(value:Bool, errorType:Null<String> = null, overflowVariant:Null<String> = null):Void {
        this.isFallible = value;
        this.errorTypeName = errorType != null ? errorType : state.errorName;
        // The overflow variant belongs to the resolved error enum; a function
        // owned by an enum without it reports the gap at the first capacity
        // expression that copies the foreign variant here.
        this.countOverflowVariant = overflowVariant;
        if (value && this.errorTypeName == null) {
            Context.error("fallible operation requires an error enum, but none found in AST", Context.currentPos());
        }
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

    public function rawArrayLiteral(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TArrayDecl(elements): "[" + [for (x in elements) expr(x)].join(", ") + "]";
            case _: rawExpression(e);
        };
    }

    /** Renders the literal itself for a Rust static function pointer initializer. */
    public function rawFunctionInitializer(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TFunction(f): functionLiteral(f, e.t);
            case _: fail(e, "static function fields accept capture-free initializers only");
        }
    }

    // ------------------------------------------------------------------
    // Function bodies
    // ------------------------------------------------------------------
    var currentMethodName:Null<String> = null;
    var currentClass:Null<ClassType> = null;
    var currentLocalName:Null<String> = null;

    function coalescingSiteFor(e:TypedExpr):Null<{parameter:String, defaultExpr:TypedExpr, valueExpr:TypedExpr}> {
        if (currentClass == null || currentMethodName == null)
            return null;
        final site = DefaultArgExpander.coalescingSite(e);
        final value = currentLocalName != null ? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentMethodName, currentLocalName,
            site == null ? "" : site.parameter) : DefaultArgExpander.coalescingDefaultForParam(currentClass, currentMethodName,
                site == null ? "" : site.parameter);
        if (site == null)
            return null;
        if (value == null)
            return null;
        return site;
    }

    /** Renders the sanctioned expression in Rust's normalization closure. */
    function coalescingDefaultText(value:DefaultArgExpander.CoalescingDefaultValue, targetType:Type, asOption:Bool = false, nested:Bool = false):String {
        // Null conditionals already produce an Option-valued expression; their
        // branches must be rendered in that same domain. The whole conditional is not
        // wrapped in Some(...).
        if (asOption)
            switch (value) {
                case CNull:
                    return "None";
                case CConditional(c, t, f):
                    return "if " + coalescingDefaultText(c, targetType, false, nested) + " { " + coalescingDefaultText(t, targetType, true, nested)
                        + " } else { " + coalescingDefaultText(f, targetType, true, nested) + " }";
                default:
            }
        final rendered = switch (value) {
            case CInt(v): Std.string(v);
            case CFloat(s):
                final padded = s.indexOf(".") >= 0 || s.indexOf("e") >= 0 || s.indexOf("E") >= 0 ? s : s + ".0";
                FloatPrecision.isF32() ? padded + "f32" : padded;
            case CString(s): quoteString(s) + (nested ? "" : ".to_string()");
            case CBool(b): b ? "true" : "false";
            case CNull: "None";
            case CEmptyArray: "vec![]";
            case CEmptyMap:
                imports.require("std::collections::HashMap");
                "HashMap::new()";
            case CPositiveInfinity: FloatPrecision.isF32() ? "f32::INFINITY" : "f64::INFINITY";
            case CNegativeInfinity: FloatPrecision.isF32() ? "f32::NEG_INFINITY" : "f64::NEG_INFINITY";
            case CEnum(enumRef, enumField):
                final en = enumRef.get();
                requireEnum(en.module, en.name);
                en.name + "::" + enumField.name;
            case CParameterRead(name): RustImports.toSnakeCase(name);
            case CInstanceFieldRead(name):
                final fieldText = "self." + RustImports.toSnakeCase(name);
                isTypeCopy(targetType) ? fieldText : "(" + fieldText + ").clone()";
            case CLocalRead(name): RustImports.toSnakeCase(name);
            case CFieldAccess(CParameterRead(staticPath), ""): coalescingStaticFieldText(staticPath, targetType);
            case CFieldAccess(receiver, fieldName):
                fieldName == "length" ? rustU32Length("(" + coalescingDefaultText(receiver,
                    targetType) + ").len()") : coalescingDefaultText(receiver, targetType) + "." + RustImports.toSnakeCase(fieldName);
            case CMethodCall(receiver, methodName, args):
                coalescingDefaultText(receiver, targetType)
                + "."
                + rustMethodName(methodName)
                + "("
                + [for (a in args) coalescingDefaultText(a, targetType)].join(", ") + ")";
            case CStaticCall(fullPath, args):
                coalescingStaticCallText(fullPath, args, targetType);
            case CConditional(c, t, f):
                "if "
                + coalescingDefaultText(c, targetType)
                + " { "
                + coalescingDefaultText(t, targetType)
                + " } else { "
                + coalescingDefaultText(f, targetType)
                + " }";
            case CBinaryOp(op, left, right):
                coalescingDefaultText(left, targetType)
                + " "
                + opStr(op)
                + " "
                + coalescingDefaultText(right, targetType);
            case CConstructorCall(classPath, args):
                // Constructor parameters render in reference form (a String
                // parameter is &str), so nested string literal arguments stay
                // bare; only the top-level default needs the owned form.
                classPath.split(".").pop() + "::new(" + [for (a in args) coalescingDefaultText(a, targetType, false, true)].join(", ") + ")";
        };
        return asOption ? "Some(" + rendered + ")" : rendered;
    }

    function coalescingStaticCallText(path:String, args:Array<DefaultArgExpander.CoalescingDefaultValue>, targetType:Type):String {
        final rendered = [for (a in args) coalescingDefaultText(a, targetType)].join(", ");
        if (path == "std.SortedSet.builder") {
            imports.requireType("runtime.SortedTable", "SortedTable");
            return "SortedTable::set_builder(" + rendered + ")";
        }
        final parts = path.split(".");
        return parts.length > 1 ? parts[0] + "::" + RustImports.toSnakeCase(parts[1]) + "(" + rendered + ")" : RustImports.toSnakeCase(path)
            + "("
            + rendered
            + ")";
    }

    function coalescingStaticFieldText(path:String, targetType:Type):String {
        final parts = path.split(".");
        if (parts.length < 2)
            return path;
        final fieldName = parts[parts.length - 1];
        final typePath = parts.slice(0, parts.length - 1).join(".");
        try {
            switch (Context.getType(typePath)) {
                case TInst(clsRef, _):
                    final rendered = staticRef(clsRef.get(), fieldName);
                    return isStringType(targetType)
                        && !StringTools.endsWith(rendered, ".to_string()") ? rendered + ".to_string()" : rendered;
                default:
            }
        } catch (_:Dynamic) {}
        return path;
    }

    static function rustMethodName(name:String):String {
        return name == "toUpperCase" ? "to_uppercase" : RustImports.toSnakeCase(name);
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
            case OpShl: "<<";
            case OpShr: ">>";
            case OpUShr: ">>";
            case OpXor: "^";
            case _: "?";
        };
    }

    public function functionBody(cls:ClassType, f:ClassFuncData):Array<String> {
        if (f.expr == null) {
            Context.error("function field has no body to lower", f.field.pos);
        }
        DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentMethodName = f.field.name;
        currentLocalName = null;
        paramVarIds.clear();
        borrowedLoopVarIds.clear();
        unsignedLocals.clear();
        nullableCollapsedLocals.clear();
        nullableSensitiveLocals.clear();
        i32Locals.clear();
        countdownShiftedVars.clear();
        mutated.clear();
        deferredLocals.clear();
        for (a in f.args) {
            if (a.tvar != null)
                paramVarIds.set(a.tvar.id, true);
        }
        // Fuse declaration-plus-assignment pairs before the mutation scan.
        // The typer lowers abstract-inline receiver bindings as `TVar(v,
        // null)` followed by an assignment; the fused initializer is the
        // declaration's own initialization, so the scan must not read it as
        // a reassignment.
        final fusedRoot = fuseWithin(f.expr);
        f.expr.expr = fusedRoot.expr;
        scanLocals(f.expr);
        scanReadsAfter(f.expr);
        final lines = blockLines(statementsOf(f.expr), 1, true);
        return coalescingNormalizationLines(f.expr, 1, [for (a in f.args) a.name]).concat(lines);
    }

    /** Body lowering for a member declared on a value wrapper. */
    public function valueTypeFunctionBody(cls:ClassType, f:ClassFuncData, receiverName:String):Array<String> {
        final abs = ValueTypeSupport.markedAbstractOfClass(cls);
        final op = abs == null ? null : ValueTypeSupport.operatorOf(abs, f.field);
        if (op != null) {
            switch (op) {
                case Binary(_):
                    if (f.args.length > 0)
                        bindLocalName(f.args[0].tvar, "self.0");
                    if (f.args.length > 1)
                        bindLocalName(f.args[1].tvar, "rhs.0");
                case Unary(_):
                    if (f.args.length > 0)
                        bindLocalName(f.args[0].tvar, "self.0");
            }
        } else if (ValueTypeSupport.hasReceiver(f.field) && f.args.length > 0) {
            bindLocalName(f.args[0].tvar, receiverName);
        }
        final rawReturn = types.of(f.ret, false);
        setReturnUnsigned(rawReturn == "u32");
        setReturnTypeName(rawReturn);
        return functionBody(cls, f);
    }

    /** Drops Haxe's synthetic representation assignment from a validating constructor. */
    public function valueTypeConstructorBody(cls:ClassType, f:ClassFuncData):Array<String> {
        if (f.expr == null)
            Context.error("value type constructor has no body to lower", f.field.pos);
        DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentMethodName = f.field.name;
        currentLocalName = null;
        paramVarIds.clear();
        unsignedLocals.clear();
        mutated.clear();
        for (a in f.args)
            if (a.tvar != null)
                paramVarIds.set(a.tvar.id, true);
        scanLocals(f.expr);
        final out:Array<String> = [];
        for (stmt in statementsOf(f.expr)) {
            if (ValueTypeSupport.isThisDeclaration(stmt) || ValueTypeSupport.isThisAssignment(stmt) || ValueTypeSupport.isThisReturn(stmt))
                continue;
            for (line in stmtLines(stmt, 1))
                out.push(line);
        }
        return out;
    }

    /**
        Constructor body classification (feature spec 27): a `this.f = f`
        assignment of a constructor parameter is the struct-literal
        shorthand and drops out; an assignment to a field the constructor
        does not receive as a parameter is that field's initialization in
        the literal; every other statement keeps statement form and
        renders before the literal, so constructor validation survives on
        this target.
    **/
    public function constructorBody(cls:ClassType, f:ClassFuncData):{statementLines:Array<String>, fieldInits:Map<String, String>} {
        if (f.expr == null) {
            Context.error("constructor has no body to lower", f.field.pos);
        }
        DefaultArgExpander.completeRootExprForRust(cls, f.field.name, f.expr);
        PipelineExpander.expandRootExpr(f.expr);
        EnumQueryExpander.expandRootExpr(f.expr);
        currentClass = cls;
        currentMethodName = f.field.name;
        currentLocalName = null;
        paramVarIds.clear();
        unsignedLocals.clear();
        mutated.clear();
        for (a in f.args) {
            if (a.tvar != null)
                paramVarIds.set(a.tvar.id, true);
        }
        final fusedRoot = fuseWithin(f.expr);
        f.expr.expr = fusedRoot.expr;
        scanLocals(f.expr);
        final argNames = [for (a in f.args) a.name];
        final fieldInits = new Map<String, String>();
        final stmts:Array<TypedExpr> = [];
        for (stmt in statementsOf(f.expr)) {
            switch (stmt.expr) {
                case TBinop(OpAssign, target, value):
                    switch (stripWrap(target).expr) {
                        case TField({expr: TConst(TThis)}, FInstance(_, _, cf)):
                            final fieldName = cf.get().name;
                            final coalescing = coalescingSiteFor(value);
                            if (coalescing != null) {
                                continue;
                            }
                            final isParam = switch (stripWrap(value).expr) {
                                case TLocal(v): argNames.indexOf(v.name) >= 0;
                                case _: false;
                            };
                            // The parameter name is a local binding. It is not necessarily the
                            // target field name (Haxe permits constructor shorthand such
                            // as `owner = o`). Preserve the typed field assignment so the
                            // declaration pass can emit the real Rust field name.
                            fieldInits.set(fieldName, renderValueForType(cf.get().type, value, expr(value)));
                        case _:
                            stmts.push(stmt);
                    }
                case _:
                    stmts.push(stmt);
            }
        }
        // tailScope stays off: the constructor's tail is the Ok(Self { ... })
        // literal assembled by the caller, so blockLines must not append the
        // fallible void closer `Ok(())` after the validation statements.
        final lines = stmts.length > 0 ? blockLines(stmts, 1, false) : [];
        final normalized = coalescingNormalizationLines(f.expr, 1, [for (a in f.args) a.name]);
        return {statementLines: normalized.concat(lines), fieldInits: fieldInits};
    }

    function coalescingNormalizationLines(root:TypedExpr, depth:Int, parameterOrder:Null<Array<String>> = null):Array<String> {
        final out:Array<String> = [];
        if (currentClass == null || currentMethodName == null)
            return out;
        final sites = DefaultArgExpander.coalescingSitesForFunction(root);
        if (parameterOrder != null) {
            var next = 0;
            for (parameterName in parameterOrder) {
                var found = next;
                while (found < sites.length && sites[found].parameter != parameterName) {
                    found++;
                }
                if (found < sites.length) {
                    final site = sites[found];
                    sites[found] = sites[next];
                    sites[next] = site;
                    next++;
                }
            }
        }
        final seen:Map<String, Bool> = [];
        for (site in sites) {
            if (parameterOrder != null && parameterOrder.indexOf(site.parameter) < 0)
                continue;
            final value = currentLocalName != null ? DefaultArgExpander.coalescingDefaultForLocalParam(currentClass, currentMethodName, currentLocalName,
                site.parameter) : DefaultArgExpander.coalescingDefaultForParam(currentClass, currentMethodName, site.parameter);
            if (value == null)
                continue;
            if (seen.exists(site.parameter)) {
                continue;
            }
            seen.set(site.parameter, true);
            final defaultIsNull = isNullType(site.valueExpr.t) && containsNullDefault(value);
            final rawDefaultText = value != null ? coalescingDefaultText(value, DefaultArgExpander.withoutNull(site.valueExpr.t),
                defaultIsNull) : expr(site.defaultExpr);
            // When a string parameter read appears inside unwrap_or_else, Rust needs
            // the owned form (&str → String).
            final isStringDefault = switch (value) {
                case CParameterRead(_): isStringType(DefaultArgExpander.withoutNull(site.valueExpr.t));
                default: false;
            };
            final defaultText = isStringDefault ? rawDefaultText + ".to_string()" : rawDefaultText;
            final combinator = defaultIsNull ? ".or_else(|| " : ".unwrap_or_else(|| ";
            // The rebound parameter only needs mutability when the body
            // assigns it again or a try block captures an assignment; the
            // same condition as plain local declarations.
            final paramVar = switch (stripWrap(site.valueExpr).expr) {
                case TLocal(v): v;
                case _: null;
            };
            final bindingKw = paramVar != null
                && (mutated.exists(paramVar.id) || tryCapturedAssignments.exists(paramVar.id)) ? "let mut " : "let ";
            out.push(indent(depth) + bindingKw + RustImports.toSnakeCase(site.parameter) + " = " + RustImports.toSnakeCase(site.parameter) + combinator
                + defaultText + ");");
        }
        return out;
    }

    // ------------------------------------------------------------------
    // Statements
    // ------------------------------------------------------------------

    public function statementsOf(e:TypedExpr):Array<TypedExpr> {
        return switch (e.expr) {
            case TBlock(stmts): stmts;
            case _: [e];
        }
    }

    function stmtLines(e:TypedExpr, depth:Int):Array<String> {
        switch (e.expr) {
            case TVar(v, init) if (init != null && isTryRegion(init)):
                return regionInitializerLines(v, stripWrap(init), depth);
            case TVar(v, init) if (init != null):
                final kw = mutated.exists(v.id) || tryCapturedAssignments.exists(v.id) ? "let mut" : "let";
                final name = RustImports.toSnakeCase(localName(v));
                final explicitType = if (isFunctionType(v.t)) {
                    ": " + types.functionReturnOf(v.t);
                } else switch (v.t) {
                    case TInst(c, _)
                        if (c.get().name == "SortedMapBuilder" || c.get().name == "SortedMap" || c.get().name == "SortedSetBuilder"
                            || c.get().name == "SortedSet"):
                        ": "
                        + types.of(v.t, false);
                    case _: "";
                };
                var explicitNullableNone = false;
                var initStr = switch (init.expr) {
                    case TFunction(fn): functionValueLiteralNamed(v.name, fn, init.t);
                    case TConst(TNull) if (isNullType(v.t)):
                        explicitNullableNone = true;
                        "None";
                    default:
                        // The initializer of an i32-domain local renders its
                        // wrapping arithmetic in i32 so the binding infers i32.
                        final wrapInit = i32Locals.exists(v.id) && switch (init.expr) {
                            case TBinop(OpAdd | OpSub | OpMult, _, _): isIntType(init.t) && !isNullType(init.t);
                            case _: false;
                        };
                        if (wrapInit) {
                            i32InitializerTarget = true;
                            final text = expr(init);
                            i32InitializerTarget = false;
                            text;
                        } else {
                            expr(init);
                        }
                };
                var nullableType = explicitType;
                if (explicitNullableNone && explicitType == "")
                    nullableType = ": " + types.of(v.t, false);
                initStr = renderValueForType(v.t, init, initStr);
                switch (stripWrap(init).expr) {
                    case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
                        switch (stripWrap(subj).expr) {
                            case TLocal(item) if ((borrowedLoopVarIds.exists(item.id) || readsAfterDeclaration.exists(item.id))
                                && !isTypeCopy(cf.get().type)):
                                initStr += ".clone()";
                            case _:
                        }
                    case TLocal(source) if (!isTypeCopy(v.t) && readsAfterDeclaration.exists(source.id)):
                        initStr = "(" + initStr + ").clone()";
                    case _:
                }
                switch (stripWrap(init).expr) {
                    case TCall(fn, _) if (isStringCharCodeAt(fn)):
                        if (!nullableSensitiveLocals.exists(v.id)) {
                            initStr += ".unwrap_or(0)";
                            nullableCollapsedLocals.set(v.id, true);
                        }
                    case TCall(ifn, iargs) if (isStringIndexOf(ifn) && iargs.length >= 1 && isIntType(v.t) && !isNullType(v.t)):
                        i32Locals.set(v.id, true);
                    case _:
                }
                // A String local owns its value; a literal initializer is
                // a &str, so the empty literal declares String::new() and
                // any other literal converts once at the declaration. A
                // Null<String> local additionally wraps in Some.
                if (isStringType(v.t)) {
                    switch (stripWrap(init).expr) {
                        case TConst(TString(s)):
                            initStr = s.length == 0 ? "String::new()" : initStr + ".to_string()";
                            if (isNullType(v.t)) {
                                initStr = "Some(" + initStr + ")";
                            }
                        case _:
                    }
                }
                // An empty array literal is an untyped `vec![]` in Rust; the
                // element reads and writes of an array local infer through
                // later uses, but an index read before any write leaves the
                // element type unknown (E0282). The declared Haxe Array
                // element type anchors the binding.
                if (explicitType == "") {
                    switch (stripWrap(init).expr) {
                        case TArrayDecl(elems) if (elems.length == 0):
                            switch (Context.follow(v.t)) {
                                case TInst(c, _) if (c.get().name == "Array"):
                                    nullableType = ": " + types.of(v.t, false);
                                case _:
                            }
                        case _:
                    }
                }
                // Array values are owned Vecs.  Borrowing an array literal here
                // made every local initialized from an array a reference, even
                // though its Haxe type is Array<T>; that leaked into later calls
                // and produced &&Vec / immutable-borrow mismatches.  Borrow only
                // at the call sites whose declared parameter requires it.
                // A let initializer needs no outer parentheses; fully
                // wrapped lowerings such as Int64.make would otherwise
                // trip rustc's unused_parens lint at this position.
                if (StringTools.startsWith(initStr, "(") && StringTools.endsWith(initStr, ")") && matchingParens(initStr)) {
                    initStr = initStr.substr(1, initStr.length - 2);
                }
                return [indent(depth) + '$kw $name$nullableType = $initStr;'];
            case TVar(v, init) if (init == null):
                final name = RustImports.toSnakeCase(localName(v));
                if (tryCapturedAssignments.exists(v.id) && isNullType(v.t))
                    return [indent(depth) + "let mut " + name + ": " + types.of(v.t, false) + " = None;"];
                final kw = "let ";
                return [indent(depth) + kw + name + ": " + types.of(v.t, false) + ";"];
            case TBlock(stmts):
                final out = [indent(depth) + "{"];
                for (l in blockLines(stmts, depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                return out;
            case TIf(c, t, f):
                var condStr = expr(c);
                while (StringTools.startsWith(condStr, "(") && StringTools.endsWith(condStr, ")") && matchingParens(condStr)) {
                    condStr = condStr.substr(1, condStr.length - 2);
                }
                final proven = provenNonNullLocal(c);
                if (proven != null)
                    provenNonNullVarIds.set(proven.id, true);
                final out = [indent(depth) + "if " + condStr + " {"];
                for (l in blockLines(statementsOf(t), depth + 1))
                    out.push(l);
                if (proven != null)
                    provenNonNullVarIds.remove(proven.id);
                if (f != null) {
                    out.push(indent(depth) + "} else {");
                    for (l in blockLines(statementsOf(f), depth + 1))
                        out.push(l);
                }
                out.push(indent(depth) + "}");
                return out;
            case TWhile(c, b, true):
                var condStr = expr(c);
                while (StringTools.startsWith(condStr, "(") && StringTools.endsWith(condStr, ")") && matchingParens(condStr)) {
                    condStr = condStr.substr(1, condStr.length - 2);
                }
                // A literal true condition lowers to Rust's dedicated loop.
                final header = condStr == "true" ? "loop" : "while " + condStr;
                final out = [indent(depth) + header + " {"];
                for (l in blockLines(statementsOf(b), depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                return out;
            case TWhile(_, _, false):
                return [fail(e, "do-while has no lowering in the subset")];
            case TReturn(ret) if (ret == null):
                if (isFallible) {
                    return [indent(depth) + "return Ok(());"];
                }
                return [indent(depth) + "return;"];
            case TReturn(ret) if (isTryRegion(ret)):
                return regionReturnLines(stripWrap(ret), depth);
            case TReturn(ret) if (isVariantSwitch(ret)):
                return matchReturnLines(stripWrap(ret), depth);
            case TReturn(ret):
                // An Int-returning function renders u32, while a length
                // expression renders usize; the return narrows once at the
                // boundary. Each length read keeps its native type; the conversion
                // occurs at the call boundary.
                var retStr = if (returnUnsigned && isUsizeExpr(ret)) {
                    RustConversions.truncate(expr(ret), "u32");
                } else {
                    renderValueForType(currentReturnType, ret, expr(ret));
                };
                while (StringTools.startsWith(retStr, "(") && StringTools.endsWith(retStr, ")") && matchingParens(retStr)) {
                    retStr = retStr.substr(1, retStr.length - 2);
                }
                // A parameter-typed read clones at the boundary: the
                // element stays owned by its array.
                if (RustType.isTypeParam(ret.t)) {
                    switch (stripWrap(ret).expr) {
                        case TArray(_, _) | TField(_, _) | TLocal(_):
                            retStr = "(" + retStr + ").clone()";
                        case _:
                    }
                }
                // String-bearing returns adjust once at the boundary: a
                // String function owns its value while a literal is a &str,
                // and an Option<String> return (Null<String>) wraps a plain
                // String expression in Some. Expressions that already carry
                // the Null type lower to Option themselves, and TNull
                // already renders None, so neither wraps again.
                if (returnTypeName == "String") {
                    switch (stripWrap(ret).expr) {
                        case TConst(TString(s)): retStr = s.length == 0 ? "String::new()" : retStr + ".to_string()";
                        case TLocal(v) if (provenNonNullVarIds.exists(v.id) && isNullType(ret.t)):
                            // A null-checked Null<String> local owns its
                            // text; the view unwrap yields the value the
                            // guard proved present.
                            retStr = "(" + retStr + ").as_deref().unwrap_or(\"\").to_string()";
                        case _:
                    }
                } else if (StringTools.startsWith(returnTypeName, "Option<") && !isNullType(ret.t) && !isTNull(ret)) {
                    final payload = switch (stripWrap(ret).expr) {
                        case TLocal(v) if (borrowedLoopVarIds.exists(v.id)): "(" + retStr + ").clone()";
                        case _: retStr;
                    };
                    retStr = "Some(" + payload + ")";
                } else if (StringTools.startsWith(returnTypeName, "Option<") && isIntType(ret.t) && !isNullType(ret.t) && !isTNull(ret)) {
                    // An Int expression returned from a Null<Int> function
                    // wraps once at the boundary; Null-typed expressions
                    // already lower to Option and TNull renders None.
                    retStr = "Some(" + retStr + ")";
                }
                if (isFallible) {
                    final guard = staticGuardOf(ret);
                    if (guard != null)
                        retStr = "(" + guard + ").clone()";
                    return [indent(depth) + "return Ok(" + retStr + ");"];
                }
                return [indent(depth) + "return " + retStr + ";"];
            case TThrow(x):
                return [indent(depth) + "return Err(" + throwVariant(x) + ");"];
            case TTry(body, catches) if (catches.length == 1):
                return regionStatementLines(body, catches[0], depth);
            case TTry(_, _):
                return [fail(e, "try region handles exactly one exception domain")];
            case TBreak:
                return [indent(depth) + "break;"];
            case TContinue:
                return [indent(depth) + "continue;"];
            case TCall(fn, args) if (stringBufMutationParts(fn) != null):
                return stringBufMutationLines(fn, args, depth);
            case TMeta(_, inner):
                return stmtLines(inner, depth);
            case TUnop(OpIncrement, _, subj):
                return [indent(depth) + expr(subj) + " += 1;"];
            case TUnop(OpDecrement, _, subj):
                return [indent(depth) + expr(subj) + " -= 1;"];
            case _:
                return [indent(depth) + expr(e) + ";"];
        }
    }

    function throwVariant(x:TypedExpr):String {
        final inner = stripWrap(x);
        final raw = switch (inner.expr) {
            case TNew(c, _, args) if (args.length == 1): exceptionVariant(c.get(), args[0]);
            case _: expr(x);
        };
        final payload = switch (inner.expr) {
            case TNew(_, _, args) if (args.length == 1): payloadEnumRef(args[0]);
            case _: null;
        };
        if (payload != null
            && errorTypeName != null
            && StringTools.endsWith(errorTypeName, "Fault")
            && errorTypeName != payload.get().name) {
            return errorTypeName + "::" + payload.get().name + "Fault(" + raw + ")";
        }
        return raw;
    }

    /**
        The payload enum behind std.UStringException: every buffer check
        of stdlib/08 reports UnpairedSurrogate through it. Registers the
        import the hand-emitted Err arms need and returns the enum name,
        or null when the exception class is outside the module set.
    **/
    function stringBufFaultEnum():Null<String> {
        final enumModule = state.exceptionPayloads.get("std.UStringException");
        if (enumModule == null) {
            return null;
        }
        final name = enumModule.split(".").pop();
        final emitted = state.payloadEnumModules.get(enumModule);
        final emittedIn = emitted != null ? emitted : "std.UStringException";
        imports.requireType(emittedIn, name);
        return name;
    }

    /**
        Recognizes `buf.add(part)` and `buf.addChar(unit)` on std.StringBuf;
        the pairing checks end the fallible owner through `return Err`, so
        these mutations lower as statements only.
    **/
    function stringBufMutationParts(fn:TypedExpr):Null<{name:String, subj:TypedExpr}> {
        return switch (fn.expr) {
            case TField(subj, FInstance(_, _, cf)) if (isStringBuf(subj)): final n = cf.get()
                    .name; n == "add" || n == "addChar" ? {name: n, subj: subj} : null;
            case _: null;
        };
    }

    /** Statement lowering of the two buffer mutations (stdlib/08). */
    function stringBufMutationLines(fn:TypedExpr, args:Array<TypedExpr>, depth:Int):Array<String> {
        final parts = stringBufMutationParts(fn);
        if (parts == null) {
            return [fail(fn, "not a string buffer mutation")];
        }
        if (!isFallible) {
            return [
                fail(fn,
                    "string buffer " + parts.name + " has no lowering outside a fallible function: route the mutation through a fallible helper (stdlib/08)")
            ];
        }
        final fault = stringBufFaultEnum();
        if (fault == null) {
            return [
                fail(fn, "string buffer checks require std.UStringException in the module set (stdlib/08)")
            ];
        }
        final buf = expr(parts.subj);
        final out:Array<String> = [];
        if (parts.name == "add") {
            final part = expr(args[0]);
            out.push(indent(depth) + "if let Some(&unit) = " + buf + ".last() {");
            // A Rust &str is always well-formed, so no part can open with
            // the trail surrogate the contract would pair; the trail-start
            // clause of stdlib/08 folds away.
            out.push(indent(depth + 1) + "if unit >= 55296 && unit <= 56319 && !" + part + ".is_empty() {");
            out.push(indent(depth + 2) + "return Err(" + fault + "::UnpairedSurrogate { unit: u32::from(unit) });");
            out.push(indent(depth + 1) + "}");
            out.push(indent(depth) + "}");
            out.push(indent(depth) + buf + ".extend(" + part + ".encode_utf16());");
        } else {
            final u = expr(args[0]);
            out.push(indent(depth) + "if " + u + " >= 56320 && " + u + " <= 57343 {");
            out.push(indent(depth + 1) + "match " + buf + ".last() {");
            out.push(indent(depth + 2) + "Some(&last) if last >= 55296 && last <= 56319 => {}");
            out.push(indent(depth + 2) + "_ => return Err(" + fault + "::UnpairedSurrogate { unit: " + u + " }),");
            out.push(indent(depth + 1) + "}");
            out.push(indent(depth) + "} else if let Some(&last) = " + buf + ".last() {");
            out.push(indent(depth + 1) + "if last >= 55296 && last <= 56319 {");
            out.push(indent(depth + 2) + "return Err(" + fault + "::UnpairedSurrogate { unit: u32::from(last) });");
            out.push(indent(depth + 1) + "}");
            out.push(indent(depth) + "}");
            out.push(indent(depth) + buf + ".push(" + RustConversions.truncate(u, "u16") + ");");
        }
        return out;
    }

    function exceptionVariant(cls:ClassType, payloadArg:TypedExpr):String {
        // Name the payload enum from the thrown variant itself: each exception
        // class pairs with exactly one payload enum, and the enum is emitted
        // inside the exception class's module file.
        final arg = stripWrap(payloadArg);
        final payloadEnum = payloadEnumRef(arg);
        final errType = payloadEnum != null ? payloadEnum.get().name : (state.errorName != null ? state.errorName : "");
        final enumModule = payloadEnum != null ? payloadEnum.get().module : null;
        final emittedIn = enumModule != null
            && state.payloadEnumModules.exists(enumModule) ? state.payloadEnumModules.get(enumModule) : cls.module;
        imports.requireType(emittedIn, errType);
        switch (arg.expr) {
            case TField(_, FEnum(_, ef)):
                return errType + "::" + RustImports.toUpperCamelCase(ef.name);
            case TCall(fn, callArgs):
                switch (stripWrap(fn).expr) {
                    case TField(_, FEnum(_, ef)):
                        final efArgs = switch (ef.type) {
                            case TFun(fargs, _): fargs;
                            case _: [];
                        };
                        final parts = [];
                        for (i in 0...callArgs.length) {
                            final argName = i < efArgs.length ? RustImports.toSnakeCase(efArgs[i].name) : "arg" + i;
                            final argType = i < efArgs.length ? efArgs[i].t : null;
                            parts.push(argName + ": " + ownedConstructorArg(argType, callArgs[i]));
                        }
                        return errType + "::" + RustImports.toUpperCamelCase(ef.name) + " { " + parts.join(", ") + " }";
                    case _:
                }
            case _:
        }
        return errType + "::" + expr(payloadArg);
    }

    function errorPropagationSuffix(c:Ref<ClassType>, cf:Ref<ClassField>, isStatic:Bool):String {
        if (!isFallible)
            return isFallibleCallee(c, cf, isStatic) ? ".unwrap()" : "";
        if (!isFallibleCallee(c, cf, isStatic))
            return "";
        final callee = state.funcErrorTypes.get(RustEmissionState.funcKey(c.get().module, cf.get().name, isStatic));
        if (callee == null || errorTypeName == null || callee.name == errorTypeName)
            return "?";
        final variant = state.syntheticErrorVariant(errorTypeName, callee);
        if (variant == null)
            return "?";
        return ".map_err(|e| " + errorTypeName + "::" + variant + "(e))?";
    }

    function payloadEnumRef(e:TypedExpr):Null<Ref<haxe.macro.Type.EnumType>> {
        return switch (e.expr) {
            case TField(_, FEnum(en, _)): en;
            case TCall(fn, _):
                switch (stripWrap(fn).expr) {
                    case TField(_, FEnum(en, _)): en;
                    case _: null;
                }
            case _: null;
        };
    }

    function fuseWithin(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TBlock(stmts):
                final fused = fuseUninitializedVars([for (s in stmts) fuseWithin(s)]);
                {expr: TBlock(fused), pos: e.pos, t: e.t};
            case _:
                TypedExprTools.map(e, fuseWithin);
        }
    }

    function fuseUninitializedVars(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            switch (stmts[i].expr) {
                case TVar(v, init) if (init == null):
                    var assignIdx = -1;
                    var rhsExpr:Null<TypedExpr> = null;
                    for (j in (i + 1)...stmts.length) {
                        switch (stripCast(stmts[j]).expr) {
                            case TBinop(OpAssign, lhs, rhs):
                                switch (stripCast(lhs).expr) {
                                    case TLocal(assignedVar) if (assignedVar.id == v.id):
                                        assignIdx = j;
                                        rhsExpr = rhs;
                                    case _:
                                }
                            case _:
                        }
                        if (assignIdx != -1)
                            break;
                    }
                    if (assignIdx != -1 && rhsExpr != null) {
                        out.push({expr: TVar(v, rhsExpr), pos: stmts[i].pos, t: stmts[i].t});
                        stmts.splice(assignIdx, 1);
                        i++;
                        continue;
                    }
                case _:
            }
            out.push(stmts[i]);
            i++;
        }
        return out;
    }

    /**
        Locals that an early-exit null guard proves present for the rest of
        a statement list: an `if (x == null) return;` without an else arm
        ends the block whenever x is absent, so every later statement sees
        a present value. A guard whose local a later statement reassigns
        (impossible for a final binding) is excluded.
    **/
    function earlyExitGuardIds(stmts:Array<TypedExpr>):Array<Int> {
        final ids = [];
        for (i in 0...stmts.length) {
            final localId = earlyExitGuardLocal(stmts[i]);
            if (localId != null && !writesLocalAfter(stmts, i, localId))
                ids.push(localId);
        }
        return ids;
    }

    /** The local an early-exit null guard statement proves, or null. */
    function earlyExitGuardLocal(stmt:TypedExpr):Null<Int> {
        return switch (stripWrap(stmt).expr) {
            case TIf(cond, thenBody, null):
                final localId = nullEqLocal(cond);
                if (localId != null && TerminationAnalysis.alwaysTerminates(thenBody)) localId else null;
            case _: null;
        };
    }

    /** The local an `x == null` or `null == x` condition compares. */
    function nullEqLocal(cond:TypedExpr):Null<Int> {
        return switch (stripWrap(cond).expr) {
            case TBinop(OpEq, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TNull)]: v.id;
                    case [TConst(TNull), TLocal(v)]: v.id;
                    case _: null;
                };
            case _: null;
        };
    }

    /** Whether any statement after `from` assigns through the local. */
    function writesLocalAfter(stmts:Array<TypedExpr>, from:Int, localId:Int):Bool {
        for (i in (from + 1)...stmts.length) {
            if (writesLocal(stmts[i], localId))
                return true;
        }
        return false;
    }

    /** Whether the statement assigns through the local anywhere. */
    function writesLocal(e:TypedExpr, localId:Int):Bool {
        return switch (stripWrap(e).expr) {
            case TBinop(OpAssign | OpAssignOp(_), t, _): targetMentions(t, localId);
            case TUnop(OpIncrement | OpDecrement, _, subj): targetMentions(subj, localId);
            case TBlock(stmts): anyWrites(stmts, localId);
            case TIf(_, t, f): writesLocal(t, localId) || (f != null && writesLocal(f, localId));
            case TWhile(_, b, _) | TFor(_, _, b): writesLocal(b, localId);
            case TVar(_, init): init != null && writesLocal(init, localId);
            case _: false;
        };
    }

    function anyWrites(stmts:Array<TypedExpr>, localId:Int):Bool {
        for (s in stmts) {
            if (writesLocal(s, localId))
                return true;
        }
        return false;
    }

    /** Whether the assignment target chain mentions the local. */
    function targetMentions(e:TypedExpr, localId:Int):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): v.id == localId;
            case TArray(arr, _): targetMentions(arr, localId);
            case TField(subj, _): targetMentions(subj, localId);
            case _: false;
        };
    }

    /** Expression-position block lowering (features/43). */
    function blockExpression(stmts:Array<TypedExpr>):String {
        if (stmts.length == 0)
            return fail(null, "expression block must end in a value statement (features/43)");
        for (i in 0...stmts.length - 1)
            switch (stmts[i].expr) {
                case TVar(_, _):
                case _:
                    return fail(stmts[i], "expression block allows only declarations before its value statement (features/43)");
            }
        switch (stmts[stmts.length - 1].expr) {
            case TReturn(_) | TThrow(_) | TVar(_, _) | TIf(_, _, _) | TWhile(_, _, _) | TFor(_, _, _) | TSwitch(_, _, _) | TTry(_, _) | TBlock(_) | TBreak |
                TContinue | TBinop(OpAssign, _, _) | TBinop(OpAssignOp(_), _, _):
                return fail(stmts[stmts.length - 1], "expression block must end in a value statement (features/43)");
            case _:
        }
        final out = ["{"];
        for (s in stmts.slice(0, stmts.length - 1))
            for (line in stmtLines(s, 1))
                out.push(line);
        out.push(indent(1) + expr(stmts[stmts.length - 1]));
        out.push("}");
        return out.join("\n");
    }

    function blockLines(stmts:Array<TypedExpr>, depth:Int, tailScope:Bool = false):Array<String> {
        stmts = fuseUninitializedVars(stmts);
        stmts = regroupLoops(stmts);
        stmts = transformCountdownLoops(stmts);
        final out:Array<String> = [];
        final provenByGuard = earlyExitGuardIds(stmts);
        for (id in provenByGuard)
            provenNonNullVarIds.set(id, true);

        var i = 0;
        while (i < stmts.length) {
            if (TerminationAnalysis.alwaysTerminates(stmts[i])) {
                for (l in stmtLines(stmts[i], depth))
                    out.push(l);
                break;
            }
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

        if (tailScope && isFallible) {
            var endsWithReturn = false;
            if (stmts.length > 0) {
                switch (stmts[stmts.length - 1].expr) {
                    case TReturn(_) | TThrow(_):
                        endsWithReturn = true;
                    // A break-free while(true) never falls through; a trailing
                    // epilogue would be dead text.
                    case TWhile(c, b, true) if (isLiteralTrue(c) && !loopBodyBreaks(b)):
                        endsWithReturn = true;
                    case _:
                }
            }
            if (!endsWithReturn) {
                out.push(indent(depth) + (inTryClosure
                    || currentReturnType == null
                    || isVoidType(currentReturnType) ? "Ok(())" : "unreachable!();"));
            }
        }

        for (id in provenByGuard)
            provenNonNullVarIds.remove(id);
        return out;
    }

    function transformCountdownLoops(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            if (i + 1 < stmts.length) {
                final cd = matchCountdownLoop(stmts[i], stmts[i + 1]);
                if (cd != null) {
                    mutated.set(cd.readVar.id, true);
                    final newDecl:TypedExpr = {
                        expr: TVar(cd.readVar, cd.base),
                        pos: stmts[i].pos,
                        t: stmts[i].t
                    };
                    out.push(newDecl);

                    final newCond = transformCountdownCond(cd.cond, cd.readVar.id);
                    final newBodyStmts = statementsOf(cd.body).map(s -> shiftIndexExpr(s, cd.readVar.id));
                    final newBody:TypedExpr = {
                        expr: TBlock(newBodyStmts),
                        pos: cd.body.pos,
                        t: cd.body.t
                    };
                    final newWhile:TypedExpr = {
                        expr: TWhile(newCond, newBody, true),
                        pos: stmts[i + 1].pos,
                        t: stmts[i + 1].t
                    };
                    out.push(newWhile);

                    for (k in (i + 2)...stmts.length) {
                        out.push(shiftIndexExpr(stmts[k], cd.readVar.id));
                    }
                    break;
                }
            }
            out.push(stmts[i]);
            i += 1;
        }
        return out;
    }

    function matchCountdownLoop(decl:TypedExpr, loop:TypedExpr):Null<{
        readVar:TVar,
        base:TypedExpr,
        cond:TypedExpr,
        body:TypedExpr
    }> {
        switch [decl.expr, loop.expr] {
            case [TVar(readVar, init), TWhile(cond, body, true)] if (init != null):
                if (!isIntType(init.t))
                    return null;
                if (!hasGteZeroCheck(cond, readVar.id)) {
                    return null;
                }
                if (!mentionsUnitDecrement(statementsOf(body), readVar.id)) {
                    return null;
                }
                // The guard becomes `> 0` and every body reference shifts
                // down by one, so the transformed loop must start one above
                // the initializer for the body to see the initializer's own
                // value on the first pass. An initializer of the exact shape
                // `X - 1` keeps the stripped `X` form; any other initializer
                // gets an explicit `+ 1`.
                final stripped = strippedUnitSub(init);
                final base = stripped != null ? stripped : {
                    expr: TBinop(OpAdd, init, {expr: TConst(TInt(1)), pos: init.pos, t: init.t}),
                    pos: init.pos,
                    t: init.t
                };
                return {
                    readVar: readVar,
                    base: base,
                    cond: cond,
                    body: body
                };
            case _:
                return null;
        }
    }

    // `X - 1` with a literal 1 on the right yields X.
    function strippedUnitSub(e:TypedExpr):Null<TypedExpr> {
        return switch (stripWrap(e).expr) {
            case TBinop(OpSub, b, r):
                switch (stripWrap(r).expr) {
                    case TConst(TInt(1)): b;
                    case _: null;
                };
            case _: null;
        };
    }

    function isLiteralTrue(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TBool(true)): true;
            case _: false;
        };
    }

    // A break lexically inside a nested loop or closure binds to that
    // construct; only direct breaks of this loop end it.
    function loopBodyBreaks(e:TypedExpr):Bool {
        switch (e.expr) {
            case TBreak:
                return true;
            case TWhile(_, _, _) | TFor(_, _, _) | TFunction(_):
                return false;
            case _:
                var found = false;
                TypedExprTools.iter(e, child -> {
                    if (!found && loopBodyBreaks(child))
                        found = true;
                });
                return found;
        }
    }

    function hasGteZeroCheck(cond:TypedExpr, varId:Int):Bool {
        final inner = stripWrap(cond);
        switch (inner.expr) {
            case TBinop(OpBoolAnd, l, _):
                return isGteZero(l, varId);
            case _:
                return isGteZero(inner, varId);
        }
    }

    function isGteZero(e:TypedExpr, varId:Int):Bool {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TBinop(OpGte, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TInt(0))] if (v.id == varId): true;
                    case _: false;
                };
            case TBinop(OpLte, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TConst(TInt(0)), TLocal(v)] if (v.id == varId): true;
                    case _: false;
                };
            case TBinop(OpGt, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TInt(-1))] if (v.id == varId): true;
                    case _: false;
                };
            case _: false;
        }
    }

    function transformCountdownCond(cond:TypedExpr, varId:Int):TypedExpr {
        final inner = stripWrap(cond);
        switch (inner.expr) {
            case TBinop(OpBoolAnd, l, r) if (isGteZero(l, varId)):
                final v = findLocalVar(l, varId);
                final newL:TypedExpr = {
                    expr: TBinop(OpGt, {expr: TLocal(v), pos: l.pos, t: l.t}, {expr: TConst(TInt(0)), pos: l.pos, t: l.t}),
                    pos: l.pos,
                    t: l.t
                };
                final newR = shiftIndexExpr(r, varId);
                return {
                    expr: TBinop(OpBoolAnd, newL, newR),
                    pos: cond.pos,
                    t: cond.t
                };
            case _:
                if (isGteZero(inner, varId)) {
                    final v = findLocalVar(inner, varId);
                    return {
                        expr: TBinop(OpGt, {expr: TLocal(v), pos: inner.pos, t: inner.t}, {expr: TConst(TInt(0)), pos: inner.pos, t: inner.t}),
                        pos: cond.pos,
                        t: cond.t
                    };
                }
                return shiftIndexExpr(cond, varId);
        }
    }

    function findLocalVar(e:TypedExpr, varId:Int):TVar {
        var found:Null<TVar> = null;
        function walk(x:TypedExpr) {
            switch (x.expr) {
                case TLocal(v) if (v.id == varId):
                    found = v;
                case _:
            }
            TypedExprTools.iter(x, walk);
        }
        walk(e);
        return found;
    }

    function mentionsUnitDecrement(stmts:Array<TypedExpr>, varId:Int):Bool {
        var found = false;
        for (s in stmts) {
            function walk(x:TypedExpr) {
                switch (x.expr) {
                    // Only a unit step is transformable: the unsigned `> 0`
                    // guard exits exactly at zero, and a larger step would
                    // wrap below zero on the unsigned domain and keep
                    // looping.
                    case TBinop(OpAssignOp(OpSub), l, r) if (isTargetVar(l, varId) && isLiteralOne(r)):
                        found = true;
                    case TBinop(OpAssign, l, r) if (isTargetVar(l, varId)):
                        switch (stripWrap(r).expr) {
                            case TBinop(OpSub, subTarget, sub) if (isTargetVar(subTarget, varId) && isLiteralOne(sub)):
                                found = true;
                            case _:
                        }
                    case TUnop(OpDecrement, _, subj) if (isTargetVar(subj, varId)):
                        found = true;
                    case _:
                }
                TypedExprTools.iter(x, walk);
            }
            walk(s);
        }
        return found;
    }

    function isLiteralOne(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(1)): true;
            case _: false;
        };
    }

    function isTargetVar(e:TypedExpr, varId:Int):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v) if (v.id == varId): true;
            case _: false;
        };
    }

    function shiftIndexExpr(e:TypedExpr, varId:Int):TypedExpr {
        switch (e.expr) {
            case TBinop(OpAdd, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [TLocal(v), TConst(TInt(1))] if (v.id == varId):
                        return l;
                    case [TConst(TInt(1)), TLocal(v)] if (v.id == varId):
                        return r;
                    case _:
                }
            case TBinop(OpAssignOp(op), l, r) if (isTargetVar(l, varId)):
                return {
                    expr: TBinop(OpAssignOp(op), l, shiftIndexExpr(r, varId)),
                    pos: e.pos,
                    t: e.t
                };
            case TBinop(OpAssign, l, r) if (isTargetVar(l, varId)):
                return {
                    expr: TBinop(OpAssign, l, shiftAssignRhs(r, varId)),
                    pos: e.pos,
                    t: e.t
                };
            case TUnop(OpDecrement, post, subj) if (isTargetVar(subj, varId)):
                return e;
            case TLocal(v) if (v.id == varId):
                return {
                    expr: TBinop(OpSub, e, {expr: TConst(TInt(1)), pos: e.pos, t: e.t}),
                    pos: e.pos,
                    t: e.t
                };
            case _:
        }
        return TypedExprTools.map(e, x -> shiftIndexExpr(x, varId));
    }

    function shiftAssignRhs(r:TypedExpr, varId:Int):TypedExpr {
        final inner = stripWrap(r);
        switch (inner.expr) {
            case TBinop(OpSub, l, rightSub) if (isTargetVar(l, varId)):
                return {
                    expr: TBinop(OpSub, l, shiftIndexExpr(rightSub, varId)),
                    pos: r.pos,
                    t: r.t
                };
            case _:
                return shiftIndexExpr(r, varId);
        }
    }

    // ------------------------------------------------------------------
    // Counted loops
    // ------------------------------------------------------------------

    function regroupLoops(stmts:Array<TypedExpr>):Array<TypedExpr> {
        final out:Array<TypedExpr> = [];
        var i = 0;
        while (i < stmts.length) {
            if (i + 2 < stmts.length) {
                final loop = intervalCore(stmts[i], stmts[i + 1], stmts[i + 2]);
                if (loop != null) {
                    final grouped:TypedExpr = {
                        expr: TBlock([stmts[i], stmts[i + 1], stmts[i + 2]]),
                        pos: stmts[i].pos,
                        t: stmts[i + 2].t
                    };
                    out.push(grouped);
                    i += 3;
                    continue;
                }
            }
            if (i + 1 < stmts.length) {
                final loop = intervalShort(stmts[i], stmts[i + 1]);
                if (loop != null) {
                    final grouped:TypedExpr = {
                        expr: TBlock([stmts[i], stmts[i + 1]]),
                        pos: stmts[i].pos,
                        t: stmts[i + 1].t
                    };
                    out.push(grouped);
                    i += 2;
                    continue;
                }
            }
            out.push(stmts[i]);
            i += 1;
        }
        return out;
    }

    function intervalCore(counterDecl:TypedExpr, boundDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        switch [counterDecl.expr, boundDecl.expr, whileExpr.expr] {
            case [TVar(counter, start), TVar(boundVar, bound), TWhile(cond, body, true)]:
                final condOk = switch (stripWrap(cond).expr) {
                    case TBinop(OpLt, l, r):
                        final lc = stripWrap(l);
                        final rc = stripWrap(r);
                        switch [lc.expr, rc.expr] {
                            case [TLocal(c), TLocal(b)]: c.id == counter.id && b.id == boundVar.id;
                            case _: false;
                        }
                    case _: false;
                }
                if (!condOk) {
                    return null;
                }
                final bodyStmts = statementsOf(body);
                if (bodyStmts.length == 0) {
                    return null;
                }
                switch (bodyStmts[0].expr) {
                    case TVar(captured, inc):
                        final captureOk = inc != null && switch (stripWrap(inc).expr) {
                            case TUnop(OpIncrement, true, subj):
                                switch (stripWrap(subj).expr) {
                                    case TLocal(c): c.id == counter.id;
                                    case _: false;
                                }
                            case _: false;
                        } if (!captureOk) {
                            return null;
                        }
                        return {
                            index: captured,
                            start: start,
                            bound: bound,
                            body: bodyStmts.slice(1)
                        };
                    case _:
                        return null;
                }
            case _:
                return null;
        }
    }

    function matchInterval(e:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        switch (e.expr) {
            case TBlock(stmts) if (stmts.length == 3):
                return intervalCore(stmts[0], stmts[1], stmts[2]);
            case TBlock(stmts) if (stmts.length == 2):
                return intervalShort(stmts[0], stmts[1]);
            case _:
                return null;
        }
    }

    function intervalShort(counterDecl:TypedExpr, whileExpr:TypedExpr):Null<{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }> {
        switch [counterDecl.expr, whileExpr.expr] {
            case [TVar(counter, start), TWhile(cond, body, true)]:
                final bound = switch (stripWrap(cond).expr) {
                    case TBinop(OpLt, {expr: TLocal(c)}, right) if (c.id == counter.id): right;
                    case _: return null;
                };
                final bodyStmts = statementsOf(body);
                if (bodyStmts.length == 0)
                    return null;
                switch (bodyStmts[0].expr) {
                    case TVar(captured, inc) if (inc != null):
                        switch (stripWrap(inc).expr) {
                            case TUnop(OpIncrement, true, {expr: TLocal(c)}) if (c.id == counter.id):
                                return {
                                    index: captured,
                                    start: start,
                                    bound: bound,
                                    body: bodyStmts.slice(1)
                                };
                            case _:
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    function loopLines(loop, depth:Int):Array<String> {
        rangeLoopVars.set(loop.index.id, true);
        final name = RustImports.toSnakeCase(loop.index.name);
        final sliceSubj = sliceIterationSubject(loop);
        if (sliceSubj != null) {
            final itemVar = sliceItemVar(loop.body, loop.index, sliceSubj);
            if (itemVar != null) {
                final itemName = RustImports.toSnakeCase(itemVar.name);
                final isScalar = switch (Context.follow(itemVar.t)) {
                    case TAbstract(a, _): final n = a.get().name; n == "Int" || n == "Bool" || n == "Float";
                    default: false;
                };
                // A name-keyed lookup is valid only for current-function parameters because argTypes accumulates across functions.
                final argType = switch (stripWrap(sliceSubj).expr) {
                    case TLocal(v): paramVarIds.exists(v.id) ? argTypes.get(v.name) : null;
                    default: null;
                };
                // A scalar loop over an owned local array borrows the array: the
                // pattern takes a reference and the array stays usable after the
                // loop. Parameters already arrive as rendered references.
                final ownedLocal = isScalar && argType == null;
                final pattern = if (isScalar) {
                    if (argType != null) {
                        StringTools.startsWith(argType, "&mut") ? "&mut " + itemName : "&" + itemName;
                    } else {
                        "&" + itemName;
                    }
                } else {
                    itemName;
                };
                if (argType != null)
                    borrowedLoopVarIds.set(itemVar.id, true);
                final subjectLocalId = switch (stripWrap(sliceSubj).expr) {
                    case TLocal(v): v.id;
                    case _: -1;
                };
                final nonScalarOwnedLocal = !isScalar && argType == null && !paramVarIds.exists(subjectLocalId);
                if (argType != null || nonScalarOwnedLocal)
                    borrowedLoopVarIds.set(itemVar.id, true);
                final iterated = (ownedLocal || nonScalarOwnedLocal) ? "&" + expr(sliceSubj) : expr(sliceSubj);
                switch (Context.follow(itemVar.t)) {
                    case TAbstract(a, _) if (a.get().name == "Int"):
                        // Array elements reach Rust as u32; remember the loop binding
                        // so negative-domain checks lower as upper-bound checks.
                        unsignedLocals.set(itemVar.id, true);
                    case _:
                }
                final remainingBody = loop.body.slice(1);
                final gb = matchGroupByBody(remainingBody);
                if (gb != null) {
                    final entryName = RustImports.toSnakeCase(gb.entryVar.name);
                    final entryExprStr = expr(gb.entryInit);
                    final builderStr = expr(gb.builderSubj);
                    final kGetExpr = sortedRefArg(gb.keyArg);
                    final kPutExpr = sortedRefArg(gb.keyArg);
                    final valStr = renderPushArg(gb.valArg);
                    final out = [indent(depth) + "for " + pattern + " in " + iterated + " {"];
                    for (l in blockLines(gb.prefix, depth + 1))
                        out.push(l);
                    out.push(indent(depth + 1) + "let " + entryName + " = " + entryExprStr + ";");
                    out.push(indent(depth + 1) + "let mut pipeline_bucket = match " + builderStr + ".get(" + kGetExpr + ") {");
                    out.push(indent(depth + 2) + "Some(b) => b,");
                    out.push(indent(depth + 2) + "None => Vec::new(),");
                    out.push(indent(depth + 1) + "};");
                    out.push(indent(depth + 1) + "pipeline_bucket.push(" + valStr + ");");
                    out.push(indent(depth + 1) + builderStr + ".put(" + kPutExpr + ", &pipeline_bucket);");
                    out.push(indent(depth) + "}");
                    return out;
                }

                final out = [indent(depth) + "for " + pattern + " in " + iterated + " {"];
                for (l in blockLines(remainingBody, depth + 1))
                    out.push(l);
                out.push(indent(depth) + "}");
                return out;
            }
        }

        final startStr = expr(loop.start);
        final boundStr = loopBound(loop.bound);
        var readsIndex = false;
        for (statement in loop.body)
            if (mentionsLocal(statement, loop.index)) {
                readsIndex = true;
                break;
            }
        final loopName = readsIndex ? name : "_";
        final out = [indent(depth) + "for " + loopName + " in " + startStr + ".." + boundStr + " {"];
        for (l in blockLines(loop.body, depth + 1))
            out.push(l);
        out.push(indent(depth) + "}");
        return out;
    }

    function sliceIterationSubject(loop:{
        index:TVar,
        start:TypedExpr,
        bound:TypedExpr,
        body:Array<TypedExpr>
    }):Null<TypedExpr> {
        final innerStart = stripWrap(loop.start);
        final isStartZero = switch (innerStart.expr) {
            case TConst(TInt(0)): true;
            case _: false;
        };
        if (!isStartZero)
            return null;
        // The element-loop rewrite drops the counter binding.  Keep the
        // explicit range loop whenever the remaining body reads that counter.
        for (statement in loop.body.slice(1))
            if (mentionsLocal(statement, loop.index))
                return null;
        final innerBound = stripWrap(loop.bound);
        return switch (innerBound.expr) {
            case TField(subj, fa) if (fieldName(fa) == "length"):
                if (EnumQueryExpander.collectionEnum(subj) != null)
                    return null;
                switch (stripWrap(subj).expr) {
                    case TLocal(_): subj;
                    case _: null;
                }
            case _: null;
        };
    }

    function sliceItemVar(body:Array<TypedExpr>, indexVar:TVar, sliceSubj:TypedExpr):Null<TVar> {
        if (body.length == 0)
            return null;
        return switch (body[0].expr) {
            case TVar(itemVar, init) if (init != null):
                switch (stripWrap(init).expr) {
                    case TArray(subj, idx):
                        final subjOk = switch [stripWrap(subj).expr, stripWrap(sliceSubj).expr] {
                            case [TLocal(s1), TLocal(s2)]: s1.id == s2.id;
                            case _: false;
                        };
                        final idxOk = switch (stripWrap(idx).expr) {
                            case TLocal(iv): iv.id == indexVar.id;
                            case _: false;
                        };
                        if (subjOk && idxOk) itemVar else null;
                    case _: null;
                }
            case _: null;
        };
    }

    function loopBound(bound:TypedExpr):String {
        final inner = stripWrap(bound);
        switch (inner.expr) {
            case TField(subj, fa) if (fieldName(fa) == "length"):
                final enumCollection = EnumQueryExpander.collectionEnum(subj);
                if (enumCollection != null)
                    return Std.string(EnumQueryExpander.constructorCount(enumCollection));
                return rustU32Length(expr(subj) + ".len()");
            case _:
                return expr(bound);
        }
    }

    // ------------------------------------------------------------------
    // Counted fill (Vec::with_capacity)
    // ------------------------------------------------------------------

    function fillFusion(stmts:Array<TypedExpr>, i:Int, depth:Int):Null<Array<String>> {
        if (i + 1 >= stmts.length) {
            return null;
        }
        final alloc:Null<{arr:TVar, elem:Type}> = switch (stmts[i].expr) {
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
        if (alloc == null) {
            return null;
        }
        final loop = matchInterval(stmts[i + 1]);
        if (loop == null) {
            return null;
        }

        var storeValue:Null<TypedExpr> = null;
        var pushArg:Null<TypedExpr> = null;
        var ok = true;
        for (s in loop.body) {
            final store = indexedStoreOf(s);
            if (store != null) {
                if (store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
                    if (storeValue != null) {
                        ok = false;
                    }
                    storeValue = store.value;
                } else {
                    ok = false;
                }
                continue;
            }
            final push = pushOf(s);
            if (push != null) {
                if (push.arr.id == alloc.arr.id) {
                    if (pushArg != null || storeValue != null) {
                        ok = false;
                    }
                    pushArg = push.arg;
                } else {
                    ok = false;
                }
                continue;
            }
            if (mentionsLocal(s, alloc.arr)) {
                ok = false;
            }
        }
        if (!ok || (storeValue == null && pushArg == null)) {
            return null;
        }

        final arrName = RustImports.toSnakeCase(localName(alloc.arr));
        final capStr = capacityExpr(loop.bound);
        final boundStr = loopBound(loop.bound);
        final loopIndexName = RustImports.toSnakeCase(loop.index.name);

        // Check if loop index is mentioned in body outside the array store index
        var loopVarMentioned = false;
        for (s in loop.body) {
            final store = indexedStoreOf(s);
            if (store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
                if (mentionsLocal(store.value, loop.index)) {
                    loopVarMentioned = true;
                }
                continue;
            }
            final push = pushOf(s);
            if (push != null && push.arr.id == alloc.arr.id) {
                if (mentionsLocal(push.arg, loop.index)) {
                    loopVarMentioned = true;
                }
                continue;
            }
            if (mentionsLocal(s, loop.index)) {
                loopVarMentioned = true;
            }
        }

        final loopVar = loopVarMentioned ? loopIndexName : "_";

        final out:Array<String> = [];
        out.push(indent(depth) + "let capacity = " + capStr + ";");
        out.push(indent(depth) + "let mut " + arrName + " = Vec::with_capacity(capacity);");
        out.push(indent(depth) + "for " + loopVar + " in 0.." + boundStr + " {");
        final nonStores:Array<TypedExpr> = [];
        for (s in loop.body) {
            final store = indexedStoreOf(s);
            if (store != null && store.arr.id == alloc.arr.id && store.idx.id == loop.index.id) {
                if (nonStores.length > 0) {
                    for (l in blockLines(nonStores, depth + 1))
                        out.push(l);
                    nonStores.resize(0);
                }
                out.push(indent(depth + 1) + arrName + ".push(" + renderPushArg(store.value) + ");");
                continue;
            }
            final push = pushOf(s);
            if (push != null && push.arr.id == alloc.arr.id) {
                if (nonStores.length > 0) {
                    for (l in blockLines(nonStores, depth + 1))
                        out.push(l);
                    nonStores.resize(0);
                }
                out.push(indent(depth + 1) + arrName + ".push(" + renderPushArg(push.arg) + ");");
                continue;
            }
            nonStores.push(s);
        }
        if (nonStores.length > 0) {
            for (l in blockLines(nonStores, depth + 1))
                out.push(l);
        }
        out.push(indent(depth) + "}");
        return out;
    }

    function sortedKeyType(fn:TypedExpr):Null<haxe.macro.Type.Type> {
        return switch (fn.t) {
            case TFun(_, TInst(_, params)) if (params.length > 0): params[0];
            case _: null;
        };
    }

    function sortedValueType(fn:TypedExpr):Null<haxe.macro.Type.Type> {
        return switch (fn.t) {
            case TFun(_, TInst(_, params)) if (params.length > 1): params[1];
            case _: null;
        };
    }

    /**
        Comparator a builder site binds: the resident integer walk
        adapted to the unsigned business domain, the resident string
        walk, or the per-structure generated comparator.
    **/
    function sortedComparator(kType:Null<haxe.macro.Type.Type>, pos:haxe.macro.Expr.Position):String {
        if (kType == null) {
            Context.error("sorted builder requires an explicit key type", pos);
        }
        return switch (RustType.classifyKey(kType, pos)) {
            case IntKey:
                imports.require("std::rc::Rc");
                "Rc::new(|a, b| SortedTable::compare_ints("
                + RustConversions.reinterpret("(*a)", "i32")
                + ", "
                + RustConversions.reinterpret("(*b)", "i32")
                + "))";
            case StringKey:
                imports.require("std::rc::Rc");
                "Rc::new(|a, b| SortedTable::compare_strings(a.as_str(), b.as_str()))";
            case StructKey(def, _):
                final cmpName = "compare_" + RustImports.toSnakeCase(def.name);
                imports.requireType(def.module, cmpName);
                imports.require("std::rc::Rc");
                "Rc::new(" + cmpName + ")";
            case DataClassKey(cls, _):
                final cmpName = "compare_" + RustImports.toSnakeCase(cls.name);
                imports.requireType(cls.module, cmpName);
                imports.require("std::rc::Rc");
                "Rc::new(" + cmpName + ")";
        };
    }

    /**
        Every table parameter borrows: keys and values arrive as
        references and the resident clones what it stores. String keys
        construct when the expression is a literal or a borrowed &str.
    **/
    function sortedRefArg(arg:TypedExpr):String {
        if (isStringType(arg.t)) {
            switch (stripWrap(arg).expr) {
                case TConst(TString(_)):
                    return "&(" + expr(arg) + ").to_string()";
                case TLocal(v):
                    final pt = types.of(v.t, true);
                    return pt == "&str" ? "&(" + expr(arg) + ").to_string()" : "&" + expr(arg);
                case _:
                    return "&" + expr(arg);
            }
        }
        return "&(" + expr(arg) + ")";
    }

    function isNullableCollapsedLocal(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): nullableCollapsedLocals.exists(v.id);
            case _: false;
        };
    }

    function isBorrowedLocal(v:haxe.macro.Type.TVar):Bool {
        // argTypes accumulates across functions, so a name match alone can
        // read a previous function's parameter; only a current-function
        // parameter is borrowed.
        if (!paramVarIds.exists(v.id))
            return false;
        final stored = argTypes.get(v.name);
        return stored != null && StringTools.startsWith(stored, "&");
    }

    function renderPushArg(arg:TypedExpr):String {
        var argStr = expr(arg);
        if (isNullType(arg.t) && !(switch (stripWrap(arg).expr) {
            case TLocal(v): nullableCollapsedLocals.exists(v.id);
            case _: false;
        })) {
            argStr = argStr + ".unwrap()";
            if (!isTypeCopy(getNullInnerType(arg.t))) {
                if (!StringTools.endsWith(argStr, ".clone()")
                    && !StringTools.endsWith(argStr, ".to_vec()")
                    && !StringTools.endsWith(argStr, ".to_string()")) {
                    argStr = argStr + ".clone()";
                }
            }
            return argStr;
        }
        if (!isTypeCopy(arg.t)) {
            switch (stripWrap(arg).expr) {
                // The base constant renderer emits a bare &str literal, so
                // pushing one into a String array needs an owned conversion.
                case TConst(TString(_)):
                    argStr = argStr + ".to_string()";
                case TNew(_, _, _):
                case TLocal(v) if (isBorrowedLocal(v)):
                    // The local holds a reference (a borrowed parameter).
                    // A String parameter is &str, which owns through
                    // to_string(); any other reference clones the referent
                    // so the array owns its element.
                    argStr = isStringType(arg.t) ? argStr + ".to_string()" : "(*" + argStr + ").clone()";
                case TLocal(_) | TField(_) | TArray(_, _):
                    if (!StringTools.endsWith(argStr, ".clone()")
                        && !StringTools.endsWith(argStr, ".to_vec()")
                        && !StringTools.endsWith(argStr, ".to_string()")) {
                        argStr = argStr + ".clone()";
                    }
                default:
            }
        }
        return argStr;
    }

    function capacityExpr(bound:TypedExpr):String {
        // Constant and length bounds cannot overflow; every other bound needs
        // the overflow variant of the resolved error enum.
        final inner = stripWrap(bound);
        switch (inner.expr) {
            case TConst(TInt(n)) if (n >= 0):
                return Std.string(n);
            case TField(subj, fa) if (fieldName(fa) == "length"):
                return expr(subj) + ".len()";
            case _:
                if (errorTypeName == null || countOverflowVariant == null) {
                    // Haxe Int is u32; the T3 index form widens it to usize
                    // infallibly, so an Int bound in a function without an
                    // error enum needs no overflow variant.
                    if (isIntType(bound.t))
                        return usizeIndex(expr(bound));
                    Context.error("cannot lower fallible capacity expression: missing error enum or overflow variant", bound.pos);
                    return "0";
                }
                final errVariant = errorTypeName + "::" + countOverflowVariant;
                return "usize::try_from(" + expr(bound) + ").map_err(|_| " + errVariant + ")?";
        }
    }

    function indexedStoreOf(s:TypedExpr):Null<{arr:TVar, idx:TVar, value:TypedExpr}> {
        switch (stripWrap(s).expr) {
            case TBinop(OpAssign, target, value):
                switch (stripWrap(target).expr) {
                    case TArray(arr, idx):
                        final arrLocal = stripWrap(arr);
                        final idxLocal = stripWrap(idx);
                        switch [arrLocal.expr, idxLocal.expr] {
                            case [TLocal(a), TLocal(ix)]: return {arr: a, idx: ix, value: value};
                            case _:
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    function pushOf(s:TypedExpr):Null<{arr:TVar, arg:TypedExpr}> {
        switch (stripWrap(s).expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, fa) if (fieldName(fa) == "push"):
                        switch (stripWrap(subj).expr) {
                            case TLocal(a): return {arr: a, arg: args[0]};
                            case _:
                        }
                    case _:
                }
            case _:
        }
        return null;
    }

    // ------------------------------------------------------------------
    // Expressions
    // ------------------------------------------------------------------

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
                    case TInt(v):
                        // Haxe Int is 32-bit two's-complement; the business
                        // module real is u32, so a negative literal carries
                        // the same bits as its wrapped unsigned decimal with
                        // an explicit u32 suffix: the suffix keeps boundary
                        // casts to i32 bit-preserving. Resident modules keep
                        // the signed i32 rendering.
                        if (v < 0 && !RuntimeResidents.isResident(imports.selfModule)) {
                            return Std.string(v + 4294967296) + "u32";
                        }
                        return Std.string(v);
                    case TFloat(f):
                        final s = Std.string(f);
                        final padded = s.indexOf(".") >= 0 || s.indexOf("e") >= 0 || s.indexOf("E") >= 0 ? s : s + ".0";
                        // The f32 configuration marks every literal so its width never
                        // depends on the inference context (feature spec 23).
                        return FloatPrecision.isF32() ? padded + "f32" : padded;
                    case TString(s): return quoteString(s);
                    case TBool(b): return b ? "true" : "false";
                    case TNull: return "None";
                    case TThis: return "self";
                    case TSuper: return "super";
                    case _: return fail(e, "constant has no Rust lowering");
                }
            case TLocal(v):
                if (subst.exists(v.id)) {
                    return subst.get(v.id);
                }
                return RustImports.toSnakeCase(localName(v));
            case TArray(arr, idx):
                final mapReceiver = mapBackingReceiver(arr);
                if (mapReceiver != null) {
                    return expr(mapReceiver) + ".get(&" + rustMapKey(idx) + ").cloned()";
                }
                final staticGuard = staticGuardOf(arr);
                if (staticGuard != null) {
                    final base = staticGuard + "[" + staticIndex(idx) + "]";
                    return scalarTypeKind(e.t) == "String" ? "(" + base + ").clone()" : base;
                }
                final receiver = expr(arr);
                final receiverText = StringTools.startsWith(receiver, "&*") ? "(" + receiver + ")" : receiver;
                final base = receiverText + "[" + castArg(idx, "usize") + "]";
                // Reading a String element moves it out of the Vec, so a
                // value read renders as a clone. Borrow consumers go
                // through arrayArgBorrow and skip the copy.
                // Reads from an owned Haxe Array must not move its element out of
                // the Rust Vec. Clone non-Copy values at the indexing boundary;
                // this is the value semantics promised by Haxe arrays.
                return !isTypeCopy(e.t) ? "(" + base + ").clone()" : base;
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
                final elemType = switch (Context.follow(e.t)) {
                    case TInst(c, params) if (c.get().name == "Array" && params.length > 0): params[0];
                    case _: null;
                };
                final isStringElem = elemType != null && isStringType(elemType);
                final isNullableElem = elemType != null && StaticFieldHelper.isNullableType(elemType);
                final rendered = [
                    for (x in elems) {
                        final inner = if (isStringElem) {
                            switch (stripWrap(x).expr) {
                                case TConst(TString(_)):
                                    expr(x) + ".to_string()";
                                case TLocal(v) if (paramVarIds.exists(v.id)):
                                    expr(x) + ".to_string()";
                                case _:
                                    expr(x) + ".clone()";
                            }
                        } else {
                            expr(x);
                        };
                        if (isNullableElem && !isTNull(x) && !StaticFieldHelper.isNullableType(x.t)) {
                            "Some(" + inner + ")";
                        } else {
                            inner;
                        }
                    }
                ];
                return "vec![" + rendered.join(", ") + "]";
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
                // any match arm; a one-construct enum folds the read into an
                // exhaustive match, and anything wider stays in arms.
                final en = switch (Context.follow(se.t)) {
                    case TEnum(r, _): r.get();
                    case _: return fail(e, "payload read subject is not a variant value");
                };
                if (Lambda.count(en.constructs) != 1) {
                    return fail(e, "payload read of a multi-variant enum lowers inside a match arm only");
                }
                requireEnum(en.module, en.name);
                final pname = payloadName(ef, index);
                return "match "
                    + expr(se)
                    + " { "
                    + en.name
                    + "::"
                    + RustImports.toUpperCamelCase(ef.name)
                    + " { "
                    + pname
                    + ", .. } => "
                    + pname
                    + " }";
            case TEnumIndex(_):
                return fail(e, "enum index only lowers inside a variant switch");
            case TFunction(f):
                return functionValueLiteral(f, e.t);
            case TIf(c, t, f) if (f != null):
                final coalescing = coalescingSiteFor(e);
                if (coalescing != null)
                    return expr(coalescing.valueExpr);
                final optional = optionalIf(c, t, f, e.t);
                if (optional != null)
                    return optional;
                final condStr = switch (stripWrap(c).expr) {
                    case _: expr(stripWrap(c));
                };
                return "if " + condStr + " { " + conditionalBranchText(t, f, e.t) + " } else { " + conditionalBranchText(f, t, e.t) + " }";
            case TSwitch(_, _, _):
                return matchExpression(e);
            case TTry(_, catches) if (catches.length != 1):
                return fail(e, "try region handles exactly one exception domain");
            case TTry(_, _):
                // Region lowering needs the statement context (features/06):
                // statement position and initializer position render in
                // stmtLines, return position in TReturn.
                return fail(e, "try region lowers at statement, initializer, or return position");
            case TBlock(stmts):
                return blockExpression(stmts);
            case _:
                return fail(e, "expression has no Rust lowering in the subset: " + Std.string(e.expr));
        }
    }

    function optionalIf(c:TypedExpr, ifTrue:TypedExpr, ifFalse:TypedExpr, resultType:Type):Null<String> {
        var value:Null<TVar> = null;
        var trueIsNone = false;
        switch (stripWrap(c).expr) {
            case TBinop(OpEq, left, right):
                if (isTNull(right)) {
                    switch (stripWrap(left).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = true;
                        case _:
                    }
                } else if (isTNull(left)) {
                    switch (stripWrap(right).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = true;
                        case _:
                    }
                }
            case TBinop(OpNotEq, left, right):
                if (isTNull(right)) {
                    switch (stripWrap(left).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = false;
                        case _:
                    }
                } else if (isTNull(left)) {
                    switch (stripWrap(right).expr) {
                        case TLocal(v):
                            value = v;
                            trueIsNone = false;
                        case _:
                    }
                }
            case _:
        }
        if (value == null) {
            return null;
        }
        final selected = trueIsNone ? ifFalse : ifTrue;
        if (nullableCollapsedLocals.exists(value.id)) {
            final noneExpr = trueIsNone ? ifTrue : ifFalse;
            final localName = RustImports.toSnakeCase(value.name);
            return "if " + localName + " == 0 { " + expr(noneExpr) + " } else { " + localName + " }";
        }
        switch (stripWrap(selected).expr) {
            case TLocal(v) if (v.id == value.id):
                final noneExpr = trueIsNone ? ifTrue : ifFalse;
                final noneText = expr(noneExpr);
                final typedNoneText = isStringType(resultType) ? noneText + ".to_string()" : noneText;
                final localName = RustImports.toSnakeCase(value.name);
                return "match " + localName + " { None => " + typedNoneText + ", Some(ref " + localName + ") => " + localName + ".clone() }";
            case _:
        }
        return null;
    }

    /** Lowers an abstract implementation block to a Rust newtype value. */
    function valueTypeSynthetic(wrapper:TypedExpr, value:TypedExpr):String {
        final abs = ValueTypeSupport.markedAbstractOfType(wrapper.t);
        if (abs == null)
            return expr(value);
        imports.requireType(abs.module, abs.name);
        final wrapperName = abs.name;
        final locals = valueTypeLocalValues(wrapper);
        final activeAbs = currentClass == null ? null : ValueTypeSupport.markedAbstractOfClass(currentClass);
        final activeField = activeAbs != null
            && currentMethodName != null ? ValueTypeSupport.memberField(activeAbs, currentMethodName) : null;
        final nativeOperator = activeAbs != null
            && activeField != null
            && ValueTypeSupport.sameAbstract(activeAbs, abs)
            && ValueTypeSupport.operatorOf(abs, activeField) != null;
        return switch (stripWrap(value).expr) {
            case TBinop(op, left, right):
                final field = ValueTypeSupport.binaryOperatorField(abs, op);
                if (field == null) expr(value) else {
                    final asRepresentation = nativeOperator && field.name == currentMethodName;
                    final rendered = valueTypeOperand(left, locals, abs, asRepresentation) + " " + opStr(op) + " "
                        + valueTypeOperand(right, locals, abs, asRepresentation);
                    nativeOperator
                    && field.name == currentMethodName ? wrapperName + "(" + rendered + ")" : rendered;
                }
            case TUnop(op, _, subject):
                final field = ValueTypeSupport.unaryOperatorField(abs, op);
                if (field == null) expr(value) else {
                    final asRepresentation = nativeOperator && field.name == currentMethodName;
                    final rendered = "-" + valueTypeOperand(subject, locals, abs, asRepresentation);
                    nativeOperator
                    && field.name == currentMethodName ? wrapperName + "(" + rendered + ")" : rendered;
                }
            case _: wrapperName + "(" + expr(value) + ")";
        };
    }

    function valueTypeLocalValues(wrapper:TypedExpr):Map<Int, TypedExpr> {
        final values:Map<Int, TypedExpr> = [];
        switch (wrapper.expr) {
            case TBlock(stmts):
                for (stmt in stmts)
                    switch (stmt.expr) {
                        case TVar(v, init) if (init != null && !StringTools.startsWith(v.name, "this")): values.set(v.id, init);
                        case _:
                    }
            case _:
        }
        return values;
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
        final alreadyRepresentation = switch (stripWrap(value).expr) {
            case TLocal(v) if (subst.exists(v.id) && StringTools.endsWith(subst.get(v.id), ".0")): true;
            case _: false;
        };
        return asRepresentation && wrapperOperand && !alreadyRepresentation ? rendered + ".0" : rendered;
    }

    function enumQuery(e:TypedExpr):Null<String> {
        switch (e.expr) {
            case TField(subj, fa):
                final name = switch (fa) {
                    case FInstance(_, _, cf) | FAnon(cf): cf.get().name;
                    case FDynamic(n): n;
                    case _: "";
                };
                final en = EnumQueryExpander.collectionEnum(subj);
                if (name == "length" && en != null)
                    return Std.string(EnumQueryExpander.constructorCount(en));
            case TArray(subj, index):
                final en = EnumQueryExpander.collectionEnum(subj);
                if (en != null) {
                    if (EnumQueryExpander.aliasEnum(subj) != null)
                        return expr(subj) + "[" + expr(index) + "]";
                    requireEnum(en.module, en.name);
                    return en.name + "::ALL[" + expr(index) + "]";
                }
            case _:
        }
        final kind = EnumQueryExpander.markerKind(e);
        if (kind == null)
            return null;
        final en = EnumQueryExpander.enumOf(e);
        final args = EnumQueryExpander.callArgs(e);
        requireEnum(en.module, en.name);
        return switch (kind) {
            case QCollection: en.name + "::ALL";
            case QName: expr(args[0]) + ".name()";
            case QLookup: en.name + "::from_name(&(" + expr(args[1]) + "))";
        };
    }

    // ------------------------------------------------------------------
    // Variant switches and try regions (features/01, features/06)
    // ------------------------------------------------------------------

    function isTryRegion(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TTry(_, catches): catches.length == 1;
            case _: false;
        };
    }

    /** True when the expression is an enum switch over variant indices. */
    function isVariantSwitch(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TSwitch(_, _, _): true;
            case _: false;
        };
    }

    /** Return-position variant switch: the match value returns through the function edge. */
    function matchReturnLines(sw:TypedExpr, depth:Int):Array<String> {
        final lines = matchExpression(sw).split("\n");
        final out = [indent(depth) + (isFallible ? "return Ok(" : "return ") + lines[0]];
        for (i in 1...lines.length) {
            out.push(indent(depth) + lines[i]);
        }
        out[out.length - 1] += isFallible ? ");" : ";";
        return out;
    }

    /**
        On a catch variable, the payload field of the exception class (the
        enum-typed field whose enum the region catches) reads as the bound
        enum value itself; the exception class is unavailable for this target
        (features/06 catch-site lowering).
    **/
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
                                                return RustImports.toSnakeCase(localName(v));
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

    /**
        A `message` or `get_message` read on a folded exception. The sealed
        fold keeps the Display impl as the message carrier, so any read maps
        to `format!("{}", value)` whether or not the value sits in a
        catch-variable position (features/06 message lowering). Without this,
        a read outside a catch emits the runtime-dependent `get_message()`
        accessor, which the folded enum lacks.
    **/
    function foldedExceptionMessage(subj:TypedExpr, name:String):Null<String> {
        if (name != "message" && name != "get_message") {
            return null;
        }
        switch (Context.follow(subj.t)) {
            case TInst(c, _):
                if (!RustDecl.isExceptionSubclass(c.get())) {
                    return null;
                }
                return "format!(\"{}\", " + expr(subj) + ")";
            case TEnum(en, _):
                final owner = state.payloadEnumOwners.get(en.get().module);
                if (owner == null) {
                    return null;
                }
                return "format!(\"{}\", " + expr(subj) + ")";
            case _:
                return null;
        }
    }

    /** The payload enum of the exception class a region catches, or null. */
    function caughtPayloadEnum(c:{v:TVar, expr:TypedExpr}):Null<{name:String, module:String}> {
        switch (Context.follow(c.v.t)) {
            case TInst(cls, _):
                final enumModule = state.exceptionPayloads.get(cls.get().module);
                if (enumModule == null) {
                    return null;
                }
                final name = enumModule.substr(enumModule.lastIndexOf(".") + 1);
                return {name: name, module: enumModule};
            case _:
                return null;
        }
    }

    function requireEnum(enumModule:String, enumName:String):Void {
        final emittedIn = state.payloadEnumModules.exists(enumModule) ? state.payloadEnumModules.get(enumModule) : enumModule;
        imports.requireType(emittedIn, enumName);
    }

    function freshRegionName(prefix:String):String {
        var index = 0;
        var name = prefix;
        while (usedNames.exists(name)) {
            index += 1;
            name = prefix + index;
        }
        usedNames.set(name, true);
        return name;
    }

    /**
        Renders the region body as an immediately invoked closure returning
        `Result<value, enum>`. The trailing value expression is rewrapped as a
        return so the existing fallible return edge rules (String ownership,
        Option wrapping) apply at the `Ok` tail; the fallibility flag is set
        for the closure body only, so `Ok` wrapping holds even when the
        enclosing function absorbed the domain.
    **/
    function regionClosureLines(body:TypedExpr, regionType:Null<Type>, enumName:String, depth:Int):Array<String> {
        var stmts = statementsOf(body);
        // A top-level throw ends the region: the tail after it is dead in
        // every target, so the closure stops at the throwing edge.
        for (i in 0...stmts.length) {
            switch (stmts[i].expr) {
                case TThrow(_):
                    stmts = stmts.slice(0, i + 1);
                    break;
                case _:
            }
        }
        final tail = regionTailValue(stmts);
        var bodyStmts = stmts;
        if (tail != null) {
            final rewrapped:TypedExpr = {expr: TypedExprDef.TReturn(tail), t: tail.t, pos: tail.pos};
            bodyStmts = stmts.slice(0, stmts.length - 1).concat([rewrapped]);
        }
        final savedFallible = isFallible;
        final savedError = errorTypeName;
        final savedOverflow = countOverflowVariant;
        final savedTryClosure = inTryClosure;
        isFallible = true;
        inTryClosure = true;
        errorTypeName = enumName;
        countOverflowVariant = null;
        final lines = blockLines(bodyStmts, depth, true);
        isFallible = savedFallible;
        errorTypeName = savedError;
        countOverflowVariant = savedOverflow;
        inTryClosure = savedTryClosure;
        // the forced fallible flag, and a rewrapped tail already returns it.
        return lines;
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
                isVoidType(last.t) ? null : last;
        }
    }

    function isVoidType(t:Null<Type>):Bool {
        if (t == null) {
            return true;
        }
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Void";
            case TEnum(en, _): en.get().name == "Void";
            case _: false;
        };
    }

    /** Return-position region: the match value returns through the function edge. */
    function regionReturnLines(region:TypedExpr, depth:Int):Array<String> {
        final parts = switch (stripWrap(region).expr) {
            case TTry(body, catches): {body: body, c: catches[0]};
            case _: return [fail(region, "not a try region")];
        }
        final payload = caughtPayloadEnum(parts.c);
        if (payload == null) {
            return [fail(parts.c.expr, "try region catch type carries no payload enum")];
        }
        if (regionTailValue(statementsOf(parts.body)) == null) {
            return [fail(region, "try region body has no value")];
        }
        requireEnum(payload.module, payload.name);
        final valueBinding = freshRegionName("__value");
        // The annotated return type keeps the error enum readable at the
        // closure head; handler arms alone cannot always infer it.
        final valueType = types.of(regionTailValue(statementsOf(parts.body)).t);
        final opener = "(|| -> Result<" + valueType + ", " + payload.name + "> {";
        final prefix = isFallible ? "return Ok(match " + opener : "return match " + opener;
        final out = [indent(depth) + prefix];
        for (l in regionClosureLines(parts.body, region.t, payload.name, depth + 1))
            out.push(l);
        out.push(indent(depth) + (isFallible ? "})() {" : "})() {"));
        out.push(indent(depth) + "    Ok(" + valueBinding + ") => " + valueBinding + ",");
        catchVars.set(parts.c.v.id, true);
        final arm = armBlock(parts.c.expr);
        catchVars.remove(parts.c.v.id);
        for (i in 0...arm.length) {
            final suffix = i == arm.length - 1 ? "," : "";
            out.push(indent(depth) + "    Err(" + RustImports.toSnakeCase(localName(parts.c.v)) + ") => " + arm[i] + suffix);
        }
        out.push(indent(depth) + (isFallible ? "});" : "};"));
        return out;
    }

    /** Statement-position region: run the closure, act on the Err arm only. */
    function regionStatementLines(body:TypedExpr, c:{v:TVar, expr:TypedExpr}, depth:Int):Array<String> {
        final payload = caughtPayloadEnum(c);
        if (payload == null) {
            return [fail(c.expr, "try region catch type carries no payload enum")];
        }
        requireEnum(payload.module, payload.name);
        final outcome = freshRegionName("__outcome");
        final tail = regionTailValue(statementsOf(body));
        final valueType = tail != null ? tail.t : null;
        final out = [indent(depth)
            + 'let $outcome: Result<'
            + (valueType == null ? "()" : types.of(valueType))
            + ', '
            + payload.name
            + "> = (|| {"];
        for (l in regionClosureLines(body, valueType, payload.name, depth + 1))
            out.push(l);
        out.push(indent(depth) + "})();");
        out.push(indent(depth) + 'match $outcome {');
        out.push(indent(depth) + "    Ok(_) => {}");
        // A handler that never reads the caught value binds the wildcard.
        final catchBinding = mentionsLocal(c.expr, c.v) ? RustImports.toSnakeCase(localName(c.v)) : "_";
        out.push(indent(depth) + "    Err(" + catchBinding + ") => {");
        catchVars.set(c.v.id, true);
        final handler = blockLines(statementsOf(c.expr), depth + 2);
        catchVars.remove(c.v.id);
        for (l in handler)
            out.push(l);
        out.push(indent(depth) + "    }");
        out.push(indent(depth) + "}");
        return out;
    }

    /** Initializer-position region: the match yields the bound value. */
    function regionInitializerLines(v:TVar, region:TypedExpr, depth:Int):Array<String> {
        final parts = switch (stripWrap(region).expr) {
            case TTry(body, catches): {body: body, c: catches[0]};
            case _: return [fail(region, "not a try region")];
        }
        final payload = caughtPayloadEnum(parts.c);
        if (payload == null) {
            return [fail(parts.c.expr, "try region catch type carries no payload enum")];
        }
        if (regionTailValue(statementsOf(parts.body)) == null) {
            return [fail(region, "try region body has no value")];
        }
        requireEnum(payload.module, payload.name);
        final name = RustImports.toSnakeCase(localName(v));
        final valueBinding = freshRegionName("__value");
        final out = [
            indent(depth) + 'let $name: ' + types.of(v.t) + ' = match (|| -> Result<' + types.of(v.t) + ', ' + payload.name + '> {'
        ];
        for (l in regionClosureLines(parts.body, v.t, payload.name, depth + 1))
            out.push(l);
        out.push(indent(depth) + "})() {");
        out.push(indent(depth) + "    Ok(" + valueBinding + ") => " + valueBinding + ",");
        catchVars.set(parts.c.v.id, true);
        final arm = armBlock(parts.c.expr);
        catchVars.remove(parts.c.v.id);
        for (i in 0...arm.length) {
            final suffix = i == arm.length - 1 ? "," : "";
            out.push(indent(depth) + "    Err(" + RustImports.toSnakeCase(localName(parts.c.v)) + ") => " + arm[i] + suffix);
        }
        out.push(indent(depth) + "};");
        return out;
    }

    /**
        Renders an enum switch as a `match` expression. The typer hands the
        switch over with the subject wrapped in TEnumIndex and case values as
        construct-index constants; payload captures arrive as TEnumParameter
        initializations in the arm block, so each arm pattern binds the
        captured payloads as named fields and represents the remaining fields with `..`.
    **/
    function matchExpression(sw:TypedExpr):String {
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
        requireEnum(en.module, en.name);
        final table = new Map<Int, EnumField>();
        for (constructName => ef in en.constructs) {
            table.set(ef.index, ef);
        }
        final out = ["match " + subjStr + " {"];
        for (c in parts.cases) {
            final index = switch (c.values[0].expr) {
                case TConst(TInt(v)): v;
                case _: return fail(sw, "variant switch case is not a constant index");
            }
            final ef = table.get(index);
            if (ef == null) {
                return fail(sw, "variant switch case index has no construct");
            }
            final argCount = switch (ef.type) {
                case TFun(args, _): args.length;
                case _: 0;
            };
            // Payload captures bind as named fields of the variant pattern;
            // uncaptured payloads use `..`; unused ones use a
            // leading underscore binding.
            final subjectLocal = switch (se.expr) {
                case TLocal(l): l.id;
                case _: -1;
            };
            final captures:Array<{vid:Int, idx:Int}> = [];
            function collect(stmts:Array<TypedExpr>) {
                for (s in stmts) {
                    switch (s.expr) {
                        case TVar(v, init) if (init != null):
                            switch (stripWrap(init).expr) {
                                case TEnumParameter(se2, _, idx):
                                    switch (se2.expr) {
                                        case TLocal(l2) if (l2.id == subjectLocal):
                                            if (Lambda.find(captures, function(c) return c.idx == idx) == null) {
                                                captures.push({vid: v.id, idx: idx});
                                            }
                                        case _:
                                    }
                                // The typer binds the pattern variable from
                                // the extraction temp; usage tracking follows
                                // the pattern variable, so a payload the arm
                                // value never reads stays out of the pattern.
                                case TLocal(src):
                                    for (cap in captures) {
                                        if (cap.vid == src.id) {
                                            cap.vid = v.id;
                                        }
                                    }
                                case _:
                            }
                        case TBlock(bs):
                            collect(bs);
                        case _:
                    }
                }
            }
            collect(statementsOf(c.expr));
            function localIsRead(vid:Int):Bool {
                // TypedExprTools.iter visits direct children only, so the
                // read scan must recurse through the callback (mentionsLocal
                // pattern); payload reads sit under TVar initializers.
                var found = false;
                function scan(x:TypedExpr) {
                    switch (x.expr) {
                        case TLocal(l) if (l.id == vid):
                            found = true;
                        case _:
                    }
                    TypedExprTools.iter(x, scan);
                }
                scan(c.expr);
                return found;
            }
            final usedIndices = [for (cap in captures) if (localIsRead(cap.vid)) cap.idx];
            var lastUsed = -1;
            for (idx in usedIndices) {
                if (idx > lastUsed) {
                    lastUsed = idx;
                }
            }
            var pattern = en.name + "::" + RustImports.toUpperCamelCase(ef.name);
            if (argCount > 0) {
                final bindings:Array<String> = [];
                for (idx in 0...argCount) {
                    if (Lambda.has(usedIndices, idx)) {
                        bindings.push(payloadName(ef, idx));
                    } else if (idx < lastUsed) {
                        // An unused payload before a used one still binds,
                        // under the underscore name.
                        bindings.push("_" + payloadName(ef, idx));
                    } else {
                        // Everything from the first unused tail payload on
                        // represents the remaining fields with the rest pattern.
                        bindings.push("..");
                        break;
                    }
                }
                pattern += " { " + bindings.join(", ") + " }";
            }
            final arm = armBlock(c.expr);
            for (i in 0...arm.length) {
                final suffix = i == arm.length - 1 ? "," : "";
                out.push("    " + pattern + " => " + arm[i] + suffix);
            }
        }
        out.push("}");
        return out.join("\n");
    }

    /**
        Renders one switch arm (or one region handler in value position).
        Payload captures fold into field reads on the subject; other
        declarations stay; the trailing statement is the arm value. A
        single-expression arm renders inline, anything longer renders as a
        block.
    **/
    function armBlock(e:TypedExpr):Array<String> {
        final decls:Array<String> = [];
        var value:Null<String> = null;
        var sawReturn = false;
        function walk(stmts:Array<TypedExpr>) {
            for (s in stmts) {
                switch (s.expr) {
                    case TVar(v, init):
                        if (init == null) {
                            Context.error("rust target: declaration without initializer has no lowering", s.pos);
                        }
                        switch (stripWrap(init).expr) {
                            case TEnumParameter(_, ef, index):
                                // The variant pattern binds the payload as a
                                // named field, so the capture reads it bare.
                                subst.set(v.id, payloadName(ef, index));
                            case TLocal(source) if (subst.exists(source.id)):
                                subst.set(v.id, subst.get(source.id));
                            case _:
                                decls.push("let " + RustImports.toSnakeCase(localName(v)) + " = " + expr(init) + ";");
                        }
                    case TBlock(bs):
                        walk(bs);
                    case TMeta(_, inner):
                        walk([inner]);
                    case TReturn(_):
                        sawReturn = true;
                    case _:
                        value = expr(s);
                        if (isStringType(e.t) && isStringLiteral(s))
                            value = value + ".to_string()";
                }
            }
        }
        walk(statementsOf(e));
        if (sawReturn) {
            return [fail(e, "return inside a value arm lowers at statement position only")];
        }
        var valueText = value;
        if (value != null && isStringType(e.t) && isStringLiteral(e)) {
            valueText = value + ".to_string()";
        }
        if (decls.length == 0) {
            return [valueText];
        }
        final out = ["{"];
        for (d in decls) {
            out.push("    " + d);
        }
        out.push("    " + valueText);
        out.push("}");
        return out;
    }

    function isStringType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().name == "String";
            case _: false;
        };
    }

    function borrowedStringLoopItem(e:TypedExpr):Null<TVar> {
        return switch (stripWrap(e).expr) {
            case TLocal(v): borrowedLoopVarIds.exists(v.id) && isStringType(v.t) ? v : null;
            default: null;
        };
    }

    function isSortedBuilder(subj:TypedExpr):Bool {
        return switch (Context.follow(subj.t)) {
            case TInst(c, _): final n = c.get().name; n == "SortedMapBuilder" || n == "SortedSetBuilder";
            case _: false;
        };
    }

    function isSortedTable(subj:TypedExpr):Bool {
        return switch (Context.follow(subj.t)) {
            case TInst(c, _): final n = c.get().name; n == "SortedMap" || n == "SortedSet";
            case _: false;
        };
    }

    function isRecordValueType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TAnonymous(_): true;
            case TType(d, _): switch (d.get().type) {
                    case TAnonymous(_): true;
                    case _: false;
                };
            case TInst(c, _): c.get().meta.has(":dataClass");
            case _: false;
        }
    }

    function isTypeCopy(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): final n = a.get().name; n == "Int" || n == "Bool" || n == "Float" || n == "Int64";
            case TAnonymous(anon):
                isAllCopy(anon.get().fields);
            case TType(d, _):
                switch (d.get().type) {
                    case TAnonymous(anon):
                        isAllCopy(anon.get().fields);
                    case _: false;
                }
            case TLazy(fn):
                isTypeCopy(fn());
            case TEnum(en, _):
                var copy = true;
                for (ef in en.get().constructs)
                    switch (Context.follow(ef.type)) {
                        case TFun(args, _) if (args.length > 0): copy = false;
                        case _:
                    }
                copy;
            case _: false;
        };
    }

    function isAllCopy(fields:Array<ClassField>):Bool {
        for (f in fields) {
            if (!isTypeCopy(f.type))
                return false;
        }
        return true;
    }

    /**
        The inner value of an Option comparison arm. A String inner must be
        owned: the Some of an Option<String> cannot hold a &str literal or a
        borrowed parameter's view.
    **/
    function optionSomeInner(e:TypedExpr):String {
        if (!isStringType(e.t))
            return expr(e);
        return switch (stripWrap(e).expr) {
            case TConst(TString(_)): expr(e) + ".to_string()";
            case TLocal(v) if (isBorrowedLocal(v)): expr(e) + ".to_string()";
            case _: expr(e);
        };
    }

    function binop(e:TypedExpr, op:Binop, l:TypedExpr, r:TypedExpr):String {
        final fromBe = tryMatchFromBeBytes(e);
        if (fromBe != null) {
            return fromBe;
        }
        switch (op) {
            case OpEq | OpNotEq if (isNullableCollapsedLocal(l) || isNullableCollapsedLocal(r)):
                return expr(l) + " " + symbolOf(op) + " " + expr(r);
            case OpEq | OpNotEq if (nullableEnumComparedWithEnum(l.t, r.t) || nullableEnumComparedWithEnum(r.t, l.t)):
                final left = isNullType(l.t) ? expr(l) : "Some(" + expr(l) + ")";
                final right = isNullType(r.t) ? expr(r) : "Some(" + expr(r) + ")";
                return left + " " + symbolOf(op) + " " + right;
            // A nullable operand compared against the null literal lowers
            // to a predicate call: Option equality against None would
            // require PartialEq on the inner type, which the emitted
            // structs do not carry.
            case OpEq | OpNotEq if (isNullType(l.t) && !isNullType(r.t) && !isTNull(r)):
                return expr(l) + " " + symbolOf(op) + " Some(" + optionSomeInner(r) + ")";
            case OpEq | OpNotEq if (isNullType(r.t) && !isNullType(l.t) && !isTNull(l)):
                return expr(r) + " " + symbolOf(op) + " Some(" + optionSomeInner(l) + ")";
            case OpEq | OpNotEq if ((isNullType(l.t) && isTNull(r)) || (isNullType(r.t) && isTNull(l))):
                final nullable = isNullType(l.t) ? l : r;
                return expr(nullable) + (op == OpEq ? ".is_none()" : ".is_some()");
            // Borrowed loop items render as references in Rust.
            case OpEq | OpNotEq if (borrowedStringLoopItem(l) != null || borrowedStringLoopItem(r) != null):
                final left = borrowedStringLoopItem(l) != null ? "*" + expr(l) : expr(l);
                final right = borrowedStringLoopItem(r) != null ? "*" + expr(r) : expr(r);
                return left + " " + symbolOf(op) + " " + right;
            case OpBoolAnd:
                final proven = provenNonNullLocal(l);
                if (proven != null) {
                    provenNonNullVarIds.set(proven.id, true);
                    final right = expr(r);
                    provenNonNullVarIds.remove(proven.id);
                    return expr(l) + " && " + right;
                }
                return expr(l) + " && " + expr(r);
            case OpAssign:
                final map = mapAssignment(l);
                if (map != null) {
                    return expr(map.receiver) + ".insert(" + rustMapKey(map.key) + ", " + rustMapValue(r) + ")";
                }
                final staticTarget = staticAssignmentTarget(l);
                if (staticTarget != null) {
                    final staticValue = if (StaticFieldHelper.isNullableType(l.t)) {
                        isTNull(r) ? "None" : "Some(" + staticOwnedValue(r) + ")";
                    } else if (StaticFieldHelper.isStringType(l.t)) {
                        staticOwnedValue(r);
                    } else {
                        expr(r);
                    };
                    return staticTarget + " = " + staticValue;
                }
                final rhs = if (isNullType(l.t) && !isNullType(r.t) && !isTNull(r)) {
                    final rStr = if (!isTypeCopy(r.t)) {
                        switch (stripWrap(r).expr) {
                            // A literal is a &str while the Null target owns
                            // Option<String>; clone does not exist on str.
                            case TConst(TString(_)): expr(r) + ".to_string()";
                            case _:
                                final s = expr(r);
                                if (!StringTools.endsWith(s, ".clone()")
                                    && !StringTools.endsWith(s, ".to_vec()")
                                    && !StringTools.endsWith(s, ".to_string()")) {
                                    s + ".clone()";
                                } else {
                                    s;
                                }
                        }
                    } else {
                        expr(r);
                    };
                    "Some(" + rStr + ")";
                } else if (isStringType(l.t) && !isNullType(l.t)) {
                    switch (stripWrap(r).expr) {
                        case TConst(TString(_)): expr(r) + ".to_string()";
                        // A String parameter renders as &str in the callee;
                        // the element slot owns its text, so the assigned
                        // value converts on the way in.
                        case TLocal(v) if (isBorrowedLocal(v)): expr(r) + ".to_string()";
                        default: expr(r);
                    }
                } else {
                    numericAssignmentValue(l.t, r, renderValueForType(l.t, r, expr(r)), i32LocalDomain(l) ? "i32" : null);
                };
                return assignTarget(l) + " = " + rhs;
            case OpAssignOp(inner):
                // Int compound assignments must preserve Haxe's 32-bit wrapping.
                final intCompound = switch (inner) {
                    case OpMult | OpAdd | OpSub
                        if (isIntType(l.t) && isLocalOrFieldTarget(l) && !isGenericLocal(l) && !isClosureParam(l) && !RustType.isTypeParam(l.t)):
                        final domain = i32LocalDomain(l) ? "i32" : types.of(l.t);
                        assignTarget(l)
                        + " = "
                        + domain
                        + "::"
                        + wrappingMethod(inner)
                        + "("
                        + assignTarget(l)
                        + ", "
                        + expr(r)
                        + ")";
                    case _: null;
                };
                if (intCompound != null)
                    return intCompound;
                // String accumulation borrows the operand: String
                // implements AddAssign<&str>, and the += desugaring makes
                // the right side a coercion site, so &(expr) accepts both
                // String expressions and literals.
                switch (inner) {
                    case OpAdd if (isStringType(l.t) && !isNullType(l.t) && isStringType(r.t) && !isNullType(r.t)):
                        return assignTarget(l) + " += &(" + expr(r) + ")";
                    case _:
                }
                return assignTarget(l) + " " + symbolOf(inner) + "= " + expr(r);
            case OpAdd if (isStringType(l.t) || isStringType(r.t)):
                final leftStd = stdStringArg(l);
                final rightStd = stdStringArg(r);
                final lStr = leftStd != null ? stdString(leftStd, true) : (isNullType(l.t) ? expr(l) + ".as_deref().unwrap_or(\"\")" : expr(l));
                final rStr = rightStd != null ? stdString(rightStd, true) : (isNullType(r.t) ? expr(r) + ".as_deref().unwrap_or(\"\")" : expr(r));
                return "format!(\"{}{}\", " + lStr + ", " + rStr + ")";
            case OpDiv if (StringTools.endsWith(operand(l, op, false), ".len()")):
                // A length divided by a Haxe-Int divisor: the divisor widens to
                // usize (T3, never truncates), the quotient is the target u32,
                // narrowed by the T4 mask.
                final lenDiv = "((" + operand(l, op, false) + ") / " + usizeIndex(operand(r, op, true)) + ")";
                return RustConversions.truncate(lenDiv, "u32");
            case OpMult | OpAdd | OpSub
                if (isIntType(e.t)
                    && !inGenericFunction
                    && !isGenericLocal(l)
                    && !isClosureParam(l)
                    && !RustType.isTypeParam(currentReturnType)
                    && !RustType.isTypeParam(e.t)
                    && !RustType.isTypeParam(l.t)
                    && !RustType.isTypeParam(r.t)):
                final wrapDomain = (i32OperandDomain(l) || i32OperandDomain(r) || i32InitializerTarget || i32ComparisonTarget) ? "i32" : types.of(e.t);
                return wrapDomain + "::" + wrappingMethod(op) + "(" + wrappingOperand(l, op, wrapDomain, true) + ", "
                    + wrappingOperand(r, op, wrapDomain, false) + ")";
            case OpMult | OpAdd | OpSub | OpDiv if (isFloatType(e.t)):
                final real = FloatPrecision.isF32() ? "f32" : "f64";
                // An integer operand crosses through its exact decimal
                // (T7), which rounds identically to `as` without a cast.
                final lStr = if (isIntType(l.t)) RustConversions.intToFloat(operand(l, op, false), real) else operand(l, op, false);
                final rStr = if (isIntType(r.t)) RustConversions.intToFloat(operand(r, op, true), real) else operand(r, op, true);
                return lStr + " " + symbolOf(op) + " " + rStr;
            case OpAnd:
                final rightInner = stripWrap(r);
                final isMask255 = switch (rightInner.expr) {
                    case TConst(TInt(255)): true;
                    case _: false;
                };
                if (isMask255) {
                    final byteExt = tryMatchByteExtract(l);
                    if (byteExt != null) {
                        return byteExt;
                    }
                }
                return (isInt64Type(l.t)
                    || isInt64Type(r.t) ? "(" + expr(l) + ") & (" + expr(r) + ")" : operand(l, op, false) + " & " + operand(r, op, true));
            case OpOr | OpXor if (isInt64Type(l.t) || isInt64Type(r.t)):
                return expr(l) + " " + symbolOf(op) + " " + expr(r);
            case OpUShr:
                // The u32 domain makes Rust >> the logical shift; operand()
                // re-adds grouping parens by precedence, so a bare shift
                // initializer carries no outer parentheses.
                return operand(l, op, false) + " >> " + operand(r, op, true);
            case OpShl:
                // Rust parses an unparenthesized cast immediately followed by
                // `<` as generic arguments (`x as u32 << y`), the same trap the
                // comparison case below groups around.  operand() decides by
                // precedence alone, which lets a path-call shift RHS through
                // bare (`as u32 << u32::wrapping_add(...)`), so group both
                // operands unconditionally.
                return "(" + operand(l, op, false) + ") << (" + operand(r, op, true) + ")";
            case OpLt if (isZero(r) && (isUnsignedOperand(l) || businessIntExpr(l))):
                return "(" + operand(l, op, false) + ") > 2147483647";
            case OpSub:
                return operand(l, op, false) + " - " + operand(r, op, true);
            case OpLt | OpLte | OpGt | OpGte:
                // Rust std implements PartialOrd only between equal string
                // types: String compares with &str through PartialEq but
                // not PartialOrd, so an ordered string comparison moves
                // every owned operand to its str view first.
                if (isStringType(l.t) && isStringType(r.t)) {
                    return "(" + stringOrderOperand(l) + ") " + symbolOf(op) + " (" + stringOrderOperand(r) + ")";
                }
                // Rust parses an unparenthesized cast immediately followed by
                // `<` as generic arguments (`x as u32 < y`).  Comparisons are
                // a precedence boundary, so group both operands unconditionally.
                // Signed-domain locals make arithmetic on the other side signed.
                final signedComparison = i32LocalDomain(l) || i32LocalDomain(r);
                if (signedComparison)
                    i32ComparisonTarget = true;
                final leftText = operand(l, op, false);
                final rightText = operand(r, op, true);
                if (signedComparison)
                    i32ComparisonTarget = false;
                return "(" + leftText + ") " + symbolOf(op) + " (" + rightText + ")";

            case _:
                final left = isInt64Type(l.t) ? "(" + expr(l) + ")" : operand(l, op, false);
                final right = isInt64Type(r.t) ? "(" + expr(r) + ")" : operand(r, op, true);
                return left + " " + symbolOf(op) + " " + right;
        }
    }

    /**
        One operand of an ordered string comparison. A literal and a
        borrowed &str parameter already render as a str view; every other
        String expression is owned and moves to its str view through
        as_str, so both sides compare as str.
    **/
    function stringOrderOperand(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TConst(TString(_)): expr(e);
            case TLocal(v) if (isBorrowedLocal(v)): expr(e);
            case _: "(" + expr(e) + ").as_str()";
        };
    }

    function nullableEnumComparedWithEnum(nullable:Type, value:Type):Bool {
        if (!isNullType(nullable))
            return false;
        return switch (Context.follow(getNullInnerType(nullable))) {
            case TEnum(_, _): switch (Context.follow(value)) {
                    case TEnum(_, _): true;
                    case _: false;
                };
            case _: false;
        };
    }

    function provenNonNullLocal(e:TypedExpr):Null<TVar> {
        final inner = stripWrap(e);
        return switch (inner.expr) {
            case TBinop(OpNotEq, left, right):
                switch [stripWrap(left).expr, stripWrap(right).expr] {
                    case [TLocal(v), _] if (isTNull(right)): v;
                    case [_, TLocal(v)] if (isTNull(left)): v;
                    case _: null;
                };
            case _: null;
        };
    }

    function isZero(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(0)): true;
            case _: false;
        };
    }

    function isUnderflowProneIntExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TBinop(OpSub, value, amount):
                switch ([stripWrap(value).expr, stripWrap(amount).expr]) {
                    case [TField(_, FInstance(_, _, field)), TConst(TInt(k))] if (field.get().name == "length" && k > 0): true;
                    case _: false;
                }
            case _: false;
        };
    }

    /**
        Haxe Int reaches Rust as u32 for values and usize for byte positions, so
        a negative-domain check can only be expressed as an upper-bound check on
        those operands; signed operands keep the literal comparison.
    **/
    function isUnsignedOperand(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): unsignedLocals.exists(v.id) || (paramVarIds.exists(v.id)
                    && isUnsignedTypeName(argTypes.get(v.name))) || (isIntType(v.t) && !RuntimeResidents.isResident(imports.selfModule));
            case _: false;
        };
    }

    /**
        Whether a Haxe Int expression renders in the business u32 domain:
        a negative test against literal zero must then read as an
        upper-bound check on the unsigned rendering.
    **/
    function businessIntExpr(e:TypedExpr):Bool {
        if (!isIntType(e.t) || RuntimeResidents.isResident(imports.selfModule))
            return false;
        if (i32OperandDomain(e) || i32LocalDomain(e))
            return false;
        return true;
    }

    function isUnsignedTypeName(n:Null<String>):Bool {
        return n == "u16" || n == "u32" || n == "usize";
    }

    function operand(e:TypedExpr, parent:Binop, isRight:Bool):String {
        var rendered = expr(e);
        // Null<Int> is represented as Option<u32>. Haxe permits it to enter
        // numeric expressions; the target contract uses zero for the absent
        // value, consistently at every arithmetic operand boundary.
        if (isNullType(e.t) || isStringCharCodeAtCall(e)) {
            switch (stripWrap(e).expr) {
                case TCall(fn, _) if (isStringCharCodeAt(fn)):
                    rendered += ".unwrap_or(0)";
                case _:
            }
        }
        switch (e.expr) {
            case TBinop(op, _, _):
                final cp = precedenceOf(op);
                final pp = precedenceOf(parent);
                var parens = cp < pp || (cp == pp && (!associative(op) || isRight));
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
                return "!" + inner;
            case OpNeg:
                return "-" + inner;
            case OpIncrement:
                return post ? "({ let t = " + inner + "; " + inner + " += 1; t })" : "({ " + inner + " += 1; " + inner + " })";
            case OpDecrement:
                return post ? "({ let t = " + inner + "; " + inner + " -= 1; t })" : "({ " + inner + " -= 1; " + inner + " })";
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

    function int64Call(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        return int64CallText(fn, args);
    }

    /**
        Folds an integer-literal `as` cast into a typed literal, matching the
        bitwise result of `(x) as T` for the module's integer domain. Returns
        null when `e` is not an integer constant, so the caller falls back to a
        runtime cast. A Haxe Int literal is the signed i32 value; the business-
        module u32 rendering is its low 32 bits, so widening casts of such a
        literal are the unsigned decimal and a cast to i32 is the signed value.
        The same v + 4294967296 arithmetic the bare literal renderer uses (in
        `expr` for a negative business constant) yields that unsigned decimal.
        Resident modules keep the signed rendering.
    **/
    function constantCast(e:TypedExpr, ty:String):Null<String> {
        switch (stripWrap(e).expr) {
            case TConst(TInt(v)):
                if (ty == "u64") {
                    // A resident negative i32 constant casts with sign extension,
                    // which the emitter never requests (Int64 and sha literals are
                    // positive domain constants), so fall back to a runtime cast
                    // for that rare case.
                    if (RuntimeResidents.isResident(imports.selfModule) && v < 0)
                        return null;
                }
                final unsigned = v < 0 ? Std.string(v + 4294967296) : Std.string(v);
                // The folded literal is a typed integer literal, whose precedence
                // binds as tightly as any parenthesized atom, so it can stand
                // bare wherever `(x) as T` used to stand without altering
                // precedence or triggering unnecessary-parens warnings.
                switch (ty) {
                    case "u32": return unsigned + "u32";
                    case "i32": return v + "i32";
                    case "i64":
                        if (RuntimeResidents.isResident(imports.selfModule))
                            return v + "i64";
                        return unsigned + "i64";
                    case "u64": return unsigned + "u64";
                    case "usize": return unsigned + "usize";
                    case "u8": return (v & 0xFF) + "u8";
                    case "u16": return (v & 0xFFFF) + "u16";
                    case "f64": return unsigned + ".0";
                    case "f32": return unsigned + ".0f32";
                    default: return null;
                }
            default:
                return null;
        }
    }

    /**
        A Float-domain Math argument. The typer widens an Int operand to
        the Float parameter implicitly; rust needs the explicit crossing.
        A bare int literal stays as written because rust infers it into
        the parameter type, keeping existing trees unchanged.
    **/
    function mathFloatArg(a:TypedExpr):String {
        if (!isIntType(a.t)) {
            return expr(a);
        }
        return switch (stripWrap(a).expr) {
            case TConst(TInt(_)): expr(a);
            case _: RustConversions.intToFloat(expr(a), FloatPrecision.isF32() ? "f32" : "f64");
        };
    }

    /** Folds an integer-constant cast to a typed literal, else renders the runtime cast. */
    function castArg(e:TypedExpr, ty:String):String {
        final folded = constantCast(e, ty);
        if (folded != null)
            return folded;
        if (ty == "usize") {
            // Index positions reach Rust as usize from a Haxe Int (u32)
            // source; the T3 form preserves every representable value and
            // never truncates, so it is allowed wherever the old `as usize`
            // index stood. usize::try_from(u32) always succeeds, making the
            // unwrap_or(0) arm unreachable.
            return usizeIndex(expr(e));
        }
        if (ty == "u8") {
            // A u8 target (Bytes element stores) truncates the source the
            // way Rust `as u8` does: mask the low byte, then try_from. The
            // literal fold above has already run, so only real expressions
            // reach this branch.
            return RustConversions.truncate(expr(e), "u8");
        }
        return "(" + expr(e) + ") as " + ty;
    }

    /** T3 index form for an already-rendered source expression. */
    function usizeIndex(rendered:String):String {
        // The call parentheses already delimit the argument, so an outer
        // grouping of the rendered source (a block expression, a parenthesized
        // binop) is dropped to keep the generated code free of
        // unnecessary-parens warnings.
        var inner = rendered;
        if (StringTools.startsWith(inner, "(") && StringTools.endsWith(inner, ")") && matchingParens(inner)) {
            inner = inner.substr(1, inner.length - 2);
        }
        return "usize::try_from(" + inner + ").unwrap_or(0)";
    }

    /**
        Reinterpret a same-width u32-domain business value into the signed i32
        position a resident runtime parameter expects. Folds a literal to its
        signed value; otherwise goes through the native-endian byte round-trip
        (T5). This is the drop-in for the `(x) as i32` cast on such boundaries.
    **/
    function castSignedI32(e:TypedExpr):String {
        final folded = constantCast(e, "i32");
        if (folded != null)
            return folded;
        // In a resident module Haxe Int is already i32, so `(x) as i32` is a
        // no-op and the expression renders bare (this keeps integer locals
        // inferable). In a business module the value is u32 and the same-width
        // cast reinterprets bits (T5).
        if (RuntimeResidents.isResident(imports.selfModule))
            return expr(e);
        // A generic static call's return type is inferred from its context;
        // `.to_ne_bytes()` alone leaves it ambiguous (E0689), so an
        // annotated binding pins the u32 domain before the byte round-trip.
        if (genericStaticCallArg(e)) {
            return "{ let v: u32 = " + expr(e) + "; i32::from_ne_bytes(v.to_ne_bytes()) }";
        }
        return RustConversions.reinterpret(expr(e), "i32");
    }

    /** Casts an Int shift count to u32 (a no-op in business, reinterpret in resident). */
    function castShiftU32(e:TypedExpr):String {
        final folded = constantCast(e, "u32");
        if (folded != null)
            return folded;
        if (RuntimeResidents.isResident(imports.selfModule))
            return RustConversions.reinterpret(expr(e), "u32");
        return expr(e);
    }

    function int64CallText(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        function topClass(e:TypedExpr):Int {
            return switch (stripWrap(e).expr) {
                case TCall(callee, _): switch (stripWrap(callee).expr) {
                        case TField(_, FStatic(c, f)) if (c.get().module == "haxe.Int64" && c.get().name == "Int64_Impl_"):
                            switch (f.get().name) {
                                case "make" | "or": 1;
                                case "xor": 2;
                                case "and": 3;
                                case "ofInt" | "getLow" | "get_low" | "getHigh" | "get_high" | "ushr": 90;
                                case _: 100;
                            };
                        case _: 100;
                    };
                case TBinop(op, _, _): switch (op) {
                        case OpOr: 1;
                        case OpXor: 2;
                        case OpAnd: 3;
                        case _: 100;
                    };
                case _: 100;
            };
        }
        function infixOperand(e:TypedExpr, parentClass:Int):String {
            final text = expr(e);
            return topClass(e) < parentClass ? "(" + text + ")" : text;
        }
        function receiverOperand(e:TypedExpr):String {
            final text = expr(e);
            return topClass(e) == 100 ? text : "(" + text + ")";
        }
        function castOperand(e:TypedExpr, ty:String):String {
            final folded = constantCast(e, ty);
            if (folded != null)
                return folded;
            return "(" + expr(e) + ") as " + ty;
        }

        /** T2 widen of a u32-domain word into i64 (positive), folding literals. */
        function widenI64(e:TypedExpr):String {
            final folded = constantCast(e, "i64");
            if (folded != null)
                return folded;
            return "i64::from(" + expr(e) + ")";
        }

        /** Sign-extends a Haxe Int to i64 (Int64.ofInt). */
        function signExtendI64(e:TypedExpr):String {
            switch (stripWrap(e).expr) {
                case TConst(TInt(v)):
                    // `(x as i32) as i64` of a literal is its signed value.
                    return v + "i64";
                default:
            }
            if (RuntimeResidents.isResident(imports.selfModule)) {
                return "i64::from(" + expr(e) + ")";
            }
            return RustConversions.ofInt(expr(e));
        }

        return switch (stripWrap(fn).expr) {
            case TField(_, FStatic(classRef, fieldRef)) if (classRef.get().module == "haxe.Int64" && classRef.get().name == "Int64_Impl_"):
                switch (fieldRef.get().name) {
                    case "make" if (args.length == 2): widenI64(args[0]) + " << 32 | " + widenI64(args[1]);
                    case "ofInt" if (args.length == 1): signExtendI64(args[0]);
                    case "getHigh" | "get_high" if (args.length == 1): if (isFpHelperInt64Halves(args[0])) expr(args[0]) + ".high" else
                            RustConversions.truncate("("
                            + receiverOperand(args[0]) + " >> 32)", "u32");
                    case "getLow" | "get_low" if (args.length == 1): if (isFpHelperInt64Halves(args[0])) expr(args[0]) + ".low" else
                            RustConversions.truncate(expr(args[0]), "u32");
                    case "add" if (args.length == 2): receiverOperand(args[0]) + ".wrapping_add(" + expr(args[1]) + ")";
                    case "sub" if (args.length == 2): receiverOperand(args[0]) + ".wrapping_sub(" + expr(args[1]) + ")";
                    case "mul" if (args.length == 2): "(" + expr(args[0]) + ").wrapping_mul(" + expr(args[1]) + ")";
                    case "mulInt" if (args.length == 2): "(" + expr(args[0]) + ").wrapping_mul(i64::from(" + expr(args[1]) + "))";
                    case "and" if (args.length == 2): infixOperand(args[0], 3) + " & " + infixOperand(args[1], 3);
                    case "or" if (args.length == 2): infixOperand(args[0], 1) + " | " + infixOperand(args[1], 1);
                    case "xor" if (args.length == 2): infixOperand(args[0], 2) + " ^ " + infixOperand(args[1], 2);
                    case "complement" if (args.length == 1): "!" + expr(args[0]);
                    case "shl" if (args.length == 2): receiverOperand(args[0]) + ".wrapping_shl(" + castShiftU32(args[1]) + ")";
                    case "shr" if (args.length == 2): receiverOperand(args[0]) + ".wrapping_shr(" + castShiftU32(args[1]) + ")";
                    case "ushr" if (args.length == 2): RustConversions.shrLogicalI64(expr(args[0]), castShiftU32(args[1]));
                    case "eq" if (args.length == 2): expr(args[0]) + " == " + expr(args[1]);
                    case "neq" if (args.length == 2): expr(args[0]) + " != " + expr(args[1]);
                    case "lt" if (args.length == 2): expr(args[0]) + " < " + expr(args[1]);
                    case "gt" if (args.length == 2): expr(args[0]) + " > " + expr(args[1]);
                    case "lte" if (args.length == 2): expr(args[0]) + " <= " + expr(args[1]);
                    case "gte" if (args.length == 2): expr(args[0]) + " >= " + expr(args[1]);
                    default: null;
                }
            default: null;
        };
    }

    function isFpHelperInt64Halves(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _): isFpHelperInt64Call(fn);
            case TLocal(v): fpInt64Halves.exists(v.id);
            case _: false;
        };
    }

    function isFpHelperInt64Call(fn:TypedExpr):Bool {
        return switch (stripWrap(fn).expr) {
            case TField(_, FStatic(classRef, fieldRef)): classRef.get()
                    .module == "haxe.io.FPHelper" && (fieldRef.get().name == "doubleToI64" || fieldRef.get().name == "f32ToI64");
            case _: false;
        };
    }

    function field(subj:TypedExpr, fa:FieldAccess):String {
        switch (fa) {
            case FStatic(c, cf):
                final cls = c.get();
                final name = cf.get().name;
                if (isLazyStaticField(cls, name) && !StaticFieldHelper.isSelfConstruction(cf.get(), cls)) {
                    return "&*" + staticItemPath(cls, name);
                }
                if (isGuardStaticField(cls, name)) {
                    if (StaticFieldHelper.isConstruction(cf.get().expr()) && !StaticFieldHelper.isSelfConstruction(cf.get(), cls)) {
                        return "&*" + staticItemPath(cls, name);
                    }
                    final guard = staticGuard(cls, name);
                    return StaticFieldHelper.isArrayType(cf.get().type) ? guard : guard + ".clone()";
                }
                final rendered = staticRef(cls, name);
                if (StaticFieldHelper.isArrayType(cf.get().type))
                    return rendered + ".to_vec()";
                return StaticFieldHelper.isStringType(cf.get().type) ? rendered + ".to_string()" : rendered;
            case FEnum(e, ef):
                final en = e.get();
                imports.requireType(en.module, en.name);
                return en.name + "::" + RustImports.toUpperCamelCase(ef.name);
            case FInstance(_, _, cf) | FAnon(cf):
                final name = cf.get().name;
                final folded = foldedExceptionMessage(subj, name);
                if (folded != null) {
                    return folded;
                }
                {
                    final bound = catchPayloadAccess(subj, name);
                    if (bound != null) {
                        return bound;
                    }
                }
                if (name == "message" || name == "get_message") {
                    switch (stripWrap(subj).expr) {
                        case TLocal(v) if (catchVars.exists(v.id)):
                            // Display carries the message text of the variant
                            // (features/06: messages are display text).
                            return "format!(\"{}\", " + RustImports.toSnakeCase(localName(v)) + ")";
                        case _:
                    }
                }
                final staticGuard = staticGuardOf(subj);
                if (staticGuard != null) {
                    if (name == "length") {
                        return rustU32Length(staticGuard + ".len()");
                    }
                    return staticGuard + "." + RustImports.toSnakeCase(name);
                }
                if (name == "length") {
                    if (isNullType(subj.t)) {
                        return "(" + expr(subj) + ").as_ref().map_or(0, |v| v.len())";
                    }
                    if (isStringBuf(subj)) {
                        return RustConversions.truncate(expr(subj) + ".len()", "u32");
                    }
                    // Resident modules keep the signed Int domain: their
                    // lengths join index arithmetic, so the read narrows
                    // here the way UStringPlatform end inlines.
                    if (RuntimeResidents.isResident(imports.selfModule)) {
                        return RustConversions.narrowI32("(" + expr(subj) + ").len()");
                    }
                    if (isString(subj)) {
                        state.shimsUsed.set("std.UStringRT", true);
                        imports.require("crate::runtime::u_string");
                        return "u_string::count(&(" + expr(subj) + "))";
                    }
                    if (i32ComparisonTarget)
                        return "(" + RustConversions.narrowI32("(" + expr(subj) + ").len()") + ")";
                    final receiver = expr(subj);
                    final receiverText = StringTools.startsWith(receiver, "&*") ? "(" + receiver + ")" : receiver;
                    return RustConversions.truncate(receiverText + ".len()", "u32");
                }
                final snake = RustImports.toSnakeCase(name);
                final subjStr = if (isNullType(subj.t)) expr(subj) + ".as_ref().unwrap()" else expr(subj);
                final access = subjStr + "." + snake;
                if (name != "length" && isConstructedStaticRead(subj) && StaticFieldHelper.isStringType(cf.get().type))
                    return "(" + access + ").to_string()";
                if (name != "length" && isConstructedStaticRead(subj) && !isTypeCopy(cf.get().type))
                    return "(" + access + ").clone()";
                if (name != "length" && isNullType(cf.get().type)) {
                    // `Std.string` and string comparisons observe nullable values;
                    // preserve Option. Do not treat it as Display.
                    return access;
                }
                if (name != "length" && (isStringType(cf.get().type) || isRecordValueType(cf.get().type))) {
                    return isStringType(cf.get().type) ? "(" + access + ").to_string()" : "(" + access + ").clone()";
                }
                return access;
            case FDynamic(name):
                if ((name == "length" || name == "get_length") && isStringBuf(subj)) {
                    return RustConversions.truncate(expr(subj) + ".len()", "u32");
                }
                return fail(subj, "dynamic field access has no lowering");
            case FClosure(_):
                return fail(subj, "closure has no lowering");
        }
    }

    function staticFieldOf(cls:ClassType, name:String):Null<ClassField> {
        for (field in cls.statics.get()) {
            if (field.name == name) {
                return field;
            }
        }
        return null;
    }

    function isLazyStaticField(cls:ClassType, name:String):Bool {
        final field = staticFieldOf(cls, name);
        return field != null && (StaticFieldHelper.isConstruction(field.expr()) || isLazyArrayStaticField(field));
    }

    function isLazyArrayStaticField(field:ClassField):Bool {
        final init = StaticFieldHelper.initializer(field);
        return field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init) && !StaticFieldHelper.isIntLiteralArray(init);
    }

    function isDirectArrayStaticField(field:ClassField):Bool {
        final init = StaticFieldHelper.initializer(field);
        return field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init) && StaticFieldHelper.isIntLiteralArray(init);
    }

    function isLazyArrayReceiver(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(c, cf)): isLazyArrayStaticField(cf.get());
            case _: false;
        };
    }

    function isGuardStaticField(cls:ClassType, name:String):Bool {
        final field = staticFieldOf(cls, name);
        return field != null
            && ValueTypeSupport.markedAbstractOfClass(cls) == null
            && StaticFieldHelper.initializer(field) != null
            && !StaticFieldHelper.isConstValue(field)
            && !DataTableHelper.isDataTableField(field)
            && !isDirectArrayStaticField(field)
            && !isLazyArrayStaticField(field)
            && (!StaticFieldHelper.isConstruction(field.expr()) || StaticFieldHelper.isSelfConstruction(field, cls));
    }

    function staticItemPath(cls:ClassType, name:String):String {
        final itemName = RustImports.toScreamingSnakeCase(name);
        return cls.module == imports.selfModule ? itemName : "crate::" + RustImports.moduleToRustPath(cls.module) + "::" + itemName;
    }

    function staticGuard(cls:ClassType, name:String):String {
        return staticItemPath(cls, name) + ".lock().unwrap_or_else(|e| e.into_inner())";
    }

    function staticGuardOf(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(c, cf)) if (isGuardStaticField(c.get(), cf.get().name)):
                staticGuard(c.get(), cf.get().name);
            case _: null;
        };
    }

    function staticIndex(e:TypedExpr):String {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(value)): Std.string(value) + "usize";
            case _:
                "match usize::try_from(" + expr(e) + ") { Ok(value) => value, Err(_) => 0usize }";
        };
    }

    function rustU32Length(length:String):String {
        return "match u32::try_from(" + length + ") { Ok(value) => value, Err(_) => u32::MAX }";
    }

    function staticAssignmentTarget(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TField(_, FStatic(c, cf)) if (isGuardStaticField(c.get(), cf.get().name)):
                "*" + staticGuard(c.get(), cf.get().name);
            case _: null;
        };
    }

    function isConstructedStaticRead(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TField(_,
                FStatic(c, cf)) if (StaticFieldHelper.isConstruction(cf.get().expr())
                    && !StaticFieldHelper.isSelfConstruction(cf.get(), c.get())): true;
            case _: false;
        };
    }

    function staticOwnedValue(e:TypedExpr):String {
        final rendered = expr(e);
        if (StaticFieldHelper.isConstruction(e))
            return rendered;
        if (StaticFieldHelper.isStringType(e.t)) {
            if (rendered.indexOf("&*") >= 0)
                return rendered + ".to_string()";
            return StringTools.endsWith(rendered, ".to_string()")
                || StringTools.endsWith(rendered, ".clone()") ? rendered : rendered + ".to_string()";
        }
        if (!isTypeCopy(e.t) && !StringTools.endsWith(rendered, ".clone()") && !StringTools.endsWith(rendered, ".to_vec()")) {
            return rendered + ".clone()";
        }
        return rendered;
    }

    function staticContainerArg(e:TypedExpr):String {
        final rendered = expr(e);
        if (StaticFieldHelper.isConstruction(e))
            return rendered;
        if (StaticFieldHelper.isArrayType(e.t))
            return rendered + ".to_vec()";
        if (StaticFieldHelper.isStringType(e.t) && !StringTools.endsWith(rendered, ".clone()")) {
            return rendered + ".to_string()";
        }
        return rendered;
    }

    function isFunctionType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TFun(_, _): true;
            case _: false;
        };
    }

    function staticFunctionName(name:String):String {
        return RustImports.toScreamingSnakeCase(name);
    }

    function staticRef(cls:ClassType, name:String):String {
        final staticField = findStaticField(cls, name);
        final staticName = staticField != null
            && staticField.isFinal ? RustImports.toSnakeCase(name).toUpperCase() : RustImports.toSnakeCase(name);
        final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
        if (valueType != null) {
            imports.requireType(valueType.module, valueType.name);
            return valueType.name + "::" + RustImports.toScreamingSnakeCase(name);
        }
        final markedField = findStaticField(cls, name);
        if (markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
            final nativeName = RustImports.toSnakeCase(name);
            if (markedField.isPublic) {
                imports.requireType(cls.module, nativeName);
            }
            return nativeName;
        }
        final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
        switch (path) {
            case "String":
                return "String::" + RustImports.toSnakeCase(name);
            case "Math":
                // The f32 configuration renders the whole Math family from f32, the
                // binary32 equivalent of every static (feature spec 23).
                final real = FloatPrecision.isF32() ? "f32" : "f64";
                if (name == "NaN")
                    return real + "::NAN";
                if (name == "POSITIVE_INFINITY")
                    return real + "::INFINITY";
                if (name == "NEGATIVE_INFINITY")
                    return real + "::NEG_INFINITY";
                return real + "::" + RustImports.toSnakeCase(name);
            case _ if (RustTestBinding.isTestExtern(cls)):
                state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                if (name == "run") {
                    imports.require("crate::runtime::test as testlib");
                    return "testlib::run";
                }
                imports.require("crate::runtime::test_core");
                return "test_core::TestCore::" + RustImports.toSnakeCase(name);
            case "std.UStringRT":
                return uStringRef(name);
            case "std.Graphemes":
                // The extern fronts the resident runtime module
                // runtime.Graphemes, compiled into graphemes.rs; the
                // reference names the struct and calls its methods.
                state.shimsUsed.set("std.Graphemes", true);
                if (name == "boundaries" && !RuntimeResidents.isResident(imports.selfModule)) {
                    // The boundary vector crosses whole between the two
                    // Int domains; the adapter in graphemes.rs casts each
                    // element once, because Array results have no
                    // call-site cast machinery (RuntimeResidents).
                    imports.require("crate::runtime::graphemes");
                    return "graphemes::boundaries";
                }
                imports.requireType("runtime.Graphemes", "Graphemes");
                return "Graphemes::" + RustImports.toSnakeCase(name);
            case "StringTools":
                // StringTools statics without a native Rust/String inline
                // lowering (lpad, rpad, ltrim, rtrim, replace, ...) route
                // into the runtime module, mirroring the Kotlin target.
                // The inline-lowered ones (hex, trim, startsWith,
                // endsWith) are handled before staticRef. A resident
                // caller addresses the compiled class directly; a business
                // caller goes through the adapter module (RuntimeResidents).
                state.shimsUsed.set("StringTools", true);
                if (RuntimeResidents.isResident(imports.selfModule)) {
                    imports.requireType("runtime.StringTools", "StringTools");
                    return "StringTools::" + RustImports.toSnakeCase(name);
                }
                imports.require("crate::runtime::string_tools");
                return "string_tools::StringTools::" + RustImports.toSnakeCase(name);
            case _:
                if (RustTestBinding.isTestExtern(cls)) {
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    if (name == "run") {
                        imports.require("crate::runtime::test as testlib");
                        return "testlib::run";
                    }
                    imports.require("crate::runtime::test_core");
                    return "test_core::TestCore::" + RustImports.toSnakeCase(name);
                }
                if (cls.module == "std.UStringRT") {
                    return uStringRef(name);
                }
                if (cls.module == "std.Graphemes") {
                    state.shimsUsed.set("std.Graphemes", true);
                    if (name == "boundaries" && !RuntimeResidents.isResident(imports.selfModule)) {
                        // Same routing as the path arm above: the boundary
                        // vector crosses whole, so the business caller
                        // reaches the element-casting adapter.
                        imports.require("crate::runtime::graphemes");
                        return "graphemes::boundaries";
                    }
                    imports.requireType("runtime.Graphemes", "Graphemes");
                    return "Graphemes::" + RustImports.toSnakeCase(name);
                }
                for (field in cls.statics.get()) {
                    if (field.name == name && field.kind.match(FVar(_, _)) && isFunctionType(field.type)) {
                        final targetName = staticFunctionName(name);
                        if (cls.module != imports.selfModule) {
                            imports.requireType(cls.module, targetName);
                        }
                        return targetName;
                    }
                }
                for (field in cls.statics.get()) {
                    if (field.name == name && DataTableHelper.isDataTableField(field)) {
                        if (cls.module == imports.selfModule) {
                            return RustImports.toScreamingSnakeCase(name);
                        }
                    }
                }
                if (markedField != null && (isDirectArrayStaticField(markedField) || isLazyArrayStaticField(markedField))) {
                    return staticItemPath(cls, name);
                }
                // The typer renders an @:native extern class under its
                // native name (console, process) even when its
                // declaration name differs; the emitted shim keeps the
                // declaration's module name (Console, Process). A
                // Pascal-case name is already the declaration name and
                // stays untouched.
                final first = cls.name.length > 0 ? cls.name.charAt(0) : "?";
                final nativeLower = first >= "a" && first <= "z";
                final structName = nativeLower ? cls.module.substr(cls.module.lastIndexOf(".") + 1) : RustImports.emittedTypeName(cls.name);
                if (cls.module != "" && StringTools.endsWith(cls.name, "_Impl_")) {
                    // A sub-type abstract's non-inline static (for example
                    // `FontId::of`) lowers to the synthetic implementation's
                    // `_Impl_`. The call site names that symbol, so
                    // compileClassImpl must not drop the referenced `_Impl_`
                    // even though ordinary synthetic impls never emit.
                    state.referencedImpls.set(cls.module, true);
                }
                imports.requireType(cls.module, structName);
                return structName + "::" + staticName;
        }
    }

    function findStaticField(cls:ClassType, name:String):Null<ClassField> {
        for (field in cls.statics.get()) {
            if (field.name == name)
                return field;
        }
        return null;
    }

    /**
        Reference to the UString runtime through the std.UStringRT extern.
        A resident caller addresses the compiled class directly and shares
        its i32 convention; a business caller goes through the u32 adapter
        free functions emitted beside the class, because Null and Array
        results have no call-site cast machinery (RuntimeResidents).
     */
    function uStringRef(name:String):String {
        state.shimsUsed.set("std.UStringRT", true);
        if (RuntimeResidents.isResident(imports.selfModule)) {
            imports.requireType("runtime.UString", "UString");
            return "UString::" + RustImports.toSnakeCase(name);
        }
        imports.require("crate::runtime::u_string");
        return "u_string::" + RustImports.toSnakeCase(name);
    }

    function typeExpr(t:ModuleType):String {
        switch (t) {
            case TClassDecl(c):
                final cls = c.get();
                if (cls.pack.length == 0 && (cls.name == "String" || cls.name == "Math")) {
                    return cls.name;
                }
                if (RustTestBinding.isTestExtern(cls)) {
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    imports.require("crate::runtime::test as testlib");
                    return "testlib";
                }
                imports.requireType(cls.module, RustImports.emittedTypeName(cls.name));
                return RustImports.emittedTypeName(cls.name);
            case TEnumDecl(e):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                final name = owner != null ? owner : en.name;
                imports.requireType(en.module, name);
                return name;
            case _:
                Context.error("type expression has no value lowering", Context.currentPos());
                return null;
        }
    }

    function stdString(arg:TypedExpr, inConcat:Bool):String {
        return stdStringType(arg.t, expr(arg), inConcat, arg);
    }

    function stdIsOfType(args:Array<TypedExpr>):String {
        final target = TypeCheckHelper.classOfTypeExpr(args[1]);
        if (target == null) {
            Context.error("Std.isOfType requires a class type expression", args[1].pos);
            return "false";
        }
        final known = TypeCheckHelper.knownIsOfType(args[0], target);
        if (known != null) {
            return known ? "true" : "false";
        }
        return expr(args[0]) + ".__haxe_type_name() == \"" + target.module + "." + target.name + "\"";
    }

    function stdStringType(t:Type, value:String, inConcat:Bool, origin:TypedExpr, depth:Int = 0):String {
        // Context.follow unwraps Null<T> into T, so the switch below never
        // sees the wrapper; a nullable operand takes the match form here,
        // before the follow.
        switch (t) {
            case TAbstract(a, [inner]) if (a.get().name == "Null"):
                return "match "
                    + value
                    + " { Some(ref v) => "
                    + stdStringType(inner, "v", false, origin, depth + 1)
                    + ", None => \"null\".to_string() }";
            case _:
        }
        return switch (Context.follow(t)) {
            case TInst(c, _) if (c.get().name == "String"):
                inConcat ? value : value + ".to_string()";
            case TInst(c, [element]) if (c.get().name == "Array"):
                imports.require("std::fmt::Write");
                final index = depth == 0 ? "i" : "i" + depth;
                final item = stdStringType(element, value + "[" + index + "]", true, origin, depth + 1);
                '{ let mut out = String::new(); out.push(\'[\'); let n = ${value}.len(); let mut ${index} = 0usize; while ${index} < n { if ${index} > 0 { out.push_str(", "); } let _ = write!(out, "{}", ${item}); ${index} += 1; } out.push(\']\'); out }';
            case TInst(c, [element]) if (c.get().module == "std.SortedSet"):
                imports.require("std::fmt::Write");
                final index = depth == 0 ? "i" : "i" + depth;
                final item = stdStringType(element, value + ".at(" + index + ")", true, origin, depth + 1);
                '{ let mut out = String::new(); out.push(\'[\'); let n = ${value}.size(); let mut ${index} = 0; while ${index} < n { if ${index} > 0 { out.push_str(", "); } let _ = write!(out, "{}", ${item}); ${index} += 1; } out.push(\']\'); out }';
            case TInst(c, [key, val]) if (c.get().module == "std.SortedMap"):
                imports.require("std::fmt::Write");
                final index = depth == 0 ? "i" : "i" + depth;
                final itemKey = stdStringType(key, value + ".key_at(" + index + ")", true, origin, depth + 1);
                final itemVal = stdStringType(val, value + ".value_at(" + index + ")", true, origin, depth + 1);
                '{ let mut out = String::new(); out.push(\'{\'); let n = ${value}.size(); let mut ${index} = 0; while ${index} < n { if ${index} > 0 { out.push_str(", "); } let _ = write!(out, "{}={}", ${itemKey}, ${itemVal}); ${index} += 1; } out.push(\'}\'); out }';
            case TInst(c, _) if (c.get().kind.match(KTypeParameter(_))):
                state.memberPrintsTypeParam = true;
                "format!(\"{:?}\", " + value + ")";
            case TInst(c, _) if (StaticFieldHelper.hasSelfConstructionStatic(c.get())
                || c.get().meta.has(":dataClass")): value + ".to_string()";
            case TInst(c, _) if (hasInstanceToString(c.get())): value + ".to_string()";
            case TAbstract(a, _) if (ValueTypeSupport.isMarkedAbstract(a.get())):
                ValueTypeSupport.memberField(a.get(), "toString") != null ? value + ".to_string()" : value + ".0.to_string()";
            case TAbstract(a, _) if (a.get().name == "Null"):
                "match " + value + " { Some(v) => v.to_string(), None => \"null\".to_string() }";
            case TAbstract(a, _) if (a.get().name == "Float"):
                inConcat ? value : "crate::runtime::test_core::TestCore::format_float(" + value + ")";
            case TAbstract(a, _) if (a.get().name == "Int" || a.get().name == "Bool"): inConcat ? value : "(" + value + ").to_string()";
            case TAbstract(a, params) if (a.get().module == "std.ReadOnlyArray"):
                stdStringType(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params), value, inConcat, origin, depth);
            case TEnum(en, _) if (isParameterlessEnum(en.get())):
                EnumQueryExpander.requireNameRead(en.get());
                value + ".name()" + (inConcat ? "" : ".to_string()");
            case TEnum(en, _) if (EnumCycleDetector.isCyclic(en.get())): cyclicEnumString(en.get(), value, inConcat, origin);
            case TEnum(_, _): value + ".to_string()";
            case _:
                Context.error("Std.string accepts scalars, enum values, records, and arrays of them only", origin.pos);
                null;
        };
    }

    function hasInstanceToString(cls:ClassType):Bool {
        for (field in cls.fields.get())
            if (field.name == "toString")
                return true;
        if (cls.superClass == null)
            return false;
        return hasInstanceToString(cls.superClass.t.get());
    }

    function cyclicEnumString(en:EnumType, value:String, inConcat:Bool, origin:TypedExpr):String {
        final key = en.module + ":" + en.name;
        final existing = enumStringHelpers.get(key);
        if (existing != null)
            return existing + "(&" + value + ")";
        final name = RustImports.toSnakeCase("stdString" + en.name) + enumStringHelperCounter++;
        enumStringHelpers.set(key, name);
        final body = payloadEnumString(en, "v", false, origin);
        enumStringHelpers.remove(key);
        return "{ fn " + name + "(v: &" + en.name + ") -> String { " + body + " } " + name + "(&" + value + ") }";
    }

    function payloadEnumString(en:EnumType, value:String, inConcat:Bool, origin:TypedExpr):String {
        final fields = [for (ef in en.constructs) ef];
        fields.sort((a, b) -> Reflect.compare(a.index, b.index));
        final arms:Array<String> = [];
        for (ef in fields) {
            final args = switch (ef.type) {
                case TFun(a, _): a;
                case _: [];
            };
            if (args.length == 0)
                arms.push(en.name + "::" + RustImports.toUpperCamelCase(ef.name) + " => \"" + ef.name + "\".to_string()");
            else {
                var text = "format!(\"" + ef.name + "(";
                for (i in 0...args.length)
                    text += (i == 0 ? "" : ", ") + args[i].name + "={}";
                text += ")\", " + [for (a in args) stdStringType(a.t, a.name, true, origin)].join(", ") + ")";
                arms.push(en.name + "::" + RustImports.toUpperCamelCase(ef.name) + " { " + [for (a in args) a.name].join(", ") + " } => " + text);
            }
        }
        return "match " + value + " { " + arms.join(", ") + " }";
    }

    function isParameterlessEnum(en:EnumType):Bool {
        for (ef in en.constructs)
            switch (ef.type) {
                case TFun(args, _) if (args.length > 0):
                    return false;
                case _:
            }
        return true;
    }

    function stdStringArg(e:TypedExpr):Null<TypedExpr> {
        return switch (stripWrap(e).expr) {
            case TCall({expr: TField(_, FStatic(c, cf))}, args) if (c.get().module == "Std" && cf.get().name == "string" && args.length == 1): args[0];
            case _: null;
        };
    }

    function stringToolsHex(args:Array<TypedExpr>):String {
        final value = args[0];
        final digits = args.length > 1 && !isTNull(args[1]) ? args[1] : null;
        if (isNegativeIntLiteral(value) || (digits != null && isNegativeIntLiteral(digits))) {
            Context.error("StringTools.hex accepts non-negative arguments only", value.pos);
        }
        final valueText = expr(value);
        if (digits == null) {
            return "format!(\"{:X}\", " + valueText + ")";
        }
        return "format!(\"{:0w$X}\", " + valueText + ", w = usize::try_from(" + expr(digits) + ").unwrap_or_default())";
    }

    function isNegativeIntLiteral(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TInt(value)): value < 0;
            case TUnop(OpNeg, _, inner):
                switch (stripWrap(inner).expr) {
                    case TConst(TInt(value)): value > 0;
                    case _: false;
                }
            case _: false;
        };
    }

    /** Routes calls on a marked abstract implementation to Rust members. */
    function valueTypeCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        switch (stripWrap(fn).expr) {
            case TField(_, FStatic(c, cf)):
                final abs = ValueTypeSupport.markedAbstractOfClass(c.get());
                if (abs == null)
                    return null;
                final field = cf.get();
                if (field.name == "_new") {
                    imports.requireType(abs.module, abs.name);
                    final rendered = ctorCallArgs(c.get(), args);
                    if (ValueTypeSupport.constructorThrows(abs)) {
                        final call = abs.name + "::new(" + rendered + ")";
                        return call + (isFallible ? "?" : ".unwrap()");
                    }
                    return abs.name + "(" + rendered + ")";
                }
                if (field.name == "toString" && args.length > 0)
                    return expr(args[0]) + ".to_string()";
                final op = ValueTypeSupport.operatorOf(abs, field);
                if (op != null) {
                    return switch (op) {
                        case Binary(_): args.length >= 2 ? expr(args[0]) + " " + opStrForValue(op) + " " + expr(args[1]) : abs.name;
                        case Unary(_): args.length > 0 ? "-" + expr(args[0]) : abs.name;
                    };
                }
                if (ValueTypeSupport.hasReceiver(field) && args.length > 0) {
                    return expr(args[0])
                        + "."
                        + RustImports.toSnakeCase(field.name)
                        + "("
                        + [for (i in 1...args.length) expr(args[i])].join(", ") + ")";
                }
                return abs.name + "::" + RustImports.toSnakeCase(field.name) + "(" + [for (a in args) expr(a)].join(", ") + ")";
            case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
                final abs = ValueTypeSupport.markedAbstractOfType(subj.t);
                if (abs == null)
                    return null;
                final name = cf.get().name;
                return name == "toString" ? expr(subj) + ".to_string()" : expr(subj)
                    + "."
                    + RustImports.toSnakeCase(name)
                    + "("
                    + [for (a in args) expr(a)].join(", ") + ")";
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
                final folded = foldedExceptionMessage(stripCast(subj), "get_message");
                if (folded != null) {
                    return folded;
                }
            case TField(subj, FStatic(c, cf)):
                final cls = c.get();
                final name = cf.get().name;
                final path = cls.pack.join(".") + "." + cls.name;
                final markedField = findStaticField(cls, name);
                if (markedField != null && StaticFunctionMarkers.isMarked(markedField)) {
                    final isOwnedExtension = StaticFunctionMarkers.isExtension(markedField)
                        && RustDecl.isCrateOwnedReceiver(cls.module, args[0].t);
                    final isStaticFallible = isFallibleCallee(c, cf, true);
                    final q = isFallible ? (isStaticFallible ? "?" : "") : (isStaticFallible ? ".unwrap()" : "");
                    if (isOwnedExtension) {
                        final receiver = expr(args[0]);
                        final receiverText = StringTools.startsWith(receiver, "*") ? "(" + receiver + ")" : receiver;
                        return receiverText
                            + "."
                            + RustImports.toSnakeCase(name)
                            + "("
                            + renderCallArgs(cf.get().type, args.slice(1), null, 1, mutableParamPositions(cf.get()))
                            + ")"
                            + q;
                    }
                    return staticRef(cls, name) + "(" + renderCallArgs(cf.get().type, args, null, 0, mutableParamPositions(cf.get())) + ")" + q;
                }
                if ((cls.name == "Functional" || cls.name == "__functional_shim" || path == "std.Functional" || cls.module == "std.Functional")
                    && name == "sortedBy") {
                    final receiver = args[0];
                    final lambda = args[1];
                    final func = unwrapLambda(lambda);
                    if (func != null && func.args.length == 1) {
                        final paramName = RustImports.toSnakeCase(func.args[0].v.name);
                        final keyExpr = expr(lambdaBody(func.expr));
                        return "{\n    let mut _sorted = " + expr(receiver) + ".to_vec();\n    _sorted.sort_by_key(|" + paramName + "| " + keyExpr
                            + ");\n    _sorted\n}";
                    }
                }
            case _:
        }
        final inlineMapCall = mapHasOwnPropertyCall(fn, args);
        if (inlineMapCall != null) {
            return inlineMapCall;
        }
        final renderedArgs = [for (a in args) expr(a)].join(", ");
        switch (fn.expr) {
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "alloc" && args.length == 1):
                return "vec![0u8; " + castArg(args[0], "usize") + "]";
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "ofString" && args.length == 1):
                return expr(args[0]) + ".as_bytes().to_vec()";
            case TField(_, FStatic(c, cf)) if (c.get().module == "haxe.io.Bytes" && cf.get().name == "concat" && args.length == 2):
                return "{ let mut v = " + expr(args[0]) + ".to_vec(); v.extend_from_slice(&" + expr(args[1]) + "); v }";
            case TCast(inner, _):
                return call(inner, args);
            case TField(subj, FDynamic(name)) if ((name == "length" || name == "get_length") && isStringBuf(subj)):
                return RustConversions.truncate(expr(subj) + ".len()", "u32");
            case TField(subj, FInstance(c, _, cf)):
                final name = cf.get().name;
                final staticGuard = staticGuardOf(subj);
                if (staticGuard != null) {
                    if (name == "push" && args.length == 1) {
                        return staticGuard + ".push(" + staticContainerArg(args[0]) + ")";
                    }
                    if (name == "length" || name == "get_length") {
                        return rustU32Length(staticGuard + ".len()");
                    }
                }
                if (isString(subj)) {
                    if (name == "toLowerCase")
                        return expr(subj) + ".to_lowercase()";
                    if (name == "toUpperCase")
                        return expr(subj) + ".to_uppercase()";
                }
                final snake = RustImports.toSnakeCase(name);
                if (isMapType(subj.t)) {
                    if (name == "exists" && args.length == 1)
                        return expr(subj) + ".contains_key(&" + rustMapKey(args[0]) + ")";
                    if (name == "get" && args.length == 1)
                        return expr(subj) + ".get(&" + rustMapKey(args[0]) + ").cloned()";
                    if (name == "set" && args.length == 2)
                        return expr(subj) + ".insert(" + rustMapKey(args[0]) + ", " + rustMapValue(args[1]) + ")";
                }
                if (isStringBuf(subj)) {
                    // stdlib/08: add and addChar lower only as statements,
                    // because the pairing check leaves through `return Err`.
                    if (name == "add") {
                        return fail(subj, "string buffer add has no expression lowering: keep the mutation a statement inside a fallible function (stdlib/08)");
                    }
                    if (name == "addChar") {
                        return fail(subj,
                            "string buffer addChar has no expression lowering: keep the mutation a statement inside a fallible function (stdlib/08)");
                    }
                    if (name == "toString") {
                        final fault = stringBufFaultEnum();
                        if (fault == null) {
                            return fail(subj, "string buffer checks require std.UStringException in the module set (stdlib/08)");
                        }
                        // The unit vector keeps the buffer well-formed up to
                        // a trailing lead, so from_utf16 fails exactly on
                        // that lead and the map_err names it. The `?` or
                        // `.unwrap()` rides the ordinary fallibility rules.
                        final q = isFallible ? "?" : ".unwrap()";
                        return "String::from_utf16(" + expr(subj) + ".as_slice()).map_err(|_| " + fault + "::UnpairedSurrogate { unit: u32::from("
                            + expr(subj) + "[" + expr(subj) + ".len() - 1]) })" + q;
                    }
                    if (name == "get_length" || name == "length") {
                        return RustConversions.truncate(expr(subj) + ".len()", "u32");
                    }
                }
                if (name == "get" && isBytes(stripCast(subj))) {
                    // A Bytes element is u8; widening to the module's Haxe
                    // Int domain (u32 in business, i32 in resident) goes
                    // through From so the read carries no `as`.
                    final intDomain = RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
                    return intDomain + "::from(" + expr(subj) + "[" + castArg(args[0], "usize") + "])";
                }
                if (name == "set" && args.length == 2 && isBytes(stripCast(subj))) {
                    return expr(subj) + "[" + castArg(args[0], "usize") + "] = " + castArg(args[1], "u8");
                }
                if (name == "blit" && args.length == 4 && isBytes(stripCast(subj))) {
                    return expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[3]) + ")")
                        + "].copy_from_slice(&"
                        + expr(args[1])
                        + "["
                        + castArg(args[2], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[2]) + " + " + expr(args[3]) + ")")
                        + "])";
                }
                if (name == "fill" && args.length == 3 && isBytes(stripCast(subj))) {
                    return expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[1]) + ")")
                        + "].fill("
                        + castArg(args[2], "u8")
                        + ")";
                }
                if (name == "sub" && args.length == 2 && isBytes(stripCast(subj))) {
                    return expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[1]) + ")")
                        + "].to_vec()";
                }
                if (name == "getString" && args.length == 2 && isBytes(stripCast(subj))) {
                    return "String::from_utf8_lossy(&"
                        + expr(subj)
                        + "["
                        + castArg(args[0], "usize")
                        + ".."
                        + usizeIndex("(" + expr(args[0]) + " + " + expr(args[1]) + ")")
                        + "]).into_owned()";
                }
                if (name == "charAt" && isString(stripCast(subj))) {
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    // The exclusive end is the index plus one in the same
                    // integer domain as the start. A bare `(index) + 1`
                    // rendered source is an untyped {integer} literal when
                    // index is one (E0689), so the end arrives as a typed
                    // wrapping add on the start's cast form instead.
                    return "u_string::substring(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", i32::wrapping_add(" + castSignedI32(args[0]) + ", 1)"
                        + ")";
                }
                if (name == "indexOf" && isString(stripCast(subj)) && args.length >= 1) {
                    return "match ("
                        + expr(subj)
                        + ").find("
                        + expr(args[0])
                        + ") { Some(v) => "
                        + RustConversions.narrowI32("v")
                        + ", None => -1 }";
                }
                if (name == "charCodeAt" && isString(stripCast(subj))) {
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    // The call site's own expression decides: a Null<Int>
                    // context keeps the Option and an Int context unwraps it.
                    var callRet:Null<Type> = null;
                    switch (Context.follow(fn.t)) {
                        case TFun(_, r): callRet = r;
                        case _:
                    }
                    final nullableResult = callRet != null && isNullType(callRet);
                    var callRet:Null<Type> = null;
                    switch (Context.follow(fn.t)) {
                        case TFun(_, r): callRet = r;
                        case _:
                    }
                    final nullableResult = callRet != null && isNullType(callRet);
                    return nullableResult ? "u_string::at(&" + expr(subj) + ", " + castShiftU32(args[0]) + ")" : "u_string::at(&"
                        + expr(subj)
                        + ", "
                        + castShiftU32(args[0])
                        + ").unwrap_or(0)";
                }
                if (name == "split" && isString(stripCast(subj)) && args.length == 1) {
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    return "u_string::split(&" + expr(subj) + ", &" + expr(args[0]) + ")";
                }
                if (name == "substring" && isString(stripCast(subj))) {
                    // Member-call lowering into the u_string runtime: the
                    // bounds are UTF-16 units on every target, so the call
                    // converts them to byte boundaries. The runtime keeps
                    // i32 bounds for the same clamping reason as
                    // u_string.slice (SIGNED_SHIM_PARAMS), and the subject
                    // borrows like every u_string call. An omitted
                    // ?endIndex reaches this arm as a null argument and
                    // routes to the one-sided form.
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    final endOmitted = args.length < 2 || switch (stripWrap(args[1]).expr) {
                        case TConst(TNull): true;
                        case _: false;
                    };
                    if (!endOmitted) {
                        return "u_string::substring(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", " + castSignedI32(args[1]) + ")";
                    }
                    return "u_string::substring_from(&" + expr(subj) + ", " + castSignedI32(args[0]) + ")";
                }
                if (name == "substr" && isString(stripCast(subj))) {
                    // Member-call lowering into the u_string runtime:
                    // UTF-16 units bound the cut on every target, a
                    // negative pos counts from the end of the unit
                    // sequence, and an omitted ?len reaches this arm as
                    // a null argument and routes to None.
                    state.shimsUsed.set("std.UStringRT", true);
                    imports.require("crate::runtime::u_string");
                    final lenOmitted = args.length < 2 || switch (stripWrap(args[1]).expr) {
                        case TConst(TNull): true;
                        case _: false;
                    };
                    if (!lenOmitted) {
                        return "u_string::substr(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", Some(" + castSignedI32(args[1]) + "))";
                    }
                    return "u_string::substr(&" + expr(subj) + ", " + castSignedI32(args[0]) + ", None)";
                }
                if (name == "put" && isSortedBuilder(subj)) {
                    // Builder puts borrow every argument; the resident
                    // clones into storage, so the call-site expressions
                    // stay alive.
                    final putArgs = [for (a in args) sortedRefArg(a)];
                    return expr(subj) + ".put(" + putArgs.join(", ") + ")";
                }
                if ((name == "get" || name == "has") && (isSortedTable(subj) || isSortedBuilder(subj))) {
                    return expr(subj) + "." + name + "(" + sortedRefArg(args[0]) + ")";
                }
                if (name == "size" && isSortedTable(subj)) {
                    // The resident counts in its signed Int domain; the business
                    // domain is unsigned, so the read reinterprets the raw i32.
                    return RustConversions.reinterpret(expr(subj) + ".size()", "u32");
                }
                if ((name == "keyAt" || name == "valueAt" || name == "at") && isSortedTable(subj)) {
                    return expr(subj) + "." + RustImports.toSnakeCase(name) + "(" + castSignedI32(args[0]) + ")";
                }
                if (name == "put" && isSortedBuilder(subj)) {
                    final kExpr = switch (args[0].expr) {
                        case TConst(TString(_)): expr(args[0]);
                        case TLocal(_) | TField(_):
                            if (!isTypeCopy(args[0].t)) {
                                expr(args[0]) + ".clone()";
                            } else {
                                expr(args[0]);
                            }
                        case _: expr(args[0]);
                    };
                    if (args.length > 1) {
                        final vExpr = if (isStringType(args[1].t)) {
                            switch (args[1].expr) {
                                case TConst(TString(_)): expr(args[1]) + ".to_string()";
                                case _: expr(args[1]) + ".clone()";
                            }
                        } else {
                            expr(args[1]);
                        };
                        return expr(subj) + ".put(" + kExpr + ", " + vExpr + ")";
                    } else {
                        return expr(subj) + ".put(" + kExpr + ")";
                    }
                }
                if ((name == "get" || name == "has") && (isSortedTable(subj) || isSortedBuilder(subj))) {
                    final kExpr = if (isStringType(args[0].t)) {
                        switch (args[0].expr) {
                            case TConst(TString(_)): expr(args[0]);
                            case TLocal(v):
                                final pt = types.of(v.t, true);
                                if (pt == "&str") expr(args[0]); else "&" + expr(args[0]);
                            case _: expr(args[0]);
                        }
                    } else if (!isTypeCopy(args[0].t)) {
                        "&" + expr(args[0]);
                    } else {
                        expr(args[0]);
                    };
                    return expr(subj) + "." + name + "(" + kExpr + ")";
                }
                if (name == "push") {
                    return expr(subj) + ".push(" + renderPushArg(args[0]) + ")";
                }
                if (name == "join") {
                    return expr(subj) + ".join(" + renderedArgs + ")";
                }
                if (name == "addByte") {
                    return expr(subj) + ".add_byte(" + RustConversions.truncate(expr(args[0]), "u8") + ")";
                }
                if (name == "add") {
                    return expr(subj) + ".add(&" + expr(args[0]) + ")";
                }
                if (name == "readU16") {
                    // The wire read answers u16 while the Int domain is
                    // u32; the widening is total, so from covers every
                    // value the field can hold. The read is fallible, so
                    // the call propagates before the widening.
                    return "u32::from(" + expr(subj) + ".read_u16()?)";
                }
                if (name == "writeU16") {
                    // The Int domain is u32 while the wire field is u16;
                    // the Haxe writer masks to the low half, and the Rust
                    // cast truncates identically, so the narrowing matches
                    // source semantics for every value.
                    return expr(subj) + ".write_u16(" + RustConversions.truncate(expr(args[0]), "u16") + ")";
                }
                if (name == "writeU32") {
                    final innerArg = stripWrap(args[0]);
                    final isLen = switch (innerArg.expr) {
                        case TField(_, fa) if (fieldName(fa) == "length"): true;
                        case _: false;
                    };
                    if (isLen) {
                        if (errorTypeName == null || countOverflowVariant == null) {
                            Context.error("cannot lower length conversion: missing error enum or overflow variant", args[0].pos);
                            return "";
                        }
                        final errVariant = errorTypeName + "::" + countOverflowVariant;
                        return expr(subj) + ".write_u32(u32::try_from(" + expr(args[0]) + ").map_err(|_| " + errVariant + ")?)";
                    }
                    return expr(subj) + ".write_u32(" + expr(args[0]) + ")";
                }
                if (name == "writeAscii") {
                    // A heap String argument borrows as &str; string
                    // literals and parameters of the enclosing function
                    // already render as &str.
                    final argStr = if (isStringType(args[0].t)) {
                        switch (stripWrap(args[0]).expr) {
                            case TConst(TString(_)): expr(args[0]);
                            case TLocal(v) if (paramVarIds.get(v.id) == true): expr(args[0]);
                            case _: expr(args[0]) + ".as_str()";
                        }
                    } else {
                        expr(args[0]);
                    };
                    return expr(subj) + ".write_ascii(" + argStr + ")";
                }
                if (cf != null && cf.get().kind.match(FVar(_, _)) && Context.follow(cf.get().type).match(TFun(_, _))) {
                    // A function-typed field calls through a parenthesized
                    // receiver: the field itself names the callee, so the
                    // read renders as an explicit field access in the
                    // parenthesized position. Method fields (FMethod) take
                    // the ordinary method-call path above this branch.
                    // Parameter-typed arguments borrow unless the local
                    // already holds a reference (a borrowed parameter of
                    // the enclosing function).
                    return "(" + expr(subj) + "." + snake + ")(" + renderCallArgs(cf.get().type, args) + ")";
                }
                final isMethodFallible = isFallibleCallee(c, cf, false);
                final q = isFallible ? (isMethodFallible ? errorPropagationSuffix(c, cf, false) : "") : (isMethodFallible ? ".unwrap()" : "");
                final subjStr = isNullType(subj.t) ? expr(subj) + ".as_ref().unwrap()" : expr(subj);
                return subjStr + "." + snake + "(" + renderCallArgs(cf.get().type, args, null, 0, mutableParamPositions(cf.get())) + ")" + q;
            case TField(_, FStatic(c, cf)):
                final cls = c.get();
                final name = cf.get().name;
                final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
                if (cls.pack.length == 0 && cls.name == "StringTools" && name == "hex") {
                    return stringToolsHex(args);
                }
                if (cls.pack.length == 0 && cls.name == "StringTools" && name == "trim" && args.length == 1) {
                    return expr(args[0]) + ".trim()";
                }
                if (cls.pack.length == 0
                    && cls.name == "StringTools"
                    && (name == "startsWith" || name == "endsWith")
                    && args.length == 2) {
                    return "(" + expr(args[0]) + ")." + RustImports.toSnakeCase(name) + "(&" + expr(args[1]) + ")";
                }
                if (cls.pack.length == 0 && cls.name == "Lambda" && name == "has" && args.length == 2) {
                    return "(" + expr(args[0]) + ").contains(&" + expr(args[1]) + ")";
                }
                if (cls.pack.length == 0 && cls.name == "Std" && name == "int") {
                    // An Int-typed argument converts nothing, except a
                    // bare length read, whose rendering is usize.
                    if (isIntType(args[0].t) && !isUsizeExpr(args[0])) {
                        return expr(args[0]);
                    }
                    // Haxe types Int/Int division as Float but truncates it
                    // back through Std.int; the truncation is Rust integer
                    // division, so the Float round-trip drops away.
                    final truncDiv = intDivisionOf(args[0]);
                    if (truncDiv != null) {
                        return truncDiv;
                    }
                    // A length-division lowering is already a truncating
                    // integer quotient in the module domain; Std.int over it
                    // converts nothing.
                    if (isLengthDivision(args[0])) {
                        return expr(args[0]);
                    }
                    // A genuine Float argument truncates with Rust `as`
                    // saturation, reproduced bit-exactly without a cast.
                    if (RuntimeResidents.isResident(imports.selfModule)) {
                        return RustConversions.floatToI32(expr(args[0]));
                    }
                    return RustConversions.floatToU32(expr(args[0]));
                }
                if (cls.pack.length == 0 && cls.name == "String" && name == "fromCharCode") {
                    final value = expr(args[0]);
                    // A collapsed local already rendered as a plain integer;
                    // unwrap applies only to an argument that still carries Option.
                    final collapsedArg = switch (stripWrap(args[0]).expr) {
                        case TLocal(v): nullableCollapsedLocals.exists(v.id);
                        case _: false;
                    };
                    final argument = (isNullType(args[0].t) && !collapsedArg) ? "(" + value + ".unwrap_or_default())" : (StringTools.startsWith(value,
                        "(") ? value : "("
                        + value + ")");
                    final unwrapped = argument;
                    return "String::from_utf16(&[u16::try_from" + unwrapped + ".unwrap_or_default()]).unwrap_or_default()";
                }
                if (path == "std.UStringPlatform") {
                    // Cursor primitives of the resident UString walk, inlined
                    // per call: a cursor is a byte offset here, so end is the
                    // byte length, codeAt decodes the char at the offset, and
                    // advance adds that char's UTF-8 width. Business code
                    // never reaches them; it calls std.UString.
                    if (!RuntimeResidents.isResident(imports.selfModule)) {
                        Context.error("std.UStringPlatform is a resident runtime primitive; business code calls std.UString", fn.pos);
                    }
                    switch (name) {
                        case "end":
                            return RustConversions.narrowI32("(" + expr(args[0]) + ").len()");
                        case "codeAt":
                            // A char lowers to its Unicode scalar through
                            // From<char> for u32, then narrows into the
                            // resident i32 domain (values fit: scalars cap at
                            // 0x10FFFF).
                            return "i32::try_from(u32::from(" + "(" + expr(args[0]) + ")[" + castArg(args[1], "usize")
                                + "..].chars().next().unwrap_or('\\0')" + ")).unwrap_or(0)";
                        case "advance":
                            return RustConversions.narrowI32("(" + castArg(args[1], "usize") + " + (" + expr(args[0]) + ")[" + castArg(args[1], "usize")
                                + "..].chars().next().unwrap_or('\\0').len_utf8())");
                        case "substringBetween":
                            return "(" + expr(args[0]) + ")[" + castArg(args[1], "usize") + ".." + castArg(args[2], "usize") + "].to_string()";
                        case "fromCodePoint":
                            return "char::from_u32(" + RustConversions.reinterpret(expr(args[0]), "u32") + ").unwrap_or('\\0').to_string()";
                        case _:
                    }
                }
                if (RustTestBinding.isTestPlatformExtern(path)) {
                    // Host edges of the resident runtime.TestCore, inlined
                    // per call: raising is a panic, the running test id
                    // lives in the test host module of the runtime emit, and
                    // plain numbers render through to_string. Marking the
                    // test extern shim used keeps that host module emitted
                    // beside this resident. Business code never reaches
                    // these; it calls test extern.
                    if (!RuntimeResidents.isResident(imports.selfModule)) {
                        Context.error("test platform extern is a resident runtime primitive; business code calls test extern", fn.pos);
                    }
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    switch (name) {
                        case "raise":
                            return "panic!(\"{}\", " + expr(args[0]) + ")";
                        case "currentTestId":
                            return "crate::runtime::test::current_test_id()";
                        case "intToString":
                            return "(" + expr(args[0]) + ").to_string()";
                        case "floatToString":
                            return "(" + expr(args[0]) + ").to_string()";
                        case _:
                    }
                }
                if (path == "haxe.io.FPHelper") {
                    imports.requireType(cls.module, "FPHelper");
                    // The f32 configuration converts the two 64-bit value edges to their
                    // binary32 runtime variants; the 8-byte wire bit layout
                    // is untouched (feature spec 23, ruling 7).
                    final targetName = if (FloatPrecision.isF32()) {
                        if (name == "i64ToDouble")
                            "i64ToF32"
                        else if (name == "doubleToI64")
                            "f32ToI64"
                        else
                            name;
                    } else {
                        name;
                    }
                    return "FPHelper::" + RustImports.toSnakeCase(targetName) + "(" + renderedArgs + ")";
                }
                if (cls.module == "Math" && name == "isNaN")
                    return "(" + expr(args[0]) + ").is_nan()";
                if (cls.module == "Math" && name == "isFinite")
                    return "(" + expr(args[0]) + ").is_finite()";
                if (cls.module == "Math" && name == "abs")
                    return "(" + mathFloatArg(args[0]) + ").abs()";
                if (cls.module == "Math" && (name == "min" || name == "max") && args.length == 2)
                    return staticRef(cls, name) + "(" + mathFloatArg(args[0]) + ", " + mathFloatArg(args[1]) + ")";
                if (cls.module == "Std" && name == "parseFloat") {
                    final real = FloatPrecision.isF32() ? "f32" : "f64";
                    imports.require("crate::runtime::u_string");
                    return "u_string::parse_" + real + "(&(" + expr(args[0]) + "))";
                }
                if (cls.module == "Std" && name == "parseInt") {
                    imports.require("crate::runtime::u_string");
                    return "u_string::parse_i32(&(" + expr(args[0]) + "))";
                }
                if ((cls.module == "std.Process" || (cls.pack.join(".") == "std" && cls.name == "Process")) && name == "exit") {
                    imports.require("std::process::exit");
                    return "exit(" + renderedArgs + ")";
                }
                if ((path == "std.Process" || cls.module == "std.Process") && name == "args") {
                    // std.Process.args() reads the arguments of the test
                    // binary after its name (stdlib/17).
                    return "std::env::args().skip(1).collect::<Vec<String>>()";
                }
                if ((path == "std.SortedMap" || cls.module == "std.SortedMap") && name == "builder") {
                    final kType = sortedKeyType(fn);
                    final vType = sortedValueType(fn);
                    state.shimsUsed.set("std.SortedMap", true);
                    imports.requireType("runtime.SortedTable", "SortedTable");
                    return "SortedTable::map_builder::<" + types.of(kType) + ", " + types.of(vType) + ">(" + sortedComparator(kType, fn.pos) + ")";
                }
                if ((path == "std.SortedSet" || cls.module == "std.SortedSet") && name == "builder") {
                    final kType = sortedKeyType(fn);
                    state.shimsUsed.set("std.SortedSet", true);
                    imports.requireType("runtime.SortedTable", "SortedTable");
                    return "SortedTable::set_builder::<" + types.of(kType) + ">(" + sortedComparator(kType, fn.pos) + ")";
                }

                if (RustTestBinding.isTestExtern(cls)) {
                    // The assertion checks and message formatting live in the
                    // resident runtime.TestCore; this host module keeps run and
                    // its result recording. Messages are plain &str: an absent
                    // message renders as the empty string, which the canonical
                    // builder omits.
                    state.shimsUsed.set(RuntimeResidents.externsOf("runtime.TestCore")[0], true);
                    imports.require("crate::runtime::test as testlib");
                    imports.require("crate::runtime::test_core");
                    final messageArg = function(idx:Int):String {
                        return (args.length > idx && !isTNull(args[idx])) ? "&(" + expr(args[idx]) + ")" : "\"\"";
                    };
                    if (name == "ok") {
                        final cond = expr(args[0]);
                        return "test_core::TestCore::ok(" + cond + ", " + messageArg(1) + ")";
                    }
                    if (name == "fail") {
                        return "test_core::TestCore::fail(&(" + expr(args[0]) + "))";
                    }
                    if (name == "run") {
                        return "testlib::run(" + renderedArgs + ")";
                    }
                    if (name == "equals") {
                        final expectedArg = args[0];
                        final actualArg = args[1];
                        final msg = messageArg(2);
                        if (isNullType(expectedArg.t) || isNullType(actualArg.t)) {
                            final nullInner = getNullInnerType(expectedArg.t != null
                                && isNullType(expectedArg.t) ? expectedArg.t : actualArg.t);
                            final innerKind = scalarTypeKind(nullInner);
                            imports.require("crate::tests::test_helper::*");
                            switch (innerKind) {
                                case "String":
                                    final expStr = renderOptArg(expectedArg, "String");
                                    final actStr = renderOptArg(actualArg, "String");
                                    return "assert_equals_opt_string(&" + expStr + ", &" + actStr + ", " + msg + ")";
                                case "Int":
                                    final expStr = renderOptArg(expectedArg, "Int");
                                    final actStr = renderOptArg(actualArg, "Int");
                                    return "assert_equals_opt(&" + expStr + ", &" + actStr + ", " + msg + ")";
                                case _:
                            }
                        }
                        if (isScalarType(expectedArg.t)) {
                            final scalarKind = scalarTypeKind(expectedArg.t);
                            switch (scalarKind) {
                                case "Bool":
                                    return "test_core::TestCore::equals_bool(" + expr(expectedArg) + ", " + expr(actualArg) + ", " + msg + ")";
                                case "Int":
                                    // Business Int renders u32, usize in loop heads;
                                    // the resident takes i32, so both sides
                                    // reinterpret once (T5). Literals fold to
                                    // their signed value first.
                                    return "test_core::TestCore::equals_int(" + castSignedI32(expectedArg) + ", " + castSignedI32(actualArg) + ", " + msg + ")";
                                case "Float":
                                    return "test_core::TestCore::equals_float(" + expr(expectedArg) + ", " + expr(actualArg) + ", " + msg + ")";
                                case "String":
                                    return "test_core::TestCore::equals_string(&(" + expr(expectedArg) + "), &(" + expr(actualArg) + "), " + msg + ")";
                                case _:
                            }
                        }
                        // Aggregate equality
                        recordAggregateType(expectedArg.t);
                        final fnName = aggregateAssertFuncName(expectedArg.t);
                        imports.require("crate::tests::test_helper::*");
                        return fnName + "(&" + expr(expectedArg) + ", &" + expr(actualArg) + ", " + msg + ")";
                    }
                }
                final isStaticFallible = isFallibleCallee(c, cf, true);
                final q = isFallible ? (isStaticFallible ? errorPropagationSuffix(c, cf, true) : "") : (isStaticFallible ? ".unwrap()" : "");
                final shimKey = if (cls.module == "std.UStringRT") {
                    "u_string." + name;
                } else {
                    null;
                };
                var signedPositions = shimKey != null ? SIGNED_SHIM_PARAMS.get(shimKey) : null;
                final callerResident = RuntimeResidents.isResidentAbi(imports.selfModule);
                // std.UStringRT resolves by caller: residents reach the
                // i32 class, business reaches the u32 adapters, so the
                // callee convention always matches the resolved path.
                final calleeResident = cls.module == "std.UStringRT" ? callerResident : RuntimeResidents.isResidentAbi(cls.module);
                if (calleeResident) {
                    // Resident runtime modules render haxe Int as i32
                    // (their clamping contracts carry negative values),
                    // while business expressions render u32; every Int
                    // parameter casts once at the call boundary.
                    signedPositions = intParamPositions(cf.get().type);
                }
                final callStr = staticRef(cls, name)
                    + "("
                    + renderCallArgs(cf.get().type, args, signedPositions, 0, mutableParamPositions(cf.get()))
                    + ")"
                    + q;
                if (calleeResident != callerResident && returnsInt(cf.get().type)) {
                    // An Int result crosses between the two conventions;
                    // containers never cross whole, only their elements
                    // through Int-typed expressions, which the argument
                    // casts above already cover. The crossing reinterprets
                    // the same-width bits (T5).
                    return RustConversions.reinterpret(callStr, callerResident ? "i32" : "u32");
                }
                return callStr;
            case TField(subj, FEnum(e, ef)):
                final en = e.get();
                imports.requireType(en.module, en.name);
                final efArgs = switch (ef.type) {
                    case TFun(fargs, _): fargs;
                    case _: [];
                };
                final parts = [];
                for (i in 0...args.length) {
                    final argName = i < efArgs.length ? RustImports.toSnakeCase(efArgs[i].name) : "arg" + i;
                    final argType = i < efArgs.length ? efArgs[i].t : null;
                    parts.push(argName + ": " + ownedConstructorArg(argType, args[i], en));
                }
                if (parts.length == 0) {
                    return en.name + "::" + RustImports.toUpperCamelCase(ef.name);
                }
                return en.name + "::" + RustImports.toUpperCamelCase(ef.name) + " { " + parts.join(", ") + " }";
            case TConst(TSuper):
                return "super(" + renderedArgs + ")";
            case TLocal(_):
                return expr(fn) + "(" + renderCallArgs(fn.t, args) + ")";
            case _:
                return expr(fn) + "(" + renderedArgs + ")";
        }
    }

    function mutableParamPositions(cf:ClassField):Array<Int> {
        final out:Array<Int> = [];
        switch (Context.follow(cf.type)) {
            case TFun(ps, _):
                final body = cf.expr();
                if (body != null)
                    for (i in 0...ps.length)
                        if (RustDecl.argIsMutated(body, ps[i].name))
                            out.push(i);
            case _:
        }
        return out;
    }

    function functionLiteral(f:TFunc, functionType:Null<Type>):String {
        final params = [for (a in f.args) RustImports.toSnakeCase(a.v.name)].join(", ");
        final previousReturnUnsigned = returnUnsigned;
        final previousReturnTypeName = returnTypeName;
        final previousReturnType = currentReturnType;
        final functionReturn = switch (functionType) {
            case null: null;
            case _: switch (Context.follow(functionType)) {
                    case TFun(_, ret): ret;
                    case _: null;
                }
        };
        returnUnsigned = functionReturn == null ? false : switch (Context.follow(functionReturn)) {
            case TAbstract(a, _) if (a.get().name == "Int"): !RuntimeResidents.isResident(imports.selfModule);
            case _: false;
        };
        returnTypeName = functionReturn == null ? null : types.of(functionReturn, false);
        currentReturnType = functionReturn;
        final previousGeneric = inGenericFunction;
        inGenericFunction = true;
        genericParamIds.clear();
        closureParamIds.clear();
        for (a in f.args) {
            closureParamIds.set(a.v.id, true);
            if (RustType.isTypeParam(a.v.t))
                genericParamIds.set(a.v.id, true);
        }
        final body = coalescingNormalizationLines(f.expr, 2, [for (a in f.args) a.v.name]).concat(blockLines(statementsOf(f.expr), 2, true));
        returnUnsigned = previousReturnUnsigned;
        returnTypeName = previousReturnTypeName;
        currentReturnType = previousReturnType;
        inGenericFunction = previousGeneric;
        return 'move |$params| {\n' + body.join("\n") + '\n}';
    }

    function functionValueLiteral(f:TFunc, functionType:Null<Type>):String {
        imports.require("std::rc::Rc");
        return "Rc::new(" + functionLiteral(f, functionType) + ")";
    }

    function functionLiteralNamed(name:String, f:TFunc, functionType:Null<Type>):String {
        final previous = currentLocalName;
        currentLocalName = name;
        final result = functionLiteral(f, functionType);
        currentLocalName = previous;
        return result;
    }

    function functionValueLiteralNamed(name:String, f:TFunc, functionType:Null<Type>):String {
        final previous = currentLocalName;
        currentLocalName = name;
        final result = functionValueLiteral(f, functionType);
        currentLocalName = previous;
        return result;
    }

    function isFallibleCallee(c:Ref<ClassType>, cf:Ref<ClassField>, isStatic:Bool):Bool {
        final name = cf.get().name;
        if (RustEmissionState.runtimeShimIsFallible(name))
            return true;
        if (name == "require" && c.get().module == "registry.Semver")
            return true;
        return state.funcErrorEnums.exists(RustEmissionState.funcKey(c.get().module, name, isStatic));
    }

    function newExpr(c:Ref<ClassType>, params:Array<Type>, args:Array<TypedExpr>):String {
        final cls = c.get();
        final valueType = ValueTypeSupport.markedAbstractOfClass(cls);
        if (valueType != null) {
            imports.requireType(valueType.module, valueType.name);
            final rendered = ctorCallArgs(cls, args);
            if (ValueTypeSupport.constructorThrows(valueType)) {
                return valueType.name + "::new(" + rendered + ")" + (isFallible ? "?" : ".unwrap()");
            }
            return valueType.name + "(" + rendered + ")";
        }
        final path = cls.pack.length == 0 ? cls.name : cls.pack.join(".") + "." + cls.name;
        switch (path) {
            case "std.StringBuf" | "StringBuf":
                return "Vec::<u16>::new()";
            case "haxe.ds._Map.Map_Impl_":
                imports.require("std::collections::HashMap");
                return "HashMap::new()";
            case "haxe.io.BytesBuffer":
                imports.requireType(path, "BytesBuffer");
                return "BytesBuffer::new()";
            case "Array":
                return "Vec::new()";
            case _:
                if (args.length == 1 && state.exceptionPayloads.exists(cls.module)) {
                    return exceptionVariant(cls, args[0]);
                }
                imports.requireType(cls.module, cls.name);
                // The generic resident tables construct with explicit
                // type arguments: the empty-array arguments leave the
                // parameters otherwise unconstrained.
                final genericStr = params.length > 0 ? "::<" + [for (p in params) types.of(p)].join(", ") + ">" : "";
                // A throwing constructor lowers through the fallibility
                // machinery: `?` propagates inside a fallible function or
                // a try-region closure, and an infallible context
                // unwraps (feature spec 27).
                final ctorFallible = state.funcErrorEnums.exists(RustEmissionState.funcKey(cls.module, "new", false));
                final q = ctorFallible ? (isFallible ? "?" : ".unwrap()") : "";
                return cls.name + genericStr + "::new(" + ctorCallArgs(cls, args) + ")" + q;
        }
    }

    function isMapType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(def, params) if (def.get().pack.join(".") == "haxe" && def.get().name == "IMap" && params.length == 2): true;
            case TInst(def, _): isMapImplementation(def.get());
            case TType(def, params): def.get().pack.length == 0 && def.get().name == "Map" && params.length == 2;
            case TAbstract(def, params) if (def.get().pack.join(".") == "haxe.ds" && def.get().name == "Map" && params.length == 2): true;
            case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1): isMapType(params[0]);
            case _: false;
        };
    }

    function isMapImplementation(cls:ClassType):Bool {
        return cls.pack.join(".") == "haxe.ds" && ["StringMap", "IntMap", "ObjectMap", "HashMap"].indexOf(cls.name) >= 0;
    }

    function mapBackingReceiver(e:TypedExpr):Null<TypedExpr> {
        return switch (stripWrap(e).expr) {
            case TField(receiver, FInstance(_, _, cf)) if (cf.get().name == "h" && isMapBackingType(receiver.t)): receiver;
            case TField(receiver, FAnon(cf)) if (cf.get().name == "h" && isMapBackingType(receiver.t)): receiver;
            case _: null;
        };
    }

    function isMapBackingType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(def, _):
                final cls = def.get();
                isMapImplementation(cls);
            case _: false;
        };
    }

    function mapAssignment(e:TypedExpr):Null<{receiver:TypedExpr, key:TypedExpr}> {
        return switch (stripWrap(e).expr) {
            case TArray(arr, key):
                final receiver = mapBackingReceiver(arr);
                receiver == null ? null : {receiver: receiver, key: key};
            case _: null;
        };
    }

    function isHasOwnPropertyValue(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TField(_, FInstance(_, _, cf)) | TField(_, FAnon(cf)) if (cf.get().name == "hasOwnProperty"): true;
            case _: false;
        };
    }

    function mapHasOwnPropertyCall(fn:TypedExpr, args:Array<TypedExpr>):Null<String> {
        if (args.length != 2)
            return null;
        return switch (stripWrap(fn).expr) {
            case TField(subject, FInstance(_, _, cf)) if (cf.get().name == "call" && isHasOwnPropertyValue(subject)):
                final receiver = mapBackingReceiver(args[0]);
                receiver == null ? null : expr(receiver)
                + ".contains_key(&"
                + rustMapKey(args[1])
                + ")";
            case _: null;
        };
    }

    function rustMapKey(e:TypedExpr):String {
        final rendered = expr(e);
        return isStringType(e.t) || isStringLiteral(e) ? rendered + ".to_string()" : rendered;
    }

    function isStringLiteral(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TString(_)): true;
            case _: false;
        };
    }

    function rustMapValue(e:TypedExpr):String {
        final rendered = expr(e);
        return isStringType(e.t) ? switch (stripWrap(e).expr) {
            case TConst(TString(_)): rendered + ".to_string()";
            case _: rendered;
        } : rendered;
    }

    /**
        Constructor arguments (feature spec 27): a String parameter takes
        &str, so a heap String argument borrows through .as_str() while a
        literal keeps its own static borrowing and a parameter of the
        enclosing function is already &str (`.as_str()` on &str is
        unstable); every other parameter renders as the plain expression,
        the convention the resident tables already construct under.
    **/
    function isSelfEnumField(expected:Null<Type>, en:EnumType):Bool {
        if (expected == null)
            return false;
        return switch (Context.follow(expected)) {
            case TEnum(e, _): final t = e.get(); t.module == en.module && t.name == en.name;
            case _: false;
        };
    }

    function ownedConstructorArg(expected:Null<Type>, arg:TypedExpr, constructed:Null<EnumType> = null):String {
        var text = expr(arg);
        if (constructed != null && isSelfEnumField(expected, constructed))
            return "Box::new(" + text + ")";
        if (expected == null)
            return text;
        if (isStringType(expected) && isStringType(arg.t)) {
            if (!StringTools.endsWith(text, ".to_string()"))
                text += ".to_string()";
            return text;
        }
        if (!isTypeCopy(expected) && (StringTools.startsWith(text, "&") || isPassByRef(expected))) {
            if (!StringTools.endsWith(text, ".clone()") && !StringTools.endsWith(text, ".to_vec()"))
                text = "(" + text + ").clone()";
        }
        return text;
    }

    function ctorCallArgs(cls:ClassType, args:Array<TypedExpr>):String {
        final fnType = cls.constructor != null ? cls.constructor.get().type : null;
        final paramTypes = fnType != null ? switch (Context.follow(fnType)) {
            case TFun(pargs, _): [for (p in pargs) p.t];
            case _: [];
        } : [];
        final out:Array<String> = [];
        for (i in 0...args.length) {
            final arg = args[i];
            final argStr = expr(arg);
            if (i < paramTypes.length) {
                final pt = paramTypes[i];
                if (isNullType(pt) && isStringType(getNullInnerType(pt)) && isNullType(arg.t)) {
                    out.push(argStr + ".clone()");
                    continue;
                }
                if (isNullType(pt) && !isNullType(arg.t)) {
                    // A nullable constructor parameter takes an Option; a
                    // null literal already renders None, any other
                    // argument wraps.
                    if (argStr != "None") {
                        final inner = switch (stripWrap(arg).expr) {
                            case TConst(TString(s)): quoteString(s) + ".to_string()";
                            case _: isInterfaceType(getNullInnerType(pt)) && !isInterfaceType(arg.t) ? "Box::new(" + argStr + ")" : argStr;
                        };
                        out.push("Some(" + inner + ")");
                        continue;
                    }
                    out.push(argStr);
                    continue;
                }
                if (isInterfaceType(pt)) {
                    out.push(renderValueForType(pt, arg, argStr));
                    continue;
                }
                if (isStringType(pt) && isStringType(arg.t)) {
                    out.push(switch (stripWrap(arg).expr) {
                        case TConst(TString(_)): argStr;
                        case TLocal(v) if (paramVarIds.get(v.id) == true): argStr;
                        case _: argStr + ".as_str()";
                    });
                    continue;
                }
                final bytesParam = switch (Context.follow(pt)) {
                    case TInst(c, _): c.get().module == "haxe.io.Bytes";
                    case TType(d, _): d.get().module == "haxe.io.Bytes";
                    case _: false;
                };
                if (bytesParam) {
                    // A Bytes parameter renders as &[u8] (RustType.isParam);
                    // an owned expression (a producer call, an owned local)
                    // borrows with &, while a borrowed parameter local stays
                    // unchanged. renderCallArgs applies the same prefix at
                    // ordinary call sites.
                    final borrowedLocal = switch (stripWrap(arg).expr) {
                        case TLocal(v): isBorrowedLocal(v);
                        case _: false;
                    };
                    if (!borrowedLocal && !StringTools.startsWith(argStr, "&")) {
                        out.push("&" + argStr);
                        continue;
                    }
                }
            }
            out.push(argStr);
        }
        return out.join(", ");
    }

    function numericAssignmentValue(expected:Type, actual:TypedExpr, rendered:String, targetOverride:Null<String> = null):String {
        if (!isIntType(expected))
            return rendered;
        final target = targetOverride != null ? targetOverride : types.of(expected, false);
        if (isNullType(actual.t)) {
            final castAt = rendered.indexOf(" as ");
            final base = castAt >= 0 ? rendered.substr(0, castAt) : rendered;
            // A collapsed Null<Int> renders its inner scalar; when that
            // scalar's domain is already the assignment target the
            // unwrap alone suffices.
            if ((target == "u32" || target == "i32") && isIntType(getNullInnerType(actual.t))) {
                final innerDomain = RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
                if (innerDomain == target) {
                    // Parentheses stay only when the base carries top-level
                    // operators that would change `.unwrap_or` binding.
                    return isSimpleValueText(base) ? base + ".unwrap_or(0)" : "(" + base + ".unwrap_or(0))";
                }
            }
            return RustConversions.reinterpret("(" + base + ".unwrap_or(0))", target);
        }
        if (!isIntType(actual.t))
            return rendered;
        if (target == "u8") {
            final folded = constantCast(actual, "u8");
            if (folded != null)
                return folded;
            return RustConversions.truncate(rendered, "u8");
        }
        // The rendered source already carries the module's Int domain unless
        // an i32-domain local or a shim parameter overrides it; when source
        // and target agree, `(x) as T` is a no-op and drops away. A
        // byte-extract renders a u8 element read while its Haxe type stays
        // the Int domain, so it widens back through From instead.
        if (target == "u32" || target == "i32") {
            final source = resolveExprType(actual);
            // A wrapping binop of i32-domain locals renders in i32 even
            // though its Haxe type is the module Int (business u32).
            final i32Source = target == "i32" && i32LocalDomain(actual);
            if (source == target || i32Source) {
                if (rendered.indexOf(".to_be_bytes()[") >= 0)
                    return target + "::from(" + rendered + ")";
                // Fold an integer constant to a typed literal: the fold
                // keeps the binding's type anchored exactly like the old
                // `as` did (a `let x = 0; x = 256;` chain infers {integer}
                // without a typed assignment).
                final folded = constantCast(actual, target);
                if (folded != null)
                    return folded;
                return rendered;
            }
        }
        return target == "u32" || target == "i32" ? RustConversions.reinterpret(rendered, target) : rendered;
    }

    function containsNullDefault(value:DefaultArgExpander.CoalescingDefaultValue):Bool {
        return switch (value) {
            case CConditional(_, _, f): switch (f) {
                    case CNull: true;
                    case _: false;
                };
            case _: false;
        };
    }

    // Unsigned wrapping keeps the historical form: the left operand carries
    // the boundary cast, the right operand stays bare. Signed wrapping casts
    // an operand only when it crosses domains; i32-domain locals and integer
    // literals assign to i32 without a cast.

    /**
        One operand of a wrapping binop, rendered in the operation's wrap
        domain. An operand that renders in the other same-width domain
        reinterprets its bits (T5); the right operand of unsigned wrapping
        keeps its historical bare form.
    **/
    function wrappingOperand(e:TypedExpr, op:Binop, wrapDomain:String, isLeft:Bool):String {
        final text = wrappingArg(e, op, isLeft);
        // An operand already rendered in the wrap domain needs no cast: an Int
        // local or field in business is u32 and a wrapping arithmetic result
        // carries it; dropping the redundant `(x) as u32` keeps the emitted
        // code free of no-op casts. Only operands that render in a different
        // width or signedness cross the boundary here.
        if (types.of(e.t, false) == wrapDomain)
            return text;
        // A Null<Int> operand already unwrapped renders its inner scalar
        // in the module domain (unwrap_or was already applied), so the
        // Option wrapper in the static type is not the rendering domain.
        if (isNullType(e.t) && isIntType(getNullInnerType(e.t))) {
            final innerDomain = RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
            if (innerDomain == wrapDomain)
                return text;
        }
        if (wrapDomain != "i32") {
            if (isParameterOfDomain(e, wrapDomain) || !isLeft)
                return text;
            return RustConversions.reinterpret(text, wrapDomain);
        }
        if (i32ComparisonTarget || i32OperandDomain(e))
            return text;
        switch (stripWrap(e).expr) {
            case TConst(TInt(_)):
                return text;
            case _:
        }
        return RustConversions.reinterpret(text, "i32");
    }

    function isParameterOfDomain(e:TypedExpr, domain:String):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v) if (paramVarIds.exists(v.id)): types.of(e.t) == domain;
            case _: false;
        };
    }

    function wrappingArg(e:TypedExpr, parent:Binop, isRight:Bool):String {
        final value = operand(e, parent, isRight);
        return StringTools.startsWith(value, "(") && StringTools.endsWith(value, ")") ? value.substr(1, value.length - 2) : value;
    }

    function isClosureParam(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): closureParamIds.exists(v.id);
            case _: false;
        };
    }

    function isGenericLocal(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): genericParamIds.exists(v.id);
            case _: false;
        };
    }

    function i32LocalDomain(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v): i32Locals.exists(v.id) && !paramVarIds.exists(v.id);
            case TBinop(OpAdd | OpSub | OpMult, left, right): i32LocalDomain(left) || i32LocalDomain(right);
            case _: false;
        };
    }

    function i32OperandDomain(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(v) if (paramVarIds.exists(v.id)): types.of(e.t) == "i32";
            case TLocal(_): i32LocalDomain(e);
            case TBinop(OpAdd | OpSub | OpMult, left, right): i32OperandDomain(left) || i32OperandDomain(right);
            case _: false;
        };
    }

    function wrappingMethod(op:Binop):String {
        return switch (op) {
            case OpAdd: "wrapping_add";
            case OpSub: "wrapping_sub";
            case OpMult: "wrapping_mul";
            case _: "";
        };
    }

    function isLocalOrFieldTarget(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TLocal(_): true;
            case TField(subj, FInstance(_, _, _)) | TField(subj, FAnon(_)): isLocalOrFieldTarget(subj);
            default: false;
        };
    }

    function assignTarget(e:TypedExpr):String {
        switch (e.expr) {
            case TArray(arr, idx):
                return expr(arr) + "[" + castArg(idx, "usize") + "]";
            case TField(_, FStatic(c, cf)):
                final target = staticAssignmentTarget(e);
                return target != null ? target : staticRef(c.get(), cf.get().name);
            case TField(subj, FInstance(_, _, cf)) | TField(subj, FAnon(cf)):
                return expr(subj) + "." + RustImports.toSnakeCase(cf.get().name);
            case TLocal(v):
                return RustImports.toSnakeCase(localName(v));
            case TCast(inner, _) | TMeta(_, inner) | TParenthesis(inner):
                return assignTarget(inner);
            case _:
                return fail(e, "assignment target has no Rust lowering: " + Std.string(e.expr));
        }
    }

    function objectLiteral(e:TypedExpr, fields:Array<{name:String, expr:TypedExpr}>):String {
        final typeName = resolveTypeName(e.t);
        final parts = [
            for (f in fields) {
                final val = if (isStringType(f.expr.t)) {
                    switch (stripWrap(f.expr).expr) {
                        case TConst(TString(_)): expr(f.expr) + ".to_string()";
                        case TLocal(v) if (paramVarIds.exists(v.id)): expr(f.expr) + ".to_string()";
                        case _: expr(f.expr) + ".clone()";
                    }
                } else {
                    expr(f.expr);
                };
                RustImports.toSnakeCase(f.name) + ": " + val;
            }
        ];
        return typeName + " { " + parts.join(", ") + " }";
    }

    function resolveTypeName(t:Type):String {
        return switch (t) {
            case TType(def, _):
                final d = def.get();
                imports.requireType(d.module, d.name);
                d.name;
            case TAnonymous(anon):
                final match = state.structTypedefs.get(RustDecl.structureSignature(anon));
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
                if (v.name != "`" && init == null) {
                    // Deferred locals are assigned by control flow below; only
                    // mark them mutable when scanLocals observes such an assignment.
                    usedNames.set(v.name, true);
                    deferredLocals.set(v.id, true);
                } else if (v.name != "`") {
                    usedNames.set(v.name, true);
                }
                if (init != null) {
                    // Wire reads and reader positions arrive as unsigned values;
                    // remember the locals so negative-domain checks lower as
                    // upper-bound checks.
                    switch (stripWrap(init).expr) {
                        case TCall(fn, _):
                            if (isFpHelperInt64Call(fn))
                                fpInt64Halves.set(v.id, true);
                            switch (fn.expr) {
                                case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)):
                                    final n = cf.get().name;
                                    if (n == "readU16" || n == "readU32" || n == "remaining" || n == "consumed") {
                                        unsignedLocals.set(v.id, true);
                                    }
                                case _:
                            }
                        case _:
                    }
                }
            case TTry(body, _):
                collectTryAssignments(body);
            case TBlock(stmts):
                // A countdown loop the renderer will shift to an unsigned
                // guard keeps the u32 domain; collect its variable here so
                // the zero-comparison rule below can exclude it.
                for (i in 0...stmts.length) {
                    if (i + 1 < stmts.length) {
                        final cd = matchCountdownLoop(stmts[i], stmts[i + 1]);
                        if (cd != null)
                            countdownShiftedVars.set(cd.readVar.id, true);
                    }
                }
            case TBinop(OpEq | OpNotEq, left, right):
                final local = switch ([stripWrap(left).expr, stripWrap(right).expr]) {
                    case [TLocal(v), _] if (isTNull(right) || isZero(right)): v;
                    case [_, TLocal(v)] if (isTNull(left) || isZero(left)): v;
                    case _: null;
                };
                if (local != null)
                    nullableSensitiveLocals.set(local.id, true);
            case TBinop(OpLte | OpLt | OpGt | OpGte, left, right):
                // A comparison against literal zero, or against an expression
                // which can underflow below zero, contemplates negative values;
                // the local keeps the signed i32 Int domain.
                switch ([stripWrap(left).expr, stripWrap(right).expr]) {
                    case [TLocal(v), _] if (isZero(right) || isUnderflowProneIntExpr(right)):
                        if (isIntType(v.t) && !isNullType(v.t) && !unsignedLocals.exists(v.id) && !countdownShiftedVars.exists(v.id)) i32Locals.set(v.id, true);
                    case [_, TLocal(v)] if (isZero(left) || isUnderflowProneIntExpr(left)):
                        if (isIntType(v.t) && !isNullType(v.t) && !unsignedLocals.exists(v.id) && !countdownShiftedVars.exists(v.id)) i32Locals.set(v.id, true);
                    case _:
                }
            case TBinop(OpAssign, t, _) | TBinop(OpAssignOp(_), t, _):
                switch (stripWrap(t).expr) {
                    case TLocal(v):
                        mutated.set(v.id, true);
                    case TArray(arr, _):
                        final receiver = mapBackingReceiver(arr);
                        switch (stripWrap(receiver == null ? arr : receiver).expr) {
                            case TLocal(v):
                                mutated.set(v.id, true);
                            case _:
                        }
                    case TField(subj, _):
                        // Assigning through a field of a local requires the binding to be mutable;
                        // the chain can be arbitrarily deep (a.b.c = ... marks a).
                        var inner = subj;
                        while (true) {
                            switch (stripWrap(inner).expr) {
                                case TLocal(v):
                                    mutated.set(v.id, true);
                                    break;
                                case TField(next, _):
                                    inner = next;
                                case _:
                                    break;
                            }
                        }
                    case _:
                }
            case TUnop(OpIncrement | OpDecrement, _, subj):
                // An `x++` / `x--` statement arrives as a unary op that
                // renders as `+= 1` / `-= 1`; the mutation goes through
                // the same path as a compound assignment.
                switch (stripWrap(subj).expr) {
                    case TLocal(v):
                        mutated.set(v.id, true);
                    case _:
                }
            case TCall(fn, args):
                switch (fn.expr) {
                    case TField(subj, FInstance(_, _, cf)):
                        final n = cf.get().name;
                        if (n == "readU16" || n == "readU32" || n == "readF64" || n == "readAscii" || n == "writeU16" || n == "writeU32" || n == "writeF64"
                            || n == "writeAscii" || n == "addByte" || n == "push" || n == "finish" || n == "put" || n == "set" || n == "update"
                            || n == "add" || n == "addChar") {
                            switch (stripWrap(subj).expr) {
                                case TLocal(v):
                                    mutated.set(v.id, true);
                                case _:
                            }
                        }
                    case _:
                }
                final isInstancePush = switch (fn.expr) {
                    case TField(_, FInstance(_, _, cf)) if (cf.get().name == "push"): true;
                    default: false;
                };
                // renderCallArgs reads the callee's declared parameter
                // types through cf.get().type, so the declaration decides
                // the borrow: a parameter declared as Array lowers to a
                // mutating borrow that drains the vector, while a param
                // left as an unbound type parameter borrows shared. The
                // call-site type fn.t binds that parameter to Array and
                // would mark a local the shared borrow never mutates.
                final declaredFnType = switch (fn.expr) {
                    case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)): cf.get().type;
                    default: fn.t;
                };
                if (!isInstancePush) {
                    final paramTypes = switch (Context.follow(declaredFnType)) {
                        case TFun(pargs, _): [for (p in pargs) p.t];
                        default: [];
                    };
                    // When the callee is a class field its body decides which
                    // positions mutate: renderCallArgs borrows &mut exactly
                    // the positions mutableParamPositions reports, so a
                    // shared-borrow position must not mark the local mutated.
                    final mutableAt = switch (fn.expr) {
                        case TField(_, FInstance(_, _, cf)) | TField(_, FStatic(_, cf)): mutableParamPositions(cf.get());
                        default: null;
                    };
                    for (i in 0...args.length)
                        if (i < paramTypes.length && isPassByRef(paramTypes[i]))
                            switch (Context.follow(paramTypes[i])) {
                                case TInst(c, _) if (c.get().name == "Array"):
                                    if (mutableAt == null || mutableAt.indexOf(i) >= 0) switch (stripWrap(args[i]).expr) {
                                        case TField(subj, _): switch (stripWrap(subj).expr) {
                                                case TLocal(v): mutated.set(v.id, true);
                                                case _:
                                            }
                                        case TLocal(v): mutated.set(v.id, true);
                                        default:
                                    }
                                default:
                            }
                }
            case _:
        }
        TypedExprTools.iter(e, scanLocals);
    }

    function scanReadsAfter(e:TypedExpr):Void {
        switch (e.expr) {
            case TBlock(stmts):
                for (i in 0...stmts.length) {
                    switch (stmts[i].expr) {
                        case TVar(_, init) if (init != null):
                            switch (stripWrap(init).expr) {
                                case TLocal(source):
                                    for (j in (i + 1)...stmts.length)
                                        if (mentionsLocal(stmts[j], source)) {
                                            readsAfterDeclaration.set(source.id, true);
                                            break;
                                        }
                                case TField(subj, _):
                                    switch (stripWrap(subj).expr) {
                                        case TLocal(source):
                                            for (j in (i + 1)...stmts.length)
                                                if (mentionsLocal(stmts[j], source)) {
                                                    readsAfterDeclaration.set(source.id, true);
                                                    break;
                                                }
                                        case _:
                                    }
                                case _:
                            }
                        case _:
                    }
                    scanReadsAfter(stmts[i]);
                }
            case _:
        }
        // Loop and branch bodies are blocks too; the sibling scan must reach them.
        TypedExprTools.iter(e, scanReadsAfter);
    }

    function collectTryAssignments(e:TypedExpr):Void {
        function walk(x:TypedExpr):Void {
            switch (x.expr) {
                case TBinop(OpAssign, target, _) | TBinop(OpAssignOp(_), target, _):
                    switch (stripWrap(target).expr) {
                        case TLocal(v): tryCapturedAssignments.set(v.id, true);
                        case _:
                    }
                case _:
            }
            TypedExprTools.iter(x, walk);
        }
        walk(e);
    }

    function mentionsLocal(e:TypedExpr, v:TVar):Bool {
        var found = false;
        function walk(x:TypedExpr) {
            switch (x.expr) {
                case TLocal(l) if (l.id == v.id):
                    found = true;
                case _:
            }
            TypedExprTools.iter(x, walk);
        }
        walk(e);
        return found;
    }

    function localName(v:TVar):String {
        if (v.name != "`") {
            return v.name;
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
                return c;
            }
        }
        hiddenCounter += 1;
        final generated = "t" + hiddenCounter;
        hiddenNames.set(v.id, generated);
        return generated;
    }

    public function payloadName(ef:EnumField, index:Int):String {
        return switch (ef.type) {
            case TFun(args, _) if (index < args.length):
                RustImports.toSnakeCase(args[index].name);
            case _:
                "param" + index;
        };
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
            case OpAnd: "&";
            case OpOr: "|";
            case OpXor: "^";
            case OpShl: "<<";
            case OpShr: ">>";
            case _: fail(null, "operator symbol has no Rust lowering: " + Std.string(op));
        }
    }

    function precedenceOf(op:Binop):Int {
        return switch (op) {
            case OpMult | OpDiv | OpMod: 11;
            case OpAdd | OpSub: 10;
            case OpShl | OpShr | OpUShr: 9;
            case OpLt | OpLte | OpGt | OpGte: 8;
            case OpEq | OpNotEq: 7;
            case OpAnd: 6;
            case OpXor: 5;
            case OpOr: 4;
            case OpBoolAnd: 3;
            case OpBoolOr: 2;
            case OpAssign | OpAssignOp(_): 1;
            case _: 0;
        }
    }

    function associative(op:Binop):Bool {
        return switch (op) {
            case OpAdd | OpMult | OpAnd | OpOr | OpXor | OpBoolAnd | OpBoolOr: true;
            case _: false;
        }
    }

    function stripWrap(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TMeta(_, inner) | TCast(inner, _): stripWrap(inner);
            case _: e;
        }
    }

    function unwrapLambda(e:TypedExpr):Null<TFunc> {
        if (e == null)
            return null;
        return switch (e.expr) {
            case TFunction(f): f;
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): unwrapLambda(inner);
            case _: null;
        };
    }

    function lambdaBody(e:TypedExpr):TypedExpr {
        if (e == null)
            return e;
        return switch (e.expr) {
            case TBlock(stmts) if (stmts.length > 0): lambdaBody(stmts[stmts.length - 1]);
            case TReturn(ret) if (ret != null): lambdaBody(ret);
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): lambdaBody(inner);
            case _: e;
        };
    }

    function stripCast(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TCast(inner, _) | TMeta(_, inner): stripCast(inner);
            case _: e;
        }
    }

    function fieldName(fa:FieldAccess):String {
        return switch (fa) {
            case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf) | FClosure(_, cf): cf.get().name;
            case FEnum(_, ef): ef.name;
            case FDynamic(n): n;
        }
    }

    function isBytes(e:TypedExpr):Bool {
        return switch (e.t) {
            case TInst(c, _): c.get().module == "haxe.io.Bytes";
            case TType(d, _): d.get().module == "haxe.io.Bytes";
            case _: false;
        }
    }

    function isString(e:TypedExpr):Bool {
        return switch (e.t) {
            case TInst(c, _): c.get().name == "String";
            case _: false;
        }
    }

    function quoteString(s:String):String {
        final esc = s.split("\\")
            .join("\\\\")
            .split("\"")
            .join("\\\"")
            .split("\n")
            .join("\\n")
            .split("\r")
            .join("\\r")
            .split("\t")
            .join("\\t");
        return '"' + esc + '"';
    }

    function indent(depth:Int):String {
        var s = "";
        for (_ in 0...depth)
            s += "    ";
        return s;
    }

    /** Whether a rendered value is a lone atom: no top-level operator
        whose precedence could capture a trailing method call. */
    static function isSimpleValueText(s:String):Bool {
        var depth = 0;
        for (i in 0...s.length) {
            final ch = s.charAt(i);
            switch (ch) {
                case "(" | "[":
                    depth++;
                case ")" | "]":
                    depth--;
                default:
                    if (depth == 0)
                        switch (ch) {
                            case "+" | "-" | "*" | "/" | "%" | "&" | "|" | "^" | "<" | ">": return false;
                            case _:
                        }
            }
        }
        return true;
    }

    function matchingParens(s:String):Bool {
        var depth = 0;
        for (i in 0...s.length) {
            if (s.charAt(i) == "(")
                depth++;
            else if (s.charAt(i) == ")") {
                depth--;
                if (depth == 0 && i < s.length - 1)
                    return false;
            }
        }
        return depth == 0;
    }

    function fail(e:Null<TypedExpr>, msg:String):String {
        final pos = e != null ? e.pos : Context.currentPos();
        Context.error(msg, pos);
        return "";
    }

    function collectOrTerms(e:TypedExpr, out:Array<TypedExpr>):Void {
        final inner = stripWrap(e);
        switch (inner.expr) {
            case TBinop(OpOr, l, r):
                collectOrTerms(l, out);
                collectOrTerms(r, out);
            case _:
                out.push(inner);
        }
    }

    function isSameExpr(a:TypedExpr, b:TypedExpr):Bool {
        if (a == null || b == null)
            return a == b;
        final sa = stripWrap(a);
        final sb = stripWrap(b);
        return switch [sa.expr, sb.expr] {
            case [TLocal(v1), TLocal(v2)]: v1.id == v2.id;
            case [TConst(c1), TConst(c2)]: Std.string(c1) == Std.string(c2);
            case [TField(s1, fa1), TField(s2, fa2)]: fieldName(fa1) == fieldName(fa2) && isSameExpr(s1, s2);
            case _: false;
        };
    }

    function extractByteRead(e:TypedExpr):Null<{buf:TypedExpr, base:TypedExpr, offset:Int}> {
        final inner = stripWrap(e);
        var bufExpr:Null<TypedExpr> = null;
        var idxExpr:Null<TypedExpr> = null;
        switch (inner.expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (stripWrap(fn).expr) {
                    case TField(subj, fa) if (fieldName(fa) == "get"):
                        bufExpr = subj;
                        idxExpr = args[0];
                    case _:
                }
            case TArray(arr, idx):
                bufExpr = arr;
                idxExpr = idx;
            case _:
        }
        if (bufExpr == null || idxExpr == null) {
            return null;
        }
        final strippedIdx = stripWrap(idxExpr);
        switch (strippedIdx.expr) {
            case TBinop(OpAdd, l, r):
                switch [stripWrap(l).expr, stripWrap(r).expr] {
                    case [_, TConst(TInt(k))]:
                        return {buf: bufExpr, base: l, offset: k};
                    case [TConst(TInt(k)), _]:
                        return {buf: bufExpr, base: r, offset: k};
                    case _:
                }
            case _:
                return {buf: bufExpr, base: idxExpr, offset: 0};
        }
        return null;
    }

    function tryMatchFromBeBytes(e:TypedExpr):Null<String> {
        final terms:Array<TypedExpr> = [];
        collectOrTerms(e, terms);
        if (terms.length != 2 && terms.length != 4 && terms.length != 8) {
            return null;
        }
        final n = terms.length;
        final extracted:Array<{
            buf:TypedExpr,
            base:TypedExpr,
            offset:Int,
            shift:Int
        }> = [];
        for (i in 0...n) {
            final term = terms[i];
            var readExpr:TypedExpr = term;
            var shift = 0;
            switch (term.expr) {
                case TBinop(OpShl, inner, s):
                    readExpr = inner;
                    switch (stripWrap(s).expr) {
                        case TConst(TInt(sh)): shift = sh;
                        case _: return null;
                    }
                case _:
                    shift = 0;
            }
            final expectedShift = (n - 1 - i) * 8;
            if (shift != expectedShift) {
                return null;
            }
            final read = extractByteRead(readExpr);
            if (read == null) {
                return null;
            }
            if (read.offset != i) {
                return null;
            }
            if (i > 0) {
                if (!isSameExpr(read.buf, extracted[0].buf) || !isSameExpr(read.base, extracted[0].base)) {
                    return null;
                }
            }
            extracted.push({
                buf: read.buf,
                base: read.base,
                offset: read.offset,
                shift: shift
            });
        }

        final typeName = switch (n) {
            case 2: "u16";
            case 4: "u32";
            case 8: "u64";
            case _: return null;
        };

        final bufStr = expr(extracted[0].buf);
        final baseStr = expr(extracted[0].base);
        // A byte buffer's element is already u8, so the element read needs
        // no cast in the from_be_bytes array; an Int-word buffer (registry
        // hashing pads a Vec<u32> with bytes) narrows each element the way
        // the old `as u8` did, through the T4 mask.
        final byteSource = isBytes(stripWrap(extracted[0].buf));
        final elems = [];
        for (i in 0...n) {
            final idx = i == 0 ? usizeIndex(baseStr) : usizeIndex(baseStr + " + " + i);
            final elem = byteSource ? "(" + bufStr + "[" + idx + "])" : RustConversions.truncate(bufStr + "[" + idx + "]", "u8");
            elems.push("(" + elem + ")");
        }
        return typeName + "::from_be_bytes([" + elems.join(", ") + "])";
    }

    function isStringIndexOf(fn:TypedExpr):Bool {
        return switch (fn.expr) {
            case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "indexOf" && isString(stripCast(subj))): true;
            case _: false;
        };
    }

    function isStringCharCodeAt(fn:TypedExpr):Bool {
        return switch (fn.expr) {
            case TField(subj, FInstance(_, _, cf)) if (cf.get().name == "charCodeAt" && isString(stripCast(subj))): true;
            case _: false;
        };
    }

    function isStringCharCodeAtCall(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _) if (isStringCharCodeAt(fn)): true;
            case _: false;
        };
    }

    function isNullableCharCodeExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _) if (isStringCharCodeAt(fn)): true;
            case _: false;
        };
    }

    function resolveExprType(e:TypedExpr):String {
        final inner = stripWrap(e);
        switch (inner.expr) {
            case TLocal(v):
                if (i32Locals.exists(v.id))
                    return "i32";
                // argTypes accumulates across functions; a current-function
                // parameter is the only valid name-keyed lookup.
                if (paramVarIds.exists(v.id) && argTypes.exists(v.name))
                    return argTypes.get(v.name);
            case _:
        }
        return types.of(e.t);
    }

    function tryMatchByteExtract(e:TypedExpr):Null<String> {
        final inner = stripWrap(e);
        var target:TypedExpr = inner;
        var shift = 0;
        switch (inner.expr) {
            case TBinop(OpUShr | OpShr, t, s):
                target = t;
                switch (stripWrap(s).expr) {
                    case TConst(TInt(sh)): shift = sh;
                    case _: return null;
                }
            case _:
                shift = 0;
        }
        final strippedTarget = stripWrap(target);
        switch (strippedTarget.expr) {
            case TCall(fn, _) if (isStringCharCodeAt(fn)):
                // A nullable code unit lowers to Option<u32>; the byte
                // extract rewrite replaces a `& 0xFF` binop whose Haxe
                // semantics unbox null to 0, so unwrap the Option to 0
                // the same way before the value feeds a u8 context.
                return expr(target) + (isNullType(target.t) || isStringCharCodeAtCall(target) ? ".unwrap_or(0)" : "");
            case _:
        }
        final targetType = resolveExprType(target);
        final bitWidth = switch (targetType) {
            case "u16": 16;
            case "u32": 32;
            case "u64": 64;
            case "u8": 8;
            case _: 32;
        };
        if (bitWidth == 8) {
            return expr(target);
        }
        if ((bitWidth - 8 - shift) % 8 != 0 || shift < 0 || shift > bitWidth - 8) {
            return null;
        }
        final byteIndex = Std.int((bitWidth - 8 - shift) / 8);
        return expr(target) + ".to_be_bytes()[" + byteIndex + "]";
    }

    function isPassByRef(t:Type):Bool {
        if (isNullType(t))
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _) if (a.get().name == "ReadOnlyArray"
                || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")): true;
            case TInst(c, _)
                if (c.get().name == "Array"
                    || c.get().name == "Bytes"
                    || (c.get().pack.join(".") == "haxe.io" && c.get().name == "Bytes")
                    || c.get().name == "String"): true;
            case _: false;
        };
    }

    function isInterfaceType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().isInterface;
            case _: false;
        };
    }

    function renderValueForType(expected:Null<Type>, actual:TypedExpr, rendered:String):String {
        if (expected == null || actual == null)
            return rendered;
        // Rust represents
        // concrete implementor therefore enters an interface slot through
        // the one sanctioned Box::new construction; an expression already
        // typed as the interface is already boxed by its declaration site.
        if (!isNullType(expected) && !isNullType(actual.t) && isStringType(expected) && isStringType(actual.t)) {
            final borrowedParam = switch (stripWrap(actual).expr) {
                case TLocal(v): paramVarIds.get(v.id) == true;
                case _: false;
            };
            if (borrowedParam)
                return rendered + ".to_string()";
        }
        if (isNullType(expected) && isNullType(actual.t) && isStringType(getNullInnerType(expected))) {
            final borrowedParam = switch (stripWrap(actual).expr) {
                case TLocal(v): paramVarIds.get(v.id) == true;
                case _: false;
            };
            if (borrowedParam)
                return "match " + rendered + " { Some(v) => Some(v.to_string()), None => None }";
        }
        // charCodeAt is represented as Option<u32>; crossing into a plain
        // value parameter applies Haxe's null-to-zero bridge exactly once.
        if (!isNullType(expected) && isStringCharCodeAtCall(actual) && isNullType(actual.t)) {
            return rendered + ".unwrap_or(0)";
        }
        if (isInterfaceType(expected) && !isInterfaceType(actual.t)) {
            return "Box::new(" + rendered + ")";
        }
        // Static methods and static function fields are emitted as callable
        // items/pointers, while every non-static function value is already an
        // Rc at its declaration site. Adapt the former only when a ruled
        // Rc-held function slot receives it.
        if (isFunctionType(expected) && isFunctionType(actual.t) && !isBoxedFunctionExpr(actual)) {
            imports.require("std::rc::Rc");
            return "Rc::new(" + rendered + ")";
        }
        return rendered;
    }

    function isBoxedFunctionExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TFunction(_): true;
            case TLocal(_): true;
            case TCall(_, _): true;
            case TField(_, FInstance(_, _, cf)) if (isFunctionType(cf.get().type)): true;
            case TField(_, FStatic(_, _)): false;
            case _: false;
        };
    }

    function renderCallArgs(fnType:Null<Type>, args:Array<TypedExpr>, signedPositions:Null<Array<Int>> = null, paramOffset:Int = 0,
            mutablePositions:Null<Array<Int>> = null):String {
        final paramTypes = if (fnType != null) {
            switch (Context.follow(fnType)) {
                case TFun(pargs, _): [for (p in pargs) p.t];
                case _: [];
            };
        } else [];
        final rendered = [];
        for (i in 0...args.length) {
            final arg = args[i];
            final paramIndex = i + paramOffset;
            final pt = paramIndex < paramTypes.length ? paramTypes[paramIndex] : null;
            var argStr = renderValueForType(pt, arg, expr(arg));
            // An i32-domain argument crossing into a u32 business parameter
            // reinterprets bits (T5); a same-domain pass (a resident runtime
            // calling another resident runtime) needs no cast.
            if (pt != null && isIntType(pt) && i32LocalDomain(arg) && types.of(pt, false) == "u32") {
                argStr = RustConversions.reinterpret(argStr, "u32");
            }
            if (paramIndex < paramTypes.length) {
                if (isNullType(pt) && isStringType(getNullInnerType(pt)) && isNullType(arg.t)) {
                    argStr = argStr + ".clone()";
                } else if (isNullType(pt) && !isNullType(arg.t)) {
                    if (argStr == "None") {
                        // already None
                    } else {
                        final inner = switch (stripWrap(arg).expr) {
                            case TConst(TString(s)): quoteString(s) + ".to_string()";
                            case _: isInterfaceType(getNullInnerType(pt)) && !isInterfaceType(arg.t) ? "Box::new(" + argStr + ")" : argStr;
                        };
                        argStr = "Some(" + inner + ")";
                    }
                } else if (RustType.isTypeParam(pt)) {
                    final borrowed = switch (stripWrap(arg).expr) {
                        case TLocal(v): isBorrowedLocal(v);
                        case _: false;
                    };
                    if (isStringType(arg.t)) {
                        // A generic T is owned in its return position. A Haxe
                        // String argument therefore specializes T as String,
                        // even when the source expression itself is a borrowed
                        // string parameter or a literal.
                        argStr = "&(" + argStr + ").to_string()";
                    } else if (!borrowed && !StringTools.startsWith(argStr, "&")) {
                        argStr = "&(" + argStr + ")";
                    }
                } else if (isPassByRef(pt)) {
                    final provenString = switch (stripWrap(arg).expr) {
                        case TLocal(v) if (provenNonNullVarIds.exists(v.id) && isNullType(arg.t) && isStringType(pt)): true;
                        case _: false;
                    };
                    if (provenString) {
                        argStr = expr(arg) + ".as_deref().unwrap_or(\"\")";
                    } else {
                        // The mutating faces are arrays and the writer and reader
                        // fronts; every other borrowed parameter reads only.
                        final isArray = switch (Context.follow(pt)) {
                            case TInst(c, _): c.get().name == "Array";
                            default: false;
                        };
                        // A compile-time data table is a static declared at file scope:
                        // it borrows immutably even where the parameter
                        // accepts mutation.
                        final isTableArg = switch (stripWrap(arg).expr) {
                            case TField(_, FStatic(_, tableField)): DataTableHelper.isDataTableField(tableField.get());
                            case _: false;
                        };
                        final prefix = if (isArray
                            && !isTableArg
                            && (mutablePositions != null && mutablePositions.indexOf(paramIndex) >= 0)) {
                            switch (stripWrap(arg).expr) {
                                case TLocal(v) if (isBorrowedLocal(v)): "&mut *";
                                case _: "&mut ";
                            }
                        } else "&";
                        if (isArray && !isTableArg && mutablePositions != null && mutablePositions.indexOf(paramIndex) >= 0) {
                            final borrowedArg = switch (stripWrap(arg).expr) {
                                case TLocal(v): isBorrowedLocal(v);
                                case _: false;
                            };
                            if (borrowedArg) {
                                // Already borrowed; leave the expression unchanged.
                            } else if (StringTools.startsWith(argStr, "&"))
                                argStr = "&mut " + (StringTools.startsWith(argStr, "&mut ") ? argStr.substr(5) : argStr.substr(1));
                            else
                                argStr = "&mut " + argStr;
                        } else if (!StringTools.startsWith(argStr, "&")) {
                            argStr = prefix + argStr;
                        }
                    }
                } else if (isRecordValueType(arg.t) && switch (stripWrap(arg).expr) {
                    case TLocal(_): true;
                    case _: false;
                    }) {
                    argStr = "(" + argStr + ").clone()";
                    } else if (!isPassByRef(pt)
                    && !isTypeCopy(arg.t)
                    && !isTemporaryOwnedExpr(arg)
                    && !StringTools.startsWith(argStr, "&")
                    && !StringTools.endsWith(argStr, ".clone()")
                    && !StringTools.endsWith(argStr, ".to_vec()")
                    && !StringTools.endsWith(argStr, ".to_string()")) {
                    final provenEnum = switch (stripWrap(arg).expr) {
                        case TLocal(v) if (provenNonNullVarIds.exists(v.id) && isNullType(arg.t)): true;
                        case _: false;
                    };
                    if (provenEnum)
                        argStr = expr(arg) + ".unwrap()";
                    else
                        argStr = "(" + argStr + ").clone()";
                }
                // A collection length is usize in Rust while a Haxe Int
                // function parameter is u32 in business modules. The
                // declared function type is the call boundary, so narrow
                // exactly there (the same convention as buf.len() as u32); the
                // stored function type remains unchanged.
                if (isIntType(pt) && isUsizeExpr(arg) && (signedPositions == null || signedPositions.indexOf(i) < 0)) {
                    final targetType = types.of(pt, false);
                    if (targetType == "u32") {
                        argStr = RustConversions.truncate(argStr, "u32");
                    } else if (targetType == "i32") {
                        argStr = RustConversions.narrowI32(argStr);
                    }
                }
            }
            if (signedPositions != null && signedPositions.indexOf(i) >= 0) {
                // The position is a resident i32 slot: fold a literal,
                // leave a resident caller's i32 value bare, and reinterpret
                // a business u32 value (T5).
                argStr = castSignedI32(arg);
            }
            rendered.push(argStr);
        }
        return rendered.join(", ");
    }

    function isTemporaryOwnedExpr(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TFunction(_) | TNew(_, _, _) | TObjectDecl(_): true;
            case _: false;
        };
    }

    function isUsizeExpr(e:TypedExpr):Bool {
        if (e == null)
            return false;
        return switch (stripWrap(e).expr) {
            case TField(subj, fa) if (fieldName(fa) == "length" || fieldName(fa) == "get_length"):
                return false;
            case TBinop(OpAdd | OpSub | OpMult | OpDiv, l, r): isUsizeExpr(l) || isUsizeExpr(r);
            default: false;
        };
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

    function scalarTypeKind(t:Type):String {
        final followed = Context.follow(t);
        return switch (followed) {
            case TAbstract(a, _): a.get().name;
            case TInst(c, _): c.get().name;
            case _: "Unknown";
        };
    }

    function recordAggregateType(t:Type):Void {
        switch (t) {
            case TInst(c, params):
                final cls = c.get();
                if (cls.name == "Array") {
                    final key = "Array_" + formatTypeKey(params[0]);
                    if (!state.testReachableTypes.exists(key)) {
                        state.testReachableTypes.set(key, t);
                        recordAggregateType(params[0]);
                    }
                } else if (cls.name == "Bytes" || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) {
                    if (!state.testReachableTypes.exists("Bytes")) {
                        state.testReachableTypes.set("Bytes", t);
                    }
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
                final key = en.module + "." + en.name;
                if (!state.testReachableTypes.exists(key)) {
                    state.testReachableTypes.set(key, t);
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
            case TEnum(e, params): e.get().module + "." + e.get().name;
            case _: "Unknown";
        };
    }

    function aggregateAssertFuncName(t:Type):String {
        return switch (t) {
            case TInst(c, params) if (c.get().name == "Array"):
                "assert_equals_vec_" + typeSafeSnake(params[0]);
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray"
                || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
                "assert_equals_vec_" + typeSafeSnake(params[0]);
            case TInst(c, _) if (c.get().name == "Bytes" || (c.get().pack.join(".") == "haxe.io" && c.get().name == "Bytes")):
                "assert_equals_bytes";
            case TType(def, _):
                "assert_equals_" + RustImports.toSnakeCase(def.get().name);
            case TEnum(e, _):
                "assert_equals_" + RustImports.toSnakeCase(e.get().name);
            case _: "assert_equals_unknown";
        };
    }

    function typeSafeSnake(t:Type):String {
        return switch (t) {
            case TAbstract(a, _):
                switch (a.get().name) {
                    case "Int": "u32";
                    case "Float": FloatPrecision.isF32() ? "f32" : "f64";
                    case "Bool": "bool";
                    case "String": "string";
                    case _: RustImports.toSnakeCase(a.get().name);
                }
            case TInst(c, _):
                switch (c.get().name) {
                    case "String": "string";
                    case "Bytes": "bytes";
                    case _: RustImports.toSnakeCase(c.get().name);
                }
            case TType(def, _): RustImports.toSnakeCase(def.get().name);
            case TEnum(e, _): RustImports.toSnakeCase(e.get().name);
            case _: "unknown";
        };
    }

    function renderOptArg(e:TypedExpr, kind:String):String {
        // Both sides must reach the helper as Option. A Null-typed
        // expression already lowers to Option; any other expression
        // renders the inner value and is wrapped into Some. The String
        // kind clones because the same local may be borrowed by the
        // actual argument of the same call.
        return switch (e.expr) {
            case TConst(TNull): kind == "String" ? "None::<String>" : "None::<u32>";
            case _ if (isNullType(e.t)): expr(e);
            case TConst(TString(s)) if (kind == "String"): "Some(" + quoteString(s) + ".to_string())";
            case TConst(TInt(i)) if (kind == "Int"): "Some(" + Std.string(i) + ")";
            case _: kind == "String" ? "Some(" + expr(e) + ".clone())" : "Some(" + expr(e) + ")";
        };
    }

    function arrayArgBorrow(e:TypedExpr):String {
        // A direct array access can be borrowed without the value-read
        // clone; the borrow consumers above do not need the copy.
        return switch (e.expr) {
            case TArray(arr, idx): expr(arr) + "[" + castArg(idx, "usize") + "]";
            case _: expr(e);
        };
    }

    function isNullType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (t) {
            case TAbstract(a, _): a.get().name == "Null";
            case _: false;
        };
    }

    function getNullInnerType(t:Type):Type {
        return switch (t) {
            case TAbstract(a, params) if (a.get().name == "Null"): params[0];
            case _: t;
        };
    }

    function isInt64Type(t:Type):Bool {
        if (t == null)
            return false;
        return StringTools.contains(Std.string(Context.follow(t)), "Int64");
    }

    function isFloatType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Float";
            case _: false;
        };
    }

    function isIntType(t:Type):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TAbstract(a, _): a.get().name == "Int";
            case _: false;
        };
    }

    /** Whether a division reads a length and divides by an Int, the
        shape the OpDiv lowering renders as truncating integer
        division; a general Int/Int division lowers through the module
        real (f64 by default, f32 under the precision switch). */
    function isLengthDivision(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TBinop(OpDiv, l, r): isIntType(r.t) && StringTools.endsWith(operand(l, OpDiv, false), ".len()");
            case _: false;
        };
    }

    /** An Int/Int division under Std.int, which truncates the Float
        quotient: Rust integer division on the same operands matches, so
        the division renders without the Float round-trip. Returns null
        when the operand is not such a division. */
    function intDivisionOf(e:TypedExpr):Null<String> {
        return switch (stripWrap(e).expr) {
            case TBinop(OpDiv, l, r) if (isIntType(l.t) && isIntType(r.t)):
                switch (stripWrap(r).expr) {
                    case TConst(TInt(k)) if (k != 0): "(" + expr(l) + ") / (" + expr(r) + ")";
                    case _: null;
                };
            case _: null;
        };
    }

    /** The parameter positions of one function type that carry Int. */
    function intParamPositions(fnType:Null<Type>):Null<Array<Int>> {
        if (fnType == null)
            return null;
        return switch (Context.follow(fnType)) {
            case TFun(pargs, _):
                final positions:Array<Int> = [];
                for (i in 0...pargs.length) {
                    if (isIntType(pargs[i].t)) {
                        positions.push(i);
                    }
                }
                positions;
            case _: null;
        };
    }

    /** Whether one function type returns Int. */
    function returnsInt(fnType:Null<Type>):Bool {
        if (fnType == null)
            return false;
        return switch (Context.follow(fnType)) {
            case TFun(_, ret): isIntType(ret);
            case _: false;
        };
    }

    /** Whether a type mentions a type parameter through any wrapper. */
    function typeHasParam(t:Null<Type>):Bool {
        if (t == null)
            return false;
        if (RustType.isTypeParam(t))
            return true;
        return switch (t) {
            case TAbstract(a, params): [for (p in params) typeHasParam(p)].indexOf(true) >= 0;
            case TInst(_, params): [for (p in params) typeHasParam(p)].indexOf(true) >= 0;
            case TFun(pargs, ret): [for (p in pargs) typeHasParam(p.t)].indexOf(true) >= 0 || typeHasParam(ret);
            case TLazy(f): typeHasParam(f());
            case _: false;
        };
    }

    /** Whether the expression is a call to a generic static function. */
    function genericStaticCallArg(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TCall(fn, _): switch (stripWrap(fn).expr) {
                    case TField(_, FStatic(_, cf)): typeHasParam(cf.get().type);
                    case _: false;
                };
            case _: false;
        };
    }

    function isStringBuf(e:TypedExpr):Bool {
        if (e == null)
            return false;
        return switch (Context.follow(e.t)) {
            case TInst(c, _): final cls = c.get(); (cls.pack.join(".") == "std" && cls.name == "StringBuf") || (cls.pack.length == 0 && cls.name == "StringBuf");
            case _: false;
        };
    }

    function isTNull(e:TypedExpr):Bool {
        return switch (stripWrap(e).expr) {
            case TConst(TNull): true;
            default: false;
        };
    }

    /**
        One branch of a two-arm conditional. A string literal renders as
        &str while a sibling member call that returns an owned String
        renders as String; Rust rejects the mismatched pair as one
        expression, so the lone literal branch converts. Two literals stay
        &str on both arms, and a sibling that renders as a borrow keeps
        the literal as &str too.
    **/
    function conditionalBranchText(branch:TypedExpr, sibling:TypedExpr, resultType:Null<Type> = null):String {
        final text = expr(branch);
        if (resultType != null && isStringType(resultType)) {
            if (StringTools.endsWith(text, ".to_string()") || StringTools.endsWith(text, ".clone()"))
                return text;
            return text + ".to_string()";
        }
        if (text.indexOf("u_string::count") >= 0 && resolveExprType(sibling) == "i32") {
            return RustConversions.reinterpret(text, "i32");
        }
        if (!isStringType(branch.t) || !isStringType(sibling.t)) {
            return text;
        }
        if (!isStringLiteral(branch) || isStringLiteral(sibling)) {
            return text;
        }
        final siblingText = expr(sibling);
        final ownedStringCall = StringTools.endsWith(siblingText, ".to_string()")
            || StringTools.endsWith(siblingText, ".to_string()?")
            || StringTools.endsWith(siblingText, ".to_string().unwrap()");
        return ownedStringCall ? text + ".to_string()" : text;
    }

    function matchGroupByBody(body:Array<TypedExpr>):Null<{
        prefix:Array<TypedExpr>,
        entryVar:TVar,
        entryInit:TypedExpr,
        builderSubj:TypedExpr,
        keyArg:TypedExpr,
        valArg:TypedExpr
    }> {
        if (body.length == 0)
            return null;
        final last = body[body.length - 1];
        final coreStmts:Null<Array<TypedExpr>> = switch (last.expr) {
            case TBlock(s) if (s.length == 4): s;
            default:
                if (body.length == 4) body else null;
        };
        if (coreStmts == null)
            return null;
        final prefix = if (coreStmts == body) [] else body.slice(0, body.length - 1);
        final entry = switch (coreStmts[0].expr) {
            case TVar(v, init) if (init != null): {v: v, init: init};
            default: return null;
        };
        final builderInfo = switch (coreStmts[1].expr) {
            case TVar(bucketV, init) if (init != null):
                switch (stripWrap(init).expr) {
                    case TCall(fn, args) if (args.length == 1):
                        switch (fn.expr) {
                            case TField(subj, fa) if (fieldName(fa) == "get" && (isSortedTable(subj) || isSortedBuilder(subj))):
                                {bucketVar: bucketV, builderSubj: subj, keyArg: args[0]};
                            default: return null;
                        }
                    default: return null;
                }
            default: return null;
        };
        if (builderInfo == null)
            return null;
        final pushInfo = switch (coreStmts[coreStmts.length - 1].expr) {
            case TCall(fn, args) if (args.length == 1):
                switch (fn.expr) {
                    case TField(subj, fa) if (fieldName(fa) == "push"):
                        switch (stripWrap(subj).expr) {
                            case TLocal(v) if (v.id == builderInfo.bucketVar.id):
                                {valArg: args[0]};
                            default: return null;
                        }
                    default: return null;
                }
            default: return null;
        };
        if (pushInfo == null)
            return null;
        return {
            prefix: prefix,
            entryVar: entry.v,
            entryInit: entry.init,
            builderSubj: builderInfo.builderSubj,
            keyArg: builderInfo.keyArg,
            valArg: pushInfo.valArg
        };
    }
}
#end
