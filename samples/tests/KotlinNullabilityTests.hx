package tests;

import std.Test;

class KotlinNullabilityOps {
    #if kotlin_output
    public static function defaulted(?value:Int = 17):Int {
        return value;
    }

    public static function receiverLabel(value:Null<KotlinNullableReceiver>):Null<String> {
        return value.label();
    }
    #else
    public static function defaulted(value:Int):Int {
        return value;
    }

    public static function receiverLabel(value:KotlinNullableReceiver):String {
        return value.label();
    }
    #end
}

class KotlinNullableReceiver {
    public function new() {}

    public function label():String {
        return "present";
    }
}

class KotlinNullabilityTests {
    @:test("optional parameters emit a native default")
    public static function testOptionalDefault():Void {
        #if kotlin_output
        Test.equals(17, KotlinNullabilityOps.defaulted());
        #end
        Test.equals(23, KotlinNullabilityOps.defaulted(23));
    }

    @:test("nullable receiver calls preserve present values")
    public static function testNullableReceiver():Void {
        Test.equals("present", KotlinNullabilityOps.receiverLabel(new KotlinNullableReceiver()));
        #if kotlin_output
        Test.equals(null, KotlinNullabilityOps.receiverLabel(null));
        #end
    }
}
