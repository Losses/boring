package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import ValueTypeSupport;
import PolicyQueries;
import ValueTypeSupport.ValueTypeInfo;

/**
    Declaration lowering: classes, variant enums, and record typedefs
    (features/14). One TsDecl instance owns the per-module emission
    context (imports, types, expression state) so every declaration in
    the same Haxe module is written to one TypeScript file with one import
    block.
**/
class TsDecl {
    final imports:TsImports;
    final types:TsType;
    final expr:TsExpr;

    public function new(selfModule:String) {
        this.imports = new TsImports(selfModule);
        this.types = new TsType(imports);
        this.expr = new TsExpr(imports, types);
    }

    public function renderImports():String {
        return imports.render();
    }

    /** The top-level std.Fs helper declarations this module's calls registered. */
    public function renderFsHelpers():String {
        return imports.renderFsHelpers();
    }

    public function renderTestImports(testOutputDir:String, mainOutputDir:String, testRunner:String):String {
        return imports.renderTestImports(testOutputDir, mainOutputDir, testRunner);
    }

    /** Whether this module references any runtime-package symbol. */
    public function usesRuntime():Bool {
        return imports.usesRuntime();
    }

    /** Whether this module references any test-entry runtime symbol. */
    public function usesRuntimeTest():Bool {
        return imports.usesRuntimeTest();
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
            final typeAliases:Array<String> = [];
            final members:Array<String> = [];
            for (f in funcFields) {
                final capName = f.field.name.charAt(0).toUpperCase() + f.field.name.substr(1);
                final aliasName = '${cls.name}${capName}Fn';
                final args = [
                    for (a in f.args) {
                        final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
                        coalescing != null ? '${a.name}?: ${types.of(DefaultArgExpander.coalescingParameterType(coalescing, a.type))}' : '${a.name}: ${types.of(a.type)}';
                    }
                ].join(", ");
                final ret = types.of(f.ret);
                typeAliases.push('export type $aliasName = ($args) => $ret;');
                members.push('  readonly ${f.field.name}: $aliasName;');
            }
            final lines:Array<String> = [];
            if (typeAliases.length > 0) {
                for (t in typeAliases)
                    lines.push(t);
                lines.push("");
            }
            lines.push('export interface ${cls.name} {');
            for (m in members)
                lines.push(m);
            lines.push("}");
            return lines.join("\n");
        }

