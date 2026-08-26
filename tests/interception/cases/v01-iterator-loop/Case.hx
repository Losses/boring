// expect: V01 IteratorLoop
import boring.Console;
class Case {
	static function main():Void {
		final items = new Array<Int>();
		for (item in items) {
			Console.log(Std.string(item));
		}
	}
}
