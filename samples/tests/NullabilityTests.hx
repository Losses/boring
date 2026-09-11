package tests;

import std.Test;
import boring.NullabilityOps;
import boring.NullableReceiver;

class NullabilityTests {
    @:test("nullable toString in argument")
    public static function testNullableToString():Void {
        Test.equals("present", NullabilityOps.nullableToString(new NullableReceiver()));
        #if kotlin_output
        Test.equals(null, NullabilityOps.nullableToString(null));
        #end
    }
    
    @:test("nullable toString with suffix")
    public static function testNullableToStringWithParam():Void {
        Test.equals("present!", NullabilityOps.nullableToStringWithParam(new NullableReceiver(), "!"));
        #if kotlin_output
        Test.equals(null, NullabilityOps.nullableToStringWithParam(null, "!"));
        #end
    }
}
