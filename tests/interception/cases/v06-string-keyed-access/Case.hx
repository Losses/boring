// expect: V06 StringKeyedAccess
import boring.Console;
class Case {
	static function main():Void {
		final record = { name: "a" };
		final value = record["name"];
		Console.log(value);
	}
}
