package tests;

import boring.AllowGuest;
import std.Test;

class AllowAccessTests {
    @:test("allowed private static function is callable across classes")
    public static function staticAccess():Void {
        Test.equals(4, AllowGuest.useStatic(3));
    }

    @:test("allowed private static field is writable across classes")
    public static function staticFieldAccess():Void {
        Test.equals(42, AllowGuest.useCounter());
    }

    @:test("allowed private instance members are reachable across classes")
    public static function instanceAccess():Void {
        final g = new AllowGuest();
        Test.equals("mhost", g.useMethod());
    }
}
