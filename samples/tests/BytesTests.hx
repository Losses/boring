package tests;

import boring.BytesOps;
import std.Test;

class BytesTests {
	@:test("allocates and mutates fixed-length bytes")
	public static function fixedMutation():Void {
		final bytes = BytesOps.build();
		Test.equals(8, bytes.length);
		Test.equals(1, bytes.get(0));
		Test.equals(2, bytes.get(1));
		Test.equals(11, bytes.get(2));
		Test.equals(12, bytes.get(3));
		Test.equals(13, bytes.get(4));
		Test.equals(0xA5, bytes.get(5));
		Test.equals(0xA5, bytes.get(6));
		Test.equals(0, bytes.get(7));
	}
}
