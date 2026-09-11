package tests;

import std.Test;

#if swift_output
import boring.ArrayJoinOps;
#end

class ArrayJoinTests {
    @:test("a non-string array join maps each value to its string form")
    public static function testJoin():Void {
        #if swift_output
        Test.equals("1, 2", ArrayJoinOps.joinInts([1, 2]));
        Test.equals("0, 5", ArrayJoinOps.joinFloats([0.0, 5.0]));
        #else
        Test.equals(true, true);
        #end
    }
}
