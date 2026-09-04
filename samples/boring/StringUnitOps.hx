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
}
