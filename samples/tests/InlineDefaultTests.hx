package tests;

import boring.InlineDefaultOps;
import boring.ProbeUnit;
import std.Test;

class InlineDefaultTests {
    @:test("inlined data-class defaults preserve static paths and parameter bindings")
    public static function testInlineDefaults():Void {
        final value = new InlineDefaultOps(7);
        Test.equals(0, value.marker);
        Test.equals(7, value.count);
    }
}
