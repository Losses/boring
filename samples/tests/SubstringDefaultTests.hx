package tests;

import std.Test;

#if swift_output
import boring.SubstringDefaultOps;
#end

class SubstringDefaultTests {
    @:test("a substring coalescing default lowers through the UTF-16 helper")
    public static function testDerive():Void {
        #if swift_output
        Test.equals("bc", SubstringDefaultOps.derive("abcdef"));
        #else
        Test.equals(true, true);
        #end
    }
}
