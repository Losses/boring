package tests;

import boring.SwitchMergeOps;
import boring.SwitchMergeOps.SwitchMergeValue;
import std.Test;

class SwitchMergeTests {
    @:test("grouped variant arms preserve both constructors")
    public static function grouped():Void {
        Test.equals("grouped:3", SwitchMergeOps.grouped(SwitchMergeValue.First(3)));
        Test.equals("grouped:4", SwitchMergeOps.grouped(SwitchMergeValue.Second(4)));
        Test.equals("third", SwitchMergeOps.grouped(SwitchMergeValue.Third));
    }

    @:test("single variant arms remain distinct")
    public static function single():Void {
        Test.equals("first:1", SwitchMergeOps.single(SwitchMergeValue.First(1)));
        Test.equals("second:2", SwitchMergeOps.single(SwitchMergeValue.Second(2)));
    }

    @:test("grouped plain arms match without payload bindings")
    public static function groupedPlainMatches():Void {
        Test.equals("plain", SwitchMergeOps.groupedPlain(SwitchMergeValue.First(1)));
        Test.equals("plain", SwitchMergeOps.groupedPlain(SwitchMergeValue.Second(2)));
        Test.equals("third", SwitchMergeOps.groupedPlain(SwitchMergeValue.Third));
    }
}
