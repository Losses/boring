// expect: V19 TryRegionControlFlow
import boring.Console;
import boring.VectorException;
class Case {
	static function main():Void {
		try {
			final value = 1;
			if (value > 0) {
				return;
			}
			Console.log(Std.string(value));
		} catch (error:VectorException) {
			Console.log("caught");
		}
	}
}
