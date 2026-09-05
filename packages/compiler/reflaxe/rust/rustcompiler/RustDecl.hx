package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import ValueTypeSupport;
import PolicyQueries;
import ValueTypeSupport.ValueTypeInfo;
import ValueTypeSupport.ValueTypeOperator;

/**
    Declaration lowering for Rust: structs, impl blocks, and enums.
**/
class RustDecl {
    final imports:RustImports;
    final types:RustType;
    final expr:RustExpr;
    final state:RustEmissionState;

    public function new(selfModule:String, state:RustEmissionState) {
        this.imports = new RustImports(selfModule, state);
        this.state = state;
        this.types = new RustType(imports, state);
        this.expr = new RustExpr(imports, types, state);
    }

    public function renderImports():String {
        return imports.render();
    }

    public function renderImportsFiltered(body:String):String {
        return imports.renderFiltered(body);
    }

    public function topLevelStatements(e:TypedExpr):String {
        return expr.topLevelStatements(e);
    }

    public function rawExpression(e:TypedExpr):String {
        return expr.rawExpression(e);
    }

    public function enumOperand(t:Type, value:String, depth:Int = 0):String {
        return switch (Context.follow(t)) {
            case TInst(c, [element]) if (c.get().name == "Array"):
                imports.require("std::fmt::Write");
                final index = "j" + depth;
                '{ let mut out = String::new(); out.push(\'[\'); let mut ${index} = 0usize; while ${index} < ${value}.len() { if ${index} > 0 { out.push_str(", "); } let _ = write!(out, "{}", ${enumOperand(element, value + "[" + index + "]", depth + 1)}); ${index} += 1; } out.push(\']\'); out }';
            case TAbstract(a, params) if (a.get().module == "std.ReadOnlyArray"):
                enumOperand(haxe.macro.TypeTools.applyTypeParameters(a.get().type, a.get().params, params), value, depth);
            case TAnonymous(anon):
                final fields = anon.get().fields;
                final formatString = "{{" + [for (f in fields) f.name + "={}"].join(", ") + "}}";
                final values = [
                    for (f in fields)
                        enumOperand(f.type, value + "." + RustImports.toSnakeCase(f.name), depth)
                ];
                'format!("${formatString}", ${values.join(", ")})';
            case TAbstract(a, _) if (a.get().name == "Int" || a.get().name == "Float" || a.get().name == "Bool"):
                "(" + value + ").to_string()";
            case TInst(c, _) if (c.get().name == "String"):
                "(" + value + ").clone()";
            case _:
                "(" + value + ").to_string()";
        };
    }

    // ------------------------------------------------------------------
    // Classes & Structs
    // ------------------------------------------------------------------

