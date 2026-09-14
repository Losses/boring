package tests;

import boring.NullableFloatCompareOps;
import std.Test;

class NullableFloatCompareTests {
    @:test("a null-coalescing Float local compares zero in the Float domain")
    public static function structuralZero():Void {
        #if rust_output
        Test.equals(true, NullableFloatCompareOps.structuralZero(0.0, 0.0));
        Test.equals(false, NullableFloatCompareOps.structuralZero(0.5, 0.0));
        Test.equals(false, NullableFloatCompareOps.structuralZero(null, 0.5));
        #end
    }

    @:test("a null-coalescing Float local inequality compares zero in the Float domain")
    public static function notZero():Void {
        #if rust_output
        Test.equals(false, NullableFloatCompareOps.notZero(0.0));
        Test.equals(true, NullableFloatCompareOps.notZero(0.5));
        Test.equals(false, NullableFloatCompareOps.notZero(null));
        #end
    }
}
