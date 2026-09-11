package boring;

#if swift_output
/**
    Optional arguments of the string-buffer, hex, and array lowerings:
    `charCodeAt` reads as an optional, `Std.parseInt` is optional, and an
    `indexOf` operand may be a nullable element.
*/
class StringCodeOptionalOps {
    public static function hexEscape(text:String, index:Int):String {
        final code = text.charCodeAt(index);
        final buf = new StringBuf();
        buf.add("\\u" + StringTools.hex(code, 4).toLowerCase());
        return buf.toString();
    }

    public static function parsedRoundTrip(text:String):Int {
        final parsed = Std.parseInt(text);
        final values:Array<Int> = [];
        values.push(parsed);
        return values.indexOf(parsed);
    }
}
#else
class StringCodeOptionalOps {}
#end
