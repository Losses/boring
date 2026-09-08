package tests;

import boring.DataClassCtorGuardOps;
import boring.ValueException;
import std.Test;

class DataClassCtorGuardTests {
    @:test("data-class constructor accepts finite non-negative values")
    public static function acceptsValidValue():Void {
        final value = new DataClassCtorGuardOps(2.5);
        Test.equals(2.5, value.magnitude);
    }

    @:test("data-class constructor rejects negative values")
    public static function rejectsNegativeValue():Void {
        var rejected = false;
        try {
            new DataClassCtorGuardOps(-1.0);
        } catch (_:ValueException) {
            rejected = true;
        }
        Test.equals(true, rejected);
    }

    @:test("data-class constructor rejects non-finite values")
    public static function rejectsNonFiniteValue():Void {
        var rejected = false;
        try {
            new DataClassCtorGuardOps(Math.POSITIVE_INFINITY);
        } catch (_:ValueException) {
            rejected = true;
        }
        Test.equals(true, rejected);
    }
}
