package tests;

import std.Test;

#if swift_output
import boring.MultiPatternSwitchOps;
import boring.MultiPatternSwitchOps.MultiPatternKind;
import boring.MultiPatternSwitchOps.MultiPatternTag;
#end

class MultiPatternSwitchTests {
    @:test("a multi-pattern switch arm keeps every pattern")
    public static function testPatterns():Void {
        #if swift_output
        Test.equals("ab", MultiPatternSwitchOps.label(MultiPatternKind.Alpha));
        Test.equals("ab", MultiPatternSwitchOps.label(MultiPatternKind.Beta));
        Test.equals("g", MultiPatternSwitchOps.label(MultiPatternKind.Gamma));
        Test.equals(4, MultiPatternSwitchOps.tagValue(MultiPatternTag.Left(4)));
        Test.equals(7, MultiPatternSwitchOps.tagValue(MultiPatternTag.Right(7)));
        Test.equals(0, MultiPatternSwitchOps.tagValue(MultiPatternTag.None));
        #else
        Test.equals(true, true);
        #end
    }
}
