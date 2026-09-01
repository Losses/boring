package tests;

import boring.ArrayRootStateOps;
import std.Test;

class ArrayRootTests {
	@:test("small static arrays preserve their roots and elements")
	public static function testArrayRoots():Void {
		Test.equals(3, ArrayRootStateOps.readOnlyLength(), "read-only length");
		Test.equals(10, ArrayRootStateOps.readOnlyElement(0), "read-only first element");
		Test.equals(30, ArrayRootStateOps.readOnlyElement(2), "read-only last element");

		Test.equals(2, ArrayRootStateOps.mutableLength(), "mutable length");
		Test.equals(40, ArrayRootStateOps.mutableElement(0), "mutable first element");
		Test.equals(50, ArrayRootStateOps.mutableElement(1), "mutable last element");

		Test.equals(2, ArrayRootStateOps.wordsLength(), "string length");
		Test.equals("alpha", ArrayRootStateOps.word(0), "first string");
		Test.equals("beta", ArrayRootStateOps.word(1), "second string");

		Test.equals(2, ArrayRootStateOps.mixedLength(), "enum length");
		Test.equals(true, ArrayRootStateOps.mixedIsWeighted(), "enum element");
		Test.equals(7, ArrayRootStateOps.mixedWeight(), "cross-field element");

		Test.equals(2, ArrayRootStateOps.nestedLength(), "nested outer length");
		Test.equals(2, ArrayRootStateOps.nestedInnerLength(0), "nested first inner length");
		Test.equals(2, ArrayRootStateOps.nestedInnerLength(1), "nested second inner length");
		Test.equals(4, ArrayRootStateOps.nestedElement(1, 1), "nested last element");
	}
}
