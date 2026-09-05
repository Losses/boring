package tests;

import boring.MathMinMaxOps;
import std.Test;

class MathMinMaxTests {
    @:test("Math.min returns the lesser float operand")
    public static function minFloat():Void {
        Test.equals(1.5, MathMinMaxOps.smaller(1.5, 2.5));
        Test.equals(1.5, MathMinMaxOps.smaller(2.5, 1.5));
        Test.equals(-3.0, MathMinMaxOps.smaller(-3.0, -1.0));
    }

    @:test("Math.max returns the greater float operand")
    public static function maxFloat():Void {
        Test.equals(2.5, MathMinMaxOps.larger(1.5, 2.5));
        Test.equals(2.5, MathMinMaxOps.larger(2.5, 1.5));
        Test.equals(-1.0, MathMinMaxOps.larger(-3.0, -1.0));
    }

    @:test("Math.min and Math.max accept int operands through the float signature")
    public static function intOperands():Void {
        Test.equals(4.0, MathMinMaxOps.smallerOfInts(4, 9));
        Test.equals(9.0, MathMinMaxOps.largerOfInts(4, 9));
    }
}
