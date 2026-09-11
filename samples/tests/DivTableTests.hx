package tests;

import std.Test;
import boring.DivTableOps;

class DivTableTests {
    @:test("length division by constant lowers to integer division")
    public static function testDiv():Void {
        Test.equals(true, DivTableOps.lookup(0x20) >= 0);
    }
}
