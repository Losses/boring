package tests;

import boring.InlineDefaultOps;
import boring.ValueTypeOps.Ic;
import std.Test;

class InlineDefaultTests {
    @:test("inlined data-class defaults preserve static paths and parameter bindings")
    public static function testInlineDefaults():Void {
        final value = new InlineDefaultOps(null);
        Test.equals(Ic.ZERO, value.marker);
        Test.equals(7, value.count);
    }
}
