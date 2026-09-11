package tests;

import std.Test;

#if swift_output
import boring.StringAppendOps;
#end

class StringAppendTests {
    @:test("a string += converts a non-string right side")
    public static function testAppend():Void {
        #if swift_output
        Test.equals("n=5", StringAppendOps.appendInt(5));
        Test.equals("@1", StringAppendOps.appendFloat(1.0));
        #else
        Test.equals(true, true);
        #end
    }
}