    public function classDecl(cls:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):String {
        final emittedName = RustImports.emittedTypeName(cls.name);
        if (cls.isInterface) {
            final lines:Array<String> = [];
            lines.push("pub trait " + emittedName + " {");
            lines.push("    fn __haxe_type_name(&self) -> &'static str;");
            for (f in funcFields) {
                final paramList = [
                    for (a in f.args)
                        RustImports.toSnakeCase(a.name) + ": " + types.of(a.type, true)
                ].join(", ");
                final selfPrefix = f.isStatic ? "" : "&self" + (f.args.length > 0 ? ", " : "");
                final retType = types.of(f.ret, false);
                final ret = retType == "()" ? "" : " -> " + retType;
                lines.push('    fn ${RustImports.toSnakeCase(f.field.name)}($selfPrefix$paramList)$ret;');
            }
            lines.push("}");
            return lines.join("\n");
        }

        if (isExceptionSubclass(cls)) {
            final payload = payloadEnumOf(funcFields);
            if (payload == null) {
                Context.error("exception subclass without a payload enum constructor has no Rust lowering", cls.pos);
                return null;
            }
            return exceptionErrorDecl(cls, payload, funcFields);
        }

        var hasTestMethods = false;
        for (f in funcFields) {
            if (f.field.meta.has(":test")) {
                hasTestMethods = true;
                break;
            }
        }

        if (hasTestMethods) {
            final lines:Array<String> = [];
            var sep = false;
            final sortedFuncs = funcFields.copy();
            sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));
            for (f in sortedFuncs) {
                if (!f.field.meta.has(":test"))
                    continue;
                if (sep)
                    lines.push("");
                sep = true;
                for (l in testFuncDecl(cls, f))
                    lines.push(l);
            }
            return lines.join("\n");
        }

        final extractedFuncs = [for (f in funcFields) if (StaticFunctionMarkers.isMarked(f.field)) f];
        final ordinaryFuncs = [for (f in funcFields) if (!StaticFunctionMarkers.isMarked(f.field)) f];
        final extractedParts:Array<String> = [];
        for (f in extractedFuncs) {
            extractedParts.push(extractedFuncDecl(cls, f).join("\n"));
        }
        if (varFields.length == 0 && ordinaryFuncs.length == 0) {
            return extractedParts.join("\n\n");
        }

        final tableLines:Array<String> = [];
        for (v in varFields) {
            if (v.isStatic && DataTableHelper.isDataTableField(v.field)) {
                final elems = DataTableHelper.getDataTableElements(v.field.expr());
                if (elems != null) {
                    tableLines.push(renderRustDataTable(v.field, elems));
                }
            }
        }
        final moduleStaticLines:Array<String> = [];
        for (v in varFields) {
            for (l in moduleStaticVarDecl(cls, v))
                moduleStaticLines.push(l);
        }
        final staticFunctionLines:Array<String> = [];
        for (v in varFields) {
            for (l in staticFunctionDecl(v))
                staticFunctionLines.push(l);
        }
        final prefixLines = tableLines.concat(moduleStaticLines).concat(staticFunctionLines);

        final isStaticClass = isAllStatic(varFields, ordinaryFuncs);
        final lines:Array<String> = [];

        if (isStaticClass) {
            lines.push("pub struct " + emittedName + ";\n");
            lines.push("impl " + emittedName + " {");
            for (v in varFields) {
                for (l in staticVarDecl(cls, v))
                    lines.push(l);
            }
            var sep = varFields.length > 0 && ordinaryFuncs.length > 0;
            for (f in ordinaryFuncs) {
                if (sep)
                    lines.push("");
                sep = true;
                for (l in staticFuncDecl(cls, f))
                    lines.push(l);
            }
            lines.push("}");
            final prefix = prefixLines.length > 0 ? prefixLines.join("\n") + "\n\n" : "";
            final classPart = prefix + lines.join("\n");
            return extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + classPart : classPart;
        }

        // Instance class
        final borrowedBytes = borrowedByteFields(funcFields);
        final hasLifetime = classHasLifetime(varFields, borrowedBytes);
        // Generic classes carry their type parameters on the struct and
        // the impl. Every parameter takes a Clone bound on the impl:
        // reads of stored elements clone out of the arrays, and the one
        // source of these classes is the sorted-table resident. A member
        // that formats a parameter for printing goes into a second impl
        // whose parameters also carry Debug, so callers that never print
        // keep the Clone-only bound set.
        final classParams = [for (p in cls.params) p.name];
        final genericList = hasLifetime ? ["'a"].concat(classParams) : classParams;
        final genericStr = genericList.length > 0 ? "<" + genericList.join(", ") + ">" : "";
        final implBoundList = hasLifetime ? ["'a"].concat([for (n in classParams) n + ": Clone"]) : [for (n in classParams) n + ": Clone"];
        final debugBoundList = hasLifetime ? ["'a"].concat([for (n in classParams) n + ": Clone + std::fmt::Debug"]) : [
            for (n in classParams)
                n + ": Clone + std::fmt::Debug"
        ];
        final implGenerics = implBoundList.length > 0 ? "<" + implBoundList.join(", ") + ">" : "";
        final ltParam = genericStr;

        if (state.recordCloneTypes.exists(cls.module + "::" + cls.name)
            && !StaticFieldHelper.hasSelfConstructionStatic(cls)
            && !cls.meta.has(":dataClass")
            && cls.module.indexOf("registry.") != 0
            && isAllClone(varFields)
            && classParams.length == 0) {
            lines.push("#[derive(Clone)]");
        }
        if ((StaticFieldHelper.hasSelfConstructionStatic(cls) || cls.meta.has(":dataClass") || classParams.length > 0)
            && (classParams.length > 0 || isAllClone(varFields))) {
            lines.push("#[derive(Clone)]");
        }
        if (cls.module.indexOf("registry.") == 0) {
            lines.push("#[derive(Debug, Clone, PartialEq)]");
        }
        lines.push("pub struct " + emittedName + genericStr + " {");
        for (v in varFields) {
            if (v.isStatic)
                continue;
            for (l in instanceVarDecl(v, hasLifetime, borrowedBytes))
                lines.push(l);
        }
        lines.push("}\n");

        lines.push("impl" + implGenerics + " " + emittedName + genericStr + " {");
        var sep = false;
        for (v in varFields) {
            if (!v.isStatic)
                continue;
            final declarations = staticVarDecl(cls, v);
            if (declarations.length == 0)
                continue;
            if (sep)
                lines.push("");
            sep = true;
            for (l in declarations)
                lines.push(l);
        }
        final printingMembers:Array<Array<String>> = [];
        for (f in ordinaryFuncs) {
            if (f.isStatic) {
                if (sep)
                    lines.push("");
                sep = true;
                for (l in staticFuncDecl(cls, f))
                    lines.push(l);
            } else {
                state.memberPrintsTypeParam = false;
                final memberLines = instanceFuncDecl(cls, f, hasLifetime);
                if (state.memberPrintsTypeParam) {
                    printingMembers.push(memberLines);
                } else {
                    if (sep)
                        lines.push("");
                    sep = true;
                    for (l in memberLines)
                        lines.push(l);
                }
            }
        }
        lines.push("}");

        if (printingMembers.length > 0) {
            final debugGenerics = debugBoundList.length > 0 ? "<" + debugBoundList.join(", ") + ">" : "";
            lines.push("\nimpl" + debugGenerics + " " + cls.name + genericStr + " {");
            var debugSep = false;
            for (memberLines in printingMembers) {
                if (debugSep)
                    lines.push("");
                debugSep = true;
                for (l in memberLines)
                    lines.push(l);
            }
            lines.push("}");
        }

        for (iface in cls.interfaces) {
            final ifaceCls = iface.t.get();
            // A cross-module interface needs its trait import recorded
            // here, exactly like a field-type reference does; a
            // same-module interface needs no import.
            imports.requireType(ifaceCls.module, ifaceCls.name);
            lines.push("\nimpl" + implGenerics + " " + ifaceCls.name + " for " + cls.name + genericStr + " {");
            lines.push('    fn __haxe_type_name(&self) -> &\'static str {');
            lines.push('        "${cls.module}.${cls.name}"');
            lines.push("    }");
            var ifaceSep = false;
            for (f in ordinaryFuncs) {
                if (f.field.name == "new")
                    continue;
                var inIface = false;
                for (ifField in ifaceCls.fields.get()) {
                    if (ifField.name == f.field.name) {
                        inIface = true;
                        break;
                    }
                }
                if (inIface) {
                    if (ifaceSep)
                        lines.push("");
                    ifaceSep = true;
                    for (l in instanceFuncDecl(cls, f, hasLifetime, true))
                        lines.push(l);
                }
            }
            lines.push("}");
        }

        final classPart = prefixLines.length > 0 ? prefixLines.join("\n\n") + "\n\n" + lines.join("\n") : lines.join("\n");
        final result = extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + classPart : classPart;
        return cls.meta.has(":dataClass")
            && RustType.canEmitDataClassComparator(cls) ? result + "\n\n" + dataClassComparator(cls) : result;
    }

    function dataClassComparator(cls:ClassType):String {
        imports.requireType("runtime.SortedTable", "SortedTable");
        final n = RustImports.toSnakeCase(cls.name);
        final lines = ['pub fn compare_$n(a: &${cls.name}, b: &${cls.name}) -> i32 {'];
        function importElementComparator(elem:ClassType):Void {
            if (elem.module != imports.selfModule) {
                final cmp = "compare_" + RustImports.toSnakeCase(elem.name);
                imports.require("crate::" + RustImports.moduleToRustPath(elem.module) + "::" + cmp);
            }
        }
        for (f in [
            for (x in cls.fields.get())
                if (switch (x.kind) {
                        case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                        case _: false;
                    }) x
        ]) {
            final fn = RustImports.toSnakeCase(f.name);
            var rawHandled = false;
            switch (f.type) {
                case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1):
                    rawHandled = true;
                    var presentCompare = cmpToI32("av.cmp(bv)");
                    switch (rawArrayElement(params[0])) {
                        case null:
                            switch (Context.follow(params[0])) {
                                case TEnum(e, _):
                                    final en = e.get();
                                    final orderName = RustImports.toSnakeCase(cls.name) + "_" + RustImports.toSnakeCase(f.name) + "_order";
                                    lines.unshift('fn $orderName(v: &${en.name}) -> i32 {\n    match v {\n' + [
                                        for (ef in en.constructs)
                                            '        ${en.name}::${RustImports.toUpperCamelCase(ef.name)}' + (enumHasPayload(ef) ? ' { .. }' : '') +
                                            ' => ${ef.index},'
                                    ].join("\n") + '\n    }\n}');
                                    presentCompare = cmpToI32('$orderName(av).cmp(&$orderName(bv))');
                                case TInst(c, _) if (c.get().meta.has(":dataClass")):
                                    importElementComparator(c.get());
                                    presentCompare = 'compare_${RustImports.toSnakeCase(c.get().name)}(av, bv)';
                                case _:
                            }
                        case element:
                            final elementExpr = nullableArrayCompareExpr(lines, cls, f.name, element);
                            presentCompare = '{ let mut cmp = 0; for (av, bv) in av.iter().zip(bv.iter()) { cmp = $elementExpr; if cmp != 0 { break; } } if cmp == 0 { cmp = '
                                + cmpToI32('av.len().cmp(&bv.len())')
                                + '; } cmp }';
                    }
                    lines.push('    let cmp_$fn = match (&a.$fn, &b.$fn) { (None, None) => 0, (None, Some(_)) => -1, (Some(_), None) => 1, (Some(av), Some(bv)) => $presentCompare };');
                case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length == 1):
                    rawHandled = true;
                    final element = Context.follow(params[0]);
                    final elementExprA = "a." + fn + ".iter()";
                    final elementExprB = "b." + fn + ".iter()";
                    var elementCompare = cmpToI32("av.cmp(bv)");
                    switch (element) {
                        case TEnum(e, _):
                            final en = e.get();
                            final orderName = n + "_" + fn + "_element_order";
                            lines.unshift('fn $orderName(v: &${en.name}) -> i32 {\n    match v {\n' + [
                                for (ef in en.constructs)
                                    '        ${en.name}::${RustImports.toUpperCamelCase(ef.name)}' + (enumHasPayload(ef) ? ' { .. }' : '') + ' => ${ef.index},'
                            ].join("\n") + '\n    }\n}');
                            elementCompare = cmpToI32('$orderName(av).cmp(&$orderName(bv))');
                        case TInst(c, _) if (c.get().meta.has(":dataClass")):
                            importElementComparator(c.get());
                            elementCompare = 'compare_${RustImports.toSnakeCase(c.get().name)}(av, bv)';
                        case _:
                    }
                    lines.push('    let mut cmp_$fn = 0; for (av, bv) in a.$fn.iter().zip(b.$fn.iter()) { cmp_$fn = $elementCompare; if cmp_$fn != 0 { break; } }');
                    lines.push('    if cmp_$fn == 0 { cmp_$fn = ' + cmpToI32('a.$fn.len().cmp(&b.$fn.len())') + '; }');
                default:
            }
            if (!rawHandled)
                switch (Context.follow(f.type)) {
                    case TAbstract(a, _) if (a.get().name == "Int"):
                        // Scalar int fields pass isDataClassFieldKey but
                        // reached no arm here before, emitting the trailing
                        // use without its let binding (E0425).
                        lines.push('    let cmp_$fn = if a.$fn < b.$fn { -1 } else if a.$fn > b.$fn { 1 } else { 0 };');
                    case TInst(c, _) if (c.get().name == "String"):
                        lines.push('    let cmp_$fn = SortedTable::compare_strings(a.$fn.as_str(), b.$fn.as_str());');
                    case TInst(c, _) if (c.get().meta.has(":dataClass")):
                        importElementComparator(c.get());
                        lines.push('    let cmp_$fn = compare_${RustImports.toSnakeCase(c.get().name)}(&a.$fn, &b.$fn);');
                    case TEnum(e, _):
                        final en = e.get();
                        final orderName = RustImports.toSnakeCase(cls.name) + "_" + RustImports.toSnakeCase(f.name) + "_order";
                        lines.unshift('fn $orderName(v: &${en.name}) -> i32 {\n    match v {\n' + [
                            for (ef in en.constructs)
                                '        ${en.name}::${RustImports.toUpperCamelCase(ef.name)}' + (enumHasPayload(ef) ? ' { .. }' : '') + ' => ${ef.index},'
                        ].join("\n") + '\n    }\n}');
                        lines.push('    let cmp_$fn = ' + cmpToI32('$orderName(&a.$fn).cmp(&$orderName(&b.$fn))') + ';');
                    case _: // validated before emission
                }
            lines.push('    if cmp_$fn != 0 { return cmp_$fn; }');
        }
        lines.push('    0');
        lines.push('}');
        return lines.join("\n");
    }

    function enumHasPayload(ef:haxe.macro.Type.EnumField):Bool {
        return switch (ef.type) {
            case TFun(args, _): args.length > 0;
            case _: false;
        };
    }

    /**
        The element type when `t` is a raw ReadOnlyArray (checked before
        Context.follow, which erases the abstract to Array). Nullable
        collections need this raw check: the Null arm's followed inner
        type is Array and would otherwise lose the array shape.
    **/
    function rawArrayElement(t:Type):Null<Type> {
        return switch (t) {
            case TAbstract(a, params) if (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray" && params.length == 1): params[0];
            case TLazy(f): rawArrayElement(f());
            case _: null;
        };
    }

    /**
        The element-wise compare expression for one nullable collection
        field. The loop binds av/bv to the zipped element references,
        shadowing the match arm's array bindings; the semantics mirror
        the non-null ReadOnlyArray arm: compare in index order, then by
        length, with the same per-element rules (native Ord for scalars
        and strings, the order helper for enums, the nested comparator
        for records).
    **/
    function nullableArrayCompareExpr(lines:Array<String>, cls:ClassType, field:String, element:Type):String {
        return switch (Context.follow(element)) {
            case TEnum(e, _):
                final en = e.get();
                final orderName = RustImports.toSnakeCase(cls.name) + "_" + RustImports.toSnakeCase(field) + "_order";
                lines.unshift('fn $orderName(v: &${en.name}) -> i32 {\n    match v {\n' + [
                    for (ef in en.constructs)
                        '        ${en.name}::${RustImports.toUpperCamelCase(ef.name)}' + (enumHasPayload(ef) ? ' { .. }' : '') + ' => ${ef.index},'
                ].join("\n") + '\n    }\n}');
                cmpToI32('$orderName(av).cmp(&$orderName(bv))');
            case TInst(c, _) if (c.get().meta.has(":dataClass")):
                'compare_${RustImports.toSnakeCase(c.get().name)}(av, bv)';
            case _:
                cmpToI32("av.cmp(bv)");
        };
    }

    /** An `Ordering` expression to the i32 trichotomy the comparators carry. */
    static function cmpToI32(cmpExpr:String):String {
        return "match " + cmpExpr + " { core::cmp::Ordering::Less => -1, core::cmp::Ordering::Equal => 0, core::cmp::Ordering::Greater => 1 }";
    }

    public function valueTypeDecl(cls:ClassType, info:ValueTypeInfo, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):String {
        final abs = info.abstractType;
        final ctor = ValueTypeSupport.constructorField(abs);
        final ctorData = findFunc(funcFields, "_new");
        final representation = types.of(info.representation, false);
        final derives = ValueTypeSupport.isFloatRepresentation(abs) ? "Debug, Clone, PartialEq" : "Debug, Clone, PartialEq, Eq, Hash";
        final lines:Array<String> = [
            "#[derive(" + derives + ")]",
            "pub struct " + info.name + "(pub " + representation + ");",
            "",
            "impl " + info.name + " {"
        ];
        final hasCtorThrow = ctor != null && ValueTypeSupport.constructorThrows(abs);
        var ctorError:Null<{name:String, module:String, hasOverflow:Bool}> = null;
        if (hasCtorThrow)
            ctorError = resolveErrorOwner(ctorData, cls);
        if (hasCtorThrow && ctorError != null)
            imports.requireType(ctorError.module, ctorError.name);
        final ctorArgType = isStringRepresentation(info.representation) ? "&str" : representation;
        lines.push("    pub fn new(value: "
            + ctorArgType
            + ")"
            + (hasCtorThrow ? " -> Result<Self, " + ctorError.name + ">" : " -> Self")
            + " {");
        if (hasCtorThrow) {
            expr.setFallible(true, ctorError.name, ctorError.hasOverflow ? state.overflowVariant : null);
            for (line in expr.valueTypeConstructorBody(cls, ctorData))
                lines.push("    " + line);
        }
        final ctorValue = isStringRepresentation(info.representation) ? "value.to_string()" : "value";
        lines.push("        " + (hasCtorThrow ? "return Ok(Self(" + ctorValue + "));" : "return Self(" + ctorValue + ");"));
        lines.push("    }");

        for (f in funcFields) {
            if (f.field.name == "_new"
                || f.field.name == "toString"
                || ValueTypeSupport.operatorOf(abs, f.field) != null
                || ValueTypeSupport.isInlineHelper(f.field))
                continue;
            final receiver = ValueTypeSupport.hasReceiver(f.field);
            final start = receiver ? 1 : 0;
            final isFallible = funcIsFallible(f);
            final errOwner = isFallible ? resolveErrorOwner(f, cls) : null;
            if (isFallible && errOwner != null)
                imports.requireType(errOwner.module, errOwner.name);
            expr.setFallible(isFallible, errOwner != null ? errOwner.name : null, errOwner != null
                && errOwner.hasOverflow ? state.overflowVariant : null);
            final rawRet = types.of(f.ret, false);
            final ret = isFallible ? " -> Result<" + rawRet + ", " + errOwner.name + ">" : (rawRet == "()" ? "" : " -> " + rawRet);
            final args = [
                for (i in start...f.args.length) {
                    final a = f.args[i];
                    RustImports.toSnakeCase(a.name) + ": " + types.of(a.type, true);
                }
            ].join(", ");
            final allArgs = receiver ? (args.length > 0 ? "&self, " + args : "&self") : args;
            final vis = f.field.isPublic ? "pub " : "";
            lines.push("");
            lines.push("    " + vis + "fn " + RustImports.toSnakeCase(f.field.name) + "(" + allArgs + ")" + ret + " {");
            final receiverName = isStringRepresentation(info.representation) && f.field.name == "toString" ? "self.0.clone()" : "self.0";
            for (line in expr.valueTypeFunctionBody(cls, f, receiverName))
                lines.push("    " + line);
            lines.push("    }");
        }

        if (ValueTypeSupport.memberField(abs, "toString") != null) {
            final f = findFunc(funcFields, "toString");
            lines.push("");
            lines.push("    fn to_string_value(&self) -> String {");
            expr.setFallible(false);
            for (line in expr.valueTypeFunctionBody(cls, f, isStringRepresentation(info.representation) ? "self.0.clone()" : "self.0"))
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
            lines.push("    pub const "
                + RustImports.toScreamingSnakeCase(v.field.name)
                + ": "
                + info.name
                + " = "
                + expr.rawExpression(initializer)
                + ";");
        }
        lines.push("}");

        for (f in funcFields) {
            final op = ValueTypeSupport.operatorOf(abs, f.field);
            if (op == null)
                continue;
            final trait = rustTraitName(op);
            final method = rustTraitMethod(op);
            lines.push("");
            lines.push("impl std::ops::" + trait + " for " + info.name + " {");
            lines.push("    type Output = " + info.name + ";");
            final args = switch (op) {
                case Binary(_): "self, rhs: " + info.name;
                case Unary(_): "self";
            };
            lines.push("    fn " + method + "(" + args + ") -> " + info.name + " {");
            expr.setFallible(false);
            for (line in expr.valueTypeFunctionBody(cls, f, "self.0"))
                lines.push("    " + line);
            lines.push("    }");
            lines.push("}");
        }

        if (ValueTypeSupport.memberField(abs, "toString") != null) {
            lines.push("");
            lines.push("impl std::fmt::Display for " + info.name + " {");
            lines.push("    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {");
            lines.push("        write!(formatter, \"{}\", self.to_string_value())");
            lines.push("    }");
            lines.push("}");
        }
        return lines.join("\n");
    }

    function findFunc(funcFields:Array<ClassFuncData>, name:String):ClassFuncData {
        for (f in funcFields)
            if (f.field.name == name)
                return f;
        Context.error("value type member is missing: " + name, Context.currentPos());
        return null;
    }

    function isStringRepresentation(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().name == "String";
            case _: false;
        };
    }

    function rustTraitName(op:ValueTypeOperator):String {
        return switch (op) {
            case Binary(binary): switch (binary) {
                    case OpAdd: "Add";
                    case OpSub: "Sub";
                    case OpMult: "Mul";
                    case OpDiv: "Div";
                    case OpMod: "Rem";
                    case _: "Add";
                };
            case Unary(unary): switch (unary) {
                    case OpNeg: "Neg";
                    case _: "Neg";
                };
        };
    }

    function rustTraitMethod(op:ValueTypeOperator):String {
        return switch (op) {
            case Binary(binary): switch (binary) {
                    case OpAdd: "add";
                    case OpSub: "sub";
                    case OpMult: "mul";
                    case OpDiv: "div";
                    case OpMod: "rem";
                    case _: "add";
                };
            case Unary(unary): switch (unary) {
                    case OpNeg: "neg";
                    case _: "neg";
                };
        };
    }

    public static function isExceptionSubclass(cls:ClassType):Bool {
        if (cls.superClass == null) {
            return false;
        }
        final parent = cls.superClass.t.get();
        return parent.pack.join(".") == "haxe" && parent.name == "Exception";
    }

    public static function structureSignature(anon:Ref<AnonType>):String {
        final entries = [for (f in anon.get().fields) f.name + ":" + Std.string(f.type)];
        entries.sort(Reflect.compare);
        return entries.join(";");
    }

    function payloadEnumOf(funcFields:Array<ClassFuncData>):Null<EnumType> {
        final ctor = findConstructor(funcFields);
        if (ctor == null) {
            return null;
        }
        for (a in ctor.args) {
            switch (a.type) {
                case TEnum(e, _):
                    return e.get();
                case _:
            }
        }
        return null;
    }

    function findMessageFunc(cls:ClassType, funcFields:Array<ClassFuncData>, payload:EnumType):Null<ClassFuncData> {
        var found:Null<ClassFuncData> = null;
        for (f in funcFields) {
            if (!f.isStatic || f.args.length != 1) {
                continue;
            }
            switch (f.args[0].type) {
                case TEnum(e, _):
                    if (e.get().module == payload.module) {
                        if (found != null) {
                            Context.error("exception class carries more than one message function", cls.pos);
                            return null;
                        }
                        found = f;
                    }
                case _:
            }
        }
        return found;
    }

    function exceptionErrorDecl(cls:ClassType, payload:EnumType, funcFields:Array<ClassFuncData>):String {
        final enumName = payload.name;
        final options = [for (_ => ef in payload.constructs) ef];
        options.sort((a, b) -> Reflect.compare(a.index, b.index));

        final messageFunc = findMessageFunc(cls, funcFields, payload);
        if (messageFunc == null || messageFunc.expr == null) {
            Context.error("exception class carries no message function for its payload enum", cls.pos);
            return null;
        }
        final messages = new Map<String, String>();
        collectMessageCases(messageFunc.expr, options, messages);

        final lines = ["#[derive(Debug, Clone, PartialEq)]", "pub enum " + enumName + " {"];
        for (o in options) {
            final args = enumFieldParams(o);
            if (args.length == 0) {
                lines.push("    " + RustImports.toUpperCamelCase(o.name) + ",");
            } else {
                final params = [
                    for (arg in args)
                        RustImports.toSnakeCase(arg.name) + ": " + fieldType(arg.type, arg.name)
                ].join(", ");
                lines.push("    " + RustImports.toUpperCamelCase(o.name) + " { " + params + " },");
            }
        }
        lines.push("}\n");

        // Display impl
        lines.push("impl std::fmt::Display for " + enumName + " {");
        lines.push("    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {");
        lines.push("        match self {");
        for (o in options) {
            final message = messages.get(o.name);
            final args = enumFieldParams(o);
            if (args.length == 0) {
                final formatted = 'write!(formatter, "{}", ${message})';
                lines.push('            ${enumName}::${RustImports.toUpperCamelCase(o.name)} => ${formatted},');
            } else {
                final params = [for (arg in args) RustImports.toSnakeCase(arg.name)].join(", ");
                lines.push('            ${enumName}::${RustImports.toUpperCamelCase(o.name)} { ${params} } => {');
                final isLiteral = message != null && StringTools.startsWith(StringTools.trim(message), '"');
                if (isLiteral) {
                    lines.push('                write!(formatter, ${message}, ${params})');
                } else {
                    lines.push('                write!(formatter, "{}", ${message})');
                }
                lines.push("            }");
            }
        }
        lines.push("        }");
        lines.push("    }");
        lines.push("}\n");

        // Error impl
        lines.push("impl std::error::Error for " + enumName + " {}");

        return lines.join("\n");
    }

    function fieldType(t:Type, name:String):String {
        return switch (t) {
            case TAbstract(a, _) if (a.get().name == "Int"):
                types.of(t);
            case _: types.of(t);
        }
    }

    function enumFieldParams(ef:haxe.macro.Type.EnumField):Array<{name:String, type:Type}> {
        return switch (ef.type) {
            case TFun(args, _): [for (a in args) {name: a.name, type: a.t}];
            case _: [];
        };
    }

    function collectMessageCases(e:TypedExpr, options:Array<haxe.macro.Type.EnumField>, out:Map<String, String>):Void {
        switch (e.expr) {
            case TReturn(r) if (r != null):
                collectMessageCases(r, options, out);
            case TConst(TString(s)) if (options.length == 1):
                // A single-variant exception folds its message function
                // down to the bare string literal: the typer reduces a
                // one-case switch, so there is no TSwitch to scan. The
                // message belongs to the sole option.
                out.set(options[0].name, '"' + s + '"');
            case TBlock(stmts):
                for (s in stmts)
                    collectMessageCases(s, options, out);
                collectCollapsedCase(stmts, options, out);
            case TMeta(_, inner):
                collectMessageCases(inner, options, out);
            case TSwitch(_, cases, _):
                for (c in cases) {
                    if (c.values.length == 0) {
                        continue;
                    }
                    final name = caseConstructorName(c.values[0], options);
                    if (name == null) {
                        continue;
                    }
                    bindPatternLocals(c.expr);
                    final body = unwrapReturn(c.expr);
                    switch (body.expr) {
                        case TConst(TString(s)):
                            out.set(name, '"' + s + '"');
                        case _:
                            out.set(name, renderDisplayFormat(body));
                    }
                }
            case _:
        }
    }

    /**
        A single-case switch in statement position becomes a two
        statement block after typing: the payload binding and the body. Recover
        the case so Display keeps its message.
    **/
    function collectCollapsedCase(stmts:Array<TypedExpr>, options:Array<haxe.macro.Type.EnumField>, out:Map<String, String>):Void {
        if (stmts.length != 2) {
            return;
        }
        switch (stmts[0].expr) {
            case TVar(_, init) if (init != null):
                switch (stripDecorations(init).expr) {
                    case TEnumParameter(_, ef, _):
                        for (o in options) {
                            if (o.name != ef.name) {
                                continue;
                            }
                            bindPatternLocals(stmts[0]);
                            bindPatternLocals(stmts[1]);
                            final body = unwrapReturn(stmts[1]);
                            switch (body.expr) {
                                case TConst(TString(s)):
                                    out.set(o.name, '"' + s + '"');
                                case _:
                                    out.set(o.name, renderDisplayFormat(body));
                            }
                        }
                    case _:
                }
            case _:
        }
    }

    function renderDisplayFormat(e:TypedExpr):String {
        switch (e.expr) {
            case TBinop(OpAdd, l, r):
                final lStr = switch (l.expr) {
                    case TConst(TString(s)): StringTools.replace(StringTools.replace(s, "{", "{{"), "}", "}}");
                    case _: "";
                };
                final rStr = switch (r.expr) {
                    case TLocal(_): "{}";
                    case TConst(TString(s)): StringTools.replace(StringTools.replace(s, "{", "{{"), "}", "}}");
                    case _: "{}";
                };
                return '"' + lStr + rStr + '"';
            case _:
                return expr.rawExpression(e);
        }
    }

    function bindPatternLocals(e:TypedExpr):Void {
        switch (e.expr) {
            case TBlock(stmts):
                for (s in stmts)
                    bindPatternLocals(s);
            case TVar(v, init) if (init != null):
                switch (stripDecorations(init).expr) {
                    case TEnumParameter(_, ef, index):
                        expr.bindLocalName(v, expr.payloadName(ef, index));
                    case TLocal(source):
                        final bound = expr.boundNameOf(source);
                        if (bound != null) {
                            expr.bindLocalName(v, bound);
                        }
                    case _:
                }
            case _:
        }
    }

    function stripDecorations(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TParenthesis(inner) | TCast(inner, _) | TMeta(_, inner): stripDecorations(inner);
            case _: e;
        }
    }

    function caseConstructorName(value:TypedExpr, options:Array<haxe.macro.Type.EnumField>):Null<String> {
        switch (value.expr) {
            case TConst(TInt(index)):
                for (o in options) {
                    if (o.index == index) {
                        return o.name;
                    }
                }
                return null;
            case TField(_, FEnum(_, ef)):
                return ef.name;
            case TEnumParameter(_, ef, _):
                return ef.name;
            case _:
                return null;
        }
    }

    function unwrapReturn(e:TypedExpr):TypedExpr {
        return switch (e.expr) {
            case TReturn(r) if (r != null): unwrapReturn(r);
            case TBlock(stmts) if (stmts.length > 0):
                unwrapReturn(stmts[stmts.length - 1]);
            case _: e;
        }
    }

    function isAllStatic(varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Bool {
        for (v in varFields) {
            if (!v.isStatic)
                return false;
        }
        for (f in funcFields) {
            if (f.field.name == "new")
                return false;
            if (!f.isStatic)
                return false;
        }
        return true;
    }

    /**
        Returns whether an extension receiver belongs to the same generated
        Rust module family as its declaring class. Standard-library and
        resident types stay on the free-function path.
    **/
    public static function isCrateOwnedReceiver(ownerModule:String, t:Null<Type>):Bool {
        final receiverModule = receiverModuleOf(t);
        if (receiverModule == null || isForeignReceiverModule(receiverModule)) {
            return false;
        }
        return moduleFamily(ownerModule) == moduleFamily(receiverModule);
    }

    static function receiverModuleOf(t:Null<Type>):Null<String> {
        if (t == null) {
            return null;
        }
        return switch (t) {
            case TInst(c, _): c.get().module;
            case TEnum(e, _): e.get().module;
            case TType(d, _): d.get().module;
            case TLazy(f): receiverModuleOf(f());
            case _: null;
        };
    }

    static function isForeignReceiverModule(module:String):Bool {
        if (module == "String" || module == "Array" || module == "Map" || module == "Std" || module == "Math") {
            return true;
        }
        return StringTools.startsWith(module, "haxe.") || StringTools.startsWith(module, "std.");
    }

    static function moduleFamily(module:String):String {
        final parts = module.split(".");
        return parts.length <= 1 ? "" : parts.slice(0, parts.length - 1).join(".");
    }

    function classHasLifetime(varFields:Array<ClassVarData>, borrowedBytes:Map<String, Bool>):Bool {
        for (v in varFields) {
            switch (v.field.type) {
                case TInst(c, _) if (c.get().module == "haxe.io.Bytes"):
                    if (borrowedBytes.exists(v.field.name))
                        return true;
                case TType(d, _) if (d.get().module == "haxe.io.Bytes"):
                    if (borrowedBytes.exists(v.field.name))
                        return true;
                case _:
            }
        }
        return false;
    }

    function borrowedByteFields(funcFields:Array<ClassFuncData>):Map<String, Bool> {
        final names:Map<String, Bool> = [];
        for (f in funcFields)
            if (f.field.name == "new") {
                for (arg in f.args)
                    if (isBytesType(arg.type))
                        names.set(arg.name, true);
            }
        return names;
    }

    function findConstructor(funcFields:Array<ClassFuncData>):Null<ClassFuncData> {
        for (f in funcFields) {
            if (f.field.name == "new")
                return f;
        }
        return null;
    }

    function renderRustDataTable(field:ClassField, elems:Array<Int>):String {
        final vis = field.isPublic ? "pub " : "";
        // Resident runtime modules render Int as i32 (RuntimeResidents),
        // so their tables carry the same element type as the functions
        // that index them.
        final elemType = RuntimeResidents.isResident(imports.selfModule) ? "i32" : "u32";
        final formatted = [for (x in elems) (x >= 0 && x <= 9) ?Std.string(x):"0x" + StringTools.hex(x).toLowerCase()];
        final chunks:Array<String> = [];
        var i = 0;
        while (i < formatted.length) {
            final end = Std.int(Math.min(i + 8, formatted.length));
            chunks.push("    " + formatted.slice(i, end).join(", "));
            i = end;
        }
        return '${vis}static ${RustImports.toScreamingSnakeCase(field.name)}: [${elemType}; ${elems.length}] = [\n' + chunks.join(",\n") + "\n];";
    }

    function isFunctionType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TFun(_, _): true;
            case _: false;
        };
    }

    function isStaticFunctionField(v:ClassVarData):Bool {
        return v.isStatic && isFunctionType(v.field.type);
    }

    function staticFunctionDecl(v:ClassVarData):Array<String> {
        if (!isStaticFunctionField(v)) {
            return [];
        }
        final field = v.field;
        final initializer = field.expr();
        if (initializer == null || !isCaptureFreeStaticInitializer(initializer)) {
            Context.error("static function fields accept capture-free initializers only", field.pos);
            return [];
        }
        switch (stripDecorations(initializer).expr) {
            case TFunction(_):
            case _:
                Context.error("static function fields accept capture-free initializers only", field.pos);
                return [];
        }
        final vis = field.isPublic ? "pub " : "";
        final name = RustImports.toScreamingSnakeCase(field.name);
        final initializerText = expr.rawFunctionInitializer(initializer);
        return [
            vis + "static " + name + ": " + types.staticFunctionOf(field.type) + " = " + initializerText + ";"
        ];
    }

    /**
        Checks the outer function body for locals that are not its own
        arguments or declarations. Nested literals may capture the outer
        function's arguments; that is still a capture-free static
        initializer because the static value itself has no environment.
    **/
    function isCaptureFreeStaticInitializer(e:TypedExpr):Bool {
        return switch (stripDecorations(e).expr) {
            case TFunction(f):
                final locals:Map<Int, Bool> = [];
                for (arg in f.args)
                    locals.set(arg.v.id, true);
                var captures = false;
                function walk(x:TypedExpr):Void {
                    if (captures)
                        return;
                    switch (x.expr) {
                        case TLocal(v):
                            if (!locals.exists(v.id))
                                captures = true;
                        case TField(_, FInstance(_, _, _)) | TField(_, FAnon(_)):
                            captures = true;
                        case TField(_, FStatic(_, cf)) if (cf.get().kind.match(FVar(_, _))):
                            captures = true;
                        case TVar(v, init):
                            if (init != null)
                                haxe.macro.TypedExprTools.iter(init, walk);
                            locals.set(v.id, true);
                        case TFor(v, source, body):
                            walk(source);
                            locals.set(v.id, true);
                            walk(body);
                        case TFunction(_):
                            // A nested closure's capture of this function's
                            // arguments does not capture the static value.
                        case _:
                            haxe.macro.TypedExprTools.iter(x, walk);
                    }
                }
                walk(f.expr);
                !captures;
            case _:
                false;
        };
    }

    function staticVarDecl(cls:ClassType, v:ClassVarData):Array<String> {
        final field = v.field;
        if (isStaticFunctionField(v)) {
            return [];
        }
        if (v.isStatic && DataTableHelper.isDataTableField(field)) {
            return [];
        }
        if (v.isStatic && StaticFieldHelper.isConstValue(field)) {
            final init = StaticFieldHelper.validatedInitializer(field, cls);
            final valStr = expr.rawExpression(init);
            final typeStr = switch (field.type) {
                case TInst(c, _) if (c.get().name == "String"): "&str";
                case _: types.of(field.type);
            };
            final vis = field.isPublic ? "pub " : "";
            final name = RustImports.toSnakeCase(field.name).toUpperCase();
            return ['    ${vis}const ${name}: ${typeStr} = $valStr;'];
        }
        return [];
    }

    /** A mutable or container static lives outside the associated impl. */
    function moduleStaticVarDecl(cls:ClassType, v:ClassVarData):Array<String> {
        final field = v.field;
        if (isStaticFunctionField(v)) {
            return [];
        }
        if (!v.isStatic || DataTableHelper.isDataTableField(field) || StaticFieldHelper.isConstValue(field)) {
            return [];
        }
        final init = StaticFieldHelper.validatedInitializer(field, cls);
        final vis = field.isPublic ? "pub " : "";
        final typeStr = types.of(field.type);
        final name = RustImports.toScreamingSnakeCase(field.name);
        if (field.isFinal && StaticFieldHelper.isNonEmptyArrayLiteral(init)) {
            if (StaticFieldHelper.isIntLiteralArray(init)) {
                final elementType = types.of(StaticFieldHelper.arrayElementType(field.type));
                final elements = switch (StaticFieldHelper.stripDecorations(init).expr) {
                    case TArrayDecl(values): values.length;
                    case _: 0;
                };
                return [
                    '${vis}static ${name}: [${elementType}; ${elements}] = ${expr.rawArrayLiteral(init)};'
                ];
            }
            imports.require("std::sync::LazyLock");
            return [
                '${vis}static ${name}: LazyLock<${typeStr}> = LazyLock::new(|| ${expr.rawExpression(init)});'
            ];
        }
        if (StaticFieldHelper.isConstruction(init) && !StaticFieldHelper.isSelfConstruction(field, cls, init)) {
            // The per-function default completion never visits static
            // initializers, so a construction over coalescing-default
            // parameters completes its omitted arguments to None here.
            DefaultArgExpander.completeStaticInitializerForRust(cls, field.name, init);
            imports.require("std::sync::LazyLock");
            return [
                '${vis}static ${name}: LazyLock<${typeStr}> = LazyLock::new(|| ${expr.rawExpression(init)});'
            ];
        }
        imports.require("std::sync::Mutex");
        return [
            '${vis}static ${name}: Mutex<${typeStr}> = Mutex::new(${expr.rawExpression(init)});'
        ];
    }

    function isStringType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TInst(c, _): c.get().name == "String";
            case TType(d, params): isStringType(d.get().type);
            case _: false;
        };
    }

    function ctorArgType(t:Type, hasLifetime:Bool, owningClass:Bool):String {
        // A constructor moves its arguments into fields. On the generic
        // resident classes an Array parameter becomes an owned Vec that
        // the field initializer takes over; other classes keep the
        // borrowed parameter forms.
        switch (Context.follow(t)) {
            case TInst(c, _) if (c.get().name == "Array"):
                return types.of(t, false);
            case TAbstract(a, _) if (a.get().name == "ReadOnlyArray"
                || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
                return types.of(t, false);
            case _:
        }
        return hasLifetime && isBytesType(t) ? "&'a [u8]" : types.of(t, true);
    }

    /** A `var x(get, never)` field renders no storage on this target (feature spec 27). */
    static function isGetterOnlyProperty(field:haxe.macro.Type.ClassField):Bool {
        switch (field.kind) {
            case FVar(read, write):
                return read.match(AccCall) && write.match(AccNever);
            case _:
                return false;
        }
    }

    function instanceVarDecl(v:ClassVarData, hasLifetime:Bool, borrowedBytes:Map<String, Bool>):Array<String> {
        final field = v.field;
        // A `var x(get, never)` field renders no storage on this target;
        // the get_x() method is the lowering (feature spec 27).
        if (isGetterOnlyProperty(field)) {
            return [];
        }
        final snake = RustImports.toSnakeCase(field.name);
        final typeStr = switch (field.type) {
            case TInst(c, _) if (c.get().module == "haxe.io.Bytes"):
                borrowedBytes.exists(field.name) ? "&'a [u8]" : "Vec<u8>";
            case TType(d, _) if (d.get().module == "haxe.io.Bytes"):
                borrowedBytes.exists(field.name) ? "&'a [u8]" : "Vec<u8>";
            case TAbstract(a, _) if (a.get().name == "Int" && (field.name == "offset" || field.name == "length")):
                "u32";
            case _:
                types.of(field.type);
        };
        // Instance-field visibility follows the Haxe declaration. Public
        // fields are part of the generated crate's API; private fields stay
        // available to the crate's own lowering and tests only.
        final visibility = field.isPublic ? "pub" : "pub(crate)";
        return ['    $visibility $snake: $typeStr,'];
    }

    function staticFuncDecl(cls:ClassType, f:ClassFuncData, firstArg:Int = 0, receiverMethod:Bool = false):Array<String> {
        for (a in f.args) {
            expr.reserveName(a.name);
            expr.setArgType(a.name, types.of(a.type, true));
        }
        // A parameter the body never mentions and no default-argument
        // prologue rebinds takes the underscore prefix; the lowering leaves
        // it otherwise unused.
        final coalescedParams:Map<String, Bool> = [];
        for (site in DefaultArgExpander.coalescingSitesForFunction(f.expr)) {
            coalescedParams.set(site.parameter, true);
        }
        final snakeName = RustImports.toSnakeCase(f.field.name);
        final args = [
            for (i in firstArg...f.args.length) {
                final a = f.args[i];
                var pType = types.of(a.type, true);
                if (argIsMutated(f.expr, a.name) && StringTools.startsWith(pType, "&Vec<")) pType = "&mut " + pType.substr(1);
                final mut = argIsMutated(f.expr, a.name) && !StringTools.startsWith(pType, "&mut") ? "mut " : "";
                final mentioned = argIsMentioned(f.expr, a.name) || coalescedParams.exists(a.name);
                mut + (mentioned ? "" : "_") + RustImports.toSnakeCase(a.name) + ": " + pType;
            }
        ].join(", ");
        final allArgs = if (receiverMethod) {
            args.length > 0 ? "&self, " + args : "&self";
        } else {
            args;
        };
        final methodParams = staticParamBounds(f, collectMethodTypeParams(f, [for (p in cls.params) p.name]));
        final methodGenericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";

        final isFallible = funcIsFallible(f);
        final errOwner = isFallible ? resolveErrorOwner(f, cls) : null;
        if (isFallible && errOwner != null) {
            imports.requireType(errOwner.module, errOwner.name);
        }
        expr.setFallible(isFallible, errOwner != null ? errOwner.name : null, errOwner != null
            && errOwner.hasOverflow ? state.overflowVariant : null);

        var rawRetType = returnsArgArray(f) ? types.of(f.ret, true) : types.functionReturnOf(f.ret);
        // A business function that directly returns that lowering uses the
        // signed result type; other Null<Int> results use the module's u32
        // domain.
        if (directParseReturn(f) && rawRetType == "Option<u32>") {
            rawRetType = "Option<i32>";
        }
        final retType = isFallible ? 'Result<$rawRetType, ${errOwner.name}>' : rawRetType;
        final ret = retType == "()" ? "" : " -> " + retType;
        final vis = f.field.isPublic ? "pub " : "";
        final head = '    ${vis}fn ${snakeName}${methodGenericStr}($allArgs)$ret {';
        if (receiverMethod && f.args[0].tvar != null) {
            expr.bindLocalName(f.args[0].tvar, receiverBodyName(f.args[0].type));
        }

        expr.setReturnUnsigned(rawRetType == "u32");
        expr.setReturnTypeName(rawRetType);
        expr.setReturnType(f.ret);
        final body = expr.functionBody(cls, f);
        return [head].concat(body.map(l -> "    " + l)).concat(["    }"]);
    }

    /** True when the body names the local anywhere, read or assignment target. */
    public static function argIsMentioned(body:Null<TypedExpr>, name:String):Bool {
        if (body == null)
            return false;
        var found = false;
        function walk(e:TypedExpr) {
            if (found)
                return;
            switch (e.expr) {
                case TLocal(v):
                    if (v.name == name)
                        found = true;
                    return;
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, walk);
        }
        walk(body);
        return found;
    }

    public static function argIsMutated(body:Null<TypedExpr>, name:String, depth:Int = 0):Bool {
        if (body == null)
            return false;
        // A recursive callee (a helper that calls itself with the same
        // array argument) would analyze its own body forever; the
        // direct mutations the walk detects already settled the answer
        // above the recursion, so a deep chain stops conservatively.
        if (depth > 8)
            return false;
        var found = false;
        function root(e:TypedExpr):Bool
            return switch (e.expr) {
                case TLocal(v): v.name == name;
                case TField(s, _): root(s);
                case TArray(s, _): root(s);
                case TParenthesis(s): root(s);
                case TMeta(_, s): root(s);
                case _: false;
            };
        function walk(e:TypedExpr) {
            switch (e.expr) {
                case TBinop(OpAssign, l, _):
                    if (root(l))
                        found = true;
                case TCall(fn, args):
                    // A call to a helper that mutates an Array argument mutates
                    // the corresponding caller argument as well; otherwise the
                    // declaration is emitted as &Vec while the call requires &mut.
                    switch (fn.expr) {
                        case TField(_, FStatic(_, cf)) | TField(_, FInstance(_, _, cf)) | TField(_, FAnon(cf)):
                            final calleeArgs = switch (Context.follow(cf.get().type)) {
                                case TFun(ps, _): ps;
                                case _: [];
                            };
                            for (i in 0...args.length)
                                if (i < calleeArgs.length && root(args[i])) {
                                    final p = calleeArgs[i];
                                    if (switch (Context.follow(p.t)) {
                                            case TInst(c, _): c.get().name == "Array";
                                            case _: false;
                                        }) {
                                        final calleeBody = cf.get().expr();
                                        if (calleeBody != null && argIsMutated(calleeBody, p.name, depth + 1))
                                            found = true;
                                        }
                                }
                        case _:
                    }
                    switch (fn.expr) {
                        case TField(s, FInstance(_, _, cf) | FAnon(cf)) if (root(s)):
                            if ([
                                "push",
                                "insert",
                                "pop",
                                "shift",
                                "unshift",
                                "remove",
                                "removeAt",
                                "splice",
                                "reverse",
                                "sort",
                                "set",
                                "add",
                                "addChar"
                            ].indexOf(cf.get().name) >= 0) found = true;
                        case _:
                    }
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, walk);
        }
        walk(body);
        return found;
    }

    function receiverBodyName(t:Type):String {
        return switch (Context.follow(t)) {
            case TEnum(_, _): "*self";
            case _: "self";
        };
    }

    /**
        True when the function body is exactly a return of one `Std.parseInt`
        call: the emitted rust signature must carry the lowering's signed
        `Option<i32>` result for the lowering; other Null<Int> results use
        the module's unsigned domain.
    **/
    function directParseReturn(f:ClassFuncData):Bool {
        if (f.expr == null) {
            return false;
        }
        final last = switch (f.expr.expr) {
            case TBlock(stmts): stmts.length > 0 ? stmts[stmts.length - 1] : null;
            case _: f.expr;
        };
        if (last == null) {
            return false;
        }
        switch (last.expr) {
            case TReturn(ret) if (ret != null):
                switch (ret.expr) {
                    case TCall(callee, args):
                        switch (callee.expr) {
                            case TField(_, FStatic(c, cf)):
                                return c.get().module == "Std" && cf.get().name == "parseInt" && args.length == 1;
                            case _:
                        }
                    case _:
                }
            case _:
        }
        return false;
    }

    function extractedFuncDecl(cls:ClassType, f:ClassFuncData):Array<String> {
        if (StaticFunctionMarkers.isTopLevel(f.field) || !isCrateOwnedReceiver(cls.module, f.args[0].type)) {
            return unindentRustFunction(staticFuncDecl(cls, f));
        }
        final receiverType = types.of(f.args[0].type, false);
        return ["impl " + receiverType + " {"].concat(staticFuncDecl(cls, f, 1, true)).concat(["}"]);
    }

    function unindentRustFunction(lines:Array<String>):Array<String> {
        return [
            for (line in lines)
                StringTools.startsWith(line, "    ") ? line.substring(4) : line
        ];
    }

    /**
        A static method that returns an instantiation of a generic class
        calls that class's impl inside its body, and the impl carries the
        class-parameter Clone bounds. The method's own type parameters
        take the same bound when they reach the instantiation, so the
        body resolves against the impl.
     */
    function staticParamBounds(f:ClassFuncData, methodParams:Array<String>):Array<String> {
        if (methodParams.length == 0 || f.ret == null)
            return methodParams;
        final reached:Array<String> = [];
        switch (Context.follow(f.ret)) {
            case TInst(c, ps) if (c.get().params.length > 0 && c.get().name != "Array"):
                for (p in ps) {
                    switch (Context.follow(p)) {
                        case TInst(pc, _):
                            final pn = pc.get();
                            if (pn.kind.match(KTypeParameter(_)) && methodParams.indexOf(pn.name) >= 0) {
                                reached.push(pn.name);
                            }
                        case _:
                    }
                }
            case _:
        }
        return [for (n in methodParams) reached.indexOf(n) >= 0 ? n + ": Clone" : n];
    }

    function returnsArgArray(f:ClassFuncData):Bool {
        if (f.expr == null)
            return false;
        return switch (f.ret) {
            case TInst(c, _) if (c.get().name == "Array"):
                final retExpr = unwrapReturn(f.expr);
                switch (retExpr.expr) {
                    case TLocal(v):
                        var isArg = false;
                        for (a in f.args) {
                            if (a.name == v.name) {
                                isArg = true;
                                break;
                            }
                        }
                        isArg;
                    case _: false;
                }
            case _: false;
        };
    }

    function findErrorOwner():String {
        if (state.errorName != null) {
            return state.errorName;
        }
        for (owner in state.payloadEnumOwners) {
            return owner;
        }
        Context.error("no error enum exists in AST for fallible function", Context.currentPos());
        return null;
    }

    /**
        Resolves the error enum owning this function's Result from what the body
        actually throws. The global names stay as the fallback for functions
        that are fallible only through helper calls.
    **/
    function resolveErrorOwner(f:ClassFuncData, cls:ClassType):{name:String, module:String, hasOverflow:Bool} {
        final key = RustEmissionState.funcKey(f.classType.module, f.field.name, f.isStatic);
        final syntheticType = state.funcErrorTypes.get(key);
        if (syntheticType != null && state.isSyntheticErrorType(syntheticType.name)) {
            return {name: syntheticType.name, module: syntheticType.module, hasOverflow: false};
        }
        if (state.funcEnumConflicts.exists(key)) {
            final synthetic = state.funcErrorTypes.get(key);
            if (synthetic != null)
                return {name: synthetic.name, module: synthetic.module, hasOverflow: false};
        }
        var unique:Null<{name:String, module:String}> = null;
        for (thrown in collectThrownPayloadEnums(f.expr)) {
            if (unique == null) {
                unique = thrown;
            } else if (unique.module != thrown.module) {
                Context.error("function throws payloads of " + unique.module + " and " + thrown.module
                    + "; the Rust lowering supports one error enum per function",
                    f.field.pos);
            }
        }
        if (unique == null) {
            // No direct throw: the error enum arrived through a call edge.
            final inherited = state.funcErrorEnums.get(key);
            if (inherited != null) {
                unique = inherited;
            }
        }
        if (f.field.name == "require" && cls.name == "Semver") {
            return {name: "SemverFault", module: cls.module, hasOverflow: false};
        }
        if (unique != null) {
            final emittedIn = state.payloadEnumModules.exists(unique.module) ? state.payloadEnumModules.get(unique.module) : cls.module;
            return {
                name: unique.name,
                module: emittedIn,
                hasOverflow: state.countOverflowEnums.exists(unique.module)
            };
        }
        return {
            name: findErrorOwner(),
            module: state.errorModule != null ? state.errorModule : cls.module,
            hasOverflow: true
        };
    }

    function collectThrownPayloadEnums(e:TypedExpr):Array<{name:String, module:String}> {
        final out:Array<{name:String, module:String}> = [];
        if (e == null) {
            return out;
        }
        // Throws of a domain the surrounding region catches do not reach
        // the signature, so the walk carries the absorbed modules.
        function walk(x:TypedExpr, absorbed:Array<String>) {
            function descend() {
                haxe.macro.TypedExprTools.iter(x, function(child) walk(child, absorbed));
            }
            switch (x.expr) {
                case TThrow(t):
                    switch (stripDecorations(t).expr) {
                        case TNew(c, _, args) if (args.length > 0):
                            final en = payloadEnumOfArg(args[0]);
                            if (en != null && state.exceptionPayloads.exists(c.get().module)) {
                                if (absorbed.indexOf(en.get().module) < 0) {
                                    out.push({name: en.get().name, module: en.get().module});
                                }
                            }
                        case _:
                    }
                    descend();
                case TTry(regionBody, regionCatches):
                    final caught = [for (c in regionCatches) caughtPayloadEnumModuleOf(c.v)];
                    final absorbedBody = absorbed.concat([for (m in caught) if (m != null) m]);
                    walk(regionBody, absorbedBody);
                    for (c in regionCatches) {
                        walk(c.expr, absorbed);
                    }
                case _:
                    descend();
            }
        }
        walk(e, []);
        return out;
    }

    /**
        Returns the payload enum module a catch clause handles, or null when
        the caught class carries no payload enum.
    **/
    function caughtPayloadEnumModuleOf(v:haxe.macro.Type.TVar):Null<String> {
        return switch (v.t) {
            case TInst(c, _):
                state.exceptionPayloads.exists(c.get().module) ? state.exceptionPayloads.get(c.get().module) : null;
            case _: null;
        }
    }

    function payloadEnumOfArg(arg:TypedExpr):Null<Ref<haxe.macro.Type.EnumType>> {
        return switch (stripDecorations(arg).expr) {
            case TField(_, FEnum(en, _)): en;
            case TCall(fn, _):
                switch (stripDecorations(fn).expr) {
                    case TField(_, FEnum(en, _)): en;
                    case _: null;
                }
            case _: null;
        };
    }

    function instanceFuncDecl(cls:ClassType, f:ClassFuncData, hasLifetime:Bool, isTraitImpl:Bool = false):Array<String> {
        final isConstructor = f.field.name == "new";
        final snakeName = isConstructor ? "new" : RustImports.toSnakeCase(f.field.name);

        for (a in f.args) {
            expr.reserveName(a.name);
        }

        if (isConstructor) {
            final args = [
                for (a in f.args)
                    RustImports.toSnakeCase(a.name) + ": " + ctorArgType(a.type, hasLifetime, cls.params.length > 0)
            ].join(", ");
            // A throwing constructor returns Result<Self, E> through the
            // fallibility machinery; its statements render before the
            // struct literal, so the source construction invariants
            // survive on this target (feature spec 27).
            final ctorFallible = funcIsFallible(f);
            final errOwner = ctorFallible ? resolveErrorOwner(f, cls) : null;
            if (ctorFallible && errOwner != null) {
                imports.requireType(errOwner.module, errOwner.name);
            }
            expr.setFallible(ctorFallible, errOwner != null ? errOwner.name : null, errOwner != null
                && errOwner.hasOverflow ? state.overflowVariant : null);
            final ret = ctorFallible ? " -> Result<Self, " + errOwner.name + ">" : " -> Self";
            var hasInstanceFields = false;
            for (field in cls.fields.get()) {
                switch (field.kind) {
                    case FVar(_, _):
                        var isStatic = false;
                        for (staticField in cls.statics.get()) {
                            if (staticField.name == field.name) {
                                isStatic = true;
                                break;
                            }
                        }
                        if (!isStatic) {
                            hasInstanceFields = true;
                            break;
                        }
                    case _:
                }
            }
            final constCtor = !ctorFallible && !hasInstanceFields;
            final head = '    pub ${constCtor ? "const " : ""}fn new($args)$ret {';
            final parts = expr.constructorBody(cls, f);
            final lines = [head];
            for (l in parts.statementLines) {
                lines.push("    " + l);
            }
            lines.push("        " + (ctorFallible ? "Ok(Self {" : "Self {"));
            for (a in f.args) {
                if (!hasInstanceField(cls, a.name))
                    continue;
                final sname = RustImports.toSnakeCase(a.name);
                // A String parameter borrows as &str while the field owns
                // a String; the initializer converts (feature spec 27).
                final isStringParam = types.of(a.type, true) == "&str";
                final isNullableStringParam = types.of(a.type, false) == "Option<String>";
                if (isStringParam) {
                    lines.push('            $sname: ${sname}.to_string(),');
                } else if (isNullableStringParam) {
                    lines.push('            $sname: match $sname { Some(v) => Some(v.to_string()), None => None },');
                } else {
                    lines.push('            $sname,');
                }
            }
            // Fields the constructor initializes from their own
            // expressions, and fields with no constructor assignment at
            // all; a getter-only property renders no storage (feature
            // spec 27).
            for (field in cls.fields.get()) {
                switch (field.kind) {
                    case FVar(_, _):
                        if (field.name != "new" && !hasArg(f.args, field.name) && !isGetterOnlyProperty(field)) {
                            final sname = RustImports.toSnakeCase(field.name);
                            final init = parts.fieldInits.exists(field.name) ? parts.fieldInits.get(field.name) : switch (field.type) {
                                case TAbstract(a, _) if (a.get().name == "Int"): "0";
                                case TInst(c, _) if (c.get().name == "BytesBuffer"): "BytesBuffer::new()";
                                case _: "Default::default()";
                            };
                            final ownedInit = switch (Context.follow(field.type)) {
                                case TInst(c, _) if (c.get().name == "String" && StringTools.startsWith(init, "\"")): init + ".to_string()";
                                case _: init;
                            };
                            lines.push('            $sname: $ownedInit,');
                        }
                    case _:
                }
            }
            lines.push("        " + (ctorFallible ? "})" : "}"));
            lines.push("    }");
            return lines;
        }

        final isMutating = isMethodMutating(f);
        // The sorted-table builder transfers its boxed comparator into the
        // immutable table, so its build method consumes the builder instead
        // of moving that box out of a shared borrow.
        final consumesSelf = cls.module == "runtime.SortedTable" && f.field.name == "build";
        final selfParam = consumesSelf ? "self" : (isMutating ? "&mut self" : "&self");
        final otherArgs = [
            for (a in f.args) {
                var pType = paramType(a.type, f.field.name, a.name);
                if (argIsMutated(f.expr, a.name) && StringTools.startsWith(pType, "&Vec<")) pType = "&mut " + pType.substr(1);
                expr.setArgType(a.name, pType);
                RustImports.toSnakeCase(a.name) + ": " + pType;
            }
        ].join(", ");
        final allArgs = otherArgs.length > 0 ? selfParam + ", " + otherArgs : selfParam;

        final isFallible = funcIsFallible(f);
        final errOwner = isFallible ? resolveErrorOwner(f, cls) : null;
        if (isFallible && errOwner != null) {
            imports.requireType(errOwner.module, errOwner.name);
        }
        expr.setFallible(isFallible, errOwner != null ? errOwner.name : null, errOwner != null
            && errOwner.hasOverflow ? state.overflowVariant : null);

        final rawRetType = methodReturnType(f.ret, f.field.name);
        final retType = isFallible ? 'Result<$rawRetType, ${errOwner.name}>' : rawRetType;
        final ret = retType == "()" ? "" : " -> " + retType;
        final vis = (f.field.isPublic && !isTraitImpl) ? "pub " : "";
        final methodParams = collectMethodTypeParams(f, [for (p in cls.params) p.name]);
        final methodGenericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
        final head = '    ${vis}fn ${snakeName}${methodGenericStr}($allArgs)$ret {';

        expr.setReturnUnsigned(rawRetType == "u32");
        expr.setReturnTypeName(rawRetType);
        expr.setReturnType(f.ret);
        final body = expr.functionBody(cls, f);
        return [head].concat(body.map(l -> "    " + l)).concat(["    }"]);
    }

    /**
        Type parameters a method signature introduces beyond its class's
        own: collected from the argument and return types in appearance
        order. The generic builder statics of the sorted-table resident
        are the source of these.
    **/
    function collectMethodTypeParams(f:ClassFuncData, classParamNames:Array<String>):Array<String> {
        final found:Array<String> = [];
        function walk(t:Null<Type>):Void {
            if (t == null) {
                return;
            }
            switch (Context.follow(t)) {
                case TInst(c, ps):
                    final cls = c.get();
                    switch (cls.kind) {
                        case KTypeParameter(_):
                            if (classParamNames.indexOf(cls.name) < 0 && found.indexOf(cls.name) < 0) {
                                found.push(cls.name);
                            }
                        case _:
                    }
                    for (p in ps)
                        walk(p);
                case TAbstract(_, ps) | TEnum(_, ps) | TType(_, ps):
                    for (p in ps)
                        walk(p);
                case TFun(fargs, fret):
                    for (a in fargs)
                        walk(a.t);
                    walk(fret);
                case _:
            }
        }
        for (a in f.args) {
            walk(a.type);
        }
        walk(f.ret);
        return found;
    }

    function isBytesType(t:Type):Bool {
        return switch (t) {
            case TInst(c, _) if (c.get().module == "haxe.io.Bytes"): true;
            case TType(d, _) if (d.get().module == "haxe.io.Bytes"): true;
            case _: false;
        };
    }

    function hasInstanceField(cls:ClassType, name:String):Bool {
        for (field in cls.fields.get()) {
            switch (field.kind) {
                case FVar(_, _) if (field.name == name):
                    return true;
                case _:
            }
        }
        return false;
    }

    function hasArg(args:Array<reflaxe.data.ClassFuncArg>, name:String):Bool {
        for (a in args) {
            if (a.name == name)
                return true;
        }
        return false;
    }

    function paramType(t:Type, funcName:String, paramName:String):String {
        if (funcName == "readAscii" || funcName == "ensureRemaining") {
            return "u32";
        }
        if (funcName == "writeU16") {
            return "u16";
        }
        if (funcName == "writeU32") {
            return "u32";
        }
        if (funcName == "writeAscii") {
            return "&str";
        }
        return types.of(t, true);
    }

    function methodReturnType(t:Type, funcName:String):String {
        if (funcName == "readU16")
            return "u16";
        if (funcName == "readU32")
            return "u32";
        if (funcName == "readF64" || funcName == "readF32" || funcName == "readF16")
            return FloatPrecision.isF32() ? "f32" : "f64";
        if (funcName == "readAscii")
            return "String";
        if (funcName == "remaining" || funcName == "consumed")
            return "u32";
        if (funcName == "ensureRemaining")
            return "()";
        return types.functionReturnOf(t);
    }

    function isMethodMutating(f:ClassFuncData):Bool {
        final name = f.field.name;
        if (name == "parse" || name == "value" || name == "string" || name == "number" || name == "word" || name == "skip" || name == "takeCode") {
            return true;
        }
        if (name == "readU16" || name == "readU32" || name == "readF64" || name == "readF32" || name == "readF16" || name == "readAscii"
            || name == "writeU16" || name == "writeU32" || name == "writeF64" || name == "writeF32" || name == "writeF16" || name == "writeAscii") {
            return true;
        }
        if (name == "finish") {
            return true;
        }
        return bodyMutatesSelf(f.expr);
    }

    /**
        Whether the method body writes through the receiver: a field of
        `this` assigned, an element of an own-field array assigned, or a
        mutating array method called on an own-field array. The
        name list above stays for the extern reader and writer faces;
        this walk covers declared classes, whose storage the resident
        runtime tables own.
    **/
    function bodyMutatesSelf(body:Null<TypedExpr>):Bool {
        if (body == null) {
            return false;
        }
        var mutates = false;
        function walk(e:TypedExpr) {
            switch (e.expr) {
                case TBinop(OpAssign, lhs, _):
                    if (ownFieldRoot(lhs)) {
                        mutates = true;
                    }
                case TCall(fn, _):
                    switch (fn.expr) {
                        case TField(subj, FInstance(_, _, cf) | FAnon(cf)):
                            final n = cf.get().name;
                            if (n == "push" || n == "insert" || n == "pop" || n == "shift" || n == "unshift" || n == "remove" || n == "removeAt"
                                || n == "splice" || n == "reverse" || n == "sort") {
                                if (ownFieldRoot(subj)) {
                                    mutates = true;
                                }
                            }
                        case _:
                    }
                case _:
            }
            haxe.macro.TypedExprTools.iter(e, walk);
        }
        walk(body);
        return mutates;
    }

    // Whether an expression reads storage rooted at `this`: the
    // receiver itself, or a field or array read whose subject recurses
    // back to it.
    function ownFieldRoot(e:TypedExpr):Bool {
        return switch (e.expr) {
            case TConst(TThis): true;
            case TField(subj, _): ownFieldRoot(subj);
            case TArray(subj, _): ownFieldRoot(subj);
            case TParenthesis(subj): ownFieldRoot(subj);
            case TMeta(_, subj): ownFieldRoot(subj);
            case _: false;
        };
    }

    function funcIsFallible(f:ClassFuncData):Bool {
        if (f.expr == null)
            return false;
        // The preScan fixpoint owns fallibility: direct throws, runtime-shim
        // calls, u32 length writes, and inheritance through call edges all
        // appear in the registry.
        if (state.funcErrorEnums.exists(RustEmissionState.funcKey(f.classType.module, f.field.name, f.isStatic))) {
            return true;
        }
        // Local re-check of direct fallibility on the body as emitted; the
        // registry cannot fall behind this without a compile error following.
        // Region bodies absorb the domains their clauses catch (features/06).
        var throwsOrCallsFallible = false;
        function walk(e:TypedExpr, absorbed:Array<String>) {
            function descend() {
                haxe.macro.TypedExprTools.iter(e, function(child) walk(child, absorbed));
            }
            switch (e.expr) {
                case TThrow(t):
                    switch (stripDecorations(t).expr) {
                        case TNew(c, _, args) if (args.length > 0):
                            final en = payloadEnumOfArg(args[0]);
                            if (en != null && state.exceptionPayloads.exists(c.get().module)) {
                                if (absorbed.indexOf(en.get().module) < 0) {
                                    throwsOrCallsFallible = true;
                                }
                            } else if (!state.exceptionPayloads.exists(c.get().module)) {
                                // A throw the subset cannot resolve still
                                // escapes the signature; stay fallible.
                                throwsOrCallsFallible = true;
                            }
                        case _:
                            throwsOrCallsFallible = true;
                    }
                    descend();
                case TCall(fn, callArgs):
                    switch (fn.expr) {
                        case TField(_, FInstance(cc, _, cf)) | TField(_, FStatic(cc, cf)):
                            final calleeEnum = state.funcErrorEnums.get(RustEmissionState.funcKey(cc.get().module, cf.get().name, switch (fn.expr) {
                                case TField(_, FStatic(_, _)): true;
                                case _: false;
                            }));
                            if (calleeEnum != null && absorbed.indexOf(calleeEnum.module) < 0) {
                                throwsOrCallsFallible = true;
                            }
                            if (isStringBufFaultOp(cc.get().module, cf.get().name)) {
                                // stdlib/08: the buffer checks end the owner
                                // in std.UStringFault unless a region absorbs it.
                                final payload = state.exceptionPayloads.get("std.UStringException");
                                final faultModule = payload != null ? payload : "std.UStringFault";
                                if (absorbed.indexOf(faultModule) < 0) {
                                    throwsOrCallsFallible = true;
                                }
                            }
                            if (RustEmissionState.runtimeShimIsFallible(cf.get().name)) {
                                if (!(state.errorModule != null && absorbed.indexOf(state.errorModule) >= 0)) {
                                    throwsOrCallsFallible = true;
                                }
                            }
                            if (isLengthConversion(cf.get().name, callArgs)) {
                                if (!(state.errorModule != null && absorbed.indexOf(state.errorModule) >= 0)) {
                                    throwsOrCallsFallible = true;
                                }
                            }
                        case _:
                    }
                    descend();
                case TTry(regionBody, regionCatches):
                    final caught = [for (c in regionCatches) caughtPayloadEnumModuleOf(c.v)];
                    final absorbedBody = absorbed.concat([for (m in caught) if (m != null) m]);
                    walk(regionBody, absorbedBody);
                    for (c in regionCatches) {
                        walk(c.expr, absorbed);
                    }
                case _:
                    descend();
            }
        }
        walk(f.expr, []);
        return throwsOrCallsFallible;
    }

    /**
        Recognizes writeU32(x.length): the Rust lowering narrows the count
        through u32::try_from(x)?, so the call makes its owner fallible
        regardless of the Haxe signature.
    **/
    /**
        stdlib/08: add, addChar, and toString on std.StringBuf carry the
        unpaired-surrogate check, so a call makes its owner fallible in
        std.UStringFault like a std.UString construction check.
    **/
    function isStringBufFaultOp(module:String, calleeName:String):Bool {
        if (module != "std.StringBuf" && module != "StringBuf") {
            return false;
        }
        return calleeName == "add" || calleeName == "addChar" || calleeName == "toString";
    }

    function isLengthConversion(calleeName:String, args:Array<TypedExpr>):Bool {
        if (calleeName != "writeU32" || args.length != 1) {
            return false;
        }
        return switch (stripDecorations(args[0]).expr) {
            case TField(_, fa):
                switch (fa) {
                    case FInstance(_, _, cf) | FStatic(_, cf) | FAnon(cf) | FClosure(_, cf): cf.get().name == "length";
                    case FEnum(_, ef): ef.name == "length";
                    case FDynamic(n): n == "length";
                }
            case _: false;
        }
    }

    public function testFuncDecl(cls:ClassType, f:ClassFuncData):Array<String> {
        final id = cls.module + "." + f.field.name;
        var desc:Null<String> = null;
        for (entry in f.field.meta.extract(":test")) {
            if (entry.params != null && entry.params.length > 0) {
                switch (entry.params[0].expr) {
                    case EConst(CString(s)):
                        desc = s;
                    case _:
                }
            }
        }
        final runnerName = desc != null ? id + ": " + desc : id;
        final snake = RustImports.toSnakeCase(f.field.name);
        // Tests are the error boundary: a fault inside one is a recorded
        // failure, so the body lowers as infallible and fallible callees
        // unwrap through the catch_unwind harness.
        expr.setFallible(false);
        expr.setReturnTypeName("()");
        final body = expr.functionBody(cls, f);
        final indented = body.map(l -> "    " + l);
        return [
            "#[test]",
            'fn $snake() {',
            '    testlib::run("${escapeRustString(id)}", "${escapeRustString(runnerName)}", || {',
        ].concat(indented).concat(["    });", "}"]);
    }

    static function escapeRustString(s:String):String {
        final out = new StringBuf();
        for (i in 0...s.length) {
            final c = s.charAt(i);
            if (c == '"')
                out.add('\\"');
            else if (c == "\\")
                out.add("\\\\");
            else if (c == "\n")
                out.add("\\n");
            else if (c == "\r")
                out.add("\\r");
            else if (c == "\t")
                out.add("\\t");
            else
                out.add(c);
        }
        return out.toString();
    }

    // ------------------------------------------------------------------
    // Enums
    // ------------------------------------------------------------------

    public function enumDecl(en:EnumType, options:Array<EnumOptionData>):String {
        final sorted = options.copy();
        sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
        // A payload-free enum is a plain discriminant: every value is Copy,
        // so branches and helper parameters pass it by value.
        var allPlain = true;
        for (o in sorted) {
            if (o.args.length > 0) {
                allPlain = false;
                break;
            }
        }
        final deriveAttr = allPlain ? "#[derive(Debug, Clone, Copy, PartialEq)]" : "#[derive(Debug, Clone, PartialEq)]";
        final lines = [deriveAttr, "pub enum " + en.name + " {"];
        for (o in sorted) {
            if (o.args.length == 0) {
                lines.push("    " + RustImports.toUpperCamelCase(o.name) + ",");
            } else {
                final params = [
                    for (arg in o.args)
                        RustImports.toSnakeCase(arg.name) + ": " + (EnumCycleDetector.isCyclic(en) ? types.recursiveEnumField(arg.type,
                            en) : types.of(arg.type))
                ].join(", ");
                lines.push("    " + RustImports.toUpperCamelCase(o.name) + " { " + params + " },");
            }
        }
        lines.push("}");
        if (!allPlain) {
            lines.push("");
            lines.push("impl " + en.name + " {");
            lines.push("    pub fn to_string(&self) -> String {");
            lines.push("        match self {");
            for (o in sorted) {
                final args = [for (arg in o.args) RustImports.toSnakeCase(arg.name)];
                if (args.length == 0)
                    lines.push('            ${en.name}::${RustImports.toUpperCamelCase(o.name)} => "${o.name}".to_string(),');
                else {
                    final params = [for (arg in o.args) RustImports.toSnakeCase(arg.name)];
                    final values = [for (i in 0...o.args.length) enumOperand(o.args[i].type, params[i])];
                    lines.push('            ${en.name}::${RustImports.toUpperCamelCase(o.name)} { ${params.join(", ")} } => format!("${o.name}(${[for(a in params) a + "={}"].join(", ")})", ${values.join(", ")}),');
                }
            }
            lines.push("        }");
            lines.push("    }");
            lines.push("}");
        }
        if (allPlain) {
            lines.push("");
            lines.push("impl " + en.name + " {");
            lines.push("    pub fn to_string(&self) -> String {");
            lines.push("        match self {");
            for (o in sorted)
                lines.push('            ${en.name}::${RustImports.toUpperCamelCase(o.name)} => "${o.name}".to_string(),');
            lines.push("        }");
            lines.push("    }");
            lines.push("}");
        }
        final use = EnumQueryExpander.usage(en);
        if (allPlain && use != null) {
            lines.push("");
            lines.push('impl ${en.name} {');
            if (use.collection)
                lines.push('    pub const ALL: [${en.name}; ${sorted.length}] = ['
                    + [for (o in sorted) '${en.name}::${RustImports.toUpperCamelCase(o.name)}'].join(", ") + '];');
            if (use.name) {
                lines.push("    pub fn name(&self) -> &'static str {");
                lines.push("        match self {");
                for (o in sorted)
                    lines.push('            ${en.name}::${RustImports.toUpperCamelCase(o.name)} => "${o.name}",');
                lines.push("        }");
                lines.push("    }");
            }
            if (use.lookup) {
                lines.push('    pub fn from_name(name: &str) -> Option<${en.name}> {');
                lines.push("        match name {");
                for (o in sorted)
                    lines.push('            "${o.name}" => Some(${en.name}::${RustImports.toUpperCamelCase(o.name)}),');
                lines.push("            _ => None,");
                lines.push("        }");
                lines.push("    }");
            }
            lines.push("}");
        }
        return lines.join("\n");
    }

    // ------------------------------------------------------------------
    // Typedefs (features/03)
    // ------------------------------------------------------------------

    public function typedefDecl(def:DefType):String {
        switch (def.type) {
            case TAnonymous(anonRef):
                final fields = anonRef.get().fields.copy();
                fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
                final fieldLines = [
                    for (field in fields)
                        '    pub ${RustImports.toSnakeCase(field.name)}: ${types.of(field.type)},'
                ];
                final deriveAttr = isAllCopy(fields) ? "#[derive(Debug, Clone, Copy, PartialEq)]" : "#[derive(Debug, Clone, PartialEq)]";
                final structStr = [deriveAttr, 'pub struct ${def.name} {', fieldLines.join("\n"), "}"].join("\n");

                if (isStructKeyCandidate(fields)) {
                    // The comparator matches the resident table contract,
                    // fn(&K, &K) -> i32: integer and boolean fields use the
                    // trichotomy directly, string fields reuse the resident
                    // string walk, nested structures call their comparator.
                    final fnName = "compare_" + RustImports.toSnakeCase(def.name);
                    final cmpLines = ['pub fn $fnName(a: &${def.name}, b: &${def.name}) -> i32 {'];
                    for (f in fields) {
                        final fieldSnake = RustImports.toSnakeCase(f.name);
                        switch (Context.follow(f.type)) {
                            case TAbstract(a, _) if (a.get().name == "Int" || a.get().name == "Bool"):
                                cmpLines.push('    let cmp_$fieldSnake = if a.$fieldSnake < b.$fieldSnake { -1 } else if a.$fieldSnake > b.$fieldSnake { 1 } else { 0 };');
                                cmpLines.push('    if cmp_$fieldSnake != 0 { return cmp_$fieldSnake; }');
                            case TInst(c, _) if (c.get().name == "String"):
                                state.shimsUsed.set("std.SortedMap", true);
                                imports.requireType("runtime.SortedTable", "SortedTable");
                                cmpLines.push('    let cmp_$fieldSnake = SortedTable::compare_strings(a.$fieldSnake.as_str(), b.$fieldSnake.as_str());');
                                cmpLines.push('    if cmp_$fieldSnake != 0 { return cmp_$fieldSnake; }');
                            case _:
                                switch (f.type) {
                                    case TType(innerDef, _):
                                        final innerCmp = "compare_" + RustImports.toSnakeCase(innerDef.get().name);
                                        imports.requireType(innerDef.get().module, innerCmp);
                                        cmpLines.push('    let cmp_$fieldSnake = $innerCmp(&a.$fieldSnake, &b.$fieldSnake);');
                                        cmpLines.push('    if cmp_$fieldSnake != 0 { return cmp_$fieldSnake; }');
                                    case _:
                                }
                        }
                    }
                    cmpLines.push('    0');
                    cmpLines.push("}");
                    return structStr + "\n\n" + cmpLines.join("\n");
                }

                return structStr;
            case TType(_, _):
                return 'pub type ${def.name} = ${types.of(def.type)};';
            case _:
                return null;
        }
    }

    function isAllClone(fields:Array<ClassVarData>):Bool {
        for (f in fields)
            if (!f.isStatic && !isCloneType(f.field.type))
                return false;
        return true;
    }

    function isCloneType(t:Type):Bool {
        return switch (Context.follow(t)) {
            case TAbstract(a, params): // `follow` unwraps Null<T> but keeps plain abstracts, so
                // ReadOnlyArray must recurse into its element type here.
                (["Int", "Bool", "Float"].indexOf(a.get().name) >= 0
                    && params.length == 0) || (a.get().name == "ReadOnlyArray" && params.length == 1 && isCloneType(params[0]));
            case TEnum(_):
                // Every generated enum derives Clone at its declaration
                // site, so an enum-typed field keeps its owner's derive.
                true;
            case TInst(c, params):
                final cls = c.get();
                final n = cls.name;
                if (n == "String") true else if (n == "Array") params.length == 1 && isCloneType(params[0]) else if (cls.meta.has(":dataClass"))
                    dataClassFieldsAllClone(cls, 0) else false;
            case TType(d, params): isCloneType(haxe.macro.TypeTools.applyTypeParameters(d.get().type, d.get().params, params));
            case TAnonymous(anon):
                var all = true;
                for (f in anon.get().fields)
                    if (!isCloneType(f.type))
                        all = false;
                all;
            case _: false;
        };
    }

    /**
        A nested data class keeps its owner's derive(Clone) when its own
        instance fields are Clone-capable; the depth cap keeps a cyclic
        alias chain from recursing forever.
    **/
    function dataClassFieldsAllClone(cls:ClassType, depth:Int):Bool {
        if (depth > 8)
            return false;
        // `fields` lists instance members only; statics live on `statics`.
        for (f in cls.fields.get()) {
            switch (f.kind) {
                case FMethod(_):
                    continue;
                case _:
            }
            if (!isCloneType(f.type))
                return false;
        }
        return true;
    }

    function isAllCopy(fields:Array<ClassField>):Bool {
        for (f in fields) {
            if (!isTypeCopy(f.type))
                return false;
        }
        return true;
    }

    function isTypeCopy(t:Type):Bool {
        return switch (t) {
            case TAbstract(a, _): final n = a.get().name; n == "Int" || n == "Bool" || n == "Float";
            case TType(d, _):
                switch (d.get().type) {
                    case TAnonymous(anon):
                        isAllCopy(anon.get().fields);
                    case _: false;
                }
            case TLazy(fn):
                isTypeCopy(fn());
            case _: false;
        };
    }

    function isStructKeyCandidate(fields:Array<ClassField>):Bool {
        return PolicyQueries.isStructKeyCandidate(fields);
    }

    function isFieldKeyCandidate(t:Type):Bool {
        return PolicyQueries.isFieldKeyCandidate(t);
    }
}
#end
