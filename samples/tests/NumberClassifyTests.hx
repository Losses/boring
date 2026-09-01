package tests;

import boring.NumberClassifyOps;
import std.Test;

class NumberClassifyTests {
	@:test("isFinite accepts finite values and rejects NaN and infinities")
	public static function finiteClassification():Void {
		Test.equals(true, NumberClassifyOps.finite(0.0));
		Test.equals(true, NumberClassifyOps.finite(-1.5));
		Test.equals(true, NumberClassifyOps.finite(1.0e308));
		Test.equals(false, NumberClassifyOps.finite(Math.NaN));
		Test.equals(false, NumberClassifyOps.finite(Math.POSITIVE_INFINITY));
		Test.equals(false, NumberClassifyOps.finite(Math.NEGATIVE_INFINITY));
	}

	@:test("isNaN accepts NaN and rejects finite values and infinities")
	public static function nanClassification():Void {
		Test.equals(true, NumberClassifyOps.nan(Math.NaN));
		Test.equals(false, NumberClassifyOps.nan(0.0));
		Test.equals(false, NumberClassifyOps.nan(-1.5));
		Test.equals(false, NumberClassifyOps.nan(Math.POSITIVE_INFINITY));
		Test.equals(false, NumberClassifyOps.nan(Math.NEGATIVE_INFINITY));
	}
}
