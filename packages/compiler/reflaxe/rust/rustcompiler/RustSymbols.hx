package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import CompilationUnits;
import EmitSink;

/**
    Identity a declared symbol by its Haxe module and raw class/enum/typedef
    name. Two payload enums (or two exception classes) can live in one Haxe
    module (PIT-281); keying by "module.name" keeps them distinct.
**/
typedef SymbolRef = {
    /** Declared Haxe module path (dot-separated). */
    var module: String;
    /** Raw Haxe-declared type name (class/enum/typedef/abstract). */
    var name: String;
};

/**
    Reference-definition resolution tracker.

    Every refer() call registers a reference record (who referred what from
    where) and returns the Rust path text.  Every emitted() call registers a
    definition (which symbol was written into the output).  checkAll() runs at
    the end of generation and fails any reference that matches no definition,
    unless -D rust_refer_ablate is active.

    Definition registration keys by declared identity
    (RustEmissionState.identityKey(module, name) == "module.name") so a payload
    enum co-emitted with its owning exception class does not collide with any
    other symbol inside the same file (PIT-281).
**/
class RustSymbols {
    /**
        Emission-state handle for payload-enum emitted-module redirection.
        Set by Compiler.preScan before lowering; null during the --macro phase
        (fixture probe) and during isolated unit tests.
    **/
    public static var state: Null<RustEmissionState> = null;

    /**
        Records collected by refer(): who referred what from where.
        Pushed in call order; checkAll() walks each record.
    **/
    static var references: Array<{ref: SymbolRef, fromModule: String}> = [];

    /**
        Module-to-module references recorded while paths are rendered.
        The file split (lib tree vs cargo integration test) reads this to
        decide which test modules another module depends on, so a helper
        type declared beside a test stays reachable from the crate that
        imports it. Never used for symbol resolution.
    **/
    static var moduleReferences: Array<{fromModule: String, targetModule: String}> = [];
    static var moduleReferenceKeys: Map<String, Bool> = [];

    /**
        Prefix markers for a path that crosses the generated crate split.
        A test-unit source renders main-unit targets with MAIN_PREFIX and
        test-unit targets with TEST_PREFIX; the writer substitutes the
        library crate name or the test-support crate name. Main-unit
        sources keep plain crate:: paths.
    **/
    public static final MAIN_PREFIX = "\u0001MAIN::";
    public static final TEST_PREFIX = "\u0001TEST::";
    public static final SUPPORT_PREFIX = "\u0001SUPPORT::";

    /**
        Test-unit modules the compiler keeps in the library crate (asset
        carriers, whose data must not be duplicated into every per-test
        support crate). They render and resolve as main-unit modules.
    **/
    public static var mainEmittedTestModules: Map<String, Bool> = [];

    /** True when the module is a test-unit module emitted outside the library. */
    static function isTestTarget(module: String): Bool {
        if (mainEmittedTestModules.exists(module))
            return false;
        if (StringTools.endsWith(module, "TestSupport"))
            return true;
        return CompilationUnits.isTestModule(module);
    }

    /** True when the module is emitted into a test crate. */
    static function isTestSource(module: String): Bool {
        if (mainEmittedTestModules.exists(module))
            return false;
        if (module == "tests")
            return true;
        if (StringTools.endsWith(module, "TestSupport"))
            return true;
        return CompilationUnits.isTestModule(module);
    }

    /** Clears the per-compilation reference state. */
    public static function resetReferences(): Void {
        references = [];
        moduleReferences = [];
        moduleReferenceKeys = [];
    }

    /** Records that fromModule's rendered source names targetModule. */
    public static function recordModuleReference(fromModule: String, targetModule: String): Void {
        if (fromModule == null || targetModule == null || fromModule == targetModule)
            return;
        final key = fromModule + "|" + targetModule;
        if (moduleReferenceKeys.exists(key))
            return;
        moduleReferenceKeys.set(key, true);
        moduleReferences.push({fromModule: fromModule, targetModule: targetModule});
    }

    /** The recorded module-to-module references, for the file split. */
    public static function recordedModuleReferences(): Array<{fromModule: String, targetModule: String}> {
        return moduleReferences.copy();
    }

    /**
        Definitions collected by emitted(), keyed by
        RustEmissionState.identityKey(module, name).
    **/
    static var definitions: Map<String, SymbolRef> = [];

