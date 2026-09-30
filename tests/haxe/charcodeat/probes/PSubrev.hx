// Source-acceptance probe: reversed in-range substring(4, 2) on the
// six-unit literal "abcdef". Compiled standalone by run.sh against the
// plain Haxe 4.3.7 toolchain; the raw diagnostic or the raw output is
// the observation.
class PSubrev {
	public static function main():Void {
		var r:String = "abcdef".substring(4, 2);
		std.Console.log("subRev=" + r);
	}
}
