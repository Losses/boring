package haxe.io;

extern class Bytes {
	var length(default, never):Int;
	static function alloc(length:Int):Bytes;
	function get(index:Int):Int;
	function set(index:Int, value:Int):Void;
	function blit(pos:Int, src:Bytes, srcPos:Int, length:Int):Void;
	function sub(pos:Int, length:Int):Bytes;
	function fill(pos:Int, length:Int, value:Int):Void;
}
