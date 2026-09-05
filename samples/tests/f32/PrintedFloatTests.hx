package tests.f32;

import boring.PrintedFloat;
import std.Test;

class PrintedFloatTests {
    @:test("shortest binary32 text")
    public static function printsShortestFloatText():Void {
        Test.equals("PrintedFloat(ratio=0.8, offset=96.004, count=7, stops=null)", Std.string(new PrintedFloat(0.8, 96.004, 7, null)));
    }

    @:test("whole, negative, and null binary32 text")
    public static function printsWholeNegativeAndNullFloatFields():Void {
        Test.equals("PrintedFloat(ratio=18.0, offset=null, count=1, stops=null)", Std.string(new PrintedFloat(18.0, null, 1, null)));
        Test.equals("PrintedFloat(ratio=-0.8, offset=18.08, count=2, stops=null)", Std.string(new PrintedFloat(-0.8, 18.08, 2, null)));
    }

    @:test("computed shortest text stays applied to nullable fields")
    public static function printsComputedShortestTextOnNullableFields():Void {
        Test.equals("PrintedFloat(ratio=0.5714286, offset=0.5714286, count=7, stops=null)", Std.string(new PrintedFloat(4 / 7, 4 / 7, 7, null)));
    }
    @:test("nullable float collection keeps the ruled array form")
    public static function printsNullableFloatCollectionForm():Void {
        Test.equals("PrintedFloat(ratio=0.8, offset=null, count=7, stops=[1.5, 2.5])", Std.string(new PrintedFloat(0.8, null, 7, [1.5, 2.5])));
    }

    @:test("non-finite binary32 text keeps the platform form")
    public static function printsNonFiniteFloatFields():Void {
        Test.equals("PrintedFloat(ratio=Infinity, offset=NaN, count=3, stops=null)", Std.string(new PrintedFloat(Math.POSITIVE_INFINITY, 0.0 / 0.0, 3, null)));
        Test.equals("PrintedFloat(ratio=-Infinity, offset=null, count=4, stops=null)", Std.string(new PrintedFloat(Math.NEGATIVE_INFINITY, null, 4, null)));
    }
}
