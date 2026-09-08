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
        final buffer = new StringBuf();
        buffer.add("" + value);
        return buffer.toString().charCodeAt(0);
    }

    public static function simpleStringBufPart(value:String):Int {
        final buffer = new StringBuf();
        buffer.add(value);
        return buffer.toString().charCodeAt(0);
    }
}
