package tests;

import std.Test;

#if swift_output
import boring.TypeAliasLocalOps;
#end

class TypeAliasLocalTests {
    @:test("a local class alias lowers to a Swift typealias")
    public static function testCompute():Void {
        #if swift_output
        Test.equals(17, TypeAliasLocalOps.compute(5));
        #else
        Test.equals(true, true);
        #end
    }
}
