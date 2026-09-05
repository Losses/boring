package boring;

/**
 * Drives the standard `StringTools` statics through the Kotlin target.
 * `lpad` has no native Kotlin `String` equivalent and no inline lowering,
 * so it must route into a runtime StringTools module (not an
 * unresolvable `StringTools.lpad` call).
 */
class StringToolsOps {
    public static function padLeft(s:String, len:Int):String {
        return StringTools.lpad(s, "0", len);
    }

    public static function ltrim(s:String):String {
        return StringTools.ltrim(s);
    }

    public static function rtrim(s:String):String {
        return StringTools.rtrim(s);
    }

    public static function replaceDelims(s:String):String {
        return StringTools.replace(s, ";", ",");
    }
}
