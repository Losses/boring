package tests;

import std.Test;
import boring.NullableCallOps;
import boring.NullableReceiver;

class NullableCallTests {
    @:test("nullable toString result")
    public static function testNullableToStringResult():Void {
        Test.equals("present", NullableCallOps.nullableToStringResult(new NullableReceiver()));
        #if kotlin_output
        Test.equals(null, NullableCallOps.nullableToStringResult(null));
        #end
    }
}
