package tests;

import std.Test;

#if swift_output
import boring.NullGuardFieldOps;
import boring.NullGuardFieldMetrics;
#end

class NullGuardFieldTests {
    @:test("a field null guard ternary lowers to nil coalescing")
    public static function testFieldGuard():Void {
        #if swift_output
        final withTypo = new NullGuardFieldMetrics(1.5, 2.0, null);
        Test.equals(true, NullGuardFieldOps.fieldAscent(withTypo) == 1.5);
        final withoutTypo = new NullGuardFieldMetrics(null, 2.0, "why");
        Test.equals(true, NullGuardFieldOps.fieldAscent(withoutTypo) == 2.0);
        Test.equals("why", NullGuardFieldOps.fieldReason(withoutTypo, "none"));
        Test.equals("none", NullGuardFieldOps.fieldReason(withTypo, "none"));
        #else
        Test.equals(true, true);
        #end
    }
}
