package tests;

import boring.LocalShadowOps;
import std.Test;

class LocalShadowTests {
    @:test("array comprehensions preserve both local values")
    public static function arrays():Void {
        Test.equals(10, LocalShadowOps.arrays());
    }

    @:test("shadowed locals retain their distinct values")
    public static function shadow():Void {
        Test.equals("ab", LocalShadowOps.shadow());
    }

    @:test("ordinary local remains unchanged")
    public static function single():Void {
        Test.equals(42, LocalShadowOps.single());
    }
}
