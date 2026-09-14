package tests;

import boring.BorrowedReceiverBoundaryOps;
import std.Test;

class BorrowedReceiverBoundaryTests {
    @:test("a borrowed receiver fills an owned constructor slot")
    public static function snapshotLabel():Void {
        #if rust_output
        Test.equals("root", BorrowedReceiverBoundaryOps.snapshotLabel());
        #end
    }

    @:test("a borrowed receiver fills an owned conditional return slot")
    public static function pickLabel():Void {
        #if rust_output
        Test.equals("root", BorrowedReceiverBoundaryOps.pickLabel(true));
        Test.equals("other", BorrowedReceiverBoundaryOps.pickLabel(false));
        #end
    }
}
