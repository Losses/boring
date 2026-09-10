package tests;

import boring.SwitchCaseScopeOps;
import boring.SwitchCaseScopeOps.ToneKind;
import std.Test;

class SwitchCaseScopeTests {
    @:test("multiple cases declaring the same name resolve without collision")
    public static function testToneRow():Void {
        Test.equals(0, SwitchCaseScopeOps.toneRow(ToneKind.Yinping, 5));
        Test.equals(10, SwitchCaseScopeOps.toneRow(ToneKind.Yangping, 5));
        Test.equals(15, SwitchCaseScopeOps.toneRow(ToneKind.Shang, 5));
        Test.equals(20, SwitchCaseScopeOps.toneRow(ToneKind.Qu, 5));
        Test.equals(0, SwitchCaseScopeOps.toneRow(ToneKind.Neutral, 5));
        Test.equals(25, SwitchCaseScopeOps.toneRow(ToneKind.Ru, 5));
    }

    @:test("cases declaring multiple locals resolve without collision")
    public static function testToneInk():Void {
        Test.equals(0.0, SwitchCaseScopeOps.toneInk(ToneKind.Yinping, 1.0, 2.0));
        Test.equals(3.0, SwitchCaseScopeOps.toneInk(ToneKind.Yangping, 1.0, 2.0));
        Test.equals(6.0, SwitchCaseScopeOps.toneInk(ToneKind.Shang, 1.0, 2.0));
        Test.equals(9.0, SwitchCaseScopeOps.toneInk(ToneKind.Qu, 1.0, 2.0));
        Test.equals(0.0, SwitchCaseScopeOps.toneInk(ToneKind.Neutral, 1.0, 2.0));
        Test.equals(12.0, SwitchCaseScopeOps.toneInk(ToneKind.Ru, 1.0, 2.0));
    }

    @:test("mixed declaring and non-declaring cases coexist")
    public static function testMixed():Void {
        Test.equals(1, SwitchCaseScopeOps.mixed(ToneKind.Yinping, 5));
        Test.equals(2, SwitchCaseScopeOps.mixed(ToneKind.Yangping, 5));
        Test.equals(15, SwitchCaseScopeOps.mixed(ToneKind.Shang, 5));
        Test.equals(25, SwitchCaseScopeOps.mixed(ToneKind.Qu, 5));
        Test.equals(3, SwitchCaseScopeOps.mixed(ToneKind.Neutral, 5));
        Test.equals(35, SwitchCaseScopeOps.mixed(ToneKind.Ru, 5));
    }
}
