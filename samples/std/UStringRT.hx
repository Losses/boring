package std;

/**
 * Unchecked runtime primitives behind std.UString
 * (docs/specs/stdlib/10-unicode-string-access.md). The public domain checks
 * live in the inline wrappers of std.UString and never reach these calls.
 * Transpile targets lower these statics into the runtime package; the haxe
 * stage-one side binds globalThis.std.UStringRT.
 */
extern class UStringRT {
    public static function count(s:String):Int;
    public static function at(s:String, index:Int):Null<Int>;
    public static function slice(s:String, from:Int, to:Int):String;
    public static function toCodePoints(s:String):Array<Int>;
    public static function fromCodePoint(code:Int):String;
    public static function fromCodePoints(codes:Array<Int>):String;
}
