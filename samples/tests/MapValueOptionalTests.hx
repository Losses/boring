package tests;

import std.Test;

#if swift_output
import boring.MapValueOptionalOps;
#end

class MapValueOptionalTests {
    @:test("a sorted-map value optional carries one optional layer")
    public static function testValue():Void {
        #if swift_output
        Test.equals(3.0, MapValueOptionalOps.sum());
        #else
        Test.equals(true, true);
        #end
    }
}
