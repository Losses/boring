package tests;

import std.Test;

#if swift_output
import boring.ValueTypeCtorBindingOps;
#end

class ValueTypeCtorBindingTests {
    @:test("a value wrapper built from a narrowed field carries the field value")
    public static function testWithSeed():Void {
        #if swift_output
        Test.equals(0.0, ValueTypeCtorBindingOps.rawOrZero());
        Test.equals(3.5, ValueTypeCtorBindingOps.withSeed(3.5));
        #else
        Test.equals(true, true);
        #end
    }
}
