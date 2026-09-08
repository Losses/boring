package tests;

import boring.ComparatorGateOps;
import std.Test;

class ComparatorGateTests {
    @:test("comparable data classes remain usable")
    public static function comparable():Void {
        Test.equals("ok", ComparatorGateOps.comparable().value.name);
    }

    @:test("data classes with unsupported comparator fields remain usable")
    public static function unsupported():Void {
#if dart_output
        Test.equals(true, ComparatorGateOps.unsupported().boolRecord.enabled);
#else
        Test.equals("ok", ComparatorGateOps.comparable().value.name);
#end
    }
}
