package tests;

import std.Test;

#if swift_output
import boring.ArrayMethodSwiftOps;
#end

class ArrayMethodSwiftTests {
    @:test("indexOf lowers onto firstIndex with the -1 miss")
    public static function testFind():Void {
        #if swift_output
        Test.equals(1, ArrayMethodSwiftOps.locate([4, 5, 6], 5));
        Test.equals(-1, ArrayMethodSwiftOps.locate([4, 5, 6], 9));
        Test.equals(true, ArrayMethodSwiftOps.findText(["a", "b"], "b"));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("copy and concat lower onto native array operations")
    public static function testCopyConcat():Void {
        #if swift_output
        Test.equals(3, ArrayMethodSwiftOps.duplicate([1, 2, 3]).length);
        Test.equals(4, ArrayMethodSwiftOps.merge([1, 2], [3, 4]).length);
        #else
        Test.equals(true, true);
        #end
    }

    @:test("pop shift and unshift lower onto the mutating array members")
    public static function testEnds():Void {
        #if swift_output
        Test.equals(3, ArrayMethodSwiftOps.dropLast([1, 2, 3]));
        Test.equals(1, ArrayMethodSwiftOps.dropFirst([1, 2, 3]));
        Test.equals(0, ArrayMethodSwiftOps.prepend([1, 2, 3], 0));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("splice returns the removed sub-array")
    public static function testSplice():Void {
        #if swift_output
        Test.equals(2, ArrayMethodSwiftOps.cutAt([1, 2, 3], 1)[0]);
        #else
        Test.equals(true, true);
        #end
    }
}
