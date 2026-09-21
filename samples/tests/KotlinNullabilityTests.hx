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

class KotlinNestedNullReturnOps {
    public static function anonymousLookup(key:Int):String {
        final lookup = function(k:Int):Null<String> {
            if (k == 0)
                return null;
            return "hit";
        };
        final value = lookup(key);
        if (value == null)
            return "none";
        return value;
    }

    static function applyLookup(fn:Int->Null<String>, key:Int):String {
        final value = fn(key);
        if (value == null)
            return "none";
        return value;
    }

    public static function appliedLookup(key:Int):String {
        return applyLookup(function(k:Int):Null<String> {
            if (k == 0)
                return null;
            return "hit";
        }, key);
    }

    public static function namedLookup(key:Int):String {
        function lookup(k:Int):Null<String> {
            if (k == 0)
                return null;
            return "hit";
        }
        final value = lookup(key);
        if (value == null)
            return "none";
        return value;
    }
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

    @:test("anonymous lambda keeps a Null return")
    public static function testAnonymousNullableLambda():Void {
        Test.equals("none", KotlinNestedNullReturnOps.anonymousLookup(0));
        Test.equals("hit", KotlinNestedNullReturnOps.anonymousLookup(1));
    }

    @:test("lambda argument keeps a Null return")
    public static function testNullableLambdaArgument():Void {
        Test.equals("none", KotlinNestedNullReturnOps.appliedLookup(0));
        Test.equals("hit", KotlinNestedNullReturnOps.appliedLookup(1));
    }

    @:test("named local function keeps a Null return")
    public static function testNamedNullableLocalFunction():Void {
        Test.equals("none", KotlinNestedNullReturnOps.namedLookup(0));
        Test.equals("hit", KotlinNestedNullReturnOps.namedLookup(1));
    }
}
