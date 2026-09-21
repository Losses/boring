package boring;

class StringUnitOps {
    public static function codeInRange(text:String):Null<Int> {
        return text.charCodeAt(1);
    }

    public static function codeAtEnd(text:String):Null<Int> {
        return text.charCodeAt(text.length - 1);
    }

    public static function codeOutOfRange(text:String):Null<Int> {
        return text.charCodeAt(text.length + 4);
    }

    public static function isSpaceAt(text:String, index:Int):Bool {
        var c:Null<Int> = text.charCodeAt(index);
        return c == 32;
    }

    public static function codeAtOrFallback(text:String, index:Int):Int {
        var c:Null<Int> = text.charCodeAt(index);
        return c == null ? -1 : c;
    }

    public static function splitCount(text:String):Int {
        return text.split(".").length;
    }

    public static function splitFirst(text:String):String {
        return text.split(".")[0];
    }

    public static function splitEmptyParts(text:String):Int {
        return text.split("..").length;
    }

    public static function splitAbsent(text:String):Int {
        return text.split("|").length;
    }

    /**
     * stdlib spec 15 rules the empty delimiter over code units, so the
     * part count equals the unit count and each part is the single-unit
     * string at that index. The parts bind to a local, so the lowering
     * sees a mutable array receiver.
     */
    public static function splitUnitCount(text:String):Int {
        final parts = text.split("");
        return parts.length;
    }

    public static function splitUnitAt(text:String, index:Int):String {
        final parts = text.split("");
        return parts[index];
    }

    public static function splitUnitCode(text:String, index:Int):Null<Int> {
        final parts = text.split("");
        return parts[index].charCodeAt(0);
    }

    /** The same split returned straight out of the general lowering. */
    public static function splitUnits(text:String):Array<String> {
        return text.split("");
    }
}
