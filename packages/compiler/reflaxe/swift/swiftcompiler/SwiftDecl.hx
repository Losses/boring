package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import ValueTypeSupport;
import PolicyQueries;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceComparisonRequest;
import swiftcompiler.SwiftComparisonPlan;
import swiftcompiler.SwiftComparisonPlan.SwiftComparisonPlanResult;
import swiftcompiler.SwiftComparisonPlan.SwiftRecordPlan;
import swiftcompiler.SwiftComparisonPlan.SwiftComparisonOperation;
import ValueTypeSupport.ValueTypeInfo;
import ValueTypeSupport.ValueTypeOperator;
import NameConversion;
import swiftcompiler.SwiftArrayBoundary.SwiftArrayPreparedOperand;
import swiftcompiler.SwiftParameterPlan.SwiftParameterDefaultMode;
import swiftcompiler.SwiftParameterPlan;

/**
    Declaration lowering: classes, variant enums, and record typedefs
    (docs/specs/features/07-numeric-tower.md). One SwiftDecl instance owns the
    per-module emission context (imports, types, expression state) so
    every declaration in the same Haxe module is written to one Swift file.
    The whole tree shares one Swift module, so no import block renders;
    what the context tracks is runtime usage and the resident ABI mode.
**/
class SwiftDecl {
    final imports:SwiftImports;
    final types:SwiftType;
    final expr:SwiftExpr;

    public function new(selfModule:String) {
        this.imports = new SwiftImports(selfModule);
        this.types = new SwiftType(imports);
        this.expr = new SwiftExpr(imports, types);
    }

    /** Whether this module references any runtime-package symbol. */
    public function usesRuntime():Bool {
        return imports.usesRuntime();
    }

    /** Whether this module uses Foundation APIs. */
    public function usesFoundation():Bool {
        return imports.usesFoundation();
    }

    /** Whether this module references any test-host symbol. */
    public function usesRuntimeTest():Bool {
        return imports.usesRuntimeTest();
    }

    /** Whether this module references the swift-system package (stdlib/17). */
    public function usesSystemPackage():Bool {
        return imports.usesSystemPackage();
    }

    /** Host-edge helper keys this module references (stdlib/17). */
    public function hostEdgeKeys():Array<String> {
        return imports.hostEdgeNames();
    }

    public function topLevelStatements(e:TypedExpr):String {
        return expr.topLevelStatements(e);
    }

    public function rawExpression(e:TypedExpr):String {
        return expr.rawExpression(e);
    }

    /** Widen an Int const val initializer to Float when the field type is Float. */
    function constValFloatInit(init:TypedExpr, fieldType:Type):String {
        final text = expr.rawExpression(init);
        if (expr.isIntType(expr.emittedType(init)) && expr.isFloatLeafType(fieldType))
            return expr.intToFloatText(text);
        return text;
    }

    // ------------------------------------------------------------------
    // Classes
    // ------------------------------------------------------------------

    /**
        Visibility for a below-public member. @:allow members use Swift
        internal unconditionally. Members of a class named by a class level
        @:access grant (or by a cross-module synthesized default) widen to
        internal, unless their signature names a module-private type (a
        same-name type in another file would turn ambiguous), so those stay
        file-scoped with fileprivate, which still admits same-file peers.
        Everything else stays private.
    **/
    static function grantedVis(isPublic:Bool, meta:MetaAccess, cls:ClassType, memberType:Type):String {
        if (isPublic) {
            return "public ";
        }
        if (meta.has(":allow")) {
            return "";
        }
        if (AccessGrants.has(cls.module + "." + cls.name)) {
            return AccessGrants.mentionsPrivateType(memberType) ? "fileprivate " : "";
        }
        return "private ";
    }

