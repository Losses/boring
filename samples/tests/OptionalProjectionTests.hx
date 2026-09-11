package tests;

import std.Test;

#if swift_output
import boring.OptionalProjectionOps;
import boring.ValueTypeOps.Ic;
#end

class OptionalProjectionTests {
    @:test("a nullable value-type projection unwraps at its member read")
    public static function testProjections():Void {
        #if swift_output
        Test.equals(32.0, OptionalProjectionOps.toPx(16.0, new Ic(2.0)));
        Test.equals(0.0, OptionalProjectionOps.toPx(16.0, null));

        Test.equals("base", OptionalProjectionOps.trimDetail("base", "  "));
        Test.equals("base:pad", OptionalProjectionOps.trimDetail("base", " pad "));
        Test.equals("none", OptionalProjectionOps.trimDetail(null, "pad"));

        final text = OptionalProjectionOps.recordText("primary", ["fallback", null]);
        Test.equals(true, text.indexOf("ProjectionRecord") >= 0);
        #else
        Test.equals(true, true);
        #end
    }
}
