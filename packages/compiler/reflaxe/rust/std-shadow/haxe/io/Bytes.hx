package haxe.io;

extern class Bytes {
    var length(default, never):Int;
    static function alloc(length:Int):Bytes;
    function get(index:Int):Int;
    function set(index:Int, value:Int):Void;
    function blit(pos:Int, src:Bytes, srcPos:Int, length:Int):Void;
    function sub(pos:Int, length:Int):Bytes;
    function fill(pos:Int, length:Int, value:Int):Void;

    /** Encode a string as UTF-8 bytes. A fresh allocation every call (stdlib/01). */
    static function ofString(s:String):Bytes;

    /** Decode len bytes starting at pos as UTF-8 text. Invalid sequences decode as U+FFFD; never throws for encoding reasons (stdlib/01). */
    function getString(pos:Int, len:Int):String;

    /** A fresh Bytes of length a.length + b.length holding a then b (stdlib/01). */
    static function concat(a:Bytes, b:Bytes):Bytes;
}