    public function classDecl(cls:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):String {
        if (cls.isInterface) {
            // An interface lowers to a protocol; the implementing class
            // names it in its conformance clause.
            final lines:Array<String> = ["public protocol " + cls.name + " {"];
            for (f in funcFields) {
                // A getter-only property is also a protocol property
                // requirement: consuming Swift code reads it by name through
                // the existential, which only the `var` requirement admits.
                if (!f.isStatic && StringTools.startsWith(f.field.name, "get_")) {
                    final propName = f.field.name.substring("get_".length);
                    for (field in cls.fields.get()) {
                        if (field.name == propName && isGetterOnlyProperty(field)) {
                            lines.push("    var " + SwiftNameEscape.escape(propName) + ": " + types.of(field.type) + " { get }");
                        }
                    }
                }
                // A protocol method cannot declare a default argument, so
                // the parameter list renders bare here; the implementing
                // class carries the default.
                final throws = SwiftFallibility.isThrowing(cls.module, cls.name, f.field.name, f.isStatic) ? " throws" : "";
                lines.push("    func " + f.field.name + paramList(cls, f, 0, false) + throws + " -> " + types.of(f.ret));
            }
            lines.push("}");
            return lines.join("\n");
        }

        if (cls.superClass != null && exceptionDepth(cls) == 0) {
            final parent = cls.superClass.t.get();
            final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
            Context.error("super class has no Swift lowering in the subset: " + parentPath, cls.pos);
        }

        final module = cls.module;
        deferredConstructorFields = constructorSelfCallFields(funcFields);
        final extractedFuncs = [for (f in funcFields) if (StaticFunctionMarkers.isMarked(f.field)) f];
        final ordinaryFuncs = [for (f in funcFields) if (!StaticFunctionMarkers.isMarked(f.field)) f];
        final extractedParts:Array<String> = [];
        for (f in extractedFuncs) {
            extractedParts.push(extractedFuncDecl(module, cls, f).join("\n"));
        }
        final selectedComparator:Null<SwiftRecordPlan> = if (cls.meta.has(":dataClass")) switch (SwiftComparisonPlan.select(SourceComparisonAnalysis.declarationReference(cls),
                [for (parameter in cls.params) parameter.t], OptionalEqualityCapability)) {
            case SwiftComparisonPlanReady(plan): plan;
            case SwiftComparisonPlanFailed(_, _, _): null;
            case SwiftComparisonPlanUnresolved(path, reason): Context.error("Swift comparator analysis incomplete at " + path + ": " + reason, cls.pos); null;
        } else null;
        final sortedComparator:Null<SwiftRecordPlan> = if (cls.meta.has(":dataClass")) switch (SwiftComparisonPlan.selectSchema(SourceComparisonAnalysis.declarationReference(cls), SortedKey)) {
            case SwiftComparisonPlanReady(plan): plan;
            case SwiftComparisonPlanFailed(_, _, _): null;
            case SwiftComparisonPlanUnresolved(path, reason): Context.error("Swift sorted comparator analysis incomplete at " + path + ": " + reason, cls.pos); null;
        } else null;
        final comparatorPlan = sortedComparator == null ? selectedComparator : sortedComparator;
        final shouldEmitComparator = selectedComparator != null;
        if (varFields.length == 0 && ordinaryFuncs.length == 0) {
            final emptyClass = extractedParts.join("\n\n");
            return comparatorPlan != null ? emptyClass + "\n\n" + dataClassComparator(comparatorPlan) : emptyClass;
        }

        final staticsOnly = isStaticsOnly(varFields, ordinaryFuncs);
        final lines:Array<String> = [];

        // A statics-only class lowers to a case-less enum namespace; an
        // instance class lowers to a final class, except exception classes
        // render open so deeper generations can subclass them.
        final classParams = cls.params.length > 0 ? "<" + [for (p in cls.params) p.name].join(", ") + ">" : "";
        if (staticsOnly) {
            lines.push("public enum " + cls.name + classParams + " {");
        } else {
            final depth = exceptionDepth(cls);
            final conformances:Array<String> = [];
            if (shouldEmitComparator) {
                conformances.push("Equatable");
            }
            if (depth == 1) {
                // The conformance names the runtime base class, so this
                // file references the runtime package. Record the use: a
                // tree whose only exception path is caught by its concrete
                // type names no haxe.Exception and would otherwise omit
                // Runtime.swift (task t-mun5d99p-op76).
                imports.runtime("BoringException");
                conformances.push("BoringException");
            } else if (depth >= 2) {
                // A deeper exception subclass inherits from its parent
                // class; BoringException arrives through that chain, and a
                // repeated conformance is a Swift compile error.
                conformances.push(cls.superClass.t.get().name);
            }
            for (i in cls.interfaces) {
                conformances.push(i.t.get().name);
            }
            // A Haxe module-private type stays file-scoped in Swift; the
            // same type name declared in another module would otherwise
            // make every bare reference ambiguous.
            final access = cls.isPrivate ? "private " : "public ";
            lines.push((depth >= 1 ? access + "class " : access + "final class ")
                + cls.name
                + classParams
                + (conformances.length > 0 ? ": " + conformances.join(", ") : "")
                + " {");
        }

        // One blank line between members; none inside a member's body.
        for (v in varFields) {
            final decl = varDecl(cls, module, v);
            if (decl.length == 0) {
                continue;
            }
            if (lines.length > 1) {
                lines.push("");
            }
            for (l in decl) {
                lines.push(l);
            }
        }
        for (f in ordinaryFuncs) {
            if (lines.length > 1) {
                lines.push("");
            }
            // A computed property renders beside its accessor function
            // (feature spec 27).
            if (!f.isStatic && StringTools.startsWith(f.field.name, "get_")) {
                final propName = f.field.name.substring("get_".length);
                for (field in cls.fields.get()) {
                    if (field.name == propName && isGetterOnlyProperty(field)) {
                        for (l in propertyDecl(cls, field)) {
                            lines.push(l);
                        }
                        lines.push("");
                    }
                }
            }
            for (l in funcDecl(module, cls, f)) {
                lines.push(l);
            }
        }

        if (selectedComparator != null && !staticsOnly) {
            // Swift classes do not receive synthesized Equatable conformance;
            // route the native operator through the generated value comparator.
            final equalityType = cls.name + (cls.params.length == 0 ? "" : "<" + [for (parameter in cls.params) parameter.name].join(", ") + ">");
            lines.push("");
            lines.push("    public static func == (lhs: " + equalityType + ", rhs: " + equalityType + ") -> Bool {");
            lines.push("        return " + selectedComparator.name + "(lhs, rhs) == 0");
            lines.push("    }");
        }
        lines.push("}");
        final classPart = lines.join("\n");
        final result = extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + classPart : classPart;
        return comparatorPlan != null ? result + "\n\n" + dataClassComparator(comparatorPlan) : result;
    }

    /** Emits a marked abstract as a value-semantic Swift struct. */
    public function valueTypeDecl(cls:ClassType, info:ValueTypeInfo, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):String {
        final abs = info.abstractType;
        final ctor = ValueTypeSupport.constructorField(abs);
        final first = ctor == null ? null : ValueTypeSupport.firstArgument(ctor);
        if (first == null) {
            Context.error("value type constructor must take its representation", cls.pos);
        }
        final fieldName = SwiftNameEscape.escape(first.name);
        final representation = types.of(info.representation);
        final hasToString = ValueTypeSupport.memberField(abs, "toString") != null;
        final conformances = ["Equatable", "Hashable"];
        if (hasToString)
            conformances.push("CustomStringConvertible");
        final lines:Array<String> = ["public struct " + info.name + ": " + conformances.join(", ") + " {"];
        final ctorThrows = ctor != null && ValueTypeSupport.constructorThrows(abs);
        lines.push("    public let " + fieldName + ": " + representation);
        lines.push("    public init(_ " + fieldName + ": " + representation + ")" + (ctorThrows ? " throws" : "") + " {");
        if (ctorThrows) {
            for (line in expr.valueTypeConstructorBody(cls, findFunc(funcFields, "_new")))
                lines.push("    " + line);
        }
        lines.push("        self." + fieldName + " = " + fieldName);
        lines.push("    }");

        for (f in funcFields) {
            if (f.field.name == "_new"
                || f.field.name == "toString"
                || (ValueTypeSupport.isInlineHelper(f.field) && ValueTypeSupport.operatorOf(abs, f.field) == null))
                continue;
            final op = ValueTypeSupport.operatorOf(abs, f.field);
            final isOperator = op != null;
            if (!isOperator && SwiftNameEscape.escape(f.field.name) == fieldName) {
                // Swift cannot declare a method and a stored property with
                // the same base name. An inline method carrying the stored
                // field's name is the underlying-value accessor: Haxe
                // expands every call in place, so no generated reference
                // names it and the declaration is dropped. A non-inline
                // collision would have generated callers, so it is
                // rejected up front.
                if (f.field.kind.match(FMethod(MethInline))) {
                    continue;
                }
                Context.error("value type method "
                    + f.field.name
                    + " collides with the stored property name; make the method inline or rename the constructor parameter",
                    f.field.pos);
            }
            final receiver = ValueTypeSupport.hasReceiver(f.field);
            final start = isOperator ? 0 : (receiver ? 1 : 0);
            final name = isOperator ? swiftOperatorName(op) : f.field.name;
            final ret = types.of(f.ret);
            final head = if (isOperator) {
                switch (op) {
                    case Binary(_): "    public static func " + name + "(lhs: " + info.name + ", rhs: " + info.name + ") -> " + ret + " {";
                    case Unary(_): "    public static prefix func " + name + "(value: " + info.name + ") -> " + ret + " {";
                }
            } else {
                final args = [
                    for (i in start...f.args.length) {
                        final a = f.args[i];
                        "_ " + a.name + ": " + types.of(a.type);
                    }
                ].join(", ");
                "    " + (f.field.isPublic ? "public " : "private ") + "func " + name + "(" + args + ") -> " + ret + " {";
            };
            lines.push("");
            lines.push(head);
            for (line in expr.valueTypeFunctionBody(cls, f, fieldName))
                lines.push("    " + line);
            lines.push("    }");
        }

        if (hasToString) {
            final f = findFunc(funcFields, "toString");
            lines.push("");
            lines.push("    public var description: String {");
            for (line in expr.valueTypeFunctionBody(cls, f, fieldName))
                lines.push("    " + line);
            lines.push("    }");
        }

        for (v in varFields) {
            if (!v.isStatic)
                continue;
            final initializer = v.field.expr();
            if (initializer == null)
                Context.error("value type static field must have an initializer", v.field.pos);
            final initText = expr.rawExpression(initializer);
            final val = ValueTypeSupport.isBareRepresentationLiteral(initializer, info.representation) ? info.name + "(" + initText + ")" : initText;
            lines.push("");
            lines.push("    public static let " + SwiftNameEscape.escape(v.field.name) + ": " + info.name + " = " + val);
        }
        lines.push("}");
        return lines.join("\n");
    }

