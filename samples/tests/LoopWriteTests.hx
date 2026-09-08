package tests;

import boring.LoopWriteOps;
import std.Test;

class LoopWriteTests {
    @:test("tail counter increment remains a counted loop")
    public static function tailIncrement():Void {
        Test.equals(15, LoopWriteOps.tailIncrement(6));
    }

    @:test("branch counter write remains a while loop")
    public static function branchIncrement():Void {
        Test.equals(12, LoopWriteOps.branchIncrement(6));
    }

    @:test("non-unit counter increment remains a while loop")
    public static function nonUnitIncrement():Void {
        Test.equals(9, LoopWriteOps.nonUnitIncrement(7));
    }

    @:test("closure counter write remains a while loop")
    public static function closureIncrement():Void {
        Test.equals(9, LoopWriteOps.closureIncrement(6));
    }
}
