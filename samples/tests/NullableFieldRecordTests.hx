package tests;

import boring.NullableFieldRecord;
import std.Test;

/**
 * The printed form of a record whose nullable fields hold null
 * (docs/specs/features/31-record-tostring-member.md). A null field prints
 * "null" on every target, the same text Std.string produces for null, and
 * the printed member runs without an exception.
 */
class NullableFieldRecordTests {
    @:test("a null Int field prints null")
    public static function nullIntFieldPrintsNull():Void {
        final value = new NullableFieldRecord("alpha", "beta", null, null);
        Test.equals("NullableFieldRecord(name=alpha, code=null, label=beta, words=null)", value.toString());
        Test.ok(value.toString().indexOf("code=null") >= 0, "the null Int field prints null");
    }

    @:test("a null String field prints null")
    public static function nullStringFieldPrintsNull():Void {
        final value = new NullableFieldRecord("alpha", null, 42, null);
        Test.equals("NullableFieldRecord(name=alpha, code=42, label=null, words=null)", value.toString());
        Test.ok(value.toString().indexOf("label=null") >= 0, "the null String field prints null");
    }

    @:test("a present Int field prints its value")
    public static function presentIntFieldPrintsValue():Void {
        final value = new NullableFieldRecord("alpha", null, 42, null);
        Test.equals("NullableFieldRecord(name=alpha, code=42, label=null, words=null)", value.toString());
        Test.ok(value.toString().indexOf("code=42") >= 0, "the present Int field prints 42");
    }

    @:test("a present String field prints its value")
    public static function presentStringFieldPrintsValue():Void {
        final value = new NullableFieldRecord("alpha", "beta", null, null);
        Test.equals("NullableFieldRecord(name=alpha, code=null, label=beta, words=null)", value.toString());
        Test.ok(value.toString().indexOf("label=beta") >= 0, "the present String field prints beta");
    }

    @:test("every nullable field prints its null and present forms")
    public static function bothStatesPrint():Void {
        final absent = new NullableFieldRecord("alpha", null, null, null);
        Test.equals("NullableFieldRecord(name=alpha, code=null, label=null, words=null)", absent.toString());
        final present = new NullableFieldRecord("alpha", "beta", 42, ["one", "two"]);
        Test.equals("NullableFieldRecord(name=alpha, code=42, label=beta, words=[one, two])", present.toString());
    }
}
