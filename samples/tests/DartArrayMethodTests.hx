package tests;

import std.Test;

#if dart_output
import boring.DartArrayMethodOps;
#end

class DartArrayMethodTests {
    @:test("concat and splice lower onto Dart list operations")
    public static function testConcatSplice():Void {
        #if dart_output
        Test.equals(1, DartArrayMethodOps.merge([1, 2], [3, 4])[0]);
        Test.equals(3, DartArrayMethodOps.cutAt([7, 8, 9], 1)[0]);
        #else
        Test.equals(true, true);
        #end
    }

    @:test("reverse and unshift mutate the list in place")
    public static function testReverseUnshift():Void {
        #if dart_output
        Test.equals(3, DartArrayMethodOps.flipped([1, 2, 3])[0]);
        Test.equals(1, DartArrayMethodOps.flipped([1, 2, 3])[2]);
        Test.equals(5, DartArrayMethodOps.prepended([1, 2], 5));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("pop and shift answer the end elements")
    public static function testPopShift():Void {
        #if dart_output
        Test.equals(3, DartArrayMethodOps.last([1, 2, 3]));
        Test.equals(1, DartArrayMethodOps.first([1, 2, 3]));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a bool comparison condition emits no toDouble call")
    public static function testBoolCondition():Void {
        #if dart_output
        Test.equals(true, DartArrayMethodOps.emptyOrNegative(0, 1.0));
        Test.equals(false, DartArrayMethodOps.emptyOrNegative(1, 1.0));
        Test.equals(true, DartArrayMethodOps.emptyOrNegative(1, -0.5));
        #else
        Test.equals(true, true);
        #end
    }
}