    function findFunc(funcFields:Array<ClassFuncData>, name:String):ClassFuncData {
        return PolicyQueries.findFunc(funcFields, name, "value type member is missing: " + name);
    }

    function dataClassComparator(plan:SwiftRecordPlan):String {
        final cls = plan.source.source.declaration;
        for (dependency in plan.dependencies)
            imports.runtime(dependency);
        final genericParams = [for (parameter in cls.params) parameter.name];
        final genericClause = genericParams.length == 0 ? "" : "<" + genericParams.join(", ") + ">";
        final typeName = cls.name + (genericParams.length == 0 ? "" : "<" + genericParams.join(", ") + ">");
        final lines:Array<String> = [];
        for (helper in plan.enumHelpers) {
            imports.type(helper.declaration.module, helper.declaration.name);
            final enumType = helper.declaration.name + (helper.arguments.length == 0 ? "" : "<" + [for (argument in helper.arguments) types.of(argument)].join(", ") + ">");
            lines.push("    func " + helper.name + "(_ value: " + enumType + ") -> Int32 {");
            lines.push("        switch value {");
            for (constructor in helper.constructors) {
                final payload = switch (constructor.type) {
                    case TFun(args, _): args.length == 0 ? "" : "(" + [for (_ in args) "_"].join(", ") + ")";
                    case _: "";
                };
                lines.push("        case ." + lowerFirst(constructor.name) + payload + ": return " + constructor.index);
            }
            lines.push("        }");
            lines.push("    }");
        }
        final evidenceParams = [for (index in plan.requiredArguments) "compareArgument" + index + ": (" + genericParams[index] + ", " + genericParams[index] + ") -> Int32"];
        lines.push((cls.isPrivate ? "private" : "public") + " func " + plan.name + genericClause + "(_ a: " + typeName + ", _ b: " + typeName
            + (evidenceParams.length == 0 ? "" : ", " + evidenceParams.join(", ")) + ") -> Int32 {");
        final localIndex = [0];
        for (field in plan.fields) {
            emitComparisonOperation(plan, field.operation, "a." + SwiftNameEscape.escape(field.field.name), "b." + SwiftNameEscape.escape(field.field.name), "    ", lines, localIndex);
        }
        lines.push("    return 0");
        lines.push("}");
        return lines.join("\n");
    }

    function emitComparisonOperation(owner:SwiftRecordPlan, operation:SwiftComparisonOperation, left:String, right:String, indent:String, lines:Array<String>, localIndex:Array<Int>):Void {
        switch (operation) {
            case SwiftIntegerOrder:
                lines.push(indent + "if " + left + " < " + right + " { return -1 }");
                lines.push(indent + "if " + left + " > " + right + " { return 1 }");
            case SwiftFloatOrder:
                lines.push(indent + "if " + left + " < " + right + " { return -1 }");
                lines.push(indent + "if " + left + " > " + right + " { return 1 }");
            case SwiftBooleanOrder:
                lines.push(indent + "if " + left + " != " + right + " { return " + left + " ? 1 : -1 }");
            case SwiftParameterOrder(index):
                final comparison = allocateComparisonLocal(localIndex);
                lines.push(indent + "let " + comparison + " = compareArgument" + index + "(" + left + ", " + right + ")");
                lines.push(indent + "if " + comparison + " != 0 { return " + comparison + " }");
            case SwiftUtf16StringOrder:
                final comparison = allocateComparisonLocal(localIndex);
                lines.push(indent + "let " + comparison + " = compareUnitOrder(" + left + ", " + right + ")");
                lines.push(indent + "if " + comparison + " != 0 { return " + comparison + " }");
            case SwiftEnumOrdinalOrder(helper, _, _):
                final leftOrder = allocateComparisonLocal(localIndex);
                final rightOrder = allocateComparisonLocal(localIndex);
                lines.push(indent + "let " + leftOrder + " = " + helper + "(" + left + ")");
                lines.push(indent + "let " + rightOrder + " = " + helper + "(" + right + ")");
                lines.push(indent + "if " + leftOrder + " < " + rightOrder + " { return -1 }");
                lines.push(indent + "if " + leftOrder + " > " + rightOrder + " { return 1 }");
            case SwiftRecordOrder(record, arguments):
                final comparison = allocateComparisonLocal(localIndex);
                final evidence:Array<String> = [for (index in record.requiredArguments) {
                    final parentIndex = index < arguments.length ? SourceComparisonAnalysis.schemaParameterIndex(arguments[index], owner.source.source.arguments) : null;
                    parentIndex == null ? "" : "compareArgument" + index + ": compareArgument" + parentIndex;
                }].filter(value -> value != "");
                lines.push(indent + "let " + comparison + " = " + record.name + "(" + left + ", " + right
                    + (evidence.length == 0 ? "" : ", " + evidence.join(", ")) + ")");
                lines.push(indent + "if " + comparison + " != 0 { return " + comparison + " }");
            case SwiftNullBeforePresent(child):
                lines.push(indent + "if " + left + " == nil && " + right + " != nil { return -1 }");
                lines.push(indent + "if " + left + " != nil && " + right + " == nil { return 1 }");
                final leftValue = allocateComparisonLocal(localIndex);
                final rightValue = allocateComparisonLocal(localIndex);
                lines.push(indent + "if let " + leftValue + " = " + left + ", let " + rightValue + " = " + right + " {");
                emitComparisonOperation(owner, child, leftValue, rightValue, indent + "    ", lines, localIndex);
                lines.push(indent + "}");
            case SwiftLexicographic(child):
                final index = allocateComparisonLocal(localIndex);
                lines.push(indent + "var " + index + " = 0");
                lines.push(indent + "while " + index + " < " + left + ".count && " + index + " < " + right + ".count {");
                emitComparisonOperation(owner, child, left + "[" + index + "]", right + "[" + index + "]", indent + "    ", lines, localIndex);
                lines.push(indent + "    " + index + " += 1");
                lines.push(indent + "}");
                lines.push(indent + "if " + left + ".count < " + right + ".count { return -1 }");
                lines.push(indent + "if " + left + ".count > " + right + ".count { return 1 }");
        }
    }

