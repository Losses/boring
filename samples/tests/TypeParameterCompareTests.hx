package tests;

import std.Test;

#if swift_output
import boring.TypeParameterCompareOps;
#end

class TypeParameterCompareTests {
    @:test("a generic equality compares equal and different values")
    public static function testCompare():Void {
        #if swift_output
        Test.equals(true, TypeParameterCompareOps.same(2, 2));
        Test.equals(false, TypeParameterCompareOps.same(2, 3));
        Test.equals(true, TypeParameterCompareOps.different(2, 3));
        #else
        Test.equals(true, true);
        #end
    }
}
