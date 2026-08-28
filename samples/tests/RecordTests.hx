package tests;

import boring.RecordOps;
import std.Test;

class RecordTests {
	@:test("zero override returns record with all original fields")
	public static function testZeroOverride():Void {
		final orig = RecordOps.makeItem(1, "alpha", 100, true);
		final copy = RecordOps.copyNoOverride(orig);
		Test.equals(1, copy.id);
		Test.equals("alpha", copy.name);
		Test.equals(100, copy.score);
		Test.equals(true, copy.active);
	}

	@:test("single override replaces only targeted field")
	public static function testSingleOverride():Void {
		final orig = RecordOps.makeItem(2, "beta", 80, false);
		final copy = RecordOps.copySingleOverride(orig, 99);
		Test.equals(2, copy.id);
		Test.equals("beta", copy.name);
		Test.equals(99, copy.score);
		Test.equals(false, copy.active);
	}

	@:test("reordered overrides apply in declaration order and preserve untouched fields")
	public static function testReorderedOverrides():Void {
		final orig = RecordOps.makeItem(3, "gamma", 50, false);
		final copy = RecordOps.copyReordered(orig, true, "gamma_updated");
		Test.equals(3, copy.id);
		Test.equals("gamma_updated", copy.name);
		Test.equals(50, copy.score);
		Test.equals(true, copy.active);
	}

	@:test("multiple overrides replace all specified fields")
	public static function testMultipleOverrides():Void {
		final orig = RecordOps.makeItem(4, "delta", 20, false);
		final copy = RecordOps.copyMultiple(orig, 10, "delta_all", 999);
		Test.equals(10, copy.id);
		Test.equals("delta_all", copy.name);
		Test.equals(999, copy.score);
		Test.equals(false, copy.active);
	}
}