        if (cls.superClass != null) {
            final parent = cls.superClass.t.get();
            final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
            if (parentPath == "haxe.Exception") {
                // haxe.Exception lowers to the platform Error class; the
                // name property is stamped by the constructor emitter.
            } else {
                Context.error("super class has no TypeScript lowering in the subset: " + parentPath, cls.pos);
            }
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
                    tableLines.push(renderDataTable(v.field.name, elems));
                }
            }
        }

        final lines:Array<String> = [];
        // The implements clause names every interface; a cross-module
        // interface needs its import recorded here, exactly like a
        // field-type reference does. Same-module interfaces emit no import.
        final ifaces = [
            for (i in cls.interfaces) {
                final iface = i.t.get();
                imports.type(iface.module, iface.name);
                iface.name;
            }
        ];
        final ifaceStr = ifaces.length > 0 ? " implements " + ifaces.join(", ") : "";
        final classParams = cls.params.length > 0 ? "<" + [for (p in cls.params) p.name].join(", ") + ">" : "";
        lines.push('export class ${cls.name}$classParams' + (isException(cls) ? " extends Error" : "") + ifaceStr + " {");

        var storageCount = 0;
        for (v in varFields) {
            if (isGetterOnlyProperty(v.field)) {
                continue;
            }
            storageCount++;
            for (l in varDecl(cls, v))
                lines.push(l);
        }

        var sep = storageCount > 0 && ordinaryFuncs.length > 0;
        for (f in ordinaryFuncs) {
            if (sep) {
                lines.push("");
            }
            sep = true;
            for (l in accessorDeclFor(cls, f))
                lines.push(l);
            for (l in funcDecl(cls, f))
                lines.push(l);
        }

        lines.push("}");
        final prefix = tableLines.length > 0 ? tableLines.join("\n\n") + "\n\n" : "";
        final classPart = prefix + lines.join("\n");
        final comparator = cls.meta.has(":dataClass") && TsType.canEmitDataClassComparator(cls) ? dataClassComparator(cls) : "";
        final fullPart = comparator == "" ? classPart : classPart + "\n\n" + comparator;
        return extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" + fullPart : fullPart;
    }

    function dataClassComparator(cls:ClassType):String {
        final lines:Array<String> = [];
        final fields = [
            for (x in cls.fields.get())
                if (switch (x.kind) {
                        case FVar(read, write): !(read.match(AccCall) && write.match(AccNever));
                        case _: false;
                    }) x
        ];
        for (f in fields) {
            var orderType:Null<EnumType> = null;
            switch (f.type) {
                case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length == 1):
                    switch (Context.follow(params[0])) {
                        case TEnum(e, _): orderType = e.get();
                        case _:
                    }
                case _:
                    switch (Context.follow(f.type)) {
                        case TEnum(e, _): orderType = e.get();
                        case _:
                    }
            }
            if (orderType != null) {
                final en = orderType;
                lines.push('export function ${cls.name}${f.name}Order(v: ${en.name}): number {');
                for (ef in en.constructs)
                    lines.push('  if (v.kind === "${ef.name}") return ${ef.index};');
                lines.push('  return 0;');
                lines.push('}');
                lines.push("");
            }
        }
        lines.push('export function compare${cls.name}(a: ${cls.name}, b: ${cls.name}): number {');
        lines.push('  if (a === b) return 0;');
        for (f in fields) {
            switch (f.type) {
                case TAbstract(a, params) if (a.get().name == "Null" && params.length == 1):
                    lines.push('  if (a.${f.name} === null && b.${f.name} !== null) return -1;');
                    lines.push('  if (a.${f.name} !== null && b.${f.name} === null) return 1;');
                    // A string compare yields only -1 or 1; tsc reports a
                    // `!== 0` check on that union as dead, so guard on
                    // inequality like the string-field arm below.
                    switch (rawArrayElement(params[0])) {
                        case null:
                            switch (Context.follow(params[0])) {
                                case TInst(c, _) if (c.get().name == "String"):
                                    lines.push('  if (a.${f.name} !== null && b.${f.name} !== null && a.${f.name} !== b.${f.name}) return a.${f.name} < b.${f.name} ? -1 : 1;');
                                case _:
                                    lines.push('  if (a.${f.name} !== null && b.${f.name} !== null) { const cmp = '
                                        + tsCompareExpr(cls, f.name, params[0])
                                        + '; if (cmp !== 0) return cmp; }');
                            }
                        case element:
                            nullableArrayComparator(lines, cls, f.name, element);
                    }
                    continue;
                case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length == 1):
                    lines.push('  const a${f.name}Length = a.${f.name}.length; const b${f.name}Length = b.${f.name}.length;');
                    switch (Context.follow(params[0])) {
                        case TInst(c, _) if (c.get().name == "String"):
                            // The indexed reads feed `<` directly; noUncheckedIndexedAccess
                            // rejects `string | undefined` operands. The `!==` guard stays bare:
                            // both sides are undefined together only when the guard is false,
                            // so `<` is never reached with undefined.
                            lines.push('  for (let i = 0; i < a${f.name}Length && i < b${f.name}Length; i++) { if (a.${f.name}[i] !== b.${f.name}[i]) return a.${f.name}[i]! < b.${f.name}[i]! ? -1 : 1; }');
                        case _:
                            // The indexed element carries the non-null assertion: the
                            // element flows into a typed parameter (an Order function or
                            // a nested compare), which noUncheckedIndexedAccess rejects
                            // for a `T | undefined` index read.
                            lines.push('  for (let i = 0; i < a${f.name}Length && i < b${f.name}Length; i++) { const cmp = '
                                + tsCompareExpr(cls, f.name + '[i]!', params[0])
                                + '; if (cmp !== 0) return cmp; }');
                    }
                    lines.push('  if (a${f.name}Length !== b${f.name}Length) return a${f.name}Length - b${f.name}Length;');
                    continue;
                default:
            }
            switch (Context.follow(f.type)) {
                case TAbstract(a, _) if (a.get().name == "Int"):
                    lines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} - b.${f.name};');
                case TInst(c, _) if (c.get().name == "String"):
                    lines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} < b.${f.name} ? -1 : 1;');
                case TInst(c, _) if (c.get().meta.has(":dataClass")):
                    imports.value(c.get().module, "compare" + c.get().name);
                    lines.push('  { const cmp = compare${c.get().name}(a.${f.name}, b.${f.name}); if (cmp !== 0) return cmp; }');
                case TEnum(_, _):
                    lines.push('  if (${cls.name}${f.name}Order(a.${f.name}) !== ${cls.name}${f.name}Order(b.${f.name})) return ${cls.name}${f.name}Order(a.${f.name}) - ${cls.name}${f.name}Order(b.${f.name});');
                case _:
            }
        }
        lines.push('  return 0;');
        lines.push('}');
        return lines.join("\n");
    }

    function tsCompareExpr(cls:ClassType, field:String, t:Type):String {
        return switch (Context.follow(t)) {
            case TInst(c, _) if (c.get().meta.has(":dataClass")):
                imports.value(c.get().module, "compare" + c.get().name);
                'compare${c.get().name}(a.${field}, b.${field})';
            case TEnum(_,
                _): '${cls.name}${field.indexOf("[") >= 0 ? field.substr(0, field.indexOf("[")) : field}Order(a.${field}) - ${cls.name}${field.indexOf("[") >= 0 ? field.substr(0, field.indexOf("[")) : field}Order(b.${field})';
            case TInst(c, _) if (c.get().name == "String"): 'a.${field} < b.${field} ? -1 : 1';
            case _: 'a.${field} - b.${field}';
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
            case TAbstract(a, params) if (a.get().name == "ReadOnlyArray" && params.length == 1): params[0];
            case TLazy(f): rawArrayElement(f());
            case _: null;
        };
    }

    /**
        The element-wise compare lines for a nullable collection field
        inside the `!== null` guard. The semantics mirror the non-null
        ReadOnlyArray arm: compare in index order, then by length; the
        field is already narrowed to the array by the outer guard.
    **/
    function nullableArrayComparator(lines:Array<String>, cls:ClassType, field:String, element:Type):Void {
        lines.push('  if (a.${field} !== null && b.${field} !== null) { const a${field}Length = a.${field}.length; const b${field}Length = b.${field}.length;');
        switch (Context.follow(element)) {
            case TInst(c, _) if (c.get().name == "String"):
                lines.push('    for (let i = 0; i < a${field}Length && i < b${field}Length; i++) { if (a.${field}[i] !== b.${field}[i]) return a.${field}[i]! < b.${field}[i]! ? -1 : 1; }');
            case _:
                lines.push('    for (let i = 0; i < a${field}Length && i < b${field}Length; i++) { const cmp = '
                    + tsCompareExpr(cls, field + '[i]!', element)
                    + '; if (cmp !== 0) return cmp; }');
        }
        lines.push('    if (a${field}Length !== b${field}Length) return a${field}Length - b${field}Length;');
        lines.push('  }');
    }

    public function valueTypeDecl(cls:ClassType, info:ValueTypeInfo, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):String {
        final abs = info.abstractType;
        final lines:Array<String> = ["export type " + info.name + " = " + types.of(info.representation) + ";"];
        var ctor:Null<ClassFuncData> = null;
        for (f in funcFields)
            if (f.field.name == "_new")
                ctor = f;
        if (ctor != null && ValueTypeSupport.constructorThrows(abs)) {
            final arg = ValueTypeSupport.firstArgument(ctor.field);
            if (arg == null) {
                Context.error("value type constructor must take its representation", ctor.field.pos);
            }
            lines.push("");
            lines.push("export function " + ValueTypeSupport.constructorName(abs) + "(value: " + types.of(arg.type) + "): " + info.name + " {");
            for (line in expr.valueTypeConstructorBody(cls, ctor))
                lines.push(line);
            lines.push("  return value;");
            lines.push("}");
        }

        for (f in funcFields) {
            if (f.field.name == "_new" || (ValueTypeSupport.isInlineHelper(f.field) && ValueTypeSupport.operatorOf(abs, f.field) == null))
                continue;
            final receiver = ValueTypeSupport.hasReceiver(f.field);
            final args = [
                for (i in 0...f.args.length) {
                    final a = f.args[i];
                    final name = receiver && i == 0 ? "value" : a.name;
                    final type = receiver && i == 0 ? info.name : types.of(a.type);
                    name + (a.opt ? "?" : "") + ": " + type;
                }
            ].join(", ");
            final ret = types.of(f.ret);
            final vis = f.field.isPublic || ValueTypeSupport.operatorOf(abs, f.field) != null ? "export " : "";
            lines.push("");
            lines.push(vis + "function " + f.field.name + "(" + args + "): " + ret + " {");
            for (line in expr.valueTypeFunctionBody(cls, f, "value"))
                lines.push(line);
            lines.push("}");
        }

        for (v in varFields) {
            if (!v.isStatic)
                continue;
            final initializer = v.field.expr();
            if (initializer == null)
                Context.error("value type static field must have an initializer", v.field.pos);
            lines.push("");
            lines.push((v.field.isPublic ? "export " : "")
                + "const "
                + v.field.name
                + ": "
                + info.name
                + " = "
                + expr.rawExpression(initializer)
                + ";");
        }
        return lines.join("\n");
    }

    function renderDataTable(name:String, elems:Array<Int>):String {
        final formatted = [for (x in elems) (x >= 0 && x <= 9) ?Std.string(x):"0x" + StringTools.hex(x).toLowerCase()];
        final chunks:Array<String> = [];
        var i = 0;
        while (i < formatted.length) {
            final end = Std.int(Math.min(i + 8, formatted.length));
            chunks.push("  " + formatted.slice(i, end).join(", "));
            i = end;
        }
        // A resident table crosses into ReadOnlyArray parameters
        // (readonly T[] here), so it renders as a plain array; business
        // tables stay Int32Array because business code indexes them
        // directly and never passes them along.
        if (imports.selfResident) {
            return 'const $name = [\n' + chunks.join(",\n") + "\n];";
        }
        return 'const $name = new Int32Array([\n' + chunks.join(",\n") + "\n]);";
    }

    public function testFuncDecl(cls:ClassType, f:ClassFuncData, testRunner:String):String {
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
        imports.runtimeTest("Test");
        final body = expr.functionBody(cls, f);
        final indented = [for (b in body) "    " + b].join("\n");
        if (testRunner == "deno") {
            return 'Deno.test("${escapeString(runnerName)}", () =>\n  Test.run("${id}", "${escapeString(runnerName)}", () => {\n$indented\n  }));';
        } else {
            return 'test("${escapeString(runnerName)}", () =>\n  Test.run("${id}", "${escapeString(runnerName)}", () => {\n$indented\n  }));';
        }
    }

    static function escapeString(s:String):String {
        var out = new StringBuf();
        for (i in 0...s.length) {
            var c = s.charAt(i);
            if (c == '"')
                out.add('\\"');
            else if (c == '\\')
                out.add('\\\\');
            else if (c == '\n')
                out.add('\\n');
            else if (c == '\r')
                out.add('\\r');
            else if (c == '\t')
                out.add('\\t');
            else
                out.add(c);
        }
        return out.toString();
    }

    function isException(cls:ClassType):Bool {
        if (cls.superClass == null) {
            return false;
        }
        final parent = cls.superClass.t.get();
        return parent.pack.join(".") == "haxe" && parent.name == "Exception";
    }

    /** A `var x(get, never)` field renders no storage on this target (feature spec 27). */
    function isGetterOnlyProperty(field:ClassField):Bool {
        switch (field.kind) {
            case FVar(read, write):
                return read.match(AccCall) && write.match(AccNever);
            case _:
                return false;
        }
    }

    /**
        The accessor for a getter-only property renders beside its `get_x`
        function (feature spec 27); every other function renders nothing
        extra. The typer lowers property reads to `get_x()` calls, so the
        accessor serves consuming TypeScript code.
    **/
    function accessorDeclFor(cls:ClassType, f:ClassFuncData):Array<String> {
        if (f.isStatic || !StringTools.startsWith(f.field.name, "get_")) {
            return [];
        }
        final propName = f.field.name.substring("get_".length);
        for (field in cls.fields.get()) {
            if (field.name != propName || !isGetterOnlyProperty(field)) {
                continue;
            }
            final vis = field.isPublic ? "public" : "private";
            return [
                '  $vis get ${propName}(): ${types.of(field.type)} {',
                '    return this.${f.field.name}();',
                "  }"
            ];
        }
        return [];
    }

    function varDecl(cls:ClassType, v:ClassVarData):Array<String> {
        final field = v.field;
        if (v.isStatic && DataTableHelper.isDataTableField(field)) {
            return [];
        }
        if (v.isStatic && isFunctionType(field.type)) {
            final initializer = field.expr();
            if (initializer == null) {
                Context.error("static function fields require initializers", field.pos);
                return [];
            }
            final vis = field.isPublic ? "public " : "private ";
            return [
                "  " + vis + "static " + field.name + ": " + types.of(field.type) + " = " + expr.rawExpression(initializer) + ";"
            ];
        }
        if (v.isStatic) {
            final init = StaticFieldHelper.validatedInitializer(field, cls);
            final vis = field.isPublic ? "public" : "private";
            final ro = field.isFinal ? "readonly " : "";
            return [
                '  $vis static ${ro}${field.name}: ${types.of(field.type)} = ${expr.rawExpression(init)};'
            ];
        }
        if (field.meta.has(":value")) {
            Context.error("instance field default has no lowering; assign it in the constructor", field.pos);
        }
        final vis = field.isPublic ? "public" : "private";
        final ro = field.isFinal ? "readonly " : "";
        return ['  $vis ${ro}${field.name}: ${types.of(field.type)};'];
    }

    static function isFunctionType(t:Null<Type>):Bool {
        if (t == null) {
            return false;
        }
        return switch (Context.follow(t)) {
            case TFun(_, _): true;
            case _: false;
        };
    }

    function funcDecl(cls:ClassType, f:ClassFuncData):Array<String> {
        final args = [
            for (a in f.args) {
                final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
                final argType = coalescing != null ? types.of(DefaultArgExpander.coalescingParameterType(coalescing, a.type)) : types.of(a.type);
                final defaultText = coalescing != null ? " = " + expr.coalescingDefaultText(coalescing, a.type) : "";
                '${a.name}: $argType$defaultText';
            }
        ].join(", ");
        // Haxe types constructors as FMethod(MethNormal) with field name
        // "new"; the name is the constructor marker.
        if (f.field.name == "new") {
            for (a in f.args) {
                expr.reserveName(a.name);
            }
            final body = expr.constructorBody(cls, cls.name, f, isException(cls));
            return ['  constructor($args) {'].concat(body).concat(["  }"]);
        }
        for (a in f.args) {
            expr.reserveName(a.name);
        }
        final ret = types.of(f.ret);
        final body = decodeBoundaryBody(cls, f);
        final vis = f.field.isPublic ? "public" : "private";
        final stat = f.isStatic ? "static " : "";
        // A method's own type parameters (the resident builders'
        // factory functions) render as method generics; the class's own
        // parameters stay in the class header only.
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
        final head = '  $vis ${stat}${f.field.name}$genericStr($args): $ret {';
        return [head].concat(body).concat(["  }"]);
    }

    function extractedFuncDecl(cls:ClassType, f:ClassFuncData):Array<String> {
        for (a in f.args) {
            expr.reserveName(a.name);
        }
        final args = [
            for (a in f.args) {
                final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
                final argType = coalescing != null ? types.of(DefaultArgExpander.coalescingParameterType(coalescing, a.type)) : types.of(a.type);
                final defaultText = coalescing != null ? " = " + expr.coalescingDefaultText(coalescing, a.type) : "";
                '${a.name}: $argType$defaultText';
            }
        ].join(", ");
        final ret = types.of(f.ret);
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
        final vis = f.field.isPublic ? "export " : "";
        final head = '${vis}function ${f.field.name}$genericStr($args): $ret {';
        final body = decodeBoundaryBody(cls, f);
        return [head].concat(body).concat(["}"]);
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
        if (t == null) {
            return;
        }
        switch (t) {
            case TInst(c, params):
                final cls = c.get();
                if (switch (cls.kind) {
                        // Haxe 4.3 carries the parameter's constraints on
                        // the kind constructor.
                        case KTypeParameter(_): true;
                        case _: false;
                    }) {
                    if (skip.indexOf(cls.name) < 0 && found.indexOf(cls.name) < 0) {
                        found.push(cls.name);
                    }
                    }
                for (p in params)
                    collectTypeParamsInto(p, skip, found);
            case TAbstract(_, params) | TType(_, params) | TEnum(_, params):
                for (p in params)
                    collectTypeParamsInto(p, skip, found);
            case TFun(args, ret):
                for (arg in args)
                    collectTypeParamsInto(arg.t, skip, found);
                collectTypeParamsInto(ret, skip, found);
            case TLazy(fun):
                collectTypeParamsInto(fun(), skip, found);
            case _:
        }
    }

    /**
        features/18: a function returning ReadOnlyArray is a decode
        boundary; its fill stores and return value are frozen.
    **/
    function decodeBoundaryBody(cls:ClassType, f:ClassFuncData):Array<String> {
        final boundary = switch (f.ret) {
            case TAbstract(a, _): final abs = a.get(); abs.pack.join(".") == "std" && abs.name == "ReadOnlyArray";
            case _: false;
        }
        expr.setDecodeBoundary(boundary);
        final body = expr.functionBody(cls, f);
        expr.setDecodeBoundary(false);
        return body;
    }

    // ------------------------------------------------------------------
    // Variant enums (stdlib/03)
    // ------------------------------------------------------------------

    public function enumDecl(en:EnumType, options:Array<EnumOptionData>):String {
        final sorted = options.copy();
        sorted.sort((a, b) -> Reflect.compare(a.field.index, b.field.index));
        // Each variant is a named interface (the no-inline-types rule bans
        // object literals inside unions); the enum is the union of names.
        final blocks:Array<String> = [];
        final names:Array<String> = [];
        for (o in sorted) {
            names.push(o.name);
            final members = ['  readonly kind: "${o.name}"'];
            for (arg in o.args) {
                members.push('  readonly ${arg.name}: ${types.of(arg.type)}');
            }
            blocks.push('export interface ${o.name} {\n' + members.join("\n") + "\n}");
        }
        blocks.push('export type ${en.name} =\n  | ' + names.join("\n  | ") + ";");
        var valueEnum = true;
        for (o in sorted)
            if (o.args.length > 0)
                valueEnum = false;
        if (valueEnum) {
            final members = [
                for (o in sorted)
                    '  ${o.name}: Object.freeze({ kind: "${o.name}" } as ${o.name})'
            ];
            blocks.push('export const ${en.name} = Object.freeze({\n' + members.join(",\n") + '\n});');
            final use = EnumQueryExpander.usage(en);
            if (use != null && use.collection) {
                final allName = EnumQueryExpander.upperSnake(en.name) + "_ALL";
                blocks.push('export const $allName = Object.freeze([' + [for (o in sorted) '${en.name}.${o.name}'].join(", ") + ']);');
            }
            if (use != null && use.lookup) {
                final fn = EnumQueryExpander.lowerFirst(en.name) + "OfName";
                final lines = ['export function $fn(name: string): ${en.name} | null {'];
                for (o in sorted)
                    lines.push('  if (name === "${o.name}") return ${en.name}.${o.name};');
                lines.push("  return null;");
                lines.push("}");
                blocks.push(lines.join("\n"));
            }
        }
        return blocks.join("\n\n");
    }

    // ------------------------------------------------------------------
    // Record typedefs (features/14, features/18)
    // ------------------------------------------------------------------

    /**
        A named function type of a resident module lowers to a generic
        type alias beside the module's classes. The generated tree bans
        inline function types (tools/eslint no-inline-types), so the
        comparator ships as a name bound once per runtime file.
    **/
    public function functionTypeDecl(def:DefType):String {
        final paramNames = [for (p in def.params) p.name];
        final generics = paramNames.length > 0 ? "<" + paramNames.join(", ") + ">" : "";
        return "export type " + def.name + generics + " = " + types.of(def.type) + ";";
    }

    public function typedefDecl(def:DefType):String {
        switch (def.type) {
            case TAnonymous(anonRef):
                final fields = anonRef.get().fields.copy();
                fields.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.pos).min, Context.getPosInfos(b.pos).min));
                final fieldLines = [for (field in fields) '  ${field.name}: ${types.of(field.type)};'];
                final interfaceStr = ['export interface ${def.name} {', fieldLines.join("\n"), "}"].join("\n");

                if (isStructKeyCandidate(fields)) {
                    final cmpLines = [
                        'export function compare${def.name}(a: ${def.name}, b: ${def.name}): number {',
                        '  if (a === b) return 0;'
                    ];
                    for (f in fields) {
                        switch (Context.follow(f.type)) {
                            case TAbstract(a, _) if (a.get().name == "Int"):
                                cmpLines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} - b.${f.name};');
                            case TAbstract(a, _) if (a.get().name == "Bool"):
                                cmpLines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} ? 1 : -1;');
                            case TInst(c, _) if (c.get().name == "String"):
                                cmpLines.push('  if (a.${f.name} !== b.${f.name}) return a.${f.name} < b.${f.name} ? -1 : 1;');
                            case _:
                                switch (f.type) {
                                    case TType(innerDef, _):
                                        final innerName = innerDef.get().name;
                                        imports.value(innerDef.get().module, "compare" + innerName);
                                        cmpLines.push('  const cmp_${f.name} = compare${innerName}(a.${f.name}, b.${f.name});');
                                        cmpLines.push('  if (cmp_${f.name} !== 0) return cmp_${f.name};');
                                    case _:
                                }
                        }
                    }
                    cmpLines.push('  return 0;');
                    cmpLines.push('}');
                    return interfaceStr + "\n\n" + cmpLines.join("\n");
                }

                return interfaceStr;
            case _:
                Context.error("typedef alias has no lowering; name the structure instead", def.pos);
                return null;
        }
    }

    function isStructKeyCandidate(fields:Array<ClassField>):Bool {
        return PolicyQueries.isStructKeyCandidate(fields);
    }

    function isFieldKeyCandidate(t:Type):Bool {
        return PolicyQueries.isFieldKeyCandidate(t);
    }
}
#end
