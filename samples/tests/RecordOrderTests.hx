package tests;

import boring.RecordOrderOps;
import boring.RecordOrderOps.RecordOrderAligned;
import boring.RecordOrderOps.RecordOrderShifted;
import std.RecordCopy;
import std.RecordStr;
import std.Test;

class RecordOrderTests {
    @:test("reordered class prints fields in declaration order")
    public static function shiftedPrintsDeclarationOrder():Void {
        Test.equals("RecordOrderShifted(a=1, b=5, c=x)", RecordOrderOps.shiftedPrinted());
    }

    @:test("reordered class prints the defaulted parameter's fallback value")
    public static function shiftedDefaultedPrintsFallback():Void {
        Test.equals("RecordOrderShifted(a=1, b=0, c=x)", RecordOrderOps.shiftedDefaulted());
    }

    @:test("reordered class prints the same text through RecordStr")
    public static function shiftedMatchesRecordStr():Void {
        final value = new RecordOrderShifted(1, "x", 5);
        Test.equals(value.toString(), RecordStr.str(value));
    }

    @:test("aligned class keeps its printed form")
    public static function alignedPrintsAsBefore():Void {
        Test.equals("RecordOrderAligned(a=1, b=5, c=x)", RecordOrderOps.alignedPrinted());
    }

    @:test("equality accepts equal values of the reordered class")
    public static function equalityAcceptsShiftedValues():Void {
        Test.equals(true, RecordOrderOps.shiftedEqual());
    }

    @:test("copy round-trips the reordered class through constructor parameter order")
    public static function copyRoundTripsShifted():Void {
        final value = new RecordOrderShifted(1, "x", 5);
        final copy = RecordCopy.copy(value, b = 7);
        Test.equals("RecordOrderShifted(a=1, b=7, c=x)", copy.toString());
    }

    @:test("copy round-trips the aligned class")
    public static function copyRoundTripsAligned():Void {
        final value = new RecordOrderAligned(1, 5, "x");
        final copy = RecordCopy.copy(value);
        Test.equals(value.toString(), copy.toString());
    }
}
