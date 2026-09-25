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

    /**
        Maps payload enum module path to the enum's declared name. The name
        cannot be derived from the module path: an enum declared in the same
        file as its exception class (for example NoSuchElementError inside
        TiqianNoSuchElementException.hx) has a module whose last segment is
        the class name; the enum name is a separate identifier.
    **/
    public final payloadEnumNames:Map<String, String> = [];

    /** Message-only exception classes are represented by their own Rust error enum. */
    public final messageOnlyExceptions:Map<String, String> = [];

    /** Maps anonymous structure signatures to their defining typedef name and module. */
    public final structTypedefs:Map<String, {module:String, name:String}> = [];

    /**
        Synthetic abstract-implementation classes whose statics a generated
        reference names (`Name_Impl_::field`). A sub-type abstract's non-inline
        statics lower to its `_Impl_`, so `compileClassImpl` must emit the
        referenced `_Impl_` even though ordinary synthetic impls never reach
        the output (features/49).
    **/
    public final referencedImpls:Map<String, Bool> = [];

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

    public final interfaceMethodShapes:Map<String, {isFallible:Bool, isMutating:Bool, errorModule:Null<String>, errorName:Null<String>}> = [];

    public static function interfaceMethodKey(module:String, name:String, method:String):String {
        return module + "." + name + "." + method;
    }

    /** Functions whose reachable error set requires a per-function union. */
    public final funcEnumConflicts:Map<String, Bool> = [];

    /** Complete reachable payload set for each fallible function. */
    public final funcErrorUnionMembers:Map<String, Array<{module:String, name:String}>> = [];

    /** Resolved Result error type for each fallible function. */
    public final funcErrorTypes:Map<String, {module:String, name:String}> = [];

    /** Synthetic union members, grouped by owning Haxe module. */
    public final syntheticErrorEnums:Map<String, Array<{name:String, members:Array<{module:String, name:String}>}>> = [];

    public final syntheticErrorVariants:Map<String, Map<String, String>> = [];

    public final emittedSyntheticErrorModules:Map<String, Bool> = [];

    /**
        Fallible-block parameters: for each fallible function (keyed by
        funcKey), the parameter indices whose `() -> Void` slot receives a
        function literal whose body contains a discarded fallible call. Such
        parameters render as `Arc<dyn Fn() -> Result<(), E>>` and their call
        sites propagate with `?`. Computed in preScan as a fixpoint so a
        fallible block passed through a wrapper reaches the leaf callee.
    **/
    public final fallibleBlockParams:Map<String, Array<Int>> = [];

    /**
        Fallible-block region error names, keyed by `funcKey#paramIndex`: the
        error type of the try region that encloses the parameter's call in the
        callee body. A block propagates into *that* region, not into the
        callee's own error enum, so the parameter type, the callee's call to
        it, and the caller's literal must all name the caught type.
    **/
    public final fallibleBlockRegions:Map<String, String> = [];

    /**
        Local variables bound to a function literal that is later handed to a
        fallible-block slot, keyed by the local's id: the slot it reaches.
        Both the literal and the local's declared type must carry the slot's
        Result, so the value is recorded where its slot is known and resolved
        to an error type once the region scan has run.
    **/
    public final fallibleBlockLocalSlots:Map<Int, String> = [];

    /**
        A message-only exception carries text and declares no variants, so a
        `?` cannot map into it the way an enum fault can; the caller formats
        the source error into the text instead.
    **/
    public function isMessageOnlyErrorName(name:String):Bool {
        return messageOnlyModuleFor(name) != null;
    }

    /** The module a message-only exception type was declared in, by type name. **/
    public function messageOnlyModuleFor(name:String):Null<String> {
        for (module in messageOnlyExceptions.keys())
            if (messageOnlyExceptions.get(module) == name)
                return module;
        return null;
    }

    public function isSyntheticErrorType(name:String):Bool {
        for (decls in syntheticErrorEnums)
            for (decl in decls)
                if (decl.name == name)
                    return true;
        return false;
    }

    public function syntheticErrorMembers(name:String):Null<Array<{module:String, name:String}>> {
        for (decls in syntheticErrorEnums)
            for (decl in decls)
                if (decl.name == name)
                    return decl.members;
        return null;
    }

    public function syntheticErrorVariant(name:String, member:{module:String, name:String}):Null<String> {
        final variants = syntheticErrorVariants.get(name);
        return variants == null ? null : variants.get(member.module + "::" + member.name);
    }

    /**
        Growth variants registered against declared (non-synthetic) fault
        enums. When a fallible callee contributes a fault the declared enum
        does not carry, the enum grows a wrapping variant and a From impl so
        the `?` conversion compiles; declared variants stay untouched.
        Keyed by the declared enum's emitted name.
    **/
    public final enumGrowth:Map<String, Array<{calleePath:String, calleeName:String, variant:String}>> = [];

    public function registerFaultConversion(callerEnum:String, calleePath:String, calleeName:String):String {
        final variant = calleeName;
        var growth = enumGrowth.get(callerEnum);
        if (growth == null) {
            growth = [];
            enumGrowth.set(callerEnum, growth);
        }
        for (item in growth)
            if (item.calleeName == calleeName)
                return variant;
        growth.push({calleePath: calleePath, calleeName: calleeName, variant: variant});
        return variant;
    }

    public function enumGrowthFor(enumName:String):Null<Array<{calleePath:String, calleeName:String, variant:String}>> {
        return enumGrowth.get(enumName);
    }

    public final recordCloneTypes:Map<String, Bool> = [];

    /**
        Sealed interfaces whose implementors all derive Clone, keyed by
        "<module>::<name>". A data class holding such an interface lowers the
        field to Box<dyn Trait>; emitting the trait with a Clone supertrait
        makes that Box Clone so the data class can derive Clone.
    **/
    public final sealedCloneInterfaces:Map<String, Bool> = [];

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
