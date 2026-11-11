
#if (macro || reflaxe_runtime)
/**
    Shared case conversion for emitted identifier names, byte-frozen by
    the refactor ruling: every function reproduces the per-target copies
    exactly, and normalization across targets requires its own approved
    project. Per-target keyword escape and snake/camel converters stay in
    their target modules until a unification ruling exists.
**/
class NameConversion {
    public static function lowerFirst(s:String):String {
        SharedModuleTrace.record("NameConversion");
        return s.charAt(0).toLowerCase() + s.substr(1);
    }

    public static function upperFirst(s:String):String {
        SharedModuleTrace.record("NameConversion");
        return s.length == 0 ? s : s.charAt(0).toUpperCase() + s.substr(1);
    }
}
#end
