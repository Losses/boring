package tests;

import boring.NumericConversionWidening;
import std.Test;

class NumericConversionWideningTests {
    #if kotlin
    @:test("Numeric conversion widening compares Float and Int")
    public static function testComparison():Void {
        Test.equals(true, NumericConversionWidening.compareEqual(1.0, 1));
        Test.equals(false, NumericConversionWidening.compareEqual(1.0, 2));
        Test.equals(false, NumericConversionWidening.compareNotEqual(1.0, 1));
        Test.equals(true, NumericConversionWidening.compareNotEqual(1.0, 2));
    }

    @:test("Numeric conversion widening returns Int from Float function")
    public static function testReturn():Void {
        Test.equals(5.0, NumericConversionWidening.returnIntAsFloat(5));
    }

    @:test("Numeric conversion widening initializes Float from Int")
    public static function testInit():Void {
        Test.equals(16.0, NumericConversionWidening.initFloat());
    }

    @:test("Numeric conversion widening assigns Int to Float")
    public static function testAssign():Void {
        Test.equals(42.0, NumericConversionWidening.assignIntToFloat());
    }

    @:test("Numeric conversion widening passes Int to Float parameter")
    public static function testParam():Void {
        Test.equals(9.0, NumericConversionWidening.callFloatParam());
    }
    #end
}
