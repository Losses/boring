package rustcompiler;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
import rustcompiler.RustSymbols.SymbolRef;

/**
    Three-state resolution of a function's error domain (WBS P6.4).

    Fallible names the error enum or union the function can throw;
    Infallible marks a function the fallibility scan proved cannot throw;
    Unknown marks a function whose domain is not registered in this
    compilation scope, which consumers must reject instead of silently
    treating as infallible.
**/
enum ErrorDomain {
    Fallible(ref:SymbolRef);
    Infallible;
    Unknown;
}

/**
    Central lookup over RustEmissionState.funcErrorEnums and
    RustEmissionState.funcErrorKnown. Replaces the scattered
    funcErrorEnums.exists reads so a reference that resolves to neither
    map faults with a scope diagnostic instead of defaulting to infallible.
**/
class ErrorDomainRegistry {
    public static var state:Null<RustEmissionState> = null;

    /** Resolve a funcKey to its three-state error domain. */
    public static function lookup(funcKey:String):ErrorDomain {
        final s = state;
        if (s == null)
            return Unknown;
        final ref = s.funcErrorEnums.get(funcKey);
        if (ref != null)
            return Fallible(ref);
        if (s.funcErrorKnown.exists(funcKey))
            return Infallible;
        return Unknown;
    }

    /** true when the domain is fallible; a scope diagnostic on Unknown. */
    public static function isFallible(funcKey:String):Bool {
        return switch (lookup(funcKey)) {
            case Fallible(_): true;
            case Infallible: false;
            case Unknown:
                fault(funcKey);
                false;
        };
    }

    /** The error enum/union a fallible function throws, or null. */
    public static function errorRef(funcKey:String):Null<SymbolRef> {
        return switch (lookup(funcKey)) {
            case Fallible(ref): ref;
            case Infallible: null;
            case Unknown:
                fault(funcKey);
                null;
        };
    }

    static function fault(funcKey:String):Void {
        Context.error("`" + funcKey + "` error domain is not emitted in this compilation scope", Context.currentPos());
    }
}
#end
