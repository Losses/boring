package tests;

import boring.StaticFnOps;
import std.Test;

class StaticFnTests {
    @:test("static function values can be called")
    public static function testFunctionStatic():Void {
        Test.equals(8, StaticFnOps.apply(7));
    }

    @:test("ordinary mutable static remains shared")
    public static function testIntStatic():Void {
        Test.equals(1, StaticFnOps.increment());
        Test.equals(2, StaticFnOps.increment());
    }
}
