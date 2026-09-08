package tests;

import boring.PayloadSelfMapOps.PayloadSelfMapError;
import boring.PayloadSelfMapOps.PayloadSelfMapException;
import std.Test;

class PayloadSelfMapOpsTests {
    @:test("keeps a payload enum and exception declared in one module")
    public static function selfMappedPayload():Void {
        final error = PayloadSelfMapException.make();
        #if rust_output
        Test.equals("payload self-map", error.message);
        #else
        Test.equals(PayloadSelfMapError.Missing, error.error);
        #end
    }
}
