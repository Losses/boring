package tests;

import boring.ValueTypeClashOps.ClashCount;
import boring.ValueTypeClashOps.PlainCount;
import std.Test;

/** Runtime hooks for the representation-name clash wrappers. */
class ValueTypeClashTests {
    @:test("clashing wrapper reads through the colliding member")
    public static function clashDoubled():Void {
        Test.equals(4.0, new ClashCount(2.0).doubled());
    }

    @:test("clash-free wrapper reads its representation")
    public static function controlMember():Void {
        Test.equals(3.0, new PlainCount(3.0).read());
    }
}