    static function allocateComparisonLocal(localIndex:Array<Int>):String {
        final result = "_compareLocal" + localIndex[0];
        localIndex[0] += 1;
        return result;
    }

    function swiftOperatorName(op:ValueTypeOperator):String {
        return switch (op) {
            case Binary(binary): switch (binary) {
                    case OpAdd: "+";
                    case OpSub: "-";
                    case OpMult: "*";
                    case OpDiv: "/";
                    case OpMod: "%";
                    case OpEq: "==";
                    case OpNotEq: "!=";
                    case OpLt: "<";
                    case OpLte: "<=";
                    case OpGt: ">";
                    case OpGte: ">=";
                    case _: "+";
                };
            case Unary(unary): switch (unary) {
                    case OpNeg: "-";
                    case _: "+";
                };
        };
    }

    static function isStaticsOnly(varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Bool {
        for (v in varFields) {
            if (!v.isStatic) {
                return false;
            }
        }
        for (f in funcFields) {
            if (!f.isStatic) {
                return false;
            }
        }
        return true;
    }

    /** Hop count up the super chain to haxe.Exception; 0 when the chain does not reach it. */
    public static function exceptionDepth(cls:ClassType):Int {
        return PolicyQueries.exceptionDepth(cls);
    }

    /** A class whose super chain reaches haxe.Exception is one of the features/06 exception classes. */
    public static function isException(cls:ClassType):Bool {
        return exceptionDepth(cls) >= 1;
    }

    // ------------------------------------------------------------------
    // Record shape registry
    // ------------------------------------------------------------------

    /**
        Structure signature to the named record typedef of that shape.
        The typer leaves an object literal's own type anonymous even where
        unification matched a named typedef, so nominal lowering matches
        literals against typedefs through this signature.
    **/
    public static final structTypedefs:Map<String, Ref<DefType>> = [];

    /** Fields assigned after a constructor invokes an instance method. */
    var deferredConstructorFields:Map<String, Bool> = [];

    /**
        Signature identifying an anonymous structure: its field names and
        types, sorted. Nominal lowering matches object literals against
        typedefs through this signature.
    **/
    public static function structureSignature(anon:Ref<AnonType>):String {
        return PolicyQueries.structureSignature(anon);
    }

    /** Registers one record typedef; two names for one shape would make nominal matching ambiguous. */
    public static function registerStructTypedef(def:Ref<DefType>):Void {
        switch (def.get().type) {
            case TAnonymous(anon):
                final sig = structureSignature(anon);
                final existing = structTypedefs.get(sig);
                if (existing != null && (existing.get().name != def.get().name || existing.get().module != def.get().module)) {
                    Context.error("typedefs " + existing.get().name + " and " + def.get().name + " share one anonymous structure shape", def.get().pos);
                }
                structTypedefs.set(sig, def);
            case _:
        }
    }

    function varDecl(cls:ClassType, module:String, v:ClassVarData):Array<String> {
        final field = v.field;
        if (v.isStatic && DataTableHelper.isDataTableField(field)) {
            final elems = DataTableHelper.getDataTableElements(field.expr());
            if (elems != null) {
                imports.runtime("TiqianArray");
                return ["    public static let "
                    + SwiftNameEscape.escape(field.name)
                    + ": TiqianArray<Int32> = TiqianArray(["
                    + renderDataTableElements(elems)
                    + "])"];
            }
        }
        if (v.isStatic && isFunctionType(field.type)) {
            final initializer = field.expr();
            if (initializer == null) {
                Context.error("static function fields require initializers", field.pos);
                return [];
            }
            return ["    public static let "
                + SwiftNameEscape.escape(field.name)
                + ": "
                + types.of(field.type)
                + " = "
                + constValFloatInit(initializer, field.type)];
        }
        if (v.isStatic) {
            final init = StaticFieldHelper.validatedInitializer(field, cls);
            final array = StaticFieldHelper.isArrayType(field.type);
            final smallArray = field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init);
            final kw = smallArray ? "let" : (array || !field.isFinal ? "var" : "let");
            // @:allow members use Swift internal visibility so allowed cross-class calls compile.
            final vis = grantedVis(field.isPublic, field.meta, cls, field.type);
            final initText = constValFloatInit(init, field.type);
            // Swift forbids a throw from a global/static stored initializer;
            // the value is a compile-time fixture, so force the fault and
            // let a failure trap at load (stdlib/08/27).
            var rendered = expr.containsThrowingCall(init) ? "try! " + initText : initText;
            if (StaticFieldHelper.isReadOnlyArrayType(field.type)) {
                final isEmpty = switch (init.expr) {
                    case TArrayDecl(elements): elements.length == 0;
                    case _: false;
                };
                final isNull = switch (init.expr) {
                    case TConst(TNull): true;
                    case _: false;
                };
                final storage = SwiftArrayBoundary.sourceStorage(init.t, isEmpty, isNull);
                final optionality = isNull ? SwiftArrayBoundary.SwiftArrayOptionality.OptionalOperand : SwiftArrayBoundary.SwiftArrayOptionality.RequiredOperand;
                final operand:SwiftArrayPreparedOperand = {
                    text: rendered,
                    sourceType: init.t,
                    storage: storage,
                    optionality: optionality,
                    presenceFact: isNull ? SwiftArrayBoundary.SwiftArrayPresenceFact.NoPresenceProof : SwiftArrayBoundary.SwiftArrayPresenceFact.LiteralProvenPresent
                };
                final plan = SwiftArrayBoundary.prepare(operand, field.type);
                if (plan == null) {
                    Context.error("read-only array initializer has no prepared storage decision", init.pos);
                } else {
                    final elementText = plan.elementType == null ? null : types.of(plan.elementType);
                    rendered = SwiftArrayBoundary.render(plan, operand.text, elementText);
                }
            }
            // A non-null Haxe field initialized to null becomes an implicitly
            // unwrapped optional: the declaration admits the nil start while
            // reads stay plain, matching the Haxe null-until-assigned idiom.
            final declaredType = types.of(field.type);
            final nullInit = switch (init.expr) {
                case TConst(TNull): true;
                case _: false;
            };
            final typeText = nullInit && !StringTools.endsWith(declaredType, "?") ? declaredType + "!" : declaredType;
            return [
                "    " + vis + "static " + kw + " " + SwiftNameEscape.escape(field.name) + ": " + typeText + " = " + rendered
            ];
        }
        // The Haxe typer places instance field defaults in the
        // constructor, so the declaration stays bare and the init
        // body carries the assignments.
        // A final Haxe field keeps the reference binding while the array
        // contents remain mutable. Array fields therefore use var.
        // Swift let array forbids that, so array fields stay var.
        final isArrayField = switch (field.type) {
            case TInst(c, _): c.get().name == "Array" || c.get().name == "StringBuf";
            case TLazy(f): switch (f()) {
                    case TInst(c, _): c.get().name == "Array" || c.get().name == "StringBuf";
                    case _: false;
                };
            case _: false;
        };
        final kw = isArrayField || !field.isFinal ? "var" : "let";
        // Private fields render with Swift's private marker (feature
        // spec 27); public fields render public for the SwiftPM split
        // between the generated-code module and its consumers.
        // @:allow members use Swift internal visibility so allowed cross-class calls compile.
        final vis = grantedVis(field.isPublic, field.meta, cls, field.type);
        final deferred = deferredConstructorFields.exists(field.name);
        return ["    "
            + vis
            + (deferred ? "var " : kw + " ")
            + SwiftNameEscape.escape(field.name)
            + ": "
            + types.of(field.type)
            + (deferred ? "! = nil" : "")];
    }

