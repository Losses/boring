package tests;

import boring.OptionalParamNull;
import std.Test;

class OptionalParamNullTests {
    @:test("omitted Int optional parameter falls back to its null default")
    public static function testIntDefault():Void {
        Test.equals(0, OptionalParamNull.intDefault());
    }

    @:test("omitted class optional parameter falls back to its null default")
    public static function testClassDefault():Void {
        Test.equals("default", OptionalParamNull.classDefault());
    }
}
