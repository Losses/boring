package tests;

import boring.InstanceDefaults;
import std.Test;

class InstanceDefaultsTests {
    @:test("instance field defaults initialize every field")
    public static function defaults():Void {
        final d = new InstanceDefaults();
        Test.equals(0, d.count);
        Test.equals("none", d.label);
        Test.equals(1.0, d.ratio);
        Test.equals(false, d.ready);
        Test.equals(3, d.tool.level);
        Test.equals(7, d.plain);
    }

    @:test("instance field defaults evaluate per instance")
    public static function perInstance():Void {
        final a = new InstanceDefaults();
        final b = new InstanceDefaults();
        a.tool.level = 9;
        Test.equals(3, b.tool.level);
    }
}
