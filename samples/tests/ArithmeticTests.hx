package tests;

import boring.ArithmeticOps;
import std.Test;

class ArithmeticTests {
	@:test("within checks integer range inclusion")
	public static function testWithinInt():Void {
		Test.equals(true, ArithmeticOps.checkWithinInt(5, 1, 10));
		Test.equals(true, ArithmeticOps.checkWithinInt(1, 1, 10));
		Test.equals(true, ArithmeticOps.checkWithinInt(10, 1, 10));
		Test.equals(false, ArithmeticOps.checkWithinInt(0, 1, 10));
		Test.equals(false, ArithmeticOps.checkWithinInt(11, 1, 10));
	}

	@:test("within checks float range inclusion")
	public static function testWithinFloat():Void {
		Test.equals(true, ArithmeticOps.checkWithinFloat(5.5, 1.0, 10.0));
		Test.equals(true, ArithmeticOps.checkWithinFloat(1.0, 1.0, 10.0));
		Test.equals(true, ArithmeticOps.checkWithinFloat(10.0, 1.0, 10.0));
		Test.equals(false, ArithmeticOps.checkWithinFloat(0.9, 1.0, 10.0));
		Test.equals(false, ArithmeticOps.checkWithinFloat(10.1, 1.0, 10.0));
	}

	@:test("coerceAtLeast clamps values to floor")
	public static function testCoerceAtLeast():Void {
		Test.equals(5, ArithmeticOps.clampLeastInt(3, 5));
		Test.equals(8, ArithmeticOps.clampLeastInt(8, 5));
		Test.equals(5.0, ArithmeticOps.clampLeastFloat(3.2, 5.0));
		Test.equals(8.4, ArithmeticOps.clampLeastFloat(8.4, 5.0));
	}

	@:test("coerceAtMost clamps values to ceiling")
	public static function testCoerceAtMost():Void {
		Test.equals(5, ArithmeticOps.clampMostInt(8, 5));
		Test.equals(3, ArithmeticOps.clampMostInt(3, 5));
		Test.equals(5.0, ArithmeticOps.clampMostFloat(8.2, 5.0));
		Test.equals(3.4, ArithmeticOps.clampMostFloat(3.4, 5.0));
	}

	@:test("coerceIn clamps values to range")
	public static function testCoerceIn():Void {
		Test.equals(10, ArithmeticOps.clampInInt(5, 10, 20));
		Test.equals(15, ArithmeticOps.clampInInt(15, 10, 20));
		Test.equals(20, ArithmeticOps.clampInInt(25, 10, 20));
		Test.equals(10.0, ArithmeticOps.clampInFloat(5.5, 10.0, 20.0));
		Test.equals(15.5, ArithmeticOps.clampInFloat(15.5, 10.0, 20.0));
		Test.equals(20.0, ArithmeticOps.clampInFloat(25.5, 10.0, 20.0));
	}

	@:test("IntRange contains evaluates bounds")
	public static function testIntRange():Void {
		Test.equals(true, ArithmeticOps.inRange(10, 20, 10));
		Test.equals(true, ArithmeticOps.inRange(10, 20, 15));
		Test.equals(true, ArithmeticOps.inRange(10, 20, 20));
		Test.equals(false, ArithmeticOps.inRange(10, 20, 9));
		Test.equals(false, ArithmeticOps.inRange(10, 20, 21));
	}
}
