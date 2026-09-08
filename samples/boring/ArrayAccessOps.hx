package boring;

import std.StringBuf;

class ArrayAccessOps {
    public static function writeSplit(text:String):String {
        final parts = text.split(",");
        parts[0] = "x";
        return parts[0];
    }

    public static function readSplit(text:String):String {
        final parts = text.split(",");
        return parts[0];
    }

    public static function compositeStringBufPart(value:String):Int {
#if kotlin_output
        final buffer = new StringBuf();
        buffer.add("" + value);
        final rendered = buffer.toString();
        return rendered.charCodeAt(0);
#else
        return value.charCodeAt(0);
#end
    }

    public static function simpleStringBufPart(value:String):Int {
#if kotlin_output
        final buffer = new StringBuf();
        buffer.add(value);
        final rendered = buffer.toString();
        return rendered.charCodeAt(0);
#else
        return value.charCodeAt(0);
#end
    }
}
