package tests;

import std.Test;

#if swift_output
import boring.NarrowLocalSwitchOps;
import boring.NarrowLocalSwitchOps.NarrowLocalKind;
#end

class NarrowLocalSwitchTests {
    @:test("a narrowed enum local resumes an exhaustive switch")
    public static function testNarrowedSwitch():Void {
        #if swift_output
        Test.equals("a", NarrowLocalSwitchOps.label(NarrowLocalKind.Alpha));
        Test.equals("b", NarrowLocalSwitchOps.label(NarrowLocalKind.Beta));
        Test.equals("g", NarrowLocalSwitchOps.label(NarrowLocalKind.Gamma));
        Test.equals("none", NarrowLocalSwitchOps.label(null));
        #else
        Test.equals(true, true);
        #end
    }
}
