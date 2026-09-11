package tests;

import std.Test;

#if swift_output
import boring.NullStaticMapOps;
#end

class NullStaticMapTests {
    @:test("a null-initialized static map reads through an implicitly unwrapped optional")
    public static function testLookup():Void {
        #if swift_output
        Test.equals(true, NullStaticMapOps.lookup(1) == null);
        #else
        Test.equals(true, true);
        #end
    }
}
