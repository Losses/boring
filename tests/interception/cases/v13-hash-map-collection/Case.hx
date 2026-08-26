// expect: V13 HashMapCollection
import boring.Console;
class Case {
	static function main():Void {
		final lookup = new Map<String, Int>();
		lookup.set("a", 1);
		Console.log(Std.string(lookup.get("a")));
	}
}
