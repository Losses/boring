// expect: V17 AssignArgExpression
import boring.Console;

class Case {
	static function helper(keep:Bool):Void {
		Console.log(Std.string(keep));
	}

	static function main():Void {
		helper(keep = true);
	}
}
