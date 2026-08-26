// expect: V12 DataInheritance
import boring.Console;
class Base {
	public function new() {}
}

class Derived extends Base {
	public function new() {
		super();
	}
}

class Case {
	static function main():Void {
		final derived = new Derived();
		Console.log(Std.string(derived));
	}
}
