package boring;

import std.UStringRT;

/**
 * Direct std.UString calls used to verify that the Dart runtime resident is
 * emitted when the extern's lowered members are referenced.
 */
class UStringResidentOps {
    public static function count(text:String):Int {
        return UStringRT.count(text);
    }

    public static function at(text:String, index:Int):Null<Int> {
        return UStringRT.at(text, index);
    }

    public static function slice(text:String, from:Int, to:Int):String {
        return UStringRT.slice(text, from, to);
    }

    public static function fromCodePoint(code:Int):String {
        return UStringRT.fromCodePoint(code);
    }
}
