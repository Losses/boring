package tests;

import boring.VecSpliceOps;
import std.Test;

class VecSpliceTests {
    @:test("vecSpliceDrain: remove a single element from the middle")
    public static function removeSingle():Void {
        #if rust_output
        final result = VecSpliceOps.removeSingle();
        Test.equals(2, result.length);
        Test.equals(1, result[0]);
        Test.equals(3, result[1]);
        #end
    }

    @:test("vecSpliceDrain: capture the removed sub-array")
    public static function captureRemoved():Void {
        #if rust_output
        final removed = VecSpliceOps.captureRemoved();
        Test.equals(1, removed.length);
        Test.equals(30, removed[0]);
        #end
    }

    @:test("vecSpliceDrain: remove the first n elements")
    public static function removeHead():Void {
        #if rust_output
        final result = VecSpliceOps.removeHead(3);
        Test.equals(2, result.length);
        Test.equals(4, result[0]);
        Test.equals(5, result[1]);
        #end
    }
}