package tests;

import std.Test;

#if kotlin_output
import boring.SumOfFloatLocalOps;
#end

class SumOfFloatLocalTests {
    @:test("sumOfFloat in a local function keeps the Float accumulator")
    public static function testTotal():Void {
        #if kotlin_output
        Test.equals(6.0, SumOfFloatLocalOps.total([1.5, 2.0, 2.5]));
        Test.equals(7.25, SumOfFloatLocalOps.total([1.5, 2.5, 3.25]));
        Test.equals(0.0, SumOfFloatLocalOps.total([]));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a weighted sumOfFloat in a local function scales the accumulator")
    public static function testWeighted():Void {
        #if kotlin_output
        Test.equals(12.0, SumOfFloatLocalOps.weighted([1.5, 2.0, 2.5], 2.0));
        Test.equals(14.5, SumOfFloatLocalOps.weighted([1.5, 2.5, 3.25], 2.0));
        #else
        Test.equals(true, true);
        #end
    }
}
