package tests;

import boring.IntDivisionOps;
import std.Test;

class IntDivisionTests {
    @:test("an Int quotient assigned to a Float keeps the fraction")
    public static function testQuotient():Void {
        Test.equals(3.5, IntDivisionOps.quotient(7, 2));
        Test.equals(0.5, IntDivisionOps.quotient(1, 2));
        Test.equals(2.0, IntDivisionOps.quotient(4, 2));
    }

    @:test("negative Int operands keep the Float quotient")
    public static function testNegativeQuotient():Void {
        Test.equals(-3.5, IntDivisionOps.quotient(-7, 2));
        Test.equals(-3.5, IntDivisionOps.quotient(7, -2));
        Test.equals(3.5, IntDivisionOps.quotient(-7, -2));
    }

    @:test("an Int quotient over a zero divisor reaches infinity")
    public static function testZeroDivisor():Void {
        Test.equals(Math.POSITIVE_INFINITY, IntDivisionOps.quotient(7, 0));
        Test.equals(Math.NEGATIVE_INFINITY, IntDivisionOps.quotient(-7, 0));
    }

    @:test("a layout offset keeps the fractional quotient")
    public static function testOffset():Void {
        Test.equals(7.5, IntDivisionOps.offset(10, 3, 4));
        Test.equals(2.5, IntDivisionOps.offset(5, 1, 2));
        Test.equals(5.0, IntDivisionOps.offset(10, 2, 4));
    }

    @:test("an Int quotient takes part in a Float multiply and add")
    public static function testScaled():Void {
        Test.equals(15.5, IntDivisionOps.scaled(10, 3, 4, 0.5));
        Test.equals(21.0, IntDivisionOps.scaled(10, 2, 4, 11.0));
    }

    @:test("the truncating spelling keeps integer division")
    public static function testTruncated():Void {
        Test.equals(3, IntDivisionOps.truncated(7, 2));
        Test.equals(-3, IntDivisionOps.truncated(-7, 2));
        Test.equals(2, IntDivisionOps.truncated(-7, -3));
        Test.equals(1, IntDivisionOps.remainder(7, 2));
        Test.equals(-1, IntDivisionOps.remainder(-7, 2));
    }

    @:test("a floored Int quotient floors the Float quotient")
    public static function testFloored():Void {
        Test.equals(3.0, IntDivisionOps.floored(7, 2));
        Test.equals(-4.0, IntDivisionOps.floored(-7, 2));
    }
}
