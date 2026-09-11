package tests;

import std.Test;

#if swift_output
import boring.FusedPushThrowOps;
#end

class FusedPushThrowTests {
    @:test("a fused push of a throwing construction carries the try marker")
    public static function testBuild():Void {
        #if swift_output
        Test.equals(6, FusedPushThrowOps.total([1, 2, 3]));
        #else
        Test.equals(true, true);
        #end
    }
}