    /**
        Named heuristic: constructor self-call deferral. Swift requires every
        stored property to be initialized before an instance method call. A
        field assigned later in the same constructor receives an IUO default,
        preserving the source order and its eventual value.
    **/
    static function constructorSelfCallFields(funcFields:Array<ClassFuncData>):Map<String, Bool> {
        final result:Map<String, Bool> = [];
        for (f in funcFields) {
            if (f.field.name != "new" || f.expr == null)
                continue;
            var selfCallSeen = false;
            for (stmt in PolicyQueries.statementsOf(f.expr)) {
                if (containsConstructorSelfMethodCall(stmt))
                    selfCallSeen = true;
                if (selfCallSeen)
                    collectAssignedInstanceFields(stmt, result);
            }
        }
        return result;
    }

    static function containsConstructorSelfMethodCall(e:TypedExpr):Bool {
        var found = false;
        function inspect(child:TypedExpr):Void {
            switch (child.expr) {
                case TCall({expr: TField({expr: TConst(TThis)}, FInstance(_, _, _))}, _):
                    found = true;
                case _:
            }
            if (!found)
                haxe.macro.TypedExprTools.iter(child, inspect);
        }
        inspect(e);
        return found;
    }

    // The scan must descend: a top-level assignment is the statement root
    // itself, and a loop or branch nests its assignments further down.
    static function collectAssignedInstanceFields(e:TypedExpr, result:Map<String, Bool>):Void {
        switch (e.expr) {
            case TBinop(OpAssign, {expr: TField({expr: TConst(TThis)}, access)}, _) | TBinop(OpAssignOp(_), {expr: TField({expr: TConst(TThis)}, access)}, _):
                switch (access) {
                    case FInstance(_, _, field): result.set(field.get().name, true);
                    case _:
                }
            case _:
        }
        haxe.macro.TypedExprTools.iter(e, function(child:TypedExpr):Void collectAssignedInstanceFields(child, result));
    }

    static function isFunctionType(t:Null<Type>):Bool {
        return PolicyQueries.isFunctionType(t);
    }

    /** A `var x(get, never)` field renders no storage on this target (feature spec 27). */
    function isGetterOnlyProperty(field:ClassField):Bool {
        return PolicyQueries.isGetterOnlyProperty(field);
    }

    /**
        A getter-only property renders as a computed property reading the
        standard accessor (feature spec 27). The typer lowers property
        reads to `get_x()` calls, so the computed property serves
        consuming Swift code.
    **/
    function propertyDecl(cls:ClassType, field:ClassField):Array<String> {
        // @:allow members use Swift internal visibility so allowed cross-class calls compile.
        final vis = grantedVis(field.isPublic, field.meta, cls, field.type);
        final getter = "get_" + field.name;
        // A Swift computed property cannot rethrow; the backing getter is a
        // compile-time fixture accessor, so force the fault at the access.
        final getterThrows = SwiftFallibility.isThrowing(cls.module, cls.name, getter, false);
        return ["    "
            + vis
            + "var "
            + SwiftNameEscape.escape(field.name)
            + ": "
            + types.of(field.type)
            + " { "
            + (getterThrows ? "try! " : "")
            + getter
            + "() }"];
    }

    function renderDataTableElements(elems:Array<Int>):String {
        final formatted = [for (x in elems) (x >= 0 && x <= 9) ?Std.string(x):"0x" + StringTools.hex(x).toLowerCase()];
        final chunks:Array<String> = [];
        var i = 0;
        while (i < formatted.length) {
            final end = Std.int(Math.min(i + 8, formatted.length));
            chunks.push("\n        " + formatted.slice(i, end).join(", "));
            i = end;
        }
        return chunks.join(",") + "\n    ";
    }

