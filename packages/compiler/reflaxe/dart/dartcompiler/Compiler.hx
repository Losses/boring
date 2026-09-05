package dartcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import haxe.macro.Type;
import PolicyQueries;
import reflaxe.BaseCompiler.BaseCompilerFileOutputType;
import reflaxe.PluginCompiler;
import reflaxe.ReflectCompiler;
import reflaxe.data.ClassFuncData;
import reflaxe.data.ClassVarData;
import reflaxe.data.EnumOptionData;
import StaticReferenceScan;

/**
    reflaxe plugin producing the Dart target of the translatable subset
    (docs/specs/stdlib/06-std-modules.md).

    Output layout is one Dart library per Haxe module at
    `lib/pack/module_name.dart`, plus `runtime.dart` (the hand-written
    prelude with the resident modules appended after it) when runtime
    symbols are referenced, and the generated test tree under `-D
    dart-test-output`: `test_host.dart` (the host entry with TestCore
    appended), `test_helper.dart` (the registered composite assertions),
    `tests/*.dart` (one library per test module), and `main.dart` (the
    runner). Every library imports what it references under the
    referenced module's file-stem prefix, so top-level names of two
    modules never collide in one file. Everything flows through the
    framework's output manager so `-D dart-output=<dir>` controls
    placement.
**/
class Compiler extends PluginCompiler<Compiler> {
    /** Module name to declaration parts, in arrival order. */
    final parts:Map<String, Array<String>> = [];

    /** Module name to emission context. */
    final contexts:Map<String, DartDecl> = [];

    /** Modules that contain @:test functions and emit to the test tree. */
    final testModules:Map<String, Bool> = [];

    /** Private static functions reached from Dart-emitted class bodies. */
    final referencedStatics:Map<String, Bool> = [];

    /** One entry per @:test function, in emission order. */
    final testEntries:Array<{
        id:String,
        runnerName:String,
        module:String,
        fn:String
    }> = [];

    var current:Null<DartDecl> = null;

    /**
        Synthetic abstract-implementation classes whose statics a generated
        reference names (`Name_Impl_.field` or the top-level lowering of its
        module). A sub-type abstract's non-inline static lowers to its
        `_Impl_`, so `compileClassImpl` must emit the referenced `_Impl_`
        even though ordinary synthetic impls never reach the output
        (features/49).
    **/
    public static final referencedImplModules:Map<String, Bool> = [];

    public static function use() {
        // Dart has one storage width for reals (double) with no binary32
        // alias in the language, so the f32 configuration has no faithful Dart
        // lowering; reject at plugin registration, before any type
        // rendering (feature spec 23).
        if (FloatPrecision.isF32()) {
            Context.error("float-precision=f32 is not available on the Dart target: double is the one real storage width; compile without the define for f64 semantics",
                Context.currentPos());
        }
        final compiler = new Compiler();
        haxe.macro.Context.onAfterTyping(ValueTypeSupport.validateModules);
        haxe.macro.Context.onAfterTyping(compiler.preScan);
        // runtime.StringTools backs the StringTools statics that have no
        // inline lowering (lpad, rpad, ltrim, rtrim, replace, ...). The
        // target rewrites those static calls into the runtime module, which
        // Haxe never types from a business reference, so force it here like
        // the Kotlin target forces runtime.TestCore. A build without a
        // runtime-import define has no way to reference the runtime package.
        if (RuntimeConfig.importName() != null) {
            Context.getType("runtime.StringTools");
        }
        ReflectCompiler.AddCompiler(compiler, {
            fileOutputType: BaseCompilerFileOutputType.Manual,
            fileOutputExtension: ".dart",
            outputDirDefineName: "dart-output",
            unwrapTypedefs: false,
            normalizeEIE: false,
            preventRepeatVars: false,
            ignoreExterns: true,
        });
    }

    public function new() {
        super();
    }

    function preScan(mtypes:Array<ModuleType>):Void {
        // Index every in-scope record typedef by shape so anonymous
        // object literals resolve their nominal class (the typer keeps
        // a literal's own type anonymous even after unification).
        for (mt in mtypes) {
            switch (mt) {
                case TTypeDecl(def):
                    final d = def.get();
                    if (!inSourceScope(d.pos)) {
                        continue;
                    }
                    switch (d.type) {
                        case TAnonymous(_): DartDecl.registerStructTypedef(def);
                        case _:
                    }
                case _:
            }
        }
        referencedStatics.clear();
        final referenced = StaticReferenceScan.scan(mtypes, cls -> !cls.isExtern
            && (RuntimeResidents.isResident(cls.module) || inSourceScope(cls.pos)));
        for (key in referenced.keys())
            referencedStatics.set(key, true);
    }

