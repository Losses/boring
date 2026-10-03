package tscompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassFuncArg;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import ValueTypeSupport;
import PolicyQueries;
import TestApplicability;
import SourceComparisonAnalysis;
import SourceComparisonAnalysis.SourceComparisonOperation;
import SourceComparisonAnalysis.SourceRecordComparisonPlan;
import ValueTypeSupport.ValueTypeInfo;
import SourceOriginFragment;
import SourceOriginFragment.SourceOriginSpan;

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

    public function renderTestImports(testOutputDir:String, mainOutputDir:String, testRunner:String, testModules:Map<String, Bool>):String {
        return imports.renderTestImports(testOutputDir, mainOutputDir, testRunner, testModules);
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

    public function classDecl(cls:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):SourceOriginFragment {
        imports.declareLocal(cls.name);
        if (cls.isInterface) {
            final typeAliases:Array<String> = [];
            final members:Array<String> = [];
            for (f in funcFields) {
                final getterOnlyProp = interfaceGetterOnlyProperty(cls, f);
                if (getterOnlyProp != null) {
                    members.push('  readonly ${getterOnlyProp.name}: ${types.of(getterOnlyProp.type)};');
                    continue;
                }
                final capName = f.field.name.charAt(0).toUpperCase() + f.field.name.substr(1);
                final aliasName = '${cls.name}${capName}Fn';
                final args = [
                    for (a in f.args) paramText(cls, f, a)
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
            return SourceOriginFragment.plain(lines.join("\n"));
        }

        if (cls.superClass != null && exceptionDepth(cls) == 0) {
            final parent = cls.superClass.t.get();
            final parentPath = parent.pack.length == 0 ? parent.name : parent.pack.join(".") + "." + parent.name;
            Context.error("super class has no TypeScript lowering in the subset: " + parentPath, cls.pos);
        }

        final extractedFuncs = [for (f in funcFields) if (StaticFunctionMarkers.isMarked(f.field)) f];
        final ordinaryFuncs = [for (f in funcFields) if (!StaticFunctionMarkers.isMarked(f.field)) f];
        final extractedParts:Array<String> = [];
        for (f in extractedFuncs) {
            extractedParts.push(extractedFuncDecl(cls, f).join("\n"));
        }
        if (varFields.length == 0 && ordinaryFuncs.length == 0) {
            return SourceOriginFragment.plain(extractedParts.join("\n\n"));
        }

        final comparatorPlan = cls.meta.has(":dataClass") && TsType.canEmitDataClassComparator(cls) ? selectComparator(cls) : null;
        if (comparatorPlan != null) {
            imports.declareLocal("compare" + cls.name);
            prepareComparatorAliases(comparatorPlan);
        }
        // Front-load every module reference this file's declarations make
        // before any body text is emitted. The import block renders after
        // every body, so an alias decision must not depend on emission
        // order: the first emitted reference already has to see a
        // collision a later field, method signature, or method body would
        // introduce. Stored fields, method signatures, and the full typed
        // expression trees cover the references the emitters resolve
        // through imports.type and imports.value.
        // A resident module appends into the shared runtime.ts; its body
        // references resolve through runtime symbols, so the resident body
        // needs no pre-registered import line.
        if (!imports.selfResident) {
            for (v in varFields)
                registerTypeImports(v.field.type);
            for (f in funcFields) {
                registerSignatureImports(f.field.type);
                registerExprTypeImports(f.field.expr());
            }
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
        final methodSpans:Array<SourceOriginSpan> = [];
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
        final depth = exceptionDepth(cls);
        if (depth >= 2) {
            // A deeper exception subclass extends its parent class, which
            // this compilation already lowers; a cross-module parent needs
            // its import recorded exactly like an interface reference.
            final parent = cls.superClass.t.get();
            imports.type(parent.module, parent.name);
        }
        final extendsClause = depth == 1 ? " extends Error" : depth >= 2 ? " extends " + cls.superClass.t.get().name : "";
        lines.push('export class ${cls.name}$classParams' + extendsClause + ifaceStr + " {");

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
            final methodFragment = funcDecl(cls, f);
            final methodBase = SourceOriginFragment.utf16Length(lines.join("\n")) + (lines.length > 0 ? 1 : 0);
            for (span in methodFragment.spans) {
                methodSpans.push({
                    start: methodBase + span.start,
                    end: methodBase + span.end,
                    origin: span.origin,
                    unmappedReason: span.unmappedReason
                });
            }
            for (l in methodFragment.text.split("\n"))
                lines.push(l);
        }

        lines.push("}");
        final prefix = tableLines.length > 0 ? tableLines.join("\n\n") + "\n\n" : "";
        final classPart = prefix + lines.join("\n");
        final comparator = comparatorPlan == null ? "" : dataClassComparator(cls, comparatorPlan);
        final fullPart = comparator == "" ? classPart : classPart + "\n\n" + comparator;
        final leading = extractedParts.length > 0 ? extractedParts.join("\n\n") + "\n\n" : "";
        final spans = [
            for (span in methodSpans)
                {
                    start: SourceOriginFragment.utf16Length(leading) + SourceOriginFragment.utf16Length(prefix) + span.start,
                    end: SourceOriginFragment.utf16Length(leading) + SourceOriginFragment.utf16Length(prefix) + span.end,
                    origin: span.origin,
                    unmappedReason: span.unmappedReason
                }
        ];
        return new SourceOriginFragment(leading + fullPart, spans);
    }

    function selectComparator(cls:ClassType):SourceRecordComparisonPlan {
        final declaration = SourceComparisonAnalysis.declarationReference(cls);
        final analyzed = SourceComparisonAnalysis.analyzeRecord(declaration, [for (parameter in cls.params) parameter.t]);
        return switch (SourceComparisonAnalysis.comparisonPlan(analyzed, SortedKey)) {
            case ComparisonPlanReady(plan): plan;
            case ComparisonPlanFailed(path, reason, _):
                Context.error("TypeScript comparator failed at " + path + ": " + reason, cls.pos);
                null;
            case ComparisonPlanUnresolved(path, reason):
                Context.error("TypeScript comparator analysis incomplete at " + path + ": " + reason, cls.pos);
                null;
        };
    }

    /**
        Registers the module references one stored-field or signature type
        makes. The set mirrors the types TsType.of resolves through
        imports.type; everything the type mapping lowers to a plain
        language primitive or a runtime symbol is skipped, because no
        module import line exists for it to collide with.
    **/
    function registerTypeImports(t:Null<Type>):Void {
        if (t == null) return;
        switch (Context.follow(t)) {
            case TInst(c, params):
                final cls = c.get();
                if (!specialClassPath(cls.pack, cls.name) && !specialModuleImport(cls.module)) {
                    imports.observeType(cls.module, cls.name);
                    for (param in params)
                        registerTypeImports(param);
                }
            case TEnum(e, _):
                final en = e.get();
                imports.observeType(en.module, en.name);
            case TAbstract(a, params):
                final abs = a.get();
                if (ValueTypeSupport.isMarkedAbstract(abs)) {
                    imports.observeType(abs.module, abs.name);
                } else {
                    final path = PolicyQueries.pathOf(abs.pack, abs.name);
                    if (path == "Null" && params.length == 1) {
                        registerTypeImports(params[0]);
                    } else if (path == "std.ReadOnlyArray" && params.length == 1) {
                        registerTypeImports(params[0]);
                    }
                }
            case TType(d, params):
                final def = d.get();
                if (!(def.pack.length == 0 && def.name == "Map")
                    && !(def.pack.join(".") == "haxe.io" && def.name == "Bytes")
                    && !RuntimeResidents.isResident(def.module)) {
                    imports.observeType(def.module, def.name);
                }
                for (param in params)
                    registerTypeImports(param);
            case _:
        }
    }

    /** Signature shapes: argument and return types of one method. */
    function registerSignatureImports(t:Null<Type>):Void {
        if (t == null) return;
        switch (Context.follow(t)) {
            case TFun(args, ret):
                for (arg in args)
                    registerTypeImports(arg.t);
                registerTypeImports(ret);
            case _:
                registerTypeImports(t);
        }
    }

    /**
        Walks one typed expression tree and registers every type reference
        it carries. Each sub-expression names its own type, so this covers
        constructor calls, casts, enum constructions, and type expressions
        the emitters resolve through imports.value and imports.type during
        body emission.
    **/
    function registerExprTypeImports(e:Null<TypedExpr>):Void {
        if (e == null) return;
        registerTypeImports(e.t);
        switch (e.expr) {
            case TTypeExpr(t):
                switch (t) {
                    case TClassDecl(c):
                        final cls = c.get();
                        imports.observeType(cls.module, cls.name);
                    case TEnumDecl(en):
                        final enumDef = en.get();
                        imports.observeType(enumDef.module, enumDef.name);
                    case _:
                }
            case _:
        }
        TypedExprTools.iter(e, registerExprTypeImports);
    }

    /** Modules whose references lower at their call site or inline, so the
    emitted text never names the module symbol. (HostShimModules) */
    static function specialModuleImport(module:String):Bool {
        return switch (module) {
            case "std.Fs", "std.Env", "std.Process", "StringTools": true;
            case _: false;
        }
    }

    /** Class paths the type mapping lowers without a module import. */
    static function specialClassPath(pack:Array<String>, name:String):Bool {
        final path = PolicyQueries.pathOf(pack, name);
        return switch (path) {
            case "String", "std.StringBuf", "StringBuf", "Array", "haxe.Exception", "haxe.io.Bytes", "haxe.io.BytesBuffer", "std.SortedMap", "std.SortedMapBuilder",
                "std.SortedSet", "std.SortedSetBuilder":
                true;
            case _:
                false;
        };
    }

    function prepareComparatorAliases(plan:SourceRecordComparisonPlan):Void {
        final modulesByName:Map<String, Array<String>> = [];
        function collect(operation:SourceComparisonOperation):Void {
            switch (operation) {
                case RecordOrder(record, _):
                    final nested = record.source.declaration;
                    if (!modulesByName.exists(nested.name)) modulesByName.set(nested.name, []);
                    final modules = modulesByName.get(nested.name);
                    if (modules != null && modules.indexOf(nested.module) < 0) modules.push(nested.module);
                case EnumOrdinalOrder(declaration, _, _):
                    if (!modulesByName.exists(declaration.name)) modulesByName.set(declaration.name, []);
                    final modules = modulesByName.get(declaration.name);
                    if (modules != null && modules.indexOf(declaration.module) < 0) modules.push(declaration.module);
                case NullBeforePresent(child) | Lexicographic(child): collect(child);
                case _:
            }
        }
        for (field in plan.fields) collect(field.operation);
        for (name in modulesByName.keys()) {
            final modules = modulesByName.get(name);
            if (modules != null && modules.length > 1)
                for (module in modules) {
                    imports.reserveAlias(module, name);
                    imports.reserveAlias(module, "compare" + name);
                }
        }
    }

    function dataClassComparator(cls:ClassType, selected:SourceRecordComparisonPlan):String {
        final helpers:Array<String> = [];
        final lines = [
            'export function compare${cls.name}(a: ${cls.name}, b: ${cls.name}): number {',
            '  if (a === b) return 0;'
        ];
        for (entry in selected.fields)
            emitComparison(lines, helpers, entry.operation, 'a.${entry.field.name}', 'b.${entry.field.name}', cls.name + entry.field.name, 0);
        lines.push('  return 0;');
        lines.push('}');
        return helpers.concat([lines.join("\n")]).join("\n\n");
    }

    function emitComparison(lines:Array<String>, helpers:Array<String>, operation:SourceComparisonOperation, left:String, right:String, name:String,
            depth:Int):Void {
        final indent = StringTools.lpad("", " ", 2 + depth * 2);
        switch (operation) {
            case IntegerOrder:
                lines.push('${indent}if (${left} !== ${right}) return ${left} - ${right};');
            case Utf16StringOrder:
                lines.push('${indent}if (${left} !== ${right}) return ${left} < ${right} ? -1 : 1;');
            case EnumOrdinalOrder(declaration, _, constructors):
                final helper = name + "Order";
                final enumLocal = imports.typeName(declaration.module, declaration.name);
                helpers.push(enumOrderHelper(helper, enumLocal, constructors));
                lines.push('${indent}if (${helper}(${left}) !== ${helper}(${right})) return ${helper}(${left}) - ${helper}(${right});');
            case RecordOrder(record, _):
                final nested = record.source.declaration;
                final comparatorName = imports.valueName(nested.module, "compare" + nested.name);
                lines.push('${indent}{ const cmp = ${comparatorName}(${left}, ${right}); if (cmp !== 0) return cmp; }');
            case NullBeforePresent(child):
                lines.push('${indent}if (${left} === null && ${right} !== null) return -1;');
                lines.push('${indent}if (${left} !== null && ${right} === null) return 1;');
                lines.push('${indent}if (${left} !== null && ${right} !== null) {');
                emitComparison(lines, helpers, child, left, right, name, depth + 1);
                lines.push('${indent}}');
            case Lexicographic(child):
                final index = "i" + depth;
                // The bound hoists into the init section next to the counter
                // (feature 09 loop rule): the condition must evaluate as a
                // local, so each length reads once here instead of once per
                // iteration. The minimum of the two declared lengths is the
                // same iteration count the per-iteration conjunction read.
                final bound = "n" + depth;
                lines.push('${indent}for (let ${index} = 0, ${bound} = ${left}.length < ${right}.length ? ${left}.length : ${right}.length; ${index} < ${bound}; ${index}++) {');
                emitComparison(lines, helpers, child, '${left}[${index}]!', '${right}[${index}]!', name + "Element", depth + 1);
                lines.push('${indent}}');
                lines.push('${indent}if (${left}.length !== ${right}.length) return ${left}.length - ${right}.length;');
            case FloatOrder | BooleanOrder | ParameterOrder(_):
                Context.error("TypeScript sorted comparator received a non-key operation", Context.currentPos());
        }
    }

    function enumOrderHelper(name:String, enumLocal:String, constructors:Array<EnumField>):String {
        final lines = ['export function ${name}(v: ${enumLocal}): number {'];
        for (constructor in constructors)
            lines.push('  if (v.kind === "${constructor.name}") return ${constructor.index};');
        lines.push('  return 0;');
        lines.push('}');
        return lines.join("\n");
    }

    public function valueTypeDecl(cls:ClassType, info:ValueTypeInfo, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):String {
        imports.declareLocal(info.name);
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
        if (TestApplicability.isExcluded(f.field, "ts")) {
            // The test declares this target in its except argument: the
            // entry does not run the body and writes the not-applicable
            // record instead, so the id stays in the cross-target set
            // (feature spec 19).
            if (testRunner == "deno") {
                return 'Deno.test("${escapeString(runnerName)}", () =>\n  Test.recordNotApplicable("${id}", "${escapeString(runnerName)}"));';
            }
            return 'test("${escapeString(runnerName)}", () =>\n  Test.recordNotApplicable("${id}", "${escapeString(runnerName)}"));';
        }
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

    /** Hop count up the super chain to haxe.Exception; 0 when the chain does not reach it. */
    function exceptionDepth(cls:ClassType):Int {
        return PolicyQueries.exceptionDepth(cls);
    }

    /** A class whose super chain reaches haxe.Exception is one of the exception classes. */
    function isException(cls:ClassType):Bool {
        return exceptionDepth(cls) >= 1;
    }

    /** A `var x(get, never)` field renders no storage on this target (feature spec 27). */
    function isGetterOnlyProperty(field:ClassField):Bool {
        return PolicyQueries.isGetterOnlyProperty(field);
    }

    /**
        For interface declarations, a funcField named `get_x` that corresponds
        to a getter-only property `x` returns that property; the interface
        then declares `readonly x: T` and omits the `readonly get_x: Fn`
        entry.
    **/
    function interfaceGetterOnlyProperty(cls:ClassType, f:ClassFuncData):Null<{name:String, type:Type}> {
        if (f.isStatic || !StringTools.startsWith(f.field.name, "get_"))
            return null;
        final propName = f.field.name.substring("get_".length);
        for (field in cls.fields.get()) {
            if (field.name == propName && isGetterOnlyProperty(field))
                return {name: field.name, type: field.type};
        }
        return null;
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
            // @:allow members omit TypeScript visibility so they are public.
            final vis = field.isPublic ? "public" : (field.meta.has(":allow") ? "" : "private");
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
            // @:allow members omit TypeScript visibility so they are public.
            final vis = field.isPublic ? "public " : (field.meta.has(":allow") ? "" : "private ");
            return [
                "  " + vis + "static " + field.name + ": " + types.of(field.type) + " = " + expr.rawExpression(initializer) + ";"
            ];
        }
        if (v.isStatic) {
            final init = StaticFieldHelper.validatedInitializer(field, cls);
            // @:allow members omit TypeScript visibility so they are public.
            final vis = field.isPublic ? "public"
                : (field.meta.has(":allow") || Compiler.hasCrossClassPrivateAccess(cls.module, cls.name, field.name)) ? "" : "private";
            final ro = field.isFinal ? "readonly " : "";
            return [
                '  $vis static ${ro}${field.name}: ${types.of(field.type)} = ${expr.rawExpression(init)};'
            ];
        }
        // The Haxe typer places instance field defaults in the
        // constructor, so the declaration stays bare and the
        // constructor body carries the assignments.
        // @:allow members omit TypeScript visibility so they are public.
        final vis = field.isPublic ? "public"
            : (field.meta.has(":allow") || Compiler.hasCrossClassPrivateAccess(cls.module, cls.name, field.name)) ? "" : "private";
        // A `final StringBuf` is still mutable: StringBuf erases to string
        // and `.add` lowers to `+=`, which reassigns the field. Marking it
        // readonly would reject every append.
        final ro = field.isFinal && !isStringBufType(field.type) ? "readonly " : "";
        return ['  $vis ${ro}${field.name}: ${types.of(field.type)};'];
    }

    static function isStringBufType(t:Null<Type>):Bool {
        if (t == null)
            return false;
        return switch (Context.follow(t)) {
            case TInst(c, _): final cls = c.get(); (cls.pack.join(".") == "std" && cls.name == "StringBuf") || (cls.pack.length == 0 && cls.name == "StringBuf");
            case _: false;
        };
    }

    static function isFunctionType(t:Null<Type>):Bool {
        return PolicyQueries.isFunctionType(t);
    }

    /**
        The name of the StringBuf parameter a function mutates in its body,
        or null when none. The TypeScript target erases StringBuf to an
        immutable string, so a mutated StringBuf parameter must thread its
        value back through the function's return value (stdlib/08).
    **/
    static function mutatedStringBufParam(cls:ClassType, f:ClassFuncData):Null<String> {
        for (a in f.args) {
            if (isStringBufType(a.type)
                && TsStringBufParams.isMutatedStringBufParam(cls.module, cls.name, f.field.name, a.name, a.index)) {
                return a.name;
            }
        }
        return null;
    }

    /**
        Renders one function parameter. A coalescing default carries `= default`
        (optional). A plain `?param:Null<T>` with no explicit default renders
        `?` when it forms a trailing optional group; a front-optional one stays
        required because TypeScript forbids a required parameter after an
        optional one, and callers always pass it. Constant defaults
        (VEnum/VInt/VFloat) materialize at every call site and stay required.
    **/
    function paramText(cls:ClassType, f:ClassFuncData, a:ClassFuncArg, inTypeAlias = false):String {
        final coalescing = DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index);
        if (coalescing != null) {
            // Spec 51 rules 4 and 5: an omitted argument and an explicit null
            // must reach the body the same way. A JavaScript default initializer
            // runs only for an omitted argument, so the parameter keeps a null
            // default and the coalescing site stays in the body as `p ?? E`.
            return '${a.name}: ${types.of(a.type)} = null';
        }
        // A non-null default (?x:Bool = true) has Haxe type Bool, not
        // Null<Bool>, but reflaxe wraps it in Null; restore the non-null
        // type so the TS signature carries the correct non-nullable type.
        // (NonNullDefaultParamType)
        final registered = DefaultArgExpander.defaultAt(cls, f.field.name, a.index);
        final paramType = registered != null ? DefaultArgExpander.defaultParameterType(registered, a.type) : a.type;
        if (isTrailingOptional(cls, f, a.index)) {
            return '${a.name}?: ${types.of(paramType)}';
        }
        return '${a.name}: ${types.of(paramType)}';
    }

    /** Whether every parameter from `fromIndex` to the end is optional. */
    function isTrailingOptional(cls:ClassType, f:ClassFuncData, fromIndex:Int):Bool {
        for (i in fromIndex...f.args.length) {
            if (!DefaultArgExpander.isOptionalDefaultAt(cls, f.field.name, f.args[i].index)) {
                return false;
            }
        }
        return true;
    }

    /**
        A trailing optional parameter the signature renders as `name?: T | null`
        admits undefined, which Haxe never hands the body (an omitted argument
        folds to null). The body-top normalization restates that fold, so the
        strict reading sees the declared `T | null` and the body's own null
        comparisons keep narrowing. (OptionalNullableBodyNormalization)
    **/
    function optionalNullNormalizations(cls:ClassType, f:ClassFuncData, indent:String):Array<String> {
        final out:Array<String> = [];
        for (a in f.args) {
            if (DefaultArgExpander.coalescingDefaultAt(cls, f.field.name, a.index) != null)
                continue;
            if (!isTrailingOptional(cls, f, a.index))
                continue;
            if (!PolicyQueries.isNullableType(a.type))
                continue;
            out.push(indent + '${a.name} = ${a.name} ?? null;');
        }
        return out;
    }

    function funcDecl(cls:ClassType, f:ClassFuncData):SourceOriginFragment {
        final args = [
            for (a in f.args) paramText(cls, f, a)
        ].join(", ");
        // Haxe types constructors as FMethod(MethNormal) with field name
        // "new"; the name is the constructor marker.
        if (f.field.name == "new") {
            for (a in f.args) {
                expr.reserveName(a.name);
            }
            final loweredBody = expr.constructorBody(cls, cls.name, f, isException(cls));
            // A trailing optional nullable parameter arrives as undefined
            // at the strict signature; the same body-top fold as ordinary
            // methods applies. Only parameter assignments are prepended,
            // before the promoted super call, so a forwarded argument is
            // the normalized value and an inherited constructor keeps its
            // position. (OptionalNullableBodyNormalization)
            final body = optionalNullNormalizations(cls, f, "    ").concat(loweredBody);
            return SourceOriginFragment.plain(['  constructor($args) {'].concat(body).concat(["  }"]).join("\n"));
        }
        for (a in f.args) {
            expr.reserveName(a.name);
        }
        final ret = types.of(f.ret);
        final bodyPrefix = optionalNullNormalizations(cls, f, "    ");
        final bodyFragment = SourceOriginFragment.join([
            SourceOriginFragment.plain(bodyPrefix.join("\n")),
            decodeBoundaryBodyFragment(cls, f)
        ], bodyPrefix.length > 0 ? "\n" : "");
        // A function whose StringBuf parameter is mutated in the body
        // threads the mutated buffer back through the return value (the
        // TypeScript target erases StringBuf to an immutable string). The
        // signature returns the buffer and the body appends
        // `return out;`; call sites reassign the argument.
        final mutatedBufParam = mutatedStringBufParam(cls, f);
        final retText = mutatedBufParam != null ? "string" : ret;
        final completeBody = mutatedBufParam != null
            ? SourceOriginFragment.join([bodyFragment, SourceOriginFragment.plain("    return " + mutatedBufParam + ";")], bodyFragment.text.length > 0 ? "\n" : "")
            : bodyFragment;
        // @:allow members omit TypeScript visibility so they are public.
        // A private member another class in the same module accesses (Haxe
        // same-module private access) also emits public.
        final vis = f.field.isPublic ? "public"
            : (f.field.meta.has(":allow") || Compiler.hasCrossClassPrivateAccess(cls.module, cls.name, f.field.name)) ? "" : "private";
        final stat = f.isStatic ? "static " : "";
        // A method's own type parameters (the resident builders'
        // factory functions) render as method generics; the class's own
        // parameters stay in the class header only.
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
        final head = '  $vis ${stat}${f.field.name}$genericStr($args): $retText {';
        final methodParts:Array<SourceOriginFragment> = [SourceOriginFragment.plain(head)];
        if (completeBody.text.length > 0)
            methodParts.push(completeBody);
        methodParts.push(SourceOriginFragment.plain("  }"));
        return SourceOriginFragment.join(methodParts, "\n");
    }

    function extractedFuncDecl(cls:ClassType, f:ClassFuncData):Array<String> {
        for (a in f.args) {
            expr.reserveName(a.name);
        }
        final args = [
            for (a in f.args) paramText(cls, f, a)
        ].join(", ");
        final ret = types.of(f.ret);
        final methodParams = collectMethodTypeParams(cls, f);
        final genericStr = methodParams.length > 0 ? "<" + methodParams.join(", ") + ">" : "";
        final vis = f.field.isPublic ? "export " : "";
        final head = '${vis}function ${f.field.name}$genericStr($args): $ret {';
        final body = optionalNullNormalizations(cls, f, "").concat(decodeBoundaryBody(cls, f));
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
        return PolicyQueries.collectTypeParamsInto(t, skip, found);
    }

    /**
        features/18: a function returning ReadOnlyArray is a decode
        boundary; its fill stores and return value are frozen.
    **/
    function decodeBoundaryBody(cls:ClassType, f:ClassFuncData):Array<String> {
        final text = decodeBoundaryBodyFragment(cls, f).text;
        return text.length == 0 ? [] : text.split("\n");
    }

    function decodeBoundaryBodyFragment(cls:ClassType, f:ClassFuncData):SourceOriginFragment {
        final boundary = StaticFieldHelper.isReadOnlyArrayType(f.ret);
        expr.setDecodeBoundary(boundary);
        final body = expr.functionBodyFragment(cls, f);
        expr.setDecodeBoundary(false);
        return body;
    }

    // ------------------------------------------------------------------
    // Variant enums (stdlib/03)
    // ------------------------------------------------------------------

    public function enumDecl(en:EnumType, options:Array<EnumOptionData>):String {
        imports.declareLocal(en.name);
        final sorted = PolicyQueries.sortedEnumOptions(options);
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
        final valueEnum = PolicyQueries.isValueEnumOptions(sorted);
        if (valueEnum) {
            final members = [
                for (o in sorted)
                    '  ${o.name}: Object.freeze({ kind: "${o.name}" } as ${o.name})'
            ];
            blocks.push('export const ${en.name} = Object.freeze({\n' + members.join(",\n") + '\n});');
            final compareLines = [
                'export function compare${en.name}(a: ${en.name}, b: ${en.name}): number {',
                '  if (a === b) return 0;'
            ];
            for (o in sorted)
                compareLines.push('  if (a.kind === "${o.name}") return ${o.field.index} - (b.kind === "${o.name}" ? ${o.field.index} : 0);');
            compareLines.push('  return 0;');
            compareLines.push('}');
            blocks.push(compareLines.join("\n"));
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
        imports.declareLocal(def.name);
        switch (def.type) {
            case TAnonymous(anonRef):
                final fields = PolicyQueries.sortedAnonFields(anonRef);
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
                                        final innerCompare = imports.valueName(innerDef.get().module, "compare" + innerName);
                                        cmpLines.push('  const cmp_${f.name} = ' + innerCompare + '(a.${f.name}, b.${f.name});');
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
