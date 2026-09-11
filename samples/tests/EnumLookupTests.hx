package tests;

import std.Test;

#if swift_output
import boring.EnumLookupOps;
#end

class EnumLookupTests {
    @:test("a createEnum result unwraps before a name read")
    public static function testRoundTrip():Void {
        #if swift_output
        Test.equals("Skia", EnumLookupOps.roundTrip("Skia"));
        Test.equals("CoreText", EnumLookupOps.roundTrip("CoreText"));
        #else
        Test.equals(true, true);
        #end
    }
}
