package swiftcompiler;

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
    reflaxe plugin producing the Swift target of the translatable subset
    (docs/specs/features/07-numeric-tower.md).

    Output layout is one Swift file per Haxe module at the module's own
    path, all inside one Swift module, plus `Runtime.swift` (the
    hand-written prelude with the resident modules appended after it)
    when runtime symbols are referenced, `Test.swift` for the test host,
    and the generated test tree under `-D swift-test-output`. Everything
    flows through the framework's output manager so `-D
    swift-output=<dir>` controls placement.
**/
class Compiler extends PluginCompiler<Compiler> {
    /** Module name to declaration parts, in arrival order. */
    final parts:Map<String, Array<String>> = [];

    /** Module name to emission context. */
    final contexts:Map<String, SwiftDecl> = [];

    /** Modules that contain @:test functions and emit to the test tree. */
    final testModules:Map<String, Bool> = [];

    /** One entry per @:test function, in emission order. */
    final testEntries:Array<{id:String, runnerName:String, call:String}> = [];

    var current:Null<SwiftDecl> = null;

    public static function use() {
        final compiler = new Compiler();
        haxe.macro.Context.onAfterTyping(ValueTypeSupport.validateModules);
        // The throw set settles before the first declaration renders:
        // Swift signatures carry `throws`, so emission needs every
        // function's fallibility up front.
        haxe.macro.Context.onAfterTyping(compiler.preScan);
        ReflectCompiler.AddCompiler(compiler, {
            fileOutputType: BaseCompilerFileOutputType.Manual,
            fileOutputExtension: ".swift",
            outputDirDefineName: "swift-output",
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
        SwiftFallibility.collect(mtypes);
        SwiftInoutParams.collect(mtypes);
        // Index every in-scope record typedef by shape so anonymous
        // object literals resolve their nominal struct (the typer keeps
        // a literal's own type anonymous even after unification).
        for (mt in mtypes) {
            switch (mt) {
                case TTypeDecl(def):
                    final d = def.get();
                    if (!inSourceScope(d.pos)) {
                        continue;
                    }
                    switch (d.type) {
                        case TAnonymous(_): SwiftDecl.registerStructTypedef(def);
                        case _:
                    }
                case _:
            }
        }
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
        if (isSyntheticImpl(classType.name) || (!classType.isInterface && isInlineOnly(classType, varFields, funcFields))) {
            return null;
        }
        StaticFunctionMarkers.validateAll(funcFields);

        var hasTestFuncs = false;
        for (f in funcFields) {
            if (f.field.meta.has(":test")) {
                hasTestFuncs = true;
                break;
            }
        }

        if (hasTestFuncs) {
            final testOutput = Context.definedValue("swift-test-output");
            if (testOutput == null) {
                Context.error("swift-test-output define is required to emit tests", classType.pos);
            }
            final testRunner = Context.definedValue("swift-test-runner");
            if (testRunner != "native") {
                Context.error("swift-test-runner define must be native for the Swift target", classType.pos);
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
                testEntries.push({id: id, runnerName: runnerNameOf(id, f), call: classType.name + "." + f.field.name});
            }
            // The test namespace mirrors the statics-only business
            // lowering: a case-less enum carrying the throwing functions.
            final lines = ["enum " + classType.name + " {"].concat(body).concat(["}"]);
            final result = lines.join("\n");
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
            // (SwiftType.ofSubstituted), so no declaration renders.
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
        final decl = current != null ? current : new SwiftDecl("eval");
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

        final swiftOutput = Context.definedValue("swift-output");
        final testOutput = Context.definedValue("swift-test-output");

        for (module in modules) {
            if (RuntimeResidents.isResident(module)) {
                // Resident modules append into Runtime.swift below,
                // not into the business tree.
                continue;
            }
            final body = parts.get(module).join("\n\n");
            final content = fileContent(module, body);
            if (testModules.exists(module)) {
                final testFileRel = relativeFromTo(swiftOutput, testOutput) + "/" + modulePath(module);
                saveTreeFile(testFileRel, content);
            } else {
                saveTreeFile(modulePath(module), content);
            }
        }

        final emitDir = RuntimeConfig.emitDir();
        if (emitDir != null && anyRuntimeUsed()) {
            // Resident modules compile through the normal pipeline and
            // append after the runtime source, so Runtime.swift stays one
            // self-contained file.
            final residentParts:Array<String> = [];
            for (resident in RuntimeResidents.MODULES) {
                final moduleParts = parts.get(resident);
                if (moduleParts != null && moduleParts.length > 0) {
                    residentParts.push(moduleParts.join("\n\n"));
                }
            }
            saveTreeFile(RuntimeConfig.emitPath(emitDir, "Runtime.swift"), StringTools.trim(SwiftRuntime.SOURCE)
                + "\n"
                + residentParts.join("\n\n")
                + "\n");
            if (anyRuntimeTestUsed()) {
                // The test host holds the failure type, the runner state,
                // and the stdout edge; TestCore compiles through the
                // normal pipeline and appends here.
                final testResidentParts:Array<String> = [];
                for (resident in RuntimeResidents.TEST_MODULES) {
                    final moduleParts = parts.get(resident);
                    if (moduleParts != null && moduleParts.length > 0) {
                        testResidentParts.push(moduleParts.join("\n\n"));
                    }
                }
                saveTreeFile(RuntimeConfig.emitPath(emitDir, "Test.swift"),
                    StringTools.trim(SwiftRuntime.TEST_SOURCE)
                    + "\n"
                    + testResidentParts.join("\n\n")
                    + "\n");
            }
        }

        if (testEntries.length > 0) {
            final testRoot = relativeFromTo(swiftOutput, testOutput);
            saveTreeFile(testRoot + "/TestMain.swift", testImportPrefix() + SwiftTestHelper.testMainSource(testEntries));
            if (SwiftTestTypes.registered.length > 0) {
                saveTreeFile(testRoot + "/TestHelper.swift", testImportPrefix() + SwiftTestHelper.testHelperSource());
            }
        }

        if (PackageShell.enabled()) {
            saveTreeFile("Package.swift", packageManifest());
        }
        if (PackageArtifacts.enabled()) {
            PackageArtifacts.requireShell();
            PackageArtifacts.emitZip(swiftOutput);
        }
    }

    /** The import header of the generated test-tree entry files. */
    function testImportPrefix():String {
        final testImport = Context.definedValue("swift-test-import");
        return testImport == null ? "" : "import " + testImport + "\n\n";
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
        The package manifest of the generated tree (feature spec 24). One
        target covers the output directory; the sources list names the
        emitted top-level entries (resident modules live inside
        Runtime.swift, test modules in the test tree, so both are absent)
        and tracks the tree by construction.
    **/
    function packageManifest():String {
        final entries:Map<String, Bool> = [];
        for (module in parts.keys()) {
            if (RuntimeResidents.isResident(module) || testModules.exists(module)) {
                continue;
            }
            entries.set(module.split(".")[0], true);
        }
        final emitDir = RuntimeConfig.emitDir();
        if (emitDir != null && anyRuntimeUsed()) {
            entries.set(RuntimeConfig.emitPath(emitDir, "Runtime.swift").split("/")[0], true);
        }
        final names = [for (name in entries.keys()) name];
        names.sort(Reflect.compare);
        final lines = [
            "// Generated by the reflaxe Swift target. Do not edit.",
            "// swift-tools-version:5.9",
            "import PackageDescription",
            "",
            "let package = Package(",
            '    name: "${PackageShell.name()}",',
            "    targets: [",
            "        .target(",
            '            name: "${PackageShell.name()}",',
            '            path: ".",',
            "            sources: ["
        ];
        for (name in names) {
            lines.push('                "$name",');
        }
        lines.push("            ]");
        lines.push("        )");
        lines.push("    ]");
        lines.push(")");
        return lines.join("\n") + "\n";
    }

    /**
        One generated file: the import header, the generated-file note,
        the stdlib/17 host-edge helpers the module references, and the
        module body. The host modules import behind canImport guards so
        the file compiles on every Swift platform; SystemPackage enters
        only when a std.Fs helper of the module needs it (spec stdlib/17,
        build-chain migration rule 3).
    **/
    function fileContent(module:String, body:String):String {
        final decl:SwiftDecl = cast contexts.get(module);
        final header:Array<String> = [];
        // The SwiftPM test tree is its own executable target beside the
        // generated-code target (stdlib/17 build-chain migration); every
        // test file imports that module under the name a compile-time
        // define states.
        final testImport = Context.definedValue("swift-test-import");
        if (testModules.exists(module) && testImport != null) {
            header.push("import " + testImport);
        }
        if (decl.usesFoundation()) {
            header.push("import Foundation");
        }
        final hostKeys = decl.hostEdgeKeys();
        var needsFoundationEssentials = false;
        var needsSystemPackage = false;
        for (key in hostKeys) {
            if (SwiftHostEdges.needsFoundationEssentials(key)) {
                needsFoundationEssentials = true;
            }
            if (SwiftHostEdges.needsSystemPackage(key)) {
                needsSystemPackage = true;
            }
        }
        if (needsFoundationEssentials) {
            header.push("#if canImport(FoundationEssentials)");
            header.push("import FoundationEssentials");
            header.push("#endif");
        }
        if (hostKeys.length > 0) {
            header.push("#if canImport(Glibc)");
            header.push("import Glibc");
            header.push("#endif");
            header.push("#if canImport(Darwin)");
            header.push("import Darwin");
            header.push("#endif");
            header.push("#if canImport(MSVCRT)");
            header.push("import MSVCRT");
            header.push("#endif");
            header.push("#if canImport(WinSDK)");
            header.push("import WinSDK");
            header.push("#endif");
        }
        if (needsSystemPackage) {
            header.push("import SystemPackage");
        }
        final helpers:Array<String> = [];
        for (key in SwiftHostEdges.KEYS) {
            if (decl.hostEdgeKeys().indexOf(key) >= 0) {
                helpers.push(SwiftHostEdges.source(key));
            }
        }
        final content:Array<String> = [];
        if (header.length > 0) {
            content.push(header.join("\n"));
        }
        content.push(GENERATED_HEADER);
        for (h in helpers) {
            content.push(StringTools.trim(h));
        }
        content.push(body);
        return content.join("\n\n") + "\n";
    }

    static final GENERATED_HEADER = "// Generated by the reflaxe Swift target. Do not edit.";

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

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function contextFor(module:String):SwiftDecl {
        current = contexts.exists(module) ? contexts.get(module) : null;
        if (current == null) {
            current = new SwiftDecl(module);
            contexts.set(module, current);
            parts.set(module, []);
        }
        return current;
    }

    /**
        The compilation scope is the intercepted source roots: a
        declaration lowers when its position file lies under one of them,
        whatever its package. The output path mirrors the module path:
        `pack.Module` is written to `pack/Module.swift`.
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

    function modulePath(module:String):String {
        return module.split(".").join("/") + ".swift";
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
