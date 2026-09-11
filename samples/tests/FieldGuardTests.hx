package tests;

import std.Test;
import boring.FieldGuardOps;

class FieldGuardTests {
    @:test("null-guarded field narrows to its inner type")
    public static function testArea():Void {
        Test.equals(true, FieldGuardOps.area() == 12.0);
        Test.equals(true, FieldGuardOps.emptyArea() == 0.0);
    }
}
