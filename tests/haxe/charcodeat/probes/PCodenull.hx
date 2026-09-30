// Source-acceptance probe: out-of-range charCodeAt(100) held in the
// declared Null<Int> context on the six-unit literal "abcdef".
class PCodenull {
	public static function main():Void {
		var c:Null<Int> = "abcdef".charCodeAt(100);
		std.Console.log("codeNull=" + (c == null ? "null" : Std.string(c)));
	}
}
