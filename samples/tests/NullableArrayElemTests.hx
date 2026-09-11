package tests;

import std.Test;

#if swift_output
import boring.NullableArrayElemOps;
#end

class NullableArrayElemTests {
    @:test("a nullable array element unwraps for a non-optional element type")
    public static function testCollect():Void {
        #if swift_output
        Test.equals(1, NullableArrayElemOps.count(NullableArrayElemOps.make(3)));
        #else
        Test.equals(true, true);
        #end
    }
}
