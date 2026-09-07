package swiftcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import ValueTypeSupport;
import PolicyQueries;
import ComparatorPlan;
import ComparatorPlan.ComparatorFieldKind;
import ValueTypeSupport.ValueTypeInfo;
import ValueTypeSupport.ValueTypeOperator;
import NameConversion;

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

    // ------------------------------------------------------------------
    // Classes
    // ------------------------------------------------------------------

    public function classDecl(cls:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):String {
        if (cls.isInterface) {
            // An interface lowers to a protocol; the implementing class
            // names it in its conformance clause.
            final lines:Array<String> = ["public protocol " + cls.name + " {"];
            for (f in funcFields) {
                lines.push("    func " + f.field.name + paramList(cls, f) + " -> " + types.of(f.ret));
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
        final extractedFuncs = [for (f in funcFields) if (StaticFunctionMarkers.isMarked(f.field)) f];
        final ordinaryFuncs = [for (f in funcFields) if (!StaticFunctionMarkers.isMarked(f.field)) f];
        final extractedParts:Array<String> = [];
        for (f in extractedFuncs) {
            extractedParts.push(extractedFuncDecl(module, cls, f).join("\n"));
        }
        final shouldEmitComparator = cls.meta.has(":dataClass") && SwiftType.canEmitDataClassComparator(cls);
        if (varFields.length == 0 && ordinaryFuncs.length == 0) {
            final emptyClass = extractedParts.join("\n\n");
            return shouldEmitComparator ? emptyClass + "\n\n" + dataClassComparator(cls) : emptyClass;
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
            if (depth == 1) {
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
            lines.push((depth >= 1 ? "public class " : "public final class ")
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

        lines.push("}");
        final classPart = lines.join("\n");
        final result = extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + classPart : classPart;
        return shouldEmitComparator ? result + "\n\n" + dataClassComparator(cls) : result;
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
            lines.push("");
            lines.push("    public static let "
                + SwiftNameEscape.escape(v.field.name)
                + ": "
                + info.name
                + " = "
                + expr.rawExpression(initializer));
        }
        lines.push("}");
        return lines.join("\n");
    }

    function dataClassComparator(cls:ClassType):String {
        final lines = [
            "public func compare" + cls.name + "(_ a: " + cls.name + ", _ b: " + cls.name + ") -> Int32 {"
        ];
        for (f in [
            for (x in cls.fields.get())
                if (switch (x.kind) {
                        case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                        case _: false;
                    }) x
        ]) {
            switch (f.type) {
                case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1):
                    lines.push("    if a." + f.name + " == nil && b." + f.name + " != nil { return -1 }");
                    lines.push("    if a." + f.name + " != nil && b." + f.name + " == nil { return 1 }");
                    lines.push("    if let av = a." + f.name + ", let bv = b." + f.name + " {");
                    switch (SwiftType.rawArrayElement(params[0])) {
                        case null:
                            switch (Context.follow(params[0])) {
                                case TAbstract(ia, _) if (ia.get().name == "Int"): lines.push("        if av != bv { return av - bv }");
                                case TInst(sc,
                                    _) if (sc.get()
                                        .name == "String"): lines.push("        let cmp" + f.name + " = compareUnitOrder(av, bv); if cmp" + f.name
                                        + " != 0 { return cmp" + f.name + " }");
                                case TEnum(e, _):
                                    final en = e.get();
                                    final orderName = cls.name + f.name + "Order";
                                    lines.unshift("    func "
                                        + orderName
                                        + "(_ v: "
                                        + en.name
                                        + ") -> Int32 {\n        switch v {\n"
                                        + [
                                            for (ef in en.constructs)
                                                "        case ." + lowerFirst(ef.name) + ": return " + ef.index
                                        ].join("\n") + "\n        }\n    }");
                                    lines.push("        if " + orderName + "(av) != " + orderName + "(bv) { return " + orderName + "(av) - " + orderName
                                        + "(bv) }");
                                case _:
                            }
                        case element:
                            nullableArrayComparator(lines, cls, f.name, element);
                    }
                    lines.push("    }");
                    continue;
                case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length == 1):
                    lines.push("    var i" + f.name + " = 0");
                    lines.push("    while i" + f.name + " < a." + f.name + ".count && i" + f.name + " < b." + f.name + ".count {");
                    switch (Context.follow(params[0])) {
                        case TInst(sc,
                            _) if (sc.get()
                                .name == "String"): lines.push("        let cmp = compareUnitOrder(a." + f.name + "[i" + f.name + "], b." + f.name + "[i"
                                + f.name + "]); if cmp != 0 { return cmp }");
                        case TEnum(e, _):
                            final en = e.get();
                            final orderName = cls.name + f.name + "ElementOrder";
                            lines.unshift("    func "
                                + orderName
                                + "(_ v: "
                                + en.name
                                + ") -> Int32 {\n        switch v {\n"
                                + [
                                    for (ef in en.constructs)
                                        "        case ." + lowerFirst(ef.name) + (switch (ef.type) {
                                            case TFun(args, _): args.length > 0 ? "(" + [for (_ in args) "_"].join(", ") + ")" : "";
                                            case _: "";
                                        }) + ": return " + ef.index
                                ].join("\n") + "\n        }\n    }");
                            lines.push("        let cmp = " + orderName + "(a." + f.name + "[i" + f.name + "]) - " + orderName + "(b." + f.name + "[i"
                                + f.name + "]); if cmp != 0 { return cmp }");
                        case TInst(c,
                            _) if (c.get()
                                .meta.has(":dataClass")): lines.push("        let cmp = compare" + c.get().name + "(a." + f.name + "[i" + f.name + "], b."
                                + f.name + "[i" + f.name + "]); if cmp != 0 { return cmp }");
                        case _: lines.push("        if a." + f.name + "[i" + f.name + "] != b." + f.name + "[i" + f.name + "] { return 1 }");
                    }
                    lines.push("        i" + f.name + " += 1");
                    lines.push("    }");
                    lines.push("    if a."
                        + f.name
                        + ".count != b."
                        + f.name
                        + ".count { return Int32(a."
                        + f.name
                        + ".count - b."
                        + f.name
                        + ".count) }");
                    continue;
                default:
            }
            switch (Context.follow(f.type)) {
                case TAbstract(a, _) if (a.get().name == "Int"):
                    lines.push("    if a." + f.name + " != b." + f.name + " { return a." + f.name + " - b." + f.name + " }");
                case TAbstract(a, _) if (a.get().name == "Float"):
                    lines.push("    if a." + f.name + " < b." + f.name + " { return -1 }");
                    lines.push("    if a." + f.name + " > b." + f.name + " { return 1 }");
                case TAbstract(a, _) if (a.get().name == "Bool"):
                    lines.push("    if a." + f.name + " != b." + f.name + " { return a." + f.name + " ? 1 : -1 }");
                case TEnum(e, _):
                    final en = e.get();
                    lines.push("    if a." + f.name + " != b." + f.name + " { return Int32(" + cls.name + f.name + "Order(a." + f.name + ") - " + cls.name
                        + f.name + "Order(b." + f.name + ")) }");
                    lines.unshift("    func "
                        + cls.name
                        + f.name
                        + "Order(_ v: "
                        + en.name
                        + ") -> Int32 {\n        switch v {\n"
                        + [
                            for (ef in en.constructs)
                                "        case ." + lowerFirst(ef.name) + (switch (ef.type) {
                                    case TFun(args, _): args.length > 0 ? "(" + [for (_ in args) "_"].join(", ") + ")" : "";
                                    case _: "";
                                }) + ": return " + ef.index
                        ].join("\n") + "\n        }\n    }");
                case TInst(c, _) if (c.get().name == "String"):
                    lines.push("    let cmp" + f.name + " = compareUnitOrder(a." + f.name + ", b." + f.name + "); if cmp" + f.name + " != 0 { return cmp"
                        + f.name + " }");
                case TInst(c, _) if (c.get().meta.has(":dataClass")):
                    lines.push("    let cmp" + f.name + " = compare" + c.get().name + "(a." + f.name + ", b." + f.name + "); if cmp" + f.name
                        + " != 0 { return cmp" + f.name + " }");
                case _:
            }
        }
        lines.push("    return 0");
        lines.push("}");
        return lines.join("\n");
    }

    function findFunc(funcFields:Array<ClassFuncData>, name:String):ClassFuncData {
        return PolicyQueries.findFunc(funcFields, name, "value type member is missing: " + name);
    }

    /**
        The element-wise compare lines for a nullable collection field
        inside the `if let` bindings. The locals av/bv hold the present
        arrays; the semantics mirror the non-null ReadOnlyArray arm:
        compare in index order, then by length.
    **/
    function nullableArrayComparator(lines:Array<String>, cls:ClassType, field:String, element:Type):Void {
        lines.push("        var i" + field + " = 0");
        lines.push("        while i" + field + " < av.count && i" + field + " < bv.count {");
        switch (Context.follow(element)) {
            case TInst(sc, _) if (sc.get().name == "String"):
                lines.push("            let cmp = compareUnitOrder(av[i" + field + "], bv[i" + field + "]); if cmp != 0 { return cmp }");
            case TEnum(e, _):
                final en = e.get();
                final orderName = cls.name + field + "ElementOrder";
                lines.unshift("    func "
                    + orderName
                    + "(_ v: "
                    + en.name
                    + ") -> Int32 {\n        switch v {\n"
                    + [
                        for (ef in en.constructs)
                            "        case ." + lowerFirst(ef.name) + (switch (ef.type) {
                                case TFun(args, _): args.length > 0 ? "(" + [for (_ in args) "_"].join(", ") + ")" : "";
                                case _: "";
                            }) + ": return " + ef.index
                    ].join("\n") + "\n        }\n    }");
                lines.push("            let cmp = "
                    + orderName
                    + "(av[i"
                    + field
                    + "]) - "
                    + orderName
                    + "(bv[i"
                    + field
                    + "]); if cmp != 0 { return cmp }");
            case TInst(c, _) if (c.get().meta.has(":dataClass")):
                lines.push("            let cmp = compare" + c.get().name + "(av[i" + field + "], bv[i" + field + "]); if cmp != 0 { return cmp }");
            case _:
                lines.push("            if av[i" + field + "] != bv[i" + field + "] { return 1 }");
        }
        lines.push("            i" + field + " += 1");
        lines.push("        }");
        lines.push("        if av.count != bv.count { return Int32(av.count - bv.count) }");
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
                return [
                    "    public static let " + SwiftNameEscape.escape(field.name) + ": [Int32] = [" + renderDataTableElements(elems) + "]"
                ];
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
                + expr.rawExpression(initializer)];
        }
        if (v.isStatic) {
            final init = StaticFieldHelper.validatedInitializer(field, cls);
            final array = StaticFieldHelper.isArrayType(field.type);
            final smallArray = field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init);
            final kw = smallArray ? "let" : (array || !field.isFinal ? "var" : "let");
            // @:allow members use Swift internal visibility so allowed cross-class calls compile.
            final vis = field.isPublic ? "public " : (field.meta.has(":allow") ? "" : "private ");
            return ["    "
                + vis
                + "static "
                + kw
                + " "
                + SwiftNameEscape.escape(field.name)
                + ": "
                + types.of(field.type)
                + " = "
                + expr.rawExpression(init)];
        }
        // The Haxe typer places instance field defaults in the
        // constructor, so the declaration stays bare and the init
        // body carries the assignments.
        // A final Haxe field keeps the reference binding while the array
        // contents remain mutable. Array fields therefore use var.
        // Swift let array forbids that, so array fields stay var.
        final isArrayField = switch (field.type) {
            case TInst(c, _): c.get().name == "Array";
            case TLazy(f): switch (f()) {
                    case TInst(c, _): c.get().name == "Array";
                    case _: false;
                };
            case _: false;
        };
        final kw = isArrayField || !field.isFinal ? "var" : "let";
        // Private fields render with Swift's private marker (feature
        // spec 27); public fields render public for the SwiftPM split
        // between the generated-code module and its consumers.
        // @:allow members use Swift internal visibility so allowed cross-class calls compile.
        final vis = field.isPublic ? "public " : (field.meta.has(":allow") ? "" : "private ");
        return [
            "    " + vis + kw + " " + SwiftNameEscape.escape(field.name) + ": " + types.of(field.type)
        ];
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
        final vis = field.isPublic ? "public " : (field.meta.has(":allow") ? "" : "private ");
        final getter = "get_" + field.name;
        return [
            "    " + vis + "var " + SwiftNameEscape.escape(field.name) + ": " + types.of(field.type) + " { " + getter + "() }"
        ];
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
        final throws = SwiftFallibility.isThrowing(cls.module, f.field.name, true) ? " throws" : "";
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
            final ctorThrows = SwiftFallibility.isThrowing(module, "new", false) ? " throws" : "";
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
        final ret = types.of(f.ret);
        final stat = f.isStatic ? "static " : "";
        final throws = SwiftFallibility.isThrowing(module, f.field.name, f.isStatic) ? " throws" : "";
        // A method's own type parameters (the resident builders'
        // factory functions) render as method generics; the class's own
        // parameters stay in the class header only.
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
        final body = decodeBoundaryBody(cls, f);
        final normLines = coalescingBodyNormalizationLines(cls, f);
        // Private functions render with Swift's private marker (feature
        // spec 27); public functions render public for the SwiftPM split.
        // @:allow members use Swift internal visibility so allowed cross-class calls compile.
        // Swift requires a member satisfying a protocol requirement to be
        // at least as accessible as the protocol, and protocols render
        // public, so interface methods render public regardless of their
        // Haxe visibility.
        final vis = isInterfaceMethod(cls, f) ? "public " : (f.field.isPublic ? "public " : (f.field.meta.has(":allow") ? "" : "private "));
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
        final throws = SwiftFallibility.isThrowing(module, f.field.name, true) ? " throws" : "";
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
        // @:allow members use Swift internal visibility so allowed cross-class calls compile.
        final vis = f.field.isPublic ? "public " : (f.field.meta.has(":allow") ? "" : "private ");
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
    function paramList(cls:ClassType, f:ClassFuncData, start:Int = 0):String {
        return "(" + [
            for (i in start...f.args.length) {
                final a = f.args[i];
                final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
                final readsParam = coalescing != null && DefaultArgExpander.coalescingReadsParamForParam(cls, f.field.name, a.name);
                final baseType = coalescing != null ? DefaultArgExpander.coalescingParameterType(coalescing, a.type) : a.type;
                // When the default reads an earlier parameter, Swift needs
                // an Optional type so the default value can be nil.
                final parameterType = readsParam ? makeOptional(baseType) : baseType;
                final escaping = switch (Context.follow(a.type)) {
                    case TFun(_, _): "@escaping ";
                    case _: "";
                };
                final defaultText = if (coalescing != null) {
                    if (readsParam)
                        " = nil"
                    else
                        " = " + expr.coalescingDefaultText(coalescing, a.type);
                } else "";
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

    /** Wraps a Haxe type in Null<T> to produce a Swift optional. */
    function makeOptional(t:Type):Type {
        final nullAbst = switch (Context.getType("Null")) {
            case TAbstract(a, _): a;
            case _: return t;
        };
        return TAbstract(nullAbst, [t]);
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
        Body normalization lines for coalescing defaults that read
        earlier parameters. Swift cannot use a default argument
        expression that references other parameters, so the parameter
        takes `T? = nil` in the signature and the body assigns
        `p = p ?? E;` at entry.
    **/
    function coalescingBodyNormalizationLines(cls:ClassType, f:ClassFuncData):Array<String> {
        final out:Array<String> = [];
        for (a in f.args) {
            final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
            if (coalescing == null)
                continue;
            if (!DefaultArgExpander.coalescingReadsParamForParam(cls, f.field.name, a.name))
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

    /**
        features/18: a function returning ReadOnlyArray is a decode
        boundary. Array is a value type in Swift and a let binding
        binding is structurally immutable, so no read-only wrappers render; the flag
        only keeps the boundary visible to the expression layer.
    **/
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
                final lines:Array<String> = ["public struct " + def.name + ": Equatable {"];
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
