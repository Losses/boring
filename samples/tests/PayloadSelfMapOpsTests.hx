package tests;

import boring.PayloadSelfMapOps.PayloadSelfMapException;
import std.Test;

class PayloadSelfMapOpsTests {
    @:test("keeps a payload enum and exception declared in one module")
    public static function selfMappedPayload():Void {
        final error = PayloadSelfMapException.make();
        Test.equals("payload self-map", error.message);
    }
}
