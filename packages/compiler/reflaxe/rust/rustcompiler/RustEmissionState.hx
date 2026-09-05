package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
    Emission state shared across modules for the Rust target.
**/
class RustEmissionState {
    /** Maps payload enum module path to its owning exception class name. */
    public final payloadEnumOwners:Map<String, String> = [];

    /**
        Set while emitting one instance member, true when that member's
        body formats a class type parameter for printing. RustDecl resets
        this before each member and routes a member that set it into the
        impl block whose parameters also carry the Debug bound.
    **/
    public var memberPrintsTypeParam:Bool = false;

    /** Maps payload enum module path to its owning exception class module path. */
    public final payloadEnumModules:Map<String, String> = [];

    /** Maps exception class module path to its payload enum module path. */
    public final exceptionPayloads:Map<String, String> = [];

    /** Maps anonymous structure signatures to their defining typedef name and module. */
    public final structTypedefs:Map<String, {module:String, name:String}> = [];

    /**
        Private static functions reachable from emitted code, keyed by
        "<module>.<field>". Haxe's @:keep on whole registry classes forces
        uncalled private statics into the output where rustc reports them
        as dead; the compiler scans references before emission and omits
        the unreachable ones.
    **/
    public final referencedStatics:Map<String, Bool> = [];

    /** Standard-library shims used during compilation. */
    public final shimsUsed:Map<String, Bool> = [];

    /** Error enum module and name for Result<T, Error>. */
    public var errorModule:Null<String> = null;

    public var errorName:Null<String> = null;
    public var overflowVariant:Null<String> = null;

    /** Payload enum modules that define a CountOverflow variant. */
    public final countOverflowEnums:Map<String, Bool> = [];

    /**
        Functions that can throw, with the error enum they throw, keyed by
        `funcKey(module, name, isStatic)`. Computed in preScan as a fixpoint:
        a function is fallible when it throws, calls a runtime shim whose
        Result type the Haxe AST cannot show, or calls another fallible
        function.
    **/
    public final funcErrorEnums:Map<String, {module:String, name:String}> = [];

    /** Functions whose reachable error set requires a per-function union. */
    public final funcEnumConflicts:Map<String, Bool> = [];

    /** Complete reachable payload set for each fallible function. */
    public final funcErrorUnionMembers:Map<String, Array<{module:String, name:String}>> = [];

    /** Resolved Result error type for each fallible function. */
    public final funcErrorTypes:Map<String, {module:String, name:String}> = [];

    /** Synthetic union members, grouped by owning Haxe module. */
    public final syntheticErrorEnums:Map<String, Array<{name:String, members:Array<{module:String, name:String}>}>> = [];
    public final emittedSyntheticErrorModules:Map<String, Bool> = [];

    public function isSyntheticErrorType(name:String):Bool {
        for (decls in syntheticErrorEnums)
            for (decl in decls)
                if (decl.name == name) return true;
        return false;
    }

    public final recordCloneTypes:Map<String, Bool> = [];

    public static function funcKey(module:String, name:String, isStatic:Bool):String {
        return module + "::" + (isStatic ? "s." : "i.") + name;
    }

    /**
        Runtime shims are lowered to hand-written Rust that returns Result,
        so their fallibility is invisible to the Haxe AST and stays a name
        rule. Every other function derives fallibility from `funcErrorEnums`.
    **/
    public static function runtimeShimIsFallible(name:String):Bool {
        return name == "readU16" || name == "readU32" || name == "readF64" || name == "readAscii" || name == "ensureRemaining" || name == "decode"
            || name == "encode";
    }

    /** Types reachable at test assertion call sites for type-guided helpers. */
    public final testReachableTypes:Map<String, Type> = [];

    /** Modules containing @:test methods. */
    public final testModules:Map<String, Bool> = [];

    public function new() {}
}
#end