    // ------------------------------------------------------------------
    // Declarations
    // ------------------------------------------------------------------

    public function compileClassImpl(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Null<String> {
        // Resident runtime modules sit under src/runtime, outside the
        // sample source roots, but compile through this same pipeline.
        final isResident = RuntimeResidents.isResident(classType.module);
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
        if (classType.isExtern || (!isResident && !inSourceScope(classType.pos))) {
            return null;
        }
        SealedVariantHelper.validateClass(classType);
        if (isSyntheticImpl(classType.name)) {
            // A synthetic abstract-implementation class emits only when a
            // generated reference names its statics (`Name_Impl_.field`): a
            // sub-type abstract whose non-inline static another module calls
            // needs the `_Impl_` to resolve (features/49). Unreferenced
            // synthetic impls (including fully-inline integrated abstracts)
            // stay dropped.
            if (!Compiler.referencedImplModules.exists(classType.module)) {
                return null;
            }
        } else if (!classType.isInterface && isInlineOnly(classType, varFields, funcFields)) {
            return null;
        }
        StaticFunctionMarkers.validateAll(funcFields);
        funcFields = [for (f in funcFields) if (includeStaticFunc(classType, f)) f];

        var hasTestFuncs = false;
        for (f in funcFields) {
            if (f.field.meta.has(":test")) {
                hasTestFuncs = true;
                break;
            }
        }

        if (hasTestFuncs) {
            final testOutput = Context.definedValue("dart-test-output");
            if (testOutput == null) {
                Context.error("dart-test-output define is required to emit tests", classType.pos);
            }
            final testRunner = Context.definedValue("dart-test-runner");
            if (testRunner != "native") {
                Context.error("dart-test-runner define must be native for the Dart target", classType.pos);
            }

            // Validate test functions
            final sortedFuncs = funcFields.copy();
            sortedFuncs.sort((a, b) -> Reflect.compare(Context.getPosInfos(a.field.pos).min, Context.getPosInfos(b.field.pos).min));

            // Test classes carry test functions and nothing else (feature
            // spec 27); shared logic belongs in an ordinary class, whose
            // member lowering every target already renders.
            for (v in varFields) {
                Context.error("test class "
                    + classType.name
                    + " carries a non-test member "
                    + v.field.name
                    + "; shared logic belongs in an ordinary class",
                    v.field.pos);
            }

            testModules.set(classType.module, true);
            final decl = contextFor(classType.module);
            final body:Array<String> = [];

            for (f in sortedFuncs) {
                if (!f.field.meta.has(":test")) {
                    Context.error("test class " + classType.name + " carries a non-test member " + f.field.name + "; shared logic belongs in an ordinary class",
                        f.field.pos);
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

                if (body.length > 0) {
                    body.push("");
                }
                for (l in decl.testFuncDecl(classType, f)) {
                    body.push(l);
                }
                // The test module lowers to top-level functions of its own
                // library; the runner reaches them through the import
                // prefix of the module's file stem.
                testEntries.push({
                    id: id,
                    runnerName: runnerNameOf(id, f),
                    module: classType.module,
                    fn: f.field.name
                });
            }
            final result = body.join("\n");
            parts.get(classType.module).push(result);
            return result;
        }

        final decl = contextFor(classType.module);
        final result = decl.classDecl(classType, varFields, funcFields);
        if (result != null && result.length > 0) {
            parts.get(classType.module).push(result);
        }
        return result;
    }

    function includeStaticFunc(cls:ClassType, f:ClassFuncData):Bool {
        return !f.isStatic
            || f.field.isPublic
            || f.field.meta.has(":test")
            || referencedStatics.exists(cls.module + "." + f.field.name);
    }

    public function compileEnumImpl(enumType:EnumType, options:Array<EnumOptionData>):Null<String> {
        final isResident = RuntimeResidents.isResident(enumType.module);
        if (!isResident && !inSourceScope(enumType.pos)) {
            return null;
        }
        SealedVariantHelper.validateEnum(enumType);
        final decl = contextFor(enumType.module);
        final result = decl.enumDecl(enumType, options);
        if (result != null && result.length > 0) {
            parts.get(enumType.module).push(result);
        }
        return result;
    }

    public override function compileTypedef(def:DefType):Null<String> {
        final isResident = RuntimeResidents.isResident(def.module);
        if (isResident) {
            // Resident typedefs are the sorted-table comparator aliases;
            // their references expand inline at every use
            // (DartType.ofSubstituted), so no declaration renders.
            return null;
        }
        if (!inSourceScope(def.pos)) {
            return null;
        }
        SealedVariantHelper.validateTypedef(def);
        switch (def.type) {
            case TAnonymous(_):
            case _:
                return null;
        }
        final decl = contextFor(def.module);
        final result = decl.typedefDecl(def);
        if (result != null && result.length > 0) {
            parts.get(def.module).push(result);
        }
        return result;
    }

    /**
        Entry point for expressions the framework itself needs lowered
        (field initializers and the like). Everything flows through the
        same typed-AST translator as class bodies.
    **/
    public function compileExpressionImpl(e:TypedExpr, topLevel:Bool):Null<String> {
        final decl = current != null ? current : new DartDecl("eval");
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

        final dartOutput = Context.definedValue("dart-output");
        final testOutput = Context.definedValue("dart-test-output");
        final testRel = relativeFromTo(dartOutput, testOutput);

        for (module in modules) {
            if (RuntimeResidents.isResident(module)) {
                // Resident modules append into runtime.dart below, not
                // into the business tree.
                continue;
            }
            final isTest = testModules.exists(module);
            // The saved path is dart-output-root relative; the import
            // math runs on the define-based locations so the walk over
            // to the test tree counts its parent steps correctly.
            final savedPath = isTest ? testRel + "/" + DartImports.libraryPathOf(module) : "lib/" + DartImports.libraryPathOf(module);
            final filePath = isTest ? testOutput + "/" + DartImports.libraryPathOf(module) : dartOutput + "/lib/" + DartImports.libraryPathOf(module);
            final ctx = contexts.get(module);
            final body = parts.get(module).join("\n\n");
            final content = GENERATED_HEADER + "\n" + importBlockOf(ctx, filePath, dartOutput, testOutput) + "\n" + body + "\n";
            saveTreeFile(savedPath, content);
        }

        final emitDir = RuntimeConfig.emitDir();
        if (emitDir != null && anyRuntimeUsed()) {
            // Resident modules compile through the normal pipeline and
            // append after the runtime source, so runtime.dart stays one
            // self-contained library.
            final residentParts:Array<String> = [];
            for (resident in RuntimeResidents.MODULES) {
                final moduleParts = parts.get(resident);
                if (moduleParts != null && moduleParts.length > 0) {
                    residentParts.push(moduleParts.join("\n\n"));
                }
            }
            final runtimeSource = GENERATED_HEADER + "\nimport 'dart:typed_data';\n" + StringTools.trim(DartRuntime.SOURCE) + "\n"
                + residentParts.join("\n\n") + "\n";
            saveTreeFile(RuntimeConfig.emitPath(emitDir, "runtime.dart"), runtimeSource);
            if (anyRuntimeTestUsed()) {
                // The test host holds the failure type, the runner state,
                // and the stdout edge; TestCore compiles through the
                // normal pipeline and appends here. The runtime import is
                // prepended by hand because its relative path depends on
                // the two output defines.
                final testResidentParts:Array<String> = [];
                for (resident in RuntimeResidents.TEST_MODULES) {
                    final moduleParts = parts.get(resident);
                    if (moduleParts != null && moduleParts.length > 0) {
                        testResidentParts.push(moduleParts.join("\n\n"));
                    }
                }
                final hostImports = "import 'dart:io';\nimport 'dart:typed_data';\nimport '"
                    + importSpecifier(testOutput + "/test_host.dart", dartOutput + "/" + RuntimeConfig.emitPath(emitDir, "runtime.dart"))
                    + "' as runtime;";
                final hostSource = GENERATED_HEADER + "\n" + hostImports + "\n" + StringTools.trim(DartRuntime.TEST_SOURCE) + "\n"
                    + testResidentParts.join("\n\n") + "\n";
                saveTreeFile(testRel + "/test_host.dart", hostSource);
            }
        }

        if (anyPlatformHostUsed()) {
            // The synthesized platform host of stdlib/17 (std.Env writes
            // and std.Process.args on the read-only Dart VM host): one
            // small library beside the runtime, emitted only when a
            // lowered call references it.
            saveTreeFile("platform_host.dart", DartRuntime.PLATFORM_HOST_SOURCE);
        }

        if (testEntries.length > 0) {
            final withArgs = DartExpr.processArgsReferenced;
            final mainSource = DartTestHelper.testMainSource(testEntries, dartOutput, testOutput, withArgs);
            saveTreeFile(testRel + "/main.dart", mainSource);
            if (DartTestTypes.registered.length > 0) {
                final helperImports = new DartImports("test_helper");
                final helperTypes = new DartType(helperImports);
                final helperBody = DartTestHelper.testHelperSource(helperImports, helperTypes);
                final importLines:Array<String> = [];
                for (entry in helperImports.moduleList()) {
                    importLines.push("import '"
                        + importSpecifier(testOutput + "/test_helper.dart", dartOutput + "/lib/" + DartImports.libraryPathOf(entry.module))
                        + "' as "
                        + entry.prefix
                        + ";");
                }
                final helperSource = GENERATED_HEADER + "\n" + importLines.join("\n") + (importLines.length > 0 ? "\n" : "") + helperBody;
                saveTreeFile(testRel + "/test_helper.dart", helperSource);
            }
        }

        if (PackageShell.enabled()) {
            saveTreeFile("pubspec.yaml", packageManifest());
        }
        if (PackageArtifacts.enabled()) {
            PackageArtifacts.requireShell();
            PackageArtifacts.emitTarGz(dartOutput, ".tar.gz");
        }
    }

    /**
        Saves one file through the output manager and records the write
        for artifact packing (feature spec 25). Paths that escape the
        output root belong to the test tree and stay unpacked.
    **/
    function saveTreeFile(path:String, content:String):Void {
        output.saveFile(path, content);
        PackageArtifacts.record(path, content);
    }

    /**
        The package manifest of the generated tree (feature spec 24). The
        tree already sits under lib/, the layout the Dart toolchain
        requires, and every import inside it is a relative sibling path,
        so the manifest names the package and the SDK floor and declares
        no dependencies.
    **/
    function packageManifest():String {
        final license = PackageShell.license();
        final lines = [
            "# Generated by the reflaxe Dart target. Do not edit.",
            'name: ${PackageShell.name()}',
            'version: ${PackageShell.version()}',
        ];
        if (license != null) {
            lines.push('license: $license');
        }
        lines.push("environment:");
        lines.push("  sdk: ^3.0.0");
        return lines.join("\n") + "\n";
    }

    /**
        The import block of one generated library: dart:math when a
        square root lowered onto it, every referenced module's library
        under its file-stem prefix, the runtime library, and for test
        modules the host and helper entries of the test tree. `filePath`
        is the file's define-based location; every specifier walks from
        it so relative steps across the two output trees stay correct.
    **/
    function importBlockOf(ctx:DartDecl, filePath:String, dartOutput:String, testOutput:String):String {
        final lines:Array<String> = [];
        if (ctx.imports.usesTypedData()) {
            lines.push("import 'dart:typed_data';");
        }
        if (ctx.imports.usesDartMath()) {
            lines.push("import 'dart:math' as math;");
        }
        if (ctx.imports.usesDartIo()) {
            lines.push("import 'dart:io';");
        }
        if (ctx.imports.usesConvert()) {
            lines.push("import 'dart:convert';");
        }
        for (entry in ctx.imports.moduleList()) {
            lines.push("import '"
                + importSpecifier(filePath, dartOutput + "/lib/" + DartImports.libraryPathOf(entry.module))
                + "' as "
                + entry.prefix
                + ";");
        }
        for (module in ctx.imports.extensionModuleList()) {
            lines.push("import '" + importSpecifier(filePath, dartOutput + "/lib/" + DartImports.libraryPathOf(module)) + "';");
        }
        if (ctx.imports.usesPlatformHost()) {
            // The synthesized platform host of stdlib/17 sits beside the
            // runtime at the output root; every referencing file imports
            // it under the fixed prefix the lowered calls spell.
            lines.push("import '" + importSpecifier(filePath, dartOutput + "/platform_host.dart") + "' as platform_host;");
        }
        if (ctx.imports.usesRuntime()) {
            final emitDir = RuntimeConfig.emitDir();
            if (emitDir == null) {
                // Bring-your-own mode: the import specifier is the
                // configured runtime identity, verbatim.
                lines.push("import '" + RuntimeConfig.requireImportName("runtime") + "' as runtime;");
            } else {
                lines.push("import '" + importSpecifier(filePath, dartOutput + "/" + RuntimeConfig.emitPath(emitDir, "runtime.dart")) + "' as runtime;");
            }
        }
        if (ctx.imports.usesRuntimeTest()) {
            lines.push("import '" + importSpecifier(filePath, testOutput + "/test_host.dart") + "' as test_host;");
            if (DartTestTypes.registered.length > 0) {
                lines.push("import '" + importSpecifier(filePath, testOutput + "/test_helper.dart") + "' as test_helper;");
            }
        }
        return lines.join("\n");
    }

    static final GENERATED_HEADER = "// Generated by the reflaxe Dart target. Do not edit.";

    function anyRuntimeTestUsed():Bool {
        for (decl in contexts.iterator()) {
            if (decl.usesRuntimeTest()) {
                return true;
            }
        }
        return false;
    }

    function anyRuntimeUsed():Bool {
        for (decl in contexts.iterator()) {
            if (decl.usesRuntime()) {
                return true;
            }
        }
        return false;
    }

    /** Whether any generated module references the synthesized platform host. */
    function anyPlatformHostUsed():Bool {
        for (decl in contexts.iterator()) {
            if (decl.imports.usesPlatformHost()) {
                return true;
            }
        }
        return false;
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function contextFor(module:String):DartDecl {
        current = contexts.exists(module) ? contexts.get(module) : null;
        if (current == null) {
            current = new DartDecl(module);
            contexts.set(module, current);
            parts.set(module, []);
        }
        return current;
    }

    /**
        The compilation scope is the intercepted source roots: a
        declaration lowers when its position file lies under one of them,
        whatever its package. The output path mirrors the module path:
        `pack.Module` is written to `lib/pack/module.dart`.
    **/
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

    /** Haxe names synthesized abstract implementation classes `<Name>_Impl_`; they erase with the abstract. */
    function isSyntheticImpl(name:String):Bool {
        return PolicyQueries.isSyntheticImpl(name);
    }

    function isInlineOnly(classType:ClassType, varFields:Array<ClassVarData>, funcFields:Array<ClassFuncData>):Bool {
        return PolicyQueries.isInlineOnly(classType, varFields, funcFields);
    }

    /** The display name of a test: its id, plus the @:test description when one was given. */
    static function runnerNameOf(id:String, f:ClassFuncData):String {
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
        return desc != null ? id + ": " + desc : id;
    }

    /**
        The relative import specifier from one generated file to another,
        both expressed relative to the dart-output root.
    **/
    public static function importSpecifier(fromFile:String, toFile:String):String {
        final fromParts = fromFile.split("/");
        fromParts.pop();
        final toParts = toFile.split("/");
        final fileName = toParts.pop();
        var shared = 0;
        while (shared < fromParts.length && shared < toParts.length && fromParts[shared] == toParts[shared]) {
            shared += 1;
        }
        final out:Array<String> = [];
        for (_ in shared...fromParts.length) {
            out.push("..");
        }
        for (i in shared...toParts.length) {
            out.push(toParts[i]);
        }
        out.push(fileName);
        return out.join("/");
    }

    /** The path from one directory to another location, both output-root relative. */
    static function relativeFromTo(fromDir:String, toPath:String):String {
        final fromParts = fromDir == "." ? [] : fromDir.split("/");
        final toParts = toPath == "." ? [] : toPath.split("/");
        var shared = 0;
        while (shared < fromParts.length && shared < toParts.length && fromParts[shared] == toParts[shared]) {
            shared += 1;
        }
        final out:Array<String> = [];
        for (_ in shared...fromParts.length) {
            out.push("..");
        }
        for (i in shared...toParts.length) {
            out.push(toParts[i]);
        }
        return out.join("/");
    }
}
#end
