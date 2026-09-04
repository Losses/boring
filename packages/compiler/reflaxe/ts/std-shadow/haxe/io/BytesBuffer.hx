package haxe.io;

extern class BytesBuffer {
    function new():Void;
    function addByte(byte:Int):Void;

    /** Append the whole argument to the end of the buffer (stdlib/02). */
    function add(b:Bytes):Void;

    function getBytes():Bytes;
}
