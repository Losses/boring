package tests;

import std.Test;

#if swift_output
import boring.NullableIndexOps;
#end

class NullableIndexTests {
    @:test("an optional array index unwraps for the Swift subscript")
    public static function testAt():Void {
        #if swift_output
        Test.equals(20, NullableIndexOps.at([10, 20, 30], 1));
        #else
        Test.equals(true, true);
        #end
    }
}
