package tests;

import boring.StdStringPlainIntOps;
import boring.StdStringPlainIntOps.PlainIntMark;
import std.Test;

class StdStringPlainIntTests {
    @:test("non-cyclic enum Int payload signed rendering")
    public static function intPayload():Void {
        Test.equals("plain", StdStringPlainIntOps.intMarkText(plain));
        Test.equals("leaf(value=-1)", StdStringPlainIntOps.intMarkText(leaf(-1)));
        Test.equals("leaf(value=0)", StdStringPlainIntOps.intMarkText(leaf(0)));
        Test.equals("leaf(value=7)", StdStringPlainIntOps.intMarkText(leaf(7)));
    }
}
