// Source-acceptance probe: high bound past the end, substring(4, 100)
// on the six-unit literal "abcdef".
class PSubhigh {
	public static function main():Void {
		var r:String = "abcdef".substring(4, 100);
		std.Console.log("subHigh=" + r);
	}
}
