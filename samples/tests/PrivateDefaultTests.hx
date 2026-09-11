package tests;

import std.Test;

#if swift_output
import boring.PrivateDefaultOps;
#end

class PrivateDefaultTests {
    @:test("a coalescing default may call a private static helper")
    public static function testDefaults():Void {
        #if swift_output
        Test.equals(0, new PrivateDefaultOps().size());
        Test.equals(2, new PrivateDefaultOps([1, 2]).size());
        #else
        Test.equals(true, true);
        #end
    }
}
