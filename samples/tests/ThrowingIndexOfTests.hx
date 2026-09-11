package tests;

import std.Test;

#if swift_output
import boring.ThrowingIndexOfOps;
#end

class ThrowingIndexOfTests {
    @:test("an index search on a throwing receiver marks the closure try")
    public static function testAt():Void {
        #if swift_output
        Test.equals(0, ThrowingIndexOfOps.at(true));
        #else
        Test.equals(true, true);
        #end
    }
}
