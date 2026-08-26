// expect: V03 Reflection
import boring.Console;
class Case {
	static function main():Void {
		final present = Reflect.hasField({ name: "a" }, "name");
		Console.log(Std.string(present));
	}
}
