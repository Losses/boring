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

    @:test("Math.abs returns the absolute value of the float operand")
    public static function absFloat():Void {
        Test.equals(2.5, MathMinMaxOps.absValue(-2.5));
        Test.equals(2.5, MathMinMaxOps.absValue(2.5));
        Test.equals(0.0, MathMinMaxOps.absValue(-0.0));
    }

    @:test("Math.abs accepts an int operand through the float signature")
    public static function absInt():Void {
        Test.equals(7.0, MathMinMaxOps.absOfInts(7));
    }
}
