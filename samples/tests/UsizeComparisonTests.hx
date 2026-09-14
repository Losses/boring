package tests;

import boring.UsizeComparisonOps;
import std.Test;

class UsizeComparisonTests {
    @:test("a nullable array length bounds an index in the u32 comparison domain")
    public static function withinBounds():Void {
        #if rust_output
        Test.equals(true, UsizeComparisonOps.withinBounds([1, 2, 3], 2));
        Test.equals(false, UsizeComparisonOps.withinBounds([1, 2, 3], 3));
        Test.equals(false, UsizeComparisonOps.withinBounds(null, 0));
        #end
    }

    @:test("a nullable array length compares above an Int limit")
    public static function lengthExceeds():Void {
        #if rust_output
        Test.equals(true, UsizeComparisonOps.lengthExceeds([1, 2, 3], 2));
        Test.equals(false, UsizeComparisonOps.lengthExceeds([1, 2, 3], 3));
        Test.equals(false, UsizeComparisonOps.lengthExceeds(null, 0));
        #end
    }
}
