package tests;

import boring.NullableLocalOps;
import boring.NullableLocalOps.LocalProbe;
import std.Test;

class NullableLocalTests {
    @:test("a nullable Int local from a literal compares equal inside Some")
    public static function intLocalKeepsSome():Void {
        Test.equals(true, NullableLocalOps.intLocalMatches([1, 2]));
    }

    @:test("a nullable Float local from a literal compares equal inside Some")
    public static function floatLocalKeepsSome():Void {
        Test.equals(true, NullableLocalOps.floatLocalMatches([0.5, 1.5]));
    }

    @:test("a null Bool local stays null")
    public static function nullBoolStaysNull():Void {
        Test.equals(true, NullableLocalOps.boolLocalIsNull());
    }

    @:test("a nullable String local keeps the existing Some wrapping")
    public static function stringLocalKeepsSome():Void {
        Test.equals(true, NullableLocalOps.stringLocalMatches(["a", "b"]));
    }

    @:test("a nullable initializer passes through without double wrapping")
    public static function nullableInitUnwrapped():Void {
        Test.equals(true, NullableLocalOps.nullableInitPassesThrough([7, 8]));
    }

    @:test("a createEnum initializer passes through without Some wrapping")
    public static function lookupInitUnwrapped():Void {
        Test.equals(true, NullableLocalOps.lookupLocalPassesThrough(LocalProbe.Alpha));
    }
}
