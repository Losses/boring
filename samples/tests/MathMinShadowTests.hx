package tests;

import std.Test;

#if swift_output
import boring.MathMinShadowOps;
#end

class MathMinShadowTests {
    @:test("Math.min evaluates an operand that reads a local named a")
    public static function testClamp():Void {
        #if swift_output
        final items = [MathMinShadowOps.make(3.0), MathMinShadowOps.make(4.0)];
        Test.equals(10.0, MathMinShadowOps.clamp(items, 100.0));
        #else
        Test.equals(true, true);
        #end
    }
}
