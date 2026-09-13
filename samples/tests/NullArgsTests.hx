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

    @:test("null-guard conditional argument wraps in the Option slot")
    public static function testConditionalArg():Void {
        Test.equals("none", NullArgsOps.conditionalArg(null));
        Test.equals("x", NullArgsOps.conditionalArg("x"));
    }

    @:test("null default keeps the nullable parameter in the Option domain")
    public static function testNullDefault():Void {
        Test.equals("null", NullArgsOps.nullDefaultAbsent());
        Test.equals("set", NullArgsOps.nullDefaultPresent());
    }
}