    /**
        One @:test function (features/19): a static throwing function on
        the module's test namespace. The runner entry that calls it is written
        in TestMain.swift.
    **/
    public function testFuncDecl(cls:ClassType, f:ClassFuncData):Array<String> {
        for (a in f.args) {
            expr.reserveName(a.name);
        }
        final throws = SwiftFallibility.isThrowing(cls.module, cls.name, f.field.name, true) ? " throws" : "";
        final body = expr.functionBody(cls, f);
        return [
            "    public static func " + SwiftNameEscape.escape(f.field.name) + "()" + throws + " -> Void {"
        ].concat(body).concat(["    }"]);
    }

    /** Function declarations append the parameter shadows after the body scan. */
    function withParamShadows(head:Array<String>, body:Array<String>, args:Array<{name:String, ?tvar:Null<TVar>}>, depth:Int = 2):Array<String> {
        return head.concat(expr.shadowMutatedParams(args, depth)).concat(body);
    }

    function funcDecl(module:String, cls:ClassType, f:ClassFuncData):Array<String> {
        // Haxe types constructors as FMethod(MethNormal) with field name
        // "new"; the name is the constructor marker. Swift initializes
        // stored properties before the super call, the reverse of the
        // Haxe source order.
        if (f.field.name == "new") {
            for (a in f.args) {
                expr.reserveName(a.name);
            }
            final body = expr.constructorBody(cls, cls.name, f, isException(cls));
            // A throwing constructor declares throws (feature spec 27);
            // construction sites pick up the try marker from the
            // fallibility machinery.
            final ctorThrows = SwiftFallibility.isThrowing(module, cls.name, "new", false) ? " throws" : "";
            // A constructor parameter whose coalescing default reads an
            // earlier parameter carries `T? = nil` in the parameter list
            // (paramList), so the body needs the same entry shadow the
            // method form emits; the field assignment then reads the
            // normalized value.
            final normLines = coalescingBodyNormalizationLines(cls, f);
            return withParamShadows(["    public init" + paramList(cls, f) + ctorThrows + " {"], normLines.concat(body), cast f.args).concat(["    }"]);
        }
        for (a in f.args) {
            expr.reserveName(a.name);
        }
        // The body-wide unused pass must run for every method entry, so
        // test-support classes get the same underscore naming as business
        // methods. (UnusedLocalNaming)
        expr.scanUnusedLocals(f.expr, cls.name + "." + f.field.name);
        final ret = types.of(f.ret);
        final stat = f.isStatic ? "static " : "";
        final throws = SwiftFallibility.isThrowing(module, cls.name, f.field.name, f.isStatic) ? " throws" : "";
        // A method's own type parameters (the resident builders'
        // factory functions) render as method generics; the class's own
        // parameters stay in the class header only.
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodGenericSignature(cls, f, methodParams);
        final body = decodeBoundaryBody(cls, f);
        final normLines = coalescingBodyNormalizationLines(cls, f);
        // Private functions render with Swift's private marker (feature
        // spec 27); public functions render public for the SwiftPM split.
        // @:allow members use Swift internal visibility so allowed cross-class calls compile.
        // Swift requires a member satisfying a protocol requirement to be
        // at least as accessible as the protocol, and protocols render
        // public, so interface methods render public regardless of their
        // Haxe visibility.
        final vis = isInterfaceMethod(cls, f) ? "public " : grantedVis(f.field.isPublic, f.field.meta, cls, f.field.type);
        final head = '    $vis$stat' + 'func ${SwiftNameEscape.escape(f.field.name)}$genericStr${paramList(cls, f)}$throws -> $ret {';
        return withParamShadows([head], normLines.concat(body), cast f.args).concat(["    }"]);
    }

    /** True when the function's name matches a field of an implemented interface. */
    function isInterfaceMethod(cls:ClassType, f:ClassFuncData):Bool {
        for (iface in cls.interfaces) {
            final ifaceCls = iface.t.get();
            for (field in ifaceCls.fields.get()) {
                if (field.name == f.field.name)
                    return true;
            }
        }
        return false;
    }

    function extractedFuncDecl(module:String, cls:ClassType, f:ClassFuncData):Array<String> {
        for (a in f.args) {
            expr.reserveName(a.name);
        }
        final isExtension = StaticFunctionMarkers.isExtension(f.field);
        final firstArg = isExtension ? 1 : 0;
        final ret = types.of(f.ret);
        final throws = SwiftFallibility.isThrowing(module, cls.name, f.field.name, true) ? " throws" : "";
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodGenericSignature(cls, f, methodParams);
        // @:allow members use Swift internal visibility so allowed cross-class calls compile.
        final vis = grantedVis(f.field.isPublic, f.field.meta, cls, f.field.type);
        final receiverType = isExtension ? types.of(f.args[0].type) : "";
        final methodIndent = isExtension ? "    " : "";
        final head = methodIndent + vis + "func " + SwiftNameEscape.escape(f.field.name) + genericStr + paramList(cls, f, firstArg) + throws + " -> " + ret
            + " {";
        if (isExtension && f.args[0].tvar != null) {
            expr.bindLocalName(f.args[0].tvar, "self");
        }
        final body = decodeBoundaryBody(cls, f, isExtension ? 2 : 1);
        final method = withParamShadows([head], body, cast f.args, isExtension ? 2 : 1).concat([methodIndent + "}"]);
        return isExtension ? (["extension " + receiverType + " {"]).concat(method).concat(["}"]) : method;
    }

    /**
        Parameter rendering: positional calls throughout, so every
        parameter takes the wildcard label. Function-typed parameters
        carry @escaping because the resident tables store their
        comparator.
    **/
    function paramList(cls:ClassType, f:ClassFuncData, start:Int = 0, allowDefaults:Bool = true):String {
        return "(" + [
            for (i in start...f.args.length) {
                final a = f.args[i];
                // The registered default covers every shape: a coalescing
                // body pattern, an explicit constant, and an optional
                // parameter's implicit null. Swift resolves an omitted
                // argument through the signature default, so all three
                // render; a constant converts through coalescingOf.
                final decision = SwiftParameterPlan.forArgument(cls, f.field.name, a.name, a.index, a.type, allowDefaults);
                final coalescing = decision.coalescingValue;
                // When the default reads an earlier parameter or can throw,
                // Swift cannot carry the expression in the signature: a
                // default argument expression cannot reference other
                // parameters and cannot throw. The parameter takes an
                // Optional type with a nil default and the body normalizes
                // it (coalescingBodyNormalizationLines).
                final escaping = switch (Context.follow(a.type)) {
                    case TFun(_, _): "@escaping ";
                    case _: "";
                };
                final parameterType = decision.parameterType;
                final defaultText = switch (decision.defaultMode) {
                    case NoParameterDefault: "";
                    case OptionalNilBodyDefault: " = nil";
                    case NativeValueDefault: " = " + expr.coalescingDefaultText(coalescing, a.type);
                };
                if (SwiftInoutParams.isMutatingParam(cls.module, cls.name, f.field.name, a.name, a.index)) {
                    if (coalescing != null) {
                        Context.error("inout parameter cannot have a default value: " + a.name, f.field.pos);
                    }
                    "_ " + SwiftNameEscape.escape(a.name) + ": inout " + escaping + types.of(parameterType);
                } else {
                    "_ " + SwiftNameEscape.escape(a.name) + ": " + escaping + types.of(parameterType) + defaultText;
                }
            }
        ].join(", ") + ")";
    }

