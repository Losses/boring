package tests;

import std.Test;

#if swift_output
import boring.NullableToStringOps;
#end

class NullableToStringTests {
    @:test("a narrowed nullable local still unwraps in Swift")
    public static function testRender():Void {
        #if swift_output
        Test.equals("info:7", NullableToStringOps.render(true));
        Test.equals("null", NullableToStringOps.render(false));
        Test.equals("info:9", NullableToStringOps.describe(true));
        Test.equals("null", NullableToStringOps.describe(false));
        #else
        Test.equals(true, true);
        #end
    }
}
