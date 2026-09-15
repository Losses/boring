package tests;

import boring.BorrowedLoopItemBoundaryOps;
#if rust_output
import boring.BorrowedLoopItemBoundaryOps.BorrowedLoopItemEntry;
import boring.BorrowedLoopItemBoundaryOps.BorrowedLoopMarker;
#end
import std.Test;

class BorrowedLoopItemBoundaryTests {
    @:test("a borrowed loop item fills an owned Option return slot")
    public static function firstEntry():Void {
        #if rust_output
        final entries = [Entry("a"), Entry("b")];
        final first = BorrowedLoopItemBoundaryOps.firstEntry(entries);
        Test.equals(true, first != null);
        Test.equals("a", first == null ? "" : BorrowedLoopItemBoundaryOps.describe(first));
        #end
    }

    @:test("a borrowed loop item fills an owned constructor slot")
    public static function wrappedEntries():Void {
        #if rust_output
        final entries = [Entry("a"), Entry("b")];
        final holders = BorrowedLoopItemBoundaryOps.wrappedEntries(entries);
        Test.equals(2, holders.length);
        Test.equals("a", BorrowedLoopItemBoundaryOps.describe(holders[0].entry));
        Test.equals("b", BorrowedLoopItemBoundaryOps.describe(holders[1].entry));
        #end
    }

    @:test("a borrowed loop item fills an owned call argument")
    public static function describedLabels():Void {
        #if rust_output
        final entries = [Entry("a"), Entry("b")];
        final labels = BorrowedLoopItemBoundaryOps.describedLabels(entries);
        Test.equals(2, labels.length);
        Test.equals("a", labels[0]);
        Test.equals("b", labels[1]);
        #end
    }

    @:test("a borrowed loop item fills an owned object field")
    public static function records():Void {
        #if rust_output
        final entries = [Entry("a"), Entry("b")];
        final records = BorrowedLoopItemBoundaryOps.records(entries);
        Test.equals(2, records.length);
        Test.equals("a", BorrowedLoopItemBoundaryOps.describe(records[0].entry));
        Test.equals("b", BorrowedLoopItemBoundaryOps.describe(records[1].entry));
        #end
    }

    @:test("a borrowed enum loop item compares against an owned value")
    public static function hasMarker():Void {
        #if rust_output
        final markers = [MarkerAlpha, MarkerBeta];
        Test.equals(true, BorrowedLoopItemBoundaryOps.hasMarker(markers, MarkerBeta));
        Test.equals(false, BorrowedLoopItemBoundaryOps.hasMarker([MarkerAlpha], MarkerBeta));
        #end
    }

    @:test("a nullable array indexOf unwraps the receiver")
    public static function indexOfNullable():Void {
        #if rust_output
        Test.equals(1, BorrowedLoopItemBoundaryOps.indexOfNullableInts([5, 7, 9], 7));
        Test.equals(-1, BorrowedLoopItemBoundaryOps.indexOfNullableInts([5, 7, 9], 3));
        Test.equals(-1, BorrowedLoopItemBoundaryOps.indexOfNullableInts(null, 3));
        Test.equals(1, BorrowedLoopItemBoundaryOps.indexOfNullableStrings(["a", "b"], "b"));
        #end
    }
}