    /**
        The names of a function's own type parameters, in first-use
        order over the signature. A generic method references its
        parameters as type-parameter classes; the enclosing class owns its
        parameters in the class header.
    **/
    function collectMethodTypeParams(cls:ClassType, f:ClassFuncData):Array<String> {
        final classParamNames = [for (p in cls.params) p.name];
        final found:Array<String> = [];
        collectTypeParamsInto(f.ret, classParamNames, found);
        for (a in f.args) {
            collectTypeParamsInto(a.type, classParamNames, found);
        }
        return found;
    }

    function collectTypeParamsInto(t:Null<Type>, skip:Array<String>, found:Array<String>):Void {
        return PolicyQueries.collectTypeParamsInto(t, skip, found);
    }

    /**
        Generic equality constraint: a method type parameter compared with
        `==` or `!=` in the body has no Swift operator without a protocol
        conformance, so the signature constrains exactly the compared
        parameters to Equatable. Haxe unifies the comparison against the
        bare type parameter and needs no such bound.
    **/
    function methodGenericSignature(cls:ClassType, f:ClassFuncData, methodParams:Array<String>):String {
        if (methodParams.length == 0)
            return "";
        final compared:Map<String, Bool> = [];
        final body = f.field.expr();
        if (body != null)
            scanGenericEquality(body, methodParams, compared);
        return "<" + [for (p in methodParams) compared.exists(p) ? p + ": Equatable" : p].join(", ") + ">";
    }

    static function scanGenericEquality(e:TypedExpr, methodParams:Array<String>, compared:Map<String, Bool>):Void {
        switch (e.expr) {
            case TBinop(OpEq, l, r) | TBinop(OpNotEq, l, r):
                for (operand in [l, r]) {
                    final name = strippedTypeParamName(operand);
                    if (name != null && methodParams.indexOf(name) >= 0)
                        compared.set(name, true);
                }
            case _:
        }
        haxe.macro.TypedExprTools.iter(e, (child:TypedExpr) -> scanGenericEquality(child, methodParams, compared));
    }

