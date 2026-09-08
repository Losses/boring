package tests;

import boring.DartCharNullOps;
import std.Test;

class DartCharNullTests {
	@:test("charCodeAt results narrow correctly at consumer boundaries")
	public static function charNullNarrowing():Void {
		Test.equals(97, DartCharNullOps.argShape("abc"));
		Test.equals(97, DartCharNullOps.boundArgShape("abc"));
		Test.equals(true, DartCharNullOps.compareShape("ba"));
		Test.equals(99, DartCharNullOps.returnShape("abc"));
		Test.equals(true, DartCharNullOps.annotatedCompareShape("ba"));
		Test.equals(97, DartCharNullOps.annotatedBoundArgShape("abc"));
	}

	@:test("charCodeAt preserves null for out-of-range indices")
	public static function charNullOutOfRange():Void {
		final outOfRange:Null<Int> = "".charCodeAt(5);
		Test.equals(true, outOfRange == null);
	}
}
