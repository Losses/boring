// Source-acceptance probe (supplementary row): negative low bound,
// substring(-1, 3) on the six-unit literal "abcdef".
class PSubneg {
	public static function main():Void {
		var r:String = "abcdef".substring(-1, 3);
		std.Console.log("subNeg=" + r);
	}
}
