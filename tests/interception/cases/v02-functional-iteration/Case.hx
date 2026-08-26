// expect: V02 FunctionalIteration
import boring.Console;
class Case {
	static function main():Void {
		final items = new Array<Int>();
		final doubled = items.map(function(item:Int):Int {
			return item * 2;
		});
		Console.log(Std.string(doubled.length));
	}
}
