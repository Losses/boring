package tests;

import boring.PrivateHolder;
import boring.ValueRecord;
import tests.ValueRecordProbes;
import std.RecordCopy;
import std.RecordEq;
import std.RecordStr;
import std.Test;

class ValueRecordTests {
    @:test("constructor keeps the given fields and validates nothing in range")
    public static function testConstruction():Void {
        final record = new ValueRecord(2, 7, "span");
        Test.equals(2, record.start);
        Test.equals(7, record.end);
        Test.equals("span", record.label);
    }

    @:test("getter-only property computes per read")
    public static function testProperty():Void {
        final record = new ValueRecord(2, 7, "span");
        Test.equals(5, record.length);
    }

    @:test("constructor throws on start after end")
    public static function testStartAfterEnd():Void {
        Test.equals(true, ValueRecordProbes.ctorRejected(8, 3));
    }

    @:test("constructor throws on negative start")
    public static function testNegativeStart():Void {
        Test.equals(true, ValueRecordProbes.ctorRejected(-1, 3));
    }

    @:test("in-range construction is accepted")
    public static function testAccepted():Void {
        Test.equals(false, ValueRecordProbes.ctorRejected(0, 0));
    }

    @:test("copy without override keeps every field")
    public static function testCopyZero():Void {
        final record = new ValueRecord(2, 7, "span");
        final copy = RecordCopy.copy(record);
        Test.equals(2, copy.start);
        Test.equals(7, copy.end);
        Test.equals("span", copy.label);
    }

    @:test("copy with one override replaces the targeted field")
    public static function testCopyOne():Void {
        final record = new ValueRecord(2, 7, "span");
        final copy = RecordCopy.copy(record, end = 9);
        Test.equals(2, copy.start);
        Test.equals(9, copy.end);
        Test.equals("span", copy.label);
    }

    @:test("copy with reordered overrides keeps parameter order")
    public static function testCopyReordered():Void {
        final record = new ValueRecord(2, 7, "span");
        final copy = RecordCopy.copy(record, label = "renamed", start = 4);
        Test.equals(4, copy.start);
        Test.equals(7, copy.end);
        Test.equals("renamed", copy.label);
    }

    @:test("structural equality compares constructor fields")
    public static function testEquality():Void {
        final left = new ValueRecord(2, 7, "span");
        final same = new ValueRecord(2, 7, "span");
        final other = new ValueRecord(2, 8, "span");
        Test.equals(true, RecordEq.eq(left, same));
        Test.equals(false, RecordEq.eq(left, other));
    }

    @:test("printed form names the class and constructor fields")
    public static function testPrintedForm():Void {
        final record = new ValueRecord(2, 7, "span");
        Test.equals("ValueRecord(start=2, end=7, label=span)", RecordStr.str(record));
    }

    @:test("private constructor-parameter field survives construction")
    public static function testPrivateHolder():Void {
        final holder = new PrivateHolder(10, 20);
        Test.equals(10, holder.shown);
        Test.equals(30, holder.total());
    }
}
