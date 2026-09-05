package kotlincompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;

/**
    State shared by the emitters of one compilation: shim usage tracked
    for demand-driven runtime emission, the payload-enum linkage of the
    sealed error fold, the structure-to-typedef index backing
    nominal object literals, and test reachable types for type-guided helpers.
**/
class KotlinEmissionState {
    /** Shim file paths (no extension) referenced by emitted code. */
    public final shimsUsed:Map<String, Bool> = [];

    /** Payload-enum module to the exception class that folded it. */
    public final payloadEnumOwners:Map<String, String> = [];

    /** Exception-class module to the payload enum module it folds. */
    public final exceptionPayloads:Map<String, String> = [];

    /** Anonymous-structure signature to the typedef naming it. */
    public final structTypedefs:Map<String, {module:String, name:String}> = [];

    /**
        Synthetic abstract-implementation classes whose statics a generated
        reference names (`Name_Impl_.field`). A sub-type abstract's non-inline
        statics lower to its `_Impl_` companion, so `compileClassImpl` must
        emit the referenced `_Impl_` object even though ordinary synthetic
        impls never reach the output (features/49).
    **/
    public final referencedImpls:Map<String, Bool> = [];

    /** Types reachable at test assertion call sites for type-guided helpers. */
    public final testReachableTypes:Map<String, Type> = [];

    /** Test classes compiled with their @:test methods. */
    public final testClasses:Map<String, {cls:ClassType, funcs:Array<String>}> = [];

    /**
        Whether any compiled module referenced std.Process.args: the test
        entry then takes the program arguments and stores them for the
        lowered calls (stdlib/17). Entries that never reference args keep
        today's no-argument shape.
    **/
    public var processArgsReferenced:Bool = false;

    /**
        Guaranteed std modules that reached compilation only through the
        scope bypass: they write no file unless generated output also
        recorded a reference to them in `shimsUsed`.
    **/
    public final outOfScopeGuaranteedStd:Map<String, Bool> = [];

    public function new() {}
}
#end
