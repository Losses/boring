package tests;

import boring.DataClassRangeEqOps;
import std.Test;

class DataClassRangeEqTests {
    @:test("DataClass with TextRange field supports == comparison")
    public static function testDataClassRangeEq():Void {
        Test.equals(true, DataClassRangeEqOps.rangesEqual(), "struct with TextRange field compares with ==");
    }
}
