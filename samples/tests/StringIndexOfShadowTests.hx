package tests;

import std.Test;

#if swift_output
import boring.StringIndexOfShadowOps;
#end

class StringIndexOfShadowTests {
    @:test("a string index search does not shadow the receiver's local")
    public static function testDashIndex():Void {
        #if swift_output
        Test.equals(1, StringIndexOfShadowOps.dashIndexAt(["a—b"], 0));
        Test.equals(-1, StringIndexOfShadowOps.dashIndexAt(["plain"], 0));
        #else
        Test.equals(true, true);
        #end
    }
}
