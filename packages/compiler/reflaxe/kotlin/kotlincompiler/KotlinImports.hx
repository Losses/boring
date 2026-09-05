package kotlincompiler;

#if (macro || reflaxe_runtime)
/**
    Tracks the import list of one generated Kotlin module and derives its
    package directive from the module path. Type references record the
    cross-package imports they need; references to the standard-library
    modules additionally mark those shims as used so the compiler emits
    them on demand.
**/
class KotlinImports {
    /** Modules of the standard library that lower to emitted shims. */
    static final SHIM_MODULES:Map<String, Bool> = [
        "haxe.io.FPHelper" => true,
        "haxe.io.BytesBuffer" => true,
        "std.Console" => true,
        "std.Process" => true,
        "std.SortedMap" => true,
        "std.SortedMapBuilder" => true,
        "std.SortedSet" => true,
        "std.SortedSetBuilder" => true,
        "std.UStringRT" => true,
        "std.Graphemes" => true,
    ];

    /**
        Compiled std modules whose presence generated output itself
        guarantees: the string-buffer fault checks throw
        `std.UStringException` without any consumer source naming it. A
        consumer build's source scope excludes `samples/`, so the scope
        filter alone would drop the class while the import stays; these
        modules compile past the scope filter and a build whose generated
        output never referenced them writes no file.
    **/
    static final GUARANTEED_STD_MODULES:Map<String, Bool> = [
        "std.UStringException" => true,
    ];

    /** Whether a module is a compiled std module generated output guarantees. */
    public static function isGuaranteedStdModule(module:String):Bool {
        return GUARANTEED_STD_MODULES.exists(module);
    }

    final selfPack:String;

    public final selfResident:Bool;

    final state:KotlinEmissionState;
    final imports:Map<String, Bool> = [];

    public function new(selfModule:String, state:KotlinEmissionState) {
        final segments = selfModule.split(".");
        // Resident modules compile into the configured runtime package;
        // their source-side "runtime" package never reaches the output.
        this.selfResident = RuntimeResidents.isResident(selfModule);
        // Test residents emit beside the test host entry, which lives in
        // the runtime package's test subpackage (emitShim subPackage).
        // The first extern names the package; every extern of a resident
        // shares the same runtime package.
        this.selfPack = this.selfResident ? RuntimeConfig.requireImportName("module " + RuntimeResidents.externsOf(selfModule)[0])
            + (RuntimeResidents.isTestResident(selfModule) ? ".test" : "") : segments.length <= 1 ? "" : segments.slice(0, segments.length - 1).join(".");
        this.state = state;
    }

    public function require(importPath:String):Void {
        imports.set(importPath, true);
    }

    /**
        Records a reference to a named type. Types in the same package are
        visible without an import. The standard-library modules are
        source-side identities: their runtime home is the configured
        runtime package, so they import as `<runtime-import>.<Type>` and
        mark their shims as used; the `haxe.*`/`std` namespaces never
        reach the output.
    **/
    public function requireType(module:String, name:String):Void {
        if (module == "Std" || module == "Math" || module == "String" || module == "haxe.Int64") {
            return;
        }
        if (SHIM_MODULES.exists(module)) {
            final runtimePackage = RuntimeConfig.requireImportName("module " + module);
            state.shimsUsed.set(module, true);
            require(runtimePackage + "." + name);
            return;
        }
        if (RuntimeResidents.isResident(module)) {
            // Residents live in the runtime package, test residents in
            // its test subpackage. A file already inside the target
            // package needs no import; business code reaches them
            // through externs instead.
            final targetPack = RuntimeConfig.requireImportName("module " + RuntimeResidents.externsOf(module)[0])
                + (RuntimeResidents.isTestResident(module) ? ".test" : "");
            if (targetPack != selfPack) {
                require(targetPack + "." + name);
            }
            return;
        }
        if (isGuaranteedStdModule(module)) {
            // The reference keeps the module's shims-used flag set so a
            // consumer build (whose source scope excludes `samples/`)
            // writes the compiled std file; in-scope builds emit the
            // module unconditionally like any other compiled module.
            state.shimsUsed.set(module, true);
        }
        final pack = packOf(module);
        if (pack != selfPack) {
            require(pack.length == 0 ? name : pack + "." + name);
        }
    }

    /** Records a file-scope function import when the declaration is public. */
    public function functionRef(module:String, name:String, isPublic:Bool):String {
        if (isPublic) {
            requireType(module, name);
        }
        return name;
    }

    public function render():String {
        final lines = selfPack.length == 0 ? [] : ["package " + selfPack];
        final items = [];
        for (imp in imports.keys()) {
            items.push(imp);
        }
        items.sort(Reflect.compare);
        if (items.length > 0) {
            if (lines.length > 0) {
                lines.push("");
            }
            for (imp in items) {
                lines.push("import " + imp);
            }
        }
        return lines.length > 0 ? lines.join("\n") + "\n" : "";
    }

    function packOf(module:String):String {
        final segments = module.split(".");
        return segments.length <= 1 ? "" : segments.slice(0, segments.length - 1).join(".");
    }
}
#end
