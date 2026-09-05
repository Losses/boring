package tests.f32;

import boring.PrintedFloat;
import std.Test;

class PrintedFloatTests {
    @:test("shortest binary32 text")
    public static function printsShortestFloatText():Void {
        Test.equals("PrintedFloat(ratio=0.8, offset=96.004, count=7)", Std.string(new PrintedFloat(0.8, 96.004, 7)));
    }

    @:test("whole, negative, and null binary32 text")
    public static function printsWholeNegativeAndNullFloatFields():Void {
        Test.equals("PrintedFloat(ratio=18.0, offset=null, count=1)", Std.string(new PrintedFloat(18.0, null, 1)));
        Test.equals("PrintedFloat(ratio=-0.8, offset=18.08, count=2)", Std.string(new PrintedFloat(-0.8, 18.08, 2)));
    }
}
