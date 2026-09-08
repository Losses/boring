package tests;

import boring.AbstractStaticDefault;
import boring.ProbeUnit;
import std.Test;

class AbstractStaticDefaultTests {
    @:test("omitted optional parameter falls back to the abstract static default")
    public static function testAbstractStaticDefault():Void {
        final d = new AbstractStaticDefault();
        Test.equals(true, d.value == ProbeUnit.ZERO);
    }
}
