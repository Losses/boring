package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
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
        return "crate::"
            + RustImports.moduleToRustPath(targetModule)
            + "::"
            + RustImports.emittedTypeName(ref.name);
    }

    /**
        Return the crate path of a non-type Rust item (a generated helper
        function or a static/const item) without registering a symbol
        reference: these are not Haxe-declared types, so checkAll() must not
        demand an emitted() definition for them (P6.5).
    **/
    public static function path(module: String, name: String): String {
        return "crate::" + RustImports.moduleToRustPath(module) + "::" + name;
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

