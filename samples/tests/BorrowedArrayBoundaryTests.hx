package tests;

import boring.BorrowedArrayBoundaryOps;
import std.Test;

class BorrowedArrayBoundaryTests {
    @:test("a borrowed array parameter fills an owned nullable constructor slot")
    public static function wrap():Void {
        #if rust_output
        final holder = BorrowedArrayBoundaryOps.wrap([1, 2, 3]);
        Test.equals(true, holder.hasValues());
        #end
    }

    @:test("a borrowed array parameter fills an owned nullable ReadOnlyArray slot")
    public static function readOnlyWrap():Void {
        #if rust_output
        final holder = BorrowedArrayBoundaryOps.readOnlyWrap([1, 2]);
        Test.equals(true, holder.hasValues());
        #end
    }

    @:test("a borrowed array parameter fills an owned nullable return slot")
    public static function nullableReturn():Void {
        #if rust_output
        final values = BorrowedArrayBoundaryOps.nullableReturn([4, 5]);
        Test.equals(true, values != null);
        #end
    }

    @:test("an owned array local clones a borrowed array assignment")
    public static function rebind():Void {
        #if rust_output
        Test.equals(2, BorrowedArrayBoundaryOps.rebind([7, 8]));
        #end
    }

    @:test("a conditional array result clones the borrowed arm")
    public static function choose():Void {
        #if rust_output
        Test.equals(2, BorrowedArrayBoundaryOps.choose([7, 8], true).length);
        Test.equals(0, BorrowedArrayBoundaryOps.choose([7, 8], false).length);
        #end
    }
}
