package tests;

import std.Test;
import boring.NullableCallOps;
import boring.NullableCallOps2;
import boring.NullableReceiver;

class NullableCallTests {
    @:test("nullable toString result")
    public static function testNullableToStringResult():Void {
        Test.equals("present", NullableCallOps.nullableToStringResult(new NullableReceiver()));
        #if kotlin_output
        Test.equals(null, NullableCallOps.nullableToStringResult(null));
        #end
    }

    @:test("normalized local toString result")
    public static function testNormalizedToStringResult():Void {
        Test.equals("present", NullableCallOps2.normalizedToStringResult(new NullableReceiver()));
        Test.equals("present", NullableCallOps2.normalizedToStringResult(null));
    }

    @:test("guarded local toString result")
    public static function testGuardedToStringResult():Void {
        Test.equals("present", NullableCallOps2.guardedToStringResult(new NullableReceiver()));
    }
}
