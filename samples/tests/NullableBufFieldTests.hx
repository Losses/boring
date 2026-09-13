package tests;

import boring.NullableBufFieldOps;
import std.Test;

class NullableBufFieldTests {
    @:test("a buffer field mutation opens the nullable owner with as_mut")
    public static function appendGuarded():Void {
        Test.equals("hi", NullableBufFieldOps.appendGuarded(true, "hi"));
        Test.equals("", NullableBufFieldOps.appendGuarded(false, "hi"));
    }

    @:test("a stranded lead in a nullable buffer field faults through the catch")
    public static function caughtFault():Void {
        Test.equals("fault", NullableBufFieldOps.caughtFault(true, 0xD800, "x"));
        Test.equals("", NullableBufFieldOps.caughtFault(false, 0xD800, "x"));
    }
}
