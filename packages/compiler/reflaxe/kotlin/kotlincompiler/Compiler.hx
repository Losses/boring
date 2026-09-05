package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import reflaxe.BaseCompiler.BaseCompilerFileOutputType;
import reflaxe.PluginCompiler;
import reflaxe.ReflectCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;

/**
    reflaxe plugin producing the Kotlin target of the translatable subset.

    Output layout is one file per Haxe module at the module's own path,
    plus runtime shims for the standard library on demand, all written
    through the framework's output manager so `-D kotlin-output=<dir>`
    controls placement.

    The compilation scope is the intercepted source roots: a declaration
    lowers when its position file lies under one of them, whatever its
    package.
**/
class Compiler extends PluginCompiler<Compiler> {
    /** Module path to declaration parts, in arrival order. */
    final parts:Map<String, Array<String>> = [];

    /** Module path to emission context. */
    final contexts:Map<String, KotlinDecl> = [];

    final state:KotlinEmissionState;

    var current:Null<KotlinDecl> = null;

    public static function use() {
        final compiler = new Compiler();
        haxe.macro.Context.onAfterTyping(ValueTypeSupport.validateModules);
        // Registered before the framework's own callback so the linkage
        // scan completes before any per-declaration lowering runs.
        haxe.macro.Context.onAfterTyping(compiler.preScan);
        // Emitter-synthesized references name support modules no
        // consumer source reaches: the stdlib/08 string-buffer fault
        // throws std.UStringException, the test host entry calls
        // Test.run, and non-concat float stringification routes through
        // runtime.TestCore. Typing them here keeps every build that
        // names a runtime package, including consumer builds whose
        // entry list omits them, able to emit them on demand; `keep`
        // alone cannot do this because it only protects an
        // already-typed module from DCE.
        Context.getType("std.UStringException");
        // TestCore is a resident module: compiling it derives its
        // output package from `runtime-import`, and a build without
        // that define cannot compile it. Skip the forced typing there;
        // such a build has no way to reference the runtime package.
        if (RuntimeConfig.importName() != null) {
            Context.getType("runtime.TestCore");
        }
        ReflectCompiler.AddCompiler(compiler, {
            fileOutputType: BaseCompilerFileOutputType.Manual,
            fileOutputExtension: ".kt",
            outputDirDefineName: "kotlin-output",
            unwrapTypedefs: false,
            normalizeEIE: false,
            preventRepeatVars: false,
            ignoreExterns: true,
        });
    }

    public function new() {
        super();
        state = new KotlinEmissionState();
    }

    // ------------------------------------------------------------------
    // Declarations
    // ------------------------------------------------------------------

    public function compileClassImpl(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Null<String> {
        // Resident runtime modules sit under src/runtime, outside the
        // sample source roots, but compile through this same pipeline.
        final isResident = RuntimeResidents.isResident(classType.module);
        // Guaranteed std modules compile past the scope filter so a
        // consumer build can still write them; the write step drops the
        // file when generated output never referenced the module.
        final isGuaranteedStd = KotlinImports.isGuaranteedStdModule(classType.module);
        final inScope = inSourceScope(classType.pos);
        if (isGuaranteedStd && !inScope) {
            state.outOfScopeGuaranteedStd.set(classType.module, true);
        }
        final valueType = ValueTypeSupport.infoOfClass(classType);
        if (valueType != null) {
            if (!ValueTypeSupport.isValidAbstract(valueType.abstractType)) {
                return null;
            }
            StaticFunctionMarkers.validateAll(funcFields);
            final decl = contextFor(classType.module);
            final result = decl.valueTypeDecl(classType, valueType, varFields, funcFields);
            parts.get(classType.module).push(result);
            return result;
        }
        if (classType.isExtern || (!isResident && !isGuaranteedStd && !inScope)) {
            return null;
        }
        SealedVariantHelper.validateClass(classType);
        if (isSyntheticImpl(classType.name) || (!classType.isInterface && isInlineOnly(classType, varFields, funcFields))) {
            return null;
        }
        StaticFunctionMarkers.validateAll(funcFields);

        var hasTestMethods = false;
        for (f in funcFields) {
            if (f.field.meta.has(":test")) {
                hasTestMethods = true;
                break;
            }
        }

        if (hasTestMethods) {
            final testOutput = Context.definedValue("kotlin-test-output");
            if (testOutput == null) {
                Context.error("kotlin-test-output define is required to emit tests", classType.pos);
            }

            final sortedFuncs = funcFields.copy();
            sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));

            final testFuncNames:Array<String> = [];
            for (f in sortedFuncs) {
                if (!f.field.meta.has(":test")) {
                    continue;
                }
                final id = classType.module + "." + f.field.name;
                if (!f.field.isPublic) {
                    Context.error("Test function " + id + " must be public", f.field.pos);
                }
                if (!f.isStatic) {
                    Context.error("Test function " + id + " must be static", f.field.pos);
                }
                if (f.args.length != 0) {
                    Context.error("Test function " + id + " must take no arguments and return Void", f.field.pos);
                }
                final isVoid = switch (Context.follow(f.ret)) {
                    case TAbstract(a, _): a.get().name == "Void";
                    case _: false;
                };
                if (!isVoid) {
                    Context.error("Test function " + id + " must take no arguments and return Void", f.field.pos);
                }
                testFuncNames.push(f.field.name);
            }

            state.testClasses.set(classType.module, {
                cls: classType,
                funcs: testFuncNames
            });
        }

