package tests;

import std.Test;

#if swift_output
import boring.InterfaceArrayLiteralOps;
#end

class InterfaceArrayLiteralTests {
    @:test("an interface-typed array literal keeps its protocol members")
    public static function testTags():Void {
        #if swift_output
        Test.equals("alpha,beta", InterfaceArrayLiteralOps.tags().join(","));
        #else
        Test.equals(true, true);
        #end
    }
}
