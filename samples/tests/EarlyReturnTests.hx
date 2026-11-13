package tests;

import std.Test;

/**
 * A runtime identity for the early-return condition. A literal condition lets
 * Swift fold the branch and warn that the assertion after the early return is
 * unreachable; a call keeps the condition a runtime value.
 * (RuntimeEarlyReturnCondition)
 */
class EarlyReturnSupport {
    public static function flag(v:Bool):Bool {
        return v;
    }
}

class EarlyReturnTests {
    @:test("conditional early return exits the test body")
    public static function conditionalReturn():Void {
        final shouldStop = EarlyReturnSupport.flag(true);
        if (shouldStop) {
            return;
        }
        Test.fail("unreachable assertion");
    }

    @:test("fall-through path continues after the conditional")
    public static function fallThrough():Void {
        final shouldStop = EarlyReturnSupport.flag(false);
        if (shouldStop) {
            return;
        }
        Test.ok(true);
    }
}
