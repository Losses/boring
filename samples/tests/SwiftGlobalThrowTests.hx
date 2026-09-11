package tests;

import std.Test;

#if swift_output
import boring.SwiftGlobalThrowOps;
#end

class SwiftGlobalThrowTests {
    @:test("a throwing stored static initializer force-tries at the declaration")
    public static function testSeed():Void {
        #if swift_output
        Test.equals(3, SwiftGlobalThrowOps.seedValue());
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a throwing computed accessor force-tries in the property body")
    public static function testCurrent():Void {
        #if swift_output
        Test.equals(4, SwiftGlobalThrowOps.currentValue(new SwiftGlobalThrowOps()));
        #else
        Test.equals(true, true);
        #end
    }
}
