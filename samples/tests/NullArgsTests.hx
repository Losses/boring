package tests;

import std.Test;
import boring.NullArgsOps;

class NullArgsTests {
    @:test("explicit null materializes a registered default")
    public static function testExplicitNull():Void {
        Test.equals("none", NullArgsOps.explicitNull());
    }

    @:test("nullable arguments use the default only when null")
    public static function testNullableVariable():Void {
        Test.equals("none", NullArgsOps.nullableVariable(null));
        Test.equals("x", NullArgsOps.nullableVariable("x"));
    }
}
