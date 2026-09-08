package tests;

import std.Test;

class EarlyReturnTests {
    @:test("conditional early return exits the test body")
    public static function conditionalReturn():Void {
        final shouldStop = true;
        if (shouldStop) {
            return;
        }
        Test.fail("unreachable assertion");
    }

    @:test("fall-through path continues after the conditional")
    public static function fallThrough():Void {
        final shouldStop = false;
        if (shouldStop) {
            return;
        }
        Test.ok(true);
    }
}