        final decl = contextFor(classType.module);
        final result = decl.classDecl(classType, varFields, funcFields);
        if (result != null && result.length > 0) {
            parts.get(classType.module).push(result);
        }
        return result;
    }

    public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<String> {
        if (!inSourceScope(enumType.pos)) {
            return null;
        }
        SealedVariantHelper.validateEnum(enumType);
        if (state.payloadEnumOwners.exists(enumType.module)) {
            // Folded into its exception class as the sealed hierarchy.
            return null;
        }
        final decl = contextFor(enumType.module);
        final result = decl.enumDecl(enumType, options);
        if (result != null && result.length > 0) {
            parts.get(enumType.module).push(result);
        }
        return result;
    }

    public override function compileTypedef(def:DefType):Null<String> {
        if (!inSourceScope(def.pos)) {
            return null;
        }
        SealedVariantHelper.validateTypedef(def);
        final decl = contextFor(def.module);
        final result = decl.typedefDecl(def);
        if (result != null && result.length > 0) {
            parts.get(def.module).push(result);
        }
        return result;
    }

    public function compileExpressionImpl(e:TypedExpr, topLevel:Bool):Null<String> {
        final decl = current != null ? current : new KotlinDecl("eval", state);
        return topLevel ? decl.topLevelStatements(e) : decl.rawExpression(e);
    }

    // ------------------------------------------------------------------
    // Output
    // ------------------------------------------------------------------

    public override function generateFilesManually() {
        final modules = [];
        for (module in parts.keys())
            modules.push(module);
        modules.sort(Reflect.compare);

        final kotlinOutput = Context.definedValue("kotlin-output");
        final kotlinTestOutput = Context.definedValue("kotlin-test-output");

        for (module in modules) {
            if (state.payloadEnumOwners.exists(module)) {
                // The sealed fold already carries these variants.
                continue;
            }
            if (state.outOfScopeGuaranteedStd.exists(module) && !state.shimsUsed.exists(module)) {
                // A consumer build whose generated output never named
                // this guaranteed std module writes no file for it.
                continue;
            }
            if (RuntimeResidents.isResident(module)) {
                emitResidentModule(module);
                continue;
            }
            final decl = contexts.get(module);
            final imports = decl.renderImports();
            final body = parts.get(module).join("\n\n");
            final content = imports + (imports.length > 0 ? "\n" : "") + body + "\n";

            if (state.testClasses.exists(module)) {
                final testFileRel = kotlinTestOutput + "/" + modulePath(module);
                final savePath = computeRelativePath(kotlinOutput, testFileRel);
                saveTreeFile(savePath, content);
            } else {
                saveTreeFile(modulePath(module), content);
            }
        }

        emitShim("haxe.io.FPHelper", "FPHelper.kt", KotlinRuntime.FP_HELPER_SOURCE);
        emitShim("haxe.io.BytesBuffer", "BytesBuffer.kt", KotlinRuntime.BYTES_BUFFER_SOURCE);
        emitShim("std.Console", "Console.kt", KotlinRuntime.CONSOLE_SOURCE);
        emitShim("std.Process", "Process.kt", KotlinRuntime.PROCESS_SOURCE);
        emitShim(RuntimeResidents.externsOf("runtime.TestCore")[0], "test/Test.kt", KotlinRuntime.testSource(), "test");
        // std.SortedMap and std.SortedSet no longer emit shims: the
        // sorted tables compile from the runtime.SortedTable resident,
        // gated through the extern usage flags these modules still set.

        if (hasAnyKey(state.testClasses) && kotlinTestOutput != null) {
            generateTestHelper(kotlinTestOutput, kotlinOutput);
            generateTestMain(kotlinTestOutput, kotlinOutput);
            final annotContent = "package kotlin.test\n\n@Target(AnnotationTarget.FUNCTION)\nannotation class Test\n";
            final annotRel = kotlinTestOutput + "/tests/TestAnnotations.kt";
            final annotSave = computeRelativePath(kotlinOutput, annotRel);
            saveTreeFile(annotSave, annotContent);
        }

        if (PackageShell.enabled()) {
            saveTreeFile("build.gradle.kts", packageManifest());
        }
        if (PackageArtifacts.enabled()) {
            PackageArtifacts.requireShell();
            PackageArtifacts.emitMaven(kotlinOutput);
        }
    }

    /**
        Saves one file through the output manager and records the write
        for artifact packing (feature spec 25). Paths that escape the
        output root are recorded away by the filter in PackageArtifacts.
    **/
    function saveTreeFile(path:String, content:String):Void {
        output.saveFile(path, content);
        PackageArtifacts.record(path, content);
    }

    /**
        The build manifest of the generated tree (feature spec 24). A
        plain JVM module: the main source set points at the output
        directory and the stdlib arrives with the plugin. Including the
        module in a build is a settings configuration for the consumer
        side; this file compiles inside any Gradle build that includes
        it. `package-license` has no field to fill in a build script, so
        the define is not read.
    **/
    function packageManifest():String {
        return "// Generated by the reflaxe Kotlin target. Do not edit.\n"
            + "plugins {\n"
            + "    kotlin(\"jvm\") version \"2.4.10\"\n"
            + "}\n"
            + "\n"
            + "repositories {\n"
            + "    mavenCentral()\n"
            + "}\n"
            + "\n"
            + "sourceSets {\n"
            + "    main {\n"
            + "        kotlin.srcDir(\".\")\n"
            + "    }\n"
            + "}\n";
    }

    function generateTestHelper(kotlinTestOutput:String, kotlinOutput:String):Void {
        final runtimePackage = RuntimeConfig.requireImportName("TestHelper");
        // The floating-point overloads follow the module real of the
        // compilation (feature spec 23); Test.formatFloat switches with
        // the same target.
        final real = FloatPrecision.isF32() ? "Float" : "Double";
        final lines = [
            "package tests",
            "",
            "import " + runtimePackage + ".test.Test",
            "",
            "object TestHelper {",
            "    fun equalsValue(a: Boolean, b: Boolean): Boolean = a == b",
            "    fun formatValue(v: Boolean): String = if (v) \"true\" else \"false\"",
            "    fun assertEquals(expected: Boolean, actual: Boolean, message: String? = null) {",
            "        if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual))",
            "    }",
            "",
            "    fun equalsValue(a: Int, b: Int): Boolean = a == b",
            "    fun formatValue(v: Int): String = v.toString()",
            "    fun assertEquals(expected: Int, actual: Int, message: String? = null) {",
            "        if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual))",
            "    }",
            "",
            '    fun equalsValue(a: ${real}, b: ${real}): Boolean = a == b',
            '    fun formatValue(v: ${real}): String = Test.formatFloat(v)',
            '    fun assertEquals(expected: ${real}, actual: ${real}, message: String? = null) {',
            "        if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual))",
            "    }",
            "",
            "    fun equalsValue(a: String?, b: String?): Boolean = a == b",
            "    fun formatValue(v: String?): String = if (v == null) \"null\" else \"\\\"\" + Test.escapeJson(v) + \"\\\"\"",
            "    fun assertEquals(expected: String?, actual: String?, message: String? = null) {",
            "        if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual))",
            "    }",
            "",
            "    fun equalsValue(a: ByteArray, b: ByteArray): Boolean = java.util.Arrays.equals(a, b)",
            "    fun formatValue(v: ByteArray): String = Test.formatBytes(v)",
            "    fun assertEquals(expected: ByteArray, actual: ByteArray, message: String? = null) {",
            "        if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual))",
            "    }"
        ];

        final dummyDecl = new KotlinDecl("tests", state);
        final dummyImports = new KotlinImports("tests", state);
        final types = new KotlinType(dummyImports, state);

        final sortedKeys = [for (k in state.testReachableTypes.keys()) k];
        sortedKeys.sort(Reflect.compare);

        for (k in sortedKeys) {
            final t = state.testReachableTypes.get(k);
            switch (t) {
                case TInst(c, params) if (c.get().name == "Array"):
                    final elemType = params[0];
                    final elemTypeStr = qualifiedType(elemType);
                    final safeName = elemTypeStr.split(".").join("_").split("<").join("_").split(">").join("_");
                    lines.push("");
                    lines.push('    @JvmName("equalsValue_list_$safeName")');
                    lines.push('    fun equalsValue(a: List<$elemTypeStr>, b: List<$elemTypeStr>): Boolean = a.size == b.size && a.indices.all { equalsValue(a[it], b[it]) }');
                    lines.push('    @JvmName("formatValue_list_$safeName")');
                    lines.push('    fun formatValue(v: List<$elemTypeStr>): String = "[" + v.map { formatValue(it) }.joinToString(", ") + "]"');
                    lines.push('    @JvmName("assertEquals_list_$safeName")');
                    lines.push('    fun assertEquals(expected: List<$elemTypeStr>, actual: List<$elemTypeStr>, message: String? = null) { if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual)) }');
                case TAbstract(a, params) if (a.get().name == "ReadOnlyArray"
                    || (a.get().pack.join(".") == "std" && a.get().name == "ReadOnlyArray")):
                    final elemType = params[0];
                    final elemTypeStr = qualifiedType(elemType);
                    final safeName = elemTypeStr.split(".").join("_").split("<").join("_").split(">").join("_");
                    lines.push("");
                    lines.push('    @JvmName("equalsValue_list_$safeName")');
                    lines.push('    fun equalsValue(a: List<$elemTypeStr>, b: List<$elemTypeStr>): Boolean = a.size == b.size && a.indices.all { equalsValue(a[it], b[it]) }');
                    lines.push('    @JvmName("formatValue_list_$safeName")');
                    lines.push('    fun formatValue(v: List<$elemTypeStr>): String = "[" + v.map { formatValue(it) }.joinToString(", ") + "]"');
                    lines.push('    @JvmName("assertEquals_list_$safeName")');
                    lines.push('    fun assertEquals(expected: List<$elemTypeStr>, actual: List<$elemTypeStr>, message: String? = null) { if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual)) }');
                case TType(def, _):
                    final d = def.get();
                    switch (d.type) {
                        case TAnonymous(anonRef):
                            final typeName = d.pack.concat([d.name]).join(".");
                            final fields = anonRef.get().fields.copy();
                            fields.sort((x, y) -> Reflect.compare(Context.getPosInfos(x.pos).min, Context.getPosInfos(y.pos).min));
                            final eqChecks = [for (f in fields) 'equalsValue(a.${f.name}, b.${f.name})'].join(" && ");
                            final fmtFields = [for (f in fields) '"' + f.name + ': " + formatValue(v.' + f.name + ')'].join(' + ", " + ');
                            lines.push("");
                            lines.push('    fun equalsValue(a: $typeName, b: $typeName): Boolean = ' + (eqChecks.length > 0 ? eqChecks : "true"));
                            lines.push('    fun formatValue(v: $typeName): String = "{" + ' + (fmtFields.length > 0 ? fmtFields : '""') + ' + "}"');
                            lines.push('    fun assertEquals(expected: $typeName, actual: $typeName, message: String? = null) { if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual)) }');
                        case _:
                    }
                case TEnum(e, _):
                    final en = e.get();
                    final owner = state.payloadEnumOwners.get(en.module);
                    final typeName = owner != null ? en.pack.concat([owner]).join(".") : en.pack.concat([en.name]).join(".");
                    lines.push("");
                    lines.push('    fun equalsValue(a: $typeName, b: $typeName): Boolean = a == b');
                    final arms = [];
                    for (opt in en.constructs) {
                        switch (Context.follow(opt.type)) {
                            case TFun(args, _):
                                final argFmts = [for (arg in args) 'formatValue(v.' + arg.name + ')'].join(' + ", " + ');
                                arms.push('            is $typeName.${opt.name} -> "${opt.name}(" + $argFmts + ")"');
                            case _:
                                arms.push('            is $typeName.${opt.name} -> "${opt.name}"');
                        }
                    }
                    lines.push('    fun formatValue(v: $typeName): String = when(v) {\n' + arms.join("\n") + '\n    }');
                    lines.push('    fun assertEquals(expected: $typeName, actual: $typeName, message: String? = null) { if (!equalsValue(expected, actual)) Test.reportFailure(message, formatValue(expected), formatValue(actual)) }');
                case _:
            }
        }
        lines.push("}");
        lines.push("");

        final helperRel = kotlinTestOutput + "/tests/TestHelper.kt";
        final savePath = computeRelativePath(kotlinOutput, helperRel);
        saveTreeFile(savePath, lines.join("\n"));
    }

    function qualifiedType(t:Type):String {
        return switch (t) {
            case TAbstract(a, params):
                final abs = a.get();
                final path = abs.pack.concat([abs.name]).join(".");
                switch (path) {
                    case "Int": "Int";
                    case "Float": FloatPrecision.isF32() ? "Float" : "Double";
                    case "Bool": "Boolean";
                    case "std.ReadOnlyArray": "List<" + qualifiedType(params[0]) + ">";
                    case _: abs.name;
                }
            case TInst(c, params):
                final cls = c.get();
                if (cls.name == "String") "String"; else if (cls.name == "Array") "List<" + qualifiedType(params[0]) + ">"; else if (cls.name == "Bytes"
                    || (cls.pack.join(".") == "haxe.io" && cls.name == "Bytes")) "ByteArray"; else cls.pack.concat([cls.name]).join(".");
            case TType(def, params):
                final d = def.get();
                d.pack.concat([d.name]).join(".");
            case TEnum(e, params):
                final en = e.get();
                final owner = state.payloadEnumOwners.get(en.module);
                owner != null ? en.pack.concat([owner]).join(".") : en.pack.concat([en.name]).join(".");
            case _: "Unit";
        };
    }

    function generateTestMain(kotlinTestOutput:String, kotlinOutput:String):Void {
        final lines = ["fun main() {", "    var hasFailure = false"];
        var idx = 0;
        for (module in state.testClasses.keys()) {
            final data = state.testClasses.get(module);
            final varName = "t" + idx;
            final className = data.cls.pack.concat([data.cls.name]).join(".");
            lines.push('    val $varName = ${className}()');
            for (func in data.funcs) {
                lines.push('    try { $varName.$func() } catch (t: Throwable) { hasFailure = true }');
            }
            idx++;
        }
        lines.push('    if (hasFailure) {');
        lines.push('        kotlin.system.exitProcess(1)');
        lines.push('    }');
        lines.push("}");
        lines.push("");

        final mainRel = kotlinTestOutput + "/TestMain.kt";
        final savePath = computeRelativePath(kotlinOutput, mainRel);
        saveTreeFile(savePath, lines.join("\n"));
    }

    /**
        Writes a used shim into the runtime-emit directory under the
        configured runtime package. Bring-your-own mode writes nothing;
        the references already point at the consumer's package.
    **/
    function emitShim(module:String, fileName:String, source:String, subPackage:String = ""):Void {
        if (!state.shimsUsed.exists(module)) {
            return;
        }
        final dir = RuntimeConfig.emitDir();
        if (dir == null) {
            return;
        }
        final runtimePackage = RuntimeConfig.requireImportName("module " + module);
        // A subPackage writes the file in a nested package directory; the
        // test entry uses this so the general entry stays browser-loadable.
        final pkg = subPackage.length > 0 ? runtimePackage + "." + subPackage : runtimePackage;
        final path = RuntimeConfig.emitPath(dir, fileName);
        saveTreeFile(path, "package " + pkg + "\n\n" + StringTools.trim(source) + "\n");
    }

    /**
        Writes one resident runtime module (RuntimeResidents) into the
        runtime-emit directory. The module compiled through the normal
        typed pipeline like a business module; only its destination and
        package differ. Emission follows the extern's usage flag so
        unreferenced residents write nothing, matching the shims.
    **/
    function emitResidentModule(module:String):Void {
        var externUsed = false;
        for (externModule in RuntimeResidents.externsOf(module)) {
            if (state.shimsUsed.exists(externModule)) {
                externUsed = true;
                break;
            }
        }
        if (!externUsed) {
            return;
        }
        final dir = RuntimeConfig.emitDir();
        if (dir == null) {
            return;
        }
        final decl = contexts.get(module);
        final moduleParts = parts.get(module);
        if (decl == null || moduleParts == null || moduleParts.length == 0) {
            return;
        }
        final imports = decl.renderImports();
        final body = moduleParts.join("\n\n");
        final segments = module.split(".");
        // Test residents emit beside the test host entry in the test
        // subpackage; general residents emit at the runtime root.
        final leaf = segments[segments.length - 1] + ".kt";
        final fileName = RuntimeResidents.isTestResident(module) ? "test/" + leaf : leaf;
        final content = imports + (imports.length > 0 ? "\n" : "") + body + "\n";
        final path = RuntimeConfig.emitPath(dir, fileName);
        saveTreeFile(path, content);
    }

    public static function computeRelativePath(fromDir:String, toFile:String):String {
        final fromParts = fromDir.split("/").filter(p -> p.length > 0 && p != ".");
        final toParts = toFile.split("/").filter(p -> p.length > 0 && p != ".");
        var shared = 0;
        while (shared < fromParts.length && shared < toParts.length && fromParts[shared] == toParts[shared]) {
            shared += 1;
        }
        final parts:Array<String> = [];
        for (i in 0...(fromParts.length - shared)) {
            parts.push("..");
        }
        for (i in shared...toParts.length) {
            parts.push(toParts[i]);
        }
        final res = parts.join("/");
        return StringTools.startsWith(res, ".") ? res : "./" + res;
    }

    static function hasAnyKey(map:Map<String, Dynamic>):Bool {
        for (_ in map.keys()) {
            return true;
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /**
        Walks every typed module once, before per-declaration lowering,
        recording the exception-payload linkage of the sealed fold. The
        scan runs ahead of the lowering pass so the linkage is visible
        whatever order the typer hands declarations over in.
    **/
    function preScan(mtypes:Array<haxe.macro.Type.ModuleType>):Void {
        for (mt in mtypes) {
            switch (mt) {
                case TClassDecl(c):
                    final cls = c.get();
                    // Guaranteed std modules register their payload fold
                    // in consumer builds too; the throw lowering reads
                    // the linkage in `exceptionPayloads`.
                    if (cls.isExtern
                        || isSyntheticImpl(cls.name)
                        || (!inSourceScope(cls.pos) && !KotlinImports.isGuaranteedStdModule(cls.module))) {
                        continue;
                    }
                    if (KotlinDecl.isExceptionSubclass(cls)) {
                        final ctor = cls.constructor != null ? cls.constructor.get() : null;
                        if (ctor != null) {
                            switch (ctor.type) {
                                case TFun(args, _):
                                    for (a in args) {
                                        switch (a.t) {
                                            case TEnum(e, _):
                                                final payload = e.get();
                                                state.payloadEnumOwners.set(payload.module, cls.name);
                                                state.exceptionPayloads.set(cls.module, payload.module);
                                            case _:
                                        }
                                    }
                                case _:
                            }
                        }
                    }
                case TTypeDecl(def):
                    final d = def.get();
                    if (!inSourceScope(d.pos)) {
                        continue;
                    }
                    switch (d.type) {
                        case TAnonymous(anon):
                            final sig = KotlinDecl.structureSignature(anon);
                            final existing = state.structTypedefs.get(sig);
                            if (existing != null && (existing.name != d.name || existing.module != d.module)) {
                                Context.error("typedefs " + existing.name + " and " + d.name + " share one anonymous structure shape", d.pos);
                            }
                            state.structTypedefs.set(sig, {module: d.module, name: d.name});
                        case _:
                    }
                case _:
            }
        }
    }

    function contextFor(module:String):KotlinDecl {
        current = contexts.exists(module) ? contexts.get(module) : null;
        if (current == null) {
            current = new KotlinDecl(module, state);
            contexts.set(module, current);
            parts.set(module, []);
        }
        return current;
    }

    function inSourceScope(pos:haxe.macro.Expr.Position):Bool {
        final file = Context.getPosInfos(pos).file;
        for (root in Intercept.sourceRoots()) {
            final prefix = root.charAt(root.length - 1) == "/" ? root : root + "/";
            if (StringTools.startsWith(file, prefix) || StringTools.startsWith(file, "./" + prefix) || file.indexOf("/" + prefix) >= 0) {
                return true;
            }
        }
        return false;
    }

    function isSyntheticImpl(name:String):Bool {
        return StringTools.endsWith(name, "_Impl_");
    }

    function isInlineOnly(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Bool {
        if (varFields.length == 0 && funcFields.length == 0)
            return true;
        if (varFields.length == 0 && funcFields.length > 0) {
            for (f in funcFields) {
                switch (f.field.kind) {
                    case FMethod(MethInline) | FMethod(MethMacro):
                    case _:
                        return false;
                }
            }
            return true;
        }
        return false;
    }

    function modulePath(module:String):String {
        return module.split(".").join("/") + ".kt";
    }
}
#end
