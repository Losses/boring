package tests;

import boring.NullBoolStyle;
import boring.NullBoolTernaryOps;
import std.Test;

class NullBoolTernaryTests {
    @:test("a narrowed Null<Bool> local drives a ternary in the guarded branch")
    public static function ternaryOnNarrowedNullBool():Void {
        Test.equals("true", NullBoolTernaryOps.flagText(new NullBoolStyle(true)));
        Test.equals("false", NullBoolTernaryOps.flagText(new NullBoolStyle(false)));
        Test.equals("absent", NullBoolTernaryOps.flagText(new NullBoolStyle(null)));
        Test.equals(1, NullBoolTernaryOps.flagBit(new NullBoolStyle(true)));
        Test.equals(0, NullBoolTernaryOps.flagBit(new NullBoolStyle(false)));
        Test.equals(-1, NullBoolTernaryOps.flagBit(new NullBoolStyle(null)));
    }
}
