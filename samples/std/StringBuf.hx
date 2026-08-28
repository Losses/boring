package std;

/**
 * Standard library extern for StringBuf (docs/specs/stdlib/08-string-buffer.md).
 * Routed per-platform in compiler layers and maps to real haxe StringBuf in stage 1.
 */
extern class StringBuf {
	public function new();
	public function add(part:String):Void;
	public function addChar(codeUnit:Int):Void;
	public var length(get, never):Int;
	public function toString():String;
}
