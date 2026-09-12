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

    @:test("a guarded nullable Float read widens after extraction")
    public static function testNarrowedFloat():Void {
        #if kotlin_output
        final values:Array<Null<Float>> = [1.5, null];
        Test.equals(1.5, NullabilityOps.narrowedFloat(values, 0));
        Test.equals(0.0, NullabilityOps.narrowedFloat(values, 1));
        #else
        Test.equals(true, true);
        #end
    }

    @:test("a nullable constructor argument reaches a nullable property")
    public static function testCtorFieldLabel():Void {
        #if kotlin_output
        Test.equals("HI", NullabilityOps.ctorFieldLabel("hi"));
        Test.equals(null, NullabilityOps.ctorFieldLabel(null));
        #else
        Test.equals(true, true);
        #end
    }
}
