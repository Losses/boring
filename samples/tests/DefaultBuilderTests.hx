package tests;

import std.Test;

#if swift_output
import boring.DefaultBuilderOps;
#end

class DefaultBuilderTests {
    @:test("a coalescing default lowers a map builder and a secondary static field")
    public static function testDefaults():Void {
        #if swift_output
        Test.equals(0, DefaultBuilderOps.defaultSize());
        Test.equals(true, DefaultBuilderOps.defaultPatternIsShared());
        #else
        Test.equals(true, true);
        #end
    }
}