    /**
        Register a reference and return the crate-qualified Rust path.

        @param ref      Declared symbol identity (module and raw name).
        @param fromModule  The module dispatch site that requests the path
                           (for error messages, not the path itself).
        @return crate::<moduleToRustPath>::<emittedTypeName(name)> with
                payload-enum actual-emitted-module redirection when state is
                set (P6.5).
    **/
    public static function refer(ref: SymbolRef, fromModule: String): String {
        references.push({ref: ref, fromModule: fromModule});
        final key = RustEmissionState.identityKey(ref.module, ref.name);
        EmitSink.recordRefer(key, fromModule, () -> definitions.exists(key));
        final targetModule = (state != null
            && state.payloadEnumModules.exists(RustEmissionState.identityKey(ref.module, ref.name)))
            ? state.payloadEnumModules.get(RustEmissionState.identityKey(ref.module, ref.name))
            : ref.module;
        // A symbol declared in the same module renders unqualified: an
        // integration test source is its own crate root, so a self path
        // written as crate::<module> names nothing there.
        if (targetModule == fromModule)
            return RustImports.emittedTypeName(ref.name);
        final prefix = isTestSource(fromModule)
            ? (isTestTarget(targetModule)
                ? (state != null && state.testModules.exists(fromModule) ? SUPPORT_PREFIX : TEST_PREFIX)
                : MAIN_PREFIX)
            : "crate::";
        return prefix
            + RustImports.moduleToRustPath(targetModule)
            + "::"
            + RustImports.emittedTypeName(ref.name);
    }

    /**
        Return the crate path of a non-type Rust item (a generated helper
        function or a static/const item) without registering a symbol
        reference: these are not Haxe-declared types, so checkAll() must not
        demand an emitted() definition for them (P6.5).

        fromModule is the module whose source is being rendered. It lets a
        same-module item stay unqualified (the integration-test crate root
        has no crate::<module> path) and records the module-to-module edge
        the file split needs.
    **/
    public static function path(module: String, name: String, ?fromModule: String): String {
        if (fromModule != null) {
            if (module == fromModule)
                return name;
            recordModuleReference(fromModule, module);
            final prefix = isTestSource(fromModule)
                ? (isTestTarget(module)
                    ? (state != null && state.testModules.exists(fromModule) ? SUPPORT_PREFIX : TEST_PREFIX)
                    : MAIN_PREFIX)
                : "crate::";
            return prefix + RustImports.moduleToRustPath(module) + "::" + name;
        }
        return "crate::" + RustImports.moduleToRustPath(module) + "::" + name;
    }

    /**
        The path of a raw type name (a synthetic fault union member), with
        the same same-module rule as path(). The raw name is used because
        the caller already holds the emitted declaration name.
    **/
    public static function typePath(module: String, name: String, fromModule: String): String {
        if (module == fromModule)
            return name;
        recordModuleReference(fromModule, module);
        final prefix = isTestSource(fromModule)
            ? (isTestTarget(module) ? TEST_PREFIX : MAIN_PREFIX)
            : "crate::";
        return prefix + RustImports.moduleToRustPath(module) + "::" + name;
    }

    /**
        Register a definition that has been emitted into the output.

        Called once per emitted symbol at its lowering site (per-symbol identity
        satisfies PIT-281; a file-level hook would lose the distinction between
        co-emitted symbols sharing one file).
    **/
    public static function emitted(ref: SymbolRef): Void {
        definitions.set(RustEmissionState.identityKey(ref.module, ref.name), ref);
    }

    /**
        Macro entry point for the self-test fixture
        (tests/haxe/rust-refer-unresolved).  Inserts exactly one reference to a
        known-nonexistent symbol so checkAll() produces "unresolved symbol" at
        generation end.
    **/
    @:keep
    public static function probeRefer(): Void {
        final ghost: SymbolRef = {module: "test.phantom.Ghost", name: "DoesNotExist"};
        refer(ghost, "test.probe");
    }

    /**
        Verify every reference matches a registered definition.

        Skipped when -D rust_refer_ablate is defined.  Errors via Context.error
        so a mismatch yields a nonzero exit code and halts generation.
    **/
    public static function checkAll(): Void {
        if (Context.defined("rust_refer_ablate")) {
            return;
        }
        for (rec in references) {
            final key = RustEmissionState.identityKey(rec.ref.module, rec.ref.name);
            if (!definitions.exists(key)) {
                Context.error(
                    'unresolved symbol: ${rec.ref.module}.${rec.ref.name}'
                    + ' (referred from ${rec.fromModule})',
                    Context.currentPos()
                );
            }
        }
    }
}
#end

