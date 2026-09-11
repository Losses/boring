package boring;

#if swift_output
/**
    `String += value` in Haxe appends the value's string form; Swift's
    `+=` needs the converted right side.
*/
class StringAppendOps {
    public static function appendInt(n:Int):String {
        var s = "n=";
        s += n;
        return s;
    }

    public static function appendFloat(f:Float):String {
        var s = "@";
        s += f;
        return s;
    }
}
#else
class StringAppendOps {}
#end
