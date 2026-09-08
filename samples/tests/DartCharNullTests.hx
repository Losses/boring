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
	}

	@:test("charCodeAt preserves null for out-of-range indices")
	public static function charNullOutOfRange():Void {
		Test.equals(null, DartCharNullOps.argShape(""));
		Test.equals(null, DartCharNullOps.boundArgShape(""));
		Test.equals(false, DartCharNullOps.compareShape(""));
		Test.equals(null, DartCharNullOps.returnShape(""));
	}
}
