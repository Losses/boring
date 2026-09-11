package tests;

import boring.StringBufThrowOps;
import std.Test;

class StringBufThrowTests {
    @:test("add carries a throwing argument through the surrogate guard")
    public static function testBuildFromChecked():Void {
        Test.equals("item-7", StringBufThrowOps.buildFromChecked(7));
    }

    @:test("the added call fault leaves the buffer expression")
    public static function testCaughtChecked():Void {
        Test.equals(3011, StringBufThrowOps.caughtChecked(0));
    }

    @:test("addChar carries a throwing unit through the surrogate guard")
    public static function testBuildCharFromChecked():Void {
        Test.equals("A", StringBufThrowOps.buildCharFromChecked(1));
    }
}