    static function strippedTypeParamName(e:TypedExpr):Null<String> {
        var current = e;
        while (true) {
            switch (current.expr) {
                case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner):
                    current = inner;
                case _:
                    break;
            }
        }
        return switch (Context.follow(current.t)) {
            case TInst(c, _):
                switch (c.get().kind) {
                    case KTypeParameter(_): c.get().name;
                    case _: null;
                }
            case _: null;
        };
    }

    /**
        Body normalization lines for coalescing defaults that Swift cannot
        carry in the signature: a default that reads an earlier parameter
        takes `T? = nil` and the body assigns `p = p ?? E;` at entry; a
        default that can throw renders as an explicit conditional instead,
        because the right side of `??` is a non-throwing autoclosure. The
        condition proves the parameter non-nil in the false branch, which
        makes the force unwrap safe.
    **/
    function coalescingBodyNormalizationLines(cls:ClassType, f:ClassFuncData):Array<String> {
        final out:Array<String> = [];
        for (a in f.args) {
            final decision = SwiftParameterPlan.forArgument(cls, f.field.name, a.name, a.index, a.type);
            final coalescing = decision.coalescingValue;
            if (coalescing == null)
                continue;
            if (decision.throwsDefault) {
                out.push("        " + (expr.parameterIsMutated(a.name) ? "var" : "let") + " " + SwiftNameEscape.escape(a.name) + " = ("
                    + SwiftNameEscape.escape(a.name) + " == nil ? try " + expr.coalescingDefaultText(coalescing, a.type) + " : "
                    + SwiftNameEscape.escape(a.name) + "!);");
                continue;
            }
            if (decision.referencesPrivateMember) {
                final keyword = expr.parameterIsMutated(a.name) ? "var" : "let";
                out.push("        " + keyword + " " + SwiftNameEscape.escape(a.name) + " = " + SwiftNameEscape.escape(a.name) + " ?? "
                    + expr.coalescingDefaultText(coalescing, a.type) + ";");
                continue;
            }
            if (!decision.readsParameter)
                continue;
            final defaultText = expr.coalescingDefaultText(coalescing, a.type);
            // The normalized shadow is assigned once, so keep it immutable.
            final keyword = switch (coalescing) {
                case CParameterRead(_): expr.parameterIsMutated(a.name) ? "var" : "let";
                default: "let";
            };
            out.push("        " + keyword + " " + a.name + " = " + a.name + " ?? " + defaultText + ";");
        }
        return out;
    }

    /** Marks a function return whose ReadOnlyArray result is a decode boundary. */
    function decodeBoundaryBody(cls:ClassType, f:ClassFuncData, depth:Int = 2):Array<String> {
        final boundary = StaticFieldHelper.isReadOnlyArrayType(f.ret);
        expr.setDecodeBoundary(boundary);
        final body = expr.functionBody(cls, f, depth);
        expr.setDecodeBoundary(false);
        return body;
    }

    // ------------------------------------------------------------------
    // Variant enums (features/01)
    // ------------------------------------------------------------------

    public function enumDecl(en:EnumType, options:Array<EnumOptionData>):String {
        final sorted = PolicyQueries.sortedEnumOptions(options);
        final valueEnum = PolicyQueries.isValueEnumOptions(sorted);
        if (valueEnum) {
            final lines = ['public enum ${en.name}: String, CaseIterable, Equatable {'];
            for (o in sorted)
                lines.push('    case ${lowerFirst(o.name)} = "${o.name}"');
            lines.push("}");
            lines.push("");
            lines.push("public func compare" + en.name + "(_ a: " + en.name + ", _ b: " + en.name + ") -> Int32 {");
            lines.push("    if a == b { return 0; }");
            lines.push("    func rank(_ v: " + en.name + ") -> Int32 {");
            lines.push("        switch v {");
            for (o in sorted)
                lines.push("        case ." + lowerFirst(o.name) + ": return " + o.field.index);
            lines.push("        }");
            lines.push("    }");
            lines.push("    return rank(a) - rank(b)");
            lines.push("}");
            return lines.join("\n");
        }
        final lines:Array<String> = [ // Equatable backs the construct comparisons the samples run
            // (`width == F64`); payload types of the subset (Int32,
            // String, nested enums) synthesize the conformance.
            // Recursive payload enums require indirect storage in Swift.
            "public "
            + (EnumCycleDetector.isCyclic(en) ? "indirect " : "")
            + "enum "
            + en.name
            + ": Equatable {"];
        for (o in sorted) {
            final caseName = lowerFirst(o.name);
            if (o.args.length == 0) {
                lines.push("    case " + caseName);
            } else {
                final payloads = [for (arg in o.args) arg.name + ": " + types.of(arg.type)].join(", ");
                lines.push("    case " + caseName + "(" + payloads + ")");
            }
        }
        lines.push("}");
        return lines.join("\n");
    }

    public static function lowerFirst(s:String):String {
        return NameConversion.lowerFirst(s);
    }

    // ------------------------------------------------------------------
    // Record typedefs (features/03, features/18)
    // ------------------------------------------------------------------

    public function typedefDecl(def:DefType):String {
        switch (def.type) {
            case TAnonymous(anonRef):
                final fields = PolicyQueries.sortedAnonFields(anonRef);
                // Equatable backs the generated test assertions; the
                // field types of the subset (scalars, strings, arrays,
                // optionals, nested records) synthesize the conformance.
                // A field that cannot synthesize it (an interface lowers to
                // a protocol existential) makes the struct drop the
                // conformance; Swift cannot synthesize it for such a field.
                final equatable = recordFieldsSupportEquatable(fields) ? ": Equatable" : "";
                final lines:Array<String> = ["public struct " + def.name + equatable + " {"];
                for (field in fields) {
                    lines.push("    public var " + field.name + ": " + types.of(field.type));
                }
                // The synthesized memberwise init is internal; the record
                // crosses the module boundary into the test tree, so the
                // init renders public with the labeled parameters in
                // declaration order, matching the memberwise form.
                final initArgs = [for (field in fields) field.name + ": " + types.of(field.type)].join(", ");
                lines.push("    public init(" + initArgs + ") {");
                for (field in fields) {
                    lines.push("        self." + field.name + " = " + field.name);
                }
                lines.push("    }");
                lines.push("}");
                if (isStructKeyCandidate(fields)) {
                    return lines.join("\n") + "\n\n" + comparatorDecl(def, fields);
                }
                return lines.join("\n");
            case _:
                Context.error("typedef alias has no lowering; name the structure instead", def.pos);
                return null;
        }
    }

    /**
        Whether every field of a record typedef has a Swift type that
        synthesizes `Equatable`: scalars, strings, arrays and optionals of
        those, nested records, and enums. A class or interface field does
        not, so the record must drop the conformance.
    **/
    function recordFieldsSupportEquatable(fields:Array<{type:Type}>):Bool {
        for (field in fields) {
            if (!fieldTypeSupportsEquatable(field.type)) {
                return false;
            }
        }
        return true;
    }

    function fieldTypeSupportsEquatable(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (Context.follow(t)) {
            case TAbstract(a, params):
                switch (a.get().name) {
                    case "Int" | "Float" | "Bool": true;
                    case "Null" if (params.length == 1): fieldTypeSupportsEquatable(params[0]);
                    case _: false;
                }
            case TInst(c, params):
                final cls = c.get();
                if (cls.isInterface || cls.kind != KNormal) {
                    false;
                } else switch (cls.name) {
                    case "String": true;
                    case "Array": params.length == 1 && fieldTypeSupportsEquatable(params[0]);
                    case _: false;
                }
            case TEnum(_, _): true;
            case TAnonymous(anon): recordFieldsSupportEquatable([for (f in anon.get().fields) f]);
            case _: false;
        };
    }

    /**
        The per-type key comparator stdlib/07 binds into sorted builders
        with structure keys. Integer fields subtract; Bool and String
        fields branch; nested structures delegate to their comparator.
        String fields compare through the unit-order helper because the
        native operators order by canonical equivalence.
    **/
    function comparatorDecl(def:DefType, fields:Array<ClassField>):String {
        final lines:Array<String> = [
            "public func compare" + def.name + "(_ a: " + def.name + ", _ b: " + def.name + ") -> Int32 {"
        ];
        for (f in fields) {
            switch (Context.follow(f.type)) {
                case TAbstract(a, _) if (a.get().name == "Int"):
                    lines.push("    if a." + f.name + " != b." + f.name + " {");
                    lines.push("        return a." + f.name + " - b." + f.name);
                    lines.push("    }");
                case TAbstract(a, _) if (a.get().name == "Bool"):
                    lines.push("    if a." + f.name + " != b." + f.name + " {");
                    lines.push("        return a." + f.name + " ? 1 : -1");
                    lines.push("    }");
                case TInst(c, _) if (c.get().name == "String"):
                    lines.push("    if a." + f.name + " != b." + f.name + " {");
                    lines.push("        return compareUnitOrder(a." + f.name + ", b." + f.name + ")");
                    lines.push("    }");
                case _:
                    switch (f.type) {
                        case TType(innerDef, _):
                            final inner = innerDef.get();
                            final orderName = "order" + upperFirst(f.name);
                            lines.push("    let " + orderName + " = compare" + inner.name + "(a." + f.name + ", b." + f.name + ")");
                            lines.push("    if " + orderName + " != 0 {");
                            lines.push("        return " + orderName);
                            lines.push("    }");
                        case _:
                    }
            }
        }
        lines.push("    return 0");
        lines.push("}");
        return lines.join("\n");
    }

    static function upperFirst(s:String):String {
        return NameConversion.upperFirst(s);
    }

    function isStructKeyCandidate(fields:Array<ClassField>):Bool {
        return PolicyQueries.isStructKeyCandidate(fields);
    }

    function isFieldKeyCandidate(t:Type):Bool {
        return PolicyQueries.isFieldKeyCandidate(t);
    }
}
#end
