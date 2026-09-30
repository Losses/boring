// Source-acceptance probe (supplementary row): negative
// charCodeAt(-1) held in the declared Null<Int> context on the
// six-unit literal "abcdef".
class PCodeneg {
	public static function main():Void {
		var c:Null<Int> = "abcdef".charCodeAt(-1);
		std.Console.log("codeNeg=" + (c == null ? "null" : Std.string(c)));
	}
}
