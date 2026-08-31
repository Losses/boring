package tests;

import boring.ConstructedStateOps;
import std.Test;

class ConstructedStateTests {
	@:test("constructed static initializers expose their state")
	public static function testConstructedState():Void {
		Test.equals("weighted,plain,imported,generated", ConstructedStateOps.labels(), "constructed labels");
		Test.equals(1.5, ConstructedStateOps.weight(), "enum payload constant");
		Test.equals("2,0", ConstructedStateOps.firstLengths(), "constructed array lengths");
		Test.equals("cross-class", ConstructedStateOps.crossClassText(), "cross-class static dependency");
		Test.equals("generated", ConstructedStateOps.generatedLabel(), "static-function construction");
	}
}
